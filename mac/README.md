# Right-Click File Converter for macOS

Adds **Convert to...** to the Finder right-click menu (under **Quick Actions**). Pick a file, choose the format from a glassy ring at your mouse pointer, and the converted copy appears next to the original. Nothing is overwritten, and nothing is uploaded: everything runs on your own Mac.

> Looking for Windows? See the [Windows version](../windows/README.md).

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

You can select several files of the same type and convert them all at once.

## Install

1. Download **`RightClickConverter-mac.zip`** from the [latest release](https://github.com/priyank1b/right-click-file-converter/releases/latest) and double-click it to extract.
2. Open **Terminal** (press Cmd + Space, type *Terminal*, press Enter).
3. Type `bash ` (with a space after it), drag the extracted `install.sh` file into the Terminal window, and press Enter.
   Or, if the folder is in Downloads: `bash ~/Downloads/RightClickConverter-mac/install.sh`
4. If Homebrew isn't installed, the script offers to install it (it asks for your Mac password). Then it installs the tools. The first install downloads about 1 GB (mostly LibreOffice) and can take 10-20 minutes. If your connection drops, run it again: anything already installed is skipped.
5. The installer builds the ring menu with Apple's Command Line Tools (a dialog offers to install them if missing; if it does, let it finish and run `install.sh` again) and asks whether to start it at login.
6. In Finder, right-click (or Control-click) a file and choose **Quick Actions > Convert to...**, or select files and press **Control + Option + C**. Both show the same ring.

Running it with `bash install.sh` also avoids the macOS "unidentified developer" warning, which applies to double-clicked scripts.

## The ring menu

- **Hover** a slice to highlight it, **click** to convert. **Esc**, a right-click, or a click outside cancels.
- The hotkey needs the small menu-bar app (the **⟳** icon in the menu bar), which the installer starts. From its menu you can convert the current Finder selection, toggle **Start at login**, or quit.
- If you select different types of files (for example an image and a video), a message asks you to pick one type at a time.
- The first time, macOS asks whether the app may control Finder (needed to read your selection). Click **OK**.
- Without the Command Line Tools the right-click entry falls back to a plain list picker.

### If "Convert to..." doesn't show up

- Open **System Settings > Keyboard > Keyboard Shortcuts > Services** (older macOS: **System Preferences > Keyboard > Shortcuts > Services**), find **Convert to...** under *Files and Folders*, and tick it.
- Or **System Settings > Privacy & Security > Extensions > Finder** (or *Added Extensions*) and enable it.
- Log out and back in once so Finder reloads its Services.

The first time you use it, macOS may ask whether Finder/Terminal can access your Documents or Downloads folder. Click **OK**.

### Requirements

- macOS 12 (Monterey) or newer, Intel or Apple Silicon
- An internet connection during install
- About 4 GB of free disk space
- Admin rights (only needed if Homebrew has to be installed)

## What gets installed

Everything is installed with [Homebrew](https://brew.sh):

| Tool | Used for |
|------|----------|
| [FFmpeg](https://ffmpeg.org/) | video and audio |
| [ImageMagick](https://imagemagick.org/) | images |
| [Ghostscript](https://ghostscript.com/) | PDF to image |
| [Pandoc](https://pandoc.org/) | Markdown, HTML, EPUB |
| [LibreOffice](https://www.libreoffice.org/) | Word, Excel, PowerPoint, CSV, PDF |
| Python + [pdf2docx](https://github.com/ArtifexSoftware/pdf2docx) | better PDF to Word |

The converter is copied to `~/Library/Application Support/RightClickConverter`, and the Quick Action to `~/Library/Services/Convert to.workflow`. Both are per-user; nothing system-wide is changed apart from Homebrew itself if you choose to install it.

## Uninstall

```bash
bash uninstall.sh
```

Removes the Quick Action, the ring menu and the converter files. The Homebrew tools stay; the script prints the command to remove them too.

## Known limits

- **Not yet tested on a real Mac by the author.** The scripts were checked for syntax and the conversion logic was run on another platform. The ring menu (Swift) was written without being compiled on a Mac, so the first build may need a fix, and the Quick Action registration (the Finder part) can behave differently between macOS versions. If something doesn't work, please [open an issue](https://github.com/priyank1b/right-click-file-converter/issues) with your macOS version and what you see.
- **PDF to Word** works best on normal text PDFs. Scanned PDFs are pictures and won't become editable text (that needs OCR). Tables without borders may come out as plain text, and hyperlinks may be lost.
- Video conversion re-encodes, so large files take time.
- The scripts are not code-signed or notarized.

## Manual setup (if the Quick Action can't be created automatically)

1. Open **Automator** > New Document > **Quick Action**.
2. Set *Workflow receives current* **files or folders** in **Finder**.
3. Add a **Run Shell Script** action, set *Shell* to `/bin/bash` and *Pass input* to **as arguments**.
4. Paste: `"$HOME/Library/Application Support/RightClickConverter/convert.sh" "$@"` (or, if the ring menu was built, `"$HOME/Library/Application Support/RightClickConverter/RadialMenu" --pick "$@"`)
5. Save as **Convert to...**
