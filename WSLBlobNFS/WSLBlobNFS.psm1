# Set the execution policy to appropriate value to run the script
# Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser

# To-do:
# 1. Add support for cleanup and mountmappings
# 2. Add tests for the module using Pester

function Install-WSLBlobNFS
{
    # Check if wsl is installed or not. Fail if wsl is not installed.
    $wslstatus = wsl -l -v
    if($LASTreturnCODE -eq 1)
    {
        Write-Host "WSL is not installed. Installing WSL..."

        wsl --install -d Ubuntu-22.04
        Write-Host "Restart the VM to complete WSL installation, and then Run the script again with setupwslenv action to continue the WSL setup."
        return
    }
    Write-Host "WSL is already installed. Skipping WSL installation."
    return
}

function Initialize-WSLBlobNFS
{
    # Most of the commands require admin privileges. Hence, we need to run the script as admin.
    $linuxusername = "root"

    # Check if wsl is installed or not. Fail if wsl is not installed.
    $wslstatus = wsl -l -v
    if($LASTreturnCODE -eq 1)
    {
        Write-Host "wsl is not installed. Please run the script with installwsl action to install wsl first."
        return
    }

    # Run the script with setupwslenv argument
    # To-do: Automate to start this on startup.

    Write-Host "Installing Ubuntu-22.04..."
    wsl --install -d Ubuntu-22.04

    # ask user if the username was setup
    $usernameSetup = Read-Host "Was the wsl distro username setup? (y/n)"
    if($usernameSetup -ne "y")
    {
        Write-Host "Restart the VM to complete wsl installation, and then run the script again with setupwslenv action to continue the wsl setup."
        return
    }

    Write-Host "Setting up the WSL environment for your WSLBlobNFS usage."

    # wsl shutsdown after 8 secs of inactivity. Hence, we need to run dbus-launch to keep it running.
    # Check the issue here:
    # https://github.com/microsoft/WSL/issues/10138

    # To-do: Copy only if the file is not present or if the file is modified.
    # Files saved from windows will have \r\n line endings. Hence, we need to remove \r.
    wsl -d Ubuntu-22.04 -u root -e bash -c "mkdir -p /root/scripts"

    # Add the blobNFSPath, which hold the path of module, to WSLENV to help in copying wsl2_linux_script.sh to wsl distro.
    # [Environment]::SetEnvironmentVariable("blobNFSPath", $PSScriptRoot)
    # $p = [Environment]::GetEnvironmentVariable("WSLENV")
    # $p += ":blobNFSPath/p"
    # [Environment]::SetEnvironmentVariable("WSLENV",$p)

    # Powershell 3+ is require for $PSScriptRoot
    $blobNFSPath = ("/mnt/" + ($PSScriptRoot.Replace("\", "/").Replace(":", ""))).ToLower()

    wsl -d Ubuntu-22.04 -u root -e bash -c "cp $blobNFSPath/wsl2_linux_script.sh /root/scripts/wsl2_linux_script.sh"
    wsl -d Ubuntu-22.04 -u root -e bash -c "sed -i -e 's/\r$//' /root/scripts/wsl2_linux_script.sh"
    wsl -d Ubuntu-22.04 -u root -e bash -c "chmod +x /root/scripts/wsl2_linux_script.sh"

    wsl -d Ubuntu-22.04 -u root -e bash -c "cp $blobNFSPath/query_quota.sh /root/scripts/query_quota.sh"
    wsl -d Ubuntu-22.04 -u root -e bash -c "sed -i -e 's/\r$//' /root/scripts/query_quota.sh"
    wsl -d Ubuntu-22.04 -u root -e bash -c "chmod +x /root/scripts/query_quota.sh"

    # Install systemd, restart wsl and install nfs and samba
    wsl -d Ubuntu-22.04 -u root /root/scripts/wsl2_linux_script.sh installsystemd
    Write-Host "Installed systemd."

    # Shutdown wsl and it will restart with systemd on next wsl command execution
    wsl -d Ubuntu-22.04 --shutdown

    # wsl shutsdown after 8 secs of inactivity. Hence, we need to run dbus-launch to keep it running.
    # To-do: Check if dbus is already running or not.
    # dbus[488]: Unable to set up transient service directory: XDG_RUNTIME_DIR "/run/user/0/" is owned by uid 1000, not our uid 0
    wsl -d Ubuntu-22.04 -u root --exec dbus-launch true

    wsl -d Ubuntu-22.04 -u root /root/scripts/wsl2_linux_script.sh installnfssmb $linuxusername
    Write-Host "Installed nfs & smb."
    return
    
}

function Mount-WSLBlobNFS
{
    param(
        # To-do: Add support for cleanup and mountmappings
        [string]$mountcommand,
        [string]$mountdrive
    )

    # Most of the commands require admin privileges. Hence, we need to run the script as admin.
    $linuxusername = "root"

    # Check if wsl is installed or not. Fail if wsl is not installed.
    $wslstatus = wsl -l -v
    if($LASTreturnCODE -eq 1)
    {
        Write-Host "wsl is not installed. Please run the script with installwsl action to install wsl first."
        return
    }
    # mountcommand and mountdrive are mandatory arguments for mountshare
    if([string]::IsNullOrWhiteSpace($mountcommand))
    {
        Write-Host "Mount command is not provided."
        return
    }
    if([string]::IsNullOrWhiteSpace($mountdrive))
    {
        Write-Host "Mount drive is not provided."
        return
    }

    $smbexportname = $mountcommand.Split(" ")[-1].Replace("/", "").Trim(" ")
    $password = $linuxusername

    Write-Host "Mounting $mountcommand."
    wsl -d Ubuntu-22.04 -u root /root/scripts/wsl2_linux_script.sh "mountshare" "$mountcommand" "$smbexportname"
    $ipaddress = wsl -d Ubuntu-22.04 -u root hostname -I
    $ipaddress = $ipaddress.Trim()
    Write-Host "Mounting smb share \\$ipaddress\$smbexportname onto windows mount point $mountdrive"

    net use $mountdrive "\\$ipaddress\$smbexportname" /persistent:yes /user:$linuxusername $password
    Write-Host "Mounting smb share done."
}

function Dismount-WSLBlobNFS
{
    param(
        [string]$mountdrive
    )
    # mountdrive is mandatory arguments for unmountshare
    if([string]::IsNullOrWhiteSpace($mountdrive))
    {
        Write-Host "Mounted drive is not provided."
        return
    }

    $smbmapping = Get-SmbMapping -LocalPath "$mountdrive"
    if($smbmapping -eq $null)
    {
        Write-Host "No smb share is mounted on $mountdrive."
        return
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
        return
    }

    # To-do: If unmount fails then, don't remove the smb mapping.
    wsl -d Ubuntu-22.04 -u root /root/scripts/wsl2_linux_script.sh "unmountshare" "$smbexportname"

    net use $mountdrive /delete
    Write-Host "Unmounting smb share done."
}

Export-ModuleMember -Function Install-WSLBlobNFS, Initialize-WSLBlobNFS, Mount-WSLBlobNFS, Dismount-WSLBlobNFS
