#!/usr/bin/env bash
#
# add-book.sh — one-stop script for "My Reading Corner"
#
# This merges what used to be two scripts:
#   1. make-reading-page.sh  (turns tagged book notes into a styled page)
#   2. add_book.sh           (adds a book card + cover to the shelf page)
#
# Now it does both in one run:
#   - builds the reading-notes page from your tagged outline .txt
#   - saves it into a BOOK_NN folder (you just type the number, e.g. 44
#     -> saved to BOOK_44/)
#   - adds a matching book card (with cover image) to your shelf HTML,
#     linking straight to the new page
#
# USAGE — just give it the book number, everything else is automatic:
#   ./add-book.sh 44
#   ./add-book.sh --num 44
#
# With just a number, the script assumes:
#   shelf page   -> ./index.html               (auto-detected, cwd)
#   notes file   -> BOOK_44/44tags.txt
#   cover image  -> front_image/44.png          (referenced by path, NOT base64)
#   title        -> the B="..." line in the notes file
#   author       -> the A="..." line in the notes file
#   subhead      -> "Reading notes on <title>" (no prompt)
#
# USAGE (flags, for overriding any of the above):
#   ./add-book.sh --num 44 --shelf other-shelf.html --notes mynotes.txt \
#       --title "Atomic Habits" --author "James Clear" --image cover.jpg \
#       [--subhead "Custom subhead"]
#
# Notes file format (same as before — one line per entry):
#   B="Book Title"        <- first line: the book's title
#   A="Author Name"       <- second line: the author (both auto-detected
#                             and stripped out, they don't appear as body text)
#   H1|Major heading (a Part, a Chapter, a standalone section)
#   H2|Sub-heading nested under the H1 above (a Principle, a Rule...)
#   P|A plain paragraph (intro/transition prose, no label)
#   B|Label: a detail point - the text before the first colon is bolded
#   S|A nested example/sub-item under the B point above it
#
# NOTE: the "B=" title line and the "B|" body-point tag look similar but
# are different things — B="..." (with an = and quotes) is only ever
# treated as the title when it's the whole line.
#
# For the "Listen" audio section on the generated page to work, place
# b.m4a (Broadcast) and d.m4a (Debate) in the BOOK_NN folder alongside
# the generated page.

set -uo pipefail

# ---------------------------------------------------------------------------
# 0. Parse flags (all optional — anything missing gets asked for below)
# ---------------------------------------------------------------------------
SHELF_FILE=""
NOTES_FILE=""
BOOK_NUM=""
TITLE=""
AUTHOR=""
SUBHEAD=""
IMG_PATH=""

usage() {
  cat <<'USAGE'
Usage: ./add-book.sh <number>
       ./add-book.sh [options]

Just give it the book number — e.g. `./add-book.sh 44` — and it will
auto-detect index.html, BOOK_44/44tags.txt, and front_image/44.png.

Options (override any auto-detected value):
  --shelf   <file.html>  Shelf/index page (default: ./index.html)
  --notes   <file.txt>   Tagged notes file (default: BOOK_<num>/<num>tags.txt)
  --num     <n>          Folder number — 44 means the page is saved to BOOK_44/
  --title   <text>       Book title (default: auto-detected B="..." line)
  --author  <text>       Author name (default: auto-detected A="..." line)
  --image   <path>       Cover image (default: front_image/<num>.png)
  --subhead <text>       Subhead line on the reading page (optional)
  -h, --help             Show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --shelf)   SHELF_FILE="${2:-}"; shift 2 ;;
    --notes)   NOTES_FILE="${2:-}"; shift 2 ;;
    --num)     BOOK_NUM="${2:-}"; shift 2 ;;
    --title)   TITLE="${2:-}"; shift 2 ;;
    --author)  AUTHOR="${2:-}"; shift 2 ;;
    --image)   IMG_PATH="${2:-}"; shift 2 ;;
    --subhead) SUBHEAD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    # bare number, e.g. `./add-book.sh 44` -> shorthand for --num 44
    [0-9]*)    BOOK_NUM="$1"; shift ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

