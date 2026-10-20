#!/usr/bin/env bash
# rotate.sh 시험. 가짜 herdr 와 임시 폴더에서만 돈다 — 실제 herdr·저장소·홈을 건드리지 않는다.
# 사용: tests/relay/rotate.test.sh   (어느 위치에서 불러도 된다. 시험 대상을 바꾸려면 ROTATE_SH=<경로>)
# 종료 코드: 0 = 전부 통과 · 1 = 실패 있음 · 2 = 실행 환경 문제
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
rotate="${ROTATE_SH:-$root/plugins/mmcode/skills/relay/scripts/rotate.sh}"
for c in jq python3; do command -v "$c" >/dev/null || { echo "$c 이 없다" >&2; exit 2; }; done
[ -f "$rotate" ] || { echo "시험 대상 없음: $rotate" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/rotate-test.XXXXXX")"
case "$tmp" in */rotate-test.*) trap 'rm -rf "$tmp"' EXIT ;; *) echo "임시 폴더 생성 실패" >&2; exit 2 ;; esac

# ── 가짜 herdr: 호출을 $FAKE_DIR/calls.log 에 남기고 정해진 JSON 을 돌려준다. PATH 앞에 둬서 진짜 herdr 는 닿지 않는다.
fakebin="$tmp/fakebin"; mkdir -p "$fakebin" "$tmp/alt" "$tmp/home"
cat > "$fakebin/herdr" <<'FAKE'
#!/usr/bin/env bash
d=${FAKE_DIR:?}
echo "$*" >> "$d/calls.log"
fail() { echo "{\"id\":\"cli:$1\",\"error\":{\"code\":\"$2\",\"message\":\"fake $2\"}}" >&2; exit 1; }
barrier() {  # barrier <이름>: FAKE_BARRIER 개 호출이 모두 도착할 때까지 기다린다(최대 10초). 동시 호출 시험에서만 쓴다.
  [ -n "${FAKE_BARRIER:-}" ] || return 0
  touch "$d/bar.$1.$$"; local i=0
  while [ "$(ls "$d" | grep -c "^bar[.]$1[.]")" -lt "$FAKE_BARRIER" ] && [ "$i" -lt 500 ]; do command -p sleep 0.02; i=$((i + 1)); done
}
pane=; prev=
for a in "$@"; do [ "$prev" = --pane ] && pane=$a; prev=$a; done
case "${1:-} ${2:-}" in
  "pane split")
    [ -z "${FAKE_SPLIT_FAIL:-}" ] || fail pane:split pane_split_failed
    barrier split
    pid=7   # 장벽을 쓰는(동시 호출) 시험에서는 호출마다 다른 pane 을 돌려준다
    if [ -n "${FAKE_BARRIER:-}" ]; then k=1; while ! mkdir "$d/pane.$k" 2>/dev/null; do k=$((k + 1)); done; pid=$((6 + k)); fi
    echo "{\"id\":\"cli:pane:split\",\"result\":{\"pane\":{\"pane_id\":\"w1:p$pid\"}}}" ;;
  "agent start")
    n=$3
    [ -z "${FAKE_START_FAIL_ALL:-}" ] || fail agent:start agent_pane_busy
    [ "$n" != "${FAKE_TAKEN_NAME:-}" ] || fail agent:start agent_name_taken
    [ "$n" != "${FAKE_BUSY_NAME:-}" ] || fail agent:start agent_pane_busy
    if awk -F'\t' -v n="$n" '$1 == n { f = 1 } END { exit !f }' "$d/agents" 2>/dev/null; then fail agent:start agent_name_taken; fi   # 실제 herdr 처럼 살아 있는 에이전트 이름은 유일하다
    printf '%s\t%s\n' "$n" "$pane" >> "$d/agents"
    [ -z "${FAKE_BREAK_STATE:-}" ] || echo '[1]' > "${FAKE_STATE:?}"
    [ -z "${FAKE_DROP_SERIAL_ON_START:-}" ] || { grep -v '^세션 연번:' "$FAKE_HANDOFF" > "$FAKE_HANDOFF.new"; mv "$FAKE_HANDOFF.new" "$FAKE_HANDOFF"; }
    echo '{"id":"cli:agent:start","result":{}}' ;;
  "agent list")
    touch "$d/agents"
    jq -Rn '{id:"cli:agent:list",result:{agents:[inputs|split("\t")|{name:.[0],pane_id:.[1],agent_status:"idle",agent:"claude"}]}}' < "$d/agents" ;;
  "agent prompt")
    grep -E '세션 연번' "${FAKE_HANDOFF:?}" > "$d/serial.at-prompt" || true
    cp "${FAKE_STATE:?}" "$d/state.at-prompt" 2>/dev/null || true
    if [ -n "${FAKE_SERIAL_DURING_PROMPT:-}" ]; then   # 전송과 연번 갱신 사이에 다른 쪽이 연번을 바꾼 상황
      sed "s/^세션 연번: demo (#[0-9]*)/세션 연번: demo (#${FAKE_SERIAL_DURING_PROMPT})/" "$FAKE_HANDOFF" > "$FAKE_HANDOFF.new" && mv "$FAKE_HANDOFF.new" "$FAKE_HANDOFF"
    fi
    [ -z "${FAKE_DROP_SERIAL_ON_PROMPT:-}" ] || { grep -v '^세션 연번:' "$FAKE_HANDOFF" > "$FAKE_HANDOFF.new"; mv "$FAKE_HANDOFF.new" "$FAKE_HANDOFF"; }
    [ -z "${FAKE_PROMPT_FAIL:-}" ] || fail agent:prompt agent_prompt_stalled
    echo '{"id":"cli:agent:prompt","result":{}}' ;;
  "pane send-keys")
    [ -z "${FAKE_SENDKEYS_FAIL:-}" ] || fail pane:send-keys pane_send_failed
    echo '{"result":{}}' ;;
  "pane rename") barrier rename; touch "$d/renamed"; echo '{"result":{}}' ;;
  "pane close") echo '{"result":{}}' ;;
  *) echo "fake herdr: 모르는 호출 $*" >&2; exit 64 ;;
