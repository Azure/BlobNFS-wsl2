# --------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
# --------------------------------------------------------------------------------------------

<#
.SYNOPSIS
    WSLBlobNFS module provides a way to mount Azure Blob NFS share in Windows via WSL.

.DESCRIPTION
    The native NFS client on Windows is not performant. This module provides a way to mount the Blob NFS share on WSL Linux distro and access the share from Windows.
    This module helps with the following:
    1. Install WSL and WSL distro if they are not installed already.
    2. Initialize WSL environment for Blob NFS usage.
    3. Mount the Blob NFS share in WSL.
    4. Dismount the Blob NFS share in WSL.

.LINK
    https://github.com/Azure/BlobNFS-wsl2

.NOTES
    Author:  Azure Blob NFS
    Website: https://github.com/Azure/BlobNFS-wsl2/
#>


# To-do:
# - Clear error message and actions to fix those errors.
# - Add support for cleanup and finding mountmappings
# - Add tests for the module using Pester
# - Sign the module
#   https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_output_streams?view=powershell-5.1
# - Add Uninitialize module support
# - Add retry logic for each of the commands
# - Allow the smb volume (plus nfs volume) to be automounted when user restarts wsl for some reason.

# Throw an error if any cmdlet, function, or command fails or a variable is unknown and stop the script execution.
Set-PSDebug -Strict
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Min supported WSL version
$minSupportedVersion = [Version]"2.0.0"

# WSL distro name and user name
$distroName = "Ubuntu-22.04"

# Most of the commands require admin privileges. Hence, we need to run the script as admin.
$userName = "root"

# Username and password for SMB share.
$smbUserName = "root"

$moduleName = "WSLBlobNFS"

$modulePathForWin = $PSScriptRoot
$modulePathForLinux = ("/mnt/" + ($modulePathForWin.Replace("\", "/").Replace(":", ""))).ToLower()

$wslScriptName = "wsl2_linux_script.sh"
$queryScriptName = "query_quota.sh"

#
# Internal functions
#
function Enable-Verbosity
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$verbosity
    )

    [Environment]::SetEnvironmentVariable("VERBOSE_MODE", $verbosity)
    $wslenvrionment = [Environment]::GetEnvironmentVariable("WSLENV")
    $wslenvrionment += ":VERBOSE_MODE"
    [Environment]::SetEnvironmentVariable("WSLENV",$wslenvrionment)
}

function Get-ModuleVersion
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    # In local dev env, the module is not installed from gallery. Hence, Get-InstalledModule will fail.
    # Hence, suppress the error and return 0.0.0 as the module version.
    $blobNFSModule = Get-InstalledModule -Name $moduleName -ErrorAction SilentlyContinue
    if ($null -eq $blobNFSModule)
    {
        return "0.0.0"
    }

    return $blobNFSModule.Version.ToString()
}

function Write-Success
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification='Need foreground color change for success message')]
    param(
        [Parameter(Mandatory = $true)][string]$message
    )

    Write-Host $message -ForegroundColor DarkGreen
}

function Invoke-WSL
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$wslcommand
    )

    Write-Verbose "Executing $wslcommand"
    wsl -d $distroName -u $userName -e bash -c $wslcommand
}

function Format-FilesInWSL
{
    [CmdletBinding()]
    param()

    # Note: Quote the path with '' to preserve space
    # Files saved from windows will have \r\n line endings. Hence, we need to remove \r.
    Invoke-WSL "sed -i -e 's/\r$//' '$modulePathForLinux/$wslScriptName'"
    Invoke-WSL "chmod +x '$modulePathForLinux/$wslScriptName'"

    # Files saved from windows will have \r\n line endings. Hence, we need to remove \r.
    Invoke-WSL "sed -i -e 's/\r$//' '$modulePathForLinux/$queryScriptName'"
    Invoke-WSL "chmod +x '$modulePathForLinux/$queryScriptName'"
}

