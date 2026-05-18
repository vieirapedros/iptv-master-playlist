#!/usr/bin/env bash

set -Eeuo pipefail

trap 'rc=$?;
echo "ERRO em ${BASH_SOURCE[0]}:${LINENO}:${FUNCNAME[0]:-main} (exit=$rc)" >&2
exit "$rc"' ERR

OUTPUT="master.m3u"
BLACKLIST="blacklist.txt"
CACHE_OK="cache_ok.txt"
LOG="update.log"

USER_AGENT="Mozilla/5.0"
CACHE_MAX_AGE_DAYS="${CACHE_MAX_AGE_DAYS:-2}"
PARALLEL_JOBS="${PARALLEL_JOBS:-16}"

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
  "https://www.apsattv.com/uslg.m3u"
  "https://www.apsattv.com/gblg.m3u"
  "https://www.apsattv.com/itlg.m3u"
  "https://www.apsattv.com/frlg.m3u"
  "https://www.apsattv.com/jplg.m3u"
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

TMPDIR="$(mktemp -d)"

RAW="$TMPDIR/raw.m3u"
BLOCKS="$TMPDIR/blocks.tsv"
CHECK_INPUT="$TMPDIR/check_input.txt"
VALID_URLS="$TMPDIR/valid_urls.txt"
KEPT="$TMPDIR/kept.tsv"
NEW_BLACKLIST="$TMPDIR/new_blacklist.txt"

cleanup() {
  local rc=$?
  rm -rf "$TMPDIR"
  exit "$rc"
}

trap cleanup EXIT INT TERM

touch "$BLACKLIST" "$CACHE_OK"

: > "$RAW"
: > "$BLOCKS"
: > "$CHECK_INPUT"
: > "$VALID_URLS"
: > "$KEPT"
: > "$NEW_BLACKLIST"
: > "$LOG"

exec > >(tee -a "$LOG") 2>&1

normalize() {
  local s="$1"

  s="$(
    printf '%s' "$s" |
    iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$s"
  )"

  printf '%s' "$s" | tr '[:lower:]' '[:upper:]'
}

country_from_text() {
  local s
  s="$(normalize "$1")"

  case "$s" in
    *BRAZIL*|*BRASIL*) echo BR ;;
    *PORTUGAL*) echo PT ;;
    *ARGENTINA*) echo AR ;;
    *MEXICO*) echo MX ;;
    *PERU*) echo PE ;;
    *SPAIN*|*ESPANA*) echo ES ;;
    *UNITED*STATES*|*USA*) echo US ;;
    *UNITED*KINGDOM*|*UK*) echo GB ;;
    *ITALY*|*ITALIA*) echo IT ;;
    *FRANCE*) echo FR ;;
    *JAPAN*) echo JP ;;
    *) echo UN ;;
  esac
}

fetch_all() {
  declare -A seen=()
  local url

  for url in "${URLS[@]}"; do

    [[ -z "${url:-}" ]] && continue
    [[ -n "${seen[$url]:-}" ]] && continue

    seen["$url"]=1

    echo "📥 Baixando: $url"

    curl \
      -fsSL \
      -A "$USER_AGENT" \
      --connect-timeout 5 \
      --max-time 20 \
      --retry 1 \
      "$url" 2>/dev/null |
      sed '/^#EXTM3U$/d' >> "$RAW" || true

  done
}

parse_blocks() {
  awk '
    function trim(s){
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }

    /^#EXTINF:/ {
      meta=$0
      grp=""
      country=""

      if (match($0, /tvg-country="[^"]+"/))
        country=substr($0, RSTART+13, RLENGTH-14)

      if (match($0, /group-title="[^"]+"/))
        grp=substr($0, RSTART+13, RLENGTH-14)

      next
    }

    /^https?:\/\// {
      url=trim($0)

      if (meta == "" || url == "")
        next

      key=meta "|" url

      if (seen[key]++)
        next

      print meta "\t" url "\t" country "\t" grp

      meta=""
      grp=""
      country=""
    }
  ' "$RAW" > "$BLOCKS"
}

is_cache_valid() {
  local url="$1"
  local cached_url cached_date
  local now epoch_cache diff

  now="$(date +%s)"

  while IFS='|' read -r cached_url cached_date || [[ -n "${cached_url:-}" ]]; do

    [[ -z "${cached_url:-}" ]] && continue
    [[ -z "${cached_date:-}" ]] && continue
    [[ "${cached_url:-}" != "${url:-}" ]] && continue

    epoch_cache="$(date -d "${cached_date:-}" +%s 2>/dev/null || true)"

    epoch_cache="${epoch_cache//[^0-9]/}"
    epoch_cache="${epoch_cache:-0}"

    (( epoch_cache == 0 )) && continue

    diff=$(( (now - epoch_cache) / 86400 ))

    (( diff <= CACHE_MAX_AGE_DAYS )) && return 0

  done < "$CACHE_OK"

  return 1
}

safe_validate_worker() {
  local url="$1"

  [[ -z "${url:-}" ]] && return 0

  local code

  code="$(
    curl \
      -o /dev/null \
      -L \
      -s \
      -w '%{http_code}' \
      -A "$USER_AGENT" \
      --connect-timeout 3 \
      --max-time 8 \
      "$url" 2>/dev/null || true
  )"

  if [[ "$code" =~ ^2|3 ]]; then
    printf '%s\n' "$url"
  fi
}