esac
FAKE
# sleep 은 기록만 하고 바로 돌아온다(재시도 횟수를 세고, 시험을 빠르게 한다).
cat > "$fakebin/sleep" <<'FAKE'
#!/bin/sh
echo "$*" >> "${FAKE_DIR:?}/sleeps.log"
FAKE
# ROTATE_HERDR_BIN 이 쓰이는지 보는 얇은 껍데기: 호출을 alt.log 에 남기고 가짜 herdr 로 넘긴다.
cat > "$tmp/alt/herdr" <<FAKE
#!/bin/sh
echo "\$*" >> "\${FAKE_DIR:?}/alt.log"
exec "$fakebin/herdr" "\$@"
FAKE
chmod +x "$fakebin/herdr" "$fakebin/sleep" "$tmp/alt/herdr"
# 다른 쪽 쓰기 주체(eval-goal.sh 역할): goal/.lock 을 쥐고 인계 문서를 읽은 뒤, 오래 걸려 옛 내용 기준으로 통째로 되쓴다.
cat > "$tmp/writer.py" <<'PY'
import fcntl, os, sys, time
lock_path, handoff, held, renamed = sys.argv[1:5]
f = open(lock_path, 'a'); fcntl.flock(f, fcntl.LOCK_EX)
stale = open(handoff, encoding='utf-8').read()
open(held, 'w').close()
for _ in range(500):                      # rotate.sh 가 연번 갱신 직전(pane rename)에 올 때까지 기다린다. 최대 10초
    if os.path.exists(renamed): break
    time.sleep(0.02)
time.sleep(0.5)                           # 그 갱신이 잠금 대기에 들어갈 시간
tmp = handoff + '.w'
open(tmp, 'w', encoding='utf-8').write(stale.replace('다음 작업:', '최근 조건 평가: 1 시험 통과 1/실패 0\n다음 작업:'))
os.replace(tmp, handoff)
PY

