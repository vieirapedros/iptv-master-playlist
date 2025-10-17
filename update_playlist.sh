#!/bin/bash
# =====================================
# Script: update_playlist.sh
# Unifica, limpa e atualiza playlists IPTV
# Remove duplicados e ignora links offline
# =====================================

OUTPUT="master.m3u"

# URLs das listas a unir
URLS=(
  "https://www.apsattv.com/brlg.m3u"
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
  "https://www.apsattv.com/xiaomi.m3u"
  "https://www.apsattv.com/tclbr.m3u"
  "https://www.apsattv.com/tcl.m3u"
  "https://www.apsattv.com/tclplus.m3u"
  "https://www.apsattv.com/ssungbra.m3u"
  "https://www.apsattv.com/ssungpor.m3u"
  "https://www.apsattv.com/ssungmex.m3u"
  "https://www.apsattv.com/redbox.m3u"
  "https://www.apsattv.com/rok.m3u"
  "https://www.apsattv.com/vidaa.m3u"
  "https://www.apsattv.com/localnow.m3u"
  "https://www.apsattv.com/moviearkbr.m3u"
  "https://www.apsattv.com/firetv.m3u"
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
)

# Limpa a saída anterior
rm -f "$OUTPUT"
echo "#EXTM3U" > "$OUTPUT"

echo "🔄 Baixando e unindo playlists..."
for url in "${URLS[@]}"; do
  echo "→ $url"
  curl -s "$url" | grep -E "^#EXTINF|^http" >> all_temp.m3u
done

echo "🧹 Removendo duplicados..."
awk '!x[$0]++' all_temp.m3u > unique_temp.m3u

echo "⚙️ Verificando canais online..."
# Filtra links válidos (status HTTP 200)
{
  echo "#EXTM3U"
  paste -d'\n' - - < unique_temp.m3u | while read -r info && read -r link; do
    if curl -s --head --connect-timeout 4 --max-time 6 "$link" | grep -q "200 OK"; then
      echo "$info"
      echo "$link"
    fi
  done
} > "$OUTPUT"

# Limpeza de temporários
rm -f all_temp.m3u unique_temp.m3u

echo "✅ Playlist final gerada com sucesso: $(wc -l < "$OUTPUT") linhas"

