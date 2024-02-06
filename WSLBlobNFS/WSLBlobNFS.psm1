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
# - Detect processor architecture and disallow ARM processors.

# Throw an error if any cmdlet, function, or command fails or a variable is unknown and stop the script execution.
Set-PSDebug -Strict
Set-StrictMode -Version Latest

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
    if($null -eq $blobNFSModule)
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

function Write-ErrorLog
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification='Need foreground color change for error message')]
    param(
        [Parameter(Mandatory = $true)][string]$message
    )

    Write-Error -Message $message -ErrorAction SilentlyContinue
    $Host.UI.WriteErrorLine($message)
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

function Format-WSLFile
{
    [CmdletBinding()]
    param()

    # Note: Quote the path with '' to preserve space
    # Files saved from windows will have \r\n line endings. Hence, we need to remove \r.
    Invoke-WSL "sed -i -e 's/\r$//' '$modulePathForLinux/$wslScriptName'"
    Invoke-WSL "chmod +x '$modulePathForLinux/$wslScriptName'"

    if($LastExitCode -ne 0)
    {
        Write-ErrorLog "Failed to update $wslScriptName in WSL."
        $global:LastExitCode = 1
        return
    }

    # Files saved from windows will have \r\n line endings. Hence, we need to remove \r.
    Invoke-WSL "sed -i -e 's/\r$//' '$modulePathForLinux/$queryScriptName'"
    Invoke-WSL "chmod +x '$modulePathForLinux/$queryScriptName'"

    if($LastExitCode -ne 0)
    {
        Write-ErrorLog "Failed to update $modulePathForLinux in WSL."
        $global:LastExitCode = 1
        return
    }
}

