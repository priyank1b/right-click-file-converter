# Right-Click File Converter

Adds a **Convert to...** entry to the Windows right-click menu. Pick a file, choose the format, and the converted copy appears next to the original. Nothing is overwritten, and nothing is uploaded: everything runs on your own PC.

![platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue) ![license](https://img.shields.io/badge/license-MIT-green)

> Looking for macOS? See the [Mac version](../mac/README.md).

## What it converts

| Type | From | To |
|------|------|----|
| Images | PNG, JPG, WEBP, BMP, GIF, TIFF, ICO, HEIC, AVIF | PNG, JPG, WEBP, BMP, GIF, TIFF, ICO, PDF |
| Video | MP4, MKV, AVI, MOV, WMV, FLV, WEBM, M4V, MPG, 3GP, TS | MP4, MKV, AVI, MOV, WEBM, animated GIF, or audio only (MP3, WAV, M4A, FLAC) |
| Audio | MP3, WAV, FLAC, AAC, M4A, OGG, OPUS, WMA, AIFF | MP3, WAV, FLAC, AAC, M4A, OGG, OPUS |
| Documents | DOC, DOCX, ODT, RTF, TXT | PDF, DOCX, ODT, RTF, TXT, HTML |
| Spreadsheets | XLS, XLSX, ODS, CSV | PDF, XLSX, ODS, CSV, HTML |
| Presentations | PPT, PPTX, ODP | PDF, PPTX, ODP |
| PDF | PDF | DOCX, ODT, TXT, or one PNG/JPG per page |
| Markdown / HTML / EPUB | MD, HTML, EPUB | DOCX, HTML, MD, TXT, EPUB, PDF |
| Illustrator | AI | SVG, PDF, EPS, PNG, JPG (one per artboard), and CDR when CorelDRAW is installed |

### Resize images

Choose **RESIZE** in the ring (or list) for any image to change its size without changing what it is:

- **Pixels**: set a width, a height or both. With *Keep proportions* on, the picture is fitted inside the box and an empty box is worked out for you (width 800 gives 800 px wide). Turn it off for an exact width x height. Or use **Percent of original**.
- **File size**: tick *Make file smaller than* and enter KB or MB (handy for upload forms with a limit). This works with JPG and WebP; PNG and other formats switch to JPG. Very small limits make the picture softer, and if the limit can't be reached you are told the smallest size it got to.
- **Save as**: keep the format, or pick JPG, PNG or WebP.

You can combine them (for example 1000 px wide and under 100 KB). Results are saved next to the original as `name (resized).jpg`; the original is untouched. Select several images to resize them all with the same settings.

## Install

1. Download the latest release from the [Releases page](https://github.com/priyank1b/right-click-file-converter/releases/latest):
   - **`RightClickConverter.zip`**: extract it, then double-click `Install.bat`. (Recommended)
   - **`RightClickConverter-Setup.exe`**: a single file that does the same thing.
2. Click **Yes** on the administrator prompt.
3. Wait. The first install downloads about 1 GB (mostly LibreOffice) and can take 10-20 minutes. If your connection drops, run the installer again: anything already installed is skipped.
4. Right-click any file and choose **Convert to...**
   On Windows 11 the entry is under **Show more options** (or Shift + right-click). The installer can make the full menu the default.

> **"Windows protected your PC"**: the installer isn't code-signed, so SmartScreen may warn. Click **More info > Run anyway**. All scripts are plain text in this repo, so you can read exactly what runs.

### Requirements

- Windows 10 or 11
- An internet connection during install
- About 3 GB of free disk space

## Radial menu (right-click or hotkey)

Right-clicking a file and choosing **Convert to...** and the hotkey show the same ring. If the selected files are of different types, a message box asks you to pick one type at a time.

To use the keyboard: select file(s) in File Explorer (or on the Desktop) and press **Ctrl + Alt + C**. A ring of output formats appears at your mouse pointer:

- **Hover** a slice to highlight it. The center shows what you're about to convert to.
- **Click** a slice to convert. **Esc**, a right-click, or a click outside the ring cancels.
- Select several files of the **same type** (for example all images) to convert them all in one go. If you mix types (say a photo and a video), you get a notice asking you to select one type.

The installer asks whether to start it automatically when you sign in. It lives in the system tray (near the clock); right-click its icon to change the hotkey (Ctrl+Alt+C, Ctrl+Alt+Space, Ctrl+Shift+Space or Win+Shift+C), toggle "Start with Windows", or exit. If the hotkey is already taken by another program, you'll get a notification and can pick a different one.
## What gets installed

The installer uses [winget](https://learn.microsoft.com/windows/package-manager/winget/) where possible, and downloads directly (with retries and resume) when a package isn't available.

| Tool | Used for |
|------|----------|
| [FFmpeg](https://ffmpeg.org/) | video and audio |
| [ImageMagick](https://imagemagick.org/) | images |
| [Ghostscript](https://ghostscript.com/) | PDF to image, Illustrator (.ai) files |
| [Pandoc](https://pandoc.org/) | Markdown, HTML, EPUB |
| [LibreOffice](https://www.libreoffice.org/) | Word, Excel, PowerPoint, CSV, PDF |
| [Python](https://www.python.org/) + [pdf2docx](https://github.com/ArtifexSoftware/pdf2docx) | better PDF to Word |

The converter itself is copied to `%LOCALAPPDATA%\RightClickConverter`. The context-menu entry is added for the **current user only** (`HKCU`), so it needs no system-wide changes.

## Uninstall

Run `Uninstall.bat`. It removes the right-click entry and the converter files. The tools above are left alone; remove them from **Settings > Apps** if you don't need them.

## Known limits

- **PDF to Word** works best on normal text PDFs. Scanned PDFs are pictures and won't become editable text (that needs OCR). Tables without borders may come out as plain text, hyperlinks may be lost, and complex multi-column layouts may not match exactly.
- **AI to CDR** only appears when CorelDRAW Graphics Suite (full Windows version, with automation) is installed, because only CorelDRAW can write .cdr files. The converter opens CorelDRAW in the background, so it takes a few seconds per file. Home & Student / Essentials editions and CorelDRAW.app may not work.
- **AI files** must be saved with "Create PDF Compatible File" on (Illustrator's default). Very old (Illustrator 8 and earlier) or non-PDF-compatible files may not convert to SVG.
- Video conversion re-encodes, so large files take time.
- The installer and exe are unsigned.

## Project layout

```
Install.bat / Install.ps1     installer (elevates, installs tools, adds the menu entry)
Convert.ps1                   the converter UI and logic
Launch.vbs                    starts Convert.ps1 without a console window
pdf2docx_run.py               PDF to DOCX helper
ai_svg_run.py                 AI to SVG helper (PyMuPDF)
ai2cdr.ps1                    AI to CDR helper (drives CorelDRAW)
Uninstall.bat / Uninstall.ps1 removes the menu entry and files
radial/RadialMenu.cs          the hotkey radial menu (tray app, compiled to RadialMenu.exe)
installer/Setup.cs            source of the self-extracting RightClickConverter-Setup.exe
```

## Building a release

Run `build.ps1` from the repository root (see the [main README](../README.md)). The exe is compiled with the .NET Framework compiler that ships with Windows; nothing extra is needed.

To test the installer without installing anything:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -DryRun
```
## License

[MIT](../LICENSE). The tools the installer downloads have their own licenses.
