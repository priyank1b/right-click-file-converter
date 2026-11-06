param([string]$Target = '', [Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-Error([string]$text) {
    [void][System.Windows.Forms.MessageBox]::Show($text, 'Convert to...', 'OK', 'Error')
}

function Q([string]$s) { return '"' + $s + '"' }

# Refresh PATH so freshly installed tools are found
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + "$env:LOCALAPPDATA\Microsoft\WinGet\Links"

function Find-Tool([string]$name, [string[]]$extra) {
    $c = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($g in $extra) {
        $m = Get-Item -Path $g -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($m) { return $m.FullName }
    }
    return $null
}

$tools = @{
    ffmpeg  = Find-Tool 'ffmpeg.exe' @("$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gyan.FFmpeg*\ffmpeg-*\bin\ffmpeg.exe")
    magick  = Find-Tool 'magick.exe' @("$env:ProgramFiles\ImageMagick*\magick.exe")
    pandoc  = Find-Tool 'pandoc.exe' @("$env:LOCALAPPDATA\Pandoc\pandoc.exe", "$env:ProgramFiles\Pandoc\pandoc.exe")
    soffice = Find-Tool 'soffice.com' @("$env:ProgramFiles\LibreOffice\program\soffice.com", "${env:ProgramFiles(x86)}\LibreOffice\program\soffice.com", "$env:ProgramFiles\LibreOffice\program\soffice.exe")
}
# Optional: better PDF -> DOCX (pdf2docx in its own Python environment)
$tools.pdfpy = $null
$pyExe = Join-Path $env:LOCALAPPDATA 'RightClickConverter\pyenv\Scripts\python.exe'
$pyRun = Join-Path $PSScriptRoot 'pdf2docx_run.py'
if ((Test-Path -LiteralPath $pyExe) -and (Test-Path -LiteralPath $pyRun)) { $tools.pdfpy = $pyExe }

function Get-Route([string]$ext) {
    switch -Regex ($ext) {
        '^(jpg|jpeg|jfif|png|webp|bmp|gif|tif|tiff|heic|heif|avif|ico)$' { return @{ Kind = 'image'; Targets = @('png', 'jpg', 'webp', 'bmp', 'gif', 'tiff', 'ico', 'pdf') } }
        '^(mp4|mkv|avi|mov|wmv|flv|webm|m4v|mpg|mpeg|3gp|ts|mts|m2ts|vob)$' { return @{ Kind = 'video'; Targets = @('mp4', 'mkv', 'avi', 'mov', 'webm', 'gif', 'mp3', 'wav', 'm4a', 'flac') } }
        '^(mp3|wav|flac|aac|m4a|ogg|opus|wma|aiff|aif)$' { return @{ Kind = 'audio'; Targets = @('mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'opus') } }
        '^(doc|docx|odt|rtf|txt|wpd)$' { return @{ Kind = 'doc'; Targets = @('pdf', 'docx', 'odt', 'rtf', 'txt', 'html') } }
        '^(xls|xlsx|ods|csv)$' { return @{ Kind = 'sheet'; Targets = @('pdf', 'xlsx', 'ods', 'csv', 'html') } }
        '^(ppt|pptx|odp)$' { return @{ Kind = 'slides'; Targets = @('pdf', 'pptx', 'odp') } }
        '^(md|markdown)$' { return @{ Kind = 'md'; Targets = @('docx', 'html', 'txt', 'epub', 'pdf') } }
        '^(html|htm)$' { return @{ Kind = 'html'; Targets = @('docx', 'md', 'txt', 'epub', 'pdf') } }
        '^epub$' { return @{ Kind = 'epub'; Targets = @('docx', 'html', 'md', 'txt') } }
        '^pdf$' { return @{ Kind = 'pdf'; Targets = @('png', 'jpg', 'docx', 'odt', 'txt') } }
    }
    return $null
}

# Which tools a conversion needs
function Get-Needs([string]$kind, [string]$target) {
    switch ($kind) {
        'image' { return @('magick') }
        'video' { return @('ffmpeg') }
        'audio' { return @('ffmpeg') }
        'doc' { return @('soffice') }
        'sheet' { return @('soffice') }
        'slides' { return @('soffice') }
        'md' { if ($target -eq 'pdf') { return @('pandoc', 'soffice') } else { return @('pandoc') } }
        'html' { if ($target -eq 'pdf') { return @('soffice') } else { return @('pandoc') } }
        'epub' { return @('pandoc') }
        'pdf' { if ($target -in 'png', 'jpg') { return @('magick') } else { return @('soffice') } }
    }
}

function Test-Needs([string[]]$needs) {
    foreach ($n in $needs) { if (-not $tools[$n]) { return $false } }
    return $true
}

function Get-FreeName([string]$dir, [string]$base, [string]$ext) {
    $p = Join-Path $dir ($base + '.' + $ext)
    $i = 1
    while (Test-Path -LiteralPath $p) {
        $p = Join-Path $dir ($base + ' (' + $i + ').' + $ext)
        $i++
    }
    return $p
}

function Invoke-Tool([string]$exe, [string]$argLine) {
    $errFile = [IO.Path]::GetTempFileName()
    $outFile = [IO.Path]::GetTempFileName()
    $p = Start-Process -FilePath $exe -ArgumentList $argLine -WindowStyle Hidden -PassThru -RedirectStandardError $errFile -RedirectStandardOutput $outFile
    $null = $p.Handle
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    $p.WaitForExit()
    $err = ''
    try { $err = (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue) } catch {}
    Remove-Item -LiteralPath $errFile, $outFile -Force -ErrorAction SilentlyContinue
    return @{ Code = $p.ExitCode; Err = $err }
}

function Wait-Output([string]$dir, [int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $f = Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) {
            $s1 = $f.Length
            for ($i = 0; $i -lt 10; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
            $f.Refresh()
            if ($f.Length -eq $s1) { return $f.FullName }
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 300
    }
    return $null
}

function Convert-LO([string]$inFile, [string]$fmt, [string]$work, [string]$infilter) {
    $outDir = Join-Path $work 'lo_out'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $loProfile = Join-Path $work 'lo_profile'
    $uri = 'file:///' + (($loProfile -replace '\\', '/') -replace ' ', '%20')
    $argLine = '-env:UserInstallation=' + $uri + ' --headless --norestore'
    if ($infilter) { $argLine += ' --infilter=' + (Q $infilter) }
    $argLine += ' --convert-to ' + (Q $fmt) + ' --outdir ' + (Q $outDir) + ' ' + (Q $inFile)
    $r = Invoke-Tool $tools.soffice $argLine
    $res = Wait-Output $outDir 120
    if (-not $res) { throw ('LibreOffice did not produce a file. ' + $r.Err) }
    return $res
}

# ---------------------------------------------------------------- main
try {
    if (-not $Paths -or -not (Test-Path -LiteralPath $Paths[0])) { Show-Error 'File not found.'; exit 1 }
    $src = (Resolve-Path -LiteralPath $Paths[0]).Path
    $dir = Split-Path $src -Parent
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    $ext = [IO.Path]::GetExtension($src).TrimStart('.').ToLower()
    $fileName = [IO.Path]::GetFileName($src)

    $route = Get-Route $ext
    if (-not $route) { Show-Error ("Sorry, .$ext files are not supported yet."); exit 1 }

    $norm = $ext
    switch ($ext) { 'jpeg' { $norm = 'jpg' } 'jfif' { $norm = 'jpg' } 'tif' { $norm = 'tiff' } 'htm' { $norm = 'html' } 'markdown' { $norm = 'md' } 'aif' { $norm = 'aiff' } 'heif' { $norm = 'heic' } }

    $kind = $route.Kind
    $targets = @()
    foreach ($t in $route.Targets) {
        if ($t -eq $norm) { continue }
        if (Test-Needs (Get-Needs $kind $t)) { $targets += $t }
    }
    if ($targets.Count -eq 0) {
        Show-Error "The tools needed to convert .$ext files are not installed. Run Install.bat again."
        exit 1
    }

    # ---- picker (skipped when a target was passed in, e.g. from the radial menu)
    $t = $null
    if ($Target -and ($targets -contains $Target.ToLower())) { $t = $Target.ToLower() }
    if (-not $t) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Convert to...'
    $f.ClientSize = New-Object System.Drawing.Size(340, 400)
    $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.TopMost = $true
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Convert  $fileName  to:"
    $lbl.Location = New-Object System.Drawing.Point(12, 12)
    $lbl.Size = New-Object System.Drawing.Size(316, 36)
    $lb = New-Object System.Windows.Forms.ListBox
    $lb.Location = New-Object System.Drawing.Point(12, 52)
    $lb.Size = New-Object System.Drawing.Size(316, 290)
    $lb.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    foreach ($t in $targets) {
        $label = $t.ToUpper()
        if ($kind -eq 'video' -and $t -in 'mp3', 'wav', 'm4a', 'flac') { $label += '  (audio only)' }
        if ($kind -eq 'video' -and $t -eq 'gif') { $label += '  (animated)' }
        if ($kind -eq 'pdf' -and $t -in 'png', 'jpg') { $label += '  (one image per page)' }
        if ($kind -eq 'pdf' -and $t -in 'docx', 'odt', 'txt') { $label += '  (approximate)' }
        [void]$lb.Items.Add($label)
    }
    $lb.SelectedIndex = 0
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Convert'
    $ok.Location = New-Object System.Drawing.Point(160, 356)
    $ok.Size = New-Object System.Drawing.Size(80, 28)
    $ok.DialogResult = 'OK'
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Location = New-Object System.Drawing.Point(248, 356)
    $cancel.Size = New-Object System.Drawing.Size(80, 28)
    $cancel.DialogResult = 'Cancel'
    $f.AcceptButton = $ok
    $f.CancelButton = $cancel
    $lb.Add_DoubleClick({ $f.DialogResult = 'OK'; $f.Close() })
    $f.Controls.AddRange(@($lbl, $lb, $ok, $cancel))
    if ($f.ShowDialog() -ne 'OK' -or $lb.SelectedIndex -lt 0) { exit 0 }
    $t = ($lb.SelectedItem -split ' ')[0].ToLower()
    }

    # ---- progress window
    $pf = New-Object System.Windows.Forms.Form
    $pf.Text = 'Converting...'
    $pf.ClientSize = New-Object System.Drawing.Size(380, 80)
    $pf.StartPosition = 'CenterScreen'
    $pf.FormBorderStyle = 'FixedToolWindow'
    $pf.TopMost = $true
    $pl = New-Object System.Windows.Forms.Label
    $pl.Text = "Converting $fileName to $($t.ToUpper())..."
    $pl.Location = New-Object System.Drawing.Point(12, 10)
    $pl.Size = New-Object System.Drawing.Size(356, 22)
    $pb = New-Object System.Windows.Forms.ProgressBar
    $pb.Style = 'Marquee'
    $pb.MarqueeAnimationSpeed = 30
    $pb.Location = New-Object System.Drawing.Point(12, 40)
    $pb.Size = New-Object System.Drawing.Size(356, 22)
    $pf.Controls.AddRange(@($pl, $pb))
    $pf.Show()
    [System.Windows.Forms.Application]::DoEvents()

    $work = Join-Path ([IO.Path]::GetTempPath()) ('rcc_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $final = $null

    try {
        switch ($kind) {
            'image' {
                $out = Join-Path $work ('out.' + $t)
                $frame = $src
                if ($t -notin 'gif', 'pdf', 'tiff') { $frame = $src + '[0]' }
                $opts = ''
                if ($t -in 'jpg', 'bmp') { $opts += ' -background white -alpha remove -alpha off' }
                if ($t -eq 'jpg') { $opts += ' -quality 92' }
                if ($t -eq 'webp') { $opts += ' -quality 90' }
                if ($t -eq 'ico') { $opts += ' -define icon:auto-resize=256,128,64,48,32,16' }
                $r = Invoke-Tool $tools.magick ((Q $frame) + $opts + ' ' + (Q $out))
                if (-not (Test-Path -LiteralPath $out)) { throw ('ImageMagick failed. ' + $r.Err) }
                $final = Get-FreeName $dir $base $t
                Move-Item -LiteralPath $out -Destination $final
            }
            { $_ -in 'video', 'audio' } {
                $out = Join-Path $work ('out.' + $t)
                $o = ''
                switch ($t) {
                    'mp4' { $o = '-c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:a aac -b:a 160k -movflags +faststart' }
                    'mkv' { $o = '-c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:a aac -b:a 160k' }
                    'mov' { $o = '-c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:a aac -b:a 160k' }
                    'avi' { $o = '-c:v mpeg4 -q:v 3 -c:a libmp3lame -q:a 4' }
                    'webm' { $o = '-c:v libvpx-vp9 -crf 32 -b:v 0 -deadline good -cpu-used 5 -c:a libopus -b:a 128k' }
                    'gif' { $o = '-vf "fps=12,scale=480:-1:flags=lanczos" -loop 0 -an' }
                    'mp3' { $o = '-vn -c:a libmp3lame -q:a 2' }
                    'wav' { $o = '-vn' }
                    'flac' { $o = '-vn' }
                    'm4a' { $o = '-vn -c:a aac -b:a 192k' }
                    'aac' { $o = '-vn -c:a aac -b:a 192k' }
                    'ogg' { $o = '-vn -c:a libvorbis -q:a 5' }
                    'opus' { $o = '-vn -c:a libopus -b:a 128k' }
                }
                $r = Invoke-Tool $tools.ffmpeg ('-y -hide_banner -loglevel error -i ' + (Q $src) + ' ' + $o + ' ' + (Q $out))
                if (-not (Test-Path -LiteralPath $out) -or (Get-Item -LiteralPath $out).Length -eq 0) { throw ('ffmpeg failed. ' + $r.Err) }
                $final = Get-FreeName $dir $base $t
                Move-Item -LiteralPath $out -Destination $final
            }
            { $_ -in 'doc', 'sheet', 'slides' } {
                $fmt = $t
                if ($t -eq 'txt') { $fmt = 'txt:Text' }
                $res = Convert-LO $src $fmt $work $null
                $final = Get-FreeName $dir $base $t
                Move-Item -LiteralPath $res -Destination $final
            }
            'html' {
                if ($t -eq 'pdf') {
                    $res = Convert-LO $src 'pdf' $work $null
                    $final = Get-FreeName $dir $base 'pdf'
                    Move-Item -LiteralPath $res -Destination $final
                } else {
                    $out = Join-Path $work ('out.' + $t)
                    $extra = ''
                    if ($t -eq 'md') { $extra = ' -t gfm' }
                    if ($t -eq 'txt') { $extra = ' -t plain' }
                    $r = Invoke-Tool $tools.pandoc ((Q $src) + $extra + ' -o ' + (Q $out))
                    if (-not (Test-Path -LiteralPath $out)) { throw ('Pandoc failed. ' + $r.Err) }
                    $final = Get-FreeName $dir $base $t
                    Move-Item -LiteralPath $out -Destination $final
                }
            }
            { $_ -in 'md', 'epub' } {
                $pandocTarget = $t
                if ($t -eq 'pdf') { $pandocTarget = 'docx' }
                $out = Join-Path $work ('out.' + $pandocTarget)
                $extra = ''
                if ($pandocTarget -eq 'html') { $extra = ' -s' }
                if ($pandocTarget -eq 'md') { $extra = ' -t gfm' }
                if ($pandocTarget -eq 'txt') { $extra = ' -t plain' }
                $r = Invoke-Tool $tools.pandoc ((Q $src) + $extra + ' -o ' + (Q $out))
                if (-not (Test-Path -LiteralPath $out)) { throw ('Pandoc failed. ' + $r.Err) }
                if ($t -eq 'pdf') {
                    $res = Convert-LO $out 'pdf' $work $null
                    $final = Get-FreeName $dir $base 'pdf'
                    Move-Item -LiteralPath $res -Destination $final
                } else {
                    $final = Get-FreeName $dir $base $t
                    Move-Item -LiteralPath $out -Destination $final
                }
            }
            'pdf' {
                if ($t -in 'png', 'jpg') {
                    $pages = Join-Path $work 'pages'
                    New-Item -ItemType Directory -Path $pages -Force | Out-Null
                    $o = '-density 200 ' + (Q $src) + ' -background white -alpha remove -alpha off'
                    if ($t -eq 'jpg') { $o += ' -quality 92' }
                    $r = Invoke-Tool $tools.magick ($o + ' ' + (Q (Join-Path $pages ('p%03d.' + $t))))
                    $made = @(Get-ChildItem -LiteralPath $pages -File | Sort-Object Name)
                    if ($made.Count -eq 0) { throw ('ImageMagick could not read the PDF (is Ghostscript installed?). ' + $r.Err) }
                    if ($made.Count -eq 1) {
                        $final = Get-FreeName $dir $base $t
                        Move-Item -LiteralPath $made[0].FullName -Destination $final
                    } else {
                        $folder = Join-Path $dir ($base + ' pages')
                        $n = 1
                        while (Test-Path -LiteralPath $folder) { $folder = Join-Path $dir ($base + ' pages (' + $n + ')'); $n++ }
                        New-Item -ItemType Directory -Path $folder | Out-Null
                        $i = 1
                        foreach ($m in $made) {
                            Move-Item -LiteralPath $m.FullName -Destination (Join-Path $folder ($base + ' - page ' + $i + '.' + $t))
                            $i++
                        }
                        $final = $folder
                    }
                } elseif ($t -eq 'docx' -and $tools.pdfpy) {
                    $out = Join-Path $work 'out.docx'
                    $r = Invoke-Tool $tools.pdfpy ('-I ' + (Q $pyRun) + ' ' + (Q $src) + ' ' + (Q $out))
                    if (-not (Test-Path -LiteralPath $out) -or (Get-Item -LiteralPath $out).Length -eq 0) {
                        # fall back to LibreOffice
                        $res = Convert-LO $src 'docx:MS Word 2007 XML' $work 'writer_pdf_import'
                    } else { $res = $out }
                    $final = Get-FreeName $dir $base 'docx'
                    Move-Item -LiteralPath $res -Destination $final
                } else {
                    $fmt = $t
                    if ($t -eq 'docx') { $fmt = 'docx:MS Word 2007 XML' }
                    if ($t -eq 'txt') { $fmt = 'txt:Text' }
                    $res = Convert-LO $src $fmt $work 'writer_pdf_import'
                    $final = Get-FreeName $dir $base $t
                    Move-Item -LiteralPath $res -Destination $final
                }
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        $pf.Close()
    }

    # ---- done notification
    $ni = New-Object System.Windows.Forms.NotifyIcon
    $ni.Icon = [System.Drawing.SystemIcons]::Information
    $ni.Visible = $true
    $ni.ShowBalloonTip(4000, 'Converted', ('Saved as ' + (Split-Path $final -Leaf)), 'Info')
    $end = (Get-Date).AddSeconds(4)
    while ((Get-Date) -lt $end) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
    $ni.Dispose()
}
catch {
    Show-Error ("Conversion failed:`r`n`r`n" + $_.Exception.Message)
    exit 1
}
