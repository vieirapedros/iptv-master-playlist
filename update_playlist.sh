#!/usr/bin/env bash

set -Eeuo pipefail

trap 'rc=$?;
echo "ERRO em ${BASH_SOURCE[0]}:${LINENO}:${FUNCNAME[0]:-main} (exit=$rc)" >&2
exit "$rc"' ERR

OUTPUT="master.m3u"
BLACKLIST="blacklist.txt"
CACHE_OK="cache_ok.txt"
LOG="update.log"

USER_AGENT="Mozilla/5.0 (SMART-TV; Linux; Tizen 5.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/5.0 TV Safari/538.1"
CACHE_MAX_AGE_DAYS="${CACHE_MAX_AGE_DAYS:-2}"
PARALLEL_JOBS="${PARALLEL_JOBS:-64}"
BLACKLIST_TTL_DAYS="${BLACKLIST_TTL_DAYS:-7}"
MIN_DIFF_PCT="${MIN_DIFF_PCT:-50}"

# ─── Fontes remotas ───────────────────────────────────────────────────────────
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
  "https://www.apsattv.com/tablo.m3u"
  "https://www.apsattv.com/veely.m3u"
  "https://www.apsattv.com/redeitv.m3u"
  "https://www.apsattv.com/soultv.m3u"
  "https://www.apsattv.com/ptlg.m3u"
  "https://www.apsattv.com/arlg.m3u"
  "https://www.apsattv.com/mxlg.m3u"
  "https://www.apsattv.com/pelg.m3u"
  "https://www.apsattv.com/eslg.m3u"
  "https://www.apsattv.com/klg.m3u"
  "https://www.apsattv.com/eslg.m3u"
  "https://www.apsattv.com/uslg.m3u"
  "https://www.apsattv.com/gblg.m3u"
  "https://www.apsattv.com/itlg.m3u"
  "https://www.apsattv.com/frlg.m3u"
  "https://www.apsattv.com/jplg.m3u"
  "https://github.com/iprtl/m3u/raw/live/Pluto.m3u"
  "https://github.com/iprtl/m3u/raw/live/Freetv.m3u"
  "https://raw.githubusercontent.com/abusaeeidx/IPTV-Scraper-Zilla/main/combined-playlist.m3u"
  "https://raw.githubusercontent.com/appcml/iptv-live-validator/refs/heads/main/output/lista_tv.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/buddylive-combined/refs/heads/main/combined_playlist.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/plutotv_all.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/plex_all.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/roku_all.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/samsungtvplus_all.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/refs/heads/main/playlists/tubi_all.m3u"
  "https://raw.githubusercontent.com/BuddyChewChew/xumo-playlist-generator/refs/heads/main/playlists/xumo_playlist.m3u"
)

# ─── Fontes locais (versionadas no repo) ──────────────────────────────────────
LOCAL_SOURCES=(
  "playlist_iptv-org.m3u"
)

COUNTRIES=(BR PT AR MX PE ES US GB IT FR JP UN)

declare -A COUNTRY_NAME=(
  [BR]="Brasil"
  [PT]="Portugal"
  [AR]="Argentina"
  [MX]="México"
  [PE]="Peru"
  [ES]="España"
  [US]="Estados Unidos"
  [GB]="Reino Unido"
  [IT]="Itália"
  [FR]="França"
  [JP]="Japão"
  [UN]="Outros"
)

# Domínios confiáveis: comparação EXATA de host (sem substring)
TRUSTED_HOSTS=(
  "raw.githubusercontent.com"
  "github.com"
)

WORKDIR="$(mktemp -d)"

RAW="$WORKDIR/raw.m3u"
BLOCKS="$WORKDIR/blocks.tsv"
CHECK_INPUT="$WORKDIR/check_input.txt"
VALID_URLS="$WORKDIR/valid_urls.txt"
KEPT="$WORKDIR/kept.tsv"
CLEAN_BLACKLIST="$WORKDIR/blacklist_kept.txt"
CLEAN_CACHE="$WORKDIR/cache_pruned.txt"
TRUSTED_FILE="$WORKDIR/trusted_hosts.txt"
NAMES_FILE="$WORKDIR/country_names.txt"
OUT_TMP="$WORKDIR/master.tmp"

