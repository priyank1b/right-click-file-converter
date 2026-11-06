$ErrorActionPreference = 'Continue'

# Remove the right-click entry and the converter files (installed tools are left alone)
[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\Classes\*\shell\ConvertTo', $false)
Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'RightClickConverter') -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Right-click "Convert to..." removed.' -ForegroundColor Green

$ans = Read-Host 'Also go back to the default Windows 11 right-click menu? (y/n)'
if ($ans -match '^[Yy]') {
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}', $false)
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
}
Read-Host 'Press Enter to close'
