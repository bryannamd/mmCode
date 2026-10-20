#!/usr/bin/env bash
# status.sh 시험. 임시 폴더에서만 돈다 — 실제 저장소·홈·herdr 를 건드리지 않는다.
# 사용: tests/relay/status.test.sh   (어느 위치에서 불러도 된다. 시험 대상을 바꾸려면 STATUS_SH=<경로>)
# 종료 코드: 0 = 전부 통과 · 1 = 실패 있음 · 2 = 실행 환경 문제
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
status="${STATUS_SH:-$root/plugins/mmcode/skills/relay/scripts/status.sh}"
command -v python3 >/dev/null || { echo "python3 이 없다" >&2; exit 2; }
[ -f "$status" ] || { echo "시험 대상 없음: $status" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/status-test.XXXXXX")"
case "$tmp" in */status-test.*) trap 'rm -rf "$tmp"' EXIT ;; *) echo "임시 폴더 생성 실패" >&2; exit 2 ;; esac

# <fixture-begin>
base=10
row() {  # row <단위> <가중치> <상태> <종료 시각>: 상태표 한 행
  printf '| %s | 내용%s | f | — | sonnet | ✘ | sonnet | r:p | %s | %s | %s | |\n' "$1" "$1" "$2" "$3" "$4"
}
mkh() {  # mkh <폴더> <상태표 행...>: <폴더>/HANDOFF.md 를 만든다
  local d=$1; shift
  mkdir -p "$d"
  {
    printf '%s\n' '# HANDOFF — demo' '' '## 재개 지시' '' '```text' '세션 연번: demo (#3)' '커밋 정책: 확인 후' '```' '' '## 상태표' '' \
      '| 단위 | 내용 | 파일 | 선행 | 모델 | 병렬 | 검수 | pathspec | 가중치 | 상태 | 종료 시각 | 커밋 |' '|---|---|---|---|---|---|---|---|---|---|---|---|'
    printf '%s\n' "$@"
    printf '%s\n' '' '## 진행률' "기준선: ${base}% (2026-10-20, 시험)"
  } > "$d/HANDOFF.md"
}
mkplain() {  # 완료 2 · 진행 1 · 미착수 1. 골든 출력의 바탕이다
  mkh "$1" "$(row U1 '' 완료 '2026-10-20 09:00')" "$(row U2 '' 완료 '2026-10-20 09:40')" "$(row U3 '' 진행 '')" "$(row U4 '' 미착수 '')"
}
# <fixture-end>

# 원본 status.sh 가 위 인계 문서에 내던 출력. state.json 이 없으면 이 출력 그대로여야 한다.
golden=$(cat <<'GOLDEN'
| 항목 | 값 |
|---|---|
| 세션 연번 | demo (#3) |
| 커밋 정책 | 확인 후 |
| 현재 단위 | U3 내용U3 |
| 완료 단위 | U1, U2 (2/4) |
| 남은 단위 | U3, U4 |
| 전체 진행률 | 약 55% (기준선 10% + 완료 가중치, ±10%p) |
| 단위 소요(최근) | 중앙값 40분 (Q1 40·Q3 40, 1표본, 4시간 초과 간격 제외) |
| 남은 시간 추정 | 80~80분 (중앙값 80분, 남은 2단위) |
GOLDEN
)

n=0; pass=0; fail=0; why=
mkdirs() { n=$((n + 1)); d="$tmp/case$n"; mkdir -p "$d"; }
st() {  # st <인계 문서>: 결과 $out(stdout+stderr) $rc
  rc=0; out=$(cd "$d" && "${BASH:-bash}" "$status" "$1" 2>&1) || rc=$?
}
mkstate() {  # mkstate <시작 시각> <반복> <최대 반복> <최대 시간> <중단 사유>: <d>/goal/state.json
  mkdir -p "$d/goal"
  printf '{"started_at":"%s","iterations":%s,"max_iterations":%s,"max_duration":"%s","stopped_reason":"%s"}\n' "$1" "$2" "$3" "$4" "$5" > "$d/goal/state.json"
}
ago() {  # ago <분> <z|offset>: 지금보다 <분>분 20초 전 시각(시간대 포함 ISO 8601)
  python3 -I -c '
import sys
from datetime import datetime, timedelta, timezone
t = datetime.now(timezone.utc) - timedelta(minutes=int(sys.argv[1]), seconds=20)
print(t.strftime("%Y-%m-%dT%H:%M:%SZ") if sys.argv[2] == "z" else t.astimezone(timezone(timedelta(hours=9))).isoformat(timespec="seconds"))
' "$1" "$2"
}
has()   { case "$1" in *"$2"*) return 0 ;; esac; why="${3:-출력}에 '$2' 없음"; return 1; }
lacks() { case "$1" in *"$2"*) why="${3:-출력}에 '$2' 있음"; return 1 ;; esac; return 0; }
eq()    { [ "$1" = "$2" ] || { why="$3: '$1' ≠ '$2'"; return 1; }; }

