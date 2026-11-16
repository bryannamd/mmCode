#!/usr/bin/env bash
# phase.sh 시험. 임시 폴더의 git 저장소에서만 돈다. 실제 저장소·홈을 건드리지 않는다.
# 사용: tests/relay/phase.test.sh   (어느 위치에서 불러도 된다. 시험 대상을 바꾸려면 PHASE_SH=<경로>)
# 종료 코드: 0 = 전부 통과 · 1 = 실패 있음 · 2 = 실행 환경 문제
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
phase="${PHASE_SH:-$root/plugins/mmcode/skills/relay/scripts/phase.sh}"
status="$root/plugins/mmcode/skills/relay/scripts/status.sh"
command -v python3 >/dev/null || { echo "python3 이 없다" >&2; exit 2; }
command -v git >/dev/null || { echo "git 이 없다" >&2; exit 2; }
[ -f "$phase" ] || { echo "시험 대상 없음: $phase" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/phase-test.XXXXXX")"
case "$tmp" in */phase-test.*) trap 'rm -rf "$tmp"' EXIT ;; *) echo "임시 폴더 생성 실패" >&2; exit 2 ;; esac

# 홈과 전역 git 설정을 쓰지 않고, 부모 폴더의 저장소를 찾아 올라가지 않게 한다.
mkdir -p "$tmp/home"
export HOME="$tmp/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$tmp"
unset HC_TERMINAL_ID PHASE_HARNESS PHASE_MODEL PHASE_EFFORT

n=0; pass=0; fail=0; why=
# row <단위> <선행> <상태>: 상태표 한 행
row() { printf '| %s | 내용%s | f | %s | sonnet | ✘ | sonnet | r:p | 30 | %s | | |\n' "$1" "$1" "$2" "$3"; }
mkh() {  # mkh <폴더> <상태표 행...>: <폴더>/HANDOFF.md
  local dir=$1; shift
  mkdir -p "$dir"
  {
    printf '%s\n' '# HANDOFF demo' '' '## 재개 지시' '' '```text' '세션 연번: demo (#1)' '커밋 정책: 확인 후' '```' '' '## 상태표' '' \
      '| 단위 | 내용 | 파일 | 선행 | 모델 | 병렬 | 검수 | pathspec | 가중치 | 상태 | 종료 시각 | 커밋 |' '|---|---|---|---|---|---|---|---|---|---|---|---|'
    printf '%s\n' "$@"
    printf '%s\n' '' '## 진행률' '기준선: 10% (시험)' '' '## 이월' '- 없음'
  } > "$dir/HANDOFF.md"
}
mkcase() {  # 새 저장소와 기본 상태표(U1, U2 선행 U1, U3 선행 "U1, U2", U4 손으로 쓴 보류)
  n=$((n + 1)); d="$tmp/case$n"; mkdir -p "$d"; git init -q "$d"
  h="$d/docs/relay/demo/HANDOFF.md"
  mkh "$d/docs/relay/demo" "$(row U1 — 미착수)" "$(row U2 U1 미착수)" "$(row U3 'U1, U2' 미착수)" "$(row U4 — 보류)"
  ev="$d/.mmcode/events.jsonl"
  cp "$h" "$d/orig.md"
}
ph() { rc=0; out=$(cd "$d" && "${BASH:-bash}" "$phase" "$@" 2>&1) || rc=$?; }  # ph <하위 명령> <인자...>: $out $rc
php() { ph "$1" "$h" "${@:2}"; }                                              # php <하위 명령> <인자...>: 인계 문서 경로를 붙인다
cell() { awk -F'|' -v u="$1" -v k="$2" '{x=$2; gsub(/^ +| +$/, "", x)} x==u {y=$k; gsub(/^ +| +$/, "", y); print y}' "$h"; }  # cell <단위> <칸 번호>: 단위=2 상태=11 종료=12 커밋=13
nev() { [ -f "$ev" ] && wc -l < "$ev" | tr -d ' ' || echo 0; }
last() { printf '%s\n' "$out" | tail -n 1; }
has()   { case "$1" in *"$2"*) return 0 ;; esac; why="${3:-출력}에 '$2' 없음: $(printf '%s' "$1" | tail -n 3 | tr '\n' ' ')"; return 1; }
lacks() { case "$1" in *"$2"*) why="${3:-출력}에 '$2' 있음"; return 1 ;; esac; return 0; }
eq()    { [ "$1" = "$2" ] || { why="$3: '$1' ≠ '$2'"; return 1; }; }
okc()   { eq "$rc" 0 "${1:-exit}" || { why="$why / $out"; return 1; }; }          # 성공해야 한다
refc()  { eq "$rc" 1 "${1:-exit}" || { why="$why / $out"; return 1; }; has "$(last)" "REFUSED:" "마지막 줄" || return 1; }  # 거부해야 한다
to_verify() { php move "$1" build && [ "$rc" = 0 ] && php move "$1" verify && [ "$rc" = 0 ]; }
run_full() {  # run_full <단위> <저장소> <해시>: 대기에서 완료까지
  to_verify "$1" || return 1
  php check "$1" cmd -- true; [ "$rc" = 0 ] || return 1
  php move "$1" review; [ "$rc" = 0 ] || return 1
  php commit "$1" "$2" "$3"; [ "$rc" = 0 ] || return 1
  php move "$1" done; [ "$rc" = 0 ] || return 1
}

