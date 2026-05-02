#!/bin/bash
set -e
source /data/config.env

INPUT_ROOT="$1"
OUTPUT_ROOT="$2"
ERROR_LOG="$OUTPUT_ROOT/errors.log"

mkdir -p "$OUTPUT_ROOT"
: > "$ERROR_LOG"

log() {
  [ "$LOG_LEVEL" = "info" ] && echo "$1"
}

process_pdf() {
  local pdf="$1"
  local input_root="$2"
  local output_root="$3"
  local error_log="$4"

  local rel_path="${pdf#$input_root/}"
  local rel_dir
  rel_dir=$(dirname "$rel_path")
  local outdir="$output_root/$rel_dir"

  mkdir -p "$outdir"

  {
    echo "Processing: $pdf"
    local tmp_txt="$outdir/output.txt"

    # Detect text-based PDF
    local text
    text=$(pdftotext "$pdf" - 2>/dev/null | tr -d "[:space:]")

    if [ -n "$text" ]; then
      echo " → Text-based PDF"
      pdftotext "$pdf" "$tmp_txt"
    else
      echo " → Image-based PDF"
      mkdir -p "$outdir/images" "$outdir/ocr"
      # TIFF avoids libpng CRC issues seen with PNG on some PDFs / Windows bind mounts
      pdftoppm -tiff -r "$DENSITY" "$pdf" "$outdir/images/page"
      while IFS= read -r -d '' img; do
        local base
        base=$(basename "$img")
        base="${base%.tif}"
        base="${base%.tiff}"
        tesseract "$img" "$outdir/ocr/$base" -l "$OCR_LANG" --dpi "$DENSITY"
      done < <(find "$outdir/images" -maxdepth 1 -type f \( -name '*.tif' -o -name '*.tiff' \) -print0 | LC_ALL=C sort -z -V)
      while IFS= read -r -d '' f; do cat "$f"; done < <(find "$outdir/ocr" -maxdepth 1 -type f -name '*.txt' -print0 | LC_ALL=C sort -z -V) > "$tmp_txt"
    fi

    # Markdown wrapper
    local md="$outdir/output.md"
    {
      echo "# OCR Result"
      echo
      echo "**Source PDF:** \`$rel_path\`"
      echo
      echo '```text'
      cat "$tmp_txt"
      echo '```'
    } > "$md"

    # JSON wrapper (using Python for safe escaping)
    local json="$outdir/output.json"
    python3 - <<EOF > "$json"
import json, pathlib
text = pathlib.Path("$tmp_txt").read_text(encoding="utf-8", errors="ignore")
obj = {"source_pdf": "$rel_path", "text": text}
print(json.dumps(obj, ensure_ascii=False, indent=2))
EOF

  } || {
    echo "Error processing $pdf" >> "$error_log"
  }
}

export -f process_pdf
export LOG_LEVEL OCR_LANG DENSITY

TOTAL=$(find "$INPUT_ROOT" -type f -name "*.$FILE_EXT" | wc -l | tr -d ' ')
[ -z "$TOTAL" ] && TOTAL=0

PROGRESS_FILE="$OUTPUT_ROOT/.progress"
LOCK_FILE="$OUTPUT_ROOT/.progress.lock"
echo 0 > "$PROGRESS_FILE"

find "$INPUT_ROOT" -type f -name "*.$FILE_EXT" -print0 | \
  xargs -0 -n1 -P "$MAX_PROCS" -I{} bash -c '
    pdf="{}"
    input_root="'"$INPUT_ROOT"'"
    output_root="'"$OUTPUT_ROOT"'"
    error_log="'"$ERROR_LOG"'"
    progress_file="'"$PROGRESS_FILE"'"
    lock_file="'"$LOCK_FILE"'"

    {
      exec 9<>"$lock_file"
      flock 9
      c=$(cat "$progress_file" 2>/dev/null || echo 0)
      c=$((c+1))
      echo "$c" > "$progress_file"
      echo "[${c}/'"$TOTAL"'] $pdf"
      exec 9>&-
    } 9<>"$lock_file"

    process_pdf "$pdf" "$input_root" "$output_root" "$error_log"
  '

rm -f "$PROGRESS_FILE" "$LOCK_FILE" 2>/dev/null || true