t_unchanged() {  # state.json 도 blocked 도 없으면 출력이 원본과 글자까지 같다
  mkdirs; mkplain "$d"; st "$d/HANDOFF.md"
  eq "$rc" 0 "exit" || return 1
  [ "$out" = "$golden" ] || { why="원본 출력과 다름: $(diff <(printf '%s\n' "$golden") <(printf '%s\n' "$out") | head -4 | tr '\n' ' ')"; return 1; }
}
t_state_row() {  # state.json 이 있으면 표 끝에 한 줄만 더한다(반복 · 경과/최대 시간)
  local z
  mkdirs; mkplain "$d"; mkstate "$(ago 90 offset)" 3 12 4h ""; st "$d/HANDOFF.md"
  eq "$rc" 0 "exit" || return 1
  eq "$(printf '%s\n' "$out" | head -n "$(printf '%s\n' "$golden" | wc -l | tr -d ' ')")" "$golden" "기존 줄" || return 1
  eq "$(printf '%s\n' "$out" | tail -n 1)" "| 경계 잔여 | 반복 3/12 · 경과 1h30m/4h |" "추가 줄" || return 1
  eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "$(( $(printf '%s\n' "$golden" | wc -l | tr -d ' ') + 1 ))" "전체 줄 수" || return 1
  z=$(ago 75 z); mkstate "$z" 0 6 2h30m ""; st "$d/HANDOFF.md"   # Z 로 끝나는 시각도 읽는다
  has "$out" "| 경계 잔여 | 반복 0/6 · 경과 1h15m/2h30m |" "Z 시각" || return 1
}
t_blocked() {  # blocked 는 미완료로 센다: 남은 단위·남은 시간 단위 수에 들어가고 blocked N 을 따로 보인다
  mkdirs; mkh "$d" "$(row U1 '' 완료 '2026-10-20 09:00')" "$(row U2 '' 완료 '2026-10-20 09:30')" "$(row U3 '' 완료 '2026-10-20 10:00')" "$(row U4 '' blocked '')" "$(row U5 '' 미착수 '')"
  st "$d/HANDOFF.md"
  eq "$rc" 0 "exit" || return 1
  has "$out" "| 완료 단위 | U1, U2, U3 (3/5) |" || return 1
  has "$out" "| 남은 단위 | U4, U5 (blocked 1: U4) |" || return 1
  has "$out" "| 현재 단위 | 다음: U4 내용U4 (blocked) |" || return 1
  has "$out" "남은 2단위" "남은 시간 추정 줄" || return 1
  has "$out" "blocked 1" || return 1
}
t_blocked_only() {  # blocked 단위가 둘이고 나머지가 끝났으면 둘 다 센다
  mkdirs; mkh "$d" "$(row U1 '' 완료 '2026-10-20 09:00')" "$(row U2 '' blocked '')" "$(row U3 '' blocked '')"
  st "$d/HANDOFF.md"
  has "$out" "| 남은 단위 | U2, U3 (blocked 2: U2, U3) |" || return 1
}
t_duration_seconds() {  # eval-goal.sh 가 쓰는 초 단위 정수 max_duration 도 '4h' 꼴로 보인다
  local pair sec want
  mkdirs; mkplain "$d"; mkdir -p "$d/goal"
  for pair in 14400:4h 5400:1h30m 600:10m 90:1m30s 45:45s 3661:1h1m; do
    sec=${pair%%:*}; want=${pair#*:}
    printf '{"started_at":"%s","iterations":1,"max_iterations":8,"max_duration":%s,"worker_timeout":1800,"stopped_reason":""}\n' "$(ago 90 offset)" "$sec" > "$d/goal/state.json"
    st "$d/HANDOFF.md"
    has "$out" "| 경계 잔여 | 반복 1/8 · 경과 1h30m/$want |" "max_duration=$sec" || return 1
  done
}
t_stop_shown() {  # 계획이 멈춘 사유는 state.json 에서 읽어 보인다
  mkdirs; mkh "$d" "$(row U1 '' 완료 '2026-10-20 09:00')" "$(row U2 '' 완료 '2026-10-20 09:30')"
  mkstate "$(ago 30 offset)" 5 12 4h "limit:duration"; st "$d/HANDOFF.md"
  eq "$rc" 0 "exit" || return 1
  has "$out" "| 경계 잔여 | 반복 5/12 · 경과 0h30m/4h · 계획 중단: limit:duration |" || return 1
  has "$out" "| 남은 단위 | 없음 |" || return 1
}
t_stop_hidden() {  # 비었거나 rotate·done 이면 중단으로 보이지 않는다. 경계 줄은 그대로 있다
  local r
  mkdirs; mkh "$d" "$(row U1 '' 완료 '2026-10-20 09:00')" "$(row U2 '' 완료 '2026-10-20 09:30')"
  for r in rotate done ""; do
    mkstate "$(ago 30 offset)" 5 12 4h "$r"; st "$d/HANDOFF.md"
    lacks "$out" "계획 중단" "stopped_reason='$r' 출력" || return 1
    has "$out" "| 경계 잔여 | 반복 5/12 · 경과 0h30m/4h |" "stopped_reason='$r' 출력" || return 1
  done
}
t_cap() {  # 미완료가 남으면 진행률은 99% 까지. 빈 가중치(0 으로 셈)로 100% 가 나오던 문제
  local save=$base
  base=0
  mkdirs; mkh "$d" "$(row U1 50 완료 '2026-10-20 09:00')" "$(row U2 50 완료 '2026-10-20 09:30')" "$(row U2-fix1 '' 미착수 '')"
  st "$d/HANDOFF.md"
  has "$out" "| 전체 진행률 | 약 99% " "보정 단위 미완료" || { base=$save; return 1; }
  mkdirs; mkh "$d" "$(row U1 100 완료 '2026-10-20 09:00')" "$(row U2 '' blocked '')"
  st "$d/HANDOFF.md"
  has "$out" "| 전체 진행률 | 약 99% " "blocked 단위가 남음" || { base=$save; return 1; }
  mkdirs; mkh "$d" "$(row U1 50 완료 '2026-10-20 09:00')" "$(row U2 50 완료 '2026-10-20 09:30')"
  st "$d/HANDOFF.md"
  base=$save
  has "$out" "| 전체 진행률 | 약 100% " "전부 완료" || return 1
}
t_malformed() {  # 깨진 state.json 은 조용히 넘기지 않고 한 줄로 알린다. 나머지 표는 그대로 나온다
  mkdirs; mkplain "$d"; mkdir -p "$d/goal"; echo '{broken' > "$d/goal/state.json"; st "$d/HANDOFF.md"
  eq "$rc" 0 "exit" || return 1
  has "$out" "| 경계 잔여 | goal/state.json 을 읽지 못함" || return 1
  has "$out" "| 완료 단위 | U1, U2 (2/4) |" || return 1
}

run() { why=; if "t_$1"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: ${why:-조건 불일치}"; fi; }
for t in unchanged state_row blocked blocked_only duration_seconds stop_shown stop_hidden cap malformed; do run "$t"; done
echo "시험 $((pass + fail))개 · 실패 ${fail}개"
[ "$fail" -eq 0 ]
