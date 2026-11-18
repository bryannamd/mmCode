#!/usr/bin/env bash
# rotate.sh 시험. 가짜 hc 와 임시 폴더에서만 돈다 — 실제 hc·Herdr·저장소·홈을 건드리지 않는다.
# 사용: tests/relay/rotate.test.sh   (어느 위치에서 불러도 된다. 시험 대상을 바꾸려면 ROTATE_SH=<경로>)
# 종료 코드: 0 = 전부 통과 · 1 = 실패 있음 · 2 = 실행 환경 문제
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
rotate="${ROTATE_SH:-$root/plugins/mmcode/skills/relay/scripts/rotate.sh}"
for c in jq python3; do command -v "$c" >/dev/null || { echo "$c 이 없다" >&2; exit 2; }; done
[ -f "$rotate" ] || { echo "시험 대상 없음: $rotate" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/rotate-test.XXXXXX")"
case "$tmp" in */rotate-test.*) trap 'rm -rf "$tmp"' EXIT ;; *) echo "임시 폴더 생성 실패" >&2; exit 2 ;; esac

# ── 가짜 hc: 호출을 $FAKE_DIR/calls.log 에 남기고 정해진 JSON 을 돌려준다. PATH 앞에 둬서 진짜 hc 는 닿지 않는다.
fakebin="$tmp/fakebin"; mkdir -p "$fakebin" "$tmp/alt" "$tmp/home"
cat > "$fakebin/hc" <<'FAKE'
#!/usr/bin/env bash
d=${FAKE_DIR:?}
echo "$*" >> "$d/calls.log"
fail() { echo "{\"error\":{\"kind\":\"$1\",\"message\":\"fake $1\"}}" >&2; exit "${2:-1}"; }
barrier() {  # barrier <이름>: FAKE_BARRIER 개 호출이 모두 도착할 때까지 기다린다(최대 10초). 동시 호출 시험에서만 쓴다.
  [ -n "${FAKE_BARRIER:-}" ] || return 0
  touch "$d/bar.$1.$$"; local i=0
  while [ "$(ls "$d" | grep -c "^bar[.]$1[.]")" -lt "$FAKE_BARRIER" ] && [ "$i" -lt 500 ]; do command -p sleep 0.02; i=$((i + 1)); done
}
name=; prev=
for a in "$@"; do [ "$prev" = --name ] && name=$a; prev=$a; done
case "${1:-}" in
  get)
    # 새 터미널(t1 이 아닌 주소)의 상태를 FAKE_TERM_STATUS(hc get 의 status 객체 JSON)로 정한다
    if [ "${3:-}" != t1 ] && [ -n "${FAKE_TERM_STATUS:-}" ]; then echo "{\"address\":\"$3\",\"labels\":{},\"state\":\"live\",\"status\":$FAKE_TERM_STATUS,\"turn\":0}"
    elif [ -n "${FAKE_NO_LABELS:-}" ]; then echo '{"address":"t1","labels":{},"state":"live","status":null,"turn":0}'
    else echo '{"address":"t1","labels":{"herdr.space":"s1","herdr.tab":"tab1","where":"sp / tb"},"state":"live","status":{"app":"claude-code","state":"working"},"turn":3}'; fi ;;
  run)
    [ -z "${FAKE_RUN_FAIL:-}" ] || fail spawn_failed
    [ "$name" != "${FAKE_TAKEN_NAME:-}" ] || fail name_taken
    if awk -F'\t' -v n="$name" '$1 == n { f = 1 } END { exit !f }' "$d/agents" 2>/dev/null; then fail name_taken; fi   # 실제 hc 처럼 살아 있는 터미널 이름은 유일하다
    barrier run
    addr=t7   # 장벽을 쓰는(동시 호출) 시험에서는 호출마다 다른 주소를 돌려준다
    if [ -n "${FAKE_BARRIER:-}" ]; then k=1; while ! mkdir "$d/term.$k" 2>/dev/null; do k=$((k + 1)); done; addr="t$((6 + k))"; fi
    printf '%s\t%s\n' "$name" "$addr" >> "$d/agents"
    [ -z "${FAKE_BREAK_STATE:-}" ] || echo '[1]' > "${FAKE_STATE:?}"
    [ -z "${FAKE_DROP_SERIAL_ON_START:-}" ] || { grep -v '^세션 연번:' "$FAKE_HANDOFF" > "$FAKE_HANDOFF.new"; mv "$FAKE_HANDOFF.new" "$FAKE_HANDOFF"; }
    [ -z "${FAKE_RUN_STDERR:-}" ] || echo "warning: fake notice on stderr" >&2   # 성공인데 stderr 에 경고가 섞인 상황
    echo "{\"address\":\"$addr\",\"agent\":\"claude\",\"cwd\":\"$PWD\",\"name\":\"$name\",\"state\":\"live\",\"turn\":0}" ;;
  wait)
    case "${FAKE_WAIT:-}" in
      timeout) echo "{\"children\":[],\"ended\":false,\"reason\":\"timeout\",\"status\":\"working\",\"terminal\":\"$2\",\"turn\":0}" ;;
      blocked) echo "{\"children\":[],\"ended\":true,\"reason\":\"status\",\"status\":\"blocked\",\"terminal\":\"$2\",\"turn\":0}" ;;
      message-once)   # 첫 대기는 나에게 온 메시지로 끊기고, 다음 대기는 정상으로 돌아온다
        if mkdir "$d/msg.done" 2>/dev/null; then echo "{\"children\":[],\"ended\":false,\"reason\":\"message\",\"status\":null,\"terminal\":\"$2\",\"turn\":0}"
        else echo "{\"children\":[],\"ended\":true,\"reason\":\"status\",\"status\":\"idle\",\"terminal\":\"$2\",\"turn\":0}"; fi ;;
      message) echo "{\"children\":[],\"ended\":false,\"reason\":\"message\",\"status\":null,\"terminal\":\"$2\",\"turn\":0}" ;;
      *) echo "{\"children\":[],\"ended\":true,\"exit_code\":null,\"reason\":\"status\",\"signal\":null,\"status\":\"idle\",\"terminal\":\"$2\",\"turn\":0}" ;;
    esac ;;
  send)
    grep -E '세션 연번' "${FAKE_HANDOFF:?}" > "$d/serial.at-prompt" || true
    cp "${FAKE_STATE:?}" "$d/state.at-prompt" 2>/dev/null || true
    if [ -n "${FAKE_SERIAL_DURING_PROMPT:-}" ]; then   # 전송과 연번 갱신 사이에 다른 쪽이 연번을 바꾼 상황
      sed "s/^세션 연번: demo (#[0-9]*)/세션 연번: demo (#${FAKE_SERIAL_DURING_PROMPT})/" "$FAKE_HANDOFF" > "$FAKE_HANDOFF.new" && mv "$FAKE_HANDOFF.new" "$FAKE_HANDOFF"
    fi
    [ -z "${FAKE_DROP_SERIAL_ON_PROMPT:-}" ] || { grep -v '^세션 연번:' "$FAKE_HANDOFF" > "$FAKE_HANDOFF.new"; mv "$FAKE_HANDOFF.new" "$FAKE_HANDOFF"; }
    [ -z "${FAKE_PROMPT_FAIL:-}" ] || fail blocked 9
    if [ -n "${FAKE_SEND_MESSAGE:-}" ]; then echo '{"started":true,"status":"idle","turn":0,"wait":{"ended":false,"reason":"message","status":"working","turn":0}}'
    elif [ -n "${FAKE_SEND_TIMEOUT:-}" ]; then echo '{"started":true,"status":"idle","turn":0,"wait":{"ended":false,"reason":"timeout","status":"working","turn":0}}'
    else echo '{"started":true,"status":"idle","turn":0,"wait":{"ended":true,"reason":"status","status":"done","turn":1}}'; fi ;;
  keys)
    [ -z "${FAKE_SENDKEYS_FAIL:-}" ] || fail keys_failed
    echo '{"status":null,"turn":0}' ;;
  label) barrier label; touch "$d/renamed"; echo '{}' ;;
  kill) echo '{"state":"finished"}' ;;
  rm) echo "{\"removed\":\"$2\"}" ;;
  *) echo "fake hc: 모르는 호출 $*" >&2; exit 64 ;;
