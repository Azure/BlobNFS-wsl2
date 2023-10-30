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
    # [string]$linuxusername
)

Write-Host "Performing $action."

# Install wsl
if($action -eq "installwsl")
{
    # Temp
    wsl --unregister Ubuntu-22.04

    Write-Host "Installing wsl. Please exit the bash with 'exit' command after installation is complete to continue the setup on windows."

    wsl --install Ubuntu-22.04

    # Install wsl without launching it and then create a system user
    # wsl --install Ubuntu-22.04 --no-launch
    # # create a system user with home directory
    # wsl -d Ubuntu-22.04 -u root useradd -m -r $linuxusername
    # # set the password for the user
    # Write-Host "Enter password for $linuxusername"
    # wsl -d Ubuntu-22.04 -u root passwd $linuxusername
    # # add the user to sudo group
    # wsl -d Ubuntu-22.04 -u root usermod -aG sudo $linuxusername

    # ask user if the username was setup
    $usernameSetup = Read-Host "Was the wsl distro username setup? (y/n)"
    if($usernameSetup -eq "y")
    {
        Write-Host "Run the script again with setupwslenv action to continue the wsl setup."
    }
    else
    {
        Write-Host "Restart the VM to complete wsl installation, and then Run the script again with setupwslenv action to continue the wsl setup."
    }
    exit
}
else
{

# Files saved from windows will have \r\n line endings. Hence, we need to remove \r.
wsl -d Ubuntu-22.04 -u root -e bash -c "mkdir -p /root/scripts; cp wsl2-linux-script.sh /root/scripts/wsl2-linux-script.sh; sed -i -e 's/\r$//' /root/scripts/wsl2-linux-script.sh; chmod +x /root/scripts/wsl2-linux-script.sh"

# Run the script with setupwslenv argument
# To-do: Automate to start this on startup.
if( $action -eq "setupwslenv" )
{
    # # linuxusername is mandatory arguments for onetimesetup
    # if([string]::IsNullOrWhiteSpace($linuxusername))
    # {
    #     Write-Host "Linux system username (linuxusername) is not provided."
    #     exit
    # }

    # temp
    $linuxusername = "root"

    # This will not work if wsl was exited with exit command. Hence, we need to check if wsl is running or not, then run the script.

    # Check if wsl is installed or not. Fail if wsl is not installed.
    # $wslstatus = wsl -l -v
    # if($wslstatus -notlike "*Ubuntu-22.04*")
    # {
    #     Write-Host "wsl Ubuntu-22.04 is not installed."
    #     exit
    # }

    Write-Host "Setting up the WSL environment for your BlobNFS usage."

    # Files saved from windows will have \r\n line endings. Hence, we need to remove \r.
    wsl -d Ubuntu-22.04 -u root -e bash -c "mkdir -p /root/scripts; cp wsl2-linux-script.sh /root/scripts/wsl2-linux-script.sh; sed -i -e 's/\r$//' /root/scripts/wsl2-linux-script.sh; chmod +x /root/scripts/wsl2-linux-script.sh"

    # wsl --setdefault Ubuntu-22.04

    # Install systemd, restart wsl and install nfs and samba
    wsl -d Ubuntu-22.04 -u root /root/scripts/wsl2-linux-script.sh installsystemd
    Write-Host "Installed systemd."

    # Shutdown wsl and it will restart with systemd on next wsl command execution
    wsl -d Ubuntu-22.04 --shutdown

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
    # if([string]::IsNullOrWhiteSpace($linuxusername))
    # {
    #     Write-Host "Linux username is not provided."
    #     exit
    # }
    if([string]::IsNullOrWhiteSpace($mountdrive))
    {
        Write-Host "Mount drive is not provided."
        exit
    }

    # temp
    $linuxusername = "root"

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

    wsl -d Ubuntu-22.04 -u root /root/scripts/wsl2-linux-script.sh "unmountshare" "$smbexportname"

    Remove-SmbMapping -LocalPath "$mountdrive"
    Write-Host "Unmounting smb share done."
}
}