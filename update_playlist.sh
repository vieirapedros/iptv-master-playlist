#!/bin/bash
# ==========================================================
# update_playlist.sh
# Playlist master com:
# - deduplicação por URL e nome
# - organização por país e categoria
# - leitura de tvg-country e group-title
# - blacklist persistente
# - teste robusto de conectividade
# ==========================================================

set -euo pipefail

OUTPUT="master.m3u"
TEMP_RAW="temp_raw.m3u"
TEMP_DEDUP="temp_dedup.m3u"
TEMP_FILTERED="temp_filtered.m3u"
BLACKLIST="blacklist.txt"
TEMP_BLACKLIST="blacklist_new.txt"
LOG="update.log"

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

COUNTRY_ORDER=(BR PT AR MX PE ES US GB IT FR JP UN)

declare -A COUNTRY_NAMES=(
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
rm -f "$OUTPUT" "$TEMP_RAW" "$TEMP_DEDUP" "$TEMP_FILTERED" "$TEMP_BLACKLIST"
touch "$BLACKLIST"

echo "#EXTM3U" > "$OUTPUT"

echo "🔄 Baixando listas..."
for url in "${URLS[@]}"; do
  curl -fsSL --connect-timeout 10 --max-time 30 "$url" | sed '/^#EXTM3U$/d' >> "$TEMP_RAW" || true
done

TOTAL_ANTES=$(grep -c '^#EXTINF' "$TEMP_RAW" 2>/dev/null || echo 0)
echo "📊 Canais brutos: $TOTAL_ANTES"

awk '
function trim(s){gsub(/^[ \t]+|[ \t]+$/, "", s); return s}
function up(s){return toupper(s)}
function normalize(s){s=up(s); gsub(/Á|À|Ã|Â/, "A", s); gsub(/É|Ê/, "E", s); gsub(/Í/, "I", s); gsub(/Ó|Õ|Ô/, "O", s); gsub(/Ú/, "U", s); gsub(/Ç/, "C", s); return s}
function detect_country(text,  t){
  t=normalize(text)
  if (t ~ /BRAZIL|BRASIL|\bBR\b/) return "BR"
  if (t ~ /PORTUGAL|\bPT\b/) return "PT"
  if (t ~ /ARGENTINA|\bAR\b/) return "AR"
  if (t ~ /MEXICO|MÉXICO|\bMX\b/) return "MX"
  if (t ~ /PERU|\bPE\b/) return "PE"
  if (t ~ /ESPANA|ESPAÑA|SPAIN|\bES\b/) return "ES"
  if (t ~ /UNITED STATES|USA|\bUS\b/) return "US"
  if (t ~ /UNITED KINGDOM|UK|BRITAIN|\bGB\b/) return "GB"
  if (t ~ /ITALY|ITALIA|\bIT\b/) return "IT"
  if (t ~ /FRANCE|\bFR\b/) return "FR"
  if (t ~ /JAPAN|\bJP\b/) return "JP"
  return "UN"
}

/^#EXTINF/ {
  meta=$0
  name=meta
  if (match(meta, /tvg-country="[^"]+"/)) {
    country=substr(meta, RSTART+12, RLENGTH-13)
  } else country=""
  if (match(meta, /group-title="[^"]+"/)) {
    grp=substr(meta, RSTART+13, RLENGTH-14)
  } else grp=""
  sub(/^.*,/ , "", name)
  name=trim(name)
  next
}
/^(http|https|rtmp|rtsp|m3u8):/ {
  url=trim($0)
  if (seen_url[url]++) next
  keytext = name " " grp " " country " " url
  c = (country != "" ? detect_country(country) : detect_country(keytext))
  print "##COUNTRY:" c
  print "##GROUP:" grp
  print meta
  print url
  print ""
  name=""; grp=""; country=""
}
' "$TEMP_RAW" > "$TEMP_DEDUP"

# Filtra blacklist e valida URL
current_country="UN"
current_group=""
current_meta=""
current_url=""

