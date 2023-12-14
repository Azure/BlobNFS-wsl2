# --------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
# --------------------------------------------------------------------------------------------

# To-do:
# - Add connection troubleshooting steps.
# - Add performance troubleshooting steps.

param(
    # SMB Mounted drive
    # [Parameter(Mandatory)]
    # [string]$mountdrive
)

# # Validate the mount drive
# if($mountdrive -eq $null)
# {
#     Write-Host "Mount drive is not specified. Please specify the mount drive."
#     exit
# }

# Output results to file
$filePath = "wslblobnfs-setup-details.txt"

# Collect system info
Write-Host "Collecting system info."
$systemInfo = Get-ComputerInfo | Out-String

# Collect WSL info
Write-Host "Collecting WSL info."
$wslInfo1 = wsl.exe -l -v | Out-String
$wslInfo1Status = $LastExitCode
$wslInfo2 = wsl.exe -v | Out-String
$wslInfo2Status = $LastExitCode

# Collect PowerShell details
Write-Host "Collecting PowerShell details."
$psVersion = $PSVersionTable | Out-String

# Log the details
"SystemInfo: $systemInfo `nwslDistro: $wslInfo1 `nwslInfo1Status: $wslInfo1Status `nwslVersion: $wslInfo2 `nwslInfo2Status:$wslInfo2Status `n$psVersion `n" | Out-File $winTempFilePath

Write-Host "Please share the following diagnostic file with the Azure Support team $filePath."
# # Install fio
# Write-Host "Downloading fio."
# Invoke-WebRequest -Uri https://github.com/axboe/fio/releases/download/fio-3.36/fio-3.36-x64.msi -OutFile fio-3.36-x64.msi

# Write-Host "Installing fio."
# $arguments = "/i `"fio-3.36-x64.msi`""
# Start-Process msiexec.exe -ArgumentList $arguments -Wait

# # Save the current directory
# $dir = $pwd

# # Change the directory to the mount drive
# Set-Location -Path $mountdrive

# Write-host "Mounted directory: $pwd"

# # Run fio
# Write-Host "Running fio write."
# $fiowrite = fio --randrepeat=0 --name=fio-test --filename=fio10g.samba.write1 --bs=1M --direct=1 --numjobs=1 --iodepth=256 --size=10G --rw=write --ioengine=windowsaio | Out-String

# # Log the fio write results
# Set-Location -Path $dir
# "$fiowrite`n" | Out-File $filePath -Append
# Set-Location -Path $mountdrive

# Write-Host "Running fio read."
# $fioread = fio --randrepeat=0 --name=fio-test --filename=fio10g.samba.read134 --bs=1M --numjobs=1 --iodepth=256 --size=10G --rw=read --ioengine=windowsaio | Out-String

# # Change the directory back to the original directory
# Set-Location -Path $dir

# # Log the fio read results
# "$fioread" | Out-File $filePath -Append