# ── 사례 준비·실행·검사 도구
n=0; pass=0; fail=0; why=
mkcase() {  # mkcase <auto|plain>: 사례 폴더·인계 문서·(auto 면) state.json 을 만든다
  n=$((n + 1)); work="$tmp/case$n"; fdir="$work/.fake"
  mkdir -p "$fdir" "$work/docs/relay/demo"
  handoff="$work/docs/relay/demo/HANDOFF.md"; state="$work/docs/relay/demo/goal/state.json"
  {
    printf '%s\n' '# HANDOFF — demo' '' '## 재개 지시' '' '```text' '계획: docs/relay/demo/PLAN.md. 규칙: mmcode:relay 스킬 (resume 모드).'
    if [ "$1" = auto ]; then echo '모드: auto'; fi
    printf '%s\n' '세션 연번: demo (#3)' '커밋 정책: 자동 승인: U1~U2 / 만료: 계획 완료' '다음 작업: U1 — 첫 단위. 첫 응답에 status.sh 상태표.' '```' '' '## 상태표' '' '| 단위 | 상태 |' '|---|---|' '| U1 | 미착수 |'
  } > "$handoff"
  if [ "$1" = auto ]; then
    mkdir -p "$work/docs/relay/demo/goal"
    echo '{"started_at":"2026-10-20T09:00:00+09:00","iterations":2,"max_iterations":12,"stopped_reason":"rotate","units":{}}' > "$state"
  fi
  extra=(); no_herdr_env=; no_pane=; herdr_path="$fakebin/herdr"; bg_pids=
}
rot() {  # rot <rotate.sh 인자...>: 격리된 환경에서 돌린다. 결과: $out(stdout) $err(stderr) $rc
  local e=("PATH=$fakebin:$PATH" "HOME=$tmp/home" "HERDR_TAB_ID=w1:T1" "ROTATE_HERDR_BIN=$herdr_path" "FAKE_DIR=$fdir" "FAKE_HANDOFF=$handoff" "FAKE_STATE=$state")
  [ -n "$no_herdr_env" ] || e+=("HERDR_ENV=1")
  [ -n "$no_pane" ] || e+=("HERDR_PANE_ID=w1:p1")
  rc=0
  out=$(cd "$work" && env -i "${e[@]}" ${extra[@]+"${extra[@]}"} "${BASH:-bash}" "$rotate" "$@" 2>"${errfile:-$fdir/stderr}") || rc=$?
  err=$(cat "${errfile:-$fdir/stderr}")
}
rot_bg() {  # rot_bg <꼬리표> <rotate.sh 인자...>: 백그라운드로 돌리고 결과를 $fdir/<꼬리표>.{rc,out,err} 에 남긴다
  local tag=$1; shift
  ( errfile="$fdir/$tag.raw"; rot "$@"; printf '%s' "$rc" > "$fdir/$tag.rc"; printf '%s' "$out" > "$fdir/$tag.out"; printf '%s' "$err" > "$fdir/$tag.err" ) &
  bg_pids="$bg_pids $!"
}
has()   { case "$1" in *"$2"*) return 0 ;; esac; why="${3:-출력}에 '$2' 없음"; return 1; }
lacks() { case "$1" in *"$2"*) why="${3:-출력}에 '$2' 있음"; return 1 ;; esac; return 0; }
eq()    { [ "$1" = "$2" ] || { why="$3: '$1' ≠ '$2'"; return 1; }; }
calls() { cat "$fdir/calls.log" 2>/dev/null || true; }
count() { calls | grep -c -- "$1" || true; }                 # 호출 로그에서 패턴에 맞는 줄 수
lineno() { calls | grep -n -- "$1" | head -1 | cut -d: -f1; } # 첫 줄 번호(없으면 빈 값)
serial() { grep '세션 연번' "$handoff"; }
sleeps() { if [ -f "$fdir/sleeps.log" ]; then grep -c . "$fdir/sleeps.log" || true; else echo 0; fi; }
untouched() {  # 호출 0회 + 스냅샷 폴더 없음 = 부작용 없이 끝났다
  [ ! -e "$fdir/calls.log" ] || { why="herdr 가 호출됨"; return 1; }
  [ ! -e "$work/docs/relay/demo/archive" ] || { why="archive 가 생김"; return 1; }
}
order() {  # order <패턴...>: 호출 로그에서 패턴들이 이 순서로 처음 나타난다
  local prev=0 p l
  for p in "$@"; do
    l=$(lineno "$p"); [ -n "$l" ] || { why="호출 없음: $p"; return 1; }
    [ "$l" -gt "$prev" ] || { why="호출 순서 어긋남: $p"; return 1; }
    prev=$l
  done
}

