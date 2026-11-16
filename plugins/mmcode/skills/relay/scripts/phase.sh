#!/usr/bin/env bash
# relay phase: 단위의 단계 전환·검사 결과·커밋·멈춤·결정·지시를 이벤트 파일에 쓰고 HANDOFF.md 상태표와 .mmcode/DECISIONS.md 를 다시 만든다.
# 사용: phase.sh <하위 명령> <HANDOFF.md|프로젝트 폴더> [인자...]   (인자 없이 부르면 사용법이 나온다)
# 폴더를 넘기면 plan 은 - 이고 ask(단위 -)·answer·direct·applied·rejected·gate·show 만 된다(relay 가 아닌 세션, codex·agy 용).
# 종료 코드: 0 성공 · 1 거부 또는 검사 실패(stdout 마지막 줄 REFUSED: <이유> 또는 FAILED: <이유>) · 2 사용 오류
# 이벤트 파일: <프로젝트>/.mmcode/events.jsonl (추가만 한다). 읽기·판정·추가·상태표 갱신은 .mmcode/.lock 을 잡고 한다.
# check 의 명령 실행은 잠금 밖에서 돈다. 거부하면 이벤트를 쓰지 않는다.
# 예외: 열린 단위 후 정지 지시로 move <단위> build 를 처음 거부할 때는 directive.applied 와 그 단위의 unit.halt 를 쓴다.
# gate 는 도구 호출 전 훅용이다: 열린 즉시 중단 지시가 있으면 종료 코드 2. 이벤트 파일이 없거나 내부 오류면 0(막지 않는 쪽).
# 상태표에 선택 열 `등급`(가벼움·일반·고위험)·`화면`(✔)이 있으면 등급별 증거(계획 3.4절)가 없을 때 전환을 거부한다. 열이 없으면 적용하지 않는다.
# ready 는 단위가 검수 단계이고 멈추지 않았고 완료에 필요한 증거(커밋 기록 제외)가 있는지만 본다. 이벤트를 쓰지 않는다(relay auto 의 커밋 전 검사).
# move <단위> queued --reason 은 구현·검증·검수에서 대기로 되돌린다(relay auto 의 unit discard).
# 근거: docs/plans/orchestration-plan.md 3.2~3.5절, 4.1~4.4절. 외부 의존 없음(bash + python3 + git).
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "python3 이 없다" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git 이 없다" >&2; exit 2; }
# 파이썬의 stdin 은 이 스크립트라서 원래 stdin(gate 의 훅 JSON)을 fd 3 으로 넘긴다. stdin 이 닫혀 있으면 /dev/null 을 준다.
{ : <&0; } 2>/dev/null && exec 3<&0 || exec 3</dev/null
exec python3 -I - "$@" <<'PY'
import contextlib, fcntl, json, os, re, shlex, subprocess, sys, tempfile, traceback
from datetime import datetime

USAGE = '''사용: phase.sh <하위 명령> <HANDOFF.md|프로젝트 폴더> [인자...]   (폴더는 ask·answer·direct·applied·rejected·gate·show 만)
  move <단위> <단계> [--reason <사유>]     단계: queued build verify review done. 대기(queued)로 되돌리기는 --reason 필수
  ready <단위>                             검수 단계·멈춤 없음·완료 증거(커밋 기록 제외)가 다 있으면 OK. 이벤트를 쓰지 않는다
  check <단위> <종류> [--reason <사유>] [--evidence <경로>] [--pass|--fail] [-- <명령...>]
                                           종류: cmd(명령 필수) manual fail-first review mutation cross-review coverage ui-review
                                           fail-first 는 명령이 실패(종료 코드 0 아님)해야 통과다. 명령 없는 면제는 --pass --reason "해당 없음: <이유>"(고위험은 거부)
  commit <단위> <저장소> <해시|없음(변경 없음)>
  halt <단위> <값>                         값: decision stop-after interrupt blocked:<그 단위>
  resume <단위>
  ask <단위|-> --question <질문> [--recommend <추천>] [--impact <영향>] [--option <선택지>]...
                                           결정 요청 D<n>. 단위가 있으면 그 단위를 decision 으로 멈춘다
  answer <ID> --answer <답> [--by user|planner|cross-review] [--undo <되돌리는 방법>]
                                           결정 답. 그 결정으로 멈춘 단위를 푼다
  direct <message|stop-after|interrupt|reorder|resume> [--text <글>] [--terminal <주소>]
                                           지시 접수 I<n>. message·reorder 는 --text 필수. resume 은 열린 정지·중단 지시를 닫는다
  applied <ID> [--reason <글>]             지시 적용 기록
  rejected <ID> --reason <글>              지시 거부 기록
  gate                                     stdin 의 훅 JSON 을 읽고 열린 즉시 중단 지시가 있으면 종료 코드 2
  show                                     단위별 단계·멈춤·남은 증거 표, 열린 결정·지시, 상태표와 DECISIONS.md 다시 생성'''

NOCHANGE = '없음(변경 없음)'
PHASES = ['queued', 'build', 'verify', 'review', 'done']
NEXT = {'queued': ['build'], 'build': ['verify', 'queued'], 'verify': ['review', 'build', 'queued'],
        'review': ['done', 'build', 'queued'], 'done': []}