cleanup() {
  local rc=$?
  rm -rf "$WORKDIR"
  exit "$rc"
}
trap cleanup EXIT INT TERM

touch "$BLACKLIST" "$CACHE_OK"

: > "$RAW"
: > "$BLOCKS"
: > "$CHECK_INPUT"
: > "$VALID_URLS"
: > "$KEPT"
: > "$LOG"

exec > >(tee -a "$LOG") 2>&1

printf '%s\n' "${TRUSTED_HOSTS[@]}" > "$TRUSTED_FILE"

for c in "${COUNTRIES[@]}"; do
  printf '%s|%s\n' "$c" "${COUNTRY_NAME[$c]}"
done > "$NAMES_FILE"

# ─── Separadores não-whitespace (US/RS) ───────────────────────────────────────
# FIX: antes era TAB e IFS=$'\t' colapsava campos vazios (canal sem tvg-country
# herdava o group-title como "país" e era descartado em silêncio)
US=$'\x1f'
RS30=$'\x1e'

TODAY="$(date +%F)"
CACHE_CUTOFF="$(date -d "-$CACHE_MAX_AGE_DAYS days" +%F)"
BLACKLIST_CUTOFF="$(date -d "-$BLACKLIST_TTL_DAYS days" +%F)"

# ─── Download com log de falhas, CRLF removido e \n garantido no fim ──────────
fetch_all() {
  declare -A seen=()
  local url

  for url in "${URLS[@]}"; do
    [[ -z "${url:-}" ]] && continue
    [[ -n "${seen[$url]:-}" ]] && continue
    seen["$url"]=1

    echo "📥 Baixando: $url"

    if curl -fsSL -A "$USER_AGENT" \
            --connect-timeout 10 --max-time 30 \
            --retry 2 --retry-delay 2 \
            "$url" 2>/dev/null |
       tr -d '\r' |
       sed '/^#EXTM3U[[:space:]]*$/d' >> "$RAW"
    then
      printf '\n' >> "$RAW"
    else
      echo "⚠️  Falha ao baixar (ignorado): $url" >&2
    fi
  done

  local f
  for f in "${LOCAL_SOURCES[@]}"; do
    if [[ -f "$f" ]]; then
      echo "📂 Fonte local: $f"
      tr -d '\r' < "$f" | sed '/^#EXTM3U[[:space:]]*$/d' >> "$RAW"
      printf '\n' >> "$RAW"
    else
      echo "⚠️  Fonte local ausente (ignorado): $f" >&2
    fi
  done
}

# ─── Parse + classificação (tudo em awk, campos com US) ───────────────────────
cat > "$WORKDIR/parse.awk" <<'AWK'
function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function sanitize(s){ gsub(/\x1f|\x1e/, " ", s); return s }
function norm(s){
  s = toupper(s)
  gsub(/[^A-Z0-9]+/, " ", s)
  gsub(/ +/, " ", s)
  return trim(s)
}
function wmatch(n, w){ return index(" " n " ", " " w " ") > 0 }

# Classificação por PALAVRA INTEIRA no nome do canal + grupo (nunca na URL)
function classify(name, grp,   n){
  n = norm(name " " grp)
  if (wmatch(n, "BRAZIL")   || wmatch(n, "BRASIL"))      return "BR"
  if (wmatch(n, "PORTUGAL"))                              return "PT"
  if (wmatch(n, "ARGENTINA"))                             return "AR"
  if (wmatch(n, "MEXICO"))                                return "MX"
  if (wmatch(n, "PERU"))                                  return "PE"
  if (wmatch(n, "SPAIN")    || wmatch(n, "ESPANA"))      return "ES"
  if (wmatch(n, "UNITED STATES") || wmatch(n, "USA"))    return "US"
  if (wmatch(n, "UNITED KINGDOM") || wmatch(n, "UK"))    return "GB"
  if (wmatch(n, "ITALY")    || wmatch(n, "ITALIA"))      return "IT"
  if (wmatch(n, "FRANCE"))                                return "FR"
  if (wmatch(n, "JAPAN"))                                 return "JP"
  return "UN"
}

function map_country(c){
  c = toupper(trim(c))
  gsub(/[^A-Z]/, "", c)
  if (c == "UK")  return "GB"
  if (c == "USA") return "US"
  return c
}

