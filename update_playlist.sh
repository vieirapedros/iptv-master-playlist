#!/bin/bash
# =====================================
# Script: update_playlist.sh
# Lógica: Deduplicação + Teste Paralelo (8 jobs) + Blacklist
# =====================================

OUTPUT="master.m3u"
TEMP_RAW="temp_raw.m3u"
TEMP_DEDUP="temp_dedup.m3u"
BLACKLIST="blacklist.txt"
TEMP_BLACKLIST="blacklist_new.txt"
SEEN_URLS="seen_urls.txt"
SEEN_NAMES="seen_names.txt"

touch "$BLACKLIST"
touch "$SEEN_URLS"
touch "$SEEN_NAMES"

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

rm -f "$OUTPUT" "$TEMP_RAW" "$TEMP_DEDUP" "$TEMP_BLACKLIST" "$SEEN_URLS" "$SEEN_NAMES"
echo "#EXTM3U" > "$OUTPUT"

echo "🔄 Baixando listas..."
for url in "${URLS[@]}"; do
  curl -sL --connect-timeout 10 "$url" | sed '/^#EXTM3U/d' >> "$TEMP_RAW"
done

echo "🧹 DEDUPLICAÇÃO: Removendo canais duplicados (URL + nome)..."

# Deduplica mantendo apenas o primeiro de cada URL ou nome
awk '
  /^#EXTINF/ {
    n = split($0, parts, ",")
    name = parts[n]
    gsub(/^[ \t]+|[ \t]+$/, "", name)
    buffer = $0
    next
  }
  /^#EXTGRP/ { buffer = buffer "\n" $0; next }
  /^(http|https|rtmp|rtsp|m3u8):/ {
    url = $0
    gsub(/^[ \t]+|[ \t]+$/, "", url)

    if (seen_url[url]) { buffer = ""; next }

    if (name && seen_name[name]) { buffer = ""; next }

    seen_url[url] = 1
    if (name) seen_name[name] = 1
    print buffer "\n" url
    buffer = ""
    name = ""
  }
' "$TEMP_RAW" > "$TEMP_DEDUP"

TOTAL_ANTES=$(grep -c "^#EXTINF" "$TEMP_RAW" || echo 0)
TOTAL_DEPOIS=$(grep -c "^#EXTINF" "$TEMP_DEDUP" || echo 0)
echo "📊 Deduplicação: $TOTAL_ANTES → $TOTAL_DEPOIS canais"

# =====================================
# FUNÇÃO DE TESTE (usada em paralelo)
# =====================================
test_channel() {
  local METADATA="$1"
  local URL="$2"

  # Se já na blacklist, falha automaticamente
  if grep -qF "$URL" "$BLACKLIST"; then
    echo "FAIL|$METADATA|$URL"
    return 1
  fi

  local retries=2
  local timeout=5

  for i in $(seq 1 $retries); do
    HTTP_CODE=$(curl -sL -r 0-1024 \
      --connect-timeout $timeout \
      --max-time $timeout \
      -o /dev/null \
      -w "%{http_code}" \
      "$URL" 2>/dev/null)

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "206" ]; then
      echo "OK|$METADATA|$URL"
      return 0
    fi

    if [ $i -lt $retries ]; then
      sleep 1
    fi
  done

  echo "FAIL|$METADATA|$URL"
  return 1
}

echo "🔍 Testando canais em PARALELO (8 jobs simultâneos)..."

# Processa canais deduplicados e testa EM PARALELO
awk '
  /^#EXTINF/ || /^#EXTGRP/ { buffer = (buffer == "" ? $0 : buffer ORS $0); next }
  /^(http|https|rtmp|rtsp|m3u8):/ {
    if (!seen[$0]++) {
      if (buffer != "") print buffer "|||"$0;
    }
    buffer = "";
  }
' "$TEMP_DEDUP" > canais_para_testar.txt

# Testa em paralelo (8 jobs simultâneos)
PARALLEL_JOBS=8
export -f test_channel
export BLACKLIST

cat canais_para_testar.txt | parallel -j $PARALLEL_JOBS --block 1 --line-buffer \
  'IFS="|||" read -r METADATA URL; test_channel "$METADATA" "$URL"' > resultados_teste.txt

# Processa resultados
grep "^OK" resultados_teste.txt | cut -d"|" -f2- | while IFS="|" read -r METADATA URL; do
  echo -e "$METADATA\n$URL" >> "$OUTPUT"
done

grep "^FAIL" resultados_teste.txt | cut -d"|" -f3- >> "$TEMP_BLACKLIST"

rm canais_para_testar.txt resultados_teste.txt

mv "$TEMP_BLACKLIST" "$BLACKLIST" 2>/dev/null || touch "$BLACKLIST"
rm -f "$TEMP_RAW" "$TEMP_DEDUP" "$SEEN_URLS" "$SEEN_NAMES"

echo "✅ Finalizado!"
echo "📊 Canais funcionais: $(grep -c "^#EXTINF" "$OUTPUT")"
