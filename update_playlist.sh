#!/bin/bash
# =====================================
# Script: update_playlist.sh
# Versão: Blindada (Ignora falhas em links de API/SSAI)
# =====================================

OUTPUT="master.m3u"
TEMP_RAW="temp_raw.m3u"
BLACKLIST="blacklist.txt"

touch "$BLACKLIST"

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

rm -f "$OUTPUT" "$TEMP_RAW"
echo "#EXTM3U" > "$OUTPUT"

echo "🔄 Baixando listas..."
for url in "${URLS[@]}"; do
  curl -sL --connect-timeout 15 "$url" | sed '/^#EXTM3U/d' >> "$TEMP_RAW"
done

echo "🧹 Validando canais..."
rm -f blacklist_new.txt && touch blacklist_new.txt

awk '
  /^#EXTINF/ || /^#EXTGRP/ { buffer = (buffer == "" ? $0 : buffer ORS $0); next }
  /^(http|https|rtmp|rtsp|mms):/ {
    if (!seen[$0]++) {
      if (buffer != "") print buffer "!!!" $0;
    }
    buffer = "";
  }
' "$TEMP_RAW" | while IFS="!!!" read -r METADATA URL; do

    [ -z "$URL" ] && continue

    # REGRA DE EXCEÇÃO: Se o link tiver cara de API/AdServer, aceita direto sem testar
    if [[ "$URL" == *"[ADS"* ]] || [[ "$URL" == *"[CACHE"* ]] || [[ "$URL" == *"aniview.com"* ]] || [[ "$URL" == *"ott.tv"* ]]; then
        echo -e "$METADATA\n$URL" >> "$OUTPUT"
        continue
    fi

    RETEST=false
    if grep -qF "$URL" "$BLACKLIST"; then RETEST=true; fi

    # TESTE HÍBRIDO
    if [[ "$URL" == *".m3u8"* ]]; then
        HTTP_STATUS=$(curl -skL --connect-timeout 8 -m 12 \
           -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36" \
           "$URL" -o /dev/null -w "%{http_code}")
    else
        HTTP_STATUS=$(curl -skL --connect-timeout 8 -m 15 \
           -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36" \
           -H "Referer: https://app.plex.tv/" \
           --range 0-10 \
           "$URL" -o /dev/null -w "%{http_code}")
    fi

    if echo "$HTTP_STATUS" | grep -qE "200|206|301|302"; then
        echo -e "$METADATA\n$URL" >> "$OUTPUT"
    else
        if [ "$RETEST" = true ]; then
             echo "🚫 REMOVIDO: $URL"
        else
             echo "❌ BLACKLIST: $URL"
             echo "$URL" >> blacklist_new.txt
             echo -e "$METADATA\n$URL" >> "$OUTPUT"
        fi
    fi
done

mv blacklist_new.txt "$BLACKLIST"
rm -f "$TEMP_RAW"

echo "✅ Finalizado! Total: $(grep -c "^#EXTINF" "$OUTPUT")"