extract_country() {
  local txt="$1"
  txt=$(echo "$txt" | tr '[:lower:]' '[:upper:]')
  case "$txt" in
    *BRAZIL*|*BRASIL*|*"BR"*|* BR *) echo BR ;;
    *PORTUGAL*|*"PT"*|* PT *) echo PT ;;
    *ARGENTINA*|*"AR"*|* AR *) echo AR ;;
    *MEXICO*|*"MX"*|* MX *) echo MX ;;
    *PERU*|*"PE"*|* PE *) echo PE ;;
    *SPAIN*|*ESPANA*|*ESPAÑA*|*"ES"*|* ES *) echo ES ;;
    *USA*|*UNITED\ STATES*|*"US"*|* US *) echo US ;;
    *UK*|*UNITED\ KINGDOM*|*BRITAIN*|*"GB"*|* GB *) echo GB ;;
    *ITALY*|*ITALIA*|*"IT"*|* IT *) echo IT ;;
    *FRANCE*|*"FR"*|* FR *) echo FR ;;
    *JAPAN*|*"JP"*|* JP *) echo JP ;;
    *) echo UN ;;
  esac
}

test_channel() {
  local URL="$1"
  local retries=2
  local timeout=8
  local code=0
  for i in $(seq 1 $retries); do
    code=$(curl -sL -r 0-1024 --connect-timeout "$timeout" --max-time "$timeout" -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null || echo 0)
    if [ "$code" = "200" ] || [ "$code" = "206" ]; then
      return 0
    fi
    [ "$i" -lt "$retries" ] && sleep 1
  done
  return 1
}

while IFS= read -r line; do
  case "$line" in
    '##COUNTRY:'*)
      current_country=${line###COUNTRY:}
      ;;
    '##GROUP:'*)
      current_group=${line###GROUP:}
      ;;
    '#EXTINF:'*)
      current_meta="$line"
      ;;
    'http://'*)
      current_url="$line"
      if grep -qF -- "$current_url" "$BLACKLIST" 2>/dev/null; then
        echo "⏭️ Blacklist: ${current_url:0:60}..."
        continue
      fi
      if test_channel "$current_url"; then
        final_country=$(extract_country "$current_meta $current_group $current_country")
        echo "##COUNTRY:$final_country" >> "$TEMP_FILTERED"
        [ -n "$current_group" ] && echo "##GROUP:$current_group" >> "$TEMP_FILTERED"
        echo "$current_meta" >> "$TEMP_FILTERED"
        echo "$current_url" >> "$TEMP_FILTERED"
        echo "" >> "$TEMP_FILTERED"
      else
        echo "$current_url" >> "$TEMP_BLACKLIST"
      fi
      ;;
  esac
done < "$TEMP_DEDUP"

# Reorganiza por país e grupo no arquivo final
{
  echo "#EXTM3U"
  for cc in "${COUNTRY_ORDER[@]}"; do
    echo "#EXTGRP:${COUNTRY_NAMES[$cc]}"
    awk -v target="$cc" '
      BEGIN { show=0 }
      /^##COUNTRY:/ { show = (substr($0,12) == target); next }
      /^##GROUP:/ { grp = substr($0,9); next }
      /^#EXTINF:/ { meta=$0; next }
      /^http/ {
        if (show) {
          if (grp != "") print "#EXTGRP:" grp
          print meta
          print $0
          print ""
        }
        meta=""
      }
    ' "$TEMP_FILTERED"
  done
} > "$OUTPUT"

# Remove linhas internas se sobrarem
sed -i '/^##COUNTRY:/d;/^##GROUP:/d' "$OUTPUT"

cat "$TEMP_BLACKLIST" 2>/dev/null >> "$BLACKLIST" || true
sort -u "$BLACKLIST" -o "$BLACKLIST"

rm -f "$TEMP_RAW" "$TEMP_DEDUP" "$TEMP_FILTERED" "$TEMP_BLACKLIST"

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
