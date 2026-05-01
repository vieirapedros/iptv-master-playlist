#!/bin/bash
# ==========================================================
# update_playlist.sh
# Versão limpa e robusta:
# - baixa listas
# - extrai blocos EXTINF + URL
# - deduplica por URL
# - detecta país por tvg-country, group-title e nome
# - testa conectividade
# - atualiza blacklist
# - gera master.m3u organizado por país
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

declare -a URLS=(
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
  "https://raw.githubusercontent.com/BuddyChewChew/My-Streams/refs/heads/main/Backup.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/buddylive/refs/heads/main/buddylive_v1.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/My-Streams/refs/heads/main/TheTVApp.m3u8"
  "https://raw.githubusercontent.com/BuddyChewChew/xumo-playlist-generator/refs/heads/main/playlists/xumo_playlist.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/ppv/refs/heads/main/PPVLand.m3u8"
  "https://raw.githubusercontent.com/BuddyChewChew/My-Streams/refs/heads/main/StreamedSU.m3u8"
  "https://raw.githubusercontent.com/BuddyChewChew/My-Streams/refs/heads/main/24-7.m3u8"
  "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/refs/heads/main/playlists/roku_all.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/refs/heads/main/playlists/plex_all.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/refs/heads/main/playlists/plutotv_all.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/refs/heads/main/playlists/samsungtvplus_all.m3u"
  "https://www.apsattv.com/ptlg.m3u"
  "https://www.apsattv.com/arlg.m3u"
  "https://www.apsattv.com/mxlg.m3u"
  "https://www.apsattv.com/pelg.m3u"
  "https://www.apsattv.com/eslg.m3u"
  "https://www.apsattv.com/uslg.m3u"
  "https://www.apsattv.com/gblg.m3u"
  "https://www.apsattv.com/itlg.m3u"
  "https://www.apsattv.com/frlg.m3u"
  "https://www.apsattv.com/jplg.m3u"
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

touch "$BLACKLIST"
rm -f "$OUTPUT" "$RAW" "$NEW_BLACKLIST"
: > "$RAW"

fetch_all() {
  for u in "${URLS[@]}"; do
    curl -fsSL --connect-timeout 10 --max-time 30 "$u" 2>/dev/null | sed '/^#EXTM3U$/d' >> "$RAW" || true
  done
}

normalize() {
  tr '[:lower:]' '[:upper:]' | sed 's/[ÁÀÃÂ]/A/g; s/[ÉÊ]/E/g; s/[Í]/I/g; s/[ÓÕÔ]/O/g; s/[Ú]/U/g; s/[Ç]/C/g'
}

detect_country() {
  local txt
  txt=$(printf '%s' "$1" | normalize)
  case "$txt" in
    *BRAZIL*|*BRASIL*|*"BR"*|* BR *) echo BR ;;
    *PORTUGAL*|*"PT"*|* PT *) echo PT ;;
    *ARGENTINA*|*"AR"*|* AR *) echo AR ;;
    *MEXICO*|*"MX"*|* MX *) echo MX ;;
    *PERU*|*"PE"*|* PE *) echo PE ;;
    *SPAIN*|*ESPANA*|*ESPAÑA*|*"ES"*|* ES *) echo ES ;;
    *USA*|*UNITED STATES*|*"US"*|* US *) echo US ;;
    *UK*|*UNITED KINGDOM*|*BRITAIN*|*"GB"*|* GB *) echo GB ;;
    *ITALY*|*ITALIA*|*"IT"*|* IT *) echo IT ;;
    *FRANCE*|*"FR"*|* FR *) echo FR ;;
    *JAPAN*|*"JP"*|* JP *) echo JP ;;
    *) echo UN ;;
  esac
}

test_url() {
  local url="$1"
  local code
  code=$(curl -sL -r 0-1024 --connect-timeout 8 --max-time 8 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 0)
  [[ "$code" == "200" || "$code" == "206" ]]
}

