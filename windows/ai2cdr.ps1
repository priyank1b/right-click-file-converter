# Converts an Adobe Illustrator (.ai) file to CorelDRAW (.cdr) by driving CorelDRAW itself.
# Only CorelDRAW can write .cdr files, so it must be installed (full Windows version with automation).
# Usage: ai2cdr.ps1 "<in.ai>" "<out.cdr>"
param([string]$In, [string]$Out)

$ErrorActionPreference = 'Stop'
$wasRunning = [bool](Get-Process -Name 'CorelDRW' -ErrorAction SilentlyContinue)
$app = $null
$doc = $null
try {
    $app = New-Object -ComObject 'CorelDRAW.Application'
    if (-not $wasRunning) { $app.Visible = $false }

    # First try opening the .ai directly (same as File > Open)
    try { $doc = $app.OpenDocument($In) } catch { $doc = $null }

    # Otherwise create a blank document and import into it (same as File > Import)
    if (-not $doc) {
        $doc = $app.CreateDocument()
        $imp = $doc.ActiveLayer.ImportEx($In, 0)   # 0 = cdrAutoSense
        $imp.Finish()
        try {
            # Fit the page to the artwork and centre it
            $sr = $doc.ActivePage.Shapes.All()
            if ($sr.Count -gt 0) {
                $doc.ActivePage.SetSize($sr.SizeWidth, $sr.SizeHeight)
                $sr.AlignToPageCenter(15)            # cdrAlignHCenter + cdrAlignVCenter
            }
        } catch {}
    }

    $doc.SaveAs($Out)
    $doc.Close()
    $doc = $null
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
finally {
    if ($doc) { try { $doc.Close() } catch {} }
    if ($app) {
        if (-not $wasRunning) { try { $app.Quit() } catch {} }
        try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($app) } catch {}
    }
}
