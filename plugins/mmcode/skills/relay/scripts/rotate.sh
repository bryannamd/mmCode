#!/usr/bin/env bash
# relay rotate: hc(herdr-core)로 새 터미널에 다음 세션을 띄우고 재개 프롬프트를 보낸다.
# 사용: rotate.sh [--print-prompt] <prefix> <HANDOFF.md> [PLAN.md]   (HC_TERMINAL_ID 필요. --print-prompt 는 불필요)
# --print-prompt: 아무것도 바꾸지 않고 재개 프롬프트만 stdout 에 출력한다(Herdr 밖에서도 된다).
# 새 세션의 effort 는 환경변수로 정한다: ROTATE_EFFORT=low|medium|high|xhigh|max (없으면 사용자 기본값)
# 새 세션의 에이전트 종류: ROTATE_KIND=claude|codex (없으면 claude). effort 옵션은 claude 에만 넘긴다. codex 는 --no-daemon 으로 띄운다.
# hc 실행 파일: ROTATE_HC_BIN (없으면 hc). 시험에서 가짜 hc 로 바꿀 때 쓴다.
# 새 터미널은 --no-parent 로 띄운다. 부모가 있으면 이 세션이 끝날 때 새 세션도 같이 끝난다.
# 내 터미널의 herdr.space·herdr.tab 라벨을 그대로 붙여 같은 탭의 새 패널로 보이게 한다. 라벨이 없으면 화면에 안 보이는 터미널로 띄운다.
# 이후 명령은 이름이 아니라 hc run 이 돌려준 주소로 겨냥한다.
# 인계 문서에 '모드: auto' 줄이 있으면 auto 모드다(references/DESIGN-auto.md 3절 11단계·9절).
#   연번 예약(claim): 새 세션 준비 확인 뒤·프롬프트 전송 전. goal/.lock 아래에서 읽기·+1·쓰기를 한 번에 해서
#           같은 인계 문서로 rotate 가 동시에 돌아도 번호가 겹치지 않는다(나중 호출은 그다음 번호).
#           goal/state.json 에 rotated_serial 을 남긴다.
#   프롬프트: 종류별 지시를 더한다. codex 는 턴 종료를 기다리지 않고 전송 시작만 확인한다(제한 20초).
#   exit 4: 새 세션은 떴는데 전송·대기가 실패했다. 나가기 전에 state.json stopped_reason=rotate-uncertain,
#           재개 블록 '중단:' 줄 기록, 새 터미널에 esc 를 보낸다.
# 일반 모드는 새 세션이 재개 4단계에서 연번을 직접 올리므로, 전송 성공 뒤에 하한만 보장한다(이미 올라갔으면 건드리지 않는다).
# 종료 코드: 0 성공 · 1 새 세션을 만들기 전 실패(준비 안 됨 포함. 일반 모드는 전송 실패도 1) · 2 입력 오류 · 3 Herdr 밖 · 4 auto 의 생성 뒤 전송·대기 실패
set -euo pipefail
print_only=0; pos=()
for a in "$@"; do
  case "$a" in
    --print-prompt) print_only=1 ;;
    -*) echo "알 수 없는 옵션: $a" >&2; exit 2 ;;
    *) pos+=("$a") ;;
  esac