parse_and_filter() {
  awk -v outdir="$TMPDIR" '
    function trim(s){gsub(/^[ \t]+|[ \t]+$/, "", s); return s}
    BEGIN { meta=""; name=""; grp=""; country=""; }
    /^#EXTINF:/ {
      meta=$0
      name=$0
      sub(/^.*,/ , "", name)
      name=trim(name)
      grp=""
      country=""
      if (match($0, /tvg-country="[^"]+"/)) country=substr($0, RSTART+12, RLENGTH-13)
      if (match($0, /group-title="[^"]+"/)) grp=substr($0, RSTART+13, RLENGTH-14)
      next
    }
    /^https?:\/\// {
      url=trim($0)
      if (url == "") next
      if (seen[url]++) next
      printf "%s\n%s\n%s\n%s\n\n", meta, url, country, grp >> (outdir "/all_blocks.txt")
      meta=""; name=""; grp=""; country=""
    }
  ' "$RAW"
}

rebuild_master() {
  local blocks="$TMPDIR/all_blocks.txt"
  : > "$OUTPUT"
  echo "#EXTM3U" > "$OUTPUT"
  for c in "${COUNTRIES[@]}"; do
    echo "#EXTGRP:${COUNTRY_NAME[$c]}" >> "$OUTPUT"
    awk -v target="$c" '
      BEGIN { RS="\n\n" }
      NF >= 4 {
        meta=$1; url=$2; country=$3; grp=$4
        if (country == "") {
          key = meta " " grp " " url
          up = toupper(key)
          gsub(/[ÁÀÃÂ]/, "A", up); gsub(/[ÉÊ]/, "E", up); gsub(/[Í]/, "I", up); gsub(/[ÓÕÔ]/, "O", up); gsub(/[Ú]/, "U", up); gsub(/[Ç]/, "C", up)
          if (up ~ /BRAZIL|BRASIL|(^|[^A-Z])BR([^A-Z]|$)/) country="BR"
          else if (up ~ /PORTUGAL|(^|[^A-Z])PT([^A-Z]|$)/) country="PT"
          else if (up ~ /ARGENTINA|(^|[^A-Z])AR([^A-Z]|$)/) country="AR"
          else if (up ~ /MEXICO|(^|[^A-Z])MX([^A-Z]|$)/) country="MX"
          else if (up ~ /PERU|(^|[^A-Z])PE([^A-Z]|$)/) country="PE"
          else if (up ~ /SPAIN|ESPANA|ESPAÑA|(^|[^A-Z])ES([^A-Z]|$)/) country="ES"
          else if (up ~ /UNITED STATES|USA|(^|[^A-Z])US([^A-Z]|$)/) country="US"
          else if (up ~ /UNITED KINGDOM|UK|BRITAIN|(^|[^A-Z])GB([^A-Z]|$)/) country="GB"
          else if (up ~ /ITALY|ITALIA|(^|[^A-Z])IT([^A-Z]|$)/) country="IT"
          else if (up ~ /FRANCE|(^|[^A-Z])FR([^A-Z]|$)/) country="FR"
          else if (up ~ /JAPAN|(^|[^A-Z])JP([^A-Z]|$)/) country="JP"
          else country="UN"
        }
        if (country == target) {
          if (grp != "") print "#EXTGRP:" grp
          print meta
          print url
          print ""
        }
      }
    ' "$blocks" >> "$OUTPUT"
  done
}

main() {
  fetch_all
  TOTAL_ANTES=$(grep -c '^#EXTINF' "$RAW" 2>/dev/null || echo 0)
  echo "📊 Canais brutos: $TOTAL_ANTES"

  parse_and_filter

  : > "$TMPDIR/kept.txt"
  : > "$NEW_BLACKLIST"

  while IFS= read -r meta && IFS= read -r url && IFS= read -r country && IFS= read -r grp && IFS= read -r blank; do
    [ -z "$url" ] && continue
    if grep -qF -- "$url" "$BLACKLIST" 2>/dev/null; then
      continue
    fi
    if test_url "$url"; then
      printf '%s\n%s\n%s\n%s\n\n' "$meta" "$url" "$country" "$grp" >> "$TMPDIR/kept.txt"
    else
      printf '%s\n' "$url" >> "$NEW_BLACKLIST"
    fi
  done < "$TMPDIR/all_blocks.txt"

  cat "$NEW_BLACKLIST" 2>/dev/null >> "$BLACKLIST" || true
  sort -u "$BLACKLIST" -o "$BLACKLIST"

  mv -f "$TMPDIR/kept.txt" "$TMPDIR/all_blocks.txt"
  rebuild_master

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
}

main
