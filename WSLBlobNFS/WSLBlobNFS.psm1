# --------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
# --------------------------------------------------------------------------------------------

# Set the execution policy to appropriate value to run the script
# Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser

# Throw an error if any cmdlet, function, or command fails or a variable is unknown and stop the script execution.
Set-PSDebug -Strict
Set-StrictMode -version Latest
$ErrorActionPreference = 'Stop'

# To-do:
# - Add support for cleanup and mountmappings
# - Add tests for the module using Pester
# - Sign the module
# - Automate to start this script and run Initialize on startup. But initialize should be run only once depending on
#   the version of the script.
# - Use various output streams to log different messages and enable or disable them accordingly while running the script.
#   https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_output_streams?view=powershell-5.1
# - Help content for each function

function Install-WSLBlobNFS
{
    # Check if wsl is installed or not.
    $wslstatus = wsl -l -v
    if($LASTEXITCODE -eq 1)
    {
        Write-Host "WSL is not installed. Installing WSL..."

        wsl --install -d Ubuntu-22.04
        # To-do: Check if the distro is installed successfully or not.

        # To-do: Prompt user to restart the machine to complete WSL installation.
        Write-Host "Restart the VM to complete WSL installation, and then Run the script again with Initialize-WSLBlobNFS to continue the WSL setup."
        return
    }

    # To-do: Prompt user to Initialize-WSLBlobNFS if WSL is already installed.
    Write-Host "WSL is already installed. Skipping WSL installation. Run Initialize-WSLBlobNFS to setup WSL environment "
               "for WSLBlobNFS usage."
}

