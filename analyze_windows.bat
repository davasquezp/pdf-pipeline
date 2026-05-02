@echo off
set OUTPUT=%1

if "%OUTPUT%"=="" (
    echo Usage: analyze_windows.bat output_folder
    exit /b
)

docker run --rm ^
  -v "%OUTPUT%:/data/output" ^
  pdf-pipeline /data/analyze-output.sh "/data/output"
