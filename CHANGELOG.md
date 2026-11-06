# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-11-06

### Added
- **Windows radial menu**: select file(s) in File Explorer or on the Desktop, press **Ctrl + Alt + C**, and a ring of output formats appears at the mouse pointer. Hover to highlight, click to convert, Esc to cancel. Multi-file selection converts them together.
- Selecting different types of files together (for example an image and a video) shows a message box asking for one type, instead of converting only some of them. Radial menu errors appear as a centered, always-on-top message box that stays until you click OK.
- Frosted-glass look for the radial menu: the screen behind the ring is blurred and tinted, with translucent slices, a light rim and a soft gloss.
- System-tray icon with a choice of hotkeys, a "Start with Windows" option and Exit. The installer asks whether to start the radial menu at sign-in.
- `Convert.ps1` / `Launch.vbs` accept an optional target format so other tools can skip the picker dialog.

### Changed
- The right-click **Convert to...** entry now opens the same radial ring as the hotkey (instant via the running tray app; works standalone if the tray app isn't running). Right-clicking one file of a multi-selection converts the whole selection.
- The uninstaller also stops and removes the radial menu.

## [1.1.0] - 2026-11-06

### Added
- **macOS version** in `mac/`: a Finder Quick Action ("Convert to...") with the same formats as Windows, a Homebrew-based installer (`install.sh`), `uninstall.sh`, and a release package `RightClickConverter-mac.zip`. Not yet tested on a real Mac.
- Multi-file selection on macOS: select several files of one type and convert them together.

### Changed
- Repository reorganised: the Windows version moved to `windows/`, with a new top-level README that links both. Windows behaviour is unchanged.
- `build.ps1` now builds the Windows and Mac packages together and checksums all three files.

## [1.0.0] - 2026-11-06

### Added
- "Convert to..." right-click entry for images, video, audio, Office documents, PDF, Markdown, HTML and EPUB.
- One-click installer that installs FFmpeg, ImageMagick, Pandoc, Ghostscript, LibreOffice and Python as needed, and skips anything already present.
- Download retries with resume, plus a direct-download fallback for LibreOffice and Ghostscript on flaky connections.
- Better PDF to Word conversion using pdf2docx in a private Python environment, with LibreOffice as the fallback.
- Uninstaller, `-DryRun` mode for the installer, and a build script that produces the release zip and a self-extracting setup exe.
