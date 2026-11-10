# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.5.0] - 2026-11-10

### Added
- **Windows: Resize for images.** A new **RESIZE** slice (and list entry) for image files opens a small dialog:
  - **Size in pixels**: width and/or height with *Keep proportions* (an empty box is worked out), or an exact width x height; or a percent of the original.
  - **File size limit** (KB or MB): for sites that ask for "under 200 KB". Works with JPG and WebP by lowering the quality and, if needed, the pixel size until the file fits; other formats switch to JPG.
  - **Save as**: keep the original format, or JPG / PNG / WebP.
  - Photos are rotated the right way up (EXIF) and results are saved as `name (resized).ext`; originals are never changed.
  - Selecting several images asks once and applies the same settings to all of them.
- `Launch.vbs` accepts extra files after the target format so a whole selection starts one conversion.

## [1.4.1] - 2026-11-10

### Fixed
- Windows: reinstalling now repairs the private Python environment (pdf2docx + PyMuPDF) if its earlier setup failed, instead of skipping it because the folder already existed.
- Windows: AI to SVG is only offered when PyMuPDF is actually installed, so it no longer shows up and then fails on PCs without it.

## [1.4.0] - 2026-11-10

### Added
- **Windows: Adobe Illustrator (.ai) files** convert to SVG, PDF, EPS, PNG and JPG using Ghostscript (and PyMuPDF for SVG). Files with several artboards give one file per artboard, in a "<name> <FORMAT> files" folder.
- **Windows: AI to CDR** when CorelDRAW is installed. `ai2cdr.ps1` opens the file in CorelDRAW in the background and saves it as .cdr; the CDR option only appears on PCs where CorelDRAW is registered.
- `Convert.ps1` tool calls can time out (used for the Ghostscript and CorelDRAW steps) so a stuck program doesn't leave the progress window open forever.

### Changed
- The macOS build is unchanged from 1.3.0.

## [1.3.0] - 2026-11-06

### Added
- **macOS radial ring menu**: right-click a file in Finder (Quick Actions > Convert to...) or select files and press **Control + Option + C**, and the same glassy ring of formats appears at the mouse pointer. Hover to highlight, click to convert, Esc to cancel.
- macOS menu-bar app (⟳) with "Convert selected Finder files", "Start at login" and Quit. The installer builds it from mac/radial/main.swift with the Xcode Command Line Tools and offers to start it at login.
- macOS: selecting different types of files shows a message asking for one type, instead of converting only some of them.
- convert.sh accepts --targets <files> (lists the output formats) and --target <fmt> <files> (converts without the list picker).

### Changed
- The macOS Quick Action opens the ring when the ring app is built, and falls back to the plain list picker otherwise.
- The macOS uninstaller also removes the ring menu and its login item.
- The Windows build is unchanged from 1.2.0.

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