function is_known(c){
  return index(",BR,PT,AR,MX,PE,ES,US,GB,IT,FR,JP,", "," c ",") > 0
}

/^#EXTINF:/ {
  meta = sanitize($0)
  # FIX: normaliza "#EXTINF:None" para "-1"
  sub(/^#EXTINF:None/, "#EXTINF:-1", meta)

  grp = ""; tvgcountry = ""

  if (match(meta, /tvg-country="[^"]*"/))
    tvgcountry = substr(meta, RSTART + 13, RLENGTH - 14)

  if (match(meta, /group-title="[^"]*"/))
    grp = substr(meta, RSTART + 13, RLENGTH - 14)

  name = ""
  if (match(meta, /,[^,]*$/))
    name = substr(meta, RSTART + 1)

  opts = ""
  next
}

# FIX: preserva user-agent / referrer / headers que o player precisa
/^#EXTVLCOPT:|^#EXTHTTP:/ {
  line = sanitize($0)
  opts = (opts == "" ? line : opts RS30 line)
  next
}

/^https?:\/\// {
  url = trim($0)
  gsub(/[[:cntrl:]]/, "", url)

  if (meta == "" || url == "")
    next

  # FIX: dedupe por URL (antes era meta|url, gerando duplicata do mesmo stream)
  if (seen[url]++)
    next

  # tvg-country: pega só o primeiro código de "BR;US"
  split(tvgcountry, parts, ";")
  code = map_country(parts[1])

  # FIX: país desconhecido vira classificação / UN, nunca descarte silencioso
  if (!is_known(code))
    code = classify(name, grp)

  printf "%s%s%s%s%s%s%s%s%s%s%s\n", \
    meta, SEP, name, SEP, url, SEP, code, SEP, grp, SEP, opts

  meta = ""; grp = ""; tvgcountry = ""; opts = ""
}
AWK

# ─── Cache/blacklist em awk (lookup O(1), cache podado, blacklist com TTL) ───
cat > "$WORKDIR/prepare.awk" <<'AWK'
FILENAME == ARGV[1] {
  split($0, a, "|")
  if (a[1] == "" || a[2] == "")
    next
  # FIX: entradas velhas da blacklist EXPIRAM de verdade
  if (a[2] >= blcut) {
    bl[a[1]] = a[2]
    print $0 > blout
  } else {
    exp_bl++
  }
  next
}

FILENAME == ARGV[2] {
  split($0, a, "|")
  if (a[1] == "" || a[2] == "")
    next
  # FIX: cache_ok podado: entradas velhas são descartadas
  if (a[2] >= cachecut) {
    cache[a[1]] = a[2]
    print $0 > cacheout
  } else {
    exp_cache++
  }
  next
}

FILENAME == ARGV[3] {
  trusted[$0] = 1
  next
}

FILENAME == ARGV[4] {
  nf = split($0, f, SEP)
  url = f[3]
  if (url == "")
    next

  # FIX: URL pulada por blacklist NÃO volta para a blacklist
  if (url in bl) {
    skipped++
    next
  }

  if (url in cache) {
    print url > valid
    cached++
    next
  }

  # FIX: host extraído e comparado exatamente (sem substring)
  host = url
  sub(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, "", host)
  sub(/.*@/, "", host)
  sub(/[\/?:].*/, "", host)
  host = tolower(host)

  for (h in trusted)
    if (host == h || substr(host, length(host) - length(h)) == "." h)
      { print url > valid; trust++; next }

  print url > checkin
}

END {
  printf "⚡ Cache atual (sem validação): %d\n", cached
  printf "⚡ Domínio confiável:           %d\n", trust
  printf "⏭️  Pulados (blacklist ativa):  %d\n", skipped + 0
  printf "🧹 Blacklist expirada podada:   %d\n", exp_bl + 0
  printf "🧹 Cache expirado podado:       %d\n", exp_cache + 0
}
AWK

parse_blocks() {
  awk -v SEP="$US" -v RS30="$RS30" \
      -f "$WORKDIR/parse.awk" "$RAW" > "$BLOCKS"
}

