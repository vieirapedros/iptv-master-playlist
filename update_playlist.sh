#!/bin/bash
# ==========================================================
# update_playlist.sh
# Fix de sintaxe + organização por país
# ==========================================================

set -Eeuo pipefail
trap 'echo "Error on line $LINENO" >&2' ERR

OUTPUT="master.m3u"
RAW="temp_raw.m3u"
BLACKLIST="blacklist.txt"
NEW_BLACKLIST="blacklist_new.txt"
LOG="update.log"
TMPDIR="tmp_playlist"

mkdir -p "$TMPDIR"
exec > >(tee -a "$LOG") 2>&1

URLS=(
  "https://www.apsattv.com/tclbr.m3u"
  "https://www.apsattv.com/brlg.m3u"
  "https://www.apsattv.com/ssungbra.m3u"
  "https://www.apsattv.com/whaletvplus_all.m3u"
  "https://www.apsattv.com/freelivesports.m3u"
  "https://www.apsattv.com/xiaomi.m3u"
  "https://www.apsattv.com/vizio.m3u"
  "https://www.apsattv.com/redbox.m3u"
  "https://www.apsattv.com/rok.m3u"
  "https://www.apsattv.com/vidaa.m3u"
  "https://www.apsattv.com/localnow.m3u"
  "https://www.apsattv.com/moviearkbr.m3u"
  "https://www.apsattv.com/firetv.m3u"
  "https://www.apsattv.com/tcl.m3u"
  "https://www.apsattv.com/tclplus.m3u"
  "https://www.apsattv.com/distro.m3u"
  "https://www.apsattv.com/ssungpor.m3u"
  "https://www.apsattv.com/ssungmex.m3u"
  "https://www.apsattv.com/metax.m3u"
)

COUNTRIES=(BR PT AR MX PE ES US GB IT FR JP UN)
declare -A COUNTRY_NAME=(
  [BR]="Brasil"
  [PT]="Portugal"
  [AR]="Argentina"
  [MX]="México"
  [PE]="Peru"
  [ES]="España"
  [US]="Estados Unidos"
  [GB]="Reino Unido"
  [IT]="Itália"
  [FR]="França"
  [JP]="Japão"
  [UN]="Outros"
)

cleanup() {
  rm -f "$TMPDIR"/*.tmp 2>/dev/null || true
}
trap cleanup EXIT

: > "$RAW"
: > "$OUTPUT"
touch "$BLACKLIST"

echo "#EXTM3U" > "$OUTPUT"
echo "🔄 Baixando listas..."

for u in "${URLS[@]}"; do
  curl -fsSL --connect-timeout 10 --max-time 30 "$u" 2>/dev/null | sed '/^#EXTM3U$/d' >> "$RAW" || true
done

TOTAL_ANTES=$(grep -c '^#EXTINF' "$RAW" 2>/dev/null || echo 0)
echo "📊 Canais brutos: $TOTAL_ANTES"

normalize_country() {
  local txt="$1"
  txt=$(printf '%s' "$txt" | tr '[:lower:]' '[:upper:]')
  txt=$(printf '%s' "$txt" | sed 's/[ÁÀÃÂ]/A/g; s/[ÉÊ]/E/g; s/[Í]/I/g; s/[ÓÕÔ]/O/g; s/[Ú]/U/g; s/[Ç]/C/g')
  case "$txt" in
    *BRAZIL*|*BRASIL* ) echo BR ;;
    *PORTUGAL* ) echo PT ;;
    *ARGENTINA* ) echo AR ;;
    *MEXICO* ) echo MX ;;
    *PERU* ) echo PE ;;
    *SPAIN*|*ESPANA*|*ESPAÑA* ) echo ES ;;
    *USA*|*UNITED STATES* ) echo US ;;
    *UK*|*UNITED KINGDOM*|*BRITAIN* ) echo GB ;;
    *ITALY*|*ITALIA* ) echo IT ;;
    *FRANCE* ) echo FR ;;
    *JAPAN* ) echo JP ;;
    *) echo UN ;;
  esac
}

extract_field() {
  local line="$1" field="$2"
  sed -n "s/.*$field=\"\([^\"]*\)\".*/\1/p" <<< "$line"
}

test_url() {
  local url="$1"
  local code
  code=$(curl -sL -r 0-1024 --connect-timeout 8 --max-time 8 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 0)
  [[ "$code" == "200" || "$code" == "206" ]]
}

: > "$TMPDIR/kept.tmp"
: > "$NEW_BLACKLIST"

meta=""
name=""
country=""
grp=""

while IFS= read -r line; do
  case "$line" in
    '#EXTINF:'*)
      meta="$line"
      name="${line##*,}"
      country="$(extract_field "$line" 'tvg-country')"
      grp="$(extract_field "$line" 'group-title')"
      ;;
    http://*|https://*|rtmp://*|rtsp://*|m3u8://*)
      url="$line"
      if [ -z "$meta" ]; then
        continue
      fi

      if grep -qF -- "$url" "$BLACKLIST" 2>/dev/null; then
        meta=""
        name=""
        country=""
        grp=""
        continue
      fi

      if test_url "$url"; then
        final_country="$(normalize_country "$country $grp $name $url")"
        printf '%s\n%s\n%s\n%s\n\n' "$meta" "$url" "$final_country" "$grp" >> "$TMPDIR/kept.tmp"
      else
        printf '%s\n' "$url" >> "$NEW_BLACKLIST"
      fi

      meta=""
      name=""
      country=""
      grp=""
      ;;
  esac
done < <(
  for u in "${URLS[@]}"; do
    curl -fsSL --connect-timeout 10 --max-time 30 "$u" 2>/dev/null | sed '/^#EXTM3U$/d' || true
  done
)

cat "$NEW_BLACKLIST" 2>/dev/null >> "$BLACKLIST" || true
sort -u "$BLACKLIST" -o "$BLACKLIST"

awk -v out="$OUTPUT" '
BEGIN { RS="\n\n" }
NF >= 4 {
  meta=$1; url=$2; country=$3; grp=$4
  blocks[country] = blocks[country] sprintf("%s\n%s\n\n", meta, url)
}
END {
  print "#EXTM3U" > out
  split("BR PT AR MX PE ES US GB IT FR JP UN", order, " ")
  names["BR"]="Brasil"; names["PT"]="Portugal"; names["AR"]="Argentina"; names["MX"]="México"; names["PE"]="Peru"; names["ES"]="España"; names["US"]="Estados Unidos"; names["GB"]="Reino Unido"; names["IT"]="Itália"; names["FR"]="França"; names["JP"]="Japão"; names["UN"]="Outros"
  for (i=1; i<=12; i++) {
    c=order[i]
    print "#EXTGRP:" names[c] >> out
    if (c in blocks) printf "%s", blocks[c] >> out
  }
}
' "$TMPDIR/kept.tmp"

FINAL_COUNT=$(grep -c '^#EXTINF' "$OUTPUT" 2>/dev/null || echo 0)
SUCCESS_RATE=$([ "$TOTAL_ANTES" -eq 0 ] && echo 0 || echo $((FINAL_COUNT * 100 / TOTAL_ANTES)))

echo "=========================================="
echo "✅ FINALIZADO!"
echo "📊 Brutos: $TOTAL_ANTES"
echo "📊 Funcionais: $FINAL_COUNT"
echo "📊 Taxa de sucesso: $SUCCESS_RATE%"
echo "📄 Saída: $OUTPUT"
echo "📄 Blacklist: $BLACKLIST"
echo "📄 Log: $LOG"
echo "=========================================="
