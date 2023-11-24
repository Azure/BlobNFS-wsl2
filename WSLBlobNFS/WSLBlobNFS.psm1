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

# WSL distro name and user name
$distroName = "Ubuntu-22.04"
# Most of the commands require admin privileges. Hence, we need to run the script as admin.
$userName = "root"

# Username and password for SMB share.
$smbUserName = "root"

$moduleName = "WSLBlobNFS"

$modulePathForWin = $PSScriptRoot
$modulePathForLinux = ("/mnt/" + ($modulePathForWin.Replace("\", "/").Replace(":", ""))).ToLower()

# To-do: Check if the files are present or not.
$wslScriptName = "wsl2_linux_script.sh"
$queryScriptName = "query_quota.sh"

$linuxScriptsPath = "/root/scripts/wslblobnfs"
$versionFileName = "version.txt"

# To-do:
# - Add support for cleanup and finding mountmappings
# - Add tests for the module using Pester
# - Sign the module
#   https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_output_streams?view=powershell-5.1
# - Help content for each function: Get-Help <function-name>
# - Add Uninitialize module support

# To-do:
# - To handle -Debug issue, set the debug preference to continue and then set it back to the original value.
# - Check why -Debug switch is not working as expected in testing env:
#  https://stackoverflow.com/questions/4301562/how-to-properly-use-the-verbose-and-debug-parameters-in-a-custom-cmdlet


#
# Internal functions
#
function Get-ModuleVersion
{
    [CmdletBinding()]
    param()

    # In local dev env, the module is not installed from gallery. Hence, Get-InstalledModule will fail.
    # Hence, suppress the error and return 0.0.0 as the module version.
    $blobNFSModule = Get-InstalledModule -Name $moduleName 2>$null
    if ($blobNFSModule -eq $null)
    {
        return "0.0.0"
    }

    return $blobNFSModule.Version.ToString()
}

function Write-Success
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$message
    )

    Write-Host $message -ForegroundColor DarkGreen
}

function Execute-WSL
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$wslcommand
    )

    Write-Debug "Executing $wslcommand"
    wsl -d $distroName -u $userName -e bash -c $wslcommand
}

function Copy-WSLFiles
{
    [CmdletBinding()]
    param()

    # Note: Quote the path with '' to preserve space
    Write-Verbose "Copying necessary linux files from $modulePathForLinux"

    Execute-WSL "mkdir -p $linuxScriptsPath"

    Execute-WSL "cp '$modulePathForLinux/$wslScriptName' $linuxScriptsPath/$wslScriptName"

    # Files saved from windows will have \r\n line endings. Hence, we need to remove \r.
    Execute-WSL "sed -i -e 's/\r$//' $linuxScriptsPath/$wslScriptName"

    Execute-WSL "chmod +x $linuxScriptsPath/$wslScriptName"

    Execute-WSL "cp '$modulePathForLinux/$queryScriptName' $linuxScriptsPath/$queryScriptName"

    # Files saved from windows will have \r\n line endings. Hence, we need to remove \r.
    Execute-WSL "sed -i -e 's/\r$//' $linuxScriptsPath/$queryScriptName"

    Execute-WSL "chmod +x $linuxScriptsPath/$queryScriptName"

    Execute-WSL "ls -l $linuxScriptsPath | grep -E '$wslScriptName|$queryScriptName' > /dev/null 2>&1"
}

function Intall-WSLBlobNFS-Internal
{
    [CmdletBinding()]
    param()

    # Check if wsl is installed or not.
    wsl -l -v > $null 2>&1
    $wslstatus = $LASTEXITCODE

    # Check if the distro is installed or not.
    # Note: executing a command such as ls is required else if the distro is installed, then control will not come out of wsl command.
    wsl -d $distroName ls > $null 2>&1
    $distrostatus = $LASTEXITCODE

    if($wslstatus -eq 1)
    {
        Write-Host "WSL is not installed. Installing WSL..."

        wsl --install -d $distroName
        # To-do: Check if the distro is installed successfully or not.

        # To-do: Prompt user to restart the machine to complete WSL installation.
        Write-Success "Restart the VM to complete WSL installation, and then run Initialize-WSLBlobNFS to continue the WSL setup."

        # Set the exit code to 1 to indicate that the script execution is not completed.
        $global:LASTEXITCODE = 1
        return
    }
    elseif($distrostatus -eq -1)
    {
        Write-Host "WSL distro $distroName is not installed. Installing WSL distro $distroName..."
        wsl --install -d $distroName
        # To-do: Check if the distro is installed successfully or not.

        Write-Success "WSL distro $distroName is installed. Run Initialize-WSLBlobNFS to setup WSL environment for WSLBlobNFS usage."

        # Set the exit code to 1 to indicate that the script execution is not completed.
        $global:LASTEXITCODE = 1
        return
    }

    return
}


