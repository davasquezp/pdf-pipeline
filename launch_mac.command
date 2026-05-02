#!/bin/bash
INPUT="$1"
OUTPUT="$2"

if [ -z "$INPUT" ] || [ -z "$OUTPUT" ]; then
  echo "Usage: launch_mac.command input_folder output_folder"
  exit 1
fi

docker run --rm \
  -v "$INPUT:/data/input" \
  -v "$OUTPUT:/data/output" \
  pdf-pipeline /data/run.sh "/data/input" "/data/output"

