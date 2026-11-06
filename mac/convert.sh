#!/bin/bash
# Right-Click File Converter for macOS
# Called by the Finder Quick Action with the selected files as arguments.
# Written for bash 3.2 (the version that ships with macOS).

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

APPDIR="$HOME/Library/Application Support/RightClickConverter"
SOFFICE="/Applications/LibreOffice.app/Contents/MacOS/soffice"
PYBIN="$APPDIR/pyenv/bin/python"
PDF2DOCX="$APPDIR/pdf2docx_run.py"

have() { command -v "$1" >/dev/null 2>&1; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

alert() {
    osascript -e 'on run argv' \
        -e 'display alert (item 1 of argv) message (item 2 of argv) as critical' \
        -e 'end run' "$1" "$2" >/dev/null 2>&1
}

notify() {
    osascript -e 'on run argv' \
        -e 'display notification (item 2 of argv) with title (item 1 of argv)' \
        -e 'end run' "$1" "$2" >/dev/null 2>&1
}

# ---- routing: file extension -> kind
kind_for() {
    case "$1" in
        jpg|jpeg|jfif|png|webp|bmp|gif|tif|tiff|heic|heif|avif|ico) echo image ;;
        mp4|mkv|avi|mov|wmv|flv|webm|m4v|mpg|mpeg|3gp|ts|mts|m2ts|vob) echo video ;;
        mp3|wav|flac|aac|m4a|ogg|opus|wma|aiff|aif) echo audio ;;
        doc|docx|odt|rtf|txt|wpd) echo doc ;;
        xls|xlsx|ods|csv) echo sheet ;;
        ppt|pptx|odp) echo slides ;;
        md|markdown) echo md ;;
        html|htm) echo html ;;
        epub) echo epub ;;
        pdf) echo pdf ;;
        *) echo "" ;;
    esac
}

# ---- routing: kind -> output formats offered
targets_for() {
    case "$1" in
        image)  echo "png jpg webp bmp gif tiff ico pdf" ;;
        video)  echo "mp4 mkv avi mov webm gif mp3 wav m4a flac" ;;
        audio)  echo "mp3 wav flac aac m4a ogg opus" ;;
        doc)    echo "pdf docx odt rtf txt html" ;;
        sheet)  echo "pdf xlsx ods csv html" ;;
        slides) echo "pdf pptx odp" ;;
        md)     echo "docx html txt epub pdf" ;;
        html)   echo "docx md txt epub pdf" ;;
        epub)   echo "docx html md txt" ;;
        pdf)    echo "png jpg docx odt txt" ;;
    esac
}

# ---- which tools a conversion needs (returns 0 when available)
tools_ok() {
    local kind="$1" target="$2"
    case "$kind" in
        image)  have magick ;;
        video|audio) have ffmpeg ;;
        doc|sheet|slides) [ -x "$SOFFICE" ] ;;
        md)     if [ "$target" = pdf ]; then have pandoc && [ -x "$SOFFICE" ]; else have pandoc; fi ;;
        html)   if [ "$target" = pdf ]; then [ -x "$SOFFICE" ]; else have pandoc; fi ;;
        epub)   have pandoc ;;
        pdf)    case "$target" in
                    png|jpg) have magick && have gs ;;
                    *) [ -x "$SOFFICE" ] ;;
                esac ;;
        *) return 1 ;;
    esac
}

# ---- output name that never overwrites: name.ext, name (1).ext, ...
free_name() {
    local dir="$1" base="$2" ext="$3" p i=1
    p="$dir/$base.$ext"
    while [ -e "$p" ]; do p="$dir/$base ($i).$ext"; i=$((i + 1)); done
    printf '%s' "$p"
}

