param(
    [ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64',
    [string]$Version = '1.0.0',
    [string]$OutputDirectory = 'release'
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
if ($Version -notmatch '^\d+\.\d+\.\d+(-[a-zA-Z0-9.-]+)?$') { throw 'Invalid version' }
$output = Join-Path $OutputDirectory $Runtime
dotnet publish windows/CPAMPMonitor/CPAMPMonitor.csproj -c Release -r $Runtime --self-contained true -p:Version=$Version -p:DebugType=None -o $output
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed' }

# Verify the packaged native apphost, not just the managed assembly.
$bytes = [IO.File]::ReadAllBytes((Join-Path $output 'CPAMPMonitor.exe'))
$pe = [BitConverter]::ToInt32($bytes, 0x3c)
$machine = [BitConverter]::ToUInt16($bytes, $pe + 4)
$expected = if ($Runtime -eq 'win-x64') { 0x8664 } else { 0xAA64 }
if ($machine -ne $expected) { throw 'Unexpected executable architecture' }
Copy-Item LICENSE (Join-Path $output 'LICENSE.txt')
Copy-Item windows/README.md (Join-Path $output 'README.md')
Copy-Item windows/README_CN.md (Join-Path $output 'README_CN.md')
$archive = Join-Path $OutputDirectory "CPAMP-Monitor-$Version-$Runtime.zip"
Compress-Archive -Path "$output/*" -DestinationPath $archive -Force
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([IO.Path]::GetFileName($archive))" | Set-Content "$archive.sha256" -Encoding ascii
Write-Output "Built $archive"
