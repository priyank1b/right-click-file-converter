# Right-Click File Converter

Adds a **Convert to...** entry to the right-click menu. Pick a file, choose the format, and the converted copy appears next to the original. Nothing is overwritten, and nothing is uploaded: everything runs on your own computer.

Convert images, video, audio, Word / Excel / PowerPoint, PDF, Markdown, HTML and EPUB with two clicks.

Both versions show a **radial ring** to pick the format: right-click a file, or select files and press **Ctrl + Alt + C** (Windows) / **Control + Option + C** (Mac), and choose from a ring at your mouse pointer.

![license](https://img.shields.io/badge/license-MIT-green)

## Pick your system

| | Download | Guide |
|---|---|---|
| **Windows 10 / 11** | `RightClickConverter.zip` or `RightClickConverter-Setup.exe` from the [latest release](https://github.com/priyank1b/right-click-file-converter/releases/latest) | [windows/README.md](windows/README.md) |
| **macOS 12+** (Intel and Apple Silicon) | `RightClickConverter-mac.zip` from the [latest release](https://github.com/priyank1b/right-click-file-converter/releases/latest) | [mac/README.md](mac/README.md) |

Each version lives in its own folder and is released together; use only the one for your system.

## What it converts

| Type | From | To |
|------|------|----|
| Images | PNG, JPG, WEBP, BMP, GIF, TIFF, ICO, HEIC, AVIF | PNG, JPG, WEBP, BMP, GIF, TIFF, ICO, PDF |
| Video | MP4, MKV, AVI, MOV, WMV, FLV, WEBM, M4V, MPG, 3GP, TS | MP4, MKV, AVI, MOV, WEBM, animated GIF, or audio only |
| Audio | MP3, WAV, FLAC, AAC, M4A, OGG, OPUS, WMA, AIFF | MP3, WAV, FLAC, AAC, M4A, OGG, OPUS |
| Documents | DOC, DOCX, ODT, RTF, TXT | PDF, DOCX, ODT, RTF, TXT, HTML |
| Spreadsheets | XLS, XLSX, ODS, CSV | PDF, XLSX, ODS, CSV, HTML |
| Presentations | PPT, PPTX, ODP | PDF, PPTX, ODP |
| PDF | PDF | DOCX, ODT, TXT, or one PNG/JPG per page |
| Markdown / HTML / EPUB | MD, HTML, EPUB | DOCX, HTML, MD, TXT, EPUB, PDF |
| Illustrator (Windows) | AI | SVG, PDF, EPS, PNG, JPG, and CDR when CorelDRAW is installed |

Under the hood it uses [FFmpeg](https://ffmpeg.org/), [ImageMagick](https://imagemagick.org/), [Ghostscript](https://ghostscript.com/), [Pandoc](https://pandoc.org/), [LibreOffice](https://www.libreoffice.org/) and [pdf2docx](https://github.com/ArtifexSoftware/pdf2docx). The installer sets up whatever is missing; the first install downloads about 1 GB.

## Repository layout

```
windows/      Windows version (PowerShell, installer, uninstaller, setup.exe source)
mac/          macOS version (bash, Swift ring menu, Finder Quick Action, Homebrew installer)
build.ps1     builds the release files into dist/
VERSION       current version (shared by both)
CHANGELOG.md  release history
```

## Building a release

From PowerShell on Windows (nothing extra to install):

```powershell
.\build.ps1
```

This writes to `dist/`: `RightClickConverter.zip` and `RightClickConverter-Setup.exe` (Windows), `RightClickConverter-mac.zip` (macOS), and `SHA256SUMS.txt`.

## License

[MIT](LICENSE). The tools the installers download have their own licenses.