# Small helper: strip stray quotes/leading tilde some terminals add when
# dragging a file in, or that people paste around a path.
clean_path() {
  local p="$1"
  p="${p/#\~/$HOME}"
  p="${p%\"}"; p="${p#\"}"
  p="${p%\'}"; p="${p#\'}"
  printf '%s' "$p"
}

html_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# 1. Shelf page — auto-detected as index.html in the current folder
# ---------------------------------------------------------------------------
if [[ -z "$SHELF_FILE" ]]; then
  SHELF_FILE="index.html"
fi
SHELF_FILE="$(clean_path "$SHELF_FILE")"

if [[ ! -f "$SHELF_FILE" ]]; then
  echo "Can't find '$SHELF_FILE' in the current folder."
  echo "Run this script from the folder that contains index.html, or pass --shelf <file.html>."
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Folder number — 44 means the new page is saved to BOOK_44/
# ---------------------------------------------------------------------------
if [[ -z "$BOOK_NUM" ]]; then
  read -p "Folder number for this book (e.g. 44 -> saved to BOOK_44/): " BOOK_NUM
fi
BOOK_NUM="$(clean_path "$BOOK_NUM")"
if [[ -z "$BOOK_NUM" ]]; then
  echo "No folder number entered."
  exit 1
fi
if [[ ! "$BOOK_NUM" =~ ^[0-9]+$ ]]; then
  echo "Folder number should just be digits (e.g. 44), got '$BOOK_NUM'."
  exit 1
fi
OUTDIR="BOOK_${BOOK_NUM}"
mkdir -p "$OUTDIR"
echo "Reading page will be saved in ${OUTDIR}/"
echo

# ---------------------------------------------------------------------------
# 3. Notes file — auto-derived as BOOK_<num>/<num>tags.txt
# ---------------------------------------------------------------------------
if [[ -z "$NOTES_FILE" ]]; then
  NOTES_FILE="${OUTDIR}/${BOOK_NUM}tags.txt"
fi
NOTES_FILE="$(clean_path "$NOTES_FILE")"
if [[ ! -f "$NOTES_FILE" ]]; then
  echo "Error: file not found: $NOTES_FILE"
  echo "Expected your tags file at ${OUTDIR}/${BOOK_NUM}tags.txt — pass --notes <file> if it's somewhere else."
  exit 1
fi

