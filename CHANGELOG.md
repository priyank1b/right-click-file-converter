# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

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
