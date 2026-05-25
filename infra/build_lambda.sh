#!/usr/bin/env bash
# Build a Lambda deployment zip with ingestion code + requests dependency
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$SCRIPT_DIR/.terraform-tmp"
BUILD_DIR="$TMP_DIR/lambda_build"
ZIP_PATH="$TMP_DIR/ingestion.zip"
SRC_DIR="$SCRIPT_DIR/../ingestion"

# Ensure output dir exists, clean previous build
mkdir -p "$TMP_DIR"
rm -rf "$BUILD_DIR" "$ZIP_PATH"
mkdir -p "$BUILD_DIR"

# Install requests into build dir (suppresses warnings about other env conflicts)
pip install --target "$BUILD_DIR" \
    --quiet --no-cache-dir --disable-pip-version-check \
    "requests>=2.32.0" 2>/dev/null || \
  pip install --target "$BUILD_DIR" --no-cache-dir "requests>=2.32.0"

# Copy ingestion module
mkdir -p "$BUILD_DIR/ingestion"
cp "$SRC_DIR"/*.py "$BUILD_DIR/ingestion/"

# Zip the bundle
(cd "$BUILD_DIR" && zip -qr "$ZIP_PATH" .)

echo "Built: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"
