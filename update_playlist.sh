#!/bin/bash
# =====================================
# Script: update_playlist.sh
# Unifica, limpa e valida integridade de canais
# =====================================

OUTPUT="master.m3u"
TEMP_RAW="temp_raw.m3u"
BLACKLIST="blacklist.txt"
TEMP_BLACKLIST="blacklist_new.txt"

# Garante que a blacklist existe
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
  "https://iptv-org.github.io/iptv/regions/amer.m3u"
  "https://iptv-org.github.io/iptv/regions/eur.m3u"
)

rm -f "$OUTPUT" "$TEMP_RAW" "$TEMP_BLACKLIST"
echo "#EXTM3U" > "$OUTPUT"

echo "🔄 Baixando e unificando listas..."
for url in "${URLS[@]}"; do
  curl -sL --connect-timeout 10 "$url" | sed '/^#EXTM3U/d' >> "$TEMP_RAW"
done

echo "🧹 Processando duplicados e validando integridade..."

# Agrupa metadados e URL em uma única linha temporária para facilitar o loop
awk '
  /^#EXTINF/ || /^#EXTGRP/ { buffer = (buffer == "" ? $0 : buffer ORS $0); next }
  /^(http|https|rtmp|rtsp|mms):/ {
    if (!seen[$0]++) {
      if (buffer != "") print buffer "|" $0;
    }
    buffer = "";
  }
' "$TEMP_RAW" > temp_processed.txt

# Loop de Verificação
while IFS="|" read -r METADATA URL; do
    # Verifica se estava na blacklist anterior
    if grep -qF "$URL" "$BLACKLIST"; then
        RETEST=true
    else
        RETEST=false
    fi

    # Teste de conexão simulando Smart TV
    if curl -sI -L --connect-timeout 5 -A "Mozilla/5.0 (SMART-TV; Linux; Tizen 5.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/2.2 Chrome/63.0.3239.84 TV Safari/537.36" "$URL" | grep -qE "200 OK|302 Found|301 Moved"; then
        echo -e "$METADATA\n$URL" >> "$OUTPUT"
    else
        if [ "$RETEST" = true ]; then
            echo "🚫 Removido definitivamente: $URL"
        else
            echo "❌ Fora do ar (Carência de 7 dias): $URL"
            echo "$URL" >> "$TEMP_BLACKLIST"
            # Mantém na lista esta semana para dar a chance de voltar
            echo -e "$METADATA\n$URL" >> "$OUTPUT"
        fi
    fi
done < temp_processed.txt

# Atualiza a blacklist para a próxima semana
mv "$TEMP_BLACKLIST" "$BLACKLIST" 2>/dev/null || touch "$BLACKLIST"

rm -f "$TEMP_RAW" temp_processed.txt
echo "✅ Playlist gerada com sucesso!"
