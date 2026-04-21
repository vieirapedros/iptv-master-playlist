#!/bin/bash
# =====================================
# Script: update_playlist.sh
# Versão corrigida: Separadores seguros e tratamento de URLs complexas
# =====================================

OUTPUT="master.m3u"
TEMP_RAW="temp_raw.m3u"
BLACKLIST="blacklist.txt"
TEMP_ALL_TESTED="tested_channels.txt"

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
# Usando !!! como separador para não conflitar com pipes nas URLs
awk '
  /^#EXTINF/ || /^#EXTGRP/ { buffer = (buffer == "" ? $0 : buffer ORS $0); next }
  /^(http|https|rtmp|rtsp|mms):/ {
    if (!seen[$0]++) {
      if (buffer != "") print buffer "!!!" $0;
    }
    buffer = "";
  }
' "$TEMP_RAW" > temp_processed.txt

test_link() {
    local line="$1"
    local blacklist_file="blacklist.txt"
    # Separa os metadados da URL usando a string de segurança !!!
    local METADATA="${line%%!!!*}"
    local URL="${line#*!!!}"
    
    local RETEST=false
    if grep -qF "$URL" "$blacklist_file" 2>/dev/null; then RETEST=true; fi

    # Teste de 5s simulando TV (User-Agent atualizado)
    if curl -sI -L --connect-timeout 5 -m 10 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "$URL" | grep -qE "200 OK|302 Found|301 Moved"; then
        echo "OK!!!$METADATA!!!$URL"
    else
        if [ "$RETEST" = true ]; then
            echo "DEL!!!$URL"
        else
            echo "BL!!!$METADATA!!!$URL"
        fi
    fi
}

export -f test_link

echo "⚡ Testando integridade (20 conexões simultâneas)..."
cat temp_processed.txt | xargs -I {} -P 20 bash -c 'test_link "{}"' > "$TEMP_ALL_TESTED"

echo "📝 Consolidando resultados..."
rm -f blacklist_new.txt && touch blacklist_new.txt

# Processa o resultado final usando o novo separador
while IFS= read -r line; do
    STATUS="${line%%!!!*}"
    REST="${line#*!!!}"
    if [ "$STATUS" == "OK" ]; then
        M="${REST%%!!!*}"
        U="${REST#*!!!}"
        echo -e "$M\n$U" >> "$OUTPUT"
    elif [ "$STATUS" == "BL" ]; then
        M="${REST%%!!!*}"
        U="${REST#*!!!}"
        echo "$U" >> blacklist_new.txt
        echo -e "$M\n$U" >> "$OUTPUT"
    fi
done < "$TEMP_ALL_TESTED"

mv blacklist_new.txt "$BLACKLIST"
rm -f "$TEMP_RAW" temp_processed.txt "$TEMP_ALL_TESTED"

echo "✅ Finalizado! Canais mantidos: $(grep -c "^#EXTINF" "$OUTPUT")"