export USER_AGENT
export -f safe_validate_worker

prepare_validation() {
  declare -A blacklist=()

  local line meta url country grp

  while IFS='|' read -r line _ || [[ -n "${line:-}" ]]; do
    [[ -n "${line:-}" ]] && blacklist["$line"]=1
  done < "$BLACKLIST"

  while IFS=$'\t' read -r meta url country grp || [[ -n "${url:-}" ]]; do

    [[ -z "${url:-}" ]] && continue
    [[ -n "${blacklist[$url]:-}" ]] && continue

    if is_cache_valid "$url"; then
      printf '%s\n' "$url" >> "$VALID_URLS"
    else
      printf '%s\n' "$url" >> "$CHECK_INPUT"
    fi

  done < "$BLOCKS"
}

validate_urls() {
  [[ ! -s "$CHECK_INPUT" ]] && return 0

  echo "🔎 Validando URLs..."

  xargs \
    -P "$PARALLEL_JOBS" \
    -I{} \
    bash -lc 'safe_validate_worker "$@"' _ "{}" \
    < "$CHECK_INPUT" >> "$VALID_URLS"

  sort -u "$VALID_URLS" -o "$VALID_URLS"
}

build_kept() {
  declare -A valid=()

  local line meta url country grp final_country

  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -n "${line:-}" ]] && valid["$line"]=1
  done < "$VALID_URLS"

  while IFS=$'\t' read -r meta url country grp || [[ -n "${url:-}" ]]; do

    [[ -z "${url:-}" ]] && continue

    if [[ -n "${valid[$url]:-}" ]]; then

      final_country="${country:-}"

      [[ -z "${final_country:-}" ]] &&
        final_country="$(country_from_text "$meta $grp $url")"

      printf '%s\t%s\t%s\t%s\n' \
        "$meta" \
        "$url" \
        "$final_country" \
        "$grp" >> "$KEPT"

    else
      printf '%s|%(%F)T\n' "$url" -1 >> "$NEW_BLACKLIST"
    fi

  done < "$BLOCKS"
}

update_cache() {
  local now url date line

  declare -A cache=()

  now="$(date +%F)"

  while IFS='|' read -r url date || [[ -n "${url:-}" ]]; do
    [[ -n "${url:-}" ]] && cache["$url"]="$date"
  done < "$CACHE_OK"

  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -n "${line:-}" ]] && cache["$line"]="$now"
  done < "$VALID_URLS"

  : > "$CACHE_OK"

  for line in "${!cache[@]}"; do
    printf '%s|%s\n' "$line" "${cache[$line]}"
  done | sort > "$CACHE_OK"
}

merge_blacklist() {
  local cutoff_days=7
  local now url date_part epoch line

  declare -A keep=()

  now="$(date +%s)"

  while IFS='|' read -r url date_part || [[ -n "${url:-}" ]]; do

    [[ -z "${url:-}" ]] && continue
    [[ -z "${date_part:-}" ]] && continue

    epoch="$(date -d "${date_part:-}" +%s 2>/dev/null || true)"

    epoch="${epoch//[^0-9]/}"
    epoch="${epoch:-0}"

    (( epoch == 0 )) && continue

    if (( (now - epoch) / 86400 <= cutoff_days )); then
      keep["$url|$date_part"]=1
    fi

  done < "$BLACKLIST"

  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -n "${line:-}" ]] && keep["$line"]=1
  done < "$NEW_BLACKLIST"

  if ((${#keep[@]})); then
    printf '%s\n' "${!keep[@]}" | sort > "$BLACKLIST"
  else
    : > "$BLACKLIST"
  fi
}

build_master() {
  declare -A grouped=()

  local meta url country grp c

  while IFS=$'\t' read -r meta url country grp || [[ -n "${url:-}" ]]; do

    [[ -z "${url:-}" ]] && continue

    grouped["$country"]+="$meta"$'\n'"$url"$'\n\n'

  done < "$KEPT"

  {
    echo '#EXTM3U'

    for c in "${COUNTRIES[@]}"; do
      echo "#EXTGRP:${COUNTRY_NAME[$c]}"
      printf '%s' "${grouped[$c]:-}"
    done

  } > "$OUTPUT"
}

main() {
  local total_raw total_parsed total_final success_rate

  fetch_all

  total_raw="$(grep -c '^#EXTINF' "$RAW" || echo 0)"
  echo "📊 Brutos: $total_raw"

  parse_blocks

  total_parsed="$(wc -l < "$BLOCKS")"
  echo "📊 Parseados: $total_parsed"

  prepare_validation
  validate_urls
  build_kept
  update_cache
  merge_blacklist
  build_master

  total_final="$(grep -c '^#EXTINF' "$OUTPUT" || echo 0)"

  if (( total_parsed == 0 )); then
    success_rate=0
  else
    success_rate=$(( total_final * 100 / total_parsed ))
  fi

  echo "=================================="
  echo "✅ FINALIZADO"
  echo "📊 Brutos:      $total_raw"
  echo "📊 Parseados:   $total_parsed"
  echo "📊 Funcionais:  $total_final"
  echo "📊 Taxa:        $success_rate%"
  echo "📄 Output:      $OUTPUT"
  echo "📄 Blacklist:   $BLACKLIST"
  echo "📄 Cache:       $CACHE_OK"
  echo "📄 Log:         $LOG"
  echo "⚙️ Jobs:        $PARALLEL_JOBS"
  echo "=================================="
}

main