done
set -- ${pos[@]+"${pos[@]}"}
[ $# -ge 2 ] && [ -n "$1" ] && [ -n "$2" ] || { echo "사용: rotate.sh [--print-prompt] <prefix> <HANDOFF.md> [PLAN.md]" >&2; exit 2; }
prefix=$1; handoff=$2; plan=${3:-}
hc_bin=${ROTATE_HC_BIN:-hc}
[ "$print_only" = 1 ] || [ -n "${HC_TERMINAL_ID:-}" ] || { echo "Herdr 밖이다. 인계 문서만 갱신하고 사용자에게 새 세션 시작을 안내하라." >&2; exit 3; }
[ -f "$handoff" ] || { echo "인계 문서 없음: $handoff" >&2; exit 2; }
[ "$print_only" = 1 ] || command -v jq >/dev/null || { echo "jq 필요" >&2; exit 2; }
[ "$print_only" = 1 ] || command -v python3 >/dev/null || { echo "python3 필요" >&2; exit 2; }
effort=${ROTATE_EFFORT:-}
case "$effort" in ''|low|medium|high|xhigh|max) ;; *) echo "ROTATE_EFFORT 값이 잘못됐다: $effort" >&2; exit 2 ;; esac
kind=${ROTATE_KIND:-claude}
case "$kind" in claude|codex) ;; *) echo "ROTATE_KIND 값이 잘못됐다: $kind" >&2; exit 2 ;; esac
# 새 터미널에서 실행할 명령. codex 는 --no-daemon 이 없으면 명령이 hc 밖에서 실행된다.
if [ "$kind" = codex ]; then agent_cmd=(codex --no-daemon); else agent_cmd=(claude); [ -z "$effort" ] || agent_cmd+=(--effort "$effort"); fi
cur=$(grep -E -m1 "세션 연번:\s*$prefix \(#[0-9]+\)" "$handoff" | sed -E 's/.*\(#([0-9]+)\).*/\1/' || true)
[ -n "$cur" ] || { echo "인계 문서에 '세션 연번: $prefix (#N)' 줄이 없다" >&2; exit 2; }
next=$((cur + 1))
name="${prefix}-${next}"
# auto 모드 판정: 재개 블록의 '모드: auto' 줄. 기계 상태 파일은 인계 문서 옆 goal/state.json 이다.
auto=0; if grep -Eq '^[[:space:]]*모드:[[:space:]]*auto([^A-Za-z0-9_-]|$)' "$handoff"; then auto=1; fi
state="$(dirname "$handoff")/goal/state.json"
prompt="$handoff 의 재개 지시부터 진행(mmcode:relay 스킬 resume 모드)."
[ -n "$plan" ] && prompt="$prompt 계획: $plan."
[ -z "${HC_TERMINAL_ID:-}" ] || prompt="$prompt 이전 세션 터미널 $HC_TERMINAL_ID 는 hc get 으로 idle·done 확인 후 hc kill 뒤 hc rm 으로 닫을 것."
prompt="$prompt 첫 응답에 status.sh 상태표를 표시할 것."
if [ "$auto" = 1 ]; then
  prompt="$prompt 이 계획은 모드 auto 다. $state 와 재개 블록·상태표만 읽고,"
  if [ "$kind" = codex ]; then
    prompt="$prompt 전이표(relay SKILL.md auto 절)대로 확인한 뒤 그 턴 안에서 바로 반복 본문에 들어가라."
  else
    prompt="$prompt 전이표(relay SKILL.md auto 절)대로 반복 엔진을 등록만 하고 턴을 끝내라."
  fi
fi
if [ "$print_only" = 1 ]; then printf '%s\n' "$prompt"; exit 0; fi
if [ "$auto" = 1 ]; then
  python3 -I -c 'import json, sys; sys.exit(0 if isinstance(json.load(open(sys.argv[1], encoding="utf-8")), dict) else 1)' "$state" 2>/dev/null \
    || { echo "auto 모드인데 state.json 이 없거나 JSON 객체가 아니다: $state" >&2; exit 2; }
fi

# 인계 문서·state.json 을 임시 파일 + rename 으로 고친다(중간에 죽어도 원본이 온전하다).
#   edit_file state <키> <JSON 값>   goal/state.json 한 키를 쓴다
#   edit_file stop <사유>            재개 블록 끝에 '중단: <사유>' 줄을 쓴다(이미 있으면 그 줄을 바꾼다)
#   edit_file claim <prefix>            '세션 연번: <prefix> (#N)' 을 (#N+1) 로 쓰고 N+1 을 stdout 으로 돌려준다(auto)
#   edit_file ensure <prefix> <floor>   N 이 floor 보다 작을 때만 (#floor) 로 올린다(일반 모드)
edit_file() {
  python3 -I - "$state" "$handoff" "$@" <<'PY'
import fcntl, json, os, re, sys, tempfile
state, handoff, op, *args = sys.argv[1:]
# eval-goal.sh 와 같은 잠금(goal/.lock)을 잡고 읽기-고치기-쓰기를 한다. 잠금은 이 프로세스가 끝나면 풀린다.
# 일반 모드에는 goal/ 폴더가 없다. 폴더를 만들지 않고 잠금 없이 고친다(그 모드에서는 eval-goal.sh 도 돌지 않는다).
gdir = os.path.dirname(state) or '.'
if os.path.isdir(gdir):
    lock = open(os.path.join(gdir, '.lock'), 'a')
    fcntl.flock(lock, fcntl.LOCK_EX)
def rd(p):  # 줄바꿈·바이트를 그대로 읽는다(CRLF·깨진 바이트도 바꾸지 않는다)
    with open(p, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()
def write(p, text):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p) or '.', prefix='.rotate-', suffix='.tmp')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(text)
        os.chmod(tmp, os.stat(p).st_mode & 0o777)
        os.replace(tmp, p)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
