# --------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
# --------------------------------------------------------------------------------------------

#
# Run the script to test the module for Script Analyzer issues and warnings.
# Fix all the issues and warnings before publishing the module.
#
param(
    [Parameter(Mandatory=$false)]
    [string]$ModulePath = ".\WSLBlobNFS"
)

if(-not (Test-Path $ModulePath))
{
    Write-Error "Path $ModulePath does not exist"
    exit 1
}

# Create a temp out folder to test the module
$tempFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("Temp-" + $ModulePath.Split("\")[-1])
New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null
Copy-Item -Path $ModulePath -Destination $tempFolder -Force -Recurse
Write-Host "Copied the module to temp folder $tempFolder to test the module." -ForegroundColor Green
Write-Host "You can use $tempFolder to for your other tests." -ForegroundColor Green

# Refer to the manifest in the temp folder
$ManifestPath = Join-Path $tempFolder ($ModulePath.Split("\")[-1]) ($ModulePath.Split("\")[-1] + ".psd1")
$ScriptPath = Join-Path $tempFolder ($ModulePath.Split("\")[-1]) ($ModulePath.Split("\")[-1] + ".psm1")
if(-not (Test-Path $ManifestPath) -or -not (Test-Path $ScriptPath))
{
    Write-Error "Manifest or script of the module does not exist. Please check"
    exit 1
}

# Test-ModuleManifest - Validate the module manifest
Write-Host "------------------ Running Test-ModuleManifest ------------------"
$ManifestPath | Test-ModuleManifest -ErrorAction STOP -Verbose
Write-Host "------------------ Test-ModuleManifest completed ------------------" -ForegroundColor Green

# PS Script Analyzer - Validate the module for issues and warnings
$analyzerInstalled = Get-InstalledModule -Name PSScriptAnalyzer 2> $null
if($null -eq $analyzerInstalled)
{
    # Force is required when you have a older version of the module installed.
    # Install-Module -Name PSScriptAnalyzer -Force
}
Import-Module PSScriptAnalyzer -Force
Write-Host "------------------ Running Script Analyzer ------------------"
Invoke-ScriptAnalyzer -Path $ScriptPath
Write-Host "------------------ Script Analyzer completed ------------------" -ForegroundColor Green

# Import the module for external usage
Write-Host "------------------ Importing the module for your usage ------------------"
Import-Module -Name $ManifestPath -Force
Write-Host "------------------ Imported the module for your usage ------------------" -ForegroundColor Green