function Install-WSL2
{
    [CmdletBinding()]
    param()

    # WSL is supported only on 64 bit PS.
    Write-Verbose "Checking if Powershell is 32 bit or 64 bit."
    $is64bit = [Environment]::Is64BitProcess

    if($is64bit -eq $false)
    {
        Write-ErrorLog "WSL2 installation is not supported on 32 bit PS. Please use 64 bit Powershell."
        $global:LastExitCode = 1
        return
    }

    # PSEdition check. Only Desktop edition is supported.
    Write-Verbose "Checking if Powershell is Desktop edition or not."
    if($PSEdition -ne "Desktop")
    {
        Write-ErrorLog "This module installation is not supported on Powershell Core. Please use Powershell Desktop edition."
        $global:LastExitCode = 1
        return
    }

    # Avoid collecting computer info path if everything is already installed and return from here.
    Write-Verbose "Checking WSL installation status."

    # Check the WSL version
    $wslVersionOp = wsl -v 2>&1
    $wslstatus = $LastExitCode
    Write-Verbose "WSL Version: `n$wslVersionOp"
    Write-Verbose "WSL Version status code: `n$wslstatus"

    # WSL2 is already present.
    if(($wslstatus -eq 0))
    {
        Write-Verbose "WSL2 is already installed. Checking for updates."
        $wslupdate = wsl --update 2>&1

        if($LastExitCode -ne 0)
        {
            # Since WSL2 is already installed, we can continue the script execution. Hence, the exit code is 0.
            Write-Warning "WSL2 update failed: $wslupdate."
            Write-Warning "Continuing with the currently installed WSL2 version."
        }
        else
        {
            Write-Verbose "WSL2 is is upto date!"
        }

        $global:LastExitCode = 0
        return
    }

    Write-Output "WSL2 is not installed. Trying to install WSL2..."

    # Check if the device support virtualization or not.
    Write-Verbose "Checking if the device supports virtualization."
    $compInfo = Get-ComputerInfo

    $windowsVersion = $compInfo.WindowsVersion
    Write-Verbose "Windows version: $windowsVersion"

    $winEdition = $compInfo.OsName
    Write-Verbose "Windows edition: $winEdition"

    # Check the os version number.
    # WSL2 commands are supported only on Windows 10/11 version than 2004.
    # and on Windows Server 2022 on version higher than 2009.
    # To-do: Add support for Server 2019
    # https://learn.microsoft.com/en-us/windows/wsl/install#prerequisites
    $isWSLsuppported = ($winEdition -notmatch "Server" -and $windowsVersion -ge 2004) -or ($winEdition -match "Server" -and $windowsVersion -ge 2009)

    if($isWSLsuppported -eq $false)
    {
        Write-ErrorLog "Your Windows version - $winEdition ($windowsVersion) - does not support WSL2 commands used by this module. Please check Prerequisites section of the module for help."
        $global:LastExitCode = 1
        return
    }

    # Only certain Azure VMs support nested virtualization required for WSL2.
    # Query Azure Instance Metadata Service to check if the VM is an Azure VM or not.
    # https://learn.microsoft.com/en-us/azure/virtual-machines/instance-metadata-service
    $azureVmInfo = $(Invoke-RestMethod -Headers @{"Metadata"="true"} -Method GET -Proxy $Null -Uri "http://169.254.169.254/metadata/instance?api-version=2021-01-01" -TimeoutSec 3) 2>&1

    if ($azureVmInfo -match "compute")
    {
        Write-Output "This is an Azure VM. Checking virtualization status..."

        $vmSecurityProfile = [bool]::Parse($azureVmInfo.compute.securityProfile.secureBootEnabled) -or [bool]::Parse($azureVmInfo.compute.securityProfile.virtualTpmEnabled)
        Write-Output "Device protection status: $vmSecurityProfile"

        $vmSize = $azureVmInfo.compute.vmSize
        Write-Output "Azure VM SKU: $vmSize"

        if(($vmSize -match "v[1-4]$") -and ($vmSecurityProfile -eq $true))
        {
            Write-ErrorLog "Sorry, this module will not work on this VM. :( `nCurrently only v5 and above Azure VMs with Trusted Launch support nested virtualization needed for WSL2."
            $global:LastExitCode = 1
            return
        }
    }
    else
    {
        Write-Output "This is not an Azure VM. Skipping virtualization check."
    }

    # WSL version check.
    $wslNotInstalled = ($wslstatus -eq 1)
    $wsl1Installed = ($wslstatus -eq -1)
    $wsl2Installed = ($wslstatus -eq 0)

    # No presence of WSL
    if($wslNotInstalled)
    {
        Write-Output "WSL2 is not installed. Installing WSL2..."

        wsl --install --no-distribution

        if($LastExitCode -ne 0)
        {
            Write-ErrorLog "WSL2 installation failed. Try again."
            $global:LastExitCode = 1
            return
        }

        Write-Success "Successfully installed WSL2!"

        # Restart computer to complete WSL installation.
        Write-Success "Restart the machine to complete WSL2 setup."
        Restart-Computer -Confirm

        Write-ErrorLog "Setup not completed. Restart the machine to complete WSL2 setup."

        # Set the exit code to 1 to indicate that the script execution is not completed.
        $global:LastExitCode = 1
        return
    }

    # When WSL1 is present.
    elseif($wsl1Installed)
    {
        Write-Output "WSL1 is installed. Updating WSL1 to WSL2..."
        wsl --update
        if($LastExitCode -ne 0)
        {
            Write-ErrorLog "WSL2 update failed. Try again."
            $global:LastExitCode = 1
            return
        }

        # Wait for 8 secs for the upgrade to finish.
        Write-Output "Waiting 8 secs for the WSL upgrade to finish.."
        Start-Sleep -s 8

        $wslstatus1 = wsl -v 2>&1

        if($LastExitCode -ne 0)
        {
            Write-ErrorLog "WSL2 update failed with error: $wslstatus1. Try again."
            $global:LastExitCode = 1
            return
        }

        Write-Success "Successfully updated WSL to WSL2!"

        # Restart computer to complete WSL installation.
        Write-Success "Restart the machine to complete WSL2 setup."
        Restart-Computer -Confirm

        Write-ErrorLog "Setup not completed. Restart the machine to complete WSL2 setup."

        # Set the exit code to 1 to indicate that the script execution is not completed.
        $global:LastExitCode = 1
        return
    }

    # WSL2 installed.
    elseif($wsl2Installed)
    {
        Write-Verbose "WSL2 is already installed. Checking for updates."
        $wslupdate = wsl --update 2>&1
        Write-Verbose "WSL2 update status: $wslupdate"

        if($LastExitCode -ne 0)
        {
            # Since WSL2 is already installed, we can continue the script execution. Hence, the exit code is 0.
            Write-Warning "WSL2 update failed: $wslupdate"
            Write-Warning "Continuing with the currently installed WSL2 version."
        }
        else
        {
            Write-Verbose "WSL2 is already installed and updated!"
        }
    }

    # Print a warning message and proceed. The other part of the script will the distro installation and version support.
    else
    {
        Write-Warning "WSL2 installation status is unknown. `nWSL Version: $wslVersionOp `nWSL Version status code: $wslstatus"
        Write-Warning "Continuing with the currently installed WSL version."
    }

    $global:LastExitCode = 0
    return
}