if op == 'state':
    with open(state, encoding='utf-8') as f:
        d = json.load(f)
    d[args[0]] = json.loads(args[1])
    write(state, json.dumps(d, ensure_ascii=False, indent=2) + '\n')
elif op in ('claim', 'ensure'):
    # '세션 연번: <prefix> (#N)' 줄을 잠금 아래에서 최신 파일로 다시 읽어 올린다. 그 사이 다른 쪽이 고친 내용을 덮지 않는다.
    #   claim <prefix>          항상 N+1 로 쓰고 그 번호를 stdout 으로 돌려준다. 동시에 도는 호출은 서로 다른 번호를 받는다.
    #   ensure <prefix> <floor> N 이 floor 보다 작을 때만 floor 로 올린다. 이미 올라가 있으면 건드리지 않는다.
    prefix = args[0]
    lines = rd(handoff).split('\n')
    pat = re.compile(r'(세션 연번:\s*' + re.escape(prefix) + r' \(#)(\d+)(\))')
    found = [m for m in (pat.search(l) for l in lines) if m]
    if not found:
        print(f'세션 연번 줄(세션 연번: {prefix} (#N))이 없다 - 연번을 올리지 못했다.', file=sys.stderr)
        sys.exit(1)
    n = int(found[0].group(2))
    new = n + 1 if op == 'claim' else int(args[1])
    if new > n:
        for i, l in enumerate(lines):
            m = pat.search(l)
            if m and int(m.group(2)) == n:
                lines[i] = l[:m.start(2)] + str(new) + l[m.end(2):]
        write(handoff, '\n'.join(lines))
    elif new < n:
        print(f'세션 연번이 이미 #{n} 이다(기준 #{new} 보다 크다) - 건드리지 않았다.', file=sys.stderr)
    if op == 'claim':
        print(new)
else:
    new = '중단: ' + args[0]
    lines = rd(handoff).split('\n')
    at = next((i for i, l in enumerate(lines) if re.match(r'\s*중단:', l)), None)
    if at is not None:
        lines[at] = re.match(r'\s*', lines[at]).group(0) + new
    else:
        # 재개 지시 절의 첫 코드 펜스 닫는 줄 앞. 펜스가 없으면 절 끝, 절이 없으면 세션 연번 줄 뒤.
        sec = next((i for i, l in enumerate(lines) if re.match(r'##\s*재개', l)), None)
        if sec is None:
            pos = next((i + 1 for i, l in enumerate(lines) if '세션 연번:' in l), len(lines))
        else:
            end = next((i for i in range(sec + 1, len(lines)) if lines[i].startswith('## ')), len(lines))
            fences = [i for i in range(sec + 1, end) if lines[i].lstrip().startswith('```')]
            pos = end
            if len(fences) >= 2:
                pos = fences[1]
            else:
                while pos > sec + 1 and not lines[pos - 1].strip():
                    pos -= 1
        lines.insert(pos, new)
    write(handoff, '\n'.join(lines))
