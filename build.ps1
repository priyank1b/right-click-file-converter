# Builds dist/RightClickConverter.zip and dist/RightClickConverter-Setup.exe
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$files = 'Install.bat', 'Install.ps1', 'Convert.ps1', 'Launch.vbs', 'pdf2docx_run.py', 'Uninstall.bat', 'Uninstall.ps1', 'README.md', 'LICENSE'
foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $f))) { throw "Missing file: $f" }
}

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

function New-Zip([string]$path, [string]$prefix) {
    if (Test-Path -LiteralPath $path) { [IO.File]::Delete($path) }
    $za = [IO.Compression.ZipFile]::Open($path, 'Create')
    try {
        foreach ($f in $files) {
            $entry = if ($prefix) { "$prefix/$f" } else { $f }
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, (Join-Path $root $f), $entry, 'Optimal')
        }
    } finally { $za.Dispose() }
}

# 1) Release zip (files inside a RightClickConverter/ folder, forward-slash paths)
$zip = Join-Path $dist 'RightClickConverter.zip'
New-Zip $zip 'RightClickConverter'

# 2) Self-extracting exe: flat payload embedded in a tiny launcher
$payload = Join-Path $env:TEMP ('rcc_payload_' + [guid]::NewGuid().ToString('N') + '.zip')
New-Zip $payload ''
try {
    $exe = Join-Path $dist 'RightClickConverter-Setup.exe'
    if (Test-Path -LiteralPath $exe) { [IO.File]::Delete($exe) }
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) { throw 'csc.exe (.NET Framework compiler) not found.' }
    & $csc /nologo /target:exe /optimize+ "/out:$exe" "/resource:$payload,payload.zip" `
        /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll `
        (Join-Path $root 'installer\Setup.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Compiling the setup exe failed.' }
} finally {
    Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue
}

# 3) Checksums
$sums = foreach ($f in $zip, $exe) { '{0}  {1}' -f (Get-FileHash $f -Algorithm SHA256).Hash.ToLower(), (Split-Path $f -Leaf) }
Set-Content -Path (Join-Path $dist 'SHA256SUMS.txt') -Value $sums -Encoding ASCII

Write-Host "Built version $version in $dist" -ForegroundColor Green
Get-ChildItem $dist | Select-Object Name, Length