prepare_validation() {
  : > "$CLEAN_BLACKLIST"
  : > "$CLEAN_CACHE"

  awk \
    -v SEP="$US" \
    -v blcut="$BLACKLIST_CUTOFF" \
    -v cachecut="$CACHE_CUTOFF" \
    -v blout="$CLEAN_BLACKLIST" \
    -v cacheout="$CLEAN_CACHE" \
    -v valid="$VALID_URLS" \
    -v checkin="$CHECK_INPUT" \
    -f "$WORKDIR/prepare.awk" \
    "$BLACKLIST" "$CACHE_OK" "$TRUSTED_FILE" "$BLOCKS"

  local check_count
  check_count="$(wc -l < "$CHECK_INPUT")"
  echo "🔎 Para validar agora: $check_count"
}

# ─── Validação: HEAD primeiro, GET de 1 byte como fallback ────────────────────
safe_validate_worker() {
  local url="$1"

  [[ -z "${url:-}" ]] && return 0

  local code

  code="$(
    curl -o /dev/null -L -s -I \
      -w '%{http_code}' \
      -A "$USER_AGENT" \
      --connect-timeout 4 --max-time 8 \
      "$url" 2>/dev/null || true
  )"

  if [[ "$code" == "405" || "$code" == "000" || -z "$code" ]]; then
    code="$(
      curl -o /dev/null -L -s \
        -w '%{http_code}' \
        -A "$USER_AGENT" \
        --connect-timeout 4 --max-time 10 \
        -r 0-0 \
        "$url" 2>/dev/null || true
    )"
  fi

  if [[ "$code" =~ ^[23] ]]; then
    printf '%s\n' "$url"
  fi
}

export USER_AGENT
export -f safe_validate_worker

validate_urls() {
  [[ ! -s "$CHECK_INPUT" ]] && return 0

  local total
  total="$(wc -l < "$CHECK_INPUT")"
  echo "🔎 Validando $total URLs com $PARALLEL_JOBS jobs paralelos..."

  xargs \
    -d '\n' \
    -P "$PARALLEL_JOBS" \
    -I{} \
    bash -c 'safe_validate_worker "$@"' _ "{}" \
    < "$CHECK_INPUT" >> "$VALID_URLS"

  sort -u "$VALID_URLS" -o "$VALID_URLS"

  local valid_count
  valid_count="$(wc -l < "$VALID_URLS")"
  echo "✅ URLs válidas após validação: $valid_count"
}

build_kept() {
  awk \
    -v kept="$KEPT" \
    '
    FILENAME == ARGV[1] {
      if ($0 != "")
        valid[$0] = 1
      next
    }
    {
      nf = split($0, f, sprintf("%c", 31))
      if (f[3] != "" && (f[3] in valid))
        print $0 > kept
    }
    ' "$VALID_URLS" "$BLOCKS"

  # Ordena por nome de canal para saída estável entre execuções
  LC_ALL=C sort -t "$US" -k2,2 -o "$KEPT" "$KEPT"
}

# ─── Blacklist: só entra URL testada que falhou NESTA execução ────────────────
merge_blacklist() {
  {
    cat "$CLEAN_BLACKLIST"
    awk \
      -v today="$TODAY" \
      '
      FILENAME == ARGV[1] {
        if ($0 != "")
          valid[$0] = 1
        next
      }
      FILENAME == ARGV[2] {
        if ($0 != "" && !($0 in valid))
          print $0 "|" today
      }
      ' "$VALID_URLS" "$CHECK_INPUT"
  } | sort -u > "$BLACKLIST"

  echo "🚫 Blacklist final: $(wc -l < "$BLACKLIST") entradas"
}

update_cache() {
  awk \
    -v today="$TODAY" \
    '
    FILENAME == ARGV[1] {
      split($0, a, "|")
      if (a[1] != "")
        cache[a[1]] = a[2]
      next
    }
    FILENAME == ARGV[2] {
      if ($0 != "")
        cache[$0] = today
      next
    }
    END {
      for (u in cache)
        print u "|" cache[u]
    }
    ' "$CLEAN_CACHE" "$VALID_URLS" | sort > "$CACHE_OK"
}