# ── --print-prompt
t_print_claude() {
  mkcase auto; extra=(ROTATE_KIND=claude); no_herdr_env=1
  local before; before=$(cksum < "$handoff"; cksum < "$state")
  rot --print-prompt demo "$handoff" docs/relay/demo/PLAN.md
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  has "$out" "등록만 하고 턴을 끝내라" stdout || return 1
  lacks "$out" "바로 반복 본문에 들어가라" stdout || return 1
  has "$out" "$handoff 의 재개 지시부터 진행" stdout || return 1
  has "$out" "계획: docs/relay/demo/PLAN.md." stdout || return 1
  has "$out" "$state" stdout || return 1
  has "$out" "이전 세션 pane w1:p1 는 idle 확인 후 herdr pane close" stdout || return 1
  eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1 "stdout 줄 수" || return 1
  untouched || return 1
  eq "$(cksum < "$handoff"; cksum < "$state")" "$before" "인계 문서·state.json 변화" || return 1
}
t_print_codex() {
  mkcase auto; extra=(ROTATE_KIND=codex); no_herdr_env=1
  rot --print-prompt demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  has "$out" "바로 반복 본문에 들어가라" stdout || return 1
  lacks "$out" "턴을 끝내라" stdout || return 1
  lacks "$out" "등록만" stdout || return 1
  untouched || return 1
}
t_print_plain() {
  mkcase plain; no_herdr_env=1
  rot --print-prompt demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  has "$out" "첫 응답에 status.sh 상태표를 표시할 것." stdout || return 1
  lacks "$out" "모드 auto" stdout || return 1
  lacks "$out" "반복 본문" stdout || return 1
  lacks "$out" "턴을 끝내라" stdout || return 1
  untouched || return 1
}
t_print_position() {  # 옵션 위치는 어디든 되고, 이전 pane id 를 모르면 그 문장을 뺀다
  mkcase plain; no_herdr_env=1; no_pane=1
  rot demo "$handoff" --print-prompt
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  lacks "$out" "pane ?" stdout || return 1
  lacks "$out" "herdr pane close" stdout || return 1
}
t_auto_detect() {  # '모드: auto' 줄 판정: 들여쓰기·뒤 설명은 auto, 주석·다른 낱말은 auto 가 아니다
  local v
  mkcase plain; no_herdr_env=1
  for v in '모드: auto' '  모드: auto' '모드: auto (완료 조건까지 반복)' '모드: auto# 설명'; do
    awk -v line="$v" '/^세션 연번:/ { print line } { print }' "$handoff" > "$work/h.md"
    rot --print-prompt demo "$work/h.md"
    has "$out" "모드 auto" "'$v' 인 줄의 출력" || return 1
  done
  for v in '# 모드: auto' '모드: automatic' '모드: 일반' '`모드: auto`'; do
    awk -v line="$v" '/^세션 연번:/ { print line } { print }' "$handoff" > "$work/h.md"
    rot --print-prompt demo "$work/h.md"
    lacks "$out" "모드 auto" "'$v' 인 줄의 출력" || return 1
  done
}
t_print_missing() {
  mkcase plain; no_herdr_env=1
  rot --print-prompt demo "$work/nope.md"
  eq "$rc" 2 "인계 문서가 없을 때 exit" || return 1
}