t_cycle() {  # 1. 대기에서 완료까지 한 바퀴
  mkcase
  export HC_TERMINAL_ID=t1 PHASE_MODEL=m1
  run_full U1 repo abc1234def5678; local r=$?
  unset HC_TERMINAL_ID PHASE_MODEL
  [ "$r" = 0 ] || { why="한 바퀴 중 실패: $out"; return 1; }
  eq "$(nev)" 6 "이벤트 줄 수" || return 1
  python3 -I -c '
import json, sys
ls = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
assert [e["type"] for e in ls] == ["unit.phase", "unit.phase", "check.result", "unit.phase", "unit.commit", "unit.phase"], "종류"
assert all(e["plan"] == "demo" and e["unit"] == "U1" for e in ls), "plan/unit"
assert ls[0]["actor"] == {"terminal": "t1", "model": "m1"}, ls[0]["actor"]
assert ls[0]["data"] == {"from": "queued", "to": "build"}, ls[0]["data"]
c = ls[2]["data"]
assert c["kind"] == "cmd" and c["pass"] is True and c["command"] == "true" and c["exit"] == 0, c
assert c["evidence"].startswith(".mmcode/logs/demo-U1-cmd-"), c["evidence"]
assert ls[4]["data"] == {"repo": "repo", "hash": "abc1234def5678"}, ls[4]["data"]
assert all(e["ts"][-6] in "+-" and len(e["ts"]) == 25 for e in ls), "시각 형식"
' "$ev" || { why="이벤트 내용 불일치"; return 1; }
  eq "$(cell U1 11)" 완료 "상태" || return 1
  [[ "$(cell U1 12)" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]] || { why="종료 시각 형식: $(cell U1 12)"; return 1; }
  eq "$(cell U1 13)" "repo abc1234" "커밋" || return 1
  eq "$(diff <(grep -v '^| U1 ' "$d/orig.md") <(grep -v '^| U1 ' "$h"))" "" "다른 행·절" || return 1
  eq "$(grep '^| U1 ' "$h" | cut -d'|' -f1-11)" "$(grep '^| U1 ' "$d/orig.md" | cut -d'|' -f1-10)| 완료 " "U1 의 바뀌지 않는 칸" || return 1
}

t_no_check() {  # 2. 검사 결과 없이 verify→review 는 거부. 이벤트 줄이 늘지 않는다
  mkcase; to_verify U1 || { why="준비 실패: $out"; return 1; }
  local before; before=$(nev)
  php move U1 review; refc || return 1
  eq "$(nev)" "$before" "이벤트 줄 수" || return 1
  eq "$(cell U1 11)" 진행 "상태" || return 1
}

t_fail_check() {  # 3. 실패한 검사는 1, 이벤트는 남는다. 전환 거부. 같은 명령이 통과하면 전환된다
  mkcase; to_verify U1 || { why="준비 실패"; return 1; }
  local before; before=$(nev)
  php check U1 cmd -- test -f "$d/flag"
  eq "$rc" 1 "실패 exit" || return 1
  has "$(last)" "FAILED: cmd" "마지막 줄" || return 1
  eq "$(nev)" "$((before + 1))" "이벤트 줄 수" || return 1
  has "$(tail -n 1 "$ev")" '"pass": false' "이벤트" || return 1
  php move U1 review; refc || return 1
  touch "$d/flag"
  php check U1 cmd -- test -f "$d/flag"; okc "재실행 exit" || return 1
  php move U1 review; okc "전환 exit" || return 1
  eq "$(cell U1 11)" 진행 "상태" || return 1
}

t_no_commit() {  # 4. 커밋 기록 없이 review→done 거부
  mkcase; to_verify U1 || { why="준비 실패"; return 1; }
  php check U1 cmd -- true; php move U1 review
  local before; before=$(nev)
  php move U1 done; refc || return 1
  eq "$(nev)" "$before" "이벤트 줄 수" || return 1
  php commit U1 repo '없음(변경 없음)'; okc "commit" || return 1
  php move U1 done; okc "done" || return 1
  eq "$(cell U1 13)" '없음(변경 없음)' "커밋 칸" || return 1
}

t_prereq() {  # 5. 선행 단위가 완료가 아니면 queued→build 거부
  mkcase
  php move U2 build; refc || return 1
  has "$out" "U1" "거부 이유" || return 1
  eq "$(nev)" 0 "이벤트 줄 수" || return 1
  run_full U1 repo abc1234 || { why="U1 완료 실패: $out"; return 1; }
  php move U3 build; refc "U3(U2 미완료)" || return 1
  php move U2 build; okc "U2" || return 1
}

t_skip_back() {  # 6. 건너뛰기 거부. 되돌아가기는 --reason 이 있어야 한다
  mkcase
  php move U1 verify; refc "queued→verify" || return 1
  php move U1 done; refc "queued→done" || return 1
  php move U1 build; okc "build" || return 1
  php move U1 review; refc "build→review" || return 1
  php move U1 verify; okc "verify" || return 1
  php move U1 build; refc "reason 없는 되돌리기" || return 1
  php move U1 build --reason "시험 실패"; okc "reason 있는 되돌리기" || return 1
  has "$(tail -n 1 "$ev")" '"reason": "시험 실패"' "이벤트" || return 1
  to_verify U1 2>/dev/null; php move U1 verify; php check U1 cmd -- true; php move U1 review; okc "review" || return 1
  php move U1 build; refc "review→build reason 없음" || return 1
  php move U1 build --reason "검수 지적"; okc "review→build" || return 1
}

t_halt() {  # 7. 멈춘 단위는 move 거부. 상태표에 보류·blocked. resume 뒤에는 된다
  mkcase
  php move U1 build; okc || return 1
  php halt U1 stop-after; okc "halt" || return 1
  eq "$(cell U1 11)" 보류 "stop-after 상태" || return 1
  php move U1 verify; refc "멈춘 단위" || return 1
  php halt U1 blocked:U1; okc "blocked" || return 1
  eq "$(cell U1 11)" blocked "blocked 상태" || return 1
  php show; okc "show" || return 1
  has "$out" '| U1 | 구현 | 단위 막힘 |' "show" || return 1
  php resume U1; okc "resume" || return 1
  eq "$(cell U1 11)" 진행 "resume 뒤 상태" || return 1
  php move U1 verify; okc "resume 뒤 전환" || return 1
  php resume U1; refc "멈추지 않은 단위의 resume" || return 1
  php halt U1 decision; okc "decision" || return 1
  php show; has "$out" '| U1 | 검증 | 결정 대기 |' "show" || return 1
}

