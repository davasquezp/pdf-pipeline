FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    poppler-utils \
    tesseract-ocr \
    tesseract-ocr-ara \
    tesseract-ocr-eng \
    tesseract-ocr-fra \
    tesseract-ocr-rus \
    tesseract-ocr-spa \
    pandoc \
    python3 \
    bash \
    && apt-get clean

WORKDIR /data

COPY config.env /data/config.env
COPY pipeline.sh /data/pipeline.sh
COPY run.sh /data/run.sh
COPY analyze-output.sh /data/analyze-output.sh

RUN chmod +x /data/pipeline.sh /data/run.sh /data/analyze-output.sh
