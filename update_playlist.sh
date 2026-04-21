#!/bin/bash
OUTPUT="master.m3u"
TEMP_RAW="temp_raw.m3u"

URLS=(
  "https://www.apsattv.com/tclbr.m3u"
  "https://www.apsattv.com/brlg.m3u"
  # ... (mantenha suas URLs aqui)
)

rm -f "$OUTPUT" "$TEMP_RAW"
echo "#EXTM3U" > "$OUTPUT"

echo "🔄 Baixando e unindo playlists..."
for url in "${URLS[@]}"; do
  # Baixa, remove o cabeçalho #EXTM3U de cada lista e salva
  curl -sL "$url" | sed '/^#EXTM3U/d' >> "$TEMP_RAW"
done

echo "🧹 Removendo duplicados baseando-se na URL..."
# Este AWK lê o par (EXTINF + URL) e usa a URL como chave para evitar duplicatas
awk '
  /^#EXTINF/ {info=$0; next} 
  /^http/ {
    if (!seen[$0]++) {
      print info; 
      print $0
    }
  }
' "$TEMP_RAW" >> "$OUTPUT"

rm -f "$TEMP_RAW"

echo "✅ Playlist final gerada: $(grep -c "^#EXTINF" "$OUTPUT") canais únicos."