t_untouched() {  # 8. 이벤트가 없는 단위의 행은 손으로 쓴 그대로. 이벤트가 있는 행은 show 가 다시 맞춘다
  mkcase
  run_full U1 repo abc1234 || { why="U1 실패"; return 1; }
  eq "$(grep '^| U4 ' "$h")" "$(grep '^| U4 ' "$d/orig.md")" "U4" || return 1
  eq "$(grep '^| U3 ' "$h")" "$(grep '^| U3 ' "$d/orig.md")" "U3" || return 1
  sed 's/^\(| U1 .*\)| 완료 |/\1| 미착수 |/' "$h" > "$d/x.md" && mv "$d/x.md" "$h"
  eq "$(cell U1 11)" 미착수 "손으로 바꾼 상태" || return 1
  php show; okc "show" || return 1
  has "$out" '| U1 | 완료 | - |' "show 출력" || return 1
  has "$out" '| U4 | 대기 | - |' "show 출력(상태표 전체)" || return 1
  eq "$(cell U1 11)" 완료 "show 뒤 상태" || return 1
  eq "$(grep '^| U4 ' "$h")" "$(grep '^| U4 ' "$d/orig.md")" "U4(show 뒤)" || return 1
}

t_ignored() {  # 9. .mmcode 는 git status 에 나오지 않는다
  mkcase
  run_full U1 repo abc1234 || { why="U1 실패"; return 1; }
  [ -f "$d/.mmcode/.gitignore" ] || { why=".mmcode/.gitignore 없음"; return 1; }
  eq "$(cat "$d/.mmcode/.gitignore")" '*' ".gitignore 내용" || return 1
  lacks "$(git -C "$d" status --porcelain --untracked-files=all)" ".mmcode" "git status" || return 1
}

t_usage() {  # 10. 사용 오류는 2, 상태표에 없는 단위는 거부(1)
  mkcase
  ph; eq "$rc" 2 "인자 없음" || return 1
  php bogus; eq "$rc" 2 "없는 하위 명령" || return 1
  php move U1; eq "$rc" 2 "move 인자 부족" || return 1
  php move U1 bogus; eq "$rc" 2 "없는 단계" || return 1
  php check U1 bogus --pass --reason x; eq "$rc" 2 "없는 종류" || return 1
  php check U1 cmd; eq "$rc" 2 "명령도 --pass 도 없음" || return 1
  php check U1 cmd --pass --reason x -- true; eq "$rc" 2 "명령과 --pass" || return 1
  php check U1 cmd --pass --reason x; eq "$rc" 2 "cmd 는 명령이 필수" || return 1
  php check U1 manual --pass; eq "$rc" 2 "--reason 없음" || return 1
  php commit U1 repo xyz; eq "$rc" 2 "나쁜 해시" || return 1
  php halt U1 bogus; eq "$rc" 2 "나쁜 멈춤 값" || return 1
  php halt U1 blocked:U2; eq "$rc" 2 "다른 단위의 blocked" || return 1
  ph move "$d/없는파일.md" U1 build; eq "$rc" 2 "없는 인계 문서" || return 1
  eq "$(nev)" 0 "사용 오류는 이벤트를 쓰지 않는다" || return 1
  php move U9 build; refc "없는 단위 move" || return 1
  php check U9 manual --pass --reason x; refc "없는 단위 check" || return 1
  php commit U9 repo abc1234; refc "없는 단위 commit" || return 1
  php halt U9 decision; refc "없는 단위 halt" || return 1
  php resume U9; refc "없는 단위 resume" || return 1
  eq "$(nev)" 0 "거부는 이벤트를 쓰지 않는다" || return 1
  # git 저장소가 아니면 2
  mkdir -p "$tmp/nogit/p"; mkh "$tmp/nogit/p"
  rc=0; out=$(cd "$tmp/nogit" && bash "$phase" show "$tmp/nogit/p/HANDOFF.md" 2>&1) || rc=$?
  eq "$rc" 2 "git 저장소 아님" || return 1
  # 상태표에 필요한 열이 없으면 2
  sed 's/ 종료 시각 |//' "$h" > "$d/docs/relay/demo/bad.md"
  ph show "$d/docs/relay/demo/bad.md"; eq "$rc" 2 "열 없음" || return 1
}

t_status() {  # 11. 갱신한 인계 문서에 status.sh 를 돌리면 0
  mkcase
  run_full U1 repo abc1234 || { why="U1 실패"; return 1; }
  php move U2 build; php halt U2 blocked:U2
  rc=0; out=$(bash "$status" "$h" 2>&1) || rc=$?
  eq "$rc" 0 "status.sh exit" || { why="$why / $out"; return 1; }
  has "$out" "| 완료 단위 | U1 (1/4) |" "status.sh" || return 1
  has "$out" "blocked 1: U2" "status.sh" || return 1
}

t_manual() {  # 보충: --pass/--fail 검사는 사유가 키다. 같은 사유를 다시 통과시키면 전환된다
  mkcase; to_verify U1 || { why="준비 실패"; return 1; }
  php check U1 manual --fail --reason "화면 확인" --evidence "$d/shot.png"
  eq "$rc" 1 "manual --fail" || return 1
  has "$(tail -n 1 "$ev")" '"evidence": "shot.png"' "증거 경로(프로젝트 기준)" || return 1
  php move U1 review; refc || return 1
  php check U1 manual --pass --reason "화면 확인"; okc "manual --pass" || return 1
  php move U1 review; okc "전환" || return 1
}

t_handguard() {  # 이벤트 없이 손으로 `완료`·`보류` 로 적은 단위는 쓰는 명령을 모두 거부한다. 표와 이벤트는 그대로
  mkcase
  mkh "$d/docs/relay/demo" "$(row U1 — 완료)" "$(row U2 U1 미착수)" "$(row U3 — 보류)"
  cp "$h" "$d/orig.md"
  local c
  for c in "move U1 build" "halt U1 decision" "commit U1 repo abc1234" "check U1 manual --pass --reason x" "check U1 cmd -- true" "resume U1" \
           "move U3 build" "halt U3 interrupt" "commit U3 repo abc1234"; do
    php $c; refc "$c" || return 1
    has "$out" "손으로 관리하던 단위다" "$c" || return 1
    eq "$(nev)" 0 "$c 이벤트 줄 수" || return 1
    cmp -s "$h" "$d/orig.md" || { why="$c 가 상태표를 바꿨다"; return 1; }
  done
  [ ! -d "$d/.mmcode/logs" ] || { why="거부된 check 가 명령을 돌렸다"; return 1; }
  php move U2 build; okc "U2(선행은 손으로 쓴 완료)" || return 1
  php show; has "$out" "| U3 | 대기 | - |" "show 는 그대로" || return 1
}