function Install-WSLBlobNFS-Internal
{
    [CmdletBinding()]
    param()

    # Check if WSL is installed or not.
    $wslDistros = wsl -l -v 2>&1
    $wslstatus = $LastExitCode

    # Check the WSL version
    $wslVersionOp = wsl -v 2>&1
    $wslstatus1 = $LastExitCode

    if(($wslstatus -ne 0) -or ($wslstatus1 -ne 0))
    {
        Write-Output "WSL is not installed. Installing WSL..."

        wsl --install -d $distroName

        # Update wsl to the latest version
        wsl --update
        # Set the default version to WSL2
        wsl --set-default-version 2

        if($LastExitCode -ne 0)
        {
            Write-Error "WSL installation failed. Try again."
            $global:LastExitCode = 1
            return
        }

        Write-Success "WSL distro $distroName successfully installed!"

        Write-Success "Restart the machine to complete WSL installation, and then run Initialize-WSLBlobNFS to continue the WSL setup."
        Restart-Computer -Confirm

        # Set the exit code to 1 to indicate that the script execution is not completed.
        $global:LastExitCode = 1
        return
    }

    # Remove the null character from the output and extract the version number.
    $wslVersionOp = $wslVersionOp -replace '\0', ''
    $wslVersionOp = $wslVersionOp -match 'WSL Version:'
    [Version]$wslVersion = $wslVersionOp.Split(":")[1].Trim()

    # Systemd is available after certain WSL version. Hence, this check.
    if($wslversion -lt $minSupportedVersion)
    {
        Write-Error "Existing WSL version $wslversion is not supported for Blob NFS usage. Please upgrade to WSL2 using 'wsl --update' and set the default version to WSL2 using 'wsl --set-default-version 2'"
        $global:LastExitCode = 1
        return
    }

    # Check if the distro is installed or not.
    $wslDistros = $wslDistros -replace '\0', ''
    $distroStatus = $wslDistros -match "Ubuntu-22.04"

    if([string]::IsNullOrWhiteSpace($distroStatus))
    {
        Write-Output "WSL distro $distroName is not installed. Installing WSL distro $distroName..."
        wsl --install -d $distroName

        if($LastExitCode -ne 0)
        {
            Write-Error "WSL distro $distroName installation failed. Try again."
            $global:LastExitCode = 1
            return
        }

        Write-Success "WSL distro $distroName is installed. Run Initialize-WSLBlobNFS to setup WSL environment for WSLBlobNFS usage."

        # Since the distro can now be used, we can continue the script execution. Hence, the exit code is 0.
        return
    }
}

function Initialize-WSLBlobNFS-Internal
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Force=$false
    )

    # Check if WSL is installed or not.
    Install-WSLBlobNFS-Internal
    if($LastExitCode -ne 0)
    {
        # Set the exit code to 1 to indicate that the script execution is not completed.
        $global:LastExitCode = 1
        return
    }

    # WSL shutsdown after 8 secs of inactivity. Hence, we need to run dbus-launch to keep it running.
    # Check the issue here:
    # https://github.com/microsoft/WSL/issues/10138
    wsl -d $distroName --exec dbus-launch true

    $initialized = $false
    if($Force)
    {
        Write-Warning "Force initializing WSL environment for WSLBlobNFS usage. Existing mounts may be lost."
    }
    else
    {
        Write-Verbose "Initializing WSL environment for your WSLBlobNFS usage."
    }

    Format-FilesInWSL

    # Install systemd
    Invoke-WSL "systemctl list-unit-files --type=service | grep -q ^systemd-"
    if($LastExitCode -eq 0 -and !$Force)
    {
        Write-Verbose "Systemd is already installed. Skipping systemd installation."
    }
    else
    {
        $initialized = $true
        if($Force)
        {
            Write-Verbose "Force parameter is provided. Installing systemd again."
        }
        else
        {
            Write-Verbose "Systemd is not installed. Installing systemd."
        }

        Invoke-WSL "'$modulePathForLinux/$wslScriptName' installsystemd"
        if ($LastExitCode -ne 0)
        {
            Write-Error "Installing systemd failed."

            $global:LastExitCode = 1
            return
        }

        # Shutdown WSL and it will restart with systemd on next WSL command execution
        # Confirm from user if we can shudown WSL
        if (!$Force)
        {
            $confirmation = Read-Host -Prompt "WSL $distroName has to be shutdown to install and run systemd. Press y/Y to shutdown WSL. Default is 'y'."
            if(-not ($confirmation -eq "y" -or $confirmation -eq "Y" -or $confirmation -eq ""))
            {
                Write-Error "Setup not comepleted. Allow WSL shutdown to continue the setup."

                $global:LastExitCode = 1
                return
            }
        }

        Write-Verbose "Shutting down WSL $distroName."
        wsl -d $distroName --shutdown

        # Since we shutdown WSL, we need to run dbus-launch again.
        wsl -d $distroName --exec dbus-launch true

        # Check if systemd is properly installed or not.
        Invoke-WSL "systemctl list-unit-files --type=service | grep -q ^systemd-"

        if($LastExitCode -ne 0)
        {
            Write-Error "Systemd installation failed."

            $global:LastExitCode = 1
            return
        }

        Write-Success "Installed systemd sucessfully!"
    }

    # Install NFS & Samba
    Invoke-WSL "dpkg -s nfs-common samba > /dev/null 2>&1"
    if($LastExitCode -eq 0 -and !$Force)
    {
        Write-Verbose "NFS & Samba are already installed. Skipping their installation."
    }
    else
    {
        $initialized = $true
        if ($Force)
        {
            Write-Verbose "Force parameter is provided. Installing NFS & Samba again."
        }
        else
        {
            Write-Verbose "NFS & Samba are not installed. Installing NFS & Samba."
        }
        Invoke-WSL "'$modulePathForLinux/$wslScriptName' installnfssmb $smbUserName"
        Write-Success "Installed NFS & Samba successfully!"
    }

    if ($initialized)
    {
        Write-Verbose "WSL environment for WSLBlobNFS usage is initialized."
    }
    else
    {
        Write-Verbose "WSL environment for WSLBlobNFS usage is already initialized. Skipping initialization."
    }
}