# ---- LibreOffice conversion: convert_lo <in> <format> <workdir> [infilter]
convert_lo() {
    local in="$1" fmt="$2" work="$3" infilter="$4"
    local outdir="$work/lo_out"
    mkdir -p "$outdir"
    if [ -n "$infilter" ]; then
        "$SOFFICE" "-env:UserInstallation=file://$work/lo_profile" --headless --norestore \
            "--infilter=$infilter" --convert-to "$fmt" --outdir "$outdir" "$in" >/dev/null 2>&1
    else
        "$SOFFICE" "-env:UserInstallation=file://$work/lo_profile" --headless --norestore \
            --convert-to "$fmt" --outdir "$outdir" "$in" >/dev/null 2>&1
    fi
    ls "$outdir"/* 2>/dev/null | head -n 1
}

# ---- ffmpeg options per target
ffmpeg_opts() {
    case "$1" in
        mp4)  echo '-c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -vf scale=trunc(iw/2)*2:trunc(ih/2)*2 -c:a aac -b:a 160k -movflags +faststart' ;;
        mkv|mov) echo '-c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -vf scale=trunc(iw/2)*2:trunc(ih/2)*2 -c:a aac -b:a 160k' ;;
        avi)  echo '-c:v mpeg4 -q:v 3 -c:a libmp3lame -q:a 4' ;;
        webm) echo '-c:v libvpx-vp9 -crf 32 -b:v 0 -deadline good -cpu-used 5 -c:a libopus -b:a 128k' ;;
        gif)  echo '-vf fps=12,scale=480:-1:flags=lanczos -loop 0 -an' ;;
        mp3)  echo '-vn -c:a libmp3lame -q:a 2' ;;
        wav|flac) echo '-vn' ;;
        m4a|aac) echo '-vn -c:a aac -b:a 192k' ;;
        ogg)  echo '-vn -c:a libvorbis -q:a 5' ;;
        opus) echo '-vn -c:a libopus -b:a 128k' ;;
    esac
}

# ---- convert one file; prints the final path on success, returns non-zero on failure
convert_one() {
    local src="$1" kind="$2" t="$3"
    local dir base work out final res opts frame
    dir="$(dirname "$src")"
    base="$(basename "$src")"; base="${base%.*}"
    work="$(mktemp -d "${TMPDIR:-/tmp}/rcc.XXXXXX")" || return 1

    case "$kind" in
        image)
            out="$work/out.$t"
            frame="$src"
            case "$t" in gif|pdf|tiff) ;; *) frame="$src[0]" ;; esac
            opts=""
            case "$t" in jpg|bmp) opts="-background white -alpha remove -alpha off" ;; esac
            [ "$t" = jpg ] && opts="$opts -quality 92"
            [ "$t" = webp ] && opts="$opts -quality 90"
            [ "$t" = ico ] && opts="$opts -define icon:auto-resize=256,128,64,48,32,16"
            # shellcheck disable=SC2086
            magick "$frame" $opts "$out" >/dev/null 2>&1
            ;;
        video|audio)
            out="$work/out.$t"
            # shellcheck disable=SC2046
            ffmpeg -y -hide_banner -loglevel error -i "$src" $(ffmpeg_opts "$t") "$out" >/dev/null 2>&1
            ;;
        doc|sheet|slides)
            local fmt="$t"; [ "$t" = txt ] && fmt="txt:Text"
            out="$(convert_lo "$src" "$fmt" "$work" "")"
            ;;
        html)
            if [ "$t" = pdf ]; then
                out="$(convert_lo "$src" pdf "$work" "")"
            else
                out="$work/out.$t"
                opts=""; [ "$t" = md ] && opts="-t gfm"; [ "$t" = txt ] && opts="-t plain"
                # shellcheck disable=SC2086
                pandoc "$src" $opts -o "$out" >/dev/null 2>&1
            fi
            ;;
        md|epub)
            local pt="$t"; [ "$t" = pdf ] && pt="docx"
            res="$work/out.$pt"
            opts=""
            [ "$pt" = html ] && opts="-s"
            [ "$pt" = md ] && opts="-t gfm"
            [ "$pt" = txt ] && opts="-t plain"
            # shellcheck disable=SC2086
            pandoc "$src" $opts -o "$res" >/dev/null 2>&1
            if [ "$t" = pdf ] && [ -s "$res" ]; then
                out="$(convert_lo "$res" pdf "$work" "")"
            else
                out="$res"
            fi
            ;;
        pdf)
            case "$t" in
                png|jpg)
                    mkdir -p "$work/pages"
                    opts="-density 200 -background white -alpha remove -alpha off"
                    [ "$t" = jpg ] && opts="$opts -quality 92"
                    # shellcheck disable=SC2086
                    magick $opts "$src" "$work/pages/p%03d.$t" >/dev/null 2>&1
                    local count
                    count="$(ls "$work/pages" 2>/dev/null | wc -l | tr -d ' ')"
                    if [ "$count" = "0" ]; then rm -rf "$work"; return 1; fi
                    if [ "$count" = "1" ]; then
                        final="$(free_name "$dir" "$base" "$t")"
                        mv "$work/pages/"* "$final"
                    else
                        local folder="$dir/$base pages" n=1 i=1 f
                        while [ -e "$folder" ]; do folder="$dir/$base pages ($n)"; n=$((n + 1)); done
                        mkdir -p "$folder"
                        for f in "$work/pages/"*; do
                            mv "$f" "$folder/$base - page $i.$t"; i=$((i + 1))
                        done
                        final="$folder"
                    fi
                    rm -rf "$work"; printf '%s' "$final"; return 0
                    ;;
                docx)
                    out=""
                    if [ -x "$PYBIN" ] && [ -f "$PDF2DOCX" ]; then
                        "$PYBIN" -I "$PDF2DOCX" "$src" "$work/out.docx" >/dev/null 2>&1
                        [ -s "$work/out.docx" ] && out="$work/out.docx"
                    fi
                    if [ -z "$out" ]; then
                        out="$(convert_lo "$src" "docx:MS Word 2007 XML" "$work" "writer_pdf_import")"
                    fi
                    ;;
                txt)
                    out="$(convert_lo "$src" "txt:Text" "$work" "writer_pdf_import")"
                    ;;
                *)
                    out="$(convert_lo "$src" "$t" "$work" "writer_pdf_import")"
                    ;;
            esac
            ;;
    esac

    if [ -z "$out" ] || [ ! -s "$out" ]; then rm -rf "$work"; return 1; fi
    final="$(free_name "$dir" "$base" "$t")"
    mv "$out" "$final"
    rm -rf "$work"
    printf '%s' "$final"
}

MODE=""
fail() {  # fail <title> <message>
    if [ "$MODE" = targets ]; then printf 'err|%s\n' "$2"; else alert "$1" "$2"; fi
    exit 1
}

main() {
    local preset=""
    case "${1:-}" in
        --targets) MODE=targets; shift ;;
        --target)  preset="$(lower "${2:-}")"; shift 2 ;;
    esac
    [ "$#" -eq 0 ] && fail "Convert to..." "No file was selected."

    local first="$1" ext kind f fext fk
    ext="$(lower "${first##*.}")"
    kind="$(kind_for "$ext")"
    [ -z "$kind" ] && fail "Convert to..." "Sorry, .$ext files are not supported yet."
    for f in "$@"; do
        fext="$(lower "${f##*.}")"; fk="$(kind_for "$fext")"
        [ -z "$fk" ] && fail "Convert to..." "Sorry, .$fext files are not supported yet."
        [ "$fk" = "$kind" ] || fail "Convert to..." "You selected different types of files. Please select one type at a time (for example only images, or only videos)."
    done

    local norm="$ext"
    case "$ext" in
        jpeg|jfif) norm=jpg ;; tif) norm=tiff ;; htm) norm=html ;;
        markdown) norm=md ;; aif) norm=aiff ;; heif) norm=heic ;;
    esac

    # offered targets = routing table minus the source format minus missing tools
    local t list=""
    for t in $(targets_for "$kind"); do
        [ "$t" = "$norm" ] && continue
        tools_ok "$kind" "$t" || continue
        list="$list $t"
    done
    [ -z "$list" ] && fail "Convert to..." "The tools needed to convert .$ext files are not installed. Run install.sh again."

    if [ "$MODE" = targets ]; then printf 'ok|%s|%s\n' "$kind" "${list# }"; exit 0; fi

    if [ -n "$preset" ]; then
        case " $list " in
            *" $preset "*) t="$preset" ;;
            *) fail "Convert to..." "Cannot convert .$ext files to $preset." ;;
        esac
    else
        # picker (AppleScript list); labels like "PNG", with notes for special cases
        local labels="" label
        for t in $list; do
            label="$(upper "$t")"
            case "$kind:$t" in
                video:mp3|video:wav|video:m4a|video:flac) label="$label  (audio only)" ;;
                video:gif) label="$label  (animated)" ;;
                pdf:png|pdf:jpg) label="$label  (one image per page)" ;;
                pdf:docx|pdf:odt|pdf:txt) label="$label  (approximate)" ;;
            esac
            labels="$labels|$label"
        done
        labels="${labels#|}"

        local picker choice
        picker='on run argv
    set fileName to item 1 of argv
    set AppleScript'"'"'s text item delimiters to "|"
    set theItems to text items of (item 2 of argv)
    set AppleScript'"'"'s text item delimiters to ""
    set picked to choose from list theItems with title "Convert to..." with prompt ("Convert " & fileName & " to:") default items {item 1 of theItems} OK button name "Convert" cancel button name "Cancel"
    if picked is false then return ""
    return item 1 of picked
end run'
        choice="$(osascript -e "$picker" "$(basename "$first")" "$labels" 2>/dev/null)"
        [ -z "$choice" ] && exit 0
        t="$(lower "${choice%% *}")"
    fi

    # convert every selected file
    local done_count=0 fail_count=0 last="" res
    for f in "$@"; do
        fext="$(lower "${f##*.}")"
        [ "$fext" = "$norm" ] && continue
        if res="$(convert_one "$f" "$kind" "$t")" && [ -n "$res" ]; then
            done_count=$((done_count + 1)); last="$res"
        else
            fail_count=$((fail_count + 1))
        fi
    done

    if [ "$done_count" -gt 0 ]; then
        if [ "$done_count" -eq 1 ]; then notify "Converted" "Saved as $(basename "$last")"
        else notify "Converted" "$done_count files converted"; fi
        # reveal the last result in Finder
        open -R "$last" >/dev/null 2>&1
    fi
    if [ "$fail_count" -gt 0 ]; then
        alert "Conversion failed" "$fail_count file(s) could not be converted to ${t}."
        exit 1
    fi
}

# run only when executed (lets tests source this file)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi