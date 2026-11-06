#!/bin/bash
# Right-Click File Converter for macOS - installer
# Run it from Terminal:   bash install.sh
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
APPDIR="$HOME/Library/Application Support/RightClickConverter"
SERVICE="$HOME/Library/Services/Convert to.workflow"

say()  { printf '\033[1;33m--> %s\033[0m\n' "$1"; }
ok()   { printf '\033[0;32m    %s\033[0m\n' "$1"; }
warn() { printf '\033[0;31m    %s\033[0m\n' "$1"; }

echo
printf '\033[1;36m=== Right-click "Convert to..." installer (macOS) ===\033[0m\n'
echo

if [ "$(uname)" != "Darwin" ]; then warn "This installer is for macOS only."; exit 1; fi

FAILED=""

retry() {  # retry <times> <command...>
    local n="$1" i=1; shift
    while [ "$i" -le "$n" ]; do
        "$@" && return 0
        warn "attempt $i failed, retrying..."
        i=$((i + 1)); sleep 3
    done
    return 1
}

# ---------------------------------------------------------------- Homebrew
find_brew() {
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$b" ] && { echo "$b"; return 0; }
    done
    command -v brew 2>/dev/null
}

BREW="$(find_brew)"
if [ -z "$BREW" ]; then
    say "Homebrew (package manager) is not installed"
    echo "    The converter tools are installed with Homebrew (https://brew.sh)."
    printf "    Install Homebrew now? It will ask for your Mac password. (y/n) "
    read -r ans
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        BREW="$(find_brew)"
    fi
    if [ -z "$BREW" ]; then
        warn "Homebrew is required. Install it from https://brew.sh and run this again."
        exit 1
    fi
fi
eval "$("$BREW" shellenv)"

# ---------------------------------------------------------------- tools
install_formula() {  # install_formula <label> <command-to-check> <formula>
    say "$1"
    if command -v "$2" >/dev/null 2>&1 || brew list --formula "$3" >/dev/null 2>&1; then
        ok "already installed"; return
    fi
    if retry 3 brew install "$3"; then ok "installed"; else warn "FAILED"; FAILED="$FAILED\n  - $1"; fi
}

install_formula "ffmpeg (video and audio)"       ffmpeg  ffmpeg
install_formula "ImageMagick (images)"           magick  imagemagick
install_formula "Pandoc (Markdown, HTML, EPUB)"  pandoc  pandoc
install_formula "Ghostscript (PDF to image)"     gs      ghostscript

say "LibreOffice (Word, Excel, PowerPoint, CSV, PDF) - large download"
if [ -d /Applications/LibreOffice.app ]; then
    ok "already installed"
elif retry 3 brew install --cask libreoffice; then
    ok "installed"
else
    warn "FAILED"; FAILED="$FAILED\n  - LibreOffice"
fi

say "Python (needed for better PDF to Word)"
PY=""
for c in "$(brew --prefix)/bin/python3" /usr/bin/python3; do
    if [ -x "$c" ] && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then PY="$c"; break; fi
done
if [ -z "$PY" ]; then
    if retry 3 brew install python; then PY="$(brew --prefix)/bin/python3"; ok "installed"; else warn "FAILED"; FAILED="$FAILED\n  - Python"; fi
else
    ok "found $PY"
fi

# ---------------------------------------------------------------- converter files
mkdir -p "$APPDIR"
cp "$DIR/convert.sh" "$DIR/pdf2docx_run.py" "$APPDIR/"
chmod +x "$APPDIR/convert.sh"

if [ -n "$PY" ] && [ ! -x "$APPDIR/pyenv/bin/python" ]; then
    say "pdf2docx (better PDF to Word)"
    if "$PY" -m venv "$APPDIR/pyenv" && "$APPDIR/pyenv/bin/python" -m pip install --quiet --disable-pip-version-check --retries 5 --timeout 60 pdf2docx; then
        ok "installed"
    else
        warn "could not install - PDF to Word will use LibreOffice (lower quality)"
    fi
fi

# files downloaded from the internet carry a quarantine flag; clear it on what we installed
xattr -dr com.apple.quarantine "$APPDIR" 2>/dev/null || true