function Initialize-WSLBlobNFS-Internal
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Force=$false
    )

    # Check if wsl is installed or not.
    Intall-WSLBlobNFS-Internal
    if($LASTEXITCODE -ne 0)
    {
        # Set the exit code to 1 to indicate that the script execution is not completed.
        $global:LASTEXITCODE = 1
        return
    }

    $initialized = $false
    if($Force)
    {
        Write-Warning "Force initializing WSL environment for WSLBlobNFS usage."
    }
    else
    {
        Write-Debug "Initializing WSL environment for your WSLBlobNFS usage."
    }

    # # Add the modulePathForLinux, which hold the path of module, to WSLENV to help in copying linux scripts to wsl distro.
    # [Environment]::SetEnvironmentVariable("modulePathForLinux", $PSScriptRoot)
    # $p = [Environment]::GetEnvironmentVariable("WSLENV")
    # $p += ":modulePathForLinux/p"
    # [Environment]::SetEnvironmentVariable("WSLENV",$p)

    $moduleVersionOnWin = Get-ModuleVersion
    Write-Debug "Module version on Windows: $moduleVersionOnWin"
    $moduleVersionOnWSL = Execute-WSL "cat $linuxScriptsPath/$versionFileName 2>/dev/null"
    Write-Debug "Module version on WSL: $moduleVersionOnWSL"
    if(($LASTEXITCODE -eq 0) -and ($moduleVersionOnWSL.Trim() -eq $moduleVersionOnWin) -and !$Force)
    {
        Write-Debug "WSL Files are upto date. Skipping copying files."
    }
    else
    {
        $initialized = $true
        if($Force)
        {
            Write-Debug "Force parameter is provided. Copying files again."
        }
        elseif ($LASTEXITCODE -ne 0)
        {
            Write-Debug "Module is not installed. Copying files again."
        }
        else
        {
            Write-Debug "Module version is changed. Copying files again."
        }

        Copy-WSLFiles
        if ($LASTEXITCODE -ne 0)
        {
            Write-Error "Copying wsl files failed."
            return
        }

        Execute-WSL "echo $moduleVersionOnWin > $linuxScriptsPath/$versionFileName"
    }

    # Install systemd, restart wsl and install NFS & Samba
    Execute-WSL "systemctl list-unit-files --type=service | grep systemd > /dev/null 2>&1"
    if($LASTEXITCODE -eq 0 -and !$Force)
    {
        Write-Debug "Systemd is already installed. Skipping systemd installation."
    }
    else
    {
        $initialized = $true
        if($Force)
        {
            Write-Debug "Force parameter is provided. Installing systemd again."
        }
        else
        {
            Write-Debug "Systemd is not installed. Installing systemd."
        }

        Execute-WSL "$linuxScriptsPath/$wslScriptName installsystemd"
        Write-Verbose "Installed systemd."

        # Shutdown wsl and it will restart with systemd on next wsl command execution
        wsl -d $distroName --shutdown
    }

    # wsl shutsdown after 8 secs of inactivity. Hence, we need to run dbus-launch to keep it running.
    # Check the issue here:
    # https://github.com/microsoft/WSL/issues/10138
    # To-do: Check if dbus is already running or not.
    # dbus[488]: Unable to set up transient service directory: XDG_RUNTIME_DIR "/run/user/0/" is owned by uid 1000, not our uid 0
    # Even if the systemd is installed, we need to run dbus-launch to keep it running.
    wsl -d $distroName --exec dbus-launch true

    Execute-WSL "dpkg -s nfs-common samba > /dev/null 2>&1"
    if($LASTEXITCODE -eq 0 -and !$Force)
    {
        Write-Debug "NFS & Samba are already installed. Skipping their installation."
    }
    else
    {
        $initialized = $true
        if (!$Force)
        {
            Write-Debug "Force parameter is provided. Installing NFS & Samba again."
        }
        else
        {
            Write-Debug "NFS & Samba are not installed. Installing NFS & Samba."
        }
        Execute-WSL "'$linuxScriptsPath/$wslScriptName' installnfssmb $smbUserName"
        Write-Verbose "Installed NFS & Samba."
    }

    if ($initialized)
    {
        Write-Debug "WSL environment for WSLBlobNFS usage is initialized."
    }
    else
    {
        Write-Debug "WSL environment for WSLBlobNFS usage is already initialized. Skipping initialization."
    }
    return
}