BACK = {('verify', 'build'), ('review', 'build'), ('build', 'queued'), ('verify', 'queued'), ('review', 'queued')}
PHASE_KO = {'queued': '대기', 'build': '구현', 'verify': '검증', 'review': '검수', 'done': '완료'}
STATUS_KO = {'queued': '미착수', 'build': '진행', 'verify': '진행', 'review': '진행', 'done': '완료'}
KINDS = ['cmd', 'manual', 'fail-first', 'review', 'mutation', 'cross-review', 'coverage', 'ui-review']
HALTS = ['decision', 'stop-after', 'interrupt']
DIRECTIVES = ['message', 'stop-after', 'interrupt', 'reorder', 'resume']
DECIDERS = ['user', 'planner', 'cross-review']
FOLDER_CMDS = ['ask', 'answer', 'direct', 'applied', 'rejected', 'gate', 'show']
GRADES = ['가벼움', '일반', '고위험']
NEED_COLS = ['단위', '상태', '종료 시각', '커밋']
GITENV = {k: v for k, v in os.environ.items()
          if k not in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_PREFIX')}


class Usage(Exception):
    pass


class Refused(Exception):
    def __init__(self, msg, events=()):
        super().__init__(msg)
        self.events = list(events)  # 거부하면서도 쓸 이벤트(단위 후 정지의 첫 거부만)


class Failed(Exception):
    pass


def read(p):
    with open(p, encoding='utf-8', newline='') as f:
        return f.read()


def write_atomic(path, text):
    # 임시 파일에 다 쓴 뒤 교체한다. 줄바꿈 문자는 그대로 둔다.
    d = os.path.dirname(path)
    mode = os.stat(path).st_mode & 0o777 if os.path.exists(path) else 0o644
    fd, tmp = tempfile.mkstemp(dir=d, prefix='.tmp-')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def cell_spans(line):
    # 표 한 줄을 칸 경계 [(왼쪽 |, 오른쪽 |)] 로 나눈다. \| 는 칸 구분이 아니다. 양 끝이 | 가 아니면 None.
    s = line.rstrip()
    bars = [i for i, ch in enumerate(s) if ch == '|' and (i == 0 or s[i - 1] != '\\')]
    if len(bars) < 2 or bars[0] != 0 or bars[-1] != len(s) - 1:
        return None
    return list(zip(bars, bars[1:]))


def cell_text(line, span):
    return line[span[0] + 1:span[1]].strip().replace('\\|', '|')


class Ctx:
    def __init__(self, path):
        self.hpath = os.path.realpath(path)
        if os.path.isdir(self.hpath):  # 폴더 모드: 상태표가 없고 plan 은 -
            self.pdir, self.plan, self.hpath = self.hpath, '-', None
        elif os.path.isfile(self.hpath):
            self.pdir = os.path.dirname(self.hpath)
            self.plan = os.path.basename(self.pdir)
        else:
            raise Usage(f'인계 문서 없음: {path}')
        r = subprocess.run(['git', '-C', self.pdir, 'rev-parse', '--show-toplevel'],
                           capture_output=True, text=True, env=GITENV)
        if r.returncode:
            raise Usage(f'git 저장소가 아니다: {self.pdir}')
        self.root = os.path.realpath(r.stdout.strip())
        self.mm = os.path.join(self.root, '.mmcode')
        self.events = os.path.join(self.mm, 'events.jsonl')
        self.lockp = os.path.join(self.mm, '.lock')

    def ensure_dir(self):
        os.makedirs(self.mm, exist_ok=True)
        gi = os.path.join(self.mm, '.gitignore')
        if not os.path.exists(gi):
            with open(gi, 'w', encoding='utf-8') as f:
                f.write('*\n')

    def rel(self, p):
        a = os.path.realpath(p)
        return os.path.relpath(a, self.root) if a == self.root or a.startswith(self.root + os.sep) else a


@contextlib.contextmanager
def locked(c):
    c.ensure_dir()
    fd = os.open(c.lockp, os.O_CREAT | os.O_RDWR, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def load_events(c, every=False):
    # 이 계획의 이벤트만(every 면 모든 계획), 파일 순서대로.
    out = []
    try:
        f = open(c.events, encoding='utf-8')
    except FileNotFoundError:
        return out
    with f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if isinstance(e, dict) and (every or e.get('plan') == c.plan):
                out.append(e)
    return out


def append_event(c, etype, unit, data, plan=None):
    actor = {k: os.environ.get(v) for k, v in
             (('terminal', 'HC_TERMINAL_ID'), ('harness', 'PHASE_HARNESS'), ('model', 'PHASE_MODEL'), ('effort', 'PHASE_EFFORT'))}
    e = {'ts': datetime.now().astimezone().isoformat(timespec='seconds'), 'type': etype, 'plan': plan or c.plan, 'unit': unit,
         'actor': {k: v for k, v in actor.items() if v}, 'data': data}
    pre = ''
    try:
        with open(c.events, 'rb') as f:  # 끝 줄에 개행이 없으면(끊긴 쓰기) 새 이벤트가 그 줄에 붙지 않게 개행부터 쓴다
            f.seek(-1, 2)
            if f.read(1) != b'\n':
                pre = '\n'
    except OSError:
        pass
    with open(c.events, 'a', encoding='utf-8') as f:
        f.write(pre + json.dumps(e, ensure_ascii=False) + '\n')
        f.flush()
        os.fsync(f.fileno())
    return e


class Table:
    # HANDOFF.md 의 ## 상태표 표. 줄 목록을 들고 있고, 고친 줄만 바꿔 다시 쓴다.
    def __init__(self, c):
        self.path = c.hpath
        self.lines = read(self.path).split('\n')
        start = next((i for i, ln in enumerate(self.lines) if re.fullmatch(r'## 상태표\s*', ln.rstrip('\r'))), None)
        if start is None:
            raise Usage('상태표 절(## 상태표)이 없다')
        end = next((i for i in range(start + 1, len(self.lines)) if self.lines[i].startswith('## ')), len(self.lines))
        hi = next((i for i in range(start + 1, end) if self.lines[i].startswith('|')), None)
        if hi is None:
            raise Usage('상태표 표가 없다')
        spans = cell_spans(self.lines[hi])
        if spans is None:
            raise Usage('상태표 머리줄을 읽지 못한다')
        names = [cell_text(self.lines[hi], s) for s in spans]
        self.cols = {n: i for i, n in enumerate(names)}
        missing = [n for n in NEED_COLS if n not in self.cols]
        if missing:
            raise Usage('상태표에 열이 없다: ' + ', '.join(missing))
        self.rows = []  # [줄 번호, 칸 경계]
        for li in range(hi + 1, end):
            ln = self.lines[li]
            if not ln.startswith('|'):
                break
            sp = cell_spans(ln)
            if sp is None or set(ln.replace('|', '')) <= set('-: \r'):
                continue
            if len(sp) > self.cols['단위']:
                self.rows.append([li, sp])
        self.dirty = False

    def text(self, row, name):
        li, sp = row
        i = self.cols.get(name)
        return cell_text(self.lines[li], sp[i]) if i is not None and i < len(sp) else ''

    def grade(self, row):
        # 등급 열이 없거나 칸이 비면 None(U2와 같은 동작). 모르는 값은 사용 오류.
        t = self.text(row, '등급')
        if t and t not in GRADES:
            raise Usage(f'알 수 없는 등급: {t} ({" ".join(GRADES)})')
        return t or None

    def screen(self, row):
        # 모르는 값(✓ 등)을 화면 없음으로 읽으면 ui-review 가 조용히 빠진다.
        t = self.text(row, '화면')
        if t not in ('', '✔', '✘', '-', '—'):
            raise Usage(f'알 수 없는 화면 값: {t} (✔ 또는 ✘)')
        return t == '✔'

    def units(self):
        return [self.text(r, '단위') for r in self.rows]

    def row(self, unit):
        return next((r for r in self.rows if self.text(r, '단위') == unit), None)

    def set_cells(self, row, want):
        li, sp = row
        line = self.lines[li]
        for name in sorted(want, key=lambda n: -self.cols[n]):  # 오른쪽 칸부터 고쳐야 왼쪽 경계가 유지된다
            i = self.cols[name]
            if i >= len(sp) or cell_text(line, sp[i]) == want[name]:
                continue
            line = line[:sp[i][0] + 1] + ' ' + want[name].replace('|', '\\|') + ' ' + line[sp[i][1]:]
        if line != self.lines[li]:
            self.lines[li] = line
            row[1] = cell_spans(line)  # 줄 길이가 달라졌으므로 칸 경계를 다시 구한다
            self.dirty = True

    def save(self):
        if self.dirty:
            write_atomic(self.path, '\n'.join(self.lines))


def unit_state(evs, unit):
    s = {'n': 0, 'phase': 'queued', 'halt': None, 'halt_d': {}, 'checks': [], 'commits': [], 'done_ts': None, 'ff': None}
    for e in evs:
        if e.get('unit') != unit:
            continue
        s['n'] += 1
        t, d = e.get('type'), e.get('data')
        d = d if isinstance(d, dict) else {}
        if t == 'unit.phase' and d.get('to') in PHASES:
            s['phase'] = d['to']
            if d['to'] == 'build':
                s['commits'] = []
            elif d['to'] == 'verify':
                s['checks'] = []
            elif d['to'] == 'done':
                s['done_ts'] = e.get('ts')
        elif t == 'check.result':
            s['checks'].append(d)
            if d.get('kind') == 'fail-first':
                s['ff'] = bool(d.get('pass'))  # 실패 먼저는 단위 기록 전체에서 가장 최근 결과를 본다
        elif t == 'unit.commit':
            s['commits'].append(d)
        elif t == 'unit.halt':
            s['halt'], s['halt_d'] = d.get('reason') or 'halt', d
        elif t == 'unit.resume':
            s['halt'], s['halt_d'] = None, {}
    return s


def count_phase(evs, unit):
    return sum(1 for e in evs if e.get('unit') == unit and e.get('type') == 'unit.phase')


def known_phase(tbl, evs, unit):
    # 이벤트가 없는 단위는 손으로 쓴 상태표를 믿는다: `완료`만 done 으로 본다(phase.sh 를 계획 도중에 들인 경우).
    s = unit_state(evs, unit)
    row = tbl.row(unit)
    if not s['n'] and row is not None and tbl.text(row, '상태') == '완료':
        return 'done'
    return s['phase']


def need_build(s):
    return [] if s['ff'] is True else ['fail-first']


def need_verify(g, checks):
    kinds = ('cmd',) if g == '고위험' else ('cmd', 'manual')
    if any(d.get('kind') in kinds and d.get('pass') for d in checks):
        return []
    return ['cmd'] if g == '고위험' else ['cmd 또는 manual']


def need_done(g, screen, checks):
    last = {}
    for d in checks:
        last[d.get('kind')] = bool(d.get('pass'))
    kinds = ['review', 'mutation'] + (['cross-review'] if g == '고위험' else []) + (['ui-review'] if screen else [])
    return [k for k in kinds if last.get(k) is not True]


def missing(g, screen, frm, to, s):
    # 이 전환에 빠진 증거 종류. 등급이 없거나 가벼움이면 없다.
    if g in (None, '가벼움'):
        return []
    if (frm, to) == ('build', 'verify'):
        return need_build(s)
    if (frm, to) == ('verify', 'review'):
        return need_verify(g, s['checks'])
    if (frm, to) == ('review', 'done'):
        return need_done(g, screen, s['checks'])
    return []


def remaining(g, screen, phase, s):
    # 완료까지 빠진 증거 종류(show 용). 구현 이전 단계의 검사 결과는 검증 진입 때 비워지므로 세지 않는다.
    if g in (None, '가벼움') or phase == 'done':
        return []
    cks = s['checks'] if phase in ('verify', 'review') else []
    out = need_build(s) if phase in ('queued', 'build') else []
    if phase != 'review':
        out += need_verify(g, cks)
    return out + need_done(g, screen, cks)


def status_text(s):
    h = s['halt']
    if h and h.startswith('blocked'):
        return 'blocked'
    if h in ('stop-after', 'interrupt'):
        return '보류'
    return STATUS_KO[s['phase']]


def halt_ko(h):
    if not h:
        return '-'
    if h == 'decision':
        return '결정 대기'
    if h in ('stop-after', 'interrupt'):
        return '사용자 정지'
    return '단위 막힘' if h.startswith('blocked') else h


def commit_text(commits):
    parts = [NOCHANGE if d.get('hash') == NOCHANGE else f"{d.get('repo', '')} {str(d.get('hash', ''))[:7]}" for d in commits]
    return '; '.join(parts)


def sync_table(tbl, evs):
    # 이 계획의 이벤트가 있는 단위의 행만 고친다. 고치는 칸은 상태·종료 시각·커밋뿐이다.
    for row in tbl.rows:
        s = unit_state(evs, tbl.text(row, '단위'))
        if not s['n']:
            continue
        want = {'상태': status_text(s)}
        if s['phase'] == 'done':
            try:
                want['종료 시각'] = datetime.fromisoformat(s['done_ts']).strftime('%Y-%m-%d %H:%M')
            except (TypeError, ValueError):
                pass
            if s['commits']:
                want['커밋'] = commit_text(s['commits'])
        tbl.set_cells(row, want)
    tbl.save()


def require_unit(tbl, unit, evs):
    # 상태표에 있는 단위만 쓴다. 이벤트가 없는데 상태 칸이 미착수·빈 칸이 아니면 손으로 관리하던 단위라 거부한다.
    row = tbl.row(unit)
    if row is None:
        raise Refused(f'상태표에 없는 단위: {unit}')
    cur = tbl.text(row, '상태')
    if cur not in ('', '미착수') and not any(e.get('unit') == unit for e in evs):
        raise Refused(f'{unit} 은 손으로 관리하던 단위다(상태 {cur}). 상태 칸을 미착수로 바꾼 뒤 옮긴다')
    return row


def transact(c, fn):
    # 잠금 안에서 표와 이벤트를 읽고, fn 이 정한 이벤트를 쓰고, 상태표와 DECISIONS.md 를 갱신한다.
    # fn 은 None, (종류, 단위, data[, plan]) 하나, 또는 그 목록을 준다. 폴더 모드는 표가 없다(tbl None).
    with locked(c):
        tbl = Table(c) if c.hpath else None
        evs = load_events(c)
        refused = None
        try:
            res = fn(tbl, evs)
        except Refused as r:
            if not r.events:
                raise
            res, refused = r.events, r
        for ev in [res] if isinstance(res, tuple) else res or []:
            e = append_event(c, *ev)
            if e['plan'] == c.plan:
                evs.append(e)
        if tbl:
            sync_table(tbl, evs)
        write_decisions(c, load_events(c, every=True))
        if refused:
            raise refused
        return tbl, evs


def edata(e):
    d = e.get('data')
    return d if isinstance(d, dict) else {}


def decisions(alls):
    # 결정 ID -> {'ask': 요청 이벤트, 'answer': 답 이벤트 data 또는 None}
    out = {}
    for e in alls:
        d = edata(e)
        if e.get('type') == 'decision.ask' and d.get('id'):
            out[d['id']] = {'ask': e, 'answer': None}
        elif e.get('type') == 'decision.answer' and d.get('id') in out:
            out[d['id']]['answer'] = d
    return out


def directives(alls):
    # 지시 ID -> 상태. done: 적용·거부·resume 으로 닫혔다. active: 막는 지시(stop-after·interrupt)가 resume 으로 닫히기 전이다.
    out = {}
    for e in alls:
        t, d = e.get('type'), edata(e)
        if t == 'directive.received' and d.get('id'):
            out[d['id']] = {'e': e, 'd': d, 'kind': d.get('kind'), 'plan': e.get('plan'),
                            'applied': False, 'rejected': False, 'closed': False}
            for x in d.get('closes') or []:
                if x in out:
                    out[x]['closed'] = True
        elif t in ('directive.applied', 'directive.rejected') and d.get('id') in out:
            out[d['id']]['applied' if t == 'directive.applied' else 'rejected'] = True
    for x in out.values():
        x['done'] = x['applied'] or x['rejected'] or x['closed'] or x['kind'] == 'resume'  # resume 은 접수가 곧 적용이다
        x['active'] = x['kind'] in ('stop-after', 'interrupt') and not x['closed']
    return out


def relevant(x, plan):
    # 폴더 모드(-)의 지시는 모든 계획에, 계획의 지시는 그 계획에만 걸린다.
    return '-' in (x['plan'], plan) or x['plan'] == plan


def next_id(prefix, ids):
    return prefix + str(max([int(i[1:]) for i in ids if re.fullmatch(prefix + r'\d+', i)] or [0]) + 1)


def mdcell(v):
    v = '; '.join(v) if isinstance(v, list) else str(v or '')
    return v.replace('\r', '').replace('|', '\\|').replace('\n', '<br>') or '-'


def mdrow(vals):
    return '| ' + ' | '.join(mdcell(v) for v in vals) + ' |'


def write_decisions(c, alls):
    # 결정 대기열 파일. 결정이 하나도 없으면 만들지 않는다.
    ds = decisions(alls)
    if not ds:
        return
    opn = [mdrow([i, x['ask'].get('plan'), x['ask'].get('unit'), d.get('question'), d.get('recommend'), d.get('impact'),
                  ' / '.join(d.get('options') or [])])
           for i, x in ds.items() if not x['answer'] for d in [edata(x['ask'])]]
    ans = [mdrow([i, x['ask'].get('plan'), x['ask'].get('unit'), edata(x['ask']).get('question'), a.get('answer'), a.get('by'), a.get('undo')])
           for i, x in ds.items() if x['answer'] for a in [x['answer']]]
    lines = ['# 결정 대기열', '', 'phase.sh 가 .mmcode/events.jsonl 에서 만든다. 손으로 고치지 않는다.', '', '## 열린 결정', '']
    lines += ['| ID | 계획 | 단위 | 질문 | 추천 | 영향 | 선택지 |', '|---|---|---|---|---|---|---|'] + opn if opn else ['- 없음']
    lines += ['', '## 답한 결정', '']
    lines += ['| ID | 계획 | 단위 | 질문 | 답 | 정한 쪽 | 되돌리는 방법 |', '|---|---|---|---|---|---|---|'] + ans if ans else ['- 없음']
    path = os.path.join(c.mm, 'DECISIONS.md')
    text = '\n'.join(lines) + '\n'
    if not os.path.exists(path) or read(path) != text:
        write_atomic(path, text)


def need(rest, n, exact=True):
    if len(rest) < n or (exact and len(rest) > n):
        raise Usage(USAGE)


def opts(args, single, multi=()):
    # --키 값 쌍을 읽는다. 같은 단일 키를 두 번 주면 뒤의 값을 쓴다.
    o, i = {}, 0
    while i < len(args):
        k = args[i]
        if (k not in single and k not in multi) or i + 1 >= len(args):
            raise Usage(f'알 수 없는 인자 또는 값 없음: {k}')
        if k in multi:
            o.setdefault(k, []).append(args[i + 1])
        else:
            o[k] = args[i + 1]
        i += 2
    return o


def parse_reason(rest):
    # move 의 선택 인자: --reason <사유>
    if not rest:
        return None
    if len(rest) != 2 or rest[0] != '--reason' or not rest[1]:
        raise Usage(USAGE)
    return rest[1]


def judge(c, tbl, evs, unit, to, reason, need_commit=True):
    # 전환 판정. 안 되면 Refused, 되면 쓸 unit.phase 이벤트. ready 는 need_commit=False 로 같은 판정을 쓴다.
    row = require_unit(tbl, unit, evs)
    grade = tbl.grade(row)
    s = unit_state(evs, unit)
    frm = s['phase']
    if s['halt']:
        raise Refused(f'{unit} 은 멈춘 단위다({s["halt"]}). resume 뒤에 옮긴다')
    if to not in NEXT[frm]:
        ok = ', '.join(NEXT[frm]) or '없음'
        raise Refused(f'{unit} {frm}→{to} 는 안 된다. {frm} 에서 갈 수 있는 단계: {ok}')
    if (frm, to) in BACK and not reason:
        raise Refused(f'{frm}→{to} 되돌아가기는 --reason 이 필요하다')
    if frm == 'queued':
        stops = [x for x in directives(load_events(c, every=True)).values()
                 if x['kind'] == 'stop-after' and x['active'] and relevant(x, c.plan)]
        if stops:
            new = [('directive.applied', '-', {'id': x['d']['id']}, x['plan']) for x in stops if not x['applied']]
            if new:
                new.append(('unit.halt', unit, {'reason': 'stop-after', 'directive': stops[0]['d']['id']}))
            ids = ', '.join(x['d']['id'] for x in stops)
            raise Refused(f'단위 후 정지 지시 {ids} 가 열려 있다. {unit} 을 시작하지 않는다. 계속하려면 사용자가 direct resume 을 실행한다', new)
        pre = [t for t in re.split(r'[,\s]+', tbl.text(row, '선행')) if t and t not in ('—', '-')]
        pend = [f'{p}({PHASE_KO[ph]})' for p in pre for ph in [known_phase(tbl, evs, p)] if ph != 'done']
        if pend:
            raise Refused('선행 단위가 완료가 아니다: ' + ', '.join(pend))
    elif frm == 'verify' and to == 'review':
        last = {}
        for d in s['checks']:
            last[(d.get('kind'), d.get('command') or d.get('reason'))] = bool(d.get('pass'))
        if not last:
            raise Refused('검증 단계 진입 뒤의 검사 결과가 없다')
        bad = [f'{k[0]}' + (f' ({k[1]})' if k[1] else '') for k, ok in last.items() if not ok]
        if bad:
            raise Refused('통과하지 못한 검사가 있다: ' + ', '.join(bad))
    elif frm == 'review' and to == 'done' and need_commit and not s['commits']:
        raise Refused('구현 단계 진입 뒤의 커밋 기록이 없다')
    miss = missing(grade, tbl.screen(row), frm, to, s)
    if miss:
        raise Refused(f'{unit} 에 빠진 증거: ' + ', '.join(miss))
    data = {'from': frm, 'to': to}
    if reason:
        data['reason'] = reason
    return 'unit.phase', unit, data


def cmd_move(c, rest):
    need(rest, 2, exact=False)
    unit, to = rest[0], rest[1]
    reason = parse_reason(rest[2:])
    if to not in PHASES:
        raise Usage(f'알 수 없는 단계: {to} (queued build verify review done)')
    transact(c, lambda tbl, evs: judge(c, tbl, evs, unit, to, reason))
    print(f'OK: {unit} {to} 로 옮겼다')


def cmd_ready(c, rest):
    # 읽기만 한다: 이벤트도 상태표도 쓰지 않는다.
    need(rest, 1)
    unit = rest[0]
    with locked(c):
        tbl, evs = Table(c), load_events(c)
        require_unit(tbl, unit, evs)
        ph = unit_state(evs, unit)['phase']
        if ph != 'review':
            raise Refused(f'{unit} 은 검수 단계가 아니다(지금 {ph})')
        judge(c, tbl, evs, unit, 'done', None, need_commit=False)
    print(f'OK: {unit} 커밋해도 된다(검수 단계, 증거 있음)')


def cmd_check(c, rest):
    need(rest, 2, exact=False)
    unit, kind = rest[0], rest[1]
    if kind not in KINDS:
        raise Usage(f'알 수 없는 종류: {kind} ({" ".join(KINDS)})')
    reason = evidence = flag = cmd = None
    args, i = rest[2:], 0
    while i < len(args):
        a = args[i]
        if a == '--':
            cmd = args[i + 1:]
            if not cmd:
                raise Usage('-- 뒤에 명령이 없다')
            break
        if a in ('--reason', '--evidence'):
            if i + 1 >= len(args):
                raise Usage(f'{a} 에 값이 없다')
            if a == '--reason':
                reason = args[i + 1]
            else:
                evidence = args[i + 1]
            i += 2
        elif a in ('--pass', '--fail'):
            if flag and flag != a:
                raise Usage('--pass 와 --fail 을 함께 쓸 수 없다')
            flag = a
            i += 1
        else:
            raise Usage(f'알 수 없는 인자: {a}')
    if cmd and flag:
        raise Usage('명령이 있으면 --pass, --fail 을 쓸 수 없다')
    if kind == 'cmd' and not cmd:
        raise Usage('cmd 종류는 -- 뒤에 명령이 필요하다')
    if not cmd and (not flag or not reason):
        raise Usage('명령이 없으면 --pass 또는 --fail 과 --reason 이 필요하다')
    evs0 = load_events(c)
    require_unit(Table(c), unit, evs0)  # 거부될 단위의 명령은 돌리지 않는다
    phases0 = count_phase(evs0, unit)
    data = {'kind': kind}
    log = None
    if cmd:
        c.ensure_dir()
        os.makedirs(os.path.join(c.mm, 'logs'), exist_ok=True)
        stamp = datetime.now().strftime('%Y%m%dT%H%M%S')
        n = 1
        while True:
            log = os.path.join(c.mm, 'logs', f'{c.plan}-{unit}-{kind}-{stamp}' + (f'-{n}' if n > 1 else '') + '.log')
            try:
                f = open(log, 'xb')
                break
            except FileExistsError:
                n += 1
        started = True
        with f:
            try:
                rc = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=f, stderr=subprocess.STDOUT).returncode
            except OSError as e:
                f.write(f'{e}\n'.encode('utf-8'))
                rc, started = 127, False
        ok = rc != 0 and started if kind == 'fail-first' else rc == 0  # 실패 먼저는 명령이 시작된 뒤 실패해야 통과다
        data.update({'pass': ok, 'command': shlex.join(cmd), 'exit': rc})
    else:
        data['pass'] = flag == '--pass'
    if reason:
        data['reason'] = reason
    if evidence:
        data['evidence'] = c.rel(evidence)
    elif log:
        data['evidence'] = c.rel(log)
    def fn(tbl, evs):
        row = require_unit(tbl, unit, evs)
        if kind == 'fail-first' and not cmd and tbl.grade(row) == '고위험':
            raise Refused('고위험 단위의 fail-first 는 명령이 필요하다')
        if count_phase(evs, unit) != phases0:
            raise Refused(f'검사 도중 {unit} 의 단계가 바뀌었다. 다시 돌린다')
        return 'check.result', unit, data

    transact(c, fn)
    what = f'{kind} 통과' if data['pass'] else f'{kind} 실패'
    tail = f' (증거 {data["evidence"]})' if data.get('evidence') else ''
    if not data['pass']:
        why = f'종료 코드 {data["exit"]}' if cmd else reason
        if kind == 'fail-first' and cmd:
            why += ', 명령이 실패해야 통과다' if started else ', 명령을 시작하지 못했다'
        raise Failed(f'{kind} {why}{tail}')
    print(f'OK: {unit} {what}{tail}')


def cmd_commit(c, rest):
    need(rest, 3)
    unit, repo, h = rest
    if not repo or not (h == NOCHANGE or re.fullmatch(r'[0-9a-fA-F]{7,40}', h)):
        raise Usage(f'해시는 16진수 7~40자 또는 {NOCHANGE} 이다')
    transact(c, lambda tbl, evs: (require_unit(tbl, unit, evs) and ('unit.commit', unit, {'repo': repo, 'hash': h})))
    print(f'OK: {unit} 커밋 기록 {repo} {h[:7] if h != NOCHANGE else h}')


def cmd_halt(c, rest):
    need(rest, 2)
    unit, val = rest
    if val not in HALTS and val != f'blocked:{unit}':
        raise Usage(f'멈춤 값은 {" ".join(HALTS)} blocked:{unit} 중 하나다')
    transact(c, lambda tbl, evs: (require_unit(tbl, unit, evs) and ('unit.halt', unit, {'reason': val})))
    print(f'OK: {unit} 멈춤 {val}')


def cmd_resume(c, rest):
    need(rest, 1)
    unit = rest[0]

    def fn(tbl, evs):
        require_unit(tbl, unit, evs)
        if not unit_state(evs, unit)['halt']:
            raise Refused(f'{unit} 은 멈춘 단위가 아니다')
        return 'unit.resume', unit, {}

    transact(c, fn)
    print(f'OK: {unit} 재개')


def cmd_show(c, rest):
    need(rest, 0)
    tbl, evs = transact(c, lambda tbl, evs: None)
    if tbl:
        print('| 단위 | 단계 | 멈춤 | 남은 증거 |')
        print('|---|---|---|---|')
        for row in tbl.rows:
            u = tbl.text(row, '단위')
            s = unit_state(evs, u)
            ph = known_phase(tbl, evs, u)
            rest_ev = ', '.join(remaining(tbl.grade(row), tbl.screen(row), ph, s)) or '-'
            print(f'| {u} | {PHASE_KO[ph]} | {halt_ko(s["halt"])} | {rest_ev} |')
    alls = load_events(c, every=True)
    opn = [mdrow([i, x['ask'].get('plan'), x['ask'].get('unit'), edata(x['ask']).get('question'), edata(x['ask']).get('recommend')])
           for i, x in decisions(alls).items() if not x['answer']]
    if opn:
        print('\n열린 결정\n| ID | 계획 | 단위 | 질문 | 추천 |\n|---|---|---|---|---|\n' + '\n'.join(opn))
    dirs = [mdrow([i, x['plan'], x['kind'], x['d'].get('text'), x['d'].get('terminal'), '적용됨' if x['applied'] else ''])
            for i, x in directives(alls).items() if x['active'] or not x['done']]
    if dirs:
        print('\n열린 지시\n| ID | 계획 | 종류 | 내용 | 터미널 | 적용 |\n|---|---|---|---|---|---|\n' + '\n'.join(dirs))


def cmd_ask(c, rest):
    need(rest, 1, exact=False)
    unit = rest[0]
    o = opts(rest[1:], ('--question', '--recommend', '--impact'), ('--option',))
    if not o.get('--question'):
        raise Usage('--question 이 필요하다')
    if c.hpath is None and unit != '-':
        raise Usage('폴더 모드의 ask 는 단위 - 만 된다')
    out = {}

    def fn(tbl, evs):
        if unit != '-':
            require_unit(tbl, unit, evs)
        did = out['id'] = next_id('D', decisions(load_events(c, every=True)))
        data = {'id': did, 'question': o['--question']}
        data.update({k[2:]: o[k] for k in ('--recommend', '--impact') if o.get(k)})
        data['options'] = o.get('--option', [])
        res = [('decision.ask', unit, data)]
        if unit != '-':
            res.append(('unit.halt', unit, {'reason': 'decision', 'decision': did}))
        return res

    transact(c, fn)
    print(f'OK: {out["id"]} 결정 요청' + (f' ({unit} 멈춤)' if unit != '-' else ''))


def cmd_answer(c, rest):
    need(rest, 1, exact=False)
    did = rest[0]
    o = opts(rest[1:], ('--answer', '--by', '--undo'))
    if not o.get('--answer'):
        raise Usage('--answer 가 필요하다')
    by = o.get('--by', 'user')
    if by not in DECIDERS:
        raise Usage(f'--by 는 {" ".join(DECIDERS)} 중 하나다')
    out = {}

    def fn(tbl, evs):
        alls = load_events(c, every=True)
        x = decisions(alls).get(did)
        if not x:
            raise Refused(f'없는 결정: {did}')
        if x['answer']:
            raise Refused(f'{did} 는 이미 답한 결정이다')
        plan, unit = x['ask'].get('plan'), x['ask'].get('unit')
        data = {'id': did, 'answer': o['--answer'], 'by': by}
        if o.get('--undo'):
            data['undo'] = o['--undo']
        res = [('decision.answer', unit, data, plan)]
        hd = unit_state([e for e in alls if e.get('plan') == plan], unit)['halt_d']
        if unit != '-' and hd.get('reason') == 'decision' and hd.get('decision') == did:
            res.append(('unit.resume', unit, {}, plan))
            out['unit'] = unit
        return res

    transact(c, fn)
    print(f'OK: {did} 답 기록' + (f' ({out["unit"]} 재개)' if out.get('unit') else ''))


def cmd_direct(c, rest):
    need(rest, 1, exact=False)
    kind = rest[0]
    if kind not in DIRECTIVES:
        raise Usage(f'지시는 {" ".join(DIRECTIVES)} 중 하나다')
    o = opts(rest[1:], ('--text', '--terminal'))
    if kind in ('message', 'reorder') and not o.get('--text'):
        raise Usage(f'{kind} 는 --text 가 필요하다')
    out = {}

    def fn(tbl, evs):
        alls = load_events(c, every=True)
        ds = directives(alls)
        iid = out['id'] = next_id('I', ds)
        data = {'id': iid, 'kind': kind}
        data.update({k[2:]: o[k] for k in ('--text', '--terminal') if o.get(k)})
        res = [('directive.received', '-', data)]
        if kind == 'resume':
            closes = [i for i, x in ds.items() if x['active'] and relevant(x, c.plan)]
            data['closes'] = out['closes'] = closes
            seen = set()
            for e in alls:  # 닫는 지시로 멈춘 단위를 푼다
                d = edata(e)
                key = (e.get('plan'), e.get('unit'))
                if e.get('type') != 'unit.halt' or d.get('directive') not in closes or key in seen:
                    continue
                seen.add(key)
                if unit_state([x for x in alls if x.get('plan') == key[0]], key[1])['halt_d'].get('directive') in closes:
                    res.append(('unit.resume', key[1], {}, key[0]))
        return res

    transact(c, fn)
    tail = f', 닫음: {", ".join(out["closes"])}' if out.get('closes') else ''
    print(f'OK: {out["id"]} 지시 접수 ({kind}{tail})')


def close_directive(c, rest, etype):
    need(rest, 1, exact=False)
    iid = rest[0]
    o = opts(rest[1:], ('--reason',))
    if etype == 'directive.rejected' and not o.get('--reason'):
        raise Usage('rejected 는 --reason 이 필요하다')

    def fn(tbl, evs):
        x = directives(load_events(c, every=True)).get(iid)
        if not x:
            raise Refused(f'없는 지시: {iid}')
        if etype == 'directive.rejected' and x['kind'] in ('stop-after', 'interrupt'):
            raise Refused(f'{iid} 는 정지·중단 지시라 거부할 수 없다. 사용자가 direct resume 으로 푼다')
        if x['done']:
            raise Refused(f'{iid} 는 이미 닫힌 지시다')
        data = {'id': iid}
        if o.get('--reason'):
            data['reason'] = o['--reason']
        return 'directive.' + etype.split('.')[1], '-', data, x['plan']

    transact(c, fn)
    print(f'OK: {iid} ' + ('적용' if etype == 'directive.applied' else '거부') + ' 기록')


def cmd_gate(c, rest):
    # 훅 JSON 을 읽고 열린 즉시 중단 지시가 있으면 막는다. 이벤트 파일이 없으면 .mmcode 를 만들지 않고 통과.
    need(rest, 0)
    if not os.path.isfile(c.events):
        return
    with open(3, encoding='utf-8', closefd=False) as f:
        j = json.loads(f.read())
    cmd = (j.get('tool_input') or {}).get('command') or ''
    if j.get('tool_name') == 'Bash' and 'phase.sh' in str(cmd):
        return
    me = os.environ.get('HC_TERMINAL_ID')
    with locked(c):
        hits = [x for x in directives(load_events(c, every=True)).values()
                if x['kind'] == 'interrupt' and x['active'] and relevant(x, c.plan)
                and (not x['d'].get('terminal') or x['d']['terminal'] == me)]
        for x in hits:
            if not x['applied']:
                append_event(c, 'directive.applied', '-', {'id': x['d']['id']}, x['plan'])
    if hits:
        ids = ', '.join(x['d']['id'] for x in hits)
        print(f'즉시 중단 지시 {ids} 가 열려 있다. 도구를 쓰지 말고 지금까지 한 일과 멈춘 지점을 사용자에게 보고한다. '
              f'계속하려면 사용자가 phase.sh direct <HANDOFF.md 또는 프로젝트 폴더> resume 을 실행한다.', file=sys.stderr)
        sys.exit(2)


CMDS = {'move': cmd_move, 'ready': cmd_ready, 'check': cmd_check, 'commit': cmd_commit, 'halt': cmd_halt, 'resume': cmd_resume, 'show': cmd_show,
        'ask': cmd_ask, 'answer': cmd_answer, 'direct': cmd_direct, 'gate': cmd_gate,
        'applied': lambda c, rest: close_directive(c, rest, 'directive.applied'),
        'rejected': lambda c, rest: close_directive(c, rest, 'directive.rejected')}

if sys.argv[1:2] == ['gate']:
    try:
        if len(sys.argv) < 3:
            raise Usage(USAGE)
        cmd_gate(Ctx(sys.argv[2]), sys.argv[3:])
    except Exception as e:  # 훅이 고장 나도 도구를 막지 않는다
        print(f'phase.sh gate: {e}', file=sys.stderr)
    sys.exit(0)
try:
    if len(sys.argv) < 3 or sys.argv[1] not in CMDS:
        raise Usage(USAGE)
    c = Ctx(sys.argv[2])
    if c.hpath is None and sys.argv[1] not in FOLDER_CMDS:
        raise Usage(f'폴더에는 {" ".join(FOLDER_CMDS)} 만 쓸 수 있다. 다른 명령은 HANDOFF.md 를 넘긴다')
    CMDS[sys.argv[1]](c, sys.argv[3:])
except Usage as e:
    print(e, file=sys.stderr)
    sys.exit(2)
except Refused as e:
    print(f'REFUSED: {e}')
    sys.exit(1)
except Failed as e:
    print(f'FAILED: {e}')
    sys.exit(1)
except Exception:
    traceback.print_exc()
    sys.exit(2)
PY
