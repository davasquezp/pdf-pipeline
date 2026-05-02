#!/bin/bash
set -e
source /data/config.env

INPUT="$1"
OUTPUT="$2"

if [ -z "$INPUT" ] || [ -z "$OUTPUT" ]; then
    echo "Usage: run.sh <input_folder> <output_folder>"
    exit 1
fi

echo "Starting pipeline..."
/data/pipeline.sh "$INPUT" "$OUTPUT"
echo "Pipeline completed."