# ── 연번 갱신 시점
t_serial_auto() {  # auto: prompt 호출 전에 연번 +1 과 rotated_serial 이 끝나 있다
  mkcase auto
  rot demo "$handoff" docs/relay/demo/PLAN.md
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  has "$(cat "$fdir/serial.at-prompt")" "(#4)" "prompt 시점 연번" || return 1
  eq "$(jq -r '.rotated_serial' "$fdir/state.at-prompt")" true "prompt 시점 rotated_serial" || return 1
  eq "$(serial | grep -c '(#4)')" 1 "최종 연번 #4 줄 수(두 번 올리면 #5)" || return 1
  eq "$(jq -r '.stopped_reason' "$state")" rotate "성공 시 stopped_reason" || return 1
  eq "$(jq -r '.rotated_serial' "$state")" true "최종 rotated_serial" || return 1
  order '^pane split' '^agent start demo-4 ' '^pane rename w1:p7 demo (#4)' '^agent prompt demo-4 ' || return 1
  local p; p=$(calls | grep '^agent prompt')
  has "$p" "--wait --timeout 120000" "claude prompt 인자" || return 1
  lacks "$p" "--until" "claude prompt 인자" || return 1
  has "$out" "교체 완료: pane=w1:p7 agent=demo-4 (#4)" stdout || return 1
}
t_serial_plain() {  # 일반 모드: 전송 뒤에 갱신하고 state.json 은 만들지 않는다
  mkcase plain
  rot demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  has "$(cat "$fdir/serial.at-prompt")" "(#3)" "prompt 시점 연번(아직 그대로)" || return 1
  has "$(serial)" "(#4)" "최종 연번" || return 1
  [ ! -e "$work/docs/relay/demo/goal" ] || { why="goal 폴더가 생김"; return 1; }
  has "$(calls | grep '^agent prompt')" "--wait --timeout 120000" "prompt 인자" || return 1
}
t_serial_locked() {  # 다른 쪽이 잠금을 쥔 채 옛 내용으로 인계 문서를 되쓰는 동안: 연번 갱신은 기다렸다가 최신 파일에 +1 한다
  local pid n=0
  mkcase auto
  python3 -I "$tmp/writer.py" "$work/docs/relay/demo/goal/.lock" "$handoff" "$fdir/held" "$fdir/renamed" &
  pid=$!
  while [ ! -e "$fdir/held" ] && [ "$n" -lt 500 ]; do sleep 0.02; n=$((n + 1)); done
  [ -e "$fdir/held" ] || { wait "$pid"; why="다른 쪽이 잠금을 쥐지 못함"; return 1; }
  rot demo "$handoff"
  wait "$pid"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  has "$(serial)" "(#4)" "연번(되쓴 쪽이 덮으면 #3 으로 돌아간다)" || return 1
  has "$(cat "$handoff")" "최근 조건 평가: 1 시험 통과" "다른 쪽이 쓴 줄(연번 갱신이 덮으면 사라진다)" || return 1
  eq "$(jq -r '.rotated_serial' "$state")" true "rotated_serial" || return 1
}
t_serial_race_values() {  # 일반 모드: 전송과 갱신 사이에 연번이 바뀌어도(새 세션이 이미 올림) 기준 이상이면 건드리지 않고, 기준보다 작으면 기준까지 올린다(exit 0)
  mkcase plain; extra=(FAKE_SERIAL_DURING_PROMPT=4)
  rot demo "$handoff"
  eq "$rc" 0 "이미 올라간 경우 exit(stderr: $err)" || return 1
  has "$(serial)" "(#4)" "이미 올라간 경우 연번(또 올리면 #5)" || return 1
  lacks "$err" "건드리지 않았다" "이미 올라간 경우 stderr" || return 1
  mkcase plain; extra=(FAKE_SERIAL_DURING_PROMPT=9)
  rot demo "$handoff"
  eq "$rc" 0 "모르는 값 exit(stderr: $err)" || return 1
  has "$(serial)" "(#9)" "모르는 값 연번(덮으면 안 된다)" || return 1
  has "$err" "건드리지 않았다" "모르는 값 stderr" || return 1
  mkcase plain; extra=(FAKE_SERIAL_DURING_PROMPT=2)
  rot demo "$handoff"
  eq "$rc" 0 "기준보다 작은 값 exit(stderr: $err)" || return 1
  has "$(serial)" "(#4)" "기준보다 작은 값은 기준까지 올린다" || return 1
}
t_claim_concurrent() {  # 같은 인계 문서로 rotate 두 개가 동시에 돌아도 연번이 겹치지 않는다(auto): 예약은 잠금 아래에서 읽기·+1·쓰기를 한 번에 한다
  local r p n na nb last
  mkcase auto; extra=(FAKE_BARRIER=2)
  rot_bg a demo "$handoff"; rot_bg b demo "$handoff"
  wait $bg_pids
  for r in a b; do eq "$(cat "$fdir/$r.rc")" 0 "$r exit(stderr: $(cat "$fdir/$r.err"))" || return 1; done
  na=$(sed -E 's/.*\(#([0-9]+)\).*/\1/' "$fdir/a.out"); nb=$(sed -E 's/.*\(#([0-9]+)\).*/\1/' "$fdir/b.out")
  eq "$(printf '%s\n%s\n' "$na" "$nb" | sort | tr '\n' ' ')" "4 5 " "두 호출이 받은 연번(같으면 겹친 것)" || return 1
  has "$(serial)" "(#5)" "최종 연번" || return 1
  eq "$(jq -r '.rotated_serial' "$state")" true "rotated_serial" || return 1
  for r in a b; do  # 각 pane 의 마지막 이름표가 그 호출이 알린 연번과 같다
    p=$(sed -E 's/.*pane=([^ ]+) .*/\1/' "$fdir/$r.out"); n=$(sed -E 's/.*\(#([0-9]+)\).*/\1/' "$fdir/$r.out")
    last=$(calls | grep "^pane rename $p " | tail -1 | sed -E 's/.*\(#([0-9]+)\).*/\1/')
    eq "$last" "$n" "pane $p 의 마지막 이름표" || return 1
  done
}
t_serial_line_gone() {  # 연번 줄이 사라졌을 때: auto 는 프롬프트 전에 멈추고(exit 4), 일반 모드는 경고만 하고 끝낸다(새 세션은 이미 떠 있다)
  mkcase auto; extra=(FAKE_DROP_SERIAL_ON_START=1)
  rot demo "$handoff"
  eq "$rc" 4 "auto exit(stderr: $err)" || return 1
  eq "$(count '^agent prompt')" 0 "auto prompt 호출 수" || return 1
  has "$err" "연번 예약 실패" "auto stderr" || return 1
  has "$(calls)" "pane send-keys w1:p7 esc" "auto 호출 기록" || return 1
  eq "$(jq -r '.stopped_reason' "$state")" rotate-uncertain "auto stopped_reason" || return 1
  mkcase plain; extra=(FAKE_DROP_SERIAL_ON_PROMPT=1)
  rot demo "$handoff"
  eq "$rc" 0 "일반 모드 exit(stderr: $err)" || return 1
  has "$err" "경고: 세션 연번 줄을 찾지 못해" "일반 모드 stderr" || return 1
}
t_serial_bytes() {  # 연번 갱신은 연번 숫자 말고는 한 바이트도 바꾸지 않는다(CRLF 줄바꿈·깨진 바이트 포함)
  mkcase plain
  awk '{ printf "%s\r\n", $0 }' "$handoff" > "$work/crlf.md"
  printf '\377\376 깨진 바이트 줄\r\n' >> "$work/crlf.md"
  cp "$work/crlf.md" "$handoff"
  LC_ALL=C sed 's/(#3)/(#4)/' "$work/crlf.md" > "$work/want.md"
  rot demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  cmp -s "$handoff" "$work/want.md" || { why="연번 숫자 말고 다른 바이트가 바뀜"; return 1; }
}
t_codex_wait() {  # codex: auto 에서만 --until working --until blocked
  mkcase auto; extra=(ROTATE_KIND=codex)
  rot demo "$handoff"
  eq "$rc" 0 "auto exit(stderr: $err)" || return 1
  has "$(calls | grep '^agent prompt')" "--wait --until working --until blocked --timeout 120000" "auto codex prompt 인자" || return 1
  has "$(calls | grep '^agent start')" "--kind codex" "agent start" || return 1
  has "$(calls | grep '^agent prompt')" "바로 반복 본문에 들어가라" "전송한 프롬프트" || return 1
  mkcase plain; extra=(ROTATE_KIND=codex)
  rot demo "$handoff"
  eq "$rc" 0 "plain exit(stderr: $err)" || return 1
  lacks "$(calls | grep '^agent prompt')" "--until" "일반 모드 codex prompt 인자" || return 1
}

