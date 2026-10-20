#!/usr/bin/env bash
# relay status: HANDOFF.md 상태표 → 첫 응답 보고표. 사용: status.sh <HANDOFF.md>
set -euo pipefail
[ $# -ge 1 ] && [ -f "$1" ] || { echo "usage: status.sh <HANDOFF.md>" >&2; exit 2; }
python3 - "$1" <<'PY'
import re, sys, statistics
from datetime import datetime
path = sys.argv[1]
text = open(path, encoding='utf-8').read()
m = re.search(r'^## 상태표\s*$(.*?)(?=^## |\Z)', text, re.M | re.S)
if not m: sys.exit('상태표 절(## 상태표)이 없다')
rows = []
header = None
for line in m.group(1).splitlines():
    if not line.startswith('|'): continue
    cells = [c.strip() for c in line.strip().strip('|').split('|')]
    if header is None: header = cells; continue
    if set(''.join(cells)) <= set('-: '): continue
    rows.append(dict(zip(header, cells)))
if not rows: sys.exit('상태표 행이 없다')
def col(r, *names):
    for n in names:
        if n in r: return r[n]
    return ''
done = [r for r in rows if col(r, '상태') == '완료']
active = [r for r in rows if col(r, '상태') == '진행']
todo = [r for r in rows if col(r, '상태') in ('', '미착수', '보류')]
b = re.search(r'기준선:\s*(\d+(?:\.\d+)?)\s*%', text)
baseline = float(b.group(1)) if b else 0.0
weights = []
for r in rows:
    w = col(r, '가중치').rstrip('%p ')
    weights.append(float(w) if w else None)
if all(w is None for w in weights):
    share = (100 - baseline) / len(rows)
    weights = [share] * len(rows)
else:
    weights = [w or 0.0 for w in weights]
progress = baseline + sum(w for r, w in zip(rows, weights) if col(r, '상태') == '완료')
times = []
for r in done:
    t = col(r, '종료 시각')
    try: times.append(datetime.strptime(t, '%Y-%m-%d %H:%M'))
    except ValueError: pass
times.sort()
IDLE_MIN = 4 * 60  # 4시간 초과 간격은 밤샘·대기로 보고 단위 소요에서 제외
gaps = [(b_ - a).total_seconds() / 60 for a, b_ in zip(times, times[1:]) if 0 < (b_ - a).total_seconds() / 60 <= IDLE_MIN]
def quart(xs):
    xs = sorted(xs); n = len(xs)
    if n < 4: return xs[0], xs[-1]
    return xs[(n - 1) // 4], xs[(3 * (n - 1)) // 4]
remaining = len(active) + len(todo)
serial = re.search(r'세션 연번:\s*(.+)', text)
policy = re.search(r'커밋 정책:\s*(.+)', text)
print('| 항목 | 값 |'); print('|---|---|')
print(f"| 세션 연번 | {serial.group(1).strip() if serial else '?'} |")
print(f"| 커밋 정책 | {policy.group(1).strip() if policy else '확인 후'} |")
print(f"| 현재 단위 | {', '.join(col(r,'단위')+' '+col(r,'내용')[:40] for r in active) or ('다음: ' + (col(todo[0],'단위')+' '+col(todo[0],'내용')[:40] if todo else '없음'))} |")
print(f"| 완료 단위 | {', '.join(col(r,'단위') for r in done) or '없음'} ({len(done)}/{len(rows)}) |")
print(f"| 남은 단위 | {', '.join(col(r,'단위') for r in active + todo) or '없음'} |")
print(f"| 전체 진행률 | 약 {round(progress)}% (기준선 {baseline:g}% + 완료 가중치, ±10%p) |")
if gaps:
    med = statistics.median(gaps)
    q1, q3 = quart(gaps)
    print(f"| 단위 소요(최근) | 중앙값 {round(med)}분 (Q1 {round(q1)}·Q3 {round(q3)}, {len(gaps)}표본, 4시간 초과 간격 제외) |")
    print(f"| 남은 시간 추정 | {round(q1 * remaining)}~{round(q3 * remaining)}분 (중앙값 {round(med * remaining)}분, 남은 {remaining}단위) |")
else:
    print('| 단위 소요(최근) | 종료 시각 2개 이상 필요 |'); print(f'| 남은 시간 추정 | 미산정 (남은 {remaining}단위) |')
PY
