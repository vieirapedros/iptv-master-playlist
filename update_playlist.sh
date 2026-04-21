#!/bin/bash
# =====================================
# Script: update_playlist.sh
# Unificação, Limpeza e Verificação Paralela (20x)
# =====================================

OUTPUT="master.m3u"
TEMP_RAW="temp_raw.m3u"
BLACKLIST="blacklist.txt"
TEMP_ALL_TESTED="tested_channels.txt"

# Garante a existência da blacklist
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
rm -f "$OUTPUT" "$TEMP_RAW" "$TEMP_ALL_TESTED"
echo "#EXTM3U" > "$OUTPUT"

echo "🔄 Baixando listas..."
for url in "${URLS[@]}"; do
  curl -sL --connect-timeout 10 "$url" | sed '/^#EXTM3U/d' >> "$TEMP_RAW"
done

echo "🧹 Removendo duplicatas..."
awk '
  /^#EXTINF/ || /^#EXTGRP/ { buffer = (buffer == "" ? $0 : buffer ORS $0); next }
  /^(http|https|rtmp|rtsp|mms):/ {
    if (!seen[$0]++) {
      if (buffer != "") print buffer "|" $0;
    }
    buffer = "";
  }
' "$TEMP_RAW" > temp_processed.txt

echo "⚡ Testando integridade em paralelo (20 conexões, timeout 5s)..."

export -f curl
test_link() {
    line="$1"
    blacklist_file="blacklist.txt"
    METADATA=$(echo "$line" | cut -d'|' -f1)
    URL=$(echo "$line" | cut -d'|' -f2)
    
    RETEST=false
    if grep -qF "$URL" "$blacklist_file"; then RETEST=true; fi

    # Teste de 5 segundos com User-Agent de Smart TV
    if curl -sI -L --connect-timeout 5 -A "Mozilla/5.0 (SMART-TV; Linux; Tizen 5.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/2.2 Chrome/63.0.3239.84 TV Safari/537.36" "$URL" | grep -qE "200 OK|302 Found|301 Moved"; then
        echo "OK|$METADATA|$URL"
    else
        if [ "$RETEST" = true ]; then
            echo "DEL|$URL"
        else
            echo "BL|$METADATA|$URL"
        fi
    fi
}
export -f test_link

# Paralelismo com xargs
cat temp_processed.txt | xargs -I {} -P 20 bash -c 'test_link "{}"' > "$TEMP_ALL_TESTED"

echo "📝 Consolidando resultados..."
rm -f blacklist_new.txt && touch blacklist_new.txt

while IFS="|" read -r STATUS DATA1 DATA2; do
    case $STATUS in
        OK)
            echo -e "$DATA1\n$DATA2" >> "$OUTPUT"
            ;;
        BL)
            echo "$DATA2" >> blacklist_new.txt
            echo -e "$DATA1\n$DATA2" >> "$OUTPUT"
            ;;
        DEL)
            ;;
    esac
done < "$TEMP_ALL_TESTED"

mv blacklist_new.txt "$BLACKLIST"
rm -f "$TEMP_RAW" temp_processed.txt "$TEMP_ALL_TESTED"

echo "✅ Finalizado! Canais na lista: $(grep -c "^#EXTINF" "$OUTPUT")"
