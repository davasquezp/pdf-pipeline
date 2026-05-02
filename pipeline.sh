#!/bin/bash
# ------------------------------------------------------------------------------
# PDF batch pipeline: mirror the input tree under the output root and, for each
# PDF, emit output.txt, output.md, and output.json (see convert_pdf_to_text_artifacts).
#
# Usage: pipeline.sh <source_pdf_root> <output_artifact_root>
# Config: /data/config.env (FILE_EXT, DENSITY, OCR_LANG, MAX_PROCS, LOG_LEVEL, …)
# ------------------------------------------------------------------------------
set -e
source /data/config.env

SOURCE_PDF_ROOT="$1"
OUTPUT_ARTIFACT_ROOT="$2"
ERROR_LOG_PATH="$OUTPUT_ARTIFACT_ROOT/errors.log"

mkdir -p "$OUTPUT_ARTIFACT_ROOT"
: > "$ERROR_LOG_PATH"

# Optional info-level logging (LOG_LEVEL comes from config.env).
log() {
  [ "$LOG_LEVEL" = "info" ] && echo "$1"
}

# ------------------------------------------------------------------------------
# convert_pdf_to_text_artifacts
#
# Inputs:
#   $1 — absolute path to a .pdf file
#   $2 — root directory that was walked to find PDFs (used to compute relative paths)
#   $3 — output root where mirrored folders and artifacts are written
#   $4 — path to append-only error log if the conversion block fails
#
# Writes (under OUTPUT_ROOT mirroring dirname(relative_path)):
#   output.txt — full document text (native extract or OCR merged in page order)
#   output.md  — fenced markdown wrapping the same text + source PDF path
#   output.json — { "source_pdf", "text" } with JSON-safe escaping via Python
#
# Flow:
#   1. Try pdftotext to stdout and strip whitespace: if anything remains, treat
#      the file as text-based and dump with pdftotext to output.txt.
#   2. Otherwise render each page to TIFF, run Tesseract per page into ocr/*.txt,
#      concatenate sorted page texts into output.txt.
#   3. Build markdown + json from output.txt.
#
# Failures inside the main block append a single line to the error log; the shell
# continues with the next PDF (outer xargs does not stop on one bad file).
# ------------------------------------------------------------------------------
convert_pdf_to_text_artifacts() {
  local pdf_path="$1"
  local source_root="$2"
  local artifact_root="$3"
  local error_log_path="$4"

  local relative_pdf_path="${pdf_path#$source_root/}"
  local relative_parent_dir
  relative_parent_dir=$(dirname "$relative_pdf_path")
  local pdf_output_dir="$artifact_root/$relative_parent_dir"

  mkdir -p "$pdf_output_dir"

  {
    echo "Processing: $pdf_path"
    local combined_text_file="$pdf_output_dir/output.txt"

    # --- Native text layer vs scan: sample pdftotext; empty sample ⇒ OCR path ---
    local stripped_text_sample
    stripped_text_sample=$(pdftotext "$pdf_path" - 2>/dev/null | tr -d "[:space:]")

    if [ -n "$stripped_text_sample" ]; then
      echo " → Text-based PDF"
      pdftotext "$pdf_path" "$combined_text_file"
    else
      echo " → Image-based PDF"
      mkdir -p "$pdf_output_dir/images" "$pdf_output_dir/ocr"
      # TIFF avoids libpng CRC issues seen with PNG on some PDFs / Windows bind mounts.
      pdftoppm -tiff -r "$DENSITY" "$pdf_path" "$pdf_output_dir/images/page"
      while IFS= read -r -d '' rendered_page; do
        local page_basename
        page_basename=$(basename "$rendered_page")
        page_basename="${page_basename%.tif}"
        page_basename="${page_basename%.tiff}"
        tesseract "$rendered_page" "$pdf_output_dir/ocr/$page_basename" -l "$OCR_LANG" --dpi "$DENSITY"
      done < <(find "$pdf_output_dir/images" -maxdepth 1 -type f \( -name '*.tif' -o -name '*.tiff' \) -print0 | LC_ALL=C sort -z -V)
      while IFS= read -r -d '' ocr_part; do cat "$ocr_part"; done < <(find "$pdf_output_dir/ocr" -maxdepth 1 -type f -name '*.txt' -print0 | LC_ALL=C sort -z -V) > "$combined_text_file"
    fi

    # --- Markdown wrapper (human-readable artifact) ---
    local markdown_file="$pdf_output_dir/output.md"
    {
      echo "# OCR Result"
      echo
      echo "**Source PDF:** \`$relative_pdf_path\`"
      echo
      echo '```text'
      cat "$combined_text_file"
      echo '```'
    } > "$markdown_file"

    # --- JSON wrapper (structured artifact; Python handles escaping) ---
    local json_file="$pdf_output_dir/output.json"
    python3 - <<EOF > "$json_file"
import json, pathlib
text = pathlib.Path("$combined_text_file").read_text(encoding="utf-8", errors="ignore")
obj = {"source_pdf": "$relative_pdf_path", "text": text}
print(json.dumps(obj, ensure_ascii=False, indent=2))
EOF

  } || {
    echo "Error processing $pdf_path" >> "$error_log_path"
  }
}

export -f convert_pdf_to_text_artifacts
export LOG_LEVEL OCR_LANG DENSITY

# --- Count PDFs once: used in [current/total] progress lines ---
total_pdf_count=$(find "$SOURCE_PDF_ROOT" -type f -name "*.$FILE_EXT" | wc -l | tr -d ' ')
[ -z "$total_pdf_count" ] && total_pdf_count=0

# Shared counter + lock: xargs may run workers in parallel (MAX_PROCS); flock keeps updates serial.
progress_counter_file="$OUTPUT_ARTIFACT_ROOT/.progress"
progress_counter_lock_file="$OUTPUT_ARTIFACT_ROOT/.progress.lock"
echo 0 > "$progress_counter_file"

# --- Dispatch: one bash subshell per PDF; increment counter under lock, then convert ---
find "$SOURCE_PDF_ROOT" -type f -name "*.$FILE_EXT" -print0 | \
  xargs -0 -n1 -P "$MAX_PROCS" -I{} bash -c '
    pdf_path="{}"
    source_root="'"$SOURCE_PDF_ROOT"'"
    artifact_root="'"$OUTPUT_ARTIFACT_ROOT"'"
    error_log_path="'"$ERROR_LOG_PATH"'"
    progress_counter_file="'"$progress_counter_file"'"
    progress_counter_lock_file="'"$progress_counter_lock_file"'"

    {
      exec 9<>"$progress_counter_lock_file"
      flock 9
      current_index=$(cat "$progress_counter_file" 2>/dev/null || echo 0)
      current_index=$((current_index + 1))
      echo "$current_index" > "$progress_counter_file"
      echo "[${current_index}/'"$total_pdf_count"'] $pdf_path"
      exec 9>&-
    } 9<>"$progress_counter_lock_file"

    convert_pdf_to_text_artifacts "$pdf_path" "$source_root" "$artifact_root" "$error_log_path"
  '

# Normal completion: remove transient progress files (if the run aborts early, .progress may remain).
rm -f "$progress_counter_file" "$progress_counter_lock_file" 2>/dev/null || true