# ---------------------------------------------------------------- radial ring menu
say "Radial ring menu (right-click ring + Control+Option+C hotkey)"
RING=""
if xcrun --find swiftc >/dev/null 2>&1; then
    mkdir -p "$APPDIR/src"
    cp "$DIR/radial/main.swift" "$APPDIR/src/main.swift"
    pkill -f "RadialMenu --tray" >/dev/null 2>&1 || true
    rm -f "$APPDIR/RadialMenu"
    if swiftc -O "$APPDIR/src/main.swift" -o "$APPDIR/RadialMenu" 2>"$APPDIR/src/build.log"; then
        RING=1; ok "built"
    else
        warn "could not build the ring menu (see $APPDIR/src/build.log) - the right-click entry will use a simple list instead"
    fi
else
    warn "Apple's Command Line Tools are needed for the ring menu. A dialog may open - click Install,"
    warn "wait for it to finish, then run install.sh again. Until then the right-click entry uses a simple list."
    xcode-select --install >/dev/null 2>&1 || true
fi
# ---------------------------------------------------------------- Finder Quick Action
say "Finder right-click entry (Quick Action)"
rm -rf "$SERVICE"
mkdir -p "$SERVICE/Contents"

cat > "$SERVICE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Convert to...</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>public.item</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

cat > "$SERVICE/Contents/document.wflow" <<'WFLOW'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>523</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>APP="$HOME/Library/Application Support/RightClickConverter"; if [ -x "$APP/RadialMenu" ]; then "$APP/RadialMenu" --pick "$@"; else "$APP/convert.sh" "$@"; fi</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/bash</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>5F2D7A0E-3B8C-4C61-9E1A-6D4B2C8F7A10</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>A4C19B72-0D5E-4F38-8B26-1E7F3D9C5A44</string>
				<key>UUID</key>
				<string>C8E3F5A1-7B02-4D96-A1C4-92B6E0D8F3B7</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict/>
				<key>isViewVisible</key>
				<true/>
			</dict>
			<key>isViewVisible</key>
			<true/>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleID</key>
		<string>com.apple.finder</string>
		<key>applicationBundleIDsByPath</key>
		<dict/>
		<key>applicationPaths</key>
		<array/>
		<key>inputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>outputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>presentationMode</key>
		<integer>15</integer>
		<key>processesInput</key>
		<false/>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<false/>
		<key>systemImageName</key>
		<string>NSActionTemplate</string>
		<key>useAutomaticInputType</key>
		<false/>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
WFLOW

if plutil -lint "$SERVICE/Contents/Info.plist" "$SERVICE/Contents/document.wflow" >/dev/null 2>&1; then
    ok "Quick Action installed"
else
    warn "Quick Action files look invalid - see the README for the manual Automator steps"
    FAILED="$FAILED\n  - Finder Quick Action"
fi
# make macOS notice the new service right away
/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true

# ---------------------------------------------------------------- start the tray app
if [ -n "$RING" ]; then
    AGENT="$HOME/Library/LaunchAgents/com.rightclickconverter.radial.plist"
    printf "    Start the ring menu (Control+Option+C) automatically when you log in? (y/n) "
    read -r ans
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
        mkdir -p "$HOME/Library/LaunchAgents"
        cat > "$AGENT" <<AGENTPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.rightclickconverter.radial</string>
<key>ProgramArguments</key><array><string>$APPDIR/RadialMenu</string><string>--tray</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
AGENTPLIST
        launchctl unload "$AGENT" >/dev/null 2>&1 || true
        launchctl load "$AGENT" >/dev/null 2>&1 || nohup "$APPDIR/RadialMenu" --tray >/dev/null 2>&1 &
    else
        nohup "$APPDIR/RadialMenu" --tray >/dev/null 2>&1 &
    fi
    ok "ring menu running (look for the icon in the menu bar)"
fi
echo
if [ -n "$FAILED" ]; then
    printf '\033[1;31mThese did not install - check your internet connection and run install.sh again (finished items are skipped):\033[0m'
    printf '%b\n' "$FAILED"
    exit 1
fi
printf '\033[1;32mAll done.\033[0m\n'
echo
echo "To use it: right-click (or Control-click) any file in Finder > Quick Actions > Convert to...,"
echo "or select files in Finder and press Control+Option+C. Both show the same ring."
echo "If the entry is missing: System Settings > Keyboard > Keyboard Shortcuts > Services (or Extensions >"
echo "Finder) and tick 'Convert to...'. You may also need to log out and back in once."
echo "The first use may ask permission for 'Terminal'/'Finder' to control files - click OK."