PY
}
claim_serial() {  # auto: 연번을 N+1 로 올리고 그 번호를 stdout 으로 돌려준다(goal/.lock 아래에서 최신 파일을 읽고 쓴다)
  edit_file claim "$prefix"
}
ensure_serial() {  # 일반 모드: 연번이 next 보다 작을 때만 next 로 올린다(새 세션이 이미 올렸으면 건드리지 않는다)
  edit_file ensure "$prefix" "$next"
}
rename_term() {  # 새 터미널에 '<prefix> (#next)' 표시 라벨을 붙인다(hc 에는 이름을 바꾸는 명령이 없다)
  "$hc_bin" label "$term" "relay=$prefix (#$next)" >/dev/null 2>&1 || true
}
# auto: 새 세션은 떴는데 전송·대기가 끝나지 않았다. 새 세션이 뒤늦게 stopped_reason=rotate 를 읽고 시작하지 못하게 막고 exit 4.
rotate_uncertain() {
  local ok=1
  echo "$1" >&2
  edit_file state stopped_reason '"rotate-uncertain"' || { ok=0; echo "state.json 갱신 실패 — stopped_reason 을 직접 rotate-uncertain 으로 고쳐라" >&2; }
  edit_file stop rotate-uncertain || { ok=0; echo "인계 문서 '중단:' 줄 기록 실패 — 재개 블록에 '중단: rotate-uncertain' 을 직접 넣어라" >&2; }
  "$hc_bin" keys "$term" esc >/dev/null 2>&1 || { ok=0; echo "esc 전송 실패 — $term 의 새 세션을 직접 멈춰라" >&2; }
  [ "$ok" = 0 ] || echo "stopped_reason 과 '중단:' 줄에 rotate-uncertain 을 기록했고 새 터미널($term)에 esc 를 보냈다." >&2
  exit 4
}
start_term() {  # $1 이름으로 새 터미널을 띄운다. 결과 JSON 은 start_out, stderr(오류 JSON·경고)는 start_err 에 남긴다.
  # stdout 과 stderr 를 섞지 않는다: 성공했는데 경고가 섞이면 주소를 읽지 못하고, 띄운 터미널이 정리되지 않은 채 남는다.
  local e rc=0
  e=$(mktemp "${TMPDIR:-/tmp}/rotate-run.XXXXXX") || return 1
  start_out=$("$hc_bin" run --bg --json --no-parent --name "$1" --cwd "$PWD" ${label_args[@]+"${label_args[@]}"} -- "${agent_cmd[@]}" 2>"$e") || rc=$?
  start_err=$(cat "$e"); rm -f "$e"
  return "$rc"
}
wait_term() {  # $1 제한(초). hc wait 는 나에게 메시지가 와도 끝난다(reason=message). 그때는 다시 기다린다(최대 3회).
  local out= i
  for i in 1 2 3; do
    out=$("$hc_bin" wait "$term" --timeout "$1" --json 2>/dev/null) || out=
    [ "$(printf '%s' "$out" | jq -r '.reason // empty' 2>/dev/null)" = message ] || break
  done
  printf '%s' "$out"
}
err_kind() {  # hc 오류 JSON 의 error.kind(없으면 빈 값)
  printf '%s' "$1" | jq -r 'select(type == "object") | .error.kind // empty' 2>/dev/null | head -1
}

# 인계 문서 스냅샷 — docs 가 gitignore 라 이력이 없다. 한 번 잘못 쓰면 상태표가 사라진다.
snap_dir="$(dirname "$handoff")/archive"; mkdir -p "$snap_dir"
cp "$handoff" "$snap_dir/HANDOFF.#${cur}.md"
# 내 터미널의 스페이스·탭 라벨을 읽는다. 값을 지어내면 엉뚱한 스페이스가 생기므로 읽은 값만 쓴다.
self=$("$hc_bin" get --json "$HC_TERMINAL_ID" 2>/dev/null) || self=
space=$(printf '%s' "$self" | jq -r '.labels["herdr.space"] // empty' 2>/dev/null) || space=
tab=$(printf '%s' "$self" | jq -r '.labels["herdr.tab"] // empty' 2>/dev/null) || tab=
label_args=()
if [ -n "$space" ] && [ -n "$tab" ]; then
  label_args=(--label "herdr.space=$space" --label "herdr.tab=$tab")
else
  echo "경고: 내 터미널($HC_TERMINAL_ID)에 herdr.space·herdr.tab 라벨이 없다. 화면에 보이지 않는 터미널로 띄운다." >&2
fi
# 이름 충돌(name_taken)은 기다려도 안 풀린다 — 재시도 없이 내 주소를 붙인 폴백 이름으로 한 번 더 띄운다.
if ! start_term "$name"; then
  kind_err=$(err_kind "$start_err"); [ -n "$kind_err" ] || kind_err=$(err_kind "$start_out")
  if [ "$kind_err" = name_taken ]; then
    name="${name}-$(printf '%s' "$HC_TERMINAL_ID" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9')"
    start_term "$name" || { echo "hc run 실패($name): $start_err $start_out" >&2; exit 1; }
  else
    echo "hc run 실패($name): $start_err $start_out" >&2; exit 1
  fi