# ---- auto-detect title (B="...") and author (A="...") from the tags file ----
if [[ -z "$TITLE" ]]; then
  BLINE=$(grep -m1 -E '^B=".*"$' "$NOTES_FILE" | tr -d '\r')
  if [[ "$BLINE" =~ ^B=\"(.*)\"$ ]]; then
    TITLE="${BASH_REMATCH[1]}"
  fi
fi
if [[ -z "$TITLE" ]]; then
  read -p "Book title (no B=\"...\" line found in $NOTES_FILE): " TITLE
fi
if [[ -z "$TITLE" ]]; then
  echo "Error: could not auto-detect a title from $NOTES_FILE, and none was entered."
  exit 1
fi

if [[ -z "$AUTHOR" ]]; then
  ALINE=$(grep -m1 -E '^A=".*"$' "$NOTES_FILE" | tr -d '\r')
  if [[ "$ALINE" =~ ^A=\"(.*)\"$ ]]; then
    AUTHOR="${BASH_REMATCH[1]}"
  fi
fi
if [[ -z "$AUTHOR" ]]; then
  echo "Note: no A=\"Author Name\" line found in $NOTES_FILE — leaving author blank."
fi

# ---------------------------------------------------------------------------
# 4. Subhead + cover image — both auto-derived, no prompts
# ---------------------------------------------------------------------------
SUBHEAD="${SUBHEAD:-Reading notes on ${TITLE}}"

if [[ -z "$IMG_PATH" ]]; then
  IMG_PATH="front_image/${BOOK_NUM}.png"
fi
IMG_PATH="$(clean_path "$IMG_PATH")"
if [[ ! -f "$IMG_PATH" ]]; then
  echo "Note: no image found yet at '$IMG_PATH' — the shelf card will still point there; just add the file whenever you're ready."
fi

echo
echo "Building the reading page for \"$TITLE\"..."

# ---------------------------------------------------------------------------
# 5. Build the reading page (same logic as make-reading-page.sh) into OUTDIR
# ---------------------------------------------------------------------------
TITLE_ESC="$(html_escape "$TITLE")"
AUTHOR_ESC="$(html_escape "$AUTHOR")"
SUBHEAD_ESC="$(html_escape "$SUBHEAD")"

SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
[ -n "$SLUG" ] || SLUG="untitled"
PAGE_FILE="${OUTDIR}/${SLUG}.html"

BASENAME=$(basename "$NOTES_FILE")
NUM=$(grep -oE '[0-9]+' <<< "$BASENAME" | head -1)
if [ -z "$NUM" ]; then
  NUM=$(( $(find "$OUTDIR" -maxdepth 1 -name '*.html' 2>/dev/null | wc -l) + 1 ))
fi

WORDS=$(wc -w < "$NOTES_FILE")
MINUTES=$(( WORDS / 200 ))
[ "$MINUTES" -lt 1 ] && MINUTES=1

TITLE_LEN=${#TITLE}
if   [ "$TITLE_LEN" -le 14 ]; then HL_MAX="7.3rem"
elif [ "$TITLE_LEN" -le 24 ]; then HL_MAX="5.6rem"
elif [ "$TITLE_LEN" -le 36 ]; then HL_MAX="4.3rem"
else                               HL_MAX="3.4rem"
fi

DATE_ADDED=$(date +"%B %Y")
META_AUTHOR=""
if [ -n "$AUTHOR_ESC" ]; then
  META_AUTHOR="<span class=\"meta-dot\">•</span><span>By ${AUTHOR_ESC}</span>"
fi

BODY_HTML=$(awk '
  function esc(s) {
    gsub(/&/, "\\&amp;", s)
    gsub(/</, "\\&lt;", s)
    gsub(/>/, "\\&gt;", s)
    return s
  }
  function labelize(s,    colonpos, lbl, rest, opens, closes, tmp) {
    colonpos = index(s, ":")
    if (colonpos > 0 && colonpos <= 70) {
      lbl = substr(s, 1, colonpos)
      tmp = lbl; opens  = gsub(/\(/, "(", tmp)
      tmp = lbl; closes = gsub(/\)/, ")", tmp)
      if (opens == closes) {
        rest = substr(s, colonpos + 1)
        sub(/^[ \t]+/, "", rest)
        return "<strong>" esc(lbl) "</strong> " esc(rest)
      }
    }
    return esc(s)
  }
  function emit_para(text, uselabel,    body) {
    body = uselabel ? labelize(text) : esc(text)
    if (firstflag) {
      printf "<p class=\"drop-cap\">%s</p>\n", body
      firstflag = 0
    } else {
      printf "<p>%s</p>\n", body
    }
  }
  BEGIN {
    firstflag = 1
    section = 0
    insub = 0
    n = split("14 16 18 21 24 28 32 36 42 48 56 64 72 84 96 108 120 144 168 192", sizes, " ")
  }
  {
    if (index($0, "|") == 0) next
    tag = substr($0, 1, index($0, "|") - 1)
    content = substr($0, index($0, "|") + 1)
    if (content == "") next

    if (tag == "H1") {
      if (insub) { print "</div>"; insub = 0 }
      idx = section + 1
      if (idx <= n) { ptsize = sizes[idx] } else { ptsize = int(sizes[n] * (1.15 ^ (idx - n))) }
      printf "<div class=\"specimen-row\"><span class=\"specimen-label\">%dpt</span><h2>%s</h2></div>\n", ptsize, esc(content)
      section++
    } else if (tag == "H2") {
      if (insub) { print "</div>"; insub = 0 }
      printf "<h3 class=\"sub-heading\">%s</h3>\n", esc(content)
    } else if (tag == "S") {
      if (!insub) { print "<div class=\"sub-points\">"; insub = 1 }
      emit_para(content, 1)
    } else if (tag == "B") {
      if (insub) { print "</div>"; insub = 0 }
      emit_para(content, 1)
    } else {
      if (insub) { print "</div>"; insub = 0 }
      emit_para(content, 0)
    }
  }
  END {
    if (insub) print "</div>"
  }
' <(sed -e '1s/^\xEF\xBB\xBF//' -e 's/\r$//' -e '/^B=".*"$/d' -e '/^A=".*"$/d' "$NOTES_FILE"))

cat > "$PAGE_FILE" <<HTMLEOF
<!DOCTYPE html>
<html lang="en" data-theme="paper">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${TITLE_ESC} — Reading Notes</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Big+Shoulders+Display:wght@700;900&family=Literata:ital,wght@0,400;0,500;0,600;0,700;1,400;1,500;1,600&family=Space+Mono:ital,wght@0,400;0,700;1,400&display=swap" rel="stylesheet">
<style>
  :root{
    --reg-offset: 11px;
    --measure: 700px;
    --headline-max: ${HL_MAX};
  }
  html[data-theme="paper"]{
    --bg: #EFE2BC; --ink: #18140E; --ink-soft: #5E5540;
    --accent: #7A4E14; --accent-strong: #E0A83A; --mark: #A23324;
    --rule: #DCC98F; --shadow: rgba(24,20,14,.10);
  }
  html[data-theme="press"]{
    --bg: #16130D; --ink: #F1E7CA; --ink-soft: #AE9F7C;
    --accent: #F0C267; --accent-strong: #E0A83A; --mark: #DD6C52;
    --rule: #33291A; --shadow: rgba(0,0,0,.35);
  }
  *,*::before,*::after{ box-sizing:border-box; }
  html{ scroll-behavior:smooth; }
  body{
    margin:0; background:var(--bg); color:var(--ink);
    font-family:'Literata',Georgia,serif;
    -webkit-font-smoothing:antialiased; text-rendering:optimizeLegibility;
    transition:background-color .35s ease, color .35s ease;
  }
  ::selection{ background:var(--accent-strong); color:#18140E; }
  .progress-bar{ position:fixed; top:0; left:0; height:3px; width:0%; background:var(--accent-strong); z-index:50; transition:width .1s ease-out; }
  .masthead{
    max-width:var(--measure); margin:0 auto; padding:1.7rem 1.5rem .9rem;
    display:flex; align-items:center; justify-content:space-between; gap:1rem;
    border-bottom:1px solid var(--rule);
    font-family:'Space Mono',monospace; font-size:.72rem; letter-spacing:.10em;
    text-transform:uppercase; color:var(--ink-soft);
  }
  .masthead-right{ display:flex; align-items:center; gap:.9rem; }
  .proof-toggle{
    display:inline-flex; align-items:center; justify-content:center;
    width:34px; height:34px; border:1px solid var(--rule); border-radius:50%;
    background:transparent; color:var(--ink-soft); cursor:pointer; flex-shrink:0;
    transition:transform .45s ease, color .2s ease, border-color .2s ease;
  }
  .proof-toggle:hover{ color:var(--ink); border-color:var(--accent); }
  .proof-toggle.flipped{ transform:rotate(180deg); }
  .proof-toggle:focus-visible, button:focus-visible{ outline:2px solid var(--accent-strong); outline-offset:3px; }
  main{ max-width:var(--measure); margin:0 auto; padding:0 1.5rem; }
  .hero{ padding-top:2.6rem; }
  .headline-wrap{ position:relative; margin-bottom:1.9rem; }
  .headline-shadow, .headline-main{
    display:block; font-family:'Big Shoulders Display', sans-serif; font-weight:900;
    font-size:clamp(2.2rem, 10vw, var(--headline-max)); line-height:.9;
    letter-spacing:-.01em; text-transform:uppercase;
  }
  .headline-shadow{
    position:absolute; top:0; left:0; right:0; color:var(--accent-strong);
    transform:translate(var(--reg-offset), var(--reg-offset)); z-index:0;
    pointer-events:none; user-select:none;
  }
  .headline-main{ position:relative; z-index:1; color:var(--ink); }
  .subhead{
    font-style:italic; font-weight:500; font-size:clamp(1.08rem, 2vw, 1.32rem);
    line-height:1.5; color:var(--ink-soft); max-width:52ch; margin:0 0 1.6rem;
  }
  .meta-row{
    font-family:'Space Mono',monospace; font-size:.76rem; letter-spacing:.09em;
    text-transform:uppercase; color:var(--ink-soft);
    display:flex; align-items:center; gap:.6rem; padding-bottom:2.2rem; flex-wrap:wrap;
  }
  .meta-dot{ opacity:.6; }
  hr.hero-rule{ border:none; height:1px; background:var(--rule); margin:0 0 2.6rem; }
  .body-text p{ font-size:1.16rem; line-height:1.75; color:var(--ink); max-width:64ch; margin:0 0 1.5rem; }
  .drop-cap::first-letter{
    font-family:'Big Shoulders Display', sans-serif; font-weight:900; font-size:4.1em;
    line-height:.72; float:left; padding:.06em .09em 0 0; color:var(--accent);
  }
  .body-text strong{ font-weight:700; color:var(--ink); }
  .body-text em{ font-style:italic; }
  .specimen-row{ display:flex; align-items:baseline; gap:.9rem; margin:3.1rem 0 1.05rem; }
  .specimen-label{
    font-family:'Space Mono',monospace; font-size:.72rem; font-weight:700; letter-spacing:.05em;
    color:var(--accent); background:var(--rule); padding:.2rem .5rem; border-radius:2px; white-space:nowrap;
  }
  .specimen-row h2{
    margin:0; font-family:'Big Shoulders Display', sans-serif; font-weight:700;
    font-size:clamp(1.4rem, 3vw, 2rem); text-transform:uppercase; letter-spacing:.005em; color:var(--ink);
  }
  .sub-heading{
    font-family:'Big Shoulders Display', sans-serif; font-weight:700;
    font-size:clamp(1.1rem, 2vw, 1.4rem); text-transform:uppercase; letter-spacing:.008em;
    color:var(--ink); margin:2.3rem 0 .9rem; padding-left:.8rem; border-left:3px solid var(--accent);
  }
  .sub-points{ margin:-.4rem 0 1.5rem 1.6rem; padding-left:1rem; border-left:2px solid var(--rule); }
  .sub-points p{ font-size:1.02rem; color:var(--ink-soft); margin-bottom:.9rem; }
  blockquote{
    margin:1rem 0 2.7rem; padding-left:1.4rem; border-left:4px solid var(--accent-strong);
    font-style:italic; font-weight:600; font-size:clamp(1.4rem, 2.7vw, 1.85rem);
    line-height:1.35; color:var(--ink); max-width:32ch;
  }
  .audio-section{ margin:3.6rem 0 1rem; padding-top:2.4rem; border-top:1px solid var(--rule); }
  .audio-section-title{
    font-family:'Space Mono',monospace; font-size:.72rem; letter-spacing:.16em;
    text-transform:uppercase; color:var(--ink-soft); margin:0 0 1.3rem;
  }
  .audio-grid{ display:grid; grid-template-columns:1fr 1fr; gap:1.1rem; }
  .audio-card{
    border:1px solid var(--rule); border-radius:4px; padding:1.15rem 1.25rem 1.35rem;
    background:transparent; transition:border-color .2s ease, background-color .2s ease;
  }
  .audio-card:hover{ border-color:var(--accent); }
  .audio-card-label{ display:flex; align-items:center; gap:.6rem; margin-bottom:.9rem; }
  .audio-card-badge{
    font-family:'Space Mono',monospace; font-size:.66rem; font-weight:700; letter-spacing:.06em;
    color:var(--accent); background:var(--rule); padding:.2rem .5rem; border-radius:2px; text-transform:uppercase;
  }
  .audio-card-name{
    font-family:'Big Shoulders Display', sans-serif; font-weight:700; font-size:1.2rem;
    text-transform:uppercase; letter-spacing:.01em; color:var(--ink);
  }
  .audio-card audio{ width:100%; accent-color:var(--accent-strong); }
  .audio-card audio::-webkit-media-controls-panel{ background-color:transparent; }
  @media (max-width:640px){ .audio-grid{ grid-template-columns:1fr; } }
  footer.colophon{
    text-align:center; font-family:'Space Mono',monospace; font-size:.7rem;
    letter-spacing:.16em; text-transform:uppercase; color:var(--ink-soft); padding:1rem 0 4.5rem;
  }
  @media (prefers-reduced-motion: reduce){ *{ transition:none !important; } }
  @media (max-width:640px){
    :root{ --reg-offset:6px; }
    .masthead-typeface{ display:none; }
    .hero{ padding-top:2rem; }
    main{ padding:0 1.15rem; }
    .masthead{ padding:1.4rem 1.15rem .8rem; }
  }
</style>
</head>
<body>

  <div class="progress-bar" id="progress"></div>

  <header class="masthead">
    <span>Specimen No. ${NUM}</span>
    <div class="masthead-right">
      <span class="masthead-typeface">Set in Big Shoulders Display</span>
      <button class="proof-toggle" id="theme-toggle" title="Flip to press proof" aria-label="Toggle dark reading mode">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
          <circle cx="8" cy="8" r="6.5" stroke="currentColor" stroke-width="1.4"/>
          <line x1="8" y1="0.5" x2="8" y2="15.5" stroke="currentColor" stroke-width="1.4"/>
          <line x1="0.5" y1="8" x2="15.5" y2="8" stroke="currentColor" stroke-width="1.4"/>
        </svg>
      </button>
    </div>
  </header>

  <main>
    <article>
      <div class="hero">
        <div class="headline-wrap">
          <span class="headline-shadow" aria-hidden="true">${TITLE_ESC}</span>
          <span class="headline-main">${TITLE_ESC}</span>
        </div>
        <p class="subhead">${SUBHEAD_ESC}</p>
        <div class="meta-row">
          <span>${MINUTES} min read</span>${META_AUTHOR}
          <span class="meta-dot">•</span>
          <span>Added ${DATE_ADDED}</span>
        </div>
      </div>

      <hr class="hero-rule">

      <div class="body-text">
${BODY_HTML}
      </div>

      <div class="audio-section">
        <p class="audio-section-title">Listen</p>
        <div class="audio-grid">
          <div class="audio-card">
            <div class="audio-card-label">
              <span class="audio-card-badge">Audio</span>
              <span class="audio-card-name">Broadcast</span>
            </div>
            <audio controls preload="none" src="b.m4a">
              Your browser does not support the audio element.
            </audio>
          </div>
          <div class="audio-card">
            <div class="audio-card-label">
              <span class="audio-card-badge">Audio</span>
              <span class="audio-card-name">Debate</span>
            </div>
            <audio controls preload="none" src="d.m4a">
              Your browser does not support the audio element.
            </audio>
          </div>
        </div>
      </div>
    </article>
  </main>

  <footer class="colophon">◆ End of Sheet ◆</footer>

<script>
  const bar = document.getElementById('progress');
  function updateProgress(){
    const scrollTop = window.scrollY;
    const docHeight = document.documentElement.scrollHeight - window.innerHeight;
    const pct = docHeight > 0 ? (scrollTop / docHeight) * 100 : 0;
    bar.style.width = pct + '%';
  }
  window.addEventListener('scroll', updateProgress);
  updateProgress();

  const root = document.documentElement;
  const toggle = document.getElementById('theme-toggle');
  let dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  function applyTheme(){
    root.setAttribute('data-theme', dark ? 'press' : 'paper');
    toggle.classList.toggle('flipped', dark);
  }
  applyTheme();
  toggle.addEventListener('click', () => { dark = !dark; applyTheme(); });
</script>

</body>
</html>
HTMLEOF

echo "Created: ${PAGE_FILE}"
echo

# ---------------------------------------------------------------------------
# 6. Add the matching book card to the shelf page (same logic as add_book.sh)
# ---------------------------------------------------------------------------
echo "Adding a card for \"$TITLE\" to $SHELF_FILE..."

# Cover image is referenced by its file path (e.g. front_image/44.png) —
# not base64-encoded — so the shelf HTML stays small.
IMG_SRC_ESC="$(html_escape "$IMG_PATH")"

# The link on the shelf card points at the page we just generated
BOOK_LINK="${PAGE_FILE}"
LINK_ESC="$(html_escape "$BOOK_LINK")"
IMG_SLUG="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"

COLORS=(coral sky mustard teal plum pink indigo)
CARD_COUNT="$(grep -c 'class="book-btn"' "$SHELF_FILE" || true)"
COLOR="${COLORS[$((CARD_COUNT % ${#COLORS[@]}))]}"

NEW_BLOCK=$(cat <<EOF
    <button class="book-btn" data-title="${TITLE_ESC}" data-author="${AUTHOR_ESC}" data-note="" data-img="${IMG_SLUG}" data-link="${LINK_ESC}">
      <div class="card">
        <div class="tape" style="background:var(--${COLOR});"></div>
        <div class="cover-wrap">
          <img src="${IMG_SRC_ESC}" alt="${TITLE_ESC} book cover" />
          <span class="cover-badge">Peek inside →</span>
        </div>
        <div class="book-title">${TITLE_ESC}</div>
        <div class="book-meta"><span class="dot" style="background:var(--${COLOR});"></span> ${AUTHOR_ESC}</div>
      </div>
    </button>
EOF
)

MAIN_CLOSE_LINE="$(grep -n '</main>' "$SHELF_FILE" | head -n1 | cut -d: -f1)"
if [[ -z "$MAIN_CLOSE_LINE" ]]; then
  echo "Couldn't find the end of the book grid in $SHELF_FILE — is this the right file?"
  exit 1
fi

# Find the last "</button>" that closes a book card, i.e. the last one
# appearing before </main>. This is robust to blank-line spacing drift,
# unlike counting a fixed number of lines back from </main>.
LAST_BTN_LINE="$(awk -v lim="$MAIN_CLOSE_LINE" '
  NR < lim && /<\/button>/ { last = NR }
  END { if (last) print last }
' "$SHELF_FILE")"

if [[ -z "$LAST_BTN_LINE" ]]; then
  echo "Couldn't find any existing book cards in $SHELF_FILE — is this the right file?"
  exit 1
fi

cp "$SHELF_FILE" "${SHELF_FILE}.bak"

TMP_FILE="$(mktemp)"
head -n "$LAST_BTN_LINE" "$SHELF_FILE" > "$TMP_FILE"
printf '\n%s\n' "$NEW_BLOCK" >> "$TMP_FILE"
tail -n +"$((LAST_BTN_LINE + 1))" "$SHELF_FILE" >> "$TMP_FILE"
mv "$TMP_FILE" "$SHELF_FILE"

echo
echo "Done!"
echo "  Reading page: ${PAGE_FILE}"
echo "  Shelf card added to: ${SHELF_FILE} (card color: $COLOR, backup saved to ${SHELF_FILE}.bak)"
echo "Open $SHELF_FILE in your browser to see it on the shelf."