function Install-WSLBlobNFS-Internal
{
    [CmdletBinding()]
    param()

    Install-WSL2
    if($LastExitCode -ne 0)
    {
        return
    }

    # Check if the distro is installed or not.
    # If WSL2 installed but the distro is not installed, then wsl -l -v will return -1.
    $wslDistros = wsl -l -v

    if( -not (($LastExitCode -eq 0) -or ($LastExitCode -eq -1)))
    {
        Write-ErrorLog "WSL distro check failed."
        $global:LastExitCode = 1
        return
    }

    $wslDistros = $wslDistros -replace '\0', ''
    $distroStatus = $wslDistros -match $distroName
    Write-Verbose "WSL distro status: $distroStatus"

    if(-not $distroStatus)
    {
        Write-Output "Installing WSL distro $distroName..."
        $wslListOnline = wsl -l -o 2>&1

        if($LastExitCode -ne 0)
        {
            Write-ErrorLog "Unable to fetch the list of WSL distros: $wslListOnline"
            $global:LastExitCode = 1
            return
        }

        Write-Output "WSL distro $distroName is not installed but MUST be installed to proceed with the Blob NFS setup. This is only one time installation."
        Write-Output "Installing WSL distro $distroName..."
        Write-Warning "!!!!! After the distro is installed, setup a new user and exit the distro (using 'exit') to continue the setup !!!!!" -WarningAction Inquire

        wsl --install -d $distroName

        if($LastExitCode -ne 0)
        {
            Write-ErrorLog "WSL distro $distroName installation failed. Try again."
            $global:LastExitCode = 1
            return
        }

        # Check if the distro is installed successfully or not.
        wsl -d $distroName -u $userName -e bash -c "whoami" | Out-Null

        if($LastExitCode -ne 0)
        {
            Write-ErrorLog "WSL distro $distroName installation failed. Check Prerequisites section of the module for help."
            $global:LastExitCode = 1
            return
        }

        Write-Success "Installed WSL distro $distroName."

        # Since the distro can now be used, we can continue the script execution. Hence, the exit code is 0.
        $global:LastExitCode = 0
        return
    }
    else
    {
        Write-Verbose "WSL distro $distroName is already installed. This distro will be used for Blob NFS usage."
    }
}