#
# Public functions
#
function Install-WSLBlobNFS
{
    <#
    .SYNOPSIS
        Add

    .DESCRIPTION
        Add

    .PARAMETER Add
        Add

    .EXAMPLE
        Add

    .INPUTS
        Add

    .OUTPUTS
        Add

    .NOTES
        Author:  Azure Blob NFS
        Website: https://github.com/Azure/BlobNFS-wsl2
    #>

    [CmdletBinding()]
    param()

    Intall-WSLBlobNFS-Internal

    if ($LASTEXITCODE -eq 0)
    {
        # To-do: Prompt user to Initialize-WSLBlobNFS if WSL is already installed.
        Write-Success "WSL is already installed. Run Initialize-WSLBlobNFS to setup WSL environment for WSLBlobNFS usage."
    }

}

# To-do:
# - Dismount all the mounted shares before running Initialize again when force is provided.
function Initialize-WSLBlobNFS
{
    <#
    .SYNOPSIS
        Add

    .DESCRIPTION
        Add

    .PARAMETER Add
        Add

    .EXAMPLE
        Add

    .INPUTS
        Add

    .OUTPUTS
        Add

    .NOTES
        Author:  Azure Blob NFS
        Website: https://github.com/Azure/BlobNFS-wsl2
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][switch]$Force
    )

    # To-do: Show progress of the script execution.

    Initialize-WSLBlobNFS-Internal -Force:$Force
    if($LASTEXITCODE -ne 0)
    {
        return
    }

    Write-Success "WSL environment for WSLBlobNFS usage is initialized. Now, you can mount the smb share using Mount-WSLBlobNFS."
}