function Dismount-MountInsideWSL
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ShareName
    )

    # Don't unmount the share if SMB share is mounted in windows.
    $smbmapping = Get-SmbMapping -RemotePath "$ShareName" -ErrorAction SilentlyContinue
    if($null -ne $smbmapping)
    {
        Write-Error "SMB share is mounted in windows on $($smbmapping.LocalPath). Use Dismount-WSLBlobNFS $($smbmapping.LocalPath) to unmount the share."
        return
    }

    Write-Verbose "Unmounting $ShareName."

    Invoke-WSL "'$modulePathForLinux/$wslScriptName' unmountshare '$ShareName'"
    if ($LastExitCode -ne 0)
    {
        Write-Error "Unmounting $ShareName failed."
        return
    }

    Write-Success "Unmounting $ShareName done."
}

#
# Public functions
#
function Install-WSLBlobNFS
{
    <#
    .SYNOPSIS
        Install WSL and WSL distro for WSLBlobNFS usage.

    .DESCRIPTION
        This command installs WSL and WSL distro if they are not installed already.
        Note: You may need to restart the machine to complete WSL installation if WSL is not installed already.

    .EXAMPLE
        PS> Install-WSLBlobNFS

    .LINK
        https://github.com/Azure/BlobNFS-wsl2

    .NOTES
        Author:  Azure Blob NFS
        Website: https://github.com/Azure/BlobNFS-wsl2
    #>

    [CmdletBinding()]
    param()

    # Set the verbosity preference for WSL based on the current preferences.
    $verbosity = 0
    if($VerbosePreference -eq "Continue")
    {
        $verbosity = 1
    }
    else
    {
        $verbosity = 0
    }
    Enable-Verbosity -verbosity $verbosity


    Install-WSLBlobNFS-Internal

    if ($LastExitCode -eq 0)
    {
        Write-Success "WSL is already installed. Run Initialize-WSLBlobNFS to setup WSL environment for WSLBlobNFS usage."

        $confirmation = Read-Host -Prompt "Press (y/Y) to run the Initialize-WSLBlobNFS command. Default is 'y'."
        if($confirmation -eq "y" -or $confirmation -eq "Y" -or $confirmation -eq "")
        {
            Initialize-WSLBlobNFS
        }
    }
}

