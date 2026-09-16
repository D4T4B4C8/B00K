#!/usr/bin/env bash
#
# png-to-webp.sh
# ------------------------------------------------------------
# Converts every .png in a folder to .webp, then deletes the
# original .png — but only after confirming the .webp was
# written successfully, so you never lose an image.
#
# Usage:
#   ./png-to-webp.sh [folder] [quality]
#
#   folder   Path to the folder with your PNGs (default: front_image)
#   quality  WebP quality 0-100 (default: 80 — visually near-
#            lossless for photos/art, big size savings)
#
# Requires ONE of:
#   - cwebp (part of Google's libwebp tools), or
#   - ImageMagick (the "convert" or "magick" command)
# The script auto-detects whichever is installed.
#
# Install options if neither is present:
#   macOS:   brew install webp
#   Ubuntu:  sudo apt install webp
#   or:      sudo apt install imagemagick
# ------------------------------------------------------------

set -euo pipefail

DIR="${1:-front_image}"
QUALITY="${2:-80}"

if [[ ! -d "$DIR" ]]; then
  echo "ERROR: folder not found: $DIR" >&2
  echo "Usage: $0 [folder] [quality]" >&2
  exit 1
fi

# ---- pick a converter ----
CONVERTER=""
if command -v cwebp >/dev/null 2>&1; then
  CONVERTER="cwebp"
elif command -v magick >/dev/null 2>&1; then
  CONVERTER="magick"
elif command -v convert >/dev/null 2>&1; then
  CONVERTER="convert"
else
  echo "ERROR: no WebP converter found. Install one of:" >&2
  echo "  macOS:  brew install webp" >&2
  echo "  Ubuntu: sudo apt install webp        (gives you cwebp)" >&2
  echo "  or:     sudo apt install imagemagick" >&2
  exit 1
fi

echo "Folder     : $DIR"
echo "Quality    : $QUALITY"
echo "Converter  : $CONVERTER"
echo

shopt -s nullglob nocaseglob
pngs=("$DIR"/*.png)
shopt -u nocaseglob
shopt -u nullglob

if [[ ${#pngs[@]} -eq 0 ]]; then
  echo "No .png files found in $DIR — nothing to do."
  exit 0
fi

converted=0
skipped=0

for png in "${pngs[@]}"; do
  webp="${png%.*}.webp"
  base="$(basename "$png")"

  if [[ -e "$webp" ]]; then
    echo "SKIP  $base  (a .webp with that name already exists)"
    skipped=$((skipped+1))
    continue
  fi

  case "$CONVERTER" in
    cwebp)
      cwebp -quiet -q "$QUALITY" "$png" -o "$webp"
      ;;
    magick)
      magick "$png" -quality "$QUALITY" "$webp"
      ;;
    convert)
      convert "$png" -quality "$QUALITY" "$webp"
      ;;
  esac

  # Only delete the original once we're sure the webp is really there
  # and isn't a zero-byte/corrupt file.
  if [[ -s "$webp" ]]; then
    rm -f "$png"
    echo "OK    $base  ->  $(basename "$webp")"
    converted=$((converted+1))
  else
    echo "FAIL  $base  (webp not created — original .png left untouched)" >&2
    rm -f "$webp" 2>/dev/null || true
  fi
done

echo
echo "Done. Converted: $converted   Skipped: $skipped"
if [[ "$converted" -gt 0 ]]; then
  echo
  echo "Remember: your index.html book list still references the old"
  echo "*.png filenames (e.g. front_image/41.png) — update those to"
  echo "*.webp, or let me know and I'll update them for you."
fi
