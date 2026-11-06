# Builds everything into dist/:
#   RightClickConverter.zip          (Windows)
#   RightClickConverter-Setup.exe    (Windows, self-extracting)
#   RightClickConverter-mac.zip      (macOS)
#   SHA256SUMS.txt
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$latin1 = [Text.Encoding]::GetEncoding(28591)   # byte-preserving

# Read a file as bytes, normalising line endings for text types
function Get-Bytes([string]$path, [string]$eol) {
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($eol -eq 'keep') { return $bytes }
    $s = $latin1.GetString($bytes).Replace("`r`n", "`n")
    if ($eol -eq 'crlf') { $s = $s.Replace("`n", "`r`n") }
    return $latin1.GetBytes($s)
}

# Add an entry from a source file; $entry uses forward slashes; $exec marks it executable for macOS/Linux
function Add-Entry($za, [string]$entry, [string]$path, [string]$eol, [bool]$exec) {
    $e = $za.CreateEntry($entry, [IO.Compression.CompressionLevel]::Optimal)
    $mode = if ($exec) { 0x81ED } else { 0x81A4 }       # 0100755 / 0100644
    $e.ExternalAttributes = ($mode -shl 16)
    $bytes = Get-Bytes $path $eol
    $st = $e.Open()
    try { $st.Write($bytes, 0, $bytes.Length) } finally { $st.Dispose() }
}

function New-Package([string]$zipPath, [string]$prefix, $items) {
    if (Test-Path -LiteralPath $zipPath) { [IO.File]::Delete($zipPath) }
    $za = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
    try {
        foreach ($it in $items) {
            if (-not (Test-Path -LiteralPath $it.src)) { throw "Missing file: $($it.src)" }
            $entry = if ($prefix) { "$prefix/$($it.name)" } else { $it.name }
            Add-Entry $za $entry $it.src $it.eol $it.exec
        }
    } finally { $za.Dispose() }
}

function Item([string]$name, [string]$src, [string]$eol, [bool]$exec = $false) {
    return @{ name = $name; src = $src; eol = $eol; exec = $exec }
}

# ---------------------------------------------------------------- Windows
$win = Join-Path $root 'windows'
$winItems = @(
    (Item 'Install.bat'      (Join-Path $win 'Install.bat')      'crlf'),
    (Item 'Install.ps1'      (Join-Path $win 'Install.ps1')      'crlf'),
    (Item 'Convert.ps1'      (Join-Path $win 'Convert.ps1')      'crlf'),
    (Item 'Launch.vbs'       (Join-Path $win 'Launch.vbs')       'crlf'),
    (Item 'pdf2docx_run.py'  (Join-Path $win 'pdf2docx_run.py')  'lf'),
    (Item 'Uninstall.bat'    (Join-Path $win 'Uninstall.bat')    'crlf'),
    (Item 'Uninstall.ps1'    (Join-Path $win 'Uninstall.ps1')    'crlf'),
    (Item 'README.md'        (Join-Path $win 'README.md')        'crlf'),
    (Item 'LICENSE'          (Join-Path $root 'LICENSE')         'crlf')
)
New-Package (Join-Path $dist 'RightClickConverter.zip') 'RightClickConverter' $winItems

# Self-extracting exe: flat payload embedded in a tiny launcher
$payload = Join-Path $env:TEMP ('rcc_payload_' + [guid]::NewGuid().ToString('N') + '.zip')
New-Package $payload '' $winItems
try {
    $exe = Join-Path $dist 'RightClickConverter-Setup.exe'
    if (Test-Path -LiteralPath $exe) { [IO.File]::Delete($exe) }
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) { throw 'csc.exe (.NET Framework compiler) not found.' }
    & $csc /nologo /target:exe /optimize+ "/out:$exe" "/resource:$payload,payload.zip" `
        /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll `
        (Join-Path $win 'installer\Setup.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Compiling the setup exe failed.' }
} finally {
    Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- macOS
$mac = Join-Path $root 'mac'
$macItems = @(
    (Item 'install.sh'       (Join-Path $mac 'install.sh')       'lf' $true),
    (Item 'uninstall.sh'     (Join-Path $mac 'uninstall.sh')     'lf' $true),
    (Item 'convert.sh'       (Join-Path $mac 'convert.sh')       'lf' $true),
    (Item 'pdf2docx_run.py'  (Join-Path $mac 'pdf2docx_run.py')  'lf'),
    (Item 'README.md'        (Join-Path $mac 'README.md')        'lf'),
    (Item 'LICENSE'          (Join-Path $root 'LICENSE')         'lf')
)
New-Package (Join-Path $dist 'RightClickConverter-mac.zip') 'RightClickConverter-mac' $macItems

# ---------------------------------------------------------------- checksums
$out = @('RightClickConverter.zip', 'RightClickConverter-Setup.exe', 'RightClickConverter-mac.zip') | ForEach-Object {
    '{0}  {1}' -f (Get-FileHash (Join-Path $dist $_) -Algorithm SHA256).Hash.ToLower(), $_
}
Set-Content -Path (Join-Path $dist 'SHA256SUMS.txt') -Value $out -Encoding ASCII

Write-Host "Built version $version in $dist" -ForegroundColor Green
Get-ChildItem $dist | Select-Object Name, Length