esac
FAKE
# sleep 은 기록만 하고 바로 돌아온다(재시도가 없는지 세고, 시험을 빠르게 한다).
cat > "$fakebin/sleep" <<'FAKE'
#!/bin/sh
echo "$*" >> "${FAKE_DIR:?}/sleeps.log"
FAKE
# ROTATE_HC_BIN 이 쓰이는지 보는 얇은 껍데기: 호출을 alt.log 에 남기고 가짜 hc 로 넘긴다.
cat > "$tmp/alt/hc" <<FAKE
#!/bin/sh
echo "\$*" >> "\${FAKE_DIR:?}/alt.log"
exec "$fakebin/hc" "\$@"
FAKE
chmod +x "$fakebin/hc" "$fakebin/sleep" "$tmp/alt/hc"
# 다른 쪽 쓰기 주체(eval-goal.sh 역할): goal/.lock 을 쥐고 인계 문서를 읽은 뒤, 오래 걸려 옛 내용 기준으로 통째로 되쓴다.
cat > "$tmp/writer.py" <<'PY'
import fcntl, os, sys, time
lock_path, handoff, held, renamed = sys.argv[1:5]
f = open(lock_path, 'a'); fcntl.flock(f, fcntl.LOCK_EX)
stale = open(handoff, encoding='utf-8').read()
open(held, 'w').close()
for _ in range(500):                      # rotate.sh 가 연번 갱신 직전(hc label)에 올 때까지 기다린다. 최대 10초
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
  extra=(); no_hc_env=; hc_path="$fakebin/hc"; bg_pids=
}
rot() {  # rot <rotate.sh 인자...>: 격리된 환경에서 돌린다. 결과: $out(stdout) $err(stderr) $rc
  local e=("PATH=$fakebin:$PATH" "HOME=$tmp/home" "ROTATE_HC_BIN=$hc_path" "FAKE_DIR=$fdir" "FAKE_HANDOFF=$handoff" "FAKE_STATE=$state")
  [ -n "$no_hc_env" ] || e+=("HC_TERMINAL_ID=t1")
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
  [ ! -e "$fdir/calls.log" ] || { why="hc 가 호출됨"; return 1; }
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
  mkcase auto; extra=(ROTATE_KIND=claude)
  local before; before=$(cksum < "$handoff"; cksum < "$state")
  rot --print-prompt demo "$handoff" docs/relay/demo/PLAN.md
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  has "$out" "등록만 하고 턴을 끝내라" stdout || return 1
  lacks "$out" "바로 반복 본문에 들어가라" stdout || return 1
  has "$out" "$handoff 의 재개 지시부터 진행" stdout || return 1
  has "$out" "계획: docs/relay/demo/PLAN.md." stdout || return 1
  has "$out" "$state" stdout || return 1
  has "$out" "이전 세션 터미널 t1 는 hc get 으로 idle·done 확인 후 hc kill 뒤 hc rm 으로 닫을 것." stdout || return 1
  eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1 "stdout 줄 수" || return 1
  untouched || return 1
  eq "$(cksum < "$handoff"; cksum < "$state")" "$before" "인계 문서·state.json 변화" || return 1
}
t_print_codex() {
  mkcase auto; extra=(ROTATE_KIND=codex); no_hc_env=1
  rot --print-prompt demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  has "$out" "바로 반복 본문에 들어가라" stdout || return 1
  lacks "$out" "턴을 끝내라" stdout || return 1
  lacks "$out" "등록만" stdout || return 1
  untouched || return 1
}
t_print_plain() {
  mkcase plain; no_hc_env=1
  rot --print-prompt demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  has "$out" "첫 응답에 status.sh 상태표를 표시할 것." stdout || return 1
  lacks "$out" "모드 auto" stdout || return 1
  lacks "$out" "반복 본문" stdout || return 1
  lacks "$out" "턴을 끝내라" stdout || return 1
  untouched || return 1
}
t_print_position() {  # 옵션 위치는 어디든 되고, 이전 터미널 주소를 모르면 그 문장을 뺀다
  mkcase plain; no_hc_env=1
  rot demo "$handoff" --print-prompt
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  lacks "$out" "이전 세션 터미널" stdout || return 1
  lacks "$out" "hc kill" stdout || return 1
}
t_auto_detect() {  # '모드: auto' 줄 판정: 들여쓰기·뒤 설명은 auto, 주석·다른 낱말은 auto 가 아니다
  local v
  mkcase plain; no_hc_env=1
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
  mkcase plain; no_hc_env=1
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
  order '^get .*t1' '^run .*--name demo-4 ' '^wait t7 ' '^label t7 relay=demo (#4)' '^send .* t7 ' || return 1
  local p; p=$(calls | grep '^send')
  has "$p" "--wait --timeout 120 " "claude send 인자" || return 1
  has "$(calls | grep '^run')" "-- claude" "run 명령" || return 1
  has "$out" "교체 완료: terminal=t7 name=demo-4 (#4)" stdout || return 1
}
t_serial_plain() {  # 일반 모드: 전송 뒤에 갱신하고 state.json 은 만들지 않는다
  mkcase plain
  rot demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  has "$(cat "$fdir/serial.at-prompt")" "(#3)" "prompt 시점 연번(아직 그대로)" || return 1
  has "$(serial)" "(#4)" "최종 연번" || return 1
  [ ! -e "$work/docs/relay/demo/goal" ] || { why="goal 폴더가 생김"; return 1; }
  has "$(calls | grep '^send')" "--wait --timeout 120 " "send 인자" || return 1
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
  [ "$(sed -E 's/.*terminal=([^ ]+) .*/\1/' "$fdir/a.out")" != "$(sed -E 's/.*terminal=([^ ]+) .*/\1/' "$fdir/b.out")" ] || { why="두 호출이 같은 터미널 주소"; return 1; }
  for r in a b; do  # 각 터미널의 마지막 표시 라벨이 그 호출이 알린 연번과 같다
    p=$(sed -E 's/.*terminal=([^ ]+) .*/\1/' "$fdir/$r.out"); n=$(sed -E 's/.*\(#([0-9]+)\).*/\1/' "$fdir/$r.out")
    last=$(calls | grep "^label $p " | tail -1 | sed -E 's/.*\(#([0-9]+)\).*/\1/')
    eq "$last" "$n" "터미널 $p 의 마지막 표시 라벨" || return 1
  done
}
t_serial_line_gone() {  # 연번 줄이 사라졌을 때: auto 는 프롬프트 전에 멈추고(exit 4), 일반 모드는 경고만 하고 끝낸다(새 세션은 이미 떠 있다)
  mkcase auto; extra=(FAKE_DROP_SERIAL_ON_START=1)
  rot demo "$handoff"
  eq "$rc" 4 "auto exit(stderr: $err)" || return 1
  eq "$(count '^send')" 0 "auto send 호출 수" || return 1
  has "$err" "연번 예약 실패" "auto stderr" || return 1
  has "$(calls)" "keys t7 esc" "auto 호출 기록" || return 1
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
t_codex_wait() {  # 전송 대기: auto codex 는 전송 시작만(20초), 그 밖은 턴 종료까지(120초)
  mkcase auto; extra=(ROTATE_KIND=codex)
  rot demo "$handoff"
  eq "$rc" 0 "auto exit(stderr: $err)" || return 1
  has "$(calls | grep '^send')" "--wait --timeout 20 " "auto codex send 인자" || return 1
  has "$(calls | grep '^run')" "-- codex --no-daemon" "run 명령" || return 1
  has "$(calls | grep '^send')" "바로 반복 본문에 들어가라" "전송한 프롬프트" || return 1
  mkcase auto; extra=(ROTATE_KIND=codex FAKE_SEND_TIMEOUT=1)
  rot demo "$handoff"
  eq "$rc" 0 "auto codex 턴 대기 초과 exit(stderr: $err)" || return 1
  mkcase plain; extra=(ROTATE_KIND=codex)
  rot demo "$handoff"
  eq "$rc" 0 "plain exit(stderr: $err)" || return 1
  has "$(calls | grep '^send')" "--wait --timeout 120 " "일반 모드 codex send 인자" || return 1
  mkcase auto; extra=(FAKE_SEND_TIMEOUT=1)
  rot demo "$handoff"
  eq "$rc" 4 "auto claude 턴 대기 초과 exit(stderr: $err)" || return 1
  mkcase plain; extra=(FAKE_SEND_TIMEOUT=1)
  rot demo "$handoff"
  eq "$rc" 1 "일반 모드 claude 턴 대기 초과 exit(stderr: $err)" || return 1
  has "$(serial)" "(#3)" "일반 모드 대기 초과 연번(그대로)" || return 1
}
t_labels() {  # 내 탭 라벨이 있으면 같은 탭에 보이게 붙이고, 없으면 붙이지 않고 알린다. 새 세션은 부모 없이 띄운다
  local r
  mkcase plain
  rot demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  r=$(calls | grep '^run')
  has "$r" "--label herdr.space=s1" "run 인자" || return 1
  has "$r" "--label herdr.tab=tab1" "run 인자" || return 1
  has "$r" "--no-parent" "run 인자" || return 1
  lacks "$err" "화면에 보이지 않는" stderr || return 1
  mkcase plain; extra=(FAKE_NO_LABELS=1)
  rot demo "$handoff"
  eq "$rc" 0 "라벨 없음 exit(stderr: $err)" || return 1
  r=$(calls | grep '^run')
  lacks "$r" "--label" "라벨 없음 run 인자" || return 1
  has "$r" "--no-parent" "라벨 없음 run 인자" || return 1
  has "$err" "화면에 보이지 않는 터미널로 띄운다" "라벨 없음 stderr" || return 1
}

# ── 종료 코드
t_start_fail() {  # hc run 실패 = 새 세션 생성 전 = exit 1, 재시도 없음, 아무것도 바뀌지 않는다
  local m before
  for m in auto plain; do
    mkcase $m; extra=(FAKE_RUN_FAIL=1)
    before=$(cat "$handoff"; cat "$state" 2>/dev/null)
    rot demo "$handoff"
    eq "$rc" 1 "$m exit" || return 1
    eq "$(count '^run ')" 1 "$m run 호출 수" || return 1
    eq "$(sleeps)" 0 "$m sleep 호출 수" || return 1
    eq "$(count '^send')" 0 "$m send 호출 수" || return 1
    has "$(serial)" "(#3)" "$m 연번(그대로)" || return 1
    eq "$(cat "$handoff"; cat "$state" 2>/dev/null)" "$before" "$m 인계 문서·state.json 변화" || return 1
  done
}
t_not_ready() {  # 새 세션이 준비되지 않음(대기 초과·blocked) = 터미널 정리 + exit 1, 프롬프트 없음, 연번 그대로
  local m w
  for w in timeout blocked; do for m in auto plain; do
    mkcase $m; extra=(FAKE_WAIT=$w)
    rot demo "$handoff"
    eq "$rc" 1 "$w $m exit(stderr: $err)" || return 1
    order '^wait t7 ' '^kill t7' '^rm t7' || return 1
    eq "$(count '^send')" 0 "$w $m send 호출 수" || return 1
    has "$(serial)" "(#3)" "$w $m 연번(그대로)" || return 1
    has "$err" "status=" "$w $m stderr" || return 1
  done; done
}
t_not_ready_reason() {  # 잡을 결함: 준비 실패 문구에 멈춘 이유(hc get 의 kind·msg)가 없어 신뢰 확인 창인지 알 수 없다
  mkcase auto; extra=(FAKE_WAIT=blocked 'FAKE_TERM_STATUS={"app":"claude-code","kind":"permission","msg":"trust this folder","state":"blocked"}')
  rot demo "$handoff"
  eq "$rc" 1 "exit(stderr: $err)" || return 1
  has "$err" "status=blocked kind=permission msg=trust this folder" stderr || return 1
  has "$err" "claude를 한 번 열어 신뢰를 승인한 뒤 다시 시도" stderr || return 1
  order '^get --json t7' '^kill t7' '^rm t7' || return 1
  mkcase plain; extra=(FAKE_WAIT=timeout 'FAKE_TERM_STATUS={"app":"claude-code","kind":"question","msg":"pick one","state":"blocked"}')
  rot demo "$handoff"
  has "$err" "kind=question msg=pick one" "질문 stderr" || return 1
  lacks "$err" "신뢰를 승인" "질문 stderr" || return 1
}
t_wait_message() {  # 준비 대기가 나에게 온 메시지로 끊기면 다시 기다린다. 계속 끊기면(3회) 준비 실패로 본다
  mkcase plain; extra=(FAKE_WAIT=message-once)
  rot demo "$handoff"
  eq "$rc" 0 "한 번 끊김 exit(stderr: $err)" || return 1
  eq "$(count '^wait t7 ')" 2 "한 번 끊김 wait 호출 수" || return 1
  eq "$(count '^kill')" 0 "한 번 끊김 kill 호출 수" || return 1
  has "$(serial)" "(#4)" "한 번 끊김 연번" || return 1
  mkcase plain; extra=(FAKE_WAIT=message)
  rot demo "$handoff"
  eq "$rc" 1 "계속 끊김 exit" || return 1
  eq "$(count '^wait t7 ')" 3 "계속 끊김 wait 호출 수" || return 1
  eq "$(count '^kill t7')" 1 "계속 끊김 kill 호출 수" || return 1
}
t_send_message() {  # 전송 뒤 대기가 메시지로 끊기면 턴 종료를 다시 기다린 뒤 판정한다
  mkcase auto; extra=(FAKE_SEND_MESSAGE=1)
  rot demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  eq "$(count '^wait t7 ')" 2 "wait 호출 수(준비 1 + 전송 뒤 1)" || return 1
  eq "$(count '^keys')" 0 "keys 호출 수" || return 1
}
t_run_stderr() {  # hc run 이 성공하면서 stderr 에 경고를 찍어도 주소를 읽는다
  mkcase plain; extra=(FAKE_RUN_STDERR=1)
  rot demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  has "$out" "terminal=t7" stdout || return 1
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
  order '^send .* t7 ' '^keys t7 esc' || return 1
  has "$err" "새 터미널(t7)에 esc 를 보냈다" stderr || return 1
}
t_state_write_fail() {  # 연번은 올렸는데 state.json 기록이 실패 = prompt 는 보내지 않고 exit 4, 나머지 처리는 계속한다
  mkcase auto; extra=(FAKE_BREAK_STATE=1)
  rot demo "$handoff"
  eq "$rc" 4 "exit(stderr: $err)" || return 1
  eq "$(count '^send')" 0 "send 호출 수" || return 1
  has "$(calls)" "keys t7 esc" "호출 기록" || return 1
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
  eq "$(count '^keys')" 0 "keys 호출 수" || return 1
  lacks "$(cat "$handoff")" "중단:" "인계 문서" || return 1
  has "$err" "세션 연번은 갱신하지 않았다" stderr || return 1
}
t_input_errors() {  # 입력 오류 = exit 2, hc 호출 없음
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
t_outside_herdr() {  # Herdr 밖(HC_TERMINAL_ID 없음)에서 --print-prompt 없이 부르면 exit 3
  mkcase plain; no_hc_env=1
  rot demo "$handoff"
  eq "$rc" 3 "exit" || return 1
  untouched || return 1
}

# ── 공통 버그 수정
t_name_taken() {  # 이름 충돌 = 재시도(sleep) 없이 바로 폴백, 이후 호출은 폴백 터미널 주소로
  local m
  for m in auto plain; do
    mkcase $m; extra=(FAKE_TAKEN_NAME=demo-4)
    rot demo "$handoff"
    eq "$rc" 0 "$m exit(stderr: $err)" || return 1
    eq "$(count '^run .*--name demo-4 ')" 1 "$m 첫 이름 시도 수" || return 1
    eq "$(count '^run .*--name demo-4-t1 ')" 1 "$m 폴백 시도 수" || return 1
    eq "$(sleeps)" 0 "$m sleep 호출 수" || return 1
    eq "$(count '^wait t7 ')" 1 "$m 폴백 터미널 wait 수" || return 1
    eq "$(count '^send .* t7 ')" 1 "$m 폴백 터미널 send 수" || return 1
    eq "$(count '^send .* demo-4')" 0 "$m 이름으로 겨냥한 send 수" || return 1
    has "$out" "terminal=t7 name=demo-4-t1" "$m stdout" || return 1
  done
}
t_hc_bin() {  # ROTATE_HC_BIN 이 지정한 실행 파일로 모든 hc 호출이 간다
  mkcase plain; hc_path="$tmp/alt/hc"
  rot demo "$handoff"
  eq "$rc" 0 "exit(stderr: $err)" || return 1
  [ -s "$fdir/alt.log" ] || { why="alt hc 가 호출되지 않음"; return 1; }
  eq "$(grep -c . "$fdir/alt.log")" "$(grep -c . "$fdir/calls.log")" "alt 호출 수와 전체 호출 수" || return 1
}

run() { why=; if "t_$1"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: ${why:-조건 불일치}"; fi; }
for t in print_claude print_codex print_plain print_position print_missing auto_detect \
         serial_auto serial_plain serial_locked serial_race_values serial_bytes claim_concurrent serial_line_gone codex_wait labels \
         start_fail not_ready prompt_fail_auto prompt_fail_twice prompt_fail_plain state_write_fail esc_fail input_errors outside_herdr \
         name_taken hc_bin wait_message send_message run_stderr not_ready_reason; do run "$t"; done
echo "시험 $((pass + fail))개 · 실패 ${fail}개"
[ "$fail" -eq 0 ]