function Initialize-WSLBlobNFS
{
    <#
    .SYNOPSIS
        Setup WSL environment with systemd, NFS, and Samba for WSL Blob NFS usage.

    .DESCRIPTION
        systemd is required to run NFS server in WSL. Then, NFS and Samba are installed to mount the Blob NFS share in WSL and access the share from Windows via SMB respectively.

    .EXAMPLE
        PS> Initialize-WSLBlobNFS

    .LINK
        https://github.com/Azure/BlobNFS-wsl2

    .NOTES
        Author:  Azure Blob NFS
        Website: https://github.com/Azure/BlobNFS-wsl2
    #>

    [CmdletBinding()]
    param(
        # Force initialization of WSL environment. This will unmount all the existing NFS mounts.
        # This is useful when you want to re-initialize the WSL environment.
        [Parameter(Mandatory = $false)][switch]$Force
    )

    # Set the verbosity preference for WSL based on the current preferences.
    $verbosity = 0
    if($VerbosePreference -eq "Continue")
    {
        $verbosity = 1
    }
    else
    {
        $verbosity = 0
    }
    Enable-Verbosity -verbosity $verbosity

    # To-do: Show progress of the script execution.

    Initialize-WSLBlobNFS-Internal -Force:$Force
    if($LastExitCode -ne 0)
    {
        return
    }

    Write-Success "WSL environment for WSLBlobNFS usage is initialized. Now, you can mount the SMB share using Mount-WSLBlobNFS."
    $confirmation = Read-Host -Prompt "Press (y/Y) to run the Mount-WSLBlobNFS command. Default is 'y'."
    if($confirmation -eq "y" -or $confirmation -eq "Y" -or $confirmation -eq "")
    {
        Mount-WSLBlobNFS
    }
}