# ─── Master: agrupa por país e reescreve o group-title (players leem isso) ────
cat > "$WORKDIR/build_master.awk" <<'AWK'
FILENAME == ARGV[1] {
  split($0, a, "|")
  disp[a[1]] = a[2]
  next
}

FILENAME == ARGV[2] {
  nf = split($0, f, SEP)
  meta = f[1]; url = f[3]; code = f[4]; grp = f[5]; opts = f[6]

  if (url == "")
    next
  if (!(code in disp))
    code = "UN"

  gt = disp[code]
  if (grp != "")
    gt = gt " - " grp

  # reescreve (ou insere) o group-title no EXTINF
  if (match(meta, /group-title="[^"]*"/))
    meta = substr(meta, 1, RSTART + 12) gt substr(meta, RSTART + RLENGTH - 1)
  else if (match(meta, /,[^,]*$/))
    meta = substr(meta, 1, RSTART - 1) " group-title=\"" gt "\"" substr(meta, RSTART)

  body[code] = body[code] meta "\n"

  if (opts != "") {
    n = split(opts, o, RS30)
    for (i = 1; i <= n; i++)
      body[code] = body[code] o[i] "\n"
  }

  body[code] = body[code] url "\n\n"
  cnt[code]++
}

END {
  printf "#EXTM3U\n" > out

  n = split(order, seq, " ")

  for (i = 1; i <= n; i++) {
    cc = seq[i]
    if (!(cc in cnt))
      continue
    printf "\n#EXTGRP:%s\n\n", disp[cc] > out
    printf "%s", body[cc] > out
    printf "📌 %-15s %d canais\n", "(" disp[cc] ")", cnt[cc]
  }
}
AWK

build_master() {
  local order="BR PT AR MX PE ES US GB IT FR JP UN"

  awk \
    -v SEP="$US" \
    -v RS30="$RS30" \
    -v out="$OUT_TMP" \
    -v order="$order" \
    -f "$WORKDIR/build_master.awk" \
    "$NAMES_FILE" "$KEPT"
}

main() {
  local total_raw total_parsed total_final success_rate prev_count

  prev_count="$(grep -c '^#EXTINF' "$OUTPUT" 2>/dev/null || true)"
  prev_count="${prev_count:-0}"

  fetch_all

  total_raw="$(grep -c '^#EXTINF' "$RAW" || true)"
  echo "📊 Brutos: $total_raw"

  parse_blocks

  total_parsed="$(wc -l < "$BLOCKS")"
  echo "📊 Parseados (únicos por URL): $total_parsed"

  prepare_validation
  validate_urls
  merge_blacklist
  build_kept
  update_cache
  build_master

  total_final="$(grep -c '^#EXTINF' "$OUT_TMP" || true)"

  # ─── Sanidade: nunca publicar uma playlist vazia ou muito menor ────────────
  if (( total_final == 0 )); then
    echo "❌ SANIDADE: playlist final vazia. master.m3u NÃO foi alterado." >&2
    exit 1
  fi

  if (( prev_count > 0 && total_final * 100 < prev_count * MIN_DIFF_PCT )); then
    echo "❌ SANIDADE: $total_final canais < $MIN_DIFF_PCT% do anterior ($prev_count)." >&2
    echo "   master.m3u NÃO foi alterado. Investigue as fontes." >&2
    exit 1
  fi

  mv "$OUT_TMP" "$OUTPUT"

  if (( total_parsed == 0 )); then
    success_rate=0
  else
    success_rate=$(( total_final * 100 / total_parsed ))
  fi

  echo "=================================="
  echo "✅ FINALIZADO"
  echo "📊 Brutos:      $total_raw"
  echo "📊 Parseados:   $total_parsed"
  echo "📊 Anterior:    $prev_count"
  echo "📊 Funcionais:  $total_final"
  echo "📊 Taxa:        $success_rate%"
  echo "📄 Output:      $OUTPUT"
  echo "📄 Blacklist:   $BLACKLIST"
  echo "📄 Cache:       $CACHE_OK"
  echo "📄 Log:         $LOG"
  echo "⚙️  Jobs:        $PARALLEL_JOBS"
  echo "⚙️  TTL blacklist: $BLACKLIST_TTL_DAYS dias | Cache: $CACHE_MAX_AGE_DAYS dias"
  echo "=================================="
}

main