function Initialize-WSLBlobNFS-Internal
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Force=$false
    )
    Write-Verbose "Checking if WSL environment is initialized for WSLBlobNFS usage..."
    # Check if WSL is installed or not.
    Install-WSLBlobNFS-Internal
    if($LastExitCode -ne 0)
    {
        # Set the exit code to 1 to indicate that the script execution is not completed.
        $global:LastExitCode = 1
        return
    }

    $initialized = $false
    if($Force)
    {
        Write-Warning "Force initializing WSL environment for WSLBlobNFS usage. WSL $distroName will be shutdown and existing mounts may be lost."
    }
    else
    {
        Write-Verbose "Initializing WSL environment for your WSLBlobNFS usage."
    }

    Format-WSLFile

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
            Write-Output "Force parameter is provided. Installing systemd again..."
        }
        else
        {
            Write-Output "Systemd is not installed. Installing systemd..."
        }

        Invoke-WSL "'$modulePathForLinux/$wslScriptName' installsystemd"
        if($LastExitCode -ne 0)
        {
            Write-ErrorLog "Installing systemd failed."

            $global:LastExitCode = 1
            return
        }

        # Shutdown WSL and it will restart with systemd on next WSL command execution
        # Confirm from user if we can shudown WSL
        if(!$Force)
        {
            $confirmation = Read-Host -Prompt "WSL $distroName has to be shutdown to install and run systemd. Press y/Y to shutdown WSL or press any key to abort. Default is 'y'."
            if(-not ($confirmation -eq "y" -or $confirmation -eq "Y" -or $confirmation -eq ""))
            {
                Write-ErrorLog "Setup not completed. Allow WSL shutdown to continue the setup."

                $global:LastExitCode = 1
                return
            }
        }

        Write-Verbose "Shutting down WSL $distroName..."

        # Note: Since we shutdown WSL, we need to run dbus-launch again, otherwise WSL will shutdown after 8 secs of inactivity.
        wsl -d $distroName --shutdown

        Write-Verbose "Starting WSL $distroName."
        Invoke-WSL "ls > /dev/null 2>&1"
        Write-Verbose "Started WSL $distroName."

        # Check if systemd is properly installed or not.
        Invoke-WSL "systemctl list-unit-files --type=service | grep -q ^systemd-"

        if($LastExitCode -ne 0)
        {
            Write-ErrorLog "Systemd installation failed."

            $global:LastExitCode = 1
            return
        }

        Write-Success "Installed systemd sucessfully!"
    }

    # WSL shutsdown after 8 secs of inactivity. Hence, we need to run dbus-launch to keep it running.
    # Check the issue here:
    # https://github.com/microsoft/WSL/issues/10138
    wsl -d $distroName --exec dbus-launch true

    # Install NFS, AzNFS, & Samba
    Invoke-WSL "dpkg -s nfs-common samba aznfs > /dev/null 2>&1"
    if($LastExitCode -eq 0 -and !$Force)
    {
        Write-Verbose "NFS, AzNFS, & Samba are already installed. Skipping their installation."
    }
    else
    {
        $initialized = $true
        if($Force)
        {
            Write-Output "Force parameter is provided. Installing NFS, AzNFS, & Samba again..."
        }
        else
        {
            Write-Output "NFS, AzNFS, & Samba are not installed. Installing NFS, AzNFS, & Samba..."
        }
        Invoke-WSL "'$modulePathForLinux/$wslScriptName' installnfssmb $smbUserName"
        if($LastExitCode -ne 0)
        {
            Write-ErrorLog "Installing NFS, AzNFS, & Samba failed."

            $global:LastExitCode = 1
            return
        }
        Write-Success "Installed NFS, AzNFS, & Samba successfully!"
    }

    if($initialized)
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
        Write-ErrorLog "SMB share is mounted in windows on $($smbmapping.LocalPath). Use Dismount-WSLBlobNFS $($smbmapping.LocalPath) to unmount the share."
        return
    }

    Write-Verbose "Unmounting $ShareName."

    Invoke-WSL "'$modulePathForLinux/$wslScriptName' unmountshare '$ShareName'"
    if($LastExitCode -ne 0)
    {
        Write-ErrorLog "Unmounting $ShareName failed."
        return
    }

    Write-Success "Unmounting $ShareName done."
}