# ── 종료 코드
t_split_fail() {  # pane 분할 실패 = 새 세션 생성 전 = exit 1, 아무것도 바뀌지 않는다
  local m before
  for m in auto plain; do
    mkcase $m; extra=(FAKE_SPLIT_FAIL=1)
    before=$(cat "$handoff"; cat "$state" 2>/dev/null)
    rot demo "$handoff"
    eq "$rc" 1 "$m exit" || return 1
    eq "$(count '^agent start')" 0 "$m agent start 호출 수" || return 1
    eq "$(cat "$handoff"; cat "$state" 2>/dev/null)" "$before" "$m 인계 문서·state.json 변화" || return 1
  done
}
t_start_fail() {  # agent start 가 끝내 실패 = exit 1 + 만든 pane 닫기
  local m
  for m in auto plain; do
    mkcase $m; extra=(FAKE_START_FAIL_ALL=1)
    rot demo "$handoff"
    eq "$rc" 1 "$m exit" || return 1
    eq "$(count '^pane close w1:p7')" 1 "$m pane close 호출 수" || return 1
    eq "$(count '^agent prompt')" 0 "$m prompt 호출 수" || return 1
    eq "$(count '^agent start demo-4 ')" 6 "$m 첫 이름 재시도 수" || return 1
    eq "$(count '^agent start demo-4-t1 ')" 1 "$m 폴백 시도 수" || return 1
    has "$(serial)" "(#3)" "$m 연번(그대로)" || return 1
    eq "$(count 'send-keys')" 0 "$m send-keys 호출 수" || return 1
  done
}
t_prompt_fail_auto() {  # auto: 생성 뒤 전송 실패 = exit 4 + rotate-uncertain + 중단 줄 + esc
  mkcase auto; extra=(FAKE_PROMPT_FAIL=1)
  rot demo "$handoff"
  eq "$rc" 4 "exit(stderr: $err)" || return 1
  eq "$(jq -r '.stopped_reason' "$state")" rotate-uncertain "stopped_reason" || return 1
  eq "$(jq -r '.rotated_serial' "$state")" true "rotated_serial(연번은 이미 올렸다)" || return 1
  has "$(serial)" "(#4)" "연번" || return 1
  eq "$(grep -c '^중단: rotate-uncertain$' "$handoff")" 1 "중단 줄 수" || return 1
  eq "$(awk '/^```/{f++} /^중단: rotate-uncertain$/{if (f==1) print "in"}' "$handoff")" in "중단 줄 위치(재개 블록 코드 펜스 안)" || return 1
  order '^agent prompt demo-4 ' '^pane send-keys w1:p7 esc' || return 1
  has "$err" "새 pane(w1:p7)에 esc 를 보냈다" stderr || return 1
}
t_state_write_fail() {  # 연번은 올렸는데 state.json 기록이 실패 = prompt 는 보내지 않고 exit 4, 나머지 처리는 계속한다
  mkcase auto; extra=(FAKE_BREAK_STATE=1)
  rot demo "$handoff"
  eq "$rc" 4 "exit(stderr: $err)" || return 1
  eq "$(count '^agent prompt')" 0 "prompt 호출 수" || return 1
  has "$(calls)" "pane send-keys w1:p7 esc" "호출 기록" || return 1
  has "$(serial)" "(#4)" "연번" || return 1
  eq "$(grep -c '^중단: rotate-uncertain$' "$handoff")" 1 "중단 줄 수" || return 1
  has "$err" "state.json 갱신 실패" stderr || return 1
  lacks "$err" "에 esc 를 보냈다" "stderr(실패했는데 성공했다고 알리면 안 된다)" || return 1
}
t_esc_fail() {  # esc 전송이 실패해도 나머지 기록은 남기고 exit 4, 직접 멈추라고 알린다
  mkcase auto; extra=(FAKE_PROMPT_FAIL=1 FAKE_SENDKEYS_FAIL=1)
  rot demo "$handoff"
  eq "$rc" 4 "exit" || return 1
  eq "$(jq -r '.stopped_reason' "$state")" rotate-uncertain "stopped_reason" || return 1
  has "$err" "esc 전송 실패" stderr || return 1
  lacks "$err" "에 esc 를 보냈다" "stderr" || return 1
}
t_prompt_fail_twice() {  # 중단 줄은 두 번 실패해도 한 줄이다
  mkcase auto; extra=(FAKE_PROMPT_FAIL=1)
  rot demo "$handoff"; rot demo "$handoff"
  eq "$rc" 4 "두 번째 exit" || return 1
  eq "$(grep -c '^중단:' "$handoff")" 1 "중단 줄 수" || return 1
  has "$(serial)" "(#5)" "연번" || return 1
}
t_prompt_fail_plain() {  # 일반 모드는 지금 그대로: exit 1, 연번 유지, state.json·esc 없음
  mkcase plain; extra=(FAKE_PROMPT_FAIL=1)
  rot demo "$handoff"
  eq "$rc" 1 "exit" || return 1
  has "$(serial)" "(#3)" "연번(그대로)" || return 1
  [ ! -e "$work/docs/relay/demo/goal" ] || { why="goal 폴더가 생김"; return 1; }
  eq "$(count 'send-keys')" 0 "send-keys 호출 수" || return 1
  lacks "$(cat "$handoff")" "중단:" "인계 문서" || return 1
  has "$err" "세션 연번은 갱신하지 않았다" stderr || return 1
}
t_input_errors() {  # 입력 오류 = exit 2, herdr 호출 없음
  mkcase auto; rm "$state"
  rot demo "$handoff"
  eq "$rc" 2 "state.json 없음 exit" || return 1
  has "$err" "state.json" stderr || return 1
  untouched || return 1
  echo '[1,2]' > "$state"
  rot demo "$handoff"
  eq "$rc" 2 "state.json 이 객체가 아님 exit" || return 1
  untouched || return 1
  rot demo
  eq "$rc" 2 "인자 부족 exit" || return 1
  rot --bogus demo "$handoff"
  eq "$rc" 2 "모르는 옵션 exit" || return 1
  untouched || return 1
}
t_outside_herdr() {  # herdr 밖에서 --print-prompt 없이 부르면 exit 3
  mkcase plain; no_herdr_env=1
  rot demo "$handoff"
  eq "$rc" 3 "exit" || return 1
  untouched || return 1
}

