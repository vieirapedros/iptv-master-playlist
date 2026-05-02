#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "Error on line $LINENO" >&2' ERR

OUTPUT="master.m3u"
RAW="temp_raw.m3u"
BLOCKS="temp_blocks.tsv"
BLACKLIST="blacklist.txt"
NEW_BLACKLIST="blacklist_new.txt"
LOG="update.log"

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

mkdir -p output
: > "$RAW"
: > "$BLOCKS"
: > "$NEW_BLACKLIST"
touch "$BLACKLIST"

exec > >(tee -a "$LOG") 2>&1

normalize() {
  local s="$1"
  s=$(printf '%s' "$s" | tr '[:lower:]' '[:upper:]')
  s=$(printf '%s' "$s" | sed 's/[ÁÀÃÂ]/A/g; s/[ÉÊ]/E/g; s/[Í]/I/g; s/[ÓÕÔ]/O/g; s/[Ú]/U/g; s/[Ç]/C/g')
  printf '%s' "$s"
}

country_from_text() {
  local s
  s=$(normalize "$1")
  case "$s" in
    *BRAZIL*|*BRASIL*) echo BR ;;
    *PORTUGAL*) echo PT ;;
    *ARGENTINA*) echo AR ;;
    *MEXICO*) echo MX ;;
    *PERU*) echo PE ;;
    *SPAIN*|*ESPANA*|*ESPAÑA*) echo ES ;;
    *UNITED*STATES*|*USA*) echo US ;;
    *UNITED*KINGDOM*|*UK*|*BRITAIN*) echo GB ;;
    *ITALY*|*ITALIA*) echo IT ;;
    *FRANCE*) echo FR ;;
    *JAPAN*) echo JP ;;
    *) echo UN ;;
  esac
}

extract_attr() {
  local line="$1" attr="$2"
  sed -n "s/.*$attr="([^"]*)".*/\u0001/p" <<< "$line"
}

safe_curl_test() {
  local url="$1"
  local code
  code=$(curl -sL -r 0-1024 --connect-timeout 8 --max-time 8 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || printf '0')
  case "$code" in
    200|206) return 0 ;;
    *) return 1 ;;
  esac
}

fetch_all() {
  for u in "${URLS[@]}"; do
    curl -fsSL --connect-timeout 10 --max-time 30 "$u" 2>/dev/null | sed '/^#EXTM3U$/d' >> "$RAW" || true
  done
}

parse_blocks() {
  awk '
    function trim(s){gsub(/^[ \t]+|[ \t]+$/, "", s); return s}
    /^#EXTINF:/ {
      meta=$0
      name=$0
      sub(/^.*,/ , "", name)
      grp=""
      country=""
      if (match($0, /tvg-country="[^"]+"/)) country=substr($0, RSTART+12, RLENGTH-13)
      if (match($0, /group-title="[^"]+"/)) grp=substr($0, RSTART+13, RLENGTH-14)
      next
    }
    /^https?:/// {
      url=trim($0)
      if (url == "") next
      if (seen[url]++) next
      print meta "\t" url "\t" country "\t" grp
      meta=""; name=""; grp=""; country=""
    }
  ' "$RAW" > "$BLOCKS"
}

build_master() {
  local final_blocks="$1"
  : > "$OUTPUT"
  printf '#EXTM3U
' > "$OUTPUT"
  for c in "${COUNTRIES[@]}"; do
    printf '#EXTGRP:%s
' "${COUNTRY_NAME[$c]}" >> "$OUTPUT"
    while IFS=$'\t' read -r meta url country grp; do
      [ -z "${meta:-}" ] && continue
      if [ "$country" = "$c" ]; then
        printf '%s
%s

' "$meta" "$url" >> "$OUTPUT"
      fi
    done < "$final_blocks"
  done
}

main() {
  fetch_all
  total_before=$(grep -c '^#EXTINF' "$RAW" 2>/dev/null || printf '0')
  echo "📊 Canais brutos: $total_before"

  parse_blocks

  kept="$TMPDIR/kept.tsv"
  mkdir -p "$TMPDIR"
  : > "$kept"
  : > "$NEW_BLACKLIST"

  while IFS=$'\t' read -r meta url country grp; do
    [ -z "${meta:-}" ] && continue
    if grep -qF -- "$url" "$BLACKLIST" 2>/dev/null; then
      continue
    fi
    if safe_curl_test "$url"; then
      final_country="$country"
      [ -z "$final_country" ] && final_country="$(country_from_text "$meta $grp $url")"
      printf '%s\t%s\t%s\t%s
' "$meta" "$url" "$final_country" "$grp" >> "$kept"
    else
      printf '%s
' "$url" >> "$NEW_BLACKLIST"
    fi
  done < "$BLOCKS"

  cat "$NEW_BLACKLIST" 2>/dev/null >> "$BLACKLIST" || true
  sort -u "$BLACKLIST" -o "$BLACKLIST"

  build_master "$kept"

  final_count=$(grep -c '^#EXTINF' "$OUTPUT" 2>/dev/null || printf '0')
  if [ "$total_before" -eq 0 ]; then
    success_rate=0
  else
    success_rate=$(( final_count * 100 / total_before ))
  fi

  echo "=========================================="
  echo "✅ FINALIZADO!"
  echo "📊 Brutos: $total_before"
  echo "📊 Funcionais: $final_count"
  echo "📊 Taxa de sucesso: $success_rate%"
  echo "📄 Saída: $OUTPUT"
  echo "📄 Blacklist: $BLACKLIST"
  echo "📄 Log: $LOG"
  echo "=========================================="
}

main
