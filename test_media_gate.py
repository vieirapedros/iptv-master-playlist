import json, os, subprocess, tempfile, unittest
from pathlib import Path
from unittest.mock import patch
import media_gate as m
from run_validated_update import integrate
ROW=['#EXTINF:-1,Example','Example','https://example.invalid/live.m3u8','BR','','']
OK={'ok':True,'reason':'video_audio_ok'}
BAD={'ok':False,'reason':'timeout'}
class Tests(unittest.TestCase):
    def test_scope(self):
        self.assertEqual(len(m.CODES),23)
        self.assertTrue(m.CODES.isdisjoint({'AF','OC','AS','ARA','OT','ORG'}))
    def test_approved(self):
        self.assertTrue(m.due(m.transition(None,ROW,OK,0),1))
    def test_weekly(self):
        s=m.transition(None,ROW,BAD,0)
        self.assertFalse(m.due(s,6*m.DAY))
        self.assertTrue(m.due(s,7*m.DAY))
    def test_month(self):
        s=m.transition(None,ROW,BAD,0)
        for d in (7,14,21,28):
            s=m.transition(s,ROW,BAD,d*m.DAY)
            self.assertEqual(s['first_failure'],0)
            self.assertEqual(s['status'],'quarantine')
        self.assertEqual(s['next_test'],30*m.DAY)
        s=m.transition(s,ROW,BAD,30*m.DAY)
        self.assertEqual(s['status'],'discarded')
        self.assertNotIn('row',s)
        self.assertFalse(m.due(s,100*m.DAY))
    def test_recovery(self):
        s=m.transition(None,ROW,BAD,0)
        s=m.transition(s,ROW,OK,30*m.DAY)
        self.assertIsNone(s['first_failure'])
        s=m.transition(s,ROW,BAD,31*m.DAY)
        self.assertEqual(s['first_failure'],31*m.DAY)
    def test_headers(self):
        row=ROW.copy(); row[5]='#EXTVLCOPT:http-referrer=https://example.invalid/'
        self.assertIn('Referer: https://example.invalid/\r\n',m.options(row))
    def test_bad_headers(self):
        row=ROW.copy(); row[5]='#EXTHTTP:[]'
        with self.assertRaises(ValueError):m.options(row)
    def test_identity(self):
        self.assertNotEqual(m.digest(ROW[2]),m.digest(ROW[2]+'?new=1'))
    def test_integrate(self):
        old='  prepare_validation\n  validate_urls\n  merge_blacklist\n  build_kept\n  update_cache\n  build_master'
        text='#!/bin/bash\nmain() {\n  parse_blocks\n'+old+'\n  if (( prev_count > 0 && total_final * 100 < prev_count * MIN_DIFF_PCT )); then\n    exit 1\n  fi\n  mv "$OUT_TMP" "$OUTPUT"\n}\n'
        result=integrate(text)
        self.assertIn('  route_media\n',result)
        self.assertLess(result.index('  update_cache'),result.index('  cat "$MEDIA_VALID"'))
        p=subprocess.run(['bash','-n'],input=result,text=True,capture_output=True)
        self.assertEqual(p.returncode,0,p.stderr)
    def test_routing(self):
        cwd=os.getcwd()
        with tempfile.TemporaryDirectory() as temp:
            os.chdir(temp)
            try:
                Path('validation_state').mkdir()
                Path('validation_state/media.json').write_text('{"schema":1,"items":{}}')
                other=ROW.copy();other[2]='https://example.invalid/other';other[3]='ORG'
                Path('blocks').write_text(m.US.join(ROW)+'\n'+m.US.join(other)+'\n')
                with patch.object(m,'preflight'),patch.object(m,'test',return_value=OK):
                    m.gate('blocks','http','media','valid','pending')
                self.assertIn(other[2],Path('http').read_text())
                self.assertNotIn(ROW[2],Path('http').read_text())
                self.assertEqual(Path('valid').read_text().strip(),ROW[2])
                self.assertEqual(json.loads(Path('pending').read_text())['items'][m.digest(ROW[2])]['status'],'approved')
            finally:os.chdir(cwd)
if __name__=='__main__':unittest.main()
