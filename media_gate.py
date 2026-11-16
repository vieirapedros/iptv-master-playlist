#!/usr/bin/env python3
import hashlib, json, os, re, shutil, subprocess, tempfile, time, csv
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
CODES=set('BR PT AR MX PE ES US GB IT FR JP CL CO UY PY BO EC VE DE DK NO SE NL'.split())
US,RS='\x1f','\x1e'
DAY=86400

def digest(url):
    return hashlib.sha256(url.encode()).hexdigest()

def due(item,now):
    return item['status']!='discarded' and (item['status']=='approved' or now>=item['next_test'])

def transition(old,row,result,now):
    item=dict(old or {})
    item.update(row=row,last_test=now,reason=result['reason'])
    if result['ok']:
        item.update(status='approved',first_failure=None,next_test=now)
    else:
        first=item.get('first_failure')
        first=now if first is None else first
        expired=now-first>=30*DAY
        item.update(status='discarded' if expired else 'quarantine',first_failure=first,next_test=None if expired else min(now+7*DAY,first+30*DAY))
        if expired:
            item.pop('row',None)
    return item

def options(row):
    data={}
    for line in row[5].split(RS):
        if line.startswith('#EXTVLCOPT:'):
            k,sep,v=line[11:].partition('=')
            if sep:
                data[k.lower()]=v
        elif line.startswith('#EXTHTTP:'):
            obj=json.loads(line[10:])
            if not isinstance(obj,dict):
                raise ValueError('Invalid EXTHTTP')
            data.update({str(k).lower():str(v) for k,v in obj.items()})
    ua=data.get('http-user-agent',data.get('user-agent',os.getenv('USER_AGENT','Mozilla/5.0')))
    if '\r' in ua or '\n' in ua:
        raise ValueError('Invalid User-Agent')
    args=['-rw_timeout','10000000','-protocol_whitelist','http,https,tcp,tls,crypto','-user_agent',ua]
    aliases={'http-referrer':'Referer','http-referer':'Referer','referer':'Referer','origin':'Origin','cookie':'Cookie','authorization':'Authorization'}
    headers=[]
    for k,v in data.items():
        if k in aliases:
            if '\r' in v or '\n' in v:
                raise ValueError('Invalid header')
            headers.append(aliases[k]+': '+v+'\r\n')
    return args+(['-headers',''.join(headers)] if headers else [])

def reason(text):
    text=text.lower()
    for words,label in [(['401','403','forbidden','unauthorized'],'acesso_negado'),(['404','not found'],'nao_encontrado'),(['timed out','timeout'],'timeout_rede'),(['connection refused','failed to resolve','network is unreachable'],'conexao'),(['invalid data','error opening input'],'entrada_invalida')]:
        if any(w in text for w in words):
            return label
    return 'erro_midia'

def attempt(row):
    if re.search(r'https?://(?:www\.)?(?:youtube\.com|youtu\.be)/',row[2],re.I):
        return {'ok':False,'reason':'pagina_youtube_nao_e_stream_direto'}
    try:
        opts=options(row)
    except (ValueError,TypeError):
        return {'ok':False,'reason':'cabecalhos_invalidos'}
    seconds=int(os.getenv('MEDIA_SECONDS','20'))
    timeout=int(os.getenv('MEDIA_TIMEOUT_SECONDS','75'))
    try:
        p=subprocess.run(['ffprobe','-v','error',*opts,'-show_streams','-of','json',row[2]],capture_output=True,text=True,errors='replace',timeout=timeout)
        if p.returncode:
            return {'ok':False,'reason':reason(p.stderr)}
        streams=json.loads(p.stdout).get('streams',[])
        if not any(s.get('codec_type')=='video' and s.get('width',0)>0 for s in streams):
            return {'ok':False,'reason':'sem_video'}
        audio=any(s.get('codec_type')=='audio' for s in streams)
        cmd=['ffmpeg','-nostdin','-hide_banner','-loglevel','error','-xerror',*opts,'-i',row[2],'-t',str(seconds),'-map','0:v:0']
        if audio:
            cmd+=['-map','0:a:0']
        cmd+=['-threads','1','-progress','pipe:1','-nostats','-f','null','-']
        p=subprocess.run(cmd,capture_output=True,text=True,errors='replace',timeout=timeout)
        frames=max([int(n) for n in re.findall(r'^frame=\s*(\d+)\s*$',p.stdout,re.M)],default=0)
        elapsed=max([int(n) for n in re.findall(r'^out_time_us=(\d+)$',p.stdout,re.M)],default=0)
        ok=p.returncode==0 and frames>=2 and elapsed>=(seconds-1)*1000000
        return {'ok':ok,'reason':('video_audio_ok' if audio else 'video_ok_sem_audio') if ok else reason(p.stderr)}
    except subprocess.TimeoutExpired:
        return {'ok':False,'reason':'timeout'}
    except (ValueError,TypeError):
        return {'ok':False,'reason':'resposta_midia_invalida'}

