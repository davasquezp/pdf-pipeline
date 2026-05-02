@echo off
set INPUT=%1
set OUTPUT=%2

if "%INPUT%"=="" (
    echo Usage: launch_windows.bat input_folder output_folder
    exit /b
)

docker run --rm ^
  -v "%INPUT%:/data/input" ^
  -v "%OUTPUT%:/data/output" ^
  pdf-pipeline /data/run.sh "/data/input" "/data/output"
