#!/bin/zsh
set -euo pipefail

usage() {
    echo "Usage: $0 -p <printer> -s <paper_size> [-f <file_list>] [-t <output_pdf>] [file1 ...]"
    echo ""
    echo "Options:"
    echo "  -p <printer>      Printer name (see 'lpstat -p' for available printers)"
    echo "  -s <paper_size>   Paper size (e.g. Letter, Legal, A4, A3, Tabloid)"
    echo "  -f <file_list>    File containing a list of files to print (one per line)"
    echo "  -t <output_pdf>   Test mode: merge files and save to output_pdf instead of printing"
    echo "  -h                Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -p MyPrinter -s A4 report.pdf slides.pdf"
    echo "  $0 -p MyPrinter -s A4 -f filelist.txt"
    echo "  $0 -s A4 -t merged_output.pdf report.pdf slides.pdf"
    exit 0
}

printer=""
paper_size=""
file_list=""
test_output=""

while getopts ":p:s:f:t:h" opt; do
    case $opt in
        p) printer="$OPTARG" ;;
        s) paper_size="$OPTARG" ;;
        f) file_list="$OPTARG" ;;
        t) test_output="$OPTARG" ;;
        h) usage ;;
        :) echo "Error: -$OPTARG requires an argument." >&2; exit 1 ;;
        \?) echo "Error: Unknown option -$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [[ -z "$paper_size" ]]; then
    echo "Error: -s (paper size) is required." >&2
    usage
fi

if [[ -z "$test_output" && -z "$printer" ]]; then
    echo "Error: -p (printer) is required unless using -t (test mode)." >&2
    usage
fi

# If a file list was provided, read its entries into the positional parameters
if [[ -n "$file_list" ]]; then
    if [[ ! -f "$file_list" ]]; then
        echo "Error: File list '$file_list' not found." >&2
        exit 1
    fi
    files_from_list=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        files_from_list+=("$line")
    done < "$file_list"
    set -- "${files_from_list[@]}" "$@"
fi

if [[ $# -eq 0 ]]; then
    echo "Error: No files specified." >&2
    usage
fi

# Verify the printer exists (skip in test mode)
if [[ -z "$test_output" ]]; then
    if ! lpstat -p "$printer" &>/dev/null; then
        echo "Error: Printer '$printer' not found. Available printers:" >&2
        lpstat -p 2>/dev/null | awk '{print "  " $2}' >&2
        exit 1
    fi
fi

# Collect valid files
valid_files=()
for file in "$@"; do
    if [[ ! -f "$file" ]]; then
        echo "Warning: '$file' not found, skipping." >&2
        continue
    fi
    valid_files+=("$file")
done

if [[ ${#valid_files[@]} -eq 0 ]]; then
    echo "Error: No valid files to print." >&2
    exit 1
fi

# Merge all files into a single PDF
if [[ -n "$test_output" ]]; then
    merged_pdf="$test_output"
else
    merged_pdf=$(mktemp /tmp/batch_print_merged_XXXXXX.pdf)
    trap 'rm -f "$merged_pdf"' EXIT
fi

join_tool="/System/Library/Automator/Combine PDF Pages.action/Contents/MacOS/join"
if [[ -x "$join_tool" ]]; then
    "$join_tool" -o "$merged_pdf" "${valid_files[@]}"
elif command -v gs &>/dev/null; then
    gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile="$merged_pdf" "${valid_files[@]}"
else
    echo "Error: No PDF merge tool found." >&2
    echo "Install Ghostscript (brew install ghostscript) or ensure macOS Automator is available." >&2
    exit 1
fi

if [[ -n "$test_output" ]]; then
    echo "Test mode: merged ${#valid_files[@]} files into '$test_output'"
else
    echo "Printing merged PDF (${#valid_files[@]} files) to '$printer' on $paper_size paper..."
    lp -d "$printer" -o media="$paper_size" "$merged_pdf"
fi

