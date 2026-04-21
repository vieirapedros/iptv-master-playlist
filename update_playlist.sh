#!/bin/bash

OUTPUT="master.m3u"
TEMP_RAW="temp_raw.m3u"
BLACKLIST="blacklist.txt"
TEMP_BLACKLIST="blacklist_new.txt"

# Cria a blacklist se não existir
touch "$BLACKLIST"

URLS=(
  "https://www.apsattv.com/tclbr.m3u"
  "https://www.apsattv.com/brlg.m3u"
  # ... (mantenha todas as suas URLs aqui)
)

rm -f "$OUTPUT" "$TEMP_RAW" "$TEMP_BLACKLIST"
echo "#EXTM3U" > "$OUTPUT"

echo "🔄 Baixando listas..."
for url in "${URLS[@]}"; do
  curl -sL --connect-timeout 10 "$url" | sed '/^#EXTM3U/d' >> "$TEMP_RAW"
done

echo "🧹 Filtrando duplicados e verificando integridade..."

# 1. Primeiro removemos duplicatas de URL para não testar o mesmo link duas vezes
awk '
  /^#EXTINF/ || /^#EXTGRP/ { buffer = (buffer == "" ? $0 : buffer ORS $0); next }
  /^(http|https|rtmp|rtsp|mms):/ {
    if (!seen[$0]++) {
      if (buffer != "") print buffer "|" $0;
    }
    buffer = "";
  }
' "$TEMP_RAW" > temp_processed.txt

# 2. Teste de integridade (limitado para não travar o workflow)
# Usamos o curl para checar o cabeçalho do stream (HTTP 200)
while IFS="|" read -r METADATA URL; do
    # Verifica se a URL já estava na blacklist da semana passada
    if grep -qF "$URL" "$BLACKLIST"; then
        echo "⚠️ Retestando canal anteriormente offline: $URL"
        RETEST=true
    else
        RETEST=false
    fi

    # Tenta conectar no stream (timeout de 3 segundos para ser rápido)
    if curl -sI --connect-timeout 3 "$URL" | grep -qE "200 OK|302 Found|301 Moved"; then
        # Canal está ON
        echo "$METADATA" >> "$OUTPUT"
        echo "$URL" >> "$OUTPUT"
    else
        # Canal está OFF
        echo "❌ Canal fora de operação: $URL"
        if [ "$RETEST" = true ]; then
            echo "🚫 Removendo permanentemente (falhou no reteste): $URL"
        else
            # Adiciona na blacklist para a próxima semana
            echo "$URL" >> "$TEMP_BLACKLIST"
            # Mantém no arquivo por enquanto (dando uma segunda chance)
            echo "$METADATA" >> "$OUTPUT"
            echo "$URL" >> "$OUTPUT"
        fi
    fi
done < temp_processed.txt

# Atualiza a blacklist para a próxima execução
mv "$TEMP_BLACKLIST" "$BLACKLIST"

rm -f "$TEMP_RAW" temp_processed.txt
echo "✅ Concluído! Canais ativos/em observação: $(grep -c "^#EXTINF" "$OUTPUT")"
