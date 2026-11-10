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
# Ghostscript reads Illustrator (.ai) files
$tools.gs = Find-Tool 'gswin64c.exe' @("$env:ProgramFiles\gs\gs*\bin\gswin64c.exe", "${env:ProgramFiles(x86)}\gs\gs*\bin\gswin32c.exe")
# AI -> SVG uses PyMuPDF from the same Python environment
$tools.svgpy = $null
$svgRun = Join-Path $PSScriptRoot 'ai_svg_run.py'
$pyMu = Join-Path $env:LOCALAPPDATA 'RightClickConverter\pyenv\Lib\site-packages\pymupdf'
if ((Test-Path -LiteralPath $pyExe) -and (Test-Path -LiteralPath $svgRun) -and (Test-Path -LiteralPath $pyMu)) { $tools.svgpy = $pyExe }
# AI -> CDR needs CorelDRAW itself (only it can write .cdr files)
$tools.corel = $null
$cdrRun = Join-Path $PSScriptRoot 'ai2cdr.ps1'
if ((Test-Path -LiteralPath 'Registry::HKEY_CLASSES_ROOT\CorelDRAW.Application\CLSID') -and (Test-Path -LiteralPath $cdrRun)) { $tools.corel = 'corel' }

function Get-Route([string]$ext) {
    switch -Regex ($ext) {
        '^(jpg|jpeg|jfif|png|webp|bmp|gif|tif|tiff|heic|heif|avif|ico)$' { return @{ Kind = 'image'; Targets = @('png', 'jpg', 'webp', 'bmp', 'gif', 'tiff', 'ico', 'pdf', 'resize') } }
        '^(mp4|mkv|avi|mov|wmv|flv|webm|m4v|mpg|mpeg|3gp|ts|mts|m2ts|vob)$' { return @{ Kind = 'video'; Targets = @('mp4', 'mkv', 'avi', 'mov', 'webm', 'gif', 'mp3', 'wav', 'm4a', 'flac') } }
        '^(mp3|wav|flac|aac|m4a|ogg|opus|wma|aiff|aif)$' { return @{ Kind = 'audio'; Targets = @('mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'opus') } }
        '^(doc|docx|odt|rtf|txt|wpd)$' { return @{ Kind = 'doc'; Targets = @('pdf', 'docx', 'odt', 'rtf', 'txt', 'html') } }
        '^(xls|xlsx|ods|csv)$' { return @{ Kind = 'sheet'; Targets = @('pdf', 'xlsx', 'ods', 'csv', 'html') } }
        '^(ppt|pptx|odp)$' { return @{ Kind = 'slides'; Targets = @('pdf', 'pptx', 'odp') } }
        '^(md|markdown)$' { return @{ Kind = 'md'; Targets = @('docx', 'html', 'txt', 'epub', 'pdf') } }
        '^(html|htm)$' { return @{ Kind = 'html'; Targets = @('docx', 'md', 'txt', 'epub', 'pdf') } }
        '^epub$' { return @{ Kind = 'epub'; Targets = @('docx', 'html', 'md', 'txt') } }
        '^pdf$' { return @{ Kind = 'pdf'; Targets = @('png', 'jpg', 'docx', 'odt', 'txt') } }
        '^ai$' { return @{ Kind = 'ai'; Targets = @('cdr', 'svg', 'pdf', 'eps', 'png', 'jpg') } }
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
        'ai' {
            if ($target -eq 'cdr') { return @('corel') }
            if ($target -eq 'svg') { return @('gs', 'svgpy') }
            return @('gs')
        }
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

function Invoke-Tool([string]$exe, [string]$argLine, [int]$timeoutSec = 0) {
    $errFile = [IO.Path]::GetTempFileName()
    $outFile = [IO.Path]::GetTempFileName()
    $p = Start-Process -FilePath $exe -ArgumentList $argLine -WindowStyle Hidden -PassThru -RedirectStandardError $errFile -RedirectStandardOutput $outFile
    $null = $p.Handle
    $deadline = $null
    if ($timeoutSec -gt 0) { $deadline = (Get-Date).AddSeconds($timeoutSec) }
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
        if ($deadline -and (Get-Date) -gt $deadline) {
            try { $p.Kill() } catch {}
            Remove-Item -LiteralPath $errFile, $outFile -Force -ErrorAction SilentlyContinue
            return @{ Code = -1; Err = "Timed out after $timeoutSec seconds." }
        }
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

# Move one or more page files next to the source: one file as-is, several into a "<name> pages" folder
function Save-Pages([object[]]$made, [string]$dir, [string]$base, [string]$t) {
    if ($made.Count -eq 1) {
        $dest = Get-FreeName $dir $base $t
        Move-Item -LiteralPath $made[0].FullName -Destination $dest
        return $dest
    }
    $label = $base + ' ' + $t.ToUpper() + ' files'
    $folder = Join-Path $dir $label
    $n = 1
    while (Test-Path -LiteralPath $folder) { $folder = Join-Path $dir ($label + ' (' + $n + ')'); $n++ }
    New-Item -ItemType Directory -Path $folder | Out-Null
    $i = 1
    foreach ($m in $made) {
        Move-Item -LiteralPath $m.FullName -Destination (Join-Path $folder ($base + ' - artboard ' + $i + '.' + $t))
        $i++
    }
    return $folder
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

# ---------------------------------------------------------------- resize (images)
function Format-Bytes([int64]$n) {
    if ($n -ge 1MB) { return ('{0:N1} MB' -f ($n / 1MB)) }
    return ('{0:N0} KB' -f [math]::Ceiling($n / 1KB))
}

# Asks how to resize. Returns $null on cancel, otherwise
#   @{ Mode = keep|px|pct; W; H; Prop; Pct; SizeBytes (0 = no limit); Fmt = keep|jpg|png|webp }
function Show-ResizeDialog([int]$count, [string]$name) {
    function C([string]$type, [string]$n, [string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
        $c = New-Object ('System.Windows.Forms.' + $type)
        $c.Name = $n
        $c.Text = $text
        $c.Location = New-Object System.Drawing.Point($x, $y)
        $c.Size = New-Object System.Drawing.Size($w, $h)
        return $c
    }
    $f = New-Object System.Windows.Forms.Form
    $f.Name = 'rzForm'
    $f.Text = 'Resize'
    $f.ClientSize = New-Object System.Drawing.Size(380, 432)
    $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.TopMost = $true

    $what = $name
    if ($count -gt 1) { $what = "$count images" }
    $lbl = C 'Label' 'lbl' ("Resize  " + $what) 12 12 356 36

    $g1 = C 'GroupBox' 'g1' 'Size in pixels' 12 52 356 156
    $rbKeep = C 'RadioButton' 'rbKeep' 'Keep original size' 14 24 200 22
    $rbKeep.Checked = $true
    $rbPx = C 'RadioButton' 'rbPx' 'Width x Height' 14 52 120 22
    $txtW = C 'TextBox' 'txtW' '' 140 50 62 24
    $lx = C 'Label' 'lblx' 'x' 208 54 14 20
    $txtH = C 'TextBox' 'txtH' '' 226 50 62 24
    $lpx = C 'Label' 'lblpx' 'px' 294 54 24 20
    $cbProp = C 'CheckBox' 'cbProp' 'Keep proportions (an empty box is worked out)' 32 80 316 22
    $cbProp.Checked = $true
    $rbPct = C 'RadioButton' 'rbPct' 'Percent of original' 14 112 124 22
    $txtPct = C 'TextBox' 'txtPct' '50' 140 110 62 24
    $lpc = C 'Label' 'lblpc' '%' 208 114 14 20
    $g1.Controls.AddRange(@($rbKeep, $rbPx, $txtW, $lx, $txtH, $lpx, $cbProp, $rbPct, $txtPct, $lpc))

    $g2 = C 'GroupBox' 'g2' 'File size' 12 216 356 82
    $cbSize = C 'CheckBox' 'cbSize' 'Make file smaller than' 14 24 150 22
    $txtSize = C 'TextBox' 'txtSize' '200' 170 22 62 24
    $cmbUnit = C 'ComboBox' 'cmbUnit' '' 238 22 62 24
    $cmbUnit.DropDownStyle = 'DropDownList'
    [void]$cmbUnit.Items.AddRange(@('KB', 'MB'))
    $cmbUnit.SelectedIndex = 0
    $hint = C 'Label' 'hint' 'Works with JPG and WebP. Other formats switch to JPG.' 14 52 334 20
    $hint.ForeColor = [System.Drawing.Color]::Gray
    $g2.Controls.AddRange(@($cbSize, $txtSize, $cmbUnit, $hint))

    $g3 = C 'GroupBox' 'g3' 'Save as' 12 306 356 58
    $cmbFmt = C 'ComboBox' 'cmbFmt' '' 14 24 220 24
    $cmbFmt.DropDownStyle = 'DropDownList'
    [void]$cmbFmt.Items.AddRange(@('Same format as original', 'JPG', 'PNG', 'WEBP'))
    $cmbFmt.SelectedIndex = 0
    $g3.Controls.Add($cmbFmt)

    $ok = C 'Button' 'btnOk' 'Resize' 196 384 80 28
    $cancel = C 'Button' 'btnCancel' 'Cancel' 288 384 80 28
    $cancel.DialogResult = 'Cancel'
    $f.AcceptButton = $ok
    $f.CancelButton = $cancel
    $f.Controls.AddRange(@($lbl, $g1, $g2, $g3, $ok, $cancel))

    $update = {
        $txtW.Enabled = $rbPx.Checked
        $txtH.Enabled = $rbPx.Checked
        $cbProp.Enabled = $rbPx.Checked
        $txtPct.Enabled = $rbPct.Checked
        $txtSize.Enabled = $cbSize.Checked
        $cmbUnit.Enabled = $cbSize.Checked
    }.GetNewClosure()
    $rbKeep.Add_CheckedChanged($update)
    $rbPx.Add_CheckedChanged($update)
    $rbPct.Add_CheckedChanged($update)
    $cbSize.Add_CheckedChanged($update)
    & $update

    # a hashtable is shared by reference with the click handler's closure ($script: variables are not)
    $state = @{ Result = $null }
    $ok.Add_Click({
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $r = @{ Mode = 'keep'; W = 0; H = 0; Prop = $true; Pct = 100.0; SizeBytes = [int64]0; Fmt = 'keep' }
        if ($rbPx.Checked) {
            $w = 0; $h = 0
            $wt = $txtW.Text.Trim(); $ht = $txtH.Text.Trim()
            if ($wt -eq '' -and $ht -eq '') { [void][System.Windows.Forms.MessageBox]::Show('Enter a width, a height, or both.', 'Resize'); return }
            if ($wt -ne '' -and -not ([int]::TryParse($wt, [ref]$w) -and $w -ge 1 -and $w -le 30000)) { [void][System.Windows.Forms.MessageBox]::Show('The width must be a whole number of pixels.', 'Resize'); return }
            if ($ht -ne '' -and -not ([int]::TryParse($ht, [ref]$h) -and $h -ge 1 -and $h -le 30000)) { [void][System.Windows.Forms.MessageBox]::Show('The height must be a whole number of pixels.', 'Resize'); return }
            if (-not $cbProp.Checked -and ($w -lt 1 -or $h -lt 1)) { [void][System.Windows.Forms.MessageBox]::Show('For an exact size, fill in both width and height (or turn on Keep proportions).', 'Resize'); return }
            $r.Mode = 'px'; $r.W = $w; $r.H = $h; $r.Prop = $cbProp.Checked
        } elseif ($rbPct.Checked) {
            $p = 0.0
            if (-not ([double]::TryParse($txtPct.Text.Trim().Replace(',', '.'), [Globalization.NumberStyles]::Float, $inv, [ref]$p) -and $p -gt 0 -and $p -le 1000)) { [void][System.Windows.Forms.MessageBox]::Show('Enter a percent between 1 and 1000.', 'Resize'); return }
            $r.Mode = 'pct'; $r.Pct = $p
        }
        if ($cbSize.Checked) {
            $s = 0.0
            if (-not ([double]::TryParse($txtSize.Text.Trim().Replace(',', '.'), [Globalization.NumberStyles]::Float, $inv, [ref]$s) -and $s -gt 0)) { [void][System.Windows.Forms.MessageBox]::Show('Enter the file size limit as a number.', 'Resize'); return }
            $mult = 1024
            if ($cmbUnit.SelectedItem -eq 'MB') { $mult = 1048576 }
            $bytes = [int64]($s * $mult)
            if ($bytes -lt 1024) { [void][System.Windows.Forms.MessageBox]::Show('The file size limit must be at least 1 KB.', 'Resize'); return }
            $r.SizeBytes = $bytes
        }
        if ($r.Mode -eq 'keep' -and $r.SizeBytes -eq 0 -and $cmbFmt.SelectedIndex -eq 0) {
            [void][System.Windows.Forms.MessageBox]::Show('Choose a new size, a file size limit, or a different format.', 'Resize'); return
        }
        $r.Fmt = @('keep', 'jpg', 'png', 'webp')[$cmbFmt.SelectedIndex]
        $state.Result = $r
        $f.DialogResult = 'OK'
    }.GetNewClosure())

    $answer = $f.ShowDialog()
    $res = $state.Result
    $f.Dispose()
    if ($answer -ne 'OK') { return $null }
    return $res
}

# Resizes one image (and tries to fit a file size limit for JPG / WebP). Returns @{ Bytes; Reached }
function Invoke-Resize([string]$src, [string]$out, [string]$fmt, $o) {
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $srcExt = [IO.Path]::GetExtension($src).TrimStart('.').ToLower()
    $anim = ($fmt -eq 'gif' -and $srcExt -eq 'gif')
    $frame = $src + '[0]'
    if ($anim) { $frame = $src }
    $first = ' -auto-orient'
    if ($anim) { $first += ' -coalesce' }
    if ($o.Mode -eq 'px') {
        $w = ''; if ($o.W -gt 0) { $w = [string]$o.W }
        $h = ''; if ($o.H -gt 0) { $h = [string]$o.H }
        $flag = ''; if (-not $o.Prop) { $flag = '!' }
        $first += ' -resize ' + $w + 'x' + $h + $flag
    } elseif ($o.Mode -eq 'pct') {
        $first += ' -resize ' + ([double]$o.Pct).ToString('0.##', $inv) + '%'
    }
    $fmtOpts = ''
    if ($fmt -in 'jpg', 'bmp') { $fmtOpts += ' -background white -alpha remove -alpha off' }
    $target = [int64]$o.SizeBytes
    $scale = 100.0
    $tries = 1
    if ($target -gt 0) { $tries = 14 }
    $size = [int64]0
    for ($i = 0; $i -lt $tries; $i++) {
        $line = (Q $frame) + $first
        if ($i -gt 0) { $line += ' -resize ' + $scale.ToString('0.#', $inv) + '%' }
        $line += $fmtOpts
        if ($target -gt 0) { $line += ' -strip' }
        if ($fmt -eq 'jpg') {
            $line += ' -quality 92'
            if ($target -gt 0) { $line += ' -define jpeg:extent=' + [math]::Max(1, [int][math]::Floor($target / 1KB)) + 'KB' }
        } elseif ($fmt -eq 'webp') {
            $line += ' -quality 90'
            if ($target -gt 0) { $line += ' -define webp:target-size=' + $target }
        }
        if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
        $r = Invoke-Tool $tools.magick ($line + ' ' + (Q $out)) 180
        if (-not (Test-Path -LiteralPath $out) -or (Get-Item -LiteralPath $out).Length -eq 0) { throw ('ImageMagick failed. ' + $r.Err) }
        $size = (Get-Item -LiteralPath $out).Length
        if ($target -le 0 -or $size -le $target) { return @{ Bytes = $size; Reached = $true } }
        # still too big: shrink the pixels a bit more and try again
        $ratio = [math]::Sqrt($target / $size) * 0.97
        $scale = $scale * [math]::Max(0.5, [math]::Min(0.92, $ratio))
        if ($scale -lt 3) { break }
    }
    return @{ Bytes = $size; Reached = $false }
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
        if ($kind -eq 'ai' -and $t -eq 'cdr') { $label += '  (CorelDRAW)' }
        if ($kind -eq 'image' -and $t -eq 'resize') { $label += '  (pixels or file size)' }
        if ($kind -eq 'ai' -and $t -in 'svg', 'eps', 'png', 'jpg') { $label += '  (one per artboard)' }
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

    # ---- resize options (asked once for the whole selection)
    $rz = $null
    $summary = $null
    if ($kind -eq 'image' -and $t -eq 'resize') {
        $rz = Show-ResizeDialog $Paths.Count $fileName
        if (-not $rz) { exit 0 }
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
    if ($rz) { $pl.Text = 'Resizing ' + $fileName + '...'; if ($Paths.Count -gt 1) { $pl.Text = 'Resizing ' + $Paths.Count + ' images...' } }
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
              if ($rz) {
                $made = @()
                $notes = @()
                $lastBytes = 0
                foreach ($p in $Paths) {
                    if (-not (Test-Path -LiteralPath $p)) { continue }
                    $sp = (Resolve-Path -LiteralPath $p).Path
                    $d2 = Split-Path $sp -Parent
                    $b2 = [IO.Path]::GetFileNameWithoutExtension($sp)
                    $e2 = [IO.Path]::GetExtension($sp).TrimStart('.').ToLower()
                    if ($e2 -in 'jpeg', 'jfif') { $e2 = 'jpg' } elseif ($e2 -eq 'tif') { $e2 = 'tiff' }
                    $fmtSel = $rz.Fmt
                    if ($fmtSel -eq 'keep') {
                        $fmtSel = $e2
                        if ($fmtSel -notin 'jpg', 'png', 'webp', 'bmp', 'gif', 'tiff') { $fmtSel = 'jpg' }
                    }
                    # a file size limit only works for formats that can trade quality for size
                    if ($rz.SizeBytes -gt 0 -and $fmtSel -notin 'jpg', 'webp') { $fmtSel = 'jpg' }
                    $out = Join-Path $work ('r' + $made.Count + '.' + $fmtSel)
                    $res = Invoke-Resize $sp $out $fmtSel $rz
                    $dest = Get-FreeName $d2 ($b2 + ' (resized)') $fmtSel
                    Move-Item -LiteralPath $out -Destination $dest
                    $made += $dest
                    $lastBytes = $res.Bytes
                    if (-not $res.Reached) { $notes += ((Split-Path $dest -Leaf) + ' is ' + (Format-Bytes $res.Bytes)) }
                }
                if ($made.Count -eq 0) { throw 'No files found to resize.' }
                $final = $made[$made.Count - 1]
                if ($made.Count -eq 1) { $summary = 'Saved as ' + (Split-Path $final -Leaf) + ' (' + (Format-Bytes $lastBytes) + ')' }
                else { $summary = ([string]$made.Count) + ' images resized' }
                if ($notes.Count -gt 0) { $summary += '. Could not get under ' + (Format-Bytes $rz.SizeBytes) + ': ' + ($notes -join ', ') }
              } else {
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
            'ai' {
                if ($t -eq 'cdr') {
                    $out = Join-Path $work 'out.cdr'
                    $r = Invoke-Tool 'powershell.exe' ('-NoProfile -ExecutionPolicy Bypass -File ' + (Q $cdrRun) + ' ' + (Q $src) + ' ' + (Q $out)) 300
                    if (-not (Test-Path -LiteralPath $out) -or (Get-Item -LiteralPath $out).Length -eq 0) { throw ('CorelDRAW could not convert the file. ' + $r.Err) }
                    $final = Get-FreeName $dir $base 'cdr'
                    Move-Item -LiteralPath $out -Destination $final
                } else {
                    $pages = Join-Path $work 'pages'
                    New-Item -ItemType Directory -Path $pages -Force | Out-Null
                    $gsOpts = '-dSAFER -q -dNOPAUSE -dBATCH'
                    switch ($t) {
                        'pdf' { $dev = '-sDEVICE=pdfwrite'; $pat = 'p.pdf' }
                        'svg' { $dev = '-sDEVICE=pdfwrite'; $pat = 'clean.pdf' }
                        'eps' { $dev = '-sDEVICE=eps2write'; $pat = 'p%03d.eps' }
                        'png' { $dev = '-sDEVICE=pngalpha -r300 -dTextAlphaBits=4 -dGraphicsAlphaBits=4'; $pat = 'p%03d.png' }
                        'jpg' { $dev = '-sDEVICE=jpeg -dJPEGQ=92 -r300 -dTextAlphaBits=4 -dGraphicsAlphaBits=4'; $pat = 'p%03d.jpg' }
                    }
                    $gsDir = $pages
                    if ($t -eq 'svg') { $gsDir = $work }
                    $r = Invoke-Tool $tools.gs ($gsOpts + ' ' + $dev + ' -sOutputFile=' + (Q (Join-Path $gsDir $pat)) + ' ' + (Q $src)) 300
                    if ($t -eq 'svg') {
                        $clean = Join-Path $work 'clean.pdf'
                        if (-not (Test-Path -LiteralPath $clean)) { throw ('Ghostscript could not read the .ai file (it may be an old, non-PDF-compatible file). ' + $r.Err) }
                        $r = Invoke-Tool $tools.svgpy ('-I ' + (Q $svgRun) + ' ' + (Q $clean) + ' ' + (Q $pages)) 300
                    }
                    $made = @(Get-ChildItem -LiteralPath $pages -File | Where-Object { $_.Length -gt 0 } | Sort-Object Name)
                    if ($made.Count -eq 0) { throw ('Could not read the .ai file (it may be an old, non-PDF-compatible file). ' + $r.Err) }
                    $final = Save-Pages $made $dir $base $t
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
    $doneText = 'Saved as ' + (Split-Path $final -Leaf)
    if ($summary) { $doneText = $summary }
    $ni.ShowBalloonTip(5000, 'Converted', $doneText, 'Info')
    $end = (Get-Date).AddSeconds(4)
    while ((Get-Date) -lt $end) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
    $ni.Dispose()
}
catch {
    Show-Error ("Conversion failed:`r`n`r`n" + $_.Exception.Message)
    exit 1
}