t_reentry() {  # 구현으로 되돌아갔다 다시 들어오면 이전 검사 결과·커밋 기록은 세지 않는다
  mkcase; to_verify U1 || { why="준비 실패"; return 1; }
  php check U1 cmd -- true
  php move U1 build --reason x; okc "되돌리기" || return 1
  php move U1 verify; okc "다시 verify" || return 1
  php move U1 review; refc "이전 검사 결과만 있는 review" || return 1
  php check U1 cmd -- true; php move U1 review; okc "다시 검사한 뒤 review" || return 1
  php commit U1 repo abc1234
  php move U1 build --reason y; okc "review→build" || return 1
  php move U1 verify; php check U1 cmd -- true; php move U1 review; okc "다시 review" || return 1
  php move U1 done; refc "이전 커밋 기록만 있는 done" || return 1
  php commit U1 repo def5678; php move U1 done; okc "새 커밋 뒤 done" || return 1
  eq "$(cell U1 13)" "repo def5678" "커밋 칸(최근 build 뒤의 것만)" || return 1
}

t_race() {  # 검사 명령이 도는 동안 단계가 바뀌면 그 결과를 기록하지 않는다
  mkcase; to_verify U1 || { why="준비 실패"; return 1; }
  ( cd "$d" && "${BASH:-bash}" "$phase" check "$h" U1 cmd -- sh -c 'sleep 2' > "$d/bg.out" 2>&1; echo $? > "$d/bg.rc" ) &
  local pid=$! i
  for i in $(seq 50); do ls "$d"/.mmcode/logs/*.log >/dev/null 2>&1 && break; sleep 0.1; done
  php move U1 build --reason x; okc "되돌리기" || { wait "$pid"; return 1; }
  php move U1 verify; okc "다시 verify" || { wait "$pid"; return 1; }
  wait "$pid"
  eq "$(cat "$d/bg.rc")" 1 "백그라운드 check exit" || return 1
  has "$(tail -n 1 "$d/bg.out")" "REFUSED: 검사 도중 U1 의 단계가 바뀌었다" "백그라운드 출력" || return 1
  eq "$(nev)" 4 "이벤트 줄 수(build, verify, build, verify)" || return 1
  php move U1 review; refc "결과 없는 review" || return 1
}

t_newline() {  # 끝 줄에 개행이 없는 깨진 조각이 있어도 새 이벤트가 그 줄에 붙지 않는다
  mkcase; php move U1 build; okc || return 1
  printf '{"broken' >> "$ev"
  php move U1 verify; okc "move" || return 1
  php show; has "$out" "| U1 | 검증 | - |" "show" || return 1
  eq "$(sed -n 2p "$ev")" '{"broken' "깨진 조각은 자기 줄에" || return 1
  eq "$(tail -c 1 "$ev" | od -An -c | tr -d ' ')" '\n' "마지막 글자" || return 1
}

t_plans() {  # 계획 폴더가 둘이어도 서로 섞이지 않는다. U1 과 U10 도 섞이지 않는다
  local ho u1
  mkcase; ho="$d/docs/relay/other"
  mkh "$ho" "$(row U1 — 미착수)" "$(row U10 — 미착수)"
  ho="$ho/HANDOFF.md"; cp "$ho" "$d/other.orig"
  php move U1 build; okc "demo U1" || return 1
  cmp -s "$ho" "$d/other.orig" || { why="other 표가 바뀌었다"; return 1; }
  ph show "$ho"; has "$out" "| U1 | 대기 | - |" "other U1" || return 1
  u1=$(grep '^| U1 ' "$ho")
  ph move "$ho" U10 build; okc "other U10" || return 1
  eq "$(grep '^| U1 ' "$ho")" "$u1" "other U1 행" || return 1
  ph show "$ho"; has "$out" "| U1 | 대기 | - |" "other U1" || return 1
  has "$out" "| U10 | 구현 | - |" "other U10" || return 1
  eq "$(cell U1 11)" 진행 "demo U1" || return 1
  php show; lacks "$out" "U10" "demo show" || return 1
  eq "$(grep -c '"plan": "other"' "$ev")" 1 "other 이벤트 수" || return 1
}

mkgrade() {  # mkgrade <등급> [<화면>]: 등급·화면 열이 중간·끝에 있는 상태표에 U1 하나
  mkcase
  {
    printf '%s\n' '# HANDOFF demo' '' '## 상태표' '' \
      '| 단위 | 내용 | 등급 | 파일 | 선행 | 모델 | 병렬 | 검수 | pathspec | 가중치 | 상태 | 종료 시각 | 커밋 | 화면 |' '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|' \
      "| U1 | 내용U1 | $1 | f | — | sonnet | ✘ | sonnet | r:p | 30 | 미착수 | | | ${2:-✘} |" '' '## 진행률' '기준선: 10% (시험)'
  } > "$h"
}
gok() { php "$@"; [ "$rc" = 0 ] || { why="실패: $* → $out"; return 1; }; }  # gok <하위 명령> <인자...>: 성공해야 한다
g_to_review() {  # 실패 먼저, 구현→검증, cmd 통과, 검수까지
  gok check U1 fail-first -- false && gok move U1 build && gok move U1 verify && gok check U1 cmd -- true && gok move U1 review
}
g_ev() { gok check U1 "$1" --pass --reason "$1 통과"; }

t_g_ff() {  # 일반: 실패 먼저가 없으면 build→verify 거부. 빌드 단계에서 기록한 뒤에는 통과
  mkgrade 일반
  gok move U1 build || return 1
  php move U1 verify; refc || return 1
  eq "$(last)" "REFUSED: U1 에 빠진 증거: fail-first" "거부 문구" || return 1
  gok check U1 fail-first -- false || return 1
  gok move U1 verify || return 1
  g_ev review || return 1  # 검사 결과는 있지만 cmd·manual 이 아니다
  php move U1 review; refc "검증 증거 없음" || return 1
  eq "$(last)" "REFUSED: U1 에 빠진 증거: cmd 또는 manual" "검증 거부 문구" || return 1
  g_ev manual && gok move U1 review || return 1
}

t_g_ffcmd() {  # fail-first 명령은 실패해야 통과. 시작하지 못한 명령은 통과가 아니다. 명령 없는 면제는 일반만
  mkgrade 일반
  gok move U1 build || return 1
  php check U1 fail-first -- true; eq "$rc" 1 "true" || return 1
  has "$(last)" "FAILED: fail-first" "문구" || return 1
  has "$(tail -n 1 "$ev")" '"pass": false' "true 이벤트" || return 1
  php check U1 fail-first -- /없는/명령; eq "$rc" 1 "시작 못 한 명령" || return 1
  php move U1 verify; refc "실패 결과만 있다" || return 1
  gok check U1 fail-first -- false || return 1
  has "$(tail -n 1 "$ev")" '"pass": true' "false 이벤트" || return 1
  has "$(tail -n 1 "$ev")" '"exit": 1' "실제 종료 코드" || return 1
  mkgrade 일반; gok move U1 build || return 1
  gok check U1 fail-first --pass --reason "해당 없음: 시험 도구 없음" || return 1
  php check U1 fail-first --fail --reason x; eq "$rc" 1 "fail-first --fail" || return 1
  php move U1 verify; refc "통과 뒤에 실패" || return 1
  gok check U1 fail-first -- false && gok move U1 verify || return 1
}

t_g_done() {  # 일반: review, mutation 이 각각 필요하다. 종류별 가장 최근 결과가 통과여야 한다
  mkgrade 일반; g_to_review || return 1
  gok commit U1 repo abc1234 || return 1
  php move U1 done; refc "둘 다 없음" || return 1
  eq "$(last)" "REFUSED: U1 에 빠진 증거: review, mutation" "문구" || return 1
  g_ev mutation || return 1
  php move U1 done; refc "review 없음" || return 1
  eq "$(last)" "REFUSED: U1 에 빠진 증거: review" "문구" || return 1
  php check U1 review --fail --reason x; eq "$rc" 1 "review --fail" || return 1
  php move U1 done; refc "review 가 실패" || return 1
  g_ev review || return 1
  php check U1 mutation --fail --reason x; eq "$rc" 1 "mutation --fail" || return 1
  php move U1 done; refc "통과 뒤에 실패한 mutation" || return 1
  g_ev mutation && gok move U1 done || return 1
}

t_g_done_mut() {  # 일반: review 만 있고 mutation 이 없으면 거부
  mkgrade 일반; g_to_review || return 1
  gok commit U1 repo abc1234 || return 1
  g_ev review || return 1
  php move U1 done; refc || return 1
  eq "$(last)" "REFUSED: U1 에 빠진 증거: mutation" "문구" || return 1
}

t_g_rework() {  # 재작업 뒤에는 이전 회차의 review·mutation 이 통하지 않는다
  mkgrade 일반; g_to_review || return 1
  g_ev review && g_ev mutation && gok commit U1 repo abc1234 || return 1
  gok move U1 build --reason "수정" || return 1
  gok move U1 verify || return 1
  gok check U1 cmd -- true && gok move U1 review && gok commit U1 repo def5678 || return 1
  php move U1 done; refc "이전 회차 증거만 있다" || return 1
  eq "$(last)" "REFUSED: U1 에 빠진 증거: review, mutation" "문구" || return 1
  g_ev review && g_ev mutation || return 1
  gok move U1 done || return 1
}

t_g_high() {  # 고위험: manual 만으로 검증을 못 넘고, 명령 없는 fail-first 는 거부, cross-review 가 필요하다
  mkgrade 고위험
  gok move U1 build || return 1
  local before; before=$(nev)
  php check U1 fail-first --pass --reason "해당 없음: x"; refc "명령 없는 fail-first" || return 1
  eq "$(nev)" "$before" "거부는 이벤트를 쓰지 않는다" || return 1
  gok check U1 fail-first -- false && gok move U1 verify && g_ev manual || return 1
  php move U1 review; refc "manual 만" || return 1
  eq "$(last)" "REFUSED: U1 에 빠진 증거: cmd" "문구" || return 1
  gok check U1 cmd -- true && gok move U1 review && gok commit U1 repo abc1234 && g_ev review && g_ev mutation || return 1
  php move U1 done; refc "cross-review 없음" || return 1
  eq "$(last)" "REFUSED: U1 에 빠진 증거: cross-review" "문구" || return 1
  g_ev cross-review && gok move U1 done || return 1
}

t_g_screen() {  # 화면 ✔: ui-review 가 없으면 done 거부
  mkgrade 일반 ✔; g_to_review || return 1
  g_ev review && g_ev mutation && gok commit U1 repo abc1234 || return 1
  php move U1 done; refc || return 1
  eq "$(last)" "REFUSED: U1 에 빠진 증거: ui-review" "문구" || return 1
  g_ev ui-review && gok move U1 done || return 1
}

t_g_light() {  # 가벼움·빈 등급·등급 열 없음: 더하는 조건 없이 done 까지 간다
  local g
  for g in 가벼움 ""; do
    mkgrade "$g" ✔
    run_full U1 repo abc1234 || { why="등급 '$g' 한 바퀴 실패: $out"; return 1; }
  done
  mkgrade 가벼움 ✔
  php show; has "$out" "| U1 | 대기 | - | - |" "가벼움 show" || return 1
  mkcase; php show; has "$out" "| U1 | 대기 | - | - |" "등급 열 없음 show" || return 1
}

t_g_unknown() {  # 모르는 등급·화면 값은 사용 오류
  mkgrade 최상
  php move U1 build; eq "$rc" 2 "move" || return 1
  php show; eq "$rc" 2 "show" || return 1
  eq "$(nev)" 0 "이벤트 줄 수" || return 1
  mkgrade 일반 ✓
  php move U1 build; eq "$rc" 2 "모르는 화면 값" || return 1
}

t_g_show() {  # show 의 남은 증거 열
  mkgrade 일반 ✔
  php show; has "$out" "| 단위 | 단계 | 멈춤 | 남은 증거 |" "머리글" || return 1
  has "$out" "| U1 | 대기 | - | fail-first, cmd 또는 manual, review, mutation, ui-review |" "대기" || return 1
  gok check U1 fail-first -- false && gok move U1 build && gok move U1 verify || return 1
  php show; has "$out" "| U1 | 검증 | - | cmd 또는 manual, review, mutation, ui-review |" "검증" || return 1
  gok check U1 cmd -- true && gok move U1 review || return 1
  php show; has "$out" "| U1 | 검수 | - | review, mutation, ui-review |" "검수" || return 1
  g_ev review && g_ev mutation && g_ev ui-review && gok commit U1 repo abc1234 && gok move U1 done || return 1
  php show; has "$out" "| U1 | 완료 | - | - |" "완료" || return 1
  mkgrade 고위험
  php show; has "$out" "| U1 | 대기 | - | fail-first, cmd, review, mutation, cross-review |" "고위험" || return 1
}

t_g_status() {  # 등급·화면 열이 있는 상태표에도 status.sh 가 돈다
  mkgrade 일반 ✔
  gok check U1 fail-first -- false && gok move U1 build || return 1
  rc=0; out=$(bash "$status" "$h" 2>&1) || rc=$?
  eq "$rc" 0 "status.sh exit" || { why="$why / $out"; return 1; }
  has "$out" "| 현재 단위 | U1 내용U1 |" "status.sh" || return 1
}

evt() {  # evt <뒤에서 몇 번째> <파이썬 식>: 그 이벤트 e 에 대해 식이 참이어야 한다
  python3 -I -c 'import json, sys
e = json.loads(open(sys.argv[1], encoding="utf-8").read().splitlines()[-int(sys.argv[2])])
assert eval(sys.argv[3]), e' "$ev" "$1" "$2" 2>/dev/null || { why="이벤트(뒤 $1번째) 조건 불일치: $2 / $(tail -n "$1" "$ev" | head -n 1)"; return 1; }
}
gate() {  # gate <훅 JSON>: 프로젝트 폴더로 gate 를 부른다. $out $rc
  rc=0; out=$(cd "$d" && printf '%s' "$1" | "${BASH:-bash}" "$phase" gate "$d" 2>&1) || rc=$?
}

t_h_ask() {  # 결정 요청은 단위를 결정 대기로 멈추고, 답하면 같은 호출에서 풀린다
  mkcase; gok move U1 build || return 1
  php ask U1 --question "어느 쪽?" --recommend A --impact "U2 지연" --option A --option B; okc "ask" || return 1
  eq "$(last)" "OK: D1 결정 요청 (U1 멈춤)" "출력" || return 1
  evt 2 'e["type"] == "decision.ask" and e["unit"] == "U1" and e["data"] == {"id": "D1", "question": "어느 쪽?", "recommend": "A", "impact": "U2 지연", "options": ["A", "B"]}' || return 1
  evt 1 'e["type"] == "unit.halt" and e["data"] == {"reason": "decision", "decision": "D1"}' || return 1
  php show; has "$out" "| U1 | 구현 | 결정 대기 |" "show" || return 1
  php move U1 verify; refc "결정 대기 중 전환" || return 1
  php answer D1 --answer A --undo "B 로 다시 묻는다"; okc "answer" || return 1
  eq "$(last)" "OK: D1 답 기록 (U1 재개)" "출력" || return 1
  evt 2 'e["type"] == "decision.answer" and e["data"] == {"id": "D1", "answer": "A", "by": "user", "undo": "B 로 다시 묻는다"}' || return 1
  evt 1 'e["type"] == "unit.resume" and e["unit"] == "U1"' || return 1
  gok move U1 verify || return 1
  gok ask U1 --question q2 && gok ask U1 --question q3 || return 1  # 결정이 둘이면 뒤의 결정이 멈춤을 잡는다
  php answer D2 --answer a; okc "D2 답" || return 1
  eq "$(last)" "OK: D2 답 기록" "D3 이 남아 풀리지 않는다" || return 1
  php show; has "$out" "| U1 | 검증 | 결정 대기 |" "아직 멈춤" || return 1
  php answer D3 --answer a; eq "$(last)" "OK: D3 답 기록 (U1 재개)" "D3 답" || return 1
}

t_h_nounit() {  # 단위 없는 결정(-)은 멈춤 이벤트를 쓰지 않는다. --by 로 정한 쪽을 적는다
  mkcase
  php ask - --question "이름은?"; okc "ask" || return 1
  eq "$(nev)" 1 "이벤트 줄 수" || return 1
  evt 1 'e["unit"] == "-" and e["data"] == {"id": "D1", "question": "이름은?", "options": []}' || return 1
  php answer D1 --answer x --by planner; okc "answer" || return 1
  eq "$(nev)" 2 "이벤트 줄 수(재개 없음)" || return 1
  evt 1 'e["data"]["by"] == "planner" and e["unit"] == "-"' || return 1
}

t_h_refuse() {  # 없는 ID·중복 답·닫힌 지시는 거부(이벤트 없음). 빠진 인자는 사용 오류
  mkcase
  php answer D1 --answer x; refc "없는 결정" || return 1
  php ask U9 --question q; refc "없는 단위" || return 1
  php ask U1; eq "$rc" 2 "--question 없음" || return 1
  php direct message; eq "$rc" 2 "message 의 --text 없음" || return 1
  php direct reorder; eq "$rc" 2 "reorder 의 --text 없음" || return 1
  php direct bogus; eq "$rc" 2 "모르는 지시" || return 1
  php applied I1; refc "없는 지시" || return 1
  eq "$(nev)" 0 "거부·사용 오류는 이벤트를 쓰지 않는다" || return 1
  gok ask - --question q && gok answer D1 --answer a || return 1
  php answer D1 --answer b; refc "중복 답" || return 1
  has "$(last)" "이미 답한" "문구" || return 1
  php answer D1 --answer b --by bogus; eq "$rc" 2 "모르는 --by" || return 1
  gok direct message --text hi && gok applied I1 || return 1
  local before; before=$(nev)
  php applied I1; refc "이미 적용" || return 1
  php rejected I1 --reason x; refc "닫힌 지시 거부" || return 1
  php rejected I1; eq "$rc" 2 "--reason 없음" || return 1
  eq "$(nev)" "$before" "이벤트 줄 수" || return 1
  gok direct reorder --text "U3 먼저" && gok rejected I2 --reason "선행 때문" || return 1
  evt 1 'e["type"] == "directive.rejected" and e["data"] == {"id": "I2", "reason": "선행 때문"}' || return 1
}

t_h_folder() {  # 폴더 모드: plan 은 -. ask(단위 -)·direct·show 는 되고 move·halt 는 사용 오류
  mkcase
  ph ask "$d" - --question q; okc "ask" || return 1
  eq "$(last)" "OK: D1 결정 요청" "출력" || return 1
  evt 1 'e["plan"] == "-" and e["unit"] == "-"' || return 1
  ph ask "$d" U1 --question q; eq "$rc" 2 "폴더 모드의 단위 ask" || return 1
  ph direct "$d" message --text hi; okc "direct" || return 1
  eq "$(last)" "OK: I1 지시 접수 (message)" "출력" || return 1
  evt 1 'e["type"] == "directive.received" and e["plan"] == "-" and e["data"] == {"id": "I1", "kind": "message", "text": "hi"}' || return 1
  ph show "$d"; okc "show" || return 1
  has "$out" "| D1 | - | - | q |" "show 결정" || return 1
  has "$out" "| I1 | - | message | hi |" "show 지시" || return 1
  ph move "$d" U1 build; eq "$rc" 2 "폴더 모드 move" || return 1
  ph halt "$d" U1 decision; eq "$rc" 2 "폴더 모드 halt" || return 1
  [ -f "$d/.mmcode/DECISIONS.md" ] || { why="DECISIONS.md 없음"; return 1; }
  cmp -s "$h" "$d/orig.md" || { why="폴더 모드가 상태표를 바꿨다"; return 1; }
}

t_h_ids() {  # ID 는 계획을 넘어 이어진다. 답·적용은 원래 이벤트의 plan 으로 쓴다
  local ho
  mkcase; ho="$d/docs/relay/other"; mkh "$ho" "$(row U1 — 미착수)"; ho="$ho/HANDOFF.md"
  php ask - --question a; eq "$(last)" "OK: D1 결정 요청" "demo" || return 1
  ph ask "$d" - --question b; eq "$(last)" "OK: D2 결정 요청" "폴더" || return 1
  ph ask "$ho" U1 --question c; eq "$(last)" "OK: D3 결정 요청 (U1 멈춤)" "other" || return 1
  ph direct "$d" message --text x; eq "$(last)" "OK: I1 지시 접수 (message)" "폴더 지시" || return 1
  php direct reorder --text y; eq "$(last)" "OK: I2 지시 접수 (reorder)" "demo 지시" || return 1
  ph answer "$d" D1 --answer z; okc "폴더에서 demo 결정에 답" || return 1
  evt 1 'e["type"] == "decision.answer" and e["plan"] == "demo" and e["data"]["id"] == "D1"' || return 1
  ph answer "$d" D3 --answer z; okc "폴더에서 other 결정에 답" || return 1
  evt 1 'e["type"] == "unit.resume" and e["plan"] == "other" and e["unit"] == "U1"' || return 1
  ph applied "$ho" I2; okc "other 에서 demo 지시 적용" || return 1
  evt 1 'e["type"] == "directive.applied" and e["plan"] == "demo"' || return 1
}

t_h_stopafter() {  # 단위 후 정지: 진행 중인 단위는 끝까지 가고, 다음 단위의 build 는 거부. 적용 기록은 한 번
  mkcase; gok move U1 build || return 1
  php direct stop-after; okc "direct" || return 1
  gok move U1 verify && gok check U1 cmd -- true && gok move U1 review && gok commit U1 repo abc1234 && gok move U1 done || return 1
  local before; before=$(nev)
  php move U2 build; refc "다음 단위 build" || return 1
  has "$(last)" "단위 후 정지 지시 I1" "문구" || return 1
  eq "$(nev)" "$((before + 2))" "처음 거부는 이벤트 2줄" || return 1
  evt 2 'e["type"] == "directive.applied" and e["data"] == {"id": "I1"}' || return 1
  evt 1 'e["type"] == "unit.halt" and e["unit"] == "U2" and e["data"]["reason"] == "stop-after"' || return 1
  eq "$(cell U2 11)" 보류 "U2 상태" || return 1
  php move U2 build; refc "두 번째 거부" || return 1
  php move U3 build; refc "다른 단위" || return 1
  eq "$(nev)" "$((before + 2))" "두 번째부터는 이벤트를 쓰지 않는다" || return 1
  mkh "$d/docs/relay/other" "$(row U1 — 미착수)"
  ph move "$d/docs/relay/other/HANDOFF.md" U1 build; okc "다른 계획의 정지 지시는 이 계획을 막지 않는다" || return 1
  ph show "$h" <&-; okc "stdin 이 닫혀 있어도 돈다" || return 1
}

t_h_resume() {  # direct resume 은 열린 정지 지시를 닫고 그 지시로 멈춘 단위를 푼다(폴더 모드에서도)
  mkcase
  gok direct stop-after || return 1
  php move U1 build; refc "정지 지시" || return 1
  php rejected I1 --reason x; refc "정지 지시는 거부할 수 없다" || return 1
  has "$(last)" "거부할 수 없다" "문구" || return 1
  ph direct "$d" resume; okc "resume" || return 1
  eq "$(last)" "OK: I2 지시 접수 (resume, 닫음: I1)" "출력" || return 1
  evt 2 'e["type"] == "directive.received" and e["data"] == {"id": "I2", "kind": "resume", "closes": ["I1"]}' || return 1
  evt 1 'e["type"] == "unit.resume" and e["plan"] == "demo" and e["unit"] == "U1"' || return 1
  gok move U1 build || return 1
  eq "$(cell U1 11)" 진행 "U1 상태" || return 1
  php show; lacks "$out" "열린 지시" "resume 지시는 접수가 곧 적용이다" || return 1
  php applied I2; refc "resume 지시는 이미 닫혔다" || return 1
}

t_h_gate() {  # gate: 열린 즉시 중단은 종료 코드 2. phase.sh 명령·다른 터미널·resume 뒤·이벤트 파일 없음은 0
  mkcase
  gate '{"tool_name":"Edit","tool_input":{}}'; eq "$rc" 0 "이벤트 파일 없음" || return 1
  [ ! -d "$d/.mmcode" ] || { why=".mmcode 를 만들었다"; return 1; }
  gok direct interrupt || return 1
  gate '{"tool_name":"Edit","tool_input":{"file_path":"x"}}'; eq "$rc" 2 "열린 interrupt" || return 1
  has "$out" "I1" "안내" || return 1
  has "$out" "resume" "안내" || return 1
  gate '{"tool_name":"Bash","tool_input":{"command":"ls"}}'; eq "$rc" 2 "다른 Bash 명령" || return 1
  eq "$(grep -c '"directive.applied"' "$ev")" 1 "적용 기록은 한 번" || return 1
  gate '{"tool_name":"Bash","tool_input":{"command":"bash plugins/x/phase.sh show docs/HANDOFF.md"}}'; eq "$rc" 0 "phase.sh 명령" || return 1
  gate 'not json'; eq "$rc" 0 "해석 실패는 막지 않는다" || return 1
  gok direct resume || return 1
  gate '{"tool_name":"Edit","tool_input":{}}'; eq "$rc" 0 "resume 뒤" || return 1
  gok direct interrupt --terminal t9 || return 1
  export HC_TERMINAL_ID=t1; gate '{"tool_name":"Edit","tool_input":{}}'; local r1=$rc
  export HC_TERMINAL_ID=t9; gate '{"tool_name":"Edit","tool_input":{}}'; local r9=$rc
  unset HC_TERMINAL_ID
  eq "$r1" 0 "다른 터미널" || return 1
  eq "$r9" 2 "지정 터미널" || return 1
}

t_h_decisions() {  # DECISIONS.md: 결정이 없으면 만들지 않는다. 열린 결정·답한 결정 표. 칸 안의 | 와 줄바꿈은 바꾼다
  mkcase
  gok show || return 1
  [ ! -f "$d/.mmcode/DECISIONS.md" ] || { why="결정 없이 만들었다"; return 1; }
  gok ask U1 --question "$(printf 'a|b\nc')" --recommend r --impact i --option x --option y || return 1
  gok ask - --question q2 && gok answer D2 --answer ans --by planner --undo u || return 1
  local f; f=$(cat "$d/.mmcode/DECISIONS.md")
  has "$f" "## 열린 결정" "파일" || return 1
  has "$f" "| ID | 계획 | 단위 | 질문 | 추천 | 영향 | 선택지 |" "열린 결정 머리글" || return 1
  has "$f" '| D1 | demo | U1 | a\|b<br>c | r | i | x / y |' "열린 결정 행" || return 1
  has "$f" "## 답한 결정" "파일" || return 1
  has "$f" "| ID | 계획 | 단위 | 질문 | 답 | 정한 쪽 | 되돌리는 방법 |" "답한 결정 머리글" || return 1
  has "$f" "| D2 | demo | - | q2 | ans | planner | u |" "답한 결정 행" || return 1
  lacks "$f" "| D2 | demo | - | q2 | - |" "열린 결정에 D2" || return 1
}

t_h_show() {  # show 는 열린 결정·지시가 있을 때만 그 부분을 보여 준다
  mkcase
  php show; okc "show" || return 1
  lacks "$out" "열린 결정" "빈 show" || return 1
  lacks "$out" "열린 지시" "빈 show" || return 1
  gok ask - --question q --recommend r && gok direct message --text hi && gok direct stop-after || return 1
  php show; okc "show" || return 1
  has "$out" "| U1 | 대기 | - | - |" "기존 표" || return 1
  has "$out" "열린 결정" "결정 제목" || return 1
  has "$out" "| D1 | demo | - | q | r |" "결정 행" || return 1
  has "$out" "| I1 | demo | message | hi | - | - |" "지시 행" || return 1
  has "$out" "| I2 | demo | stop-after | - | - | - |" "정지 지시 행" || return 1
  gok applied I1 && gok answer D1 --answer a || return 1
  php show; lacks "$out" "열린 결정" "답한 뒤" || return 1
  lacks "$out" "| I1 |" "적용한 메시지" || return 1
  has "$out" "| I2 | demo | stop-after |" "정지 지시는 resume 전까지 열려 있다" || return 1
}

run() { why=; if "t_$1"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: ${why:-조건 불일치}"; fi; }
t_handdone() {  # 보충: 이벤트 없이 손으로 `완료`라고 적은 선행 단위는 완료로 본다. `진행`은 아니다
  mkcase
  mkh "$d/docs/relay/demo" "$(row U1 — 완료)" "$(row U2 U1 미착수)" "$(row U3 — 진행)" "$(row U4 U3 미착수)"
  php move U2 build; okc "U2(선행 U1 은 손으로 쓴 완료)" || return 1
  eq "$(cell U1 11)" "완료" "U1 상태 칸" || return 1
  php move U4 build; refc "U4(선행 U3 은 손으로 쓴 진행)" || return 1
  php show; okc "show" || return 1
  has "$out" "| U1 | 완료 |" "show" || return 1
}
for t in cycle no_check fail_check no_commit prereq skip_back halt untouched ignored usage status manual handdone handguard reentry race newline plans g_ff g_ffcmd g_done g_done_mut g_rework g_high g_screen g_light g_unknown g_show g_status \
         h_ask h_nounit h_refuse h_folder h_ids h_stopafter h_resume h_gate h_decisions h_show; do run "$t"; done
echo "시험 $((pass + fail))개 · 실패 ${fail}개"
[ "$fail" -eq 0 ]
