#!/usr/bin/env bash
#
# add_book.sh — Add a new book to dastaan-e-kitab-order_2_.html
#
# Usage:
#   ./add_book.sh
#   ./add_book.sh dastaan-e-kitab-order_2_.html
#
# What it does:
#   1. Asks for the image number (e.g. 05)
#   2. Maps it to front_image/05.png
#   3. Looks up BOOK_05/05tags.txt for the book title, expecting a line like:
#         B="Some Book Title"
#      (optionally also picks up a price line like:  P="60")
#   4. Appends a new entry to the BOOKS array in the HTML file
#
set -euo pipefail

# ---------- config ----------
HTML_FILE="${1:-dastaan-e-kitab-order_2_.html}"
DEFAULT_PRICE=50

# ---------- sanity checks ----------
if [[ ! -f "$HTML_FILE" ]]; then
    echo "Error: HTML file not found: $HTML_FILE"
    exit 1
fi

if ! grep -q "const BOOKS = \[" "$HTML_FILE"; then
    echo "Error: Could not find 'const BOOKS = [' in $HTML_FILE"
    exit 1
fi

# ---------- ask for image number ----------
read -rp "Enter image number (e.g. 05): " RAW_NUM

# strip any non-digits, then zero-pad to 2 digits
NUM_DIGITS=$(echo "$RAW_NUM" | tr -cd '0-9')
if [[ -z "$NUM_DIGITS" ]]; then
    echo "Error: please enter a numeric image number, e.g. 05"
    exit 1
fi
IMG_NUM=$(printf "%02d" "$((10#$NUM_DIGITS))")

IMG_PATH="front_image/${IMG_NUM}.png"
TAGS_DIR="BOOK_${IMG_NUM}"
TAGS_FILE="${TAGS_DIR}/${IMG_NUM}tags.txt"

# ---------- warn (but don't block) if image is missing ----------
if [[ ! -f "$IMG_PATH" ]]; then
    echo "Warning: $IMG_PATH not found on disk yet. It will still be referenced in the HTML."
fi

# ---------- read book title from tags file ----------
if [[ ! -f "$TAGS_FILE" ]]; then
    echo "Error: Tags file not found: $TAGS_FILE"
    echo "Expected something like:"
    echo "  ${TAGS_DIR}/${IMG_NUM}tags.txt"
    echo '  B="Book Title Here"'
    exit 1
fi

# Extract B="..." (book title)
TITLE=$(grep -m1 '^B=' "$TAGS_FILE" | sed -E 's/^B="(.*)"$/\1/')
if [[ -z "$TITLE" ]]; then
    echo "Error: Could not find a line like  B=\"Book Title\"  in $TAGS_FILE"
    exit 1
fi

# Extract P="..." (price) if present, else use default
PRICE=$(grep -m1 '^P=' "$TAGS_FILE" | sed -E 's/^P="(.*)"$/\1/' || true)
if [[ -z "$PRICE" ]]; then
    PRICE="$DEFAULT_PRICE"
fi

# Escape single quotes in the title for safe JS string embedding
SAFE_TITLE=$(echo "$TITLE" | sed "s/'/\\\\'/g")

# ---------- work out a fresh book id (b1, b2, b3 ...) ----------
LAST_NUM=$(grep -oE "id:'b[0-9]+'" "$HTML_FILE" | grep -oE '[0-9]+' | sort -n | tail -1)
if [[ -z "$LAST_NUM" ]]; then
    LAST_NUM=0
fi
NEW_ID="b$((LAST_NUM + 1))"

# ---------- build the new entry line ----------
NEW_LINE="  { id:'${NEW_ID}', title:'${SAFE_TITLE}', price:${PRICE}, img:'${IMG_PATH}' },"

# ---------- insert it just before the closing "];" of the BOOKS array ----------
awk -v newline="$NEW_LINE" '
    BEGIN { in_books = 0; inserted = 0 }
    /const BOOKS = \[/ { in_books = 1 }
    in_books == 1 && /^\];/ && inserted == 0 {
        print newline
        inserted = 1
    }
    { print }
' "$HTML_FILE" > "${HTML_FILE}.tmp"

mv "${HTML_FILE}.tmp" "$HTML_FILE"

echo ""
echo "Added book:"
echo "  id:    $NEW_ID"
echo "  title: $TITLE"
echo "  price: $PRICE"
echo "  img:   $IMG_PATH"
echo ""
echo "Done. $HTML_FILE updated."
