#!/usr/bin/env bash
# relay auto 모드 도구: 완료 조건 검사·평가, 단위 워크트리 브랜치(시작·검사·커밋·ff 머지·정리·복구), goal/state.json 기록.
# 사용: eval-goal.sh <하위 명령> <HANDOFF.md> [인자...]   (인자 없이 부르면 하위 명령 목록이 나온다)
# 종료 코드: 0 성공 · 1 거부·blocked(stdout 마지막 줄 BLOCKED: <이유>) · 2 사용 오류 · 3 judge-fail
# unit <UNIT> recover 출력 한 단어: start(단위 시작부터) · worker(Worker부터) · review(검수 통과 상태, commit부터)
#                                   · merge(④ 머지부터) · cleanup(⑤ 정리부터) · done(할 일 없음)
# 쓰기 규칙: goal/.lock 을 잡고, 쓰기 직전에 state.json·인계 문서를 다시 읽어 이 호출이 바꾸는 키·줄만 고친다(rotate.sh 도 같은 잠금).
#            잠금은 그 짧은 구간에만 쥔다. git·조건 명령은 잠금 밖에서 돌린다(훅이 이 스크립트를 불러도 교착되지 않게).
#            다른 프로세스가 잠금을 RELAY_LOCK_WAIT 초(기본 30) 넘게 쥐면 기다리지 않고 BLOCKED 로 끝난다.
#            git·조건 명령을 돌리는 명령(init·run·clean·unit·fix·redeleg)은 goal/.driver 를 명령 내내 쥔다(한 계획에 하나만).
# 근거: references/DESIGN-auto.md 3~5·8절. 외부 의존 없음(bash + python3 + git). 파괴적 git 명령은 쓰지 않는다.
set -euo pipefail
command -v python3 >/dev/null 2>&1 || { echo "python3 이 없다" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git 이 없다" >&2; exit 2; }
exec python3 -I - "$@" <<'PY'
import contextlib, fcntl, fnmatch, json, os, re, shlex, shutil, subprocess, sys, tempfile, time, traceback
from datetime import datetime, timezone

USAGE = '''사용: eval-goal.sh <하위 명령> <HANDOFF.md> [인자...]
  check                                   완료 조건·경계·저장소·pathspec·자동 승인 검사
  init                                    check 통과 뒤 goal/state.json 생성
  run                                     조건 명령 평가(반복 +1)
  treekey <slug>                          작업 트리 키(기본 저장소는 계획 문서 제외)
  clean <slug> [--pathspec <경로>...]     공유 트리 전제 검사
  unit <UNIT> start|checkwt|commit -m <메시지>|merge|cleanup|recover|discard
  fix add <NAME> --key <키> --repo <slug> --files <경로,...> --summary <한 줄>
  redeleg <키> incr|get|reset
  stop <사유> · clear-stop · state get <키> · state set <키> <값> · status-json'''

NOCHANGE = '없음(변경 없음)'
STOPS = {'rotate', 'done', 'limit:iterations', 'limit:duration', 'expired', 'judge-fail', 'timeout-survivors',
         'scope', 'fix-cap', 'rotate-uncertain', 'rotate-failed', 'worker-alive'}
COLUMNS = ['단위', '내용', '파일', '선행', '모델', '병렬', '검수', 'pathspec', '가중치', '상태', '종료 시각', '커밋']
# 권위 관문 파일(DESIGN 5절): 무인 중에는 커밋하지 않는다
GATE = re.compile(r'(^|/)(\.claude/settings[^/]*$|\.env[^/]*$|\.git(/|$))')
META, GLOB = set(';|&`$()<>'), set('*?[')
ENVPFX = re.compile(r'[A-Za-z_][A-Za-z0-9_]*=')
# 문자열 안전망(DESIGN 4절). 스크립트 내부 동작은 보지 못한다. rm -r 은 인자 배열로 따로 본다
BANNED = [('curl', r'\bcurl\b'), ('wget', r'\bwget\b'), ('ssh', r'\bssh\b'), ('scp', r'\bscp\b'), ('sudo', r'\bsudo\b'),
          ('git push', r'\bgit\b.*\bpush\b')]
FIXNAME = re.compile(r'(.+?)-fix([0-9]+)(-[A-Za-z0-9._-]+)?')
DROP = object()
# 잠금(goal/.lock)은 state.json·인계 문서를 고치는 짧은 구간에만 쥔다. 쥔 채로 git·조건 명령을 돌리면 그 안의 훅이
# 이 스크립트를 다시 부를 때 교착되므로, 쥐고 있는지 표시해 두고 git 실행 전에 확인한다.
LOCK = {'held': False}
DRIVER = {'fd': None}  # goal/.driver 를 쥔 fd. git 자식에게 물려줘 부모가 죽어도 git 이 끝날 때까지 잠금이 유지된다
try:
    LOCK_WAIT = float(os.environ.get('RELAY_LOCK_WAIT') or 30)  # 다른 프로세스가 쥔 잠금을 기다리는 상한(초)
except ValueError:
    LOCK_WAIT = 30.0
UMASK = os.umask(0)
os.umask(UMASK)
# 훅 안에서 불려도 git 대상이 바뀌지 않게 저장소를 가리키는 환경 변수는 뺀다
GITENV = {k: v for k, v in os.environ.items()
          if k not in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_PREFIX')}


class Usage(Exception):
    pass


class Blocked(Exception):
    def __init__(self, msg, code=1):
        super().__init__(msg)
        self.code = code


class GitErr(Blocked):
    pass


class LogsErr(Exception):
    def __init__(self, msg, moved=()):
        super().__init__(msg)
        self.moved = list(moved)


def read(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


def write_atomic(path, text):
    # 임시 파일에 다 쓴 뒤 rename 한다. 중간에 끊겨도 반쯤 쓴 파일이 남지 않는다.
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    mode = os.stat(path).st_mode & 0o777 if os.path.exists(path) else 0o666 & ~UMASK
    fd, tmp = tempfile.mkstemp(dir=d, prefix='.tmp-')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def now_iso():
    return datetime.now().astimezone().isoformat(timespec='seconds')


def now_min():
    return datetime.now().strftime('%Y-%m-%d %H:%M')


def elapsed(st):
    t = datetime.fromisoformat(st['started_at'])
    return (datetime.now(timezone.utc) - (t if t.tzinfo else t.astimezone())).total_seconds()


def dur(v):
    # '30s'·'10m'·'4h' → 초. 단위 없는 숫자는 뜻이 모호해 받지 않는다.
    m = re.fullmatch(r'(\d+)\s*([smh])', (v or '').strip())
    return int(m.group(1)) * {'s': 1, 'm': 60, 'h': 3600}[m.group(2)] if m and int(m.group(1)) > 0 else None


def scan_quotes(s, hit):
    # shlex 규칙(따옴표·백슬래시)을 따라가며 따옴표 밖 문자에서 hit(ch) 가 참인 첫 위치. 없으면 None.
    q, esc = None, False
    for i, ch in enumerate(s):
        if esc:
            esc = False
        elif ch == '\\' and q != "'":
            esc = True
        elif q:
            q = None if ch == q else q
        elif ch in '"\'':
            q = ch
        elif hit(ch):
            return i
    return None


def nocomment(v):
    # 따옴표 밖 # 부터 줄 끝까지 주석이다(cmd: 줄의 shlex 규칙과 같다). 값의 따옴표는 그대로 둔다.
    i = scan_quotes(v, lambda ch: ch == '#')
    return (v if i is None else v[:i]).strip()


def qsplit(s, seps):
    # 따옴표 밖의 seps 문자로 나눈다
    parts = []
    while True:
        i = scan_quotes(s, lambda ch: ch in seps)
        if i is None:
            return parts + [s]
        parts.append(s[:i])
        s = s[i + 1:]


def split_paths(cell):
    # 경로 목록 → (경로들, 오류). 쉼표·세미콜론으로 나누고 항목마다 shlex 로 푼다(공백이 든 경로는 따옴표로).
    # 따옴표 없이 공백으로 이어진 항목은 한 경로인지 여러 경로인지 모호해 거부한다.
    items, errs = [], []
    for part in qsplit(cell, ',;'):
        part = part.strip()
        if len(part) > 1 and part[0] == part[-1] == '`':
            part = part[1:-1].strip()
        if part in ('', '—', '-'):
            continue
        try:
            toks = shlex.split(part)
        except ValueError as e:
            errs.append(f'따옴표 오류 {part}({e})')
            continue
        if len(toks) != 1:
            errs.append(f'모호한 경로 {part} — 공백이 든 경로는 따옴표로 감싸고, 여러 경로는 쉼표로 나눈다')
            continue
        items.append(toks[0])
    return items, errs


def join_paths(items):
    # split_paths 의 반대: 공백·구분자·따옴표·백슬래시가 든 항목만 따옴표로 감싼다
    return ', '.join(shlex.quote(x) if re.search(r'[\s,;\'"\\`]', x) else x for x in items)


def fmt(xs, n=8):
    xs = [str(x) for x in xs]
    return ', '.join(xs[:n]) + (f' 외 {len(xs) - n}개' if len(xs) > n else '')


def short(h):
    return (h or '?')[:7]


def git(repo, *args, inp=None, env=None, check=True):
    if LOCK['held']:
        raise RuntimeError('잠금(goal/.lock)을 쥔 채 git 을 돌리지 않는다 — 훅이 이 스크립트를 부르면 교착된다')
    kw = {'input': inp} if inp is not None else {'stdin': subprocess.DEVNULL}
    if DRIVER['fd'] is not None:  # 운전 잠금은 git 쓰기가 끝날 때까지 유지돼야 한다(부모가 먼저 죽어도)
        kw['pass_fds'] = (DRIVER['fd'],)
    r = subprocess.run(['git', '-c', 'core.quotePath=false', *args], cwd=repo, env=env or GITENV,
                       capture_output=True, encoding='utf-8', errors='surrogateescape', **kw)
    if check and r.returncode:
        raise GitErr(f'git {" ".join(args[:3])} 실패: {(r.stderr or r.stdout).strip()[-400:]}')
    return r


def out(repo, *args, **kw):
    return git(repo, *args, **kw).stdout


def errtail(r):
    return (r.stderr or r.stdout).strip()[-300:]


def rev(repo, ref):
    r = git(repo, 'rev-parse', '-q', '--verify', ref + '^{commit}', check=False)
    return r.stdout.strip() if r.returncode == 0 else None


def symref(repo):
    r = git(repo, 'symbolic-ref', '-q', 'HEAD', check=False)
    return r.stdout.strip() if r.returncode == 0 else None


def is_anc(repo, a, b):
    return git(repo, 'merge-base', '--is-ancestor', a, b, check=False).returncode == 0


def porcelain(text):
    # status --porcelain -z → 경로 목록. 이름 바꾸기 항목 뒤의 원래 경로 칸은 건너뛴다.
    ents, res, i = text.split('\0'), [], 0
    while i < len(ents):
        e = ents[i]
        i += 1
        if len(e) > 3:
            res.append(e[3:])
            if e[0] in 'RC':
                i += 1
    return res


def dirty(repo, paths, excl):
    # 경로들의 미커밋 변경(미추적 포함). excl(기본 저장소의 이 계획 문서 폴더)은 커밋 대상이 아니라 뺀다.
    if not paths:
        return []
    return porcelain(out(repo, 'status', '--porcelain', '-z', '-uall', '--', *paths, *([':!' + excl] if excl else [])))


def treekey(repo, excl):
    # 임시 인덱스로 지금 작업 트리의 트리 해시를 만든다. 공유 인덱스는 건드리지 않는다.
    # excl 이 무시 대상 폴더면 제외 pathspec 이 git add 를 exit 1 로 만든다(git 2.56 직접 확인). 그때는 빼지 않아도 안 올라간다.
    ign = bool(excl) and git(repo, 'check-ignore', '-q', '--', excl, check=False).returncode == 0
    with tempfile.TemporaryDirectory() as d:
        env = dict(GITENV, GIT_INDEX_FILE=os.path.join(d, 'index'))
        git(repo, 'read-tree', 'HEAD', env=env)
        git(repo, 'add', '-A', '--', '.', *([':!' + excl] if excl and not ign else []), env=env)
        if excl:
            git(repo, 'rm', '-r', '--cached', '-q', '--ignore-unmatch', '--', excl, env=env)
        return out(repo, 'write-tree', env=env).strip()


def covered(path, specs):
    # 경로가 pathspec(파일·폴더·글로브) 안에 드는지
    for s in specs:
        s = s.rstrip('/')
        if s in ('', '.') or path == s or path.startswith(s + '/') or (set(s) & GLOB and fnmatch.fnmatchcase(path, s)):
            return True
    return False


def rm_recursive(argv):
    # rm 이 재귀 삭제로 불리는지(인자 배열 기준). rm 뒤 '--' 전까지 모든 옵션에서 r·R·--recursive 를 찾는다
    for i, t in enumerate(argv):
        if os.path.basename(t) != 'rm':
            continue
        for o in argv[i + 1:]:
            if o == '--':
                break
            if o.startswith('--') and len(o) > 2 and '--recursive'.startswith(o):
                return True
            if o[:1] == '-' and o[:2] != '--' and set(o[1:]) & {'r', 'R'}:
                return True
    return False


def parse_cmd(raw, root):
    # cmd: 값 → (인자 배열, 거부 이유). 따옴표 밖 # 부터는 주석이다.
    try:
        argv = shlex.split(raw, comments=True)
    except ValueError as e:
        return [], [f'따옴표 오류({e})']
    if not argv:
        return [], ['빈 명령']
    probs, chars = [], set(''.join(argv))
    if chars & META:
        probs.append('셸 메타문자 ' + ' '.join(sorted(chars & META)))
    if chars & GLOB:
        probs.append('글로빙 문자 ' + ' '.join(sorted(chars & GLOB)))
    if ENVPFX.match(argv[0]):
        probs.append('환경변수 접두사')
    probs += [f'금지 패턴 {n}' for n, p in BANNED if re.search(p, ' '.join(argv))]
    if rm_recursive(argv):
        probs.append('금지 패턴 rm -r')
    w = argv[0]
    if '/' in w:  # ./x·/x 는 저장소 루트 기준 파일이어야 한다
        f = w if w.startswith('/') else os.path.join(root, w)
        if not os.path.isfile(f):
            probs.append(f'파일 없음: {w}')
        elif not os.access(f, os.X_OK):
            probs.append(f'실행 비트 없음: {w}')
    elif not ENVPFX.match(w) and not shutil.which(w):
        probs.append(f'명령을 찾지 못함: {w}')
    return argv, probs


def unfold(argv, root):
    # npm·yarn·pnpm·make 명령을 package.json scripts·Makefile 대상에서 한 단계 푼다. 못 풀면 None.
    tool, a = os.path.basename(argv[0]), argv[1:]
    if tool in ('npm', 'yarn', 'pnpm'):
        if a[:1] in (['run'], ['run-script']) and len(a) > 1:
            name, extra = a[1], a[2:]
        elif a[:1] in (['test'], ['t'], ['start']):
            name, extra = {'t': 'test'}.get(a[0], a[0]), a[1:]
        elif tool != 'npm' and a and not a[0].startswith('-'):
            name, extra = a[0], a[1:]
        else:
            return None
        try:
            line = json.loads(read(os.path.join(root, 'package.json'))).get('scripts', {}).get(name)
        except (OSError, ValueError, AttributeError):
            return None
        if not isinstance(line, str):
            return None
        extra = extra[1:] if extra[:1] == ['--'] else extra
        return ' '.join([line] + [shlex.quote(x) for x in extra])
    if tool != 'make' or len(a) > 1 or any(x.startswith('-') for x in a):
        return None
    mk = next((os.path.join(root, n) for n in ('GNUmakefile', 'makefile', 'Makefile')
               if os.path.isfile(os.path.join(root, n))), None)
    if not mk:
        return None
    lines, tgt, idx = read(mk).split('\n'), re.compile(r'([A-Za-z0-9_./-]+)\s*::?(?!=)'), None
    for i, l in enumerate(lines):  # 대상 줄. 변수 대입(:=)과 .PHONY 같은 특수 대상은 뺀다
        m = tgt.match(l)
        if m and not m.group(1).startswith('.') and (not a or m.group(1) == a[0]):
            idx = i
            break
    if idx is None:
        return None
    recipe = []
    for l in lines[idx + 1:]:
        if not l.startswith('\t'):
            break
        recipe.append(l.strip())
    return '; '.join(recipe) or None


def expiry(until):
    # 만료 조건 → ({events, at}, 오류). 닫힌 집합만 받는다: 계획 완료·중단·최대 반복·최대 시간(각각 뒤에 '도달' 가능)을
    # '·' 나 '또는'으로 이은 것, 또는 YYYY-MM-DD HH:MM(시간대 없음, 로컬 시각). 그 밖은 해석하지 못한 것으로 본다.
    u = until.strip()
    if re.fullmatch(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}', u):
        try:
            return {'events': [], 'at': datetime.strptime(u, '%Y-%m-%d %H:%M')}, None
        except ValueError:
            return None, f'만료 시각이 없는 날짜·시각이다: {u}'
    events = []
    for part in re.split(r'\s*(?:·|또는)\s*', u):
        m = re.fullmatch(r'(계획 완료|중단|최대 반복|최대 시간)(?:\s*도달)?', part)
        if not m:
            return None, (f'만료 조건을 해석하지 못했다: {u or "(빈 값)"} — 계획 완료·중단·최대 반복·최대 시간을 '
                          f'· 나 "또는"으로 잇거나 YYYY-MM-DD HH:MM 으로 쓴다')
        events.append(m.group(1))
    return {'events': events, 'at': None}, None


def approval(pol):
    # '자동 승인: <범위> / 만료: <조건>' 해석 → (판정 자료, 오류). 범위는 전부 · U1~U4 · U1,U3, 뒤에 '(보정 단위 포함)' 가능.
    m = re.fullmatch(r'\s*자동 승인:\s*(.*?)\s*/\s*만료:\s*(.*?)\s*', pol)
    if not m:
        return None, '"자동 승인: <범위> / 만료: <조건>" 형식이 아니다'
    scope, until = m.group(1), m.group(2)
    if not until:
        return None, '만료 조건이 비었다'
    ex, err = expiry(until)
    if err:
        return None, err
    spec = {'text': scope, 'until': until, 'expiry': ex, 'fix': False, 'all': False, 'names': None, 'range': None}
    f = re.fullmatch(r'(.*?)\s*\(보정 단위 포함\)', scope)
    if f:
        scope, spec['fix'] = f.group(1), True
    r = re.fullmatch(r'([A-Za-z]*)(\d+)\s*~\s*([A-Za-z]*)(\d+)', scope)
    if scope == '전부':
        spec['all'] = True
    elif r and r.group(1) == r.group(3) and int(r.group(2)) <= int(r.group(4)):
        spec['range'] = (r.group(1), int(r.group(2)), int(r.group(4)))
    elif re.fullmatch(r'[A-Za-z0-9._-]+(\s*,\s*[A-Za-z0-9._-]+)*', scope):
        spec['names'] = {x.strip() for x in scope.split(',')}
    else:
        return None, f'자동 승인 범위를 해석하지 못했다: {scope or "(빈 값)"} — 전부 · U1~U4 · U1,U3 중 하나'
    return spec, None


def approved(spec, unit):
    # 단위가 자동 승인 범위 안인지. 보정 단위는 '(보정 단위 포함)'이고 원래 단위가 범위 안일 때만이다.
    m = FIXNAME.fullmatch(unit)
    if m:
        return spec['fix'] and approved(dict(spec, fix=False), m.group(1))
    if spec['all']:
        return True
    if spec['names'] is not None:
        return unit in spec['names']
    pre, lo, hi = spec['range']
    n = re.fullmatch(re.escape(pre) + r'(\d+)', unit)
    return bool(n) and lo <= int(n.group(1)) <= hi


def cell_spans(line):
    # 표 한 줄 → 칸 경계 [(왼쪽 |, 오른쪽 |)]. \| 는 칸 구분이 아니다. 양 끝이 | 가 아니면 None.
    s = line.rstrip()
    bars = [i for i, ch in enumerate(s) if ch == '|' and (i == 0 or s[i - 1] != '\\')]
    if len(bars) < 2 or bars[0] != 0 or bars[-1] != len(s) - 1:
        return None
    return list(zip(bars, bars[1:]))


def cell_text(line, span):
    return line[span[0] + 1:span[1]].strip().replace('\\|', '|')


class Ctx:
    # 인계 문서 하나와 그 계획 폴더(docs/relay/<plan>/)
    def __init__(self, path):
        self.hpath = os.path.realpath(path)
        if not os.path.isfile(self.hpath):
            raise Usage(f'인계 문서 없음: {path}')
        self.pdir = os.path.dirname(self.hpath)
        self.plan = os.path.basename(self.pdir)
        self.goal = os.path.join(self.pdir, 'goal')
        self.spath = os.path.join(self.goal, 'state.json')
        self.lines = read(self.hpath).split('\n')
        self._lock = None
        r = git(self.pdir, 'rev-parse', '--show-toplevel', check=False)
        if r.returncode:
            raise Usage(f'인계 문서가 git 저장소 안에 없다: {path}')
        self.top = os.path.realpath(r.stdout.strip())
        self.prel = os.path.relpath(self.pdir, self.top)
        if self.prel == '.' or self.prel.startswith('..'):
            raise Usage('인계 문서는 저장소 루트가 아닌 계획 폴더(docs/relay/<plan>/)에 둔다')

    @contextlib.contextmanager
    def driving(self):
        # 계획 운전 잠금(goal/.driver). 상태를 바꾸는 명령(unit·run·stop…)은 한 계획에 한 번에 하나만 돈다. 두 프로세스의
        # 머지와 recover 가 서로의 예약을 지우는 것을 막는다(코드 검토 4라운드 재현). 훅이 부르는 state set 은 이 잠금을 안 잡는다.
        os.makedirs(self.goal, exist_ok=True)
        with open(os.path.join(self.goal, '.driver'), 'a') as f:
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise Blocked('다른 eval-goal 명령이 이 계획을 실행 중이다(goal/.driver) — 끝난 뒤 다시 한다')
            DRIVER['fd'] = f.fileno()
            try:
                yield
            finally:
                DRIVER['fd'] = None

    @contextlib.contextmanager
    def locked(self):
        # 계획 단위 잠금(goal/.lock). state.json·인계 문서의 읽기-고치기-쓰기 구간에만 쥔다(git·조건 명령은 잠금 밖).
        # 같은 프로세스 안에서 다시 잡으면 그대로 쓴다. 다른 프로세스가 LOCK_WAIT 초 넘게 쥐면 기다리지 않고 거부한다.
        if self._lock is not None:
            yield
            return
        os.makedirs(self.goal, exist_ok=True)
        with open(os.path.join(self.goal, '.lock'), 'a') as f:
            end = time.monotonic() + LOCK_WAIT
            while True:
                try:
                    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() > end:
                        raise Blocked(f'goal/.lock 을 {LOCK_WAIT:g}초 안에 얻지 못했다 — 다른 프로세스가 쥐고 있다. 그 프로세스가 끝난 뒤 다시 한다')
                    time.sleep(0.05)
            self._lock, LOCK['held'] = f, True
            try:
                yield
            finally:
                self._lock, LOCK['held'] = None, False

    def reload(self):
        self.lines = read(self.hpath).split('\n')

    def save(self):
        write_atomic(self.hpath, '\n'.join(self.lines))

    def edit(self, fn):
        # 잠근 채 인계 문서를 다시 읽고 fn 이 바꾼 줄만 반영해 쓴다. 다른 줄은 디스크의 최신 내용 그대로다.
        with self.locked():
            self.reload()
            r = fn()
            self.save()
            return r

    def state(self):
        if not os.path.isfile(self.spath):
            raise Usage(f'state.json 없음 — init 먼저: {self.spath}')
        with open(self.spath, encoding='utf-8') as f:
            return json.load(f)

    def update(self, fn):
        # 잠근 채 최신 state.json 을 읽어 fn 으로 고친 뒤 쓴다. 이 호출이 바꾸는 키만 바뀐다.
        with self.locked():
            st = self.state()
            r = fn(st)
            write_atomic(self.spath, json.dumps(st, ensure_ascii=False, indent=2) + '\n')
            return r

    def fence(self):
        # 재개 지시 절 첫 ``` 펜스의 (여는 줄, 닫는 줄) 번호
        L, s = self.lines, None
        h = next((i for i, l in enumerate(L) if re.match(r'##\s*재개 지시\s*$', l)), None)
        if h is None:
            raise Usage('인계 문서에 ## 재개 지시 절이 없다')
        for i in range(h + 1, len(L)):
            if L[i].startswith('## '):
                break
            if L[i].startswith('```'):
                if s is not None:
                    return s, i
                s = i
        raise Usage('재개 지시 절에 ``` 펜스가 없다')

    def cfg(self):
        # 재개 블록 → {top, cmds, timeout, bounds, repos, errs}. 들여쓴 줄은 바로 위 블록의 항목이다.
        s, e = self.fence()
        c, sec = {'top': {}, 'cmds': [], 'timeout': None, 'bounds': {}, 'repos': [], 'errs': []}, None
        for raw in self.lines[s + 1:e]:
            if not raw.strip() or raw.strip().startswith('#'):  # 빈 줄·# 주석 줄은 건너뛴다. 블록도 끊지 않는다
                continue
            k, sep, v = raw.strip().partition(':')
            k, v = k.strip(), v.strip()
            if raw[0] in ' \t':
                if sec == '완료 조건' and k == 'cmd':
                    c['cmds'].append(v)
                elif sec == '완료 조건' and k == 'timeout':
                    c['timeout'] = nocomment(v)
                elif sec == '경계' and k in ('최대 반복', '최대 시간', 'Worker 제한'):
                    c['bounds'][k] = nocomment(v)
                elif sec:
                    c['errs'].append(f'{sec} 블록의 알 수 없는 줄: {raw.strip()}')
                continue
            sec = k if k in ('완료 조건', '경계') and not nocomment(v) else None
            if sec:
                continue
            if k == '저장소':
                c['repos'].append(nocomment(v))
            elif sep:
                c['top'].setdefault(k, nocomment(v) if k == '모드' else v)
        return c

    def set_line(self, key, value):
        # 재개 블록의 '<key>: <value>' 줄을 바꾸거나 블록 끝(닫는 펜스 앞)에 더한다. value 가 None 이면 지운다.
        # 줄 맨 앞(공백만 허용)에서 찾는다. rotate.sh 의 '중단:' 줄 규칙과 같다.
        def fn():
            s, e = self.fence()
            i = next((i for i in range(s + 1, e) if re.match(r'\s*' + re.escape(key) + ':', self.lines[i])), None)
            if value is None:
                if i is not None:
                    del self.lines[i]
            elif i is None:
                self.lines.insert(e, f'{key}: {value}')
            else:
                self.lines[i] = re.match(r'\s*', self.lines[i]).group(0) + f'{key}: {value}'
        self.edit(fn)

    def table(self):
        # 상태표 → (머리글, [[줄 번호, {열: 값}, 칸 경계]], 표 마지막 줄 번호, 오류). 칸 안의 | 는 \| 로 쓴다.
        L = self.lines
        h = next((i for i, l in enumerate(L) if re.match(r'##\s*상태표\s*$', l)), None)
        if h is None:
            raise Usage('인계 문서에 ## 상태표 절이 없다')
        head, rows, last, errs = None, [], None, []
        for i in range(h + 1, len(L)):
            if L[i].startswith('## '):
                break
            if not L[i].startswith('|'):
                if head:
                    break
                continue
            sp, last = cell_spans(L[i]), i
            if sp is None:
                errs.append(f'{i + 1}번째 줄: 표 줄은 | 로 시작하고 | 로 끝나야 한다')
                continue
            vals = [cell_text(L[i], x) for x in sp]
            if head is None:
                head = vals
                if len(head) != len(COLUMNS) or set(head) != set(COLUMNS):
                    errs.append(f'상태표 머리글은 12열({" | ".join(COLUMNS)})이어야 한다')
            elif not set(''.join(vals)) <= set('-: '):
                if len(vals) != len(head):
                    errs.append(f'{i + 1}번째 줄: 칸 {len(vals)}개 ≠ 머리글 {len(head)}개(칸 안의 | 는 \\| 로 쓴다)')
                else:
                    rows.append([i, dict(zip(head, vals)), sp])
        if head is None:
            raise Usage('상태표가 없다')
        return head, rows, last, errs

    def rows(self):
        # 모호하지 않은 상태표만 쓴다. 모호하면 읽지도 쓰지도 않는다
        head, rows, last, errs = self.table()
        if errs:
            raise Usage('상태표가 모호하다 — ' + '; '.join(errs))
        return head, rows, last

    def row(self, unit):
        r = next((r for _, r, _ in self.rows()[1] if r.get('단위') == unit), None)
        if r is None:
            raise Usage(f'상태표에 단위 {unit} 이 없다')
        return r

    def set_row(self, unit, vals):
        # 그 단위 행에서 지정한 칸만 바꾼다. 다른 칸의 원문(이스케이프 포함)은 그대로 둔다.
        def fn():
            head, rows, _ = self.rows()
            for i, r, sp in rows:
                if r.get('단위') == unit:
                    line = self.lines[i]
                    for idx in sorted((head.index(name) for name in vals), reverse=True):  # 뒤 칸부터 바꿔 앞 칸 위치를 지킨다
                        a, b = sp[idx]
                        line = line[:a + 1] + ' ' + vals[head[idx]].replace('|', '\\|') + ' ' + line[b:]
                    self.lines[i] = line
                    return
            raise Usage(f'상태표에 단위 {unit} 이 없다')
        self.edit(fn)

    def add_row(self, vals):
        # 상태표 끝에 행을 더한다. 칸 안의 | 는 \| 로 쓴다
        def fn():
            head, _, last = self.rows()
            self.lines.insert(last + 1, '| ' + ' | '.join(vals.get(h, '').replace('|', '\\|') for h in head) + ' |')
        self.edit(fn)

    def repos(self):
        # ({slug: 경로}, 기본 slug, 오류). 기본 저장소 = 인계 문서가 속한 저장소(조건 명령도 여기서 돈다).
        repos, errs = {}, []
        for v in self.cfg()['repos']:
            m = re.fullmatch(r'([A-Za-z0-9._-]+)=(/.*)', v)
            if not m:
                errs.append(f'저장소 줄 형식은 <slug>=<절대경로>: {v}')
            elif m.group(1) in repos:
                errs.append(f'저장소 slug 중복: {m.group(1)}')
            else:
                repos[m.group(1)] = os.path.realpath(m.group(2))
        default = next((s for s, p in repos.items() if p == self.top), None)
        if default is None:
            default = os.path.basename(self.top)
            if default in repos:
                errs.append(f'기본 저장소 slug {default} 가 다른 저장소와 겹친다')
            else:
                repos[default] = self.top
        return repos, default, errs

    def excl(self, repo):
        # 계획 폴더 제외는 인계 문서가 든 기본 저장소에만 쓴다. 보조 저장소의 같은 경로는 실제 작업 파일이다
        return self.prel if os.path.realpath(repo) == self.top else None

    def units(self):
        # 상태표 → ({단위: (slug, [경로])}, 저장소별 합집합 {slug: [경로]}, 오류)
        repos, default, _ = self.repos()
        _, rows, _, errs = self.table()
        units, union, errs = {}, {}, list(errs)
        for _, r, _ in rows:
            u = r.get('단위', '')
            if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', u) or '..' in u or u.endswith('.lock') or u in units:
                errs.append(f'단위 이름이 비었거나 중복이거나 브랜치 이름으로 못 쓴다: {u!r}')
                continue
            items, perrs = split_paths(r.get('pathspec', ''))
            errs += [f'단위 {u}: {e}' for e in perrs]
            specs = {}
            for it in items:
                m = re.fullmatch(r'([A-Za-z0-9._-]+):(.+)', it)
                slug, p = (m.group(1), m.group(2)) if m else (default, it)
                if slug not in repos:
                    errs.append(f'단위 {u}: 모르는 저장소 {slug}')
                elif p.startswith((':', '/')) or '..' in p.split('/'):
                    errs.append(f'단위 {u}: 쓸 수 없는 경로 {p}')
                else:
                    specs.setdefault(slug, []).append(p)
            if len(specs) > 1:
                errs.append(f'단위 {u}: 저장소 {len(specs)}개({", ".join(specs)}) — 단위를 저장소별로 나눈다')
            elif not specs and r.get('상태') != '완료' and not perrs:
                errs.append(f'단위 {u}: pathspec 이 비었다')
            for s, ps in specs.items():
                union.setdefault(s, []).extend(ps)
            units[u] = next(iter(specs.items()), (default, []))
        return units, union, errs

    def strict(self):
        # check 밖 하위 명령용: 저장소·상태표에 오류가 있으면 멈춘다
        errs = self.repos()[2]
        units, union, uerrs = self.units()
        if errs + uerrs:
            raise Usage('저장소·상태표 오류: ' + '; '.join(errs + uerrs))
        return units, union

    def bounds(self, n_units):
        # 경계 블록 → ({max_iterations, max_duration, worker_timeout}, [(이름, 키, 원문, 값)]). 값이 None 이면 잘못된 값.
        # 줄이 없으면 기본값(단위 수×2·4h·30m).
        b = self.cfg()['bounds']
        v = b.get('최대 반복')
        items = [('최대 반복', 'max_iterations', v, (int(v) if v.isdigit() and int(v) > 0 else None) if v else max(1, n_units * 2)),
                 ('최대 시간', 'max_duration', b.get('최대 시간'), dur(b['최대 시간']) if b.get('최대 시간') else 4 * 3600),
                 ('Worker 제한', 'worker_timeout', b.get('Worker 제한'), dur(b['Worker 제한']) if b.get('Worker 제한') else 30 * 60)]
        return {k: val for _, k, _, val in items}, items


def put(c, st, path, value):
    # 스냅샷 st 와 state.json 에 같은 값을 넣는다(DROP 이면 지운다). 파일은 잠근 채 다시 읽어 그 키만 바꾼다.
    def setp(d):
        for k in path[:-1]:
            d = d.setdefault(k, {})
        if value is DROP:
            d.pop(path[-1], None)
        else:
            d[path[-1]] = value
    setp(st)
    c.update(setp)


def branch(c, u):
    return f'relay/{c.plan}/{u}'


def wtpath(c, u):
    return os.path.join(c.pdir, u, 'wt')


def key_for(st, u):
    # 재위임 키: 보정 단위는 등록한 완료 기준 키, 그 밖은 단위 이름
    return next((f['key'] for f in st.get('fix_units', []) if f['unit'] == u), u)


def new_unit(c, st, u, slug, base):
    return {'repo': slug, 'base_head': base, 'branch': branch(c, u), 'wt': wtpath(c, u), 'stage': 'started',
            'commit': '', 'worker': {}, 'key': key_for(st, u)}


def stop(c, reason):
    # 중단 기록은 stopped_reason 하나로 모은다. rotate·done 은 중단: 줄을 쓰지 않고 남은 줄도 지운다(DESIGN 9단계).
    with c.locked():
        if reason.startswith('blocked:'):
            c.set_row(reason[8:], {'상태': 'blocked'})
        c.update(lambda s: s.__setitem__('stopped_reason', reason))
        c.set_line('중단', None if reason in ('rotate', 'done') else reason)


def block(c, u, msg):
    # 단위 실행 중 멈춤: 행 blocked · stopped_reason blocked:<단위> · 중단: 줄
    stop(c, f'blocked:{u}')
    raise Blocked(f'{u} {msg}')


def shared_probs(c, R, base, paths):
    # 공유 트리 전제: 대상 브랜치에 있다 · HEAD 가 기대한 tip(머지 땐 base_head) · 계획 경로가 깨끗하다
    repo, p = R['path'], []
    ref, head = symref(repo), rev(repo, 'HEAD')
    if ref != R['target_ref']:
        p.append(f'HEAD 가 대상 브랜치 {R["target_ref"]} 를 가리키지 않는다({ref or "분리 HEAD"})')
    if head != R['expected_tip']:
        p.append(f'HEAD {short(head)} ≠ expected_tip {short(R["expected_tip"])}(외부 커밋)')
    elif base and head != base:
        p.append(f'HEAD {short(head)} ≠ base_head {short(base)}')
    d = dirty(repo, paths, c.excl(repo))
    if d:
        p.append(f'계획 경로 미커밋 변경 {fmt(d)}')
    return p


def worktrees(repo):
    # git worktree list --porcelain → [(경로, 체크아웃한 브랜치 ref 또는 None(분리·bare), HEAD OID)]
    res, cur = [], {}
    for l in out(repo, 'worktree', 'list', '--porcelain').split('\n') + ['']:
        if l:
            k, _, v = l.partition(' ')
            cur[k] = v
        elif cur:
            res.append((cur.get('worktree', ''), cur.get('branch'), cur.get('HEAD')))
            cur = {}
    return res


def wt_listed(repo, wt):
    real = os.path.realpath(wt)
    return any(os.path.realpath(p) == real for p, _, _ in worktrees(repo))


def wt_check(u, R):
    # 워크트리 정체성: 등록된 이 단위의 워크트리이고 이 단위 브랜치에 있는지. 아니면 이유를 돌려준다.
    # 워크트리가 아니면 git 이 상위 저장소로 풀려 공유 인덱스를 건드리므로, 워크트리에서 무엇을 하기 전에 본다.
    wt, repo = u['wt'], R['path']
    if os.path.islink(wt) or os.path.realpath(wt) != os.path.abspath(wt):
        return '워크트리 경로에 심볼릭 링크가 있다'
    if not os.path.isdir(wt):
        return '워크트리 폴더가 없다'
    if not wt_listed(repo, wt):
        return '등록된 워크트리가 아니다'
    top = git(wt, 'rev-parse', '--show-toplevel', check=False)
    if top.returncode or os.path.realpath(top.stdout.strip()) != os.path.realpath(wt):
        return '워크트리 최상위가 다르다(다른 저장소로 풀린다)'
    common = [git(d, 'rev-parse', '--path-format=absolute', '--git-common-dir', check=False) for d in (wt, repo)]
    if any(x.returncode for x in common) or len({os.path.realpath(x.stdout.strip()) for x in common}) != 1:
        return 'git common dir 이 저장소와 다르다'
    ref = git(wt, 'symbolic-ref', '-q', 'HEAD', check=False).stdout.strip()
    if ref != 'refs/heads/' + u['branch']:
        return f'워크트리가 {u["branch"]} 브랜치에 있지 않다({ref or "분리 HEAD"})'
    return None


def wt_ready(c, U, u, R):
    why = wt_check(u, R)
    if why:
        block(c, U, f'워크트리 정체성 — {why}(워크트리·공유 인덱스는 건드리지 않았다)')


def wt_scan(u, specs):
    # Worker 가 올린 인덱스를 비우고 워크트리 변경을 본다. .relay-logs/ 는 커밋 대상이 아니라 뺀다.
    wt = u['wt']
    git(wt, 'reset', '-q', 'HEAD')
    allc = [p for p in porcelain(out(wt, 'status', '--porcelain', '-z', '-uall')) if p.split('/')[0] != '.relay-logs']
    # pathspec 이 비면 git status -- 가 전부를 돌려주므로 '안'을 빈 집합으로 둔다
    inside = set(porcelain(out(wt, 'status', '--porcelain', '-z', '-uall', '--', *specs))) if specs else set()
    return allc, [p for p in allc if p not in inside], [p for p in allc if GATE.search(p)]


def scan_or_block(c, U, u, specs):
    allc, outside, gate = wt_scan(u, specs)
    why = ([f'pathspec 밖 {fmt(outside)}'] if outside else []) + ([f'권위 관문 {fmt(gate)}'] if gate else [])
    if why:
        block(c, U, '워크트리 변경 — ' + ' · '.join(why) + ' (워크트리는 그대로 둔다)')
    return allc


def stage_files(wt, files):
    # 검사한 파일만 올린다. 파일 이름의 * ? [ 가 패턴으로 풀리지 않게 literal 로 넘긴다.
    if files:
        git(wt, '--literal-pathspecs', 'add', '-A', '--pathspec-from-file=-', '--pathspec-file-nul', inp='\0'.join(files))


def commit_probs(repo, base, cm, specs):
    # 커밋 전체(base..cm) 변경 파일 검사: pathspec 밖·권위 관문·.relay-logs. 이미 만든 커밋도 같은 기준으로 본다.
    def names(*extra):
        return [x for x in out(repo, 'diff', '--name-only', '--no-renames', '-z', base, cm, *extra).split('\0') if x]
    allc = names()
    inside = set(names('--', *specs)) if specs else set()
    outside = [x for x in allc if x not in inside or x.split('/')[0] == '.relay-logs']
    gate = [x for x in allc if GATE.search(x)]
    return ([f'커밋에 pathspec 밖 파일 {fmt(outside)}'] if outside else []) + ([f'커밋에 권위 관문 파일 {fmt(gate)}'] if gate else [])


def adoptable(repo, u, tip):
    # 기록 전에 끊긴 이 세션의 커밋인지: commit 이 남긴 의도(stage committing·committed)가 있고 base 바로 위 커밋 하나다
    return u.get('stage') in ('committing', 'committed') and rev(repo, tip + '^') == u['base_head']


def ignored(repo, files):
    # 들어올 새 파일 자리에 이미 있는 무시 파일(머지가 덮어쓰거나 거부한다)
    res = []
    for i in range(0, len(files), 100):
        res += [x for x in out(repo, '--literal-pathspecs', 'ls-files', '-z', '-o', '-i', '--exclude-standard',
                               '--', *files[i:i + 100]).split('\0') if x]
    return res


def ref_snapshot(repo):
    # 머지 전후 비교용: ({브랜치 ref: OID}, HEAD 가 가리키는 ref(분리면 None), HEAD OID)
    refs = {}
    for l in out(repo, 'for-each-ref', '--format=%(objectname) %(refname)', 'refs/heads').splitlines():
        oid, _, name = l.partition(' ')
        refs[name] = oid
    return refs, symref(repo), rev(repo, 'HEAD')


def all_refs(repo):
    # 모든 ref(브랜치·태그·그 밖. HEAD 가 refs/heads 밖 ref 를 가리킨 채 ff 되는 경우까지 잡는다): {ref: oid}
    refs = {}
    for l in out(repo, 'for-each-ref', '--format=%(objectname) %(refname)').splitlines():
        oid, _, name = l.partition(' ')
        refs[name] = oid
    return refs


def contains(repo, cm):
    # cm 을 포함하는 ref 목록(한 번의 git 호출). 조회가 실패하면(cm 부재·저장소 오류) 빈 결과로 바꾸지 않고 멈춘다 —
    # '포함하는 ref 없음' 으로 읽으면 잘못 전진한 ref 를 놓치고 예약을 지운다(코드 검토 6라운드 재현)
    r = git(repo, 'for-each-ref', '--format=%(refname)', '--contains', cm, check=False)
    if r.returncode:
        raise Blocked(f'git for-each-ref --contains {short(cm)} 실패 — 판정하지 않는다(예약·기록 그대로): {errtail(r)}')
    return r.stdout.split()


def misapplied(repo, before, cm, target_ref, unit_ref):
    # ff 전 스냅샷(before: refs {ref: oid}, heads {워크트리: 분리 HEAD oid})과 비교해 cm 을 '새로' 포함하게 된 대상 외 ref 와
    # 분리 HEAD. 후속 커밋이 붙어 tip ≠ cm 이어도 잡는다. 스냅샷 oid 가 그대로이거나 그 oid 가 이미 cm 을 품고 있던 것
    # (사용자가 미리 만든 백업과 그 백업의 독립 전진)은 빼준다
    def new(old, cur):
        return old != cur and not (old and is_anc(repo, cm, old))
    now = all_refs(repo)
    moved = sorted(r for r in contains(repo, cm) if r not in (target_ref, unit_ref) and new(before['refs'].get(r), now.get(r)))
    detached = sorted(p for p, b, h in worktrees(repo) if not b and h and is_anc(repo, cm, h) and new(before['heads'].get(p), h))
    return moved, detached


def snapshot(repo):
    return {'refs': all_refs(repo), 'heads': {p: h for p, b, h in worktrees(repo) if not b and h}}


def undo_ff(c, st, U, repo, base, cm, before, target_ref):
    # 머지가 대상 브랜치가 아닌 곳을 전진시켰을 때. 어떤 ref 도 자동으로 되돌리지 않고 작업 트리·인덱스도 건드리지 않는다:
    # 확인과 update-ref 사이에 누가 그 브랜치를 체크아웃하면 그 작업 트리가 어긋난다(코드 검토 3라운드 재현).
    # 무엇이 어디로 전진했는지 ff_misapplied 에 적고 사람이 정리한다.
    moved, detached = misapplied(repo, before, cm, target_ref, 'refs/heads/' + st['units'][U]['branch'])
    why = f'{fmt(moved + detached) or "알 수 없는 ref"} 가 {short(cm)} 를 포함하게 됐다(자동으로 되돌리지 않는다)'
    put(c, st, ('units', U, 'ff_misapplied'), {'ref': moved, 'detached': detached, 'base': base, 'cm': cm, 'why': why})
    return (f'아무것도 바꾸지 않았다 — {why}. 남의 브랜치(또는 HEAD)가 이 단위 커밋 {short(cm)} 로 전진해 있다. '
            f'사람이 확인해 git reset·git switch 로 정리한 뒤 state 의 units.{U}.ff_misapplied 를 지운다')


def move_logs(c, U, wt, report):
    # Worker 로그(<wt>/.relay-logs/)를 단위 폴더로 옮긴다. report 면 REPORT.md 는 단위 폴더에, 나머지는 logs/ 에.
    # 링크를 따라 워크트리 밖 파일을 옮기지 않게, 원본·목적지·그 부모에 심볼릭 링크가 있으면 아무것도 옮기지 않는다.
    # 이미 있는 파일은 덮어쓰지 않고 확장자 앞에 번호를 붙인다(REPORT.1.md).
    src, udir = os.path.join(wt, '.relay-logs'), os.path.join(c.pdir, U)
    if not os.path.lexists(src):
        return []
    for p in (wt, src, udir, os.path.join(udir, 'logs')):
        if os.path.lexists(p) and (os.path.islink(p) or os.path.realpath(p) != os.path.abspath(p)):
            raise LogsErr(f'{p} 에 심볼릭 링크가 있다 — 옮기지 않는다')
    if not os.path.isdir(src):
        raise LogsErr(f'{src} 가 폴더가 아니다 — 옮기지 않는다')
    moved = []
    try:
        for name in sorted(os.listdir(src)):
            d = udir if report and name == 'REPORT.md' else os.path.join(udir, 'logs')
            os.makedirs(d, exist_ok=True)
            base, ext = os.path.splitext(os.path.join(d, name))
            t, n = base + ext, 1
            while os.path.lexists(t):
                t, n = f'{base}.{n}{ext}', n + 1
            os.rename(os.path.join(src, name), t)
            moved.append(t)
        os.rmdir(src)
    except OSError as e:
        raise LogsErr(f'옮기다 멈췄다({e})', moved)
    return moved


def expired(c, U, st):
    # 자동 승인 만료(실패 폐쇄): 정책·만료 조건을 해석하지 못하거나, 만료 시각이 지났거나, 적힌 사건(최대 반복·최대 시간)에
    # 닿았거나, 이 단위가 승인 범위 밖이다. 계획 완료·중단은 stopped_reason 이 차 있어 이 검사 전에 커밋을 막는다.
    spec, err = approval(c.cfg()['top'].get('커밋 정책', ''))
    if err:
        return f'커밋 정책 — {err}'
    ex = spec['expiry']
    if ex['at'] and datetime.now() > ex['at']:
        return f'만료 시각 {spec["until"]} 지남'
    if '최대 반복' in ex['events'] and st.get('iterations', 0) >= st.get('max_iterations', 0):
        return '만료 조건 최대 반복 도달'
    if '최대 시간' in ex['events'] and elapsed(st) > st.get('max_duration', 0):
        return '만료 조건 최대 시간 도달'
    if not approved(spec, U):
        return f'{U} 는 자동 승인 범위({spec["text"]}) 밖이다'
    return None


def do_check(c):
    # 항목마다 PASS/FAIL 한 줄을 찍고 거부 수를 돌려준다
    bad = [0]

    def say(ok, msg):
        print(('PASS ' if ok else 'FAIL ') + msg)
        bad[0] += not ok

    cfg = c.cfg()
    for e in cfg['errs']:
        say(False, e)
    repos, default, errs = c.repos()
    for e in errs:
        say(False, e)
    for s, p in repos.items():
        r = git(p, 'rev-parse', '--show-toplevel', check=False) if os.path.isdir(p) else None
        ok = bool(r) and r.returncode == 0 and os.path.realpath(r.stdout.strip()) == p
        say(ok, f'저장소 {s}={p}' + (' (기본)' if s == default else '') + ('' if ok else ' — git 저장소 최상위가 아니다'))
    root = repos.get(default, c.top)
    say(bool(cfg['cmds']), '완료 조건 ' + (f'cmd: {len(cfg["cmds"])}줄' if cfg['cmds'] else '— cmd: 줄이 없다'))
    for i, raw in enumerate(cfg['cmds'], 1):
        argv, probs = parse_cmd(raw, root)
        say(not probs, f'cmd {i}: {raw} ' + ('— ' + ', '.join(probs) if probs else '→ argv ' + json.dumps(argv, ensure_ascii=False)))
        if argv and os.path.basename(argv[0]) in ('npm', 'yarn', 'pnpm', 'make'):
            print(f'     → {unfold(argv, root) or "(해석 불가)"}')
    t = cfg['timeout']
    say(not t or dur(t) is not None, f'timeout: {t or "10m(기본값)"}' + ('' if not t or dur(t) else ' — <숫자>s|m|h 형식이어야 한다'))
    units, union, uerrs = c.units()
    mode, pol = cfg['top'].get('모드', ''), cfg['top'].get('커밋 정책', '')
    if mode == 'auto':
        spec, err = approval(pol)
        if err:
            say(False, f'커밋 정책: {pol or "(없음)"} — {err}')
        else:
            miss = [u for u in units if not approved(spec, u)]
            note = ([] if spec['fix'] else ['"(보정 단위 포함)" 이 없다(auto 는 보정 단위까지 미리 승인받는다)']) + \
                   ([f'범위 밖 단위 {", ".join(miss)}'] if miss else [])
            say(not note, f'커밋 정책: 자동 승인 {spec["text"]} / 만료 {spec["until"]}' + (' — ' + '; '.join(note) if note else ''))
    else:
        print(f'INFO 모드: {mode or "(없음)"} — auto 가 아니라 커밋 정책을 보지 않는다')
    for name, _, raw, val in c.bounds(len(units))[1]:
        unit = '' if name == '최대 반복' else '초'
        say(val is not None, f'경계 {name}: {raw or "(기본값)"} ' + (f'→ {val}{unit}' if val is not None
                                                                   else '— 최대 반복은 양의 정수, 시간은 <숫자>s|m|h'))
    for e in uerrs:
        say(False, e)
    ref_ok = git(c.top, 'check-ref-format', f'refs/heads/relay/{c.plan}/x', check=False).returncode == 0
    say(ref_ok, f'계획 이름 {c.plan}' + ('' if ref_ok else ' — 브랜치 이름(relay/<plan>/<unit>)으로 못 쓴다'))
    if not uerrs:
        say(True, f'단위 {len(units)}개 · ' + ' · '.join(f'{s}: {fmt(ps, 5)}' for s, ps in union.items()))
    return bad[0]


def cmd_check(c, rest):
    if rest:
        raise Usage(USAGE)
    n = do_check(c)
    if n:
        raise Blocked(f'check 거부 {n}건')
    print('OK: check')


def cmd_init(c, rest):
    if rest:
        raise Usage(USAGE)
    if c.cfg()['top'].get('모드') != 'auto':
        raise Blocked('모드: auto 가 아니다 — auto 계획만 init 한다')
    n = do_check(c)
    if n:
        raise Blocked(f'check 거부 {n}건')
    if os.path.exists(c.spath):
        raise Blocked(f'state.json 이 이미 있다(이어 하려면 resume): {c.spath}')
    repos = c.repos()[0]
    units, union = c.strict()
    b = c.bounds(len(units))[0]
    st_repos, probs = {}, []
    for s, p in repos.items():
        ref, head = symref(p), rev(p, 'HEAD')
        if not ref:
            probs.append(f'{s}: 분리 HEAD — 브랜치에서 시작한다')
        if not head:
            probs.append(f'{s}: 커밋이 없다')
        d = dirty(p, union.get(s, []), c.excl(p)) if head else []
        if d:
            probs.append(f'{s}: 계획 경로 미커밋 변경 {fmt(d)} — 사용자가 먼저 정리한다')
        st_repos[s] = {'path': p, 'init_head': head, 'expected_tip': head, 'target_ref': ref}
    if probs:
        raise Blocked('; '.join(probs))
    with c.locked():
        if os.path.exists(c.spath):
            raise Blocked(f'state.json 이 이미 있다(이어 하려면 resume): {c.spath}')
        write_atomic(c.spath, json.dumps(dict(started_at=now_iso(), iterations=0, last_eval=None, fix_units=[],
                                              redelegations={}, integration={}, repos=st_repos, units={},
                                              stopped_reason='', **b), ensure_ascii=False, indent=2) + '\n')
    for u, (s, _) in units.items():
        if c.row(u).get('상태') != '완료':
            print(f'자산 {u}: 워크트리 {wtpath(c, u)} · 브랜치 {branch(c, u)} ({s}) — 머지·깨끗할 때만 지운다')
    print(f'OK: init {c.spath}')


def cmd_treekey(c, rest):
    repos = c.repos()[0]
    if len(rest) != 1 or rest[0] not in repos:
        raise Usage(f'사용: treekey <HANDOFF.md> <slug>  (slug: {", ".join(repos)})')
    print(treekey(repos[rest[0]], c.excl(repos[rest[0]])))


def group_left(pgid):
    # 프로세스 묶음 pgid 에 남은 프로세스: 번호 목록([] = 없음), 있는데 번호를 못 얻으면 None(모름).
    # 있는지는 신호 0 으로 본다(아무 신호도 보내지 않는 존재 확인이라 무엇도 끝내지 않는다). 그래서 남은 게 없으면 ps 없이 판정한다.
    # 번호는 ps 의 묶음 번호(pgid)로만 찾는다. 이름은 쓰지 않는다.
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return []
    except PermissionError:
        pass  # 있지만 신호 권한이 없다
    try:
        r = subprocess.run(['ps', '-A', '-o', 'pid=,pgid='], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    except OSError:
        return None
    if r.returncode:
        return None
    return [int(f[0]) for f in (line.split() for line in r.stdout.splitlines())
            if len(f) == 2 and f[1] == str(pgid) and f[0] != str(pgid)]


def run_one(argv, cwd, tsec):
    # 셸 없이 인자 배열로 실행한다. 새 세션으로 띄워 이 실행의 프로세스 묶음(pgid)을 구분한다.
    # 제한 시간을 넘기면 직접 띄운 프로세스 하나만 끝낸다. 묶음에 남은 프로세스는 끝내지 않고 번호만 돌려준다(전역 규칙).
    if LOCK['held']:
        raise RuntimeError('잠금(goal/.lock)을 쥔 채 조건 명령을 돌리지 않는다')
    with tempfile.TemporaryFile() as f:
        try:
            p = subprocess.Popen(argv, cwd=cwd, stdin=subprocess.DEVNULL, stdout=f, stderr=subprocess.STDOUT,
                                 start_new_session=True)
        except FileNotFoundError:
            return 127, False, f'{argv[0]}: 명령을 찾지 못함', []
        except OSError as e:
            return 126, False, f'{argv[0]}: 실행 불가({e})', []
        left = []
        try:
            code, timed = p.wait(timeout=tsec), False
        except subprocess.TimeoutExpired:
            p.terminate()
            timed = True
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()
            code, left = p.returncode, group_left(p.pid)
        f.seek(0)
        return code, timed, f.read().decode('utf-8', 'replace'), left


def cmd_run(c, rest):
    if rest:
        raise Usage(USAGE)
    st0, cfg = c.state(), c.cfg()
    repos, default, errs = c.repos()
    if errs:
        raise Usage('; '.join(errs))
    root, cmds = repos[default], cfg['cmds']
    if not cmds:
        raise Blocked('완료 조건에 cmd: 줄이 없다')
    parsed = []
    for raw in cmds:  # 인계 문서가 바뀌었을 수 있어 실행 전마다 다시 검사한다
        argv, probs = parse_cmd(raw, root)
        if probs:
            raise Blocked(f'cmd 검사 실패 — {raw}: {", ".join(probs)}')
        parsed.append((raw, argv))
    tsec = dur(cfg['timeout']) if cfg['timeout'] else 600
    if tsec is None:
        raise Blocked(f'timeout 값이 잘못됐다: {cfg["timeout"]}')
    undone = sum(1 for _, r, _ in c.rows()[1] if r.get('상태') != '완료')

    def bump(s):
        s['iterations'] = s.get('iterations', 0) + 1
        return s['iterations']
    it = c.update(bump)  # 평가 중 끊겨도 반복 수는 남긴다
    keys = {s: treekey(p, c.excl(p)) for s, p in sorted(repos.items())}
    le = st0.get('last_eval') or {}
    # 미완료 단위가 0개면 완료 보고로 갈 수 있는 평가라 재사용하지 않는다
    reuse = undone > 0 and le.get('tree_keys') == keys and le.get('cmds') == cmds
    log, halt = [f'# 반복 {it} · {now_iso()} · 미완료 단위 {undone} · 작업 디렉터리 {root}'], None
    if reuse:
        results = le['results']
        log.append(f'반복 {le.get("iteration")} 결과 재사용 (이전 실행 · 그 뒤 변경 없음)')
    else:
        results = []
        for raw, argv in parsed:
            code, timed, text, left = run_one(argv, root, tsec)
            res = {'cmd': raw, 'exit': code, 'timeout': timed}
            log += [f'$ {raw}', f'exit: {code}' + (f' (제한 시간 {tsec}초 초과 — 직접 띄운 프로세스를 끝냄)' if timed else '')]
            log += text.splitlines()[-50:] + ['']
            if timed and left != []:  # 남은 프로세스가 공유 트리에 계속 쓸 수 있다. 끝내지 않고 멈춘다
                res['survivors'] = left
                log.append('제한 시간 뒤 남은 프로세스(끝내지 않았다): ' + (fmt(left, 20) if left is not None else '확인 못 함(ps 실패)'))
                results.append(res)
                halt = ('timeout-survivors', raw, left)
                break
            results.append(res)
            if code in (126, 127):  # 판정 명령 자체의 오류: 뒤 명령은 돌리지 않는다
                halt = ('judge-fail', raw, code)
                break
        log += [f'$ {raw}\n(실행 안 함 — 앞 명령에서 멈춤)' for raw, _ in parsed[len(results):]]
    passed = sum(1 for r in results if r['exit'] == 0 and not r.get('timeout'))
    failed, at = len(cmds) - passed, now_iso()
    complete, at_min = undone == 0 and failed == 0 and not halt, at[:16].replace('T', ' ')
    # 기록 순서: 로그 → eval.md → 인계 문서 한 줄 → state.last_eval. state 가 마지막이라 중간에 끊기면 다음 평가가 새로 돈다
    write_atomic(os.path.join(c.goal, f'{it}.log'), '\n'.join(log) + '\n')
    tag = ' · (이전 실행 · 그 뒤 변경 없음)' if reuse else ''
    verdict = halt[0] if halt else ('완료' if complete else '미완료')
    with c.locked():
        ev = os.path.join(c.goal, 'eval.md')
        prev = read(ev) if os.path.lexists(ev) else ''
        write_atomic(ev, prev + f'- 반복 {it} · {at_min} · 통과 {passed}/{len(cmds)} · 미완료 단위 {undone} · {verdict}{tag} · {it}.log\n')
    c.set_line('최근 조건 평가', f'{it} {at_min} 통과 {passed} 실패 {failed}{" (재사용)" if reuse else ""} → goal/eval.md')
    new = {'iteration': it, 'at': at, 'cmds': cmds, 'results': results, 'reused': reuse,
           'tree_keys': None if halt else keys, 'complete': complete, 'unfinished': undone}
    if reuse:
        new['reused_from'] = le.get('iteration')
    c.update(lambda s: s.__setitem__('last_eval', new))
    for r in results:
        print(f'exit {r["exit"]}{" (timeout)" if r.get("timeout") else ""} · {r["cmd"]}')
    if reuse:
        print('(이전 실행 · 그 뒤 변경 없음)')
    if halt:
        stop(c, halt[0])
        if halt[0] == 'judge-fail':
            raise Blocked(f'judge-fail — {halt[1]} exit {halt[2]}(판정 명령 자체의 오류)', 3)
        raise Blocked(f'timeout-survivors — {halt[1]} 제한 시간 뒤 남은 프로세스 '
                      f'{fmt(halt[2], 20) if halt[2] is not None else "(확인 못 함)"} — 끝내지 않았다. 사람이 확인한다')
    print('DONE: complete' if complete else f'DONE: incomplete(units={undone},failed={failed})')


def cmd_clean(c, rest):
    st = c.state()
    units, union = c.strict()
    if not rest or rest[0] not in st['repos'] or (rest[1:] and (rest[1] != '--pathspec' or len(rest) < 3)):
        raise Usage(f'사용: clean <HANDOFF.md> <slug> [--pathspec <경로>...]  (slug: {", ".join(st["repos"])})')
    paths = rest[2:] or union.get(rest[0], [])
    probs = shared_probs(c, st['repos'][rest[0]], None, paths)
    if probs:
        raise Blocked(f'{rest[0]}: ' + '; '.join(probs))
    print(f'OK: clean {rest[0]}')


IDENT = ('repo', 'base_head', 'branch', 'wt')


def same_unit(s, cur, u, R):
    # 잠금을 풀었다 다시 잡은 뒤, 그 사이 단위의 정체(저장소·base·브랜치·워크트리)와 저장소 설정(경로·대상 브랜치)이
    # 바뀌지 않았는지. 바뀌었으면 옛 git 결과를 새 설정에 적지 않는다
    rp = (s.get('repos') or {}).get(u.get('repo')) or {}
    return all(cur.get(k) == u.get(k) for k in IDENT) and rp.get('path') == R['path'] and rp.get('target_ref') == R['target_ref']


def need_unit(st, U):
    u = st['units'].get(U)
    if not u:
        raise Usage(f'{U} 는 시작 기록이 없다 — start 또는 recover')
    return u


def u_start(c, st, U, slug, specs, union, R, args):
    if c.row(U).get('상태') == '완료':
        raise Usage(f'{U} 는 이미 완료다')
    if (st['units'].get(U) or {}).get('commit'):
        raise Usage(f'{U} 에 커밋 기록이 있다 — recover 로 이어 한다')
    repo, br, wt = R['path'], branch(c, U), wtpath(c, U)
    if rev(repo, 'refs/heads/' + br) or os.path.lexists(wt):
        raise Usage(f'{U}: 브랜치나 워크트리가 이미 있다 — recover 또는 discard')
    udir = os.path.dirname(wt)
    if os.path.lexists(udir) and (os.path.islink(udir) or os.path.realpath(udir) != os.path.abspath(udir)):
        block(c, U, f'단위 폴더 {udir} 가 심볼릭 링크다 — 워크트리를 만들지 않는다')
    probs = shared_probs(c, R, None, union)
    if probs:
        block(c, U, '시작 검사 — ' + '; '.join(probs))
    base = R['expected_tip']
    c.set_row(U, {'상태': '진행'})
    git(repo, 'worktree', 'add', '-q', '-b', br, wt, base)
    put(c, st, ('units', U), new_unit(c, st, U, slug, base))
    print(f'OK: start {U} wt={wt} branch={br} base={short(base)}')


def u_checkwt(c, st, U, slug, specs, union, R, args):
    u = need_unit(st, U)
    wt_ready(c, U, u, R)
    files = scan_or_block(c, U, u, specs)
    stage_files(u['wt'], files)
    sys.stdout.write(out(u['wt'], 'diff', '--cached', '--stat', 'HEAD'))
    print(f'OK: checkwt {U} 파일 {len(files)}개')


def u_commit(c, st, U, slug, specs, union, R, args):
    if len(args) != 2 or args[0] != '-m' or not args[1].strip():
        raise Usage('사용: unit <HANDOFF.md> <UNIT> commit -m <메시지>')
    u = need_unit(st, U)
    if u.get('stage') not in ('started', 'reviewed', 'committing') or u.get('commit'):
        raise Usage(f'{U}: stage {u.get("stage")} · commit {u.get("commit") or "-"} — 커밋할 단계가 아니다')
    # ① 재검사: 중단 상태 · 최대 시간 · 자동 승인(만료·범위) · 워크트리 정체성 · pathspec · 권위 관문
    if st.get('stopped_reason'):
        raise Blocked(f'중단 상태({st["stopped_reason"]}) — 커밋하지 않는다')
    if elapsed(st) > st['max_duration']:
        stop(c, 'limit:duration')
        raise Blocked('limit:duration — 최대 시간을 넘겼다(행은 진행, stage 는 그대로)')
    why = expired(c, U, st)
    if why:
        stop(c, 'expired')
        raise Blocked(f'expired — {why}')
    wt_ready(c, U, u, R)
    head = rev(u['wt'], 'HEAD')
    if head != u['base_head']:
        if u.get('stage') == 'committing' and rev(u['wt'], 'HEAD^') == u['base_head']:
            raise Usage(f'{U}: 커밋이 이미 있다(기록 전에 끊김) — recover 로 이어 한다')
        block(c, U, f'워크트리 HEAD {short(head)} ≠ base_head {short(u["base_head"])} — 이 세션이 만들지 않은 커밋이 있다')
    files = scan_or_block(c, U, u, specs)
    stage_files(u['wt'], files)  # ②
    rc = git(u['wt'], 'diff', '--cached', '--quiet', check=False).returncode
    if rc not in (0, 1):
        raise GitErr('git diff --cached 실패')
    if rc == 0:  # ③ 검증된 무변경 단위: 기록은 ④ 통과 뒤에 한다
        print('NOCHANGE')
        return
    def intent(s):  # 잠근 채 최신 상태로 다시 확인하고 커밋 의도를 남긴다. 복구는 이 표시가 있는 커밋만 받는다
        cur = s['units'].get(U) or {}
        if s.get('stopped_reason') or cur.get('commit') or cur.get('stage') not in ('started', 'reviewed', 'committing') or not same_unit(s, cur, u, R):
            raise Blocked(f'{U}: 그 사이 상태가 바뀌었다(stage {cur.get("stage")}, 중단 {s.get("stopped_reason") or "-"}) — 커밋하지 않는다')
        cur['stage'] = 'committing'
    c.update(intent)
    git(u['wt'], 'commit', '-q', '-m', args[1])  # 잠금 밖: 훅이 이 스크립트를 불러도 막히지 않는다
    cm = rev(u['wt'], 'HEAD')
    if not cm or rev(u['wt'], cm + '^') != u['base_head']:  # 훅이 커밋을 더 만들었으면 기록하지 않는다(복구가 출처 불명으로 멈춘다)
        raise Blocked(f'{U}: 커밋 결과 {short(cm)} 가 base_head 바로 위가 아니다 — 기록하지 않는다. recover 로 확인한다')

    def record(s):  # 다시 잠그고 최신 상태를 확인한 뒤 결과를 적는다
        cur = s['units'].get(U) or {}
        if cur.get('stage') != 'committing' or cur.get('commit') or not same_unit(s, cur, u, R):
            raise Blocked(f'{U}: 커밋 뒤 상태가 바뀌었다(stage {cur.get("stage")}) — 기록하지 않는다. recover 로 확인한다')
        cur['commit'], cur['stage'] = cm, 'committed'
    c.update(record)
    sys.stdout.write(out(u['wt'], 'show', '--stat', '--format=%h %an %s', 'HEAD'))
    print(f'OK: commit {U} {short(cm)}')


def u_merge(c, st, U, slug, specs, union, R, args):
    u = need_unit(st, U)
    if u.get('ff_misapplied'):
        raise Blocked(f'{U}: 되돌리지 못한 머지 기록(ff_misapplied)이 있다 — 사람이 확인한다')
    repo, base, cm = R['path'], u['base_head'], u.get('commit') or ''
    if cm == NOCHANGE or u.get('stage') in ('merged', 'cleaned'):
        raise Usage(f'{U} 는 이미 머지됐다 — cleanup')
    if u.get('stage') == 'merging':
        raise Usage(f'{U}: 머지 중에 끊겼다 — recover 로 확인한다')
    tip = rev(repo, 'refs/heads/' + u['branch'])
    if not tip:
        raise Usage(f'{U}: 브랜치 {u["branch"]} 가 없다 — recover')
    if not cm and tip != base:  # 기록 전에 끊긴 이 세션의 커밋만 받는다
        if not adoptable(repo, u, tip):
            block(c, U, f'출처 불명 커밋 {short(tip)} — commit 하위 명령이 만든 커밋이 아니다(stage {u.get("stage")})')
        put(c, st, ('units', U, 'commit'), tip)
        put(c, st, ('units', U, 'stage'), 'committed')
        cm = tip
    if not cm:
        wt_ready(c, U, u, R)
        if wt_scan(u, specs)[0]:
            raise Usage(f'{U}: 워크트리에 커밋하지 않은 변경이 있다 — commit 먼저')
    # ④ 공유 트리 검사(무변경 단위도 같다)와 커밋 전체 검사
    probs = shared_probs(c, R, base, union)
    if cm:
        probs += commit_probs(repo, base, cm, specs)
        added = [x for x in out(repo, 'diff', '--name-only', '-z', '--diff-filter=A', base, cm).split('\0') if x]
        ign = ignored(repo, added) if added else []
        if ign:
            probs.append(f'들어올 새 파일과 겹치는 무시 파일 {fmt(ign)}')
    if probs:
        block(c, U, '머지 전 검사 — ' + '; '.join(probs))
    if not cm:
        def nochange(s):  # 잠근 채 그 사이 커밋 기록이 생기지 않았는지 확인하고 무변경 완료를 적는다
            cur = s['units'].get(U) or {}
            if cur.get('commit') or not same_unit(s, cur, u, R):
                raise Blocked(f'{U}: 그 사이 상태가 바뀌었다 — 무변경으로 적지 않는다. recover 로 확인한다')
            cur['commit'], cur['stage'] = NOCHANGE, 'merged'
        c.update(nochange)
        c.set_row(U, {'상태': '완료', '종료 시각': now_min(), '커밋': NOCHANGE})
        print(f'OK: merge {U} {NOCHANGE}')
        return
    def reserve(s):  # 잠근 채 머지 의도를 남긴다. ff 뒤 기록에 실패해도 recover 가 이 표시로 미확정 머지를 알아본다
        cur = s['units'].get(U) or {}
        if s.get('stopped_reason') or cur.get('commit') != cm or cur.get('stage') != 'committed' or cur.get('ff_misapplied') or not same_unit(s, cur, u, R):
            raise Blocked(f'{U}: 그 사이 상태가 바뀌었다(stage {cur.get("stage")}, 중단 {s.get("stopped_reason") or "-"}) — 머지하지 않는다')
        cur['stage'], cur['merge_intent'] = 'merging', {'path': R['path'], 'target_ref': R['target_ref'], 'base': base, 'cm': cm, 'before': before}
    before = snapshot(repo)  # ff 전 ref·분리 HEAD 스냅샷. 예약에 넣어 recover 도 같은 기준으로 비교한다
    c.update(reserve)
    r = git(repo, 'merge', '--ff-only', '--no-autostash', '--no-overwrite-ignore', '-q', cm, check=False)
    if r.returncode:
        def unreserve(s):  # ff 가 거부됐으니 이 예약을 거둔다(아무것도 바뀌지 않았다)
            cur = s['units'].get(U) or {}
            if cur.get('stage') == 'merging' and (cur.get('merge_intent') or {}).get('cm') == cm:
                cur['stage'] = 'committed'
                cur.pop('merge_intent', None)
        c.update(unreserve)
        block(c, U, '--ff-only 머지 거부(공유 트리 무변경, 워크트리 커밋 보존) — ' + errtail(r))
    # 머지 뒤 재검증: 대상 브랜치가 이 커밋이면 성공이다(그 사이 HEAD 가 다른 브랜치로 옮겨졌어도)
    if rev(repo, R['target_ref']) != cm:
        note = undo_ff(c, st, U, repo, base, cm, before, R['target_ref'])
        block(c, U, f'머지 뒤 재검증 실패(대상 {R["target_ref"]} 가 {short(cm)} 가 아니다) — {note}')
    def record(s):  # 다시 잠그고 최신 상태가 이 커밋을 가리키는지 확인한 뒤 결과를 적는다
        cur = s['units'].get(U) or {}
        if cur.get('commit') != cm or cur.get('stage') != 'merging' or not same_unit(s, cur, u, R):
            raise Blocked(f'{U}: 머지 뒤 상태가 바뀌었다(commit {short(cur.get("commit"))}, stage {cur.get("stage")}) — 기록하지 않는다. recover 로 확인한다')
        cur['stage'] = 'merged'
        cur.pop('merge_intent', None)
        s['repos'][slug]['expected_tip'] = cm
    c.update(record)
    c.set_row(U, {'상태': '완료', '종료 시각': now_min(), '커밋': f'{slug} {short(cm)}'})
    if symref(repo) != R['target_ref']:
        print(f'주의: 머지 뒤 HEAD 가 {R["target_ref"]} 가 아니다 — 다음 단위 시작 검사가 멈춘다')
    print(f'OK: merge {U} {slug} {short(cm)}')


def u_cleanup(c, st, U, slug, specs, union, R, args):
    u = need_unit(st, U)
    repo, cm = R['path'], u.get('commit') or ''
    if u.get('stage') == 'merging':  # 머지 기록이 끝나지 않았다(expected_tip 미갱신). recover 가 확정한다
        raise Usage(f'{U}: 머지 중에 끊겼다 — recover 로 확인한다')
    # 완료 확정은 대상 브랜치 기준이다. HEAD 가 다른 브랜치면 자산을 지우지 않는다
    if symref(repo) != R['target_ref']:
        raise Blocked(f'{U}: HEAD 가 대상 브랜치 {R["target_ref"]} 가 아니다 — 정리하지 않는다')
    if not (cm == NOCHANGE or (cm and is_anc(repo, cm, R['target_ref']))):
        raise Usage(f'{U}: 대상 브랜치에 머지되지 않았다 — merge 먼저')
    try:
        moved = move_logs(c, U, u['wt'], True)
    except LogsErr as e:
        put(c, st, ('units', U, 'logs_error'), {'msg': str(e), 'moved': e.moved})
        raise Blocked(f'{U}: 로그를 옮기지 않았다(stage 그대로, 이월에 적는다) — {e}')
    for t in moved:
        print(f'옮김: {os.path.relpath(t, c.pdir)}')
    for what, args2 in (('워크트리 제거', ('worktree', 'remove', u['wt'])), ('브랜치 삭제', ('branch', '-d', u['branch']))):
        if what == '워크트리 제거' and not wt_listed(repo, u['wt']):
            continue
        if what == '브랜치 삭제' and not rev(repo, 'refs/heads/' + u['branch']):
            continue
        r = git(repo, *args2, check=False)
        if r.returncode:  # 강제 삭제는 하지 않는다. 남은 자산은 이월에 적는다
            put(c, st, ('units', U, 'stage'), 'merged')
            raise Blocked(f'{U}: {what} 실패(stage merged 유지) — {errtail(r)}')
    put(c, st, ('units', U, 'stage'), 'cleaned')
    print(f'OK: cleanup {U}')


def u_recover(c, st, U, slug, specs, union, R, args):
    # 복구 분기(DESIGN 3절 4단계): stage 는 참고값이고 git 실제 상태로 다음 할 일을 정한다
    repo, row, u = R['path'], c.row(U), st['units'].get(U)
    if u and u.get('ff_misapplied'):
        raise Blocked(f'{U}: 되돌리지 못한 머지 기록(ff_misapplied)이 있다 — 사람이 확인한다')
    tip = rev(repo, 'refs/heads/' + branch(c, U))
    if u is None:
        if not tip:
            print('done' if row.get('상태') == '완료' else 'start')
            return
        # 워크트리 브랜치를 만든 직후·기록 전에 끊긴 경우: 만든 시점의 HEAD 는 expected_tip 이었다
        u = new_unit(c, st, U, slug, R['expected_tip'])
        put(c, st, ('units', U), u)
    if u.get('stage') == 'merging' and u.get('merge_intent'):
        # ff 뒤 기록에 실패한(잠금을 못 얻은) 머지. 예약의 대상 브랜치에 들어갔으면 머지된 단위, 예약 스냅샷과 비교해
        # 대상 외 ref·분리 HEAD 가 이 커밋을 새로 포함하게 됐으면 잘못 전진한 머지(ff_misapplied), 둘 다 아니면
        # ff 가 되기 전에 끊긴 것이다. 대상 브랜치 설정이 예약과 다르면 판정하지 않는다.
        mi, cmx = u['merge_intent'], u['merge_intent']['cm']
        if mi.get('target_ref') != R['target_ref'] or mi.get('path') != R['path']:
            raise Blocked(f'{U}: 저장소 설정(경로·대상 브랜치)이 머지 예약({mi.get("path")} {mi.get("target_ref")})과 다르다'
                          f'({R["path"]} {R["target_ref"]}) — 예약을 그대로 두고 사람이 확인한다')
        if not mi.get('before'):
            raise Blocked(f'{U}: 머지 예약에 ff 전 스냅샷이 없다 — 판정하지 않는다. 사람이 확인한 뒤 units.{U}.merge_intent 를 지우고 stage 를 committed 로 고친다')
        others, det = misapplied(repo, mi['before'], cmx, R['target_ref'], 'refs/heads/' + u['branch'])
        if is_anc(repo, cmx, R['target_ref']):
            pass  # 대상에 들어갔다: 예약은 아래 완료 확정(finish)이 같은 갱신에서 지운다(그때까지 보존)
        elif others or det:
            put(c, st, ('units', U, 'ff_misapplied'), {'ref': others, 'detached': det, 'base': mi['base'], 'cm': cmx,
                                                      'why': '머지 중 끊긴 뒤 대상 브랜치가 아닌 곳이 이 커밋을 포함하게 됐다'})
            block(c, U, f'미확정 머지 — {fmt(others + det)} 가 {short(cmx)} 를 포함한다. 사람이 git reset·git switch 로 정리한 뒤 units.{U}.ff_misapplied 를 지운다')
        else:
            def settle(s):  # ff 전에 끊긴 예약만 거둔다(한 번의 갱신). 그 사이 설정·정체가 바뀌었으면 예약을 둔다
                cur = s['units'].get(U) or {}
                if cur.get('stage') != 'merging' or (cur.get('merge_intent') or {}).get('cm') != cmx or not same_unit(s, cur, u, R):
                    raise Blocked(f'{U}: 그 사이 머지 예약이나 저장소 설정이 바뀌었다 — 예약을 그대로 두고 다시 recover')
                cur['stage'] = 'committed'
                cur.pop('merge_intent', None)
            c.update(settle)
            u['stage'] = 'committed'
            u.pop('merge_intent', None)
    if tip and tip != u['base_head'] and not u.get('commit'):
        if not adoptable(repo, u, tip):  # 이 세션이 커밋 의도를 남기지 않은 커밋은 받지 않는다
            block(c, U, f'출처 불명 커밋 {short(tip)} — commit 하위 명령이 만든 커밋이 아니다(stage {u.get("stage")})')
        put(c, st, ('units', U, 'commit'), tip)
        put(c, st, ('units', U, 'stage'), 'committed')
    cm = u.get('commit') or ''
    if cm and cm != NOCHANGE:
        probs = commit_probs(repo, u['base_head'], cm, specs)
        if probs:
            block(c, U, '복구 검사 — ' + '; '.join(probs))
    if cm == NOCHANGE or (cm and is_anc(repo, cm, R['target_ref'])):
        # 대상 브랜치에 들어간 단위: HEAD 가 대상 브랜치일 때만 완료를 확정하고 정리로 간다
        if symref(repo) != R['target_ref']:
            raise Blocked(f'{U}: HEAD 가 대상 브랜치 {R["target_ref"]} 가 아니다 — 완료 확정·정리를 하지 않는다')
        left = bool(tip) or wt_listed(repo, u['wt']) or os.path.lexists(u['wt'])
        def finish(s):  # 완료 확정은 한 번의 갱신으로, 그 사이 설정·정체·예약이 그대로일 때만(머지 예약도 여기서 지운다)
            cur = s['units'].get(U) or {}
            if cur.get('commit') != cm or not same_unit(s, cur, u, R) or (cur.get('merge_intent') or {}) != (u.get('merge_intent') or {}):
                raise Blocked(f'{U}: 그 사이 단위·저장소 설정·머지 예약이 바뀌었다 — 완료를 적지 않는다(예약 그대로). 다시 recover')
            if cm != NOCHANGE and s['repos'][slug].get('expected_tip') == u['base_head']:
                s['repos'][slug]['expected_tip'] = cm
            cur['stage'] = 'merged' if left else 'cleaned'
            cur.pop('merge_intent', None)
        c.update(finish)
        if row.get('상태') != '완료':
            c.set_row(U, {'상태': '완료', '종료 시각': now_min(), '커밋': NOCHANGE if cm == NOCHANGE else f'{slug} {short(cm)}'})
        print('cleanup' if left else 'done')
        return
    if tip and tip != u['base_head']:
        word = 'merge'
    elif tip:
        word = 'review' if u.get('stage') in ('reviewed', 'committing') else 'worker'
    elif cm:
        raise Blocked(f'{U}: 커밋 {short(cm)} 이 대상 브랜치에 없고 단위 브랜치도 없다 — 사람이 확인한다')
    else:
        word = 'start'
    print(word)


def u_discard(c, st, U, slug, specs, union, R, args):
    # 사용자가 blocked 행을 미착수로 되돌린 단위: 자산을 치우고 처음부터 하게 한다(브랜치는 이름만 바꿔 보존)
    if c.row(U).get('상태') != '미착수':
        raise Usage(f'{U}: 행이 미착수가 아니다 — 사용자가 되돌린 단위만 discard 한다')
    repo, br, u = R['path'], branch(c, U), st['units'].get(U) or {}
    wt = u.get('wt') or wtpath(c, U)
    try:  # 버린 시도의 REPORT.md 도 logs/ 로 보낸다. 단위 폴더의 REPORT.md 자리는 다시 하는 시도 몫이다
        moved = move_logs(c, U, wt, False)
    except LogsErr as e:
        if U in st['units']:
            put(c, st, ('units', U, 'logs_error'), {'msg': str(e), 'moved': e.moved})
        block(c, U, f'로그를 옮기지 않았다 — {e}')
    for t in moved:
        print(f'옮김: {os.path.relpath(t, c.pdir)}')
    if wt_listed(repo, wt):
        r = git(repo, 'worktree', 'remove', wt, check=False)
        if r.returncode:
            block(c, U, f'워크트리 제거 실패 — 사용자가 직접 정리한다: {errtail(r)}')
    new = None
    if rev(repo, 'refs/heads/' + br):
        n = 1
        while rev(repo, f'refs/heads/{br}.discarded-{n}'):
            n += 1
        new = f'{br}.discarded-{n}'
        git(repo, 'branch', '-m', br, new)
    key = u.get('key') or key_for(st, U)
    c.update(lambda s: (s['units'].pop(U, None), s.setdefault('redelegations', {}).pop(key, None)))
    print(f'OK: discard {U}' + (f' 브랜치 → {new}' if new else ''))


UNIT_OPS = {'start': u_start, 'checkwt': u_checkwt, 'commit': u_commit, 'merge': u_merge,
            'cleanup': u_cleanup, 'recover': u_recover, 'discard': u_discard}


def cmd_unit(c, rest):
    if len(rest) < 2 or rest[1] not in UNIT_OPS or (rest[2:] and rest[1] != 'commit'):
        raise Usage(USAGE)
    U, op = rest[0], rest[1]
    # 잠금은 state.json·인계 문서를 고치는 순간에만 잡는다(put·set_row·stop). git 은 잠금 밖에서 돌려 훅과 교착되지 않게 한다
    st = c.state()
    units, union = c.strict()
    if U not in units:
        raise Usage(f'상태표에 단위 {U} 이 없다')
    slug, specs = units[U]
    if slug not in st['repos']:
        raise Usage(f'state.json 에 저장소 {slug} 가 없다')
    UNIT_OPS[op](c, st, U, slug, specs, union.get(slug, []), st['repos'][slug], rest[2:])


def opts(args, names):
    o, it = {}, iter(args)
    for a in it:
        if a not in names:
            raise Usage(f'모르는 옵션: {a}')
        v = next(it, None)
        if v is None:
            raise Usage(f'{a} 값이 없다')
        o[a] = v
    miss = [n for n in names if n not in o]
    if miss:
        raise Usage('빠진 옵션: ' + ' '.join(miss))
    return o


def cmd_fix(c, rest):
    if len(rest) < 2 or rest[0] != 'add':
        raise Usage(USAGE)
    name, o = rest[1], opts(rest[2:], ('--key', '--repo', '--files', '--summary'))
    c.state()
    with c.locked():
        c.reload()
        st = c.state()
        units, union = c.strict()
        m = FIXNAME.fullmatch(name)
        if not m or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name):
            raise Usage('보정 단위 이름은 U<마지막 원래 단위>-fix<회차>[-<저장소 slug>]')
        rnd, top = int(m.group(2)), max([f['round'] for f in st.get('fix_units', [])] or [0])
        if rnd > 2:  # 보정은 계획당 2회차까지(DESIGN 3절 7단계)
            stop(c, 'fix-cap')
            raise Blocked(f'fix-cap — 보정은 2회차까지다({name})')
        if rnd < 1 or rnd not in (top, top + 1):
            raise Usage(f'회차 {rnd} 가 순서에 맞지 않다(지금 {top}회차)')
        if name in units:
            raise Usage(f'상태표에 {name} 이 이미 있다')
        if o['--repo'] not in st['repos']:
            raise Usage(f'모르는 저장소: {o["--repo"]}')
        files, ferrs = split_paths(o['--files'])
        bad = [f for f in files if f.startswith(('/', ':')) or '..' in f.split('/')]
        if ferrs or bad or not files:
            raise Usage(f'--files 가 비었거나 쓸 수 없는 경로가 있다: {"; ".join(ferrs) or fmt(bad)}')
        outside = [f for f in files if not covered(f, union.get(o['--repo'], []))]
        if outside:  # 계획 pathspec 밖 수정은 범위 확장이다
            stop(c, 'scope')
            raise Blocked(f'scope — 계획 pathspec 밖: {fmt(outside)}')
        rows = c.rows()[1]
        prev = rows[-1][1] if rows else {}
        c.add_row({'단위': name, '내용': o['--summary'].replace('\n', ' '), '파일': join_paths(files),
                   '선행': prev.get('단위', '—'), '모델': prev.get('모델', ''), '병렬': '✘', '검수': prev.get('검수', ''),
                   'pathspec': join_paths([f'{o["--repo"]}:{f}' for f in files]), '상태': '미착수'})
        c.update(lambda s: s.setdefault('fix_units', []).append({'round': rnd, 'unit': name, 'key': o['--key']}))
    print(f'OK: fix add {name} ({rnd}회차, 키 {o["--key"]})')


def cmd_redeleg(c, rest):
    if len(rest) != 2 or rest[1] not in ('incr', 'get', 'reset'):
        raise Usage(USAGE)
    key, op = rest
    c.state()
    with c.locked():
        n = c.state().get('redelegations', {}).get(key, 0)
        if op == 'incr':
            if n >= 2:
                raise Blocked(f'재위임 한도(완료 기준당 2회) 초과 — {key}')
            n += 1
            c.update(lambda s: s.setdefault('redelegations', {}).__setitem__(key, n))
        elif op == 'reset':
            n = 0
            c.update(lambda s: s.setdefault('redelegations', {}).pop(key, None))
    print(n)


def cmd_stop(c, rest):
    if len(rest) != 1:
        raise Usage(USAGE)
    r = rest[0]
    if r not in STOPS and not (r.startswith('blocked:') and len(r) > 8):
        raise Usage(f'모르는 사유: {r} (허용: {", ".join(sorted(STOPS))}, blocked:<단위>)')
    c.state()
    with c.locked():
        if r == 'done':  # 완료 보고는 멈춘 단위가 없을 때만이다
            c.reload()
            left = [x['단위'] for _, x, _ in c.rows()[1] if x.get('상태') == 'blocked']
            if left:
                raise Blocked(f'blocked 행이 남아 있어 done 으로 끝내지 않는다: {", ".join(left)}')
        stop(c, r)
    print(f'OK: stop {r}')


def cmd_clear_stop(c, rest):
    if rest:
        raise Usage(USAGE)
    c.state()
    with c.locked():
        c.update(lambda s: s.__setitem__('stopped_reason', ''))
        c.set_line('중단', None)
    print('OK: clear-stop')


def cmd_state(c, rest):
    st = c.state()
    if len(rest) == 2 and rest[0] == 'get':
        v = st
        for k in rest[1].split('.'):
            if not isinstance(v, dict) or k not in v:
                raise Blocked(f'키 없음: {rest[1]}')
            v = v[k]
        print(v if isinstance(v, str) else json.dumps(v, ensure_ascii=False))
    elif len(rest) == 3 and rest[0] == 'set':
        try:
            val = json.loads(rest[2])
        except ValueError:
            val = rest[2]
        *path, last = rest[1].split('.')

        def setp(d):
            for k in path:
                d = d.setdefault(k, {})
                if not isinstance(d, dict):
                    raise Usage(f'{k} 는 객체가 아니다')
            d[last] = val
        c.update(setp)
        print(f'OK: state set {rest[1]}')
    else:
        raise Usage(USAGE)


def cmd_status_json(c, rest):
    if rest:
        raise Usage(USAGE)
    st, rows = c.state(), [r for _, r, _ in c.rows()[1]]
    le = st.get('last_eval')
    if le:
        p = sum(1 for r in le['results'] if r['exit'] == 0 and not r.get('timeout'))
        le = {'iteration': le['iteration'], 'at': le['at'], 'passed': p, 'failed': len(le['cmds']) - p,
              'total': len(le['cmds']), 'reused': le.get('reused', False), 'complete': le.get('complete', False)}
    print(json.dumps({'iterations': st.get('iterations', 0), 'max_iterations': st.get('max_iterations'),
                      'elapsed_sec': int(elapsed(st)), 'max_duration_sec': st.get('max_duration'),
                      'worker_timeout_sec': st.get('worker_timeout'), 'stopped_reason': st.get('stopped_reason', ''),
                      'units_total': len(rows), 'unfinished': sum(1 for r in rows if r.get('상태') != '완료'),
                      'blocked': sum(1 for r in rows if r.get('상태') == 'blocked'), 'last_eval': le},
                     ensure_ascii=False))


CMDS = {'check': cmd_check, 'init': cmd_init, 'run': cmd_run, 'treekey': cmd_treekey, 'clean': cmd_clean,
        'unit': cmd_unit, 'fix': cmd_fix, 'redeleg': cmd_redeleg, 'stop': cmd_stop, 'clear-stop': cmd_clear_stop,
        'state': cmd_state, 'status-json': cmd_status_json}
DRIVING = {'init', 'run', 'clean', 'unit', 'fix', 'redeleg'}  # git·조건 명령을 돌리는 명령만. stop·clear-stop·state 는 상태만 고치므로 제외

try:
    if len(sys.argv) < 3 or sys.argv[1] not in CMDS:
        raise Usage(USAGE)
    c = Ctx(sys.argv[2])
    if sys.argv[1] in DRIVING:
        with c.driving():
            CMDS[sys.argv[1]](c, sys.argv[3:])
    else:
        CMDS[sys.argv[1]](c, sys.argv[3:])
except Usage as e:
    print(e, file=sys.stderr)
    sys.exit(2)
except Blocked as e:
    print(f'BLOCKED: {e}')
    sys.exit(e.code)
except Exception:
    traceback.print_exc()
    sys.exit(2)
PY