function Initialize-WSLBlobNFS
{
    # To-do: Show progress of the script execution.

    # Most of the commands require admin privileges. Hence, we need to run the script as admin.
    $linuxusername = "root"

    # Check if wsl is installed or not.
    $wslstatus = wsl -l -v
    if($LASTEXITCODE -eq 1)
    {
        Write-Host "WSL is not installed. Installing WSL..."

        wsl --install -d Ubuntu-22.04
        Write-Host "Restart the VM to complete WSL installation, and then Run the script again with Initialize-WSLBlobNFS to continue the WSL setup."
        return
    }

    Write-Host "Setting up the WSL environment for your WSLBlobNFS usage."

    # # Add the modulePath, which hold the path of module, to WSLENV to help in copying linux scripts to wsl distro.
    # [Environment]::SetEnvironmentVariable("modulePath", $PSScriptRoot)
    # $p = [Environment]::GetEnvironmentVariable("WSLENV")
    # $p += ":modulePath/p"
    # [Environment]::SetEnvironmentVariable("WSLENV",$p)

    # Powershell 3+ is require for $PSScriptRoot
    $modulePath = ("/mnt/" + ($PSScriptRoot.Replace("\", "/").Replace(":", ""))).ToLower()

    # To-do: Copy only if the file is not present or if the file is modified.
    # To-do: Check if the files are present or not.
    $linuxScriptsPath = "/root/scripts"
    $wslScriptName = "wsl2_linux_script.sh"
    $queryScriptName = "query_quota.sh"

    # To-do: Handle errors for each of the following commands.
    wsl -d Ubuntu-22.04 -u root -e bash -c "mkdir -p $linuxScriptsPath"

    # Quote the path with '' to preserve space
    Write-Host "Copying necessary linux files from $modulePath"

    wsl -d Ubuntu-22.04 -u root -e bash -c "cp '$modulePath/$wslScriptName' $linuxScriptsPath/$wslScriptName"

    # Files saved from windows will have \r\n line endings. Hence, we need to remove \r.
    wsl -d Ubuntu-22.04 -u root -e bash -c "sed -i -e 's/\r$//' $linuxScriptsPath/$wslScriptName"

    wsl -d Ubuntu-22.04 -u root -e bash -c "chmod +x $linuxScriptsPath/$wslScriptName"

    wsl -d Ubuntu-22.04 -u root -e bash -c "cp '$modulePath/$queryScriptName' $linuxScriptsPath/$queryScriptName"

    # Files saved from windows will have \r\n line endings. Hence, we need to remove \r.
    wsl -d Ubuntu-22.04 -u root -e bash -c "sed -i -e 's/\r$//' $linuxScriptsPath/$queryScriptName"

    wsl -d Ubuntu-22.04 -u root -e bash -c "chmod +x $linuxScriptsPath/$queryScriptName"

    # Install systemd, restart wsl and install nfs and samba
    # To-do: Check if systemd is already installed or not.
    wsl -d Ubuntu-22.04 -u root $linuxScriptsPath/$wslScriptName installsystemd
    Write-Host "Installed systemd."

    # Shutdown wsl and it will restart with systemd on next wsl command execution
    wsl -d Ubuntu-22.04 --shutdown

    # wsl shutsdown after 8 secs of inactivity. Hence, we need to run dbus-launch to keep it running.
    # Check the issue here:
    # https://github.com/microsoft/WSL/issues/10138
    # To-do: Check if dbus is already running or not.
    # dbus[488]: Unable to set up transient service directory: XDG_RUNTIME_DIR "/run/user/0/" is owned by uid 1000, not our uid 0
    wsl -d Ubuntu-22.04 -u root --exec dbus-launch true

    # To-do: Check exit code of the following command.
    wsl -d Ubuntu-22.04 -u root $linuxScriptsPath/$wslScriptName installnfssmb $linuxusername
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

    # Most of the commands require admin privileges. Hence, we need to run the script as admin.
    $linuxusername = "root"

    # Check if wsl is installed or not.
    $wslstatus = wsl -l -v
    if($LASTEXITCODE -eq 1)
    {
        Write-Host "WSL is not installed. Installing WSL..."

        wsl --install -d Ubuntu-22.04
        Write-Host "Restart the VM to complete WSL installation, and then Run the script again with Initialize-WSLBlobNFS to continue the WSL setup."
        return
    }

    # To-do:
    # - Validate the mountcommand and mountdrive even further.
    # - Check if the mountdrive is already mounted or not.
    # - Check if the mountcommand is already mounted or not.
    # - Check the exit code of net use command.
    $smbexportname = $mountcommand.Split(" ")[-1].Replace("/", "").Trim(" ")
    $password = $linuxusername

    # To-do: Copy only if the file is not present or if the file is modified.
    # To-do: Check if the files are present or not.
    $linuxScriptsPath = "/root/scripts"
    $wslScriptName = "wsl2_linux_script.sh"

    Write-Host "Mounting $mountcommand."
    wsl -d Ubuntu-22.04 -u root $linuxScriptsPath/$wslScriptName "mountshare" "$mountcommand" "$smbexportname"
    $ipaddress = wsl -d Ubuntu-22.04 -u root hostname -I
    $ipaddress = $ipaddress.Trim()
    Write-Host "Mounting smb share \\$ipaddress\$smbexportname onto windows mount point $mountdrive"

    net use $mountdrive "\\$ipaddress\$smbexportname" /persistent:yes /user:$linuxusername $password
    Write-Host "Mounting smb share done."
}

function Dismount-WSLBlobNFS
{
    param(
        # Mountdrive is mandatory arguments for unmountshare
        [string]$mountdrive
    )
    # mountdrive is mandatory arguments for unmountshare
    if([string]::IsNullOrWhiteSpace($mountdrive))
    {
        Write-Host "Mounted drive is not provided."
        return
    }

    # Check if wsl is installed or not.
    $wslstatus = wsl -l -v
    if($LASTEXITCODE -eq 1)
    {
        Write-Host "WSL is not installed. Installing WSL..."

        wsl --install -d Ubuntu-22.04
        Write-Host "Restart the VM to complete WSL installation, and then Run the script again with Initialize-WSLBlobNFS to continue the WSL setup."
        return
    }

    $smbmapping = Get-SmbMapping -LocalPath "$mountdrive"

    # To-do: Ask user if they want to unmount previously mounted share in wsl?
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

    # To-do: Copy only if the file is not present or if the file is modified.
    # To-do: Check if the files are present or not.
    $linuxScriptsPath = "/root/scripts"
    $wslScriptName = "wsl2_linux_script.sh"

    # To-do: If unmount fails then, don't remove the smb mapping.
    wsl -d Ubuntu-22.04 -u root $linuxScriptsPath/$wslScriptName "unmountshare" "$smbexportname"

    net use $mountdrive /delete
    Write-Host "Unmounting smb share done."
}

Export-ModuleMember -Function Install-WSLBlobNFS, Initialize-WSLBlobNFS, Mount-WSLBlobNFS, Dismount-WSLBlobNFS