fi
term=$(printf '%s' "$start_out" | jq -r '.address // empty' 2>/dev/null) || term=
[ -n "$term" ] || { echo "hc run 결과에 주소가 없다($name): $start_out $start_err" >&2; exit 1; }
# 새 세션이 입력을 받을 준비가 될 때까지 기다린다. 준비되지 않으면 그 터미널을 정리하고 새 세션 생성 실패로 본다.
ready=$(wait_term 60)
r_reason=$(printf '%s' "$ready" | jq -r '.reason // empty' 2>/dev/null) || r_reason=
r_status=$(printf '%s' "$ready" | jq -r '.status // empty' 2>/dev/null) || r_status=
case "$r_reason:$r_status" in
  status:idle|status:done) ;;
  *)
    echo "새 세션이 준비되지 않았다($term $name): reason=${r_reason:-없음} status=${r_status:-없음}. 터미널을 정리했다." >&2
    "$hc_bin" kill "$term" >/dev/null 2>&1 || true
    "$hc_bin" rm "$term" >/dev/null 2>&1 || true
    exit 1 ;;
esac
rename_term
if [ "$auto" = 1 ]; then
  # auto: 새 세션이 읽을 때 연번이 이미 올라가 있고 rotated_serial 이 있어야 한다. 그래서 전송 전에 예약한다.
  # 읽기·+1·쓰기를 잠금 아래에서 한 번에 한다: 같은 인계 문서로 rotate 가 동시에 돌아도 번호가 겹치지 않는다(나중 호출은 그다음 번호).
  # 연번을 먼저 올린다: 중간에 죽으면 번호가 건너뛸 뿐이다. 표시를 먼저 쓰면 번호가 겹친다.
  claimed=$(claim_serial) || rotate_uncertain "연번 예약 실패 — $name($term) 은 떠 있다. 프롬프트는 보내지 않았다."
  if [ "$claimed" != "$next" ]; then next=$claimed; rename_term; fi  # 다른 호출이 먼저 올렸다: 받은 번호로 표시 라벨을 고친다
  edit_file state rotated_serial true || rotate_uncertain "state.json 기록 실패 — $name($term) 은 떠 있다. 연번은 #$next 로 이미 올렸다. 프롬프트는 보내지 않았다."
fi
# 전송 성공 조건: claude·일반 모드 codex 는 턴 종료까지(제한 120초), auto codex 는 전송 시작만(제한 20초).
send_timeout=120; need_turn_end=1
if [ "$auto" = 1 ] && [ "$kind" = codex ]; then send_timeout=20; need_turn_end=0; fi
sent=0
if send_out=$("$hc_bin" send --wait --timeout "$send_timeout" --json "$term" "$prompt" 2>/dev/null); then
  if [ "$need_turn_end" = 1 ]; then
    s_reason=$(printf '%s' "$send_out" | jq -r 'select(.started == true) | .wait.reason // empty' 2>/dev/null) || s_reason=
    # 나에게 온 메시지로 대기가 끊겼으면 새 세션의 턴 종료를 다시 기다린다.
    if [ "$s_reason" = message ]; then s_reason=$(wait_term "$send_timeout" | jq -r '.reason // empty' 2>/dev/null) || s_reason=; fi
    [ "$s_reason" != status ] || sent=1
  else
    printf '%s' "$send_out" | jq -e '.started == true' >/dev/null 2>&1 && sent=1
  fi
fi
if [ "$sent" != 1 ]; then
  if [ "$auto" = 1 ]; then
    rotate_uncertain "prompt 전송 실패 또는 대기 초과 — $term 상태를 hc get 으로 확인. 세션 연번은 #$next 로 이미 올렸다."
  fi
  echo "prompt 전송 실패 또는 대기 초과 — $term 상태를 hc get 으로 확인. 세션 연번은 갱신하지 않았다(#$cur 유지)." >&2; exit 1
fi
# 일반 모드: 전송 성공 후에만 세션 연번을 올린다. 새 세션이 재개 4단계에서 이미 올렸을 수 있으므로 하한만 보장한다.
if [ "$auto" != 1 ]; then ensure_serial || echo "경고: 세션 연번 줄을 찾지 못해 올리지 못했다. 인계 문서의 연번을 확인하라." >&2; fi
echo "교체 완료: terminal=$term name=$name (#$next) effort=${effort:-기본값}. 이 세션은 여기서 종료한다(자기 터미널은 닫지 않는다)."
