#!/bin/bash
# =====================================
# Script: update_playlist.sh
# Deduplicação + Teste Robusto (2 tentativas, 8s timeout) + Blacklist
# SEM paralelismo - versão estável
# =====================================

OUTPUT="master.m3u"
TEMP_RAW="temp_raw.m3u"
TEMP_DEDUP="temp_dedup.m3u"
BLACKLIST="blacklist.txt"
TEMP_BLACKLIST="blacklist_new.txt"

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

rm -f "$OUTPUT" "$TEMP_RAW" "$TEMP_DEDUP" "$TEMP_BLACKLIST"
echo "#EXTM3U" > "$OUTPUT"

echo "🔄 Baixando listas..."
for url in "${URLS[@]}"; do
  curl -sL --connect-timeout 10 "$url" | sed '/^#EXTM3U/d' >> "$TEMP_RAW"
done

TOTAL_ANTES=$(grep -c "^#EXTINF" "$TEMP_RAW" 2>/dev/null || echo "0")
echo "📊 Canais brutos baixados: $TOTAL_ANTES"

echo "🧹 DEDUPLICAÇÃO: Removendo canais duplicados (URL + nome)..."

# Deduplica: mantém o primeiro de cada URL ou nome
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

TOTAL_DEPOIS=$(grep -c "^#EXTINF" "$TEMP_DEDUP" 2>/dev/null || echo "0")
DUPLICATAS=$(echo "$TOTAL_ANTES - $TOTAL_DEPOIS" | bc)
REDUCAO=$(echo "scale=1; ($TOTAL_ANTES - $TOTAL_DEPOIS) * 100 / $TOTAL_ANTES" | bc 2>/dev/null || echo "0")

echo "📊 Deduplicação: $TOTAL_ANTES → $TOTAL_DEPOIS canais ($DUPLICATAS removidas, $REDUCAO%)"

echo "🔍 Testando conectividade dos canais..."

# =====================================
# FUNÇÃO DE TESTE ROBUSTA
# =====================================
test_channel() {
    local URL="$1"
    local retries=2
    local timeout=5
    
    for i in $(seq 1 $retries); do
        HTTP_CODE=$(curl -sL -r 0-1024 \
            --connect-timeout $timeout \
            --max-time $timeout \
            -o /dev/null \
            -w "%{http_code}" \
            "$URL" 2>/dev/null)
        
        # 200 = OK, 206 = Partial Content (streaming)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "206" ]; then
            return 0
        fi
        
        # Se não foi sucesso e ainda tem tentativas, espera 1s
        if [ $i -lt $retries ]; then
            sleep 1
        fi
    done
    
    return 1
}

# Extrai e processa canais
awk '
/^#EXTINF/ || /^#EXTGRP/ { buffer = (buffer == "" ? $0 : buffer ORS $0); next }
/^(http|https|rtmp|rtsp|m3u8):/ {
  if (!seen[$0]++) {
    if (buffer != "") print buffer "###DELIM###" $0;
  }
  buffer = "";
}
' "$TEMP_DEDUP" | while IFS="###DELIM###" read -r METADATA URL; do

    # Se já está na blacklist, ignora
    if grep -qF "$URL" "$BLACKLIST" 2>/dev/null; then
        echo "⏭️  Ignorado (blacklist): ${URL:0:60}..."
        continue
    fi

    # Testa o canal
    if test_channel "$URL"; then
        echo -e "$METADATA\n$URL" >> "$OUTPUT"
        echo "✅ OK (${URL:0:60}...)"
    else
        echo "$URL" >> "$TEMP_BLACKLIST"
        echo "❌ OFF (${URL:0:60}...)"
    fi

done

rm -f "$TEMP_RAW" "$TEMP_DEDUP"

mv "$TEMP_BLACKLIST" "$BLACKLIST" 2>/dev/null || touch "$BLACKLIST"

FINAL_COUNT=$(grep -c "^#EXTINF" "$OUTPUT" 2>/dev/null || echo "0")

echo ""
echo "=========================================="
echo "✅ FINALIZADO!"
echo "=========================================="
echo "📊 Canais brutos:     $TOTAL_ANTES"
echo "📊 Canais únicos:     $TOTAL_DEPOIS"
echo "📊 Canais funcionais: $FINAL_COUNT"
echo "📊 Taxa de sucesso:   $(echo "scale=1; $FINAL_COUNT * 100 / $TOTAL_DEPOIS" | bc 2>/dev/null || echo "0")%"
echo "=========================================="
