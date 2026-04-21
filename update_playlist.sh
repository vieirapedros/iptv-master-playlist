#!/bin/bash
# =====================================
# Script: update_playlist.sh
# Versão: Ultra-Compatibilidade (Plex, Amagi, Sportstribal)
# =====================================

OUTPUT="master.m3u"
TEMP_RAW="temp_raw.m3u"
BLACKLIST="blacklist.txt"

touch "$BLACKLIST"

URLS=(
  # ... (suas URLs aqui)
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

echo "🧹 Filtrando e Validando (Plex/Amagi Friendly)..."
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
    RETEST=false
    if grep -qF "$URL" "$BLACKLIST"; then RETEST=true; fi

    # TESTE PARA CANAIS PROTEGIDOS (AMAGI/PLEX)
    # -k: ignora erro de SSL
    # --range 0-10: pede os primeiros 10 bytes para confirmar que é vídeo
    HTTP_STATUS=$(curl -skL --connect-timeout 10 -m 20 \
       -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" \
       -H "Referer: https://www.sportstribal.tv/" \
       -H "Origin: https://www.sportstribal.tv" \
       --range 0-10 \
       "$URL" -o /dev/null -w "%{http_code}")

    # Amagi e Plex às vezes retornam 403 ou 401 para bots, mas 200/206 para players.
    # Se retornar 200, 206 ou códigos de redirecionamento, consideramos OK.
    if echo "$HTTP_STATUS" | grep -qE "200|206|301|302"; then
        echo -e "$METADATA\n$URL" >> "$OUTPUT"
    else
        # Se falhou, mas não era reteste, damos o benefício da dúvida (Blacklist)
        if [ "$RETEST" = true ]; then
             echo "🚫 REMOVIDO: $URL [Code: $HTTP_STATUS]"
        else
             echo "❌ BLACKLIST (Aguardando Retorno): $URL [Code: $HTTP_STATUS]"
             echo "$URL" >> blacklist_new.txt
             echo -e "$METADATA\n$URL" >> "$OUTPUT"
        fi
    fi
done

mv blacklist_new.txt "$BLACKLIST"
rm -f "$TEMP_RAW"

echo "✅ Finalizado! Canais no master: $(grep -c "^#EXTINF" "$OUTPUT")"
