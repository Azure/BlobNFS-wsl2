# Set the execution policy to appropriate value to run the script
# Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser

param(
    # The first argument is the action to be performed
    # To-do: Add support for cleanup and mountmappings
    [Parameter(Mandatory)]
    [ValidateSet("installwsl", "setupwslenv", "mountshare", "unmountshare")]
    [string]$action,
    [string]$mountcommand,
    [string]$mountdrive
)

Write-Host "Performing $action."

# Most of the commands require admin privileges. Hence, we need to run the script as admin.
$linuxusername = "root"

# Install wsl
if($action -eq "installwsl")
{
    # Check if wsl is installed or not. Fail if wsl is not installed.
    $wslstatus = wsl -l -v
    if($LASTEXITCODE -eq -1)
    {
        Write-Host "wsl is not installed. Installing wsl..."

        # Installing just wsl is necessary.
        # wsl --install Ubuntu-22.04 will fail if wsl is not installed.
        wsl --install
        Write-Host "Restart the VM to complete wsl installation, and then Run the script again with setupwslenv action to continue the wsl setup."
        exit
    }
    exit
}
else
{
    # Check if wsl is installed or not. Fail if wsl is not installed.
    $wslstatus = wsl -l -v
    if($LASTEXITCODE -eq -1)
    {
        Write-Host "wsl is not installed. Please run the script with installwsl action to install wsl first."
        exit
    }
    # Check if Ubuntu-22.04 is installed or not.
    # else
    # {
    #     $ubuntustatus = $wslstatus | Select-String -Pattern "Ubuntu-22.04"

    #     # To-do: Check the wsl status
    #     if($true)
    #     {
    #         Write-Host "Ubuntu-22.04 is not installed. Installing Ubuntu-22.04..."
    #         wsl --install Ubuntu-22.04
    #     }

    #     # ask user if the username was setup
    #     $usernameSetup = Read-Host "Was the wsl distro username setup? (y/n)"
    #     if($usernameSetup -ne "y")
    #     {
    #         Write-Host "Restart the VM to complete wsl installation, and then Run the script again with setupwslenv action to continue the wsl setup."
    #         exit
    #     }
    # }

    # wsl shutsdown after 8 secs of inactivity. Hence, we need to run dbus-launch to keep it running.
    # Check the issue here:
    # https://github.com/microsoft/WSL/issues/10138

    # To-do: Check if dbus is already running or not.
    # dbus[488]: Unable to set up transient service directory: XDG_RUNTIME_DIR "/run/user/0/" is owned by uid 1000, not our uid 0
    wsl -d Ubuntu-22.04 -u root --exec dbus-launch true

    # To-do: Copy only if the file is not present or if the file is modified.
    # Files saved from windows will have \r\n line endings. Hence, we need to remove \r.
    wsl -d Ubuntu-22.04 -u root -e bash -c "mkdir -p /root/scripts; cp wsl2-linux-script.sh /root/scripts/wsl2-linux-script.sh; sed -i -e 's/\r$//' /root/scripts/wsl2-linux-script.sh; chmod +x /root/scripts/wsl2-linux-script.sh"

    # Run the script with setupwslenv argument
    # To-do: Automate to start this on startup.
    if( $action -eq "setupwslenv" )
    {
        Write-Host "Ubuntu-22.04 is not installed. Installing Ubuntu-22.04..."
        wsl --install Ubuntu-22.04

        # ask user if the username was setup
        $usernameSetup = Read-Host "Was the wsl distro username setup? (y/n)"
        if($usernameSetup -ne "y")
        {
            Write-Host "Restart the VM to complete wsl installation, and then Run the script again with setupwslenv action to continue the wsl setup."
            exit
        }

        Write-Host "Setting up the WSL environment for your BlobNFS usage."

        # Install systemd, restart wsl and install nfs and samba
        wsl -d Ubuntu-22.04 -u root /root/scripts/wsl2-linux-script.sh installsystemd
        Write-Host "Installed systemd."

        # Shutdown wsl and it will restart with systemd on next wsl command execution
        wsl -d Ubuntu-22.04 --shutdown

        # wsl shutsdown after 8 secs of inactivity. Hence, we need to run dbus-launch to keep it running.
        wsl -d Ubuntu-22.04 -u root --exec dbus-launch true

        wsl -d Ubuntu-22.04 -u root /root/scripts/wsl2-linux-script.sh installnfssmb $linuxusername
        Write-Host "Installed nfs & smb."
    }

    elseif( $action -eq "mountshare" )
    {
        # mountcommand, linuxusername and mountdrive are mandatory arguments for mountshare
        if([string]::IsNullOrWhiteSpace($mountcommand))
        {
            Write-Host "Mount command is not provided."
            exit
        }
        if([string]::IsNullOrWhiteSpace($mountdrive))
        {
            Write-Host "Mount drive is not provided."
            exit
        }

        $smbexportname = $mountcommand.Split(" ")[-1].Replace("/", "").Trim(" ")
        $password = $linuxusername

        Write-Host "Mounting $mountcommand."
        wsl -d Ubuntu-22.04 -u root /root/scripts/wsl2-linux-script.sh "mountshare" "$mountcommand" "$smbexportname"
        $ipaddress = wsl -d Ubuntu-22.04 -u root hostname -I
        $ipaddress = $ipaddress.Trim()
        Write-Host "Mounting smb share \\$ipaddress\$smbexportname onto windows mount point $mountdrive"

        New-SmbMapping -LocalPath "$mountdrive" -RemotePath "\\$ipaddress\$smbexportname" -UserName "$linuxusername" -Password "$password"
        Write-Host "Mounting smb share done."
    }

    elseif( $action -eq "unmountshare" )
    {
        # mountdrive is mandatory arguments for unmountshare
        if([string]::IsNullOrWhiteSpace($mountdrive))
        {
            Write-Host "Mounted drive is not provided."
            exit
        }

        $smbmapping = Get-SmbMapping -LocalPath "$mountdrive"
        if($smbmapping -eq $null)
        {
            Write-Host "No smb share is mounted on $mountdrive."
            exit
        }

        # Sample remote path: \\172.17.47.111\mntnfsv3share
        $remotePathTokens = $smbmapping.RemotePath.Split("\")
        $smbexportname = $remotePathTokens[-1].Trim(" ")
        $smbremotehost = $remotePathTokens[2].Trim(" ")

        # check if the remote host is the current wsl ip address
        $ipaddress = wsl -d Ubuntu-22.04 -u root hostname -I
        $ipaddress = $ipaddress.Trim()
        if($smbremotehost -ne $ipaddress)
        {
            Write-Host "The smb share is not mounted from the current wsl ip address."
            exit
        }

        # To-do: If unmount fails then, don't remove the smb mapping.
        wsl -d Ubuntu-22.04 -u root /root/scripts/wsl2-linux-script.sh "unmountshare" "$smbexportname"

        Remove-SmbMapping -LocalPath "$mountdrive"
        Write-Host "Unmounting smb share done."
    }
}