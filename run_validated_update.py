#!/usr/bin/env python3
from pathlib import Path
import re, subprocess, tempfile

def integrate(text):
    old='  prepare_validation\n  validate_urls\n  merge_blacklist\n  build_kept\n  update_cache\n  build_master'
    new='  prepare_validation\n  validate_urls\n  merge_blacklist\n  update_cache\n  cat "$MEDIA_VALID" >> "$VALID_URLS"\n  sort -u "$VALID_URLS" -o "$VALID_URLS"\n  cat "$MEDIA_BLOCKS" >> "$BLOCKS"\n  build_kept\n  build_master'
    if text.count(old)!=1 or text.count('  parse_blocks\n')!=1 or text.count('main() {')!=1:
        raise ValueError('Script base mudou; integracao cancelada para revisao')
    text=text.replace(old,new)
    hook='route_media() {\n  MEDIA_BLOCKS="$WORKDIR/media_blocks.tsv"\n  MEDIA_VALID="$WORKDIR/media_valid.txt"\n  MEDIA_PENDING="$WORKDIR/media_pending.json"\n  python3 media_gate.py gate "$BLOCKS" "$WORKDIR/http_blocks.tsv" "$MEDIA_BLOCKS" "$MEDIA_VALID" "$MEDIA_PENDING"\n  mv "$WORKDIR/http_blocks.tsv" "$BLOCKS"\n}\n\n'
    text=text.replace('main() {',hook+'main() {').replace('  parse_blocks\n','  parse_blocks\n  route_media\n')
    pattern=r'  if \(\( prev_count > 0 && total_final \* 100 < prev_count \* MIN_DIFF_PCT \)\); then\n.*?\n  fi\n'
    text,n=re.subn(pattern,'  python3 media_gate.py guard "$OUTPUT" "$OUT_TMP"\n',text,flags=re.S)
    if n!=1 or text.count('  mv "$OUT_TMP" "$OUTPUT"')!=1:
        raise ValueError('Guarda/publicacao do script base nao reconhecida')
    return text.replace('  mv "$OUT_TMP" "$OUTPUT"','  mv "$OUT_TMP" "$OUTPUT"\n  mkdir -p validation_state\n  mv "$MEDIA_PENDING" validation_state/media.json')

if __name__=='__main__':
    text=integrate(Path('update_playlist.sh').read_text(encoding='utf-8'))
    with tempfile.TemporaryDirectory() as temp:
        script=Path(temp)/'update_selected.sh'
        script.write_text(text,encoding='utf-8')
        subprocess.run(['bash','-n',str(script)],check=True)
        subprocess.run(['bash',str(script)],check=True)