function Assert-PipelineWSLBlobNFS-Internal
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][CimInstance]$smbmapping
    )

    Write-Output "Checking WSLBlobNFS pipeline status..."

    $mountDrive = $smbmapping.LocalPath
    # Sample remote path: \\172.17.47.111\mntnfsv3share
    $remotePathTokens = $smbmapping.RemotePath.Split("\")
    $smbexportname = $remotePathTokens[-1].Trim(" ")
    $smbremotehost = $remotePathTokens[2].Trim(" ")

    # Remote host should be the current WSL's ip address
    $ipaddress = Invoke-WSL "hostname -I"
    $ipaddress = $ipaddress.Trim()
    if($smbremotehost -ne $ipaddress)
    {
        Write-Warning "The $mountDrive is not mounted from the current WSL $distroName."
    }
    else
    {
        Write-Output "Checking the mount status of $mountDrive in WSL $distroName..."
        Invoke-WSL "'$modulePathForLinux/$wslScriptName' checkmount '$smbexportname'"

        if($LastExitCode -ne 0)
        {
            Write-ErrorLog "Unable to mount $mountDrive in WSL $distroName."
        }
        else
        {
            Write-Output "Removing $mountDrive from Windows."
            # Remove the SMB mapping and add again to avoid having to authenticate again in the explorer.
            net use $mountDrive /delete /yes | Out-Null
            $mnt = Get-SmbMapping -LocalPath $mountDrive -ErrorAction SilentlyContinue

            if(($LastExitCode -ne 0) -or ($null -ne $mnt))
            {
                Write-ErrorLog "Unable to mount $mountDrive in Windows."
                return
            }

            Write-Output "Mounting $mountDrive in Windows."
            net use $mountDrive "\\$ipaddress\$smbexportname" /persistent:yes /user:$smbUserName $smbUserName | Out-Null
            $mnt = Get-SmbMapping -LocalPath $mountDrive -ErrorAction SilentlyContinue

            if(($LastExitCode -ne 0) -or ($null -eq $mnt))
            {
                Write-ErrorLog "Unable to mount $mountDrive in Windows."
                return
            }

            Get-SmbMapping -LocalPath $mountDrive

            Write-Success "Mounting SMB share done. Now, you can access the share from $mountDrive."
        }
    }
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

    if($LastExitCode -eq 0)
    {
        Write-Success "WSL2 is already installed. Run Initialize-WSLBlobNFS to setup WSL environment for WSLBlobNFS usage."
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
        Note: MountDrive parameter is optional. If not provided, the drive will be automatically assigned.

    .EXAMPLE
        PS> Mount-WSLBlobNFS -RemoteMount "mount -t aznfs -o nolock,vers=3,proto=tcp account.blob.preprod.core.windows.net:/account/container /mnt/nfsv3share"
        You can also provide the NFS mount command if you want to provide extra mount parameters.
        Note: MountDrive parameter is optional. If not provided, the drive will be automatically assigned.

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
        # Get the first free drive letter, starting from Z: upto A:
        # 65 is the ASCII value of 'A' and 90 is the ASCII value of 'Z'
        (90..(65)).ForEach({
            if((-not (Get-PSDrive ([char]$_) -ErrorAction SilentlyContinue) -and [string]::IsNullOrWhiteSpace($MountDrive)))
            {
                $MountDrive = [char]$_ + ":"
                Write-Success "Using $MountDrive to mount the share."
            }})

        if([string]::IsNullOrWhiteSpace($MountDrive))
        {
            Write-ErrorLog "No free drive letter found to mount the share."
            return
        }
    }

    # Check if the MountDrive is already in use or not.
    $pathExists = Test-Path "$MountDrive"
    if($pathExists)
    {
        Write-ErrorLog "$MountDrive is in use already."
        return
    }

    # To-do:
    # - Validate the RemoteMount and MountDrive even further.
    # - Check if the RemoteMount is a valid mount command or not.
    # - Check if the RemoteMount is already mounted or not.
    # - Check the exit code of net use command.

    $mountParameterType = ""

    $mountPattern = "mount -t"
    if($RemoteMount.Contains($mountPattern) -and $RemoteMount.IndexOf($mountPattern) -eq 0)
    {
        $mountParameterType = "command"
        if($RemoteMount.Contains("mount -t nfs"))
        {
            Write-ErrorLog "NFS mounts '-t nfs' are not supported. Please use AZNFS mounts with '-t aznfs'."
            return
        }
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

    if($LastExitCode -ne 0)
    {
        Write-ErrorLog "Mounting $RemoteMount failed in WSL."
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
    if($LastExitCode -ne 0)
    {
        Dismount-MountInsideWSL $smbShareName
        Write-ErrorLog "Mounting '$RemoteMount' failed."
        return
    }

    #  Print the mount mappings
    Get-SmbMapping -LocalPath "$MountDrive"

    Write-Success "Mounting SMB share done. Now, you can access the share from $MountDrive."
}

function Register-AutoMountWSLBlobNFS
{
    <#
    .SYNOPSIS
        Resiter a scheduled job to auto mount WSL Blob NFS on startup.

    .DESCRIPTION
        This command requires admin privileges to register a scheduled job to auto mount WSL Blob NFS on startup.

    .EXAMPLE
        PS> Register-AutoMountWSLBlobNFS

    .LINK
        https://github.com/Azure/BlobNFS-wsl2

    .NOTES
        Author:  Azure Blob NFS
        Website: https://github.com/Azure/BlobNFS-wsl2
    #>

    [CmdletBinding()]
    param()

    # Requires admin privileges.
    if(-not ([bool](([System.Security.Principal.WindowsPrincipal] [System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole] "Administrator"))))
    {
        Write-ErrorLog "This command requires admin privileges. Run the command again with admin privileges."
        $global:LastExitCode = 1
        return
    }

    Write-Output "Initializing WSL environment for WSLBlobNFS usage on startup."
    Import-Module PSScheduledJob -Force -Verbose:$false | Out-Null

    # Remove the existing scheduled job if it exists.
    Write-Output "Removing existing scheduled job to auto mount WSL Blob NFS on startup."
    Unregister-ScheduledJob -Name "AutoMountWSLBlobNFS" -ErrorAction SilentlyContinue

    Register-ScheduledJob -Name AutoMountWSLBlobNFS -ScriptBlock {
                    Import-Module WSLBlobNFS -Force
                    Assert-PipelineWSLBlobNFS -Verbose

                    if($LastExitCode -ne 0)
                    {
                        Write-ErrorLog 'Error while mounting Blob NFS share on startup.'
                        return
                    }
                } -Trigger (New-JobTrigger -AtStartup) -ScheduledJobOption (New-ScheduledJobOption -ContinueIfGoingOnBattery -StartIfOnBattery)

    $automnt = Get-ScheduledJob -Name AutoMountWSLBlobNFS -ErrorAction SilentlyContinue
    if($null -eq $automnt)
    {
        Write-ErrorLog "Unable to register a scheduled job to auto mount WSL Blob NFS on startup. Try again with admin privileges."
        return
    }

    Write-Success "Successfully registered a scheduled job to auto mount WSL Blob NFS on startup."
}

function Assert-PipelineWSLBlobNFS
{
    <#
    .SYNOPSIS
        Checks and sets the WSL Blob NFS environment in Windows on startup.

    .DESCRIPTION
        This command initializes WSL on startup and mounts the Blob NFS share for the persistent SMB mappings present in Windows.

    .EXAMPLE
        PS> Assert-PipelineWSLBlobNFS

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

    Initialize-WSLBlobNFS-Internal
    if($LastExitCode -ne 0)
    {
        return
    }

    $smbmappings = Get-SmbMapping

    if($null -eq $smbmappings)
    {
        Write-Success "No WSL Blob NFS share is mounted."
        return
    }

    if($smbmappings.GetType().Name -eq "CimInstance")
    {
        Assert-PipelineWSLBlobNFS-Internal -smbmapping $smbmappings
    }
    else
    {
        $smbmappings.ForEach({
            $smbmapping = $_
            Assert-PipelineWSLBlobNFS-Internal -smbmapping $smbmapping
        })
    }
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
        Write-ErrorLog "Empty or Null mounted drive received."
        return
    }

    $smbmapping = Get-SmbMapping -LocalPath "$MountDrive" -ErrorAction SilentlyContinue

    if($null -eq $smbmapping)
    {
        Write-ErrorLog "No SMB share is mounted on $MountDrive."
        return
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
        Write-ErrorLog "The $MountDrive is not mounted from the current WSL $distroName."
        return
    }

    Invoke-WSL "'$modulePathForLinux/$wslScriptName' unmountshare '$smbexportname'"

    if($LastExitCode -ne 0)
    {
        Write-ErrorLog "Unmounting $MountDrive failed in WSL."
        return
    }

    # Force delete when we have open files in the share.
    net use $MountDrive /delete /yes | Out-Null
    if($LastExitCode -ne 0)
    {
        Write-ErrorLog "Unmounting $MountDrive failed in Windows."
        return
    }
    Write-Success "Unmounting $MountDrive done."
}

# This list overrides the list provided in the module manifest (.psd1) file.
Export-ModuleMember -Function Install-WSLBlobNFS, Initialize-WSLBlobNFS, Mount-WSLBlobNFS, Dismount-WSLBlobNFS, Assert-PipelineWSLBlobNFS, Register-AutoMountWSLBlobNFS
