# IPTV Master Playlist

Pipeline que consolida ~46 fontes públicas de listas IPTV (`.m3u`) em uma única
playlist validada e organizada por país.

## URL da playlist (aponte o player para cá)

```
https://raw.githubusercontent.com/vieirapedros/iptv-master-playlist/main/master.m3u
```

## Como funciona

1. **Download** — busca todas as fontes em `update_playlist.sh` (`URLS`) mais as
   fontes locais versionadas em `LOCAL_SOURCES` (ex.: `playlist_iptv-org.m3u`).
   Falhas de download são registradas no log, sem derrubar o pipeline.
2. **Parse** — extrai `#EXTINF` + URL + `#EXTVLCOPT`/`#EXTHTTP` (user-agent e
   referrer são preservados). Deduplica por URL e normaliza `#EXTINF:None`.
3. **Classificação de país** — usa `tvg-country` (primeiro código de `BR;US`);
   se inválido/ausente, classifica por palavra inteira no nome do canal;
   fallback para `Outros (UN)` — nenhum canal é descartado por país desconhecido.
4. **Validação** — HTTP HEAD (com fallback para GET de 1 byte) em paralelo.
   URLs em cache válido ou em domínio confiável não são revalidadas.
5. **Estado** — `blacklist.txt` (URLs que falharam, TTL de 7 dias) e
   `cache_ok.txt` (URLs válidas, TTL de 2 dias) ficam em `actions/cache`,
   fora do histórico do git (e estão no `.gitignore`).
6. **Sanidade** — se o resultado for vazio ou menor que `MIN_DIFF_PCT`% do
   anterior, o job falha e o `master.m3u` atual é preservado.

## Saída

`master.m3u` agrupada por país com `group-title` reescrito
(`Brasil - Esportes`, `Outros - News`, ...), ordenada por nome de canal.

## Rodar localmente

```bash
chmod +x update_playlist.sh
./update_playlist.sh
```

Variáveis opcionais: `PARALLEL_JOBS` (64), `CACHE_MAX_AGE_DAYS` (2),
`BLACKLIST_TTL_DAYS` (7), `MIN_DIFF_PCT` (50).

## Agenda

GitHub Actions: segunda e sexta, 15:00 UTC (12:00 BRT), ou manual em
**Actions → Update IPTV Playlist → Run workflow**.
