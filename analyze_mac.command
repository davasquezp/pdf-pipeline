#!/bin/bash
OUTPUT="$1"

if [ -z "$OUTPUT" ]; then
  echo "Usage: analyze_mac.command output_folder"
  exit 1
fi

docker run --rm \
  -v "$OUTPUT:/data/output" \
  pdf-pipeline /data/analyze-output.sh "/data/output"