function Mount-WSLBlobNFS
{
    <#
    .SYNOPSIS
        Add

    .DESCRIPTION
        Add

    .PARAMETER Add
        Add

    .EXAMPLE
        Add

    .INPUTS
        Add

    .OUTPUTS
        Add

    .NOTES
        Author:  Azure Blob NFS
        Website: https://github.com/Azure/BlobNFS-wsl2
    #>

    [CmdletBinding(PositionalBinding=$true)]
    param(
        [Parameter(Mandatory = $true, Position=0)][string]$RemoteMount,
        [Parameter(Position=1)][string]$MountDrive
    )

    Initialize-WSLBlobNFS-Internal
    if($LASTEXITCODE -ne 0)
    {
        return
    }

    # Create a new MountDrive if not provided
    if([string]::IsNullOrWhiteSpace($MountDrive))
    {
        (65..(65+25)).ForEach({
            if ((-not (Test-Path ([char]$_ + ":")) -and [string]::IsNullOrWhiteSpace($MountDrive)))
            {
                $MountDrive = [char]$_ + ":"
                Write-Host "Using $MountDrive to mount the share."
            }})
    }

    # Check if the MountDrive is already in use or not.
    $pathExists = Test-Path "$MountDrive"
    if($pathExists)
    {
        Write-Error "$MountDrive is in use already."
        return
    }

    # To-do:
    # - Validate the RemoteMount and MountDrive even further.
    # - Check if the RemoteMount is a valid mount command or not.
    # - Check if the RemoteMount is already mounted or not.
    # - Check the exit code of net use command.

    $mountParameterType = ""

    $mountPattern = "mount -t nfs"
    if ($RemoteMount.Contains($mountPattern) -and $RemoteMount.IndexOf($mountPattern) -eq 0)
    {
        $mountParameterType = "command"
    }
    else
    {
        $mountParameterType = "remotehost"
    }

    # Temp file to store the share name in wsl
    # To-do:
    # - Can we use env variables to store the share name instead of temp file?
    # - Blocker: Windows spans a new shell and the env variables are forked and changes made in wsl are not available
    #            in windows.
    # - Check how to not span a new shell for wsl command execution.
    # - https://stackoverflow.com/questions/66150671/wsl-running-linux-commands-with-wsl-exec-cmd-or-wsl-cmd
    $winTempFilePath = New-TemporaryFile
    $wslTempFilePath = ("/mnt/" + ($winTempFilePath.FullName.Replace("\", "/").Replace(":", ""))).ToLower()

    Write-Verbose "Mounting $RemoteMount."
    Execute-WSL "$linuxScriptsPath/$wslScriptName mountshare $mountParameterType '$RemoteMount' '$wslTempFilePath'"

    if ($LASTEXITCODE -ne 0)
    {
        Write-Error "Mounting $RemoteMount failed."
        return
    }

    # Get the remote host ip address and the share name
    $ipaddress = Execute-WSL "hostname -I"
    $ipaddress = $ipaddress.Trim()

    # Read the share name from the temp file
    $smbsharename = Get-Content $winTempFilePath.FullName
    Remove-Item $winTempFilePath.FullName

    Write-Host "Mounting smb share \\$ipaddress\$smbsharename onto windows mount point $MountDrive"

    $password = $smbUserName
    net use $MountDrive "\\$ipaddress\$smbsharename" /persistent:yes /user:$smbUserName $password

    # Rollback the changes in wsl if net use fails.
    if ($LASTEXITCODE -ne 0)
    {
        Dismount-WSLMount $smbsharename
        Write-Error "Mounting '$RemoteMount' failed."
        return
    }

    Write-Success "Mounting smb share done. Now, you can access the share from $MountDrive."
}

# To-do:
# - Unmount multiple shares at once.
function Dismount-WSLBlobNFS
{
    <#
    .SYNOPSIS
        Add

    .DESCRIPTION
        Add

    .PARAMETER Add
        Add

    .EXAMPLE
        Add

    .INPUTS
        Add

    .OUTPUTS
        Add

    .NOTES
        Author:  Azure Blob NFS
        Website: https://github.com/Azure/BlobNFS-wsl2
    #>

    [CmdletBinding()]
    param(
        # Mountdrive is mandatory arguments for unmountshare
        [Parameter(Mandatory = $true)][string]$MountDrive,
        [Parameter(Mandatory = $false)][switch]$Force
    )

    Initialize-WSLBlobNFS-Internal
    if($LASTEXITCODE -ne 0)
    {
        return
    }

    # MountDrive is mandatory arguments for unmountshare
    if([string]::IsNullOrWhiteSpace($MountDrive))
    {
        Write-Error "Mounted drive is not provided."
        return
    }

    $smbmapping = Get-SmbMapping -LocalPath "$MountDrive"

    if($smbmapping -eq $null)
    {
        Write-Error "No smb share is mounted on $MountDrive."
        return
    }

    # Sample remote path: \\172.17.47.111\mntnfsv3share
    $remotePathTokens = $smbmapping.RemotePath.Split("\")
    $smbexportname = $remotePathTokens[-1].Trim(" ")
    $smbremotehost = $remotePathTokens[2].Trim(" ")

    # check if the remote host is the current wsl ip address
    $ipaddress = Execute-WSL "hostname -I"
    $ipaddress = $ipaddress.Trim()
    if($smbremotehost -ne $ipaddress)
    {
        Write-Error "The smb share is not mounted from the current wsl ip address."
        return
    }

    Execute-WSL "$linuxScriptsPath/$wslScriptName unmountshare '$smbexportname'"

    if ($LASTEXITCODE -ne 0)
    {
        Write-Error "Unmounting smb share failed in WSL."
        return
    }

    net use $MountDrive /delete
    Write-Success "Unmounting smb share done."
}

function Dismount-WSLMount
{
    <#
    .SYNOPSIS
        Add

    .DESCRIPTION
        Add

    .PARAMETER Add
        Add

    .EXAMPLE
        Add

    .INPUTS
        Add

    .OUTPUTS
        Add

    .NOTES
        Author:  Azure Blob NFS
        Website: https://github.com/Azure/BlobNFS-wsl2
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ShareName
    )

    Initialize-WSLBlobNFS-Internal
    if($LASTEXITCODE -ne 0)
    {
        return
    }

    # Don't unmount the share if SMB share is mounted in windows.
    $smbmapping = Get-SmbMapping -RemotePath "$ShareName" 2>$null
    if($smbmapping -ne $null)
    {
        Write-Error "SMB share is mounted in windows on $($smbmapping.LocalPath). Use Dismount-WSLBlobNFS $($smbmapping.LocalPath) to unmount the share."
        return
    }

    Write-Verbose "Unmounting $ShareName."

    Execute-WSL "$linuxScriptsPath/$wslScriptName unmountshare '$ShareName'"
    if ($LASTEXITCODE -ne 0)
    {
        Write-Error "Unmounting $ShareName failed."
        return
    }

    Write-Success "Unmounting $ShareName done."
}

Export-ModuleMember -Function Install-WSLBlobNFS, Initialize-WSLBlobNFS, Mount-WSLBlobNFS, Dismount-WSLBlobNFS, Dismount-WSLMount