function Mount-WSLBlobNFS
{
    <#
    .SYNOPSIS
        Mount Blob NFS share in Windows via WSL.

    .DESCRIPTION
        This command mounts the provided Blob NFS share in WSL, exports the share via SMB, and mounts the SMB share in Windows.

    .EXAMPLE
        PS> Mount-WSLBlobNFS -RemoteMount "account.blob.core.windows.net:account/container"
        You can just provide the NFSv3 share address as below.

    .EXAMPLE
        PS> Mount-WSLBlobNFS -RemoteMount "mount -t nfs -o vers=3,proto=tcp account.blob.preprod.core.windows.net:/account/container /mnt/nfsv3share"
        You can also provide the NFS mount command if you want to provide extra mount parameters.

    .LINK
        https://github.com/Azure/BlobNFS-wsl2

    .NOTES
        Author:  Azure Blob NFS
        Website: https://github.com/Azure/BlobNFS-wsl2
    #>

    [CmdletBinding(PositionalBinding=$true)]
    param(
        # RemoteMount is your Blob NFS share address or the NFS mount command.
        # If the RemoteMount is the NFS share address, then the share will be mounted with default mount parameters.
        # If the RemoteMount is the NFS mount command, then the share will be mounted with the provided mount parameters.
        # Check the examples for more details.
        [Parameter(Mandatory = $true, Position=0)][string]$RemoteMount,

        # MountDrive is the drive letter to mount the SMB share in Windows.
        [Parameter(Position=1)][string]$MountDrive
    )

    # Set the verbosity preference for WSL based on the current preferences.
    $verbosity = 0
    if($VerbosePreference -eq "Continue")
    {
        $verbosity = 1
    }
    else
    {
        $verbosity = 0
    }
    Enable-Verbosity -verbosity $verbosity

    Initialize-WSLBlobNFS-Internal
    if($LastExitCode -ne 0)
    {
        return
    }

    # Create a new MountDrive if not provided
    if([string]::IsNullOrWhiteSpace($MountDrive))
    {
        Write-Output "MountDrive parameter is not provided. Finding a free drive letter to mount the share."
        # Get the first free drive letter
        # 65 is the ASCII value of 'A'
        (65..(65+25)).ForEach({
            if ((-not (Get-PSDrive ([char]$_) -ErrorAction SilentlyContinue) -and [string]::IsNullOrWhiteSpace($MountDrive)))
            {
                $MountDrive = [char]$_ + ":"
                Write-Success "Using $MountDrive to mount the share."
            }})

        if([string]::IsNullOrWhiteSpace($MountDrive))
        {
            Write-Error "No free drive letter found to mount the share."
            return
        }
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

    # Temp file to store the share name in WSL
    # To-do:
    # - Can we use env variables to store the share name instead of temp file?
    # - Blocker: Windows spans a new shell and the env variables are forked and changes made in WSL are not available in windows.
    # - Check how to not span a new shell for wsl command execution.
    # - https://stackoverflow.com/questions/66150671/wsl-running-linux-commands-with-wsl-exec-cmd-or-wsl-cmd
    $winTempFilePath = New-TemporaryFile
    $wslTempFilePath = ("/mnt/" + ($winTempFilePath.FullName.Replace("\", "/").Replace(":", ""))).ToLower()

    Write-Verbose "Mounting $RemoteMount."
    Invoke-WSL "'$modulePathForLinux/$wslScriptName' mountshare '$mountParameterType' '$RemoteMount' '$wslTempFilePath'"

    if ($LastExitCode -ne 0)
    {
        Write-Error "Mounting $RemoteMount failed in WSL."
        return
    }

    # Get the remote host ip address and the share name
    $ipaddress = Invoke-WSL "hostname -I"
    $ipaddress = $ipaddress.Trim()

    # Read the share name from the temp file
    $smbShareName = Get-Content $winTempFilePath -ErrorAction SilentlyContinue
    Remove-Item $winTempFilePath -ErrorAction SilentlyContinue

    Write-Output "Mounting SMB share \\$ipaddress\$smbShareName onto drive $MountDrive"

    $password = $smbUserName
    net use $MountDrive "\\$ipaddress\$smbShareName" /persistent:yes /user:$smbUserName $password | Out-Null

    # Rollback the changes in WSL if net use fails.
    if ($LastExitCode -ne 0)
    {
        Dismount-MountInsideWSL $smbShareName
        Write-Error "Mounting '$RemoteMount' failed."
        return
    }

    #  Print the mount mappings
    Get-SmbMapping -LocalPath "$MountDrive"

    Write-Success "Mounting SMB share done. Now, you can access the share from $MountDrive."
}

function Dismount-WSLBlobNFS
{
    <#
    .SYNOPSIS
        Dismount your Blob NFS share in Windows.

    .DESCRIPTION
        You can only dismount the Blob NFS share that is mounted using Mount-WSLBlobNFS.

    .EXAMPLE
        PS> DisMount-WSLBlobNFS -MountDrive "Z:"

    .LINK
        https://github.com/Azure/BlobNFS-wsl2

    .NOTES
        Author:  Azure Blob NFS
        Website: https://github.com/Azure/BlobNFS-wsl2
    #>

    [CmdletBinding()]
    param(
        # Mountdrive that has previously mounted Blob NFS share.
        [Parameter(Mandatory = $true)][string]$MountDrive
    )

    # Set the verbosity preference for WSL based on the current preferences.
    $verbosity = 0
    if($VerbosePreference -eq "Continue")
    {
        $verbosity = 1
    }
    else
    {
        $verbosity = 0
    }
    Enable-Verbosity -verbosity $verbosity

    Initialize-WSLBlobNFS-Internal
    if($LastExitCode -ne 0)
    {
        return
    }

    if([string]::IsNullOrWhiteSpace($MountDrive))
    {
        Write-Error "Empty or Null mounted drive received."
        return
    }

    $smbmapping = Get-SmbMapping -LocalPath "$MountDrive" -ErrorAction SilentlyContinue

    if($null -eq $smbmapping)
    {
        Write-Error "No SMB share is mounted on $MountDrive."
        continue
    }

    # Sample remote path: \\172.17.47.111\mntnfsv3share
    $remotePathTokens = $smbmapping.RemotePath.Split("\")
    $smbexportname = $remotePathTokens[-1].Trim(" ")
    $smbremotehost = $remotePathTokens[2].Trim(" ")

    # Remote host should be the current WSL's ip address
    $ipaddress = Invoke-WSL "hostname -I"
    $ipaddress = $ipaddress.Trim()
    if($smbremotehost -ne $ipaddress)
    {
        Write-Error "The $MountDrive is not mounted from the current WSL $distroName."
        return
    }

    Invoke-WSL "'$modulePathForLinux/$wslScriptName' unmountshare '$smbexportname'"

    if ($LastExitCode -ne 0)
    {
        Write-Error "Unmounting $MountDrive failed in WSL."
        return
    }

    net use $MountDrive /delete | Out-Null
    if ($LastExitCode -ne 0)
    {
        Write-Error "Unmounting $MountDrive failed in Windows."
        return
    }
    Write-Success "Unmounting $MountDrive done."
}

# This list overrides the list provided in the module manifest (.psd1) file.
Export-ModuleMember -Function Install-WSLBlobNFS, Initialize-WSLBlobNFS, Mount-WSLBlobNFS, Dismount-WSLBlobNFS