# ── 공통 버그 수정
t_name_taken() {  # 이름 충돌 = 재시도(sleep) 없이 바로 폴백, prompt 도 폴백 이름으로
  local m
  for m in auto plain; do
    mkcase $m; extra=(FAKE_TAKEN_NAME=demo-4)
    rot demo "$handoff"
    eq "$rc" 0 "$m exit(stderr: $err)" || return 1
    eq "$(count '^agent start demo-4 ')" 1 "$m 첫 이름 시도 수" || return 1
    eq "$(count '^agent start demo-4-t1 ')" 1 "$m 폴백 시도 수" || return 1
    eq "$(sleeps)" 0 "$m sleep 호출 수" || return 1
    eq "$(count '^agent prompt demo-4-t1 ')" 1 "$m 폴백 이름 prompt 수" || return 1
    eq "$(count '^agent prompt demo-4 ')" 0 "$m 옛 이름 prompt 수" || return 1
    has "$out" "agent=demo-4-t1" "$m stdout" || return 1
  done
}
t_other_pane() {  # 다른 pane 의 동명 에이전트는 존재로 세지 않는다 → 폴백 이름으로 prompt
  mkcase auto; extra=(FAKE_BUSY_NAME=demo-4)
  printf 'demo-4\tw9:p9\n' > "$fdir/agents"
  rot demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  eq "$(count '^agent start demo-4 ')" 6 "첫 이름 재시도 수(일반 오류는 재시도한다)" || return 1
  eq "$(count '^agent start demo-4-t1 ')" 1 "폴백 시도 수" || return 1
  eq "$(count '^agent prompt demo-4-t1 ')" 1 "폴백 이름 prompt 수" || return 1
  eq "$(count '^agent prompt demo-4 ')" 0 "다른 pane 에이전트로 간 prompt 수" || return 1
}
t_same_pane() {  # agent start 가 오류를 내도(예: agent_not_ready) 이 pane 에 떠 있으면 폴백하지 않는다
  mkcase auto; extra=(FAKE_BUSY_NAME=demo-4)
  printf 'demo-4\tw1:p7\n' > "$fdir/agents"
  rot demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  eq "$(count '^agent start demo-4-t1 ')" 0 "폴백 시도 수" || return 1
  eq "$(count '^agent prompt demo-4 ')" 1 "prompt 수" || return 1
}
t_herdr_bin() {  # ROTATE_HERDR_BIN 이 지정한 실행 파일로 모든 herdr 호출이 간다
  mkcase plain; herdr_path="$tmp/alt/herdr"
  rot demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  [ -s "$fdir/alt.log" ] || { why="alt herdr 가 호출되지 않음"; return 1; }
  eq "$(grep -c . "$fdir/alt.log")" "$(grep -c . "$fdir/calls.log")" "alt 호출 수와 전체 호출 수" || return 1
}

run() { why=; if "t_$1"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: ${why:-조건 불일치}"; fi; }
for t in print_claude print_codex print_plain print_position print_missing auto_detect \
         serial_auto serial_plain serial_locked serial_race_values serial_bytes claim_concurrent serial_line_gone codex_wait \
         split_fail start_fail prompt_fail_auto prompt_fail_twice prompt_fail_plain state_write_fail esc_fail input_errors outside_herdr \
         name_taken other_pane same_pane herdr_bin; do run "$t"; done
echo "시험 $((pass + fail))개 · 실패 ${fail}개"
[ "$fail" -eq 0 ]
