#!/bin/bash
set -e
source /data/config.env

OUTPUT_ROOT="$1"

if [ -z "$OUTPUT_ROOT" ]; then
  echo "Usage: analyze-output.sh <output_folder>"
  exit 1
fi

REPORT_DIR="$OUTPUT_ROOT/report"
mkdir -p "$REPORT_DIR"

CORPUS="$REPORT_DIR/source_corpus.md"
SUMMARY_MD="$REPORT_DIR/summary.md"
SUMMARY_DOCX="$REPORT_DIR/summary.docx"
SUMMARY_PDF="$REPORT_DIR/summary.pdf"

echo "# Source Corpus" > "$CORPUS"
echo >> "$CORPUS"

find "$OUTPUT_ROOT" -type f -name "output.txt" | sort | while read -r txt; do
  rel="${txt#$OUTPUT_ROOT/}"
  echo "## $rel" >> "$CORPUS"
  echo >> "$CORPUS"
  echo '```text' >> "$CORPUS"
  cat "$txt" >> "$CORPUS"
  echo '```' >> "$CORPUS"
  echo >> "$CORPUS"
done

cat > "$SUMMARY_MD" <<EOF
# Analysis Report

This file is a starting point. You can open it in Word (DOCX) or as PDF and refine it with Copilot.

## 1. Overview

- Total documents processed: (fill in)
- Time range / categories: (fill in)

## 2. Key Themes

- Theme 1:
- Theme 2:
- Theme 3:

## 3. Notable Entities

- People:
- Organizations:
- Locations:

## 4. Trends and Patterns

- Trend 1:
- Trend 2:

## 5. Risks / Issues

- Item 1:
- Item 2:

## 6. Recommendations

- Recommendation 1:
- Recommendation 2:

---

For deeper analysis, paste sections of \`source_corpus.md\` into Copilot and ask for:
- Topic clustering
- Sentiment analysis
- Cross-document comparisons
- Executive summaries
EOF

pandoc "$SUMMARY_MD" -o "$SUMMARY_DOCX" || echo "DOCX generation failed (pandoc)."
pandoc "$SUMMARY_MD" -o "$SUMMARY_PDF" || echo "PDF generation failed (pandoc)."

echo "Report generated in: $REPORT_DIR"
