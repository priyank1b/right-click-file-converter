param([switch]$DryRun)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# Re-launch as administrator if needed
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $DryRun) {
    Start-Process powershell -Verb RunAs -Wait -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"')
    exit
}

Write-Host ''
Write-Host '=== Right-click "Convert to..." installer ===' -ForegroundColor Cyan
if ($DryRun) { Write-Host '(dry run: nothing will be installed)' -ForegroundColor Magenta }
Write-Host ''

$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
$tmp = Join-Path $env:TEMP 'RightClickConverterSetup'
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$failed = @()

# ------------------------------------------------------------ helpers
function Find-First([string[]]$patterns) {
    foreach ($p in $patterns) {
        $m = Get-Item -Path $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($m) { return $m.FullName }
    }
    return $null
}

function Test-Cmd([string]$name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }

function Get-RealPython {
    # Ignore the Microsoft Store "python.exe" stub that only opens the Store
    $cands = @(
        "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe",
        "$env:ProgramFiles\Python3*\python.exe"
    )
    $p = Find-First $cands
    if ($p) { return $p }
    $c = Get-Command python -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'WindowsApps' } | Select-Object -First 1
    if ($c) { return $c.Source }
    $py = Get-Command py -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($py) {
        $exe = & $py.Source -3 -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0 -and $exe) { return $exe.Trim() }
    }
    return $null
}

# Download with resume + retries (handles flaky connections and stalls)
function Get-File([string]$url, [string]$dest, [int]$tries = 15) {
    for ($i = 1; $i -le $tries; $i++) {
        & curl.exe -sS -L -C - --connect-timeout 30 --speed-time 30 --speed-limit 5000 -o $dest $url
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $dest)) { return $true }
        Write-Host ('    connection problem, retrying (' + $i + '/' + $tries + ')...') -ForegroundColor DarkYellow
        Start-Sleep -Seconds 3
    }
    return $false
}

function Install-Winget([string]$id) {
    if (-not $hasWinget) { return $false }
    for ($i = 1; $i -le 3; $i++) {
        winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
        # 0 = ok; -1978335189 = already installed / no applicable upgrade
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) { return $true }
        Write-Host ('    attempt ' + $i + ' failed (code ' + $LASTEXITCODE + ')') -ForegroundColor DarkYellow
        Start-Sleep -Seconds 3
    }
    return $false
}

function Install-LibreOfficeDirect {
    Write-Host '    trying direct download from libreoffice.org...' -ForegroundColor Yellow
    try {
        $idx = (Invoke-WebRequest -UseBasicParsing 'https://download.documentfoundation.org/libreoffice/stable/').Content
        $ver = [regex]::Matches($idx, 'href="(\d+\.\d+\.\d+)/"') | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending | Select-Object -First 1
        if (-not $ver) { return $false }
        $url = "https://download.documentfoundation.org/libreoffice/stable/$ver/win/x86_64/LibreOffice_${ver}_Win_x86-64.msi"
        $msi = Join-Path $tmp "LibreOffice_$ver.msi"
        if (-not (Get-File $url $msi)) { return $false }
        $sig = Get-AuthenticodeSignature $msi
        if ($sig.Status -ne 'Valid') { Write-Host '    downloaded file failed the signature check' -ForegroundColor Red; return $false }
        $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestore" -Wait -PassThru
        return ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010)
    } catch { return $false }
}

function Install-GhostscriptDirect {
    Write-Host '    downloading from the official Ghostscript releases...' -ForegroundColor Yellow
    try {
        $r = Invoke-RestMethod 'https://api.github.com/repos/ArtifexSoftware/ghostpdl-downloads/releases/latest' -Headers @{ 'User-Agent' = 'RightClickConverter' }
        $a = $r.assets | Where-Object { $_.name -match '^gs\d+w64\.exe$' } | Select-Object -First 1
        if (-not $a) { return $false }
        $exe = Join-Path $tmp $a.name
        if (-not (Get-File $a.browser_download_url $exe)) { return $false }
        $p = Start-Process $exe -ArgumentList '/S' -Wait -PassThru
        return ($p.ExitCode -eq 0)
    } catch { return $false }
}

function Ensure([string]$label, [scriptblock]$isInstalled, [scriptblock]$install) {
    Write-Host ('--> ' + $label) -ForegroundColor Yellow
    if (& $isInstalled) { Write-Host '    already installed' -ForegroundColor Green; return }
    if ($DryRun) { Write-Host '    would install' -ForegroundColor Magenta; return }
    $ok = & $install
    if ($ok -and (& $isInstalled)) { Write-Host '    installed' -ForegroundColor Green }
    else {
        # a fresh install may not be visible until PATH refresh; re-check after refreshing
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($ok -and (& $isInstalled)) { Write-Host '    installed' -ForegroundColor Green }
        else { Write-Host '    FAILED' -ForegroundColor Red; $script:failed += $label }
    }
}

