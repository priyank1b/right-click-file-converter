#!/bin/bash
# Removes the Finder Quick Action and the converter files.
# The programs it installed with Homebrew (ffmpeg, ImageMagick, ...) are left alone.

launchctl unload "$HOME/Library/LaunchAgents/com.rightclickconverter.radial.plist" >/dev/null 2>&1 || true
rm -f "$HOME/Library/LaunchAgents/com.rightclickconverter.radial.plist"
pkill -f "RadialMenu --tray" >/dev/null 2>&1 || true
rm -rf "$HOME/Library/Services/Convert to.workflow"
rm -rf "$HOME/Library/Application Support/RightClickConverter"
/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
echo 'Right-click "Convert to..." removed.'
echo 'To remove the tools too:  brew uninstall ffmpeg imagemagick pandoc ghostscript python && brew uninstall --cask libreoffice'
echo '(only do that if nothing else on your Mac needs them)'