def test(row):
    result=attempt(row)
    if not result['ok']:
        time.sleep(int(os.getenv('MEDIA_RETRY_DELAY_SECONDS','5')))
        result=attempt(row)
    return result

def preflight():
    for name in ('ffprobe','ffmpeg'):
        if not shutil.which(name):
            raise RuntimeError(name+' ausente')
    with tempfile.TemporaryDirectory() as temp:
        sample=str(Path(temp)/'sample.mkv')
        p=subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc=size=32x32:rate=5','-t','1','-c:v','ffv1',sample],capture_output=True,timeout=20)
        if p.returncode:
            raise RuntimeError('Autoteste FFmpeg falhou')
        p=subprocess.run(['ffprobe','-v','error','-show_streams',sample],capture_output=True,timeout=20)
        if p.returncode:
            raise RuntimeError('Autoteste ffprobe falhou')

def gate(blocks,http,media,valid,pending):
    preflight()
    workers=int(os.getenv('MEDIA_JOBS','4'))
    seconds=int(os.getenv('MEDIA_SECONDS','20'))
    timeout=int(os.getenv('MEDIA_TIMEOUT_SECONDS','75'))
    if not 1<=workers<=16 or not 5<=seconds<=60 or timeout<seconds+10:
        raise ValueError('Parametros invalidos')
    state=json.loads(Path('validation_state/media.json').read_text())
    if state.get('schema')!=1 or not isinstance(state.get('items'),dict):
        raise ValueError('Historico invalido')
    items,current,others=state['items'],{},[]
    for line in Path(blocks).read_text(encoding='utf-8').split('\n'):
        if not line:
            continue
        row=line.split(US)
        if len(row)!=6:
            raise ValueError('Bloco invalido')
        if row[3] in CODES:
            current[digest(row[2])]=row
        else:
            others.append(row)
    candidates=dict(current)
    for k,item in items.items():
        if item['status']=='quarantine':
            candidates.setdefault(k,item['row'])
    now=int(time.time())
    tasks=[(k,row) for k,row in candidates.items() if k not in items or due(items[k],now)]
    results={}
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for (k,row),result in zip(tasks,pool.map(lambda pair:test(pair[1]),tasks)):
            results[k]=result
            if len(results)%25==0:
                print(f'Midia: {len(results)}/{len(tasks)} concluidos',flush=True)
    reports=Path('reports'); reports.mkdir(exist_ok=True)
    (reports/'media_attempts.json').write_text(json.dumps(results,indent=2))
    failures=sum(not r['ok'] for r in results.values())
    if len(results)>=20 and failures/len(results)>=0.95 and os.getenv('ALLOW_MASS_FAILURE')!='1':
        raise RuntimeError('Falha massiva; publicacao cancelada para revisao')
    approved,rows=[],[]
    for k,row in candidates.items():
        if k in results:
            items[k]=transition(items.get(k),row,results[k],now)
        item=items[k]
        if k in results and results[k]['ok']:
            approved.append(row)
        rows.append([k,row[1],row[3],item['status'],item['reason'],k in results,item.get('first_failure'),item.get('next_test')])
    others=[r for r in others if digest(r[2]) not in items]
    for path,content in [(http,''.join(US.join(r)+'\n' for r in others)),(media,''.join(US.join(r)+'\n' for r in approved)),(valid,''.join(r[2]+'\n' for r in approved)),(pending,json.dumps(state,ensure_ascii=False,indent=2)+'\n')]:
        Path(path).write_text(content,encoding='utf-8')
    with (reports/'media_validation.csv').open('w',newline='',encoding='utf-8') as f:
        writer=csv.writer(f)
        writer.writerow(['url_sha256','canal','pais','estado','motivo','testado_agora','primeira_falha_unix','proximo_teste_unix'])
        writer.writerows(rows)
    summary={'tested':len(results),'approved':len(approved),'failed_now':failures,'quarantine':sum(i['status']=='quarantine' for i in items.values()),'discarded':sum(i['status']=='discarded' for i in items.values())}
    (reports/'media_summary.json').write_text(json.dumps(summary,indent=2))
    print(json.dumps(summary),flush=True)

def http_count(path):
    if not path.exists():
        return 0
    count=0
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        m=re.search(r'group-title="([^"]*)"',line) if line.startswith('#EXTINF:') else None
        if m and (m[1]=='IPTV-ORG (Global)' or m[1]=='WORLD' or m[1].startswith('WORLD - ')):
            count+=1
    return count

def guard(before,after):
    old,new=http_count(Path(before)),http_count(Path(after))
    if old and new*100<old*int(os.getenv('MIN_DIFF_PCT','50')):
        raise RuntimeError(f'Queda anormal nos grupos HTTP: {old} -> {new}')

if __name__=='__main__':
    import sys
    if len(sys.argv)==4 and sys.argv[1]=='guard':
        guard(*sys.argv[2:])
    elif len(sys.argv)==7 and sys.argv[1]=='gate':
        gate(*sys.argv[2:])
    else:
        raise SystemExit('Uso: media_gate.py gate BLOCKS HTTP MEDIA VALID PENDING | guard OLD NEW')
