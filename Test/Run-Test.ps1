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
    [string]$Path = ".\WSLBlobNFS\WSLBlobNFS.psd1"
)

if(-not (Test-Path $Path))
{
    Write-Error "Path $Path does not exist"
    exit 1
}
Write-Host "Using Path $Path."
$analyzerInstalled = Get-InstalledModule -Name PSScriptAnalyzer 2> $null

if($null -eq $analyzerInstalled)
{
    # Force is required when you have a older version of the module installed.
    Install-Module -Name PSScriptAnalyzer -Force
}

Import-Module PSScriptAnalyzer -Force

Write-Host "Running Script Analyzer on $Path"

Invoke-ScriptAnalyzer -Path $Path

Write-Host "Script Analyzer completed on $Path" -ForegroundColor Green

Write-Host "Running Test-ModuleManifest on $Path"

$Path | Test-ModuleManifest -ErrorAction STOP -Verbose

Write-Host "Test-ModuleManifest completed on $Path" -ForegroundColor Green