if (-not $hasWinget) {
    Write-Host 'Note: winget was not found. Some tools will be downloaded directly; for the rest install "App Installer" from the Microsoft Store and run this again.' -ForegroundColor DarkYellow
}

# ------------------------------------------------------------ tools
Ensure 'ffmpeg (video and audio)' {
    (Test-Cmd ffmpeg) -or (Find-First @("$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gyan.FFmpeg*\ffmpeg-*\bin\ffmpeg.exe", "$env:LOCALAPPDATA\Microsoft\WinGet\Links\ffmpeg.exe"))
} { Install-Winget 'Gyan.FFmpeg' }

Ensure 'ImageMagick (images)' {
    (Test-Cmd magick) -or (Find-First @("$env:ProgramFiles\ImageMagick*\magick.exe"))
} { Install-Winget 'ImageMagick.ImageMagick' }

Ensure 'Pandoc (Markdown, HTML, EPUB)' {
    (Test-Cmd pandoc) -or (Find-First @("$env:LOCALAPPDATA\Pandoc\pandoc.exe", "$env:ProgramFiles\Pandoc\pandoc.exe"))
} { Install-Winget 'JohnMacFarlane.Pandoc' }

Ensure 'Ghostscript (PDF to image)' {
    (Test-Cmd gswin64c) -or (Find-First @("$env:ProgramFiles\gs\gs*\bin\gswin64c.exe"))
} { Install-GhostscriptDirect }

Ensure 'LibreOffice (Word, Excel, PowerPoint, CSV, PDF) - large download' {
    Find-First @("$env:ProgramFiles\LibreOffice\program\soffice.exe", "${env:ProgramFiles(x86)}\LibreOffice\program\soffice.exe")
} { (Install-Winget 'TheDocumentFoundation.LibreOffice') -or (Install-LibreOfficeDirect) }

Ensure 'Python (needed for better PDF to Word)' {
    Get-RealPython
} { Install-Winget 'Python.Python.3.12' }

# ------------------------------------------------------------ converter files
$dest = Join-Path $env:LOCALAPPDATA 'RightClickConverter'
if (-not $DryRun) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    foreach ($f in 'Convert.ps1', 'Launch.vbs', 'pdf2docx_run.py') {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination $dest -Force
    }

    # pdf2docx in a private Python environment (LibreOffice is the fallback if this fails)
    $venvPy = Join-Path $dest 'pyenv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $venvPy)) {
        $py = Get-RealPython
        if ($py) {
            Write-Host '--> pdf2docx (better PDF to Word)' -ForegroundColor Yellow
            & $py -m venv (Join-Path $dest 'pyenv')
            & $venvPy -m pip install --quiet --disable-pip-version-check --retries 5 --timeout 60 pdf2docx
            if ($LASTEXITCODE -eq 0) { Write-Host '    installed' -ForegroundColor Green }
            else { Write-Host '    could not install - PDF to Word will use LibreOffice (lower quality)' -ForegroundColor DarkYellow }
        } else {
            Write-Host 'Python not available - PDF to Word will use LibreOffice (lower quality).' -ForegroundColor DarkYellow
        }
    }

    # Add the right-click entry for all files (current user only)
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Classes\*\shell\ConvertTo')
    $key.SetValue('', 'Convert to...')
    $cmdKey = $key.CreateSubKey('command')
    $cmdKey.SetValue('', ('wscript.exe "' + (Join-Path $dest 'Launch.vbs') + '" "%1"'))
    $cmdKey.Close()
    $key.Close()
    Write-Host ''
    Write-Host 'Right-click entry added.' -ForegroundColor Green

    # Optional: classic right-click menu on Windows 11
    Write-Host ''
    Write-Host 'On Windows 11 the entry sits under "Show more options" (or Shift + right-click).' -ForegroundColor Cyan
    $ans = Read-Host 'Make Windows 11 always show the full classic right-click menu? (y/n)'
    if ($ans -match '^[Yy]') {
        $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32')
        $k.SetValue('', '')
        $k.Close()
        Write-Host 'Restarting File Explorer...'
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host 'These did not install - check your internet connection and run Install.bat again (finished items are skipped):' -ForegroundColor Red
    $failed | ForEach-Object { Write-Host ('  - ' + $_) -ForegroundColor Red }
} else {
    Write-Host 'All done. Right-click any file > Convert to...' -ForegroundColor Green
}
if (-not $DryRun) { Read-Host 'Press Enter to close' }
