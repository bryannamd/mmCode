#!/usr/bin/env bash
# eval-goal.sh 시험. mktemp 폴더 안 임시 git 저장소에서만 돈다(실제 저장소·사용자 git 설정·네트워크 무접촉).
# 사용: bash tests/relay/eval-goal.test.sh   출력: 시험마다 PASS/FAIL 한 줄, 끝에 통과·실패 수. 실패가 있으면 exit 1.
# 근거: plugins/mmcode/skills/relay/references/DESIGN-auto.md 10절 중 스크립트로 확인할 수 있는 항목.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
EG="$HERE/../../plugins/mmcode/skills/relay/scripts/eval-goal.sh"
TMP=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
# 사용자 전역 git 설정(훅·서명·기본 브랜치)을 읽지 않는다
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1 MARK="$TMP/mark" COUNT="$TMP/count" PIDF="$TMP/child.pid"
printf '[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' > "$GIT_CONFIG_GLOBAL"
REALGIT=$(command -v git)
NOCH='없음(변경 없음)'
PASS=0 FAIL=0 OUT='' RC=0

ok() { echo "PASS $1"; PASS=$((PASS + 1)); }
ng() { echo "FAIL $1: $2"; FAIL=$((FAIL + 1)); }
# t <이름> <조건 식>: 조건이 참이면 PASS, 아니면 FAIL 과 마지막 출력 꼬리
t() { if eval "$2"; then ok "$1"; else ng "$1" "rc=$RC $(printf '%s' "$OUT" | tail -n 3 | tr '\n' ' ')"; fi; }
eg() { OUT=$(bash "$EG" "$@" 2>&1); RC=$?; }
# 준비 단계: 실패하면 FAIL 로 센다
must() { eg "$@"; [ "$RC" = 0 ] || ng "준비 단계 $*" "rc=$RC $(printf '%s' "$OUT" | tail -n 2 | tr '\n' ' ')"; }
# 검사와 머지 사이의 틈을 재현한다: 가짜 git 이 merge --ff-only 직전에 EG_WRAP 동작을 한다
wrap() { local w=$1; shift; OUT=$(EG_WRAP=$w PATH="$TMP/fakebin:$PATH" bash "$EG" "$@" 2>&1); RC=$?; }
has() { printf '%s\n' "$OUT" | grep -F -- "$1" >/dev/null; }
hasline() { printf '%s\n' "$OUT" | grep -F -- "$1" | grep -F -- "$2" >/dev/null; }
lastline() { printf '%s\n' "$OUT" | tail -n 1; }
sget() { bash "$EG" state "$H" get "$1" 2>/dev/null; }
jget() { printf '%s' "$OUT" | python3 -I -c '
import json, sys
v = json.load(sys.stdin)
for k in sys.argv[1].split("."):
    v = v[k]
print(v if isinstance(v, str) else json.dumps(v))' "$1"; }
# 마지막 평가의 survivors 배열에 파일 $1 에 적힌 PID 가 있는지
survivor_pid() { sget last_eval.results | python3 -I -c '
import json, sys
pid = int(open(sys.argv[1]).read().strip())
sys.exit(0 if any(pid in (r.get("survivors") or []) for r in json.load(sys.stdin)) else 1)' "$1"; }
absent() { sget "$1" | grep -q "^BLOCKED: 키 없음"; }   # state 에 그 키가 없다
rowof() { grep -F "| $1 |" "$H"; }
rowis() { rowof "$1" | grep -F "| $2 |" >/dev/null; }
brtip() { "$REALGIT" -C "$R" rev-parse -q --verify "refs/heads/relay/p1/$1"; }
wt() { printf '%s' "$P/$1/wt"; }

sh_() { printf '#!/bin/sh\n%s\n' "$2" > "$1"; chmod +x "$1"; }
mkrepo() { # <폴더>: 시험 파일·스크립트와 첫 커밋이 있는 저장소
  local d=$1
  mkdir -p "$d/src" "$d/lib"
  git init -q "$d"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name tester
  printf 'a\n' > "$d/src/a.txt"; printf 'b\n' > "$d/lib/b.txt"; printf 'o\n' > "$d/other.txt"
  printf '\000\001\002' > "$d/bin.dat"; printf '__pycache__/\n' > "$d/.gitignore"
  sh_ "$d/ok.sh" 'echo "arg=$1"'
  sh_ "$d/fail.sh" 'echo fail; exit 1'
  sh_ "$d/slow.sh" 'exec sleep 5'
  sh_ "$d/e127.sh" 'exit 127'
  sh_ "$d/mark.sh" 'echo ran > "$MARK"'
  sh_ "$d/count.sh" 'echo x >> "$COUNT"'
  printf 'echo no\n' > "$d/noexec.sh"
  git -C "$d" add -A && git -C "$d" commit -q -m init
}
# 인계 문서: $1 완료 조건 cmd 블록 · $2 상태표 행 · $3 재개 블록에 더할 줄(선택). MODE·POLICY 로 바꿀 수 있다.
mkhandoff() {
  mkdir -p "$P"
  {
    printf '# HANDOFF — p1\n\n## 재개 지시\n\n```text\n'
    printf '계획: docs/relay/p1/PLAN.md. 규칙: mmcode:relay 스킬 (resume 모드).\n세션 연번: t (#0)\n'
    printf '모드: %s\n' "${MODE:-auto}"
    printf '커밋 정책: %s\n' "${POLICY:-자동 승인: 전부(보정 단위 포함) / 만료: 계획 완료·중단·최대 반복 또는 최대 시간 도달}"
    printf '다음 작업: U1\n완료 조건:\n%s\n경계:\n  최대 반복: 20\n  최대 시간: 4h\n  Worker 제한: 30m\n' "$1"
    if [ -n "${3:-}" ]; then printf '%s\n' "$3"; fi
    printf '```\n\n## 상태표\n\n'
    printf '| 단위 | 내용 | 파일 | 선행 | 모델 | 병렬 | 검수 | pathspec | 가중치 | 상태 | 종료 시각 | 커밋 |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|\n%s\n\n## 이월\n- 없음\n' "$2"
  } > "$H"
}
row() { printf '| %s | 내용 | %s | — | sonnet | ✘ | sonnet | %s | | %s | | |' "$1" "${2#*:}" "$2" "${3:-미착수}"; }
setup() { # <slug=폴더 이름> <cmd 블록> <상태표 행> [추가 줄]: 전역 R·P·H 를 정한다
  R="$TMP/$1"; P="$R/docs/relay/p1"; H="$P/HANDOFF.md"
  mkrepo "$R"; mkhandoff "$2" "$3" "${4:-}"
}
setrow() { # <단위> <상태>: 사용자가 상태표를 고친 것처럼 그 행의 상태 칸만 바꾼다
  python3 -I - "$H" "$1" "$2" <<'PYT'
import sys
p, u, s = sys.argv[1:]
L = open(p, encoding='utf-8').read().split('\n')
for i, l in enumerate(L):
    c = l.split('|')
    if len(c) > 12 and c[1].strip() == u:
        c[10] = f' {s} '
        L[i] = '|'.join(c)
open(p, 'w', encoding='utf-8').write('\n'.join(L))
PYT
}
work() { must unit "$H" "$1" start; printf 'a1\n' > "$(wt "$1")/src/a.txt"; }  # 단위 시작 + Worker 수정
ext() { printf 'ext\n' >> "$R/other.txt"; git -C "$R" commit -q -am ext; }      # 남의 커밋(pathspec 밖)
TWO="$(row U1 src/a.txt)
$(row U2 lib/b.txt)"
OKCMD='  cmd: ./ok.sh'
SRC2="$(row U1 src/)
$(row U2 lib/b.txt)"   # 새 파일을 만드는 단위용

mkdir -p "$TMP/fakebin" "$TMP/bin"
# ignored-*: 머지가 src/a.txt 를 지우면 빈 src/ 도 지워지므로 폴더부터 만들고 무시 파일을 쓴다
# wrongtree·laterace: other 로 전환 → 머지 → third 로 전환(codex 2라운드 재현). laterace 는 update-ref 직전에 사용자 파일을 쓴다
# EG_GITLOG 가 있으면 불린 git 인자를 한 줄씩 남긴다(read-tree 를 쓰지 않는지 본다)
# after-lock·wrongtree-lock·wrongtree-desc-lock·refuse-lock: ff 뒤(refuse 는 ff 대신)에 goal/.lock 을 3초 쥔다(기록 단계가 잠금을 못 얻는 경우). 잠금 경로는 EG_LOCK
# after-target: ff 뒤에 다른 프로세스가 state 의 저장소 설정(EG_SET)을 바꾼다(EG_EVAL·EG_H 로 이 스크립트를 부른다)
cat > "$TMP/fakebin/git" <<EOF
#!/bin/sh
[ -n "\${EG_GITLOG:-}" ] && printf '%s\n' "\$*" >> "\$EG_GITLOG"
hold_lock() {  # 홀더는 물려받은 fd(goal/.driver 포함)를 먼저 닫는다. 시험 대상은 .lock 뿐이다
  python3 -I -c 'import fcntl, os, sys, time; os.closerange(3, 65536); f = open(sys.argv[1], "a"); fcntl.flock(f, fcntl.LOCK_EX); time.sleep(3)' "\$EG_LOCK" >/dev/null 2>&1 &
  sleep 1
}
probe_driver() {  # goal/.driver 를 지금 잡을 수 있는지(FREE/LOCKED) EG_PROBE 에 쓴다. 물려받은 fd 는 닫고 본다
  python3 -I -c 'import fcntl, os, sys; os.closerange(3, 65536); f = open(sys.argv[1], "a")
try:
    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB); print("FREE")
except BlockingIOError:
    print("LOCKED")' "\$EG_DRIVER" > "\$EG_PROBE" 2>/dev/null
}
for a in "\$@"; do
  if [ "\$a" = --ff-only ]; then
    case "\${EG_WRAP:-}" in
      switch) "$REALGIT" switch -q -c other ;;
      switch-existing) "$REALGIT" switch -q other ;;
      detach) "$REALGIT" switch -q --detach ;;
      touch) printf 'race\n' > src/a.txt ;;
      after-switch) "$REALGIT" "\$@" || exit \$?; "$REALGIT" switch -q other; exit 0 ;;
      ignored-new) "$REALGIT" switch -q -c other; "$REALGIT" "\$@" || exit \$?; mkdir -p src; printf 'user-ignored-data\n' > src/a.txt; exit 0 ;;
      ignored-existing) "$REALGIT" switch -q other; "$REALGIT" "\$@" || exit \$?; mkdir -p src; printf 'user-ignored-data\n' > src/a.txt; exit 0 ;;
      wrongtree|laterace) "$REALGIT" switch -q other; "$REALGIT" "\$@" || exit \$?; "$REALGIT" switch -q third; exit 0 ;;
      after-lock) "$REALGIT" "\$@" || exit \$?; hold_lock; exit 0 ;;
      wrongtree-lock) "$REALGIT" switch -q other; "$REALGIT" "\$@" || exit \$?; "$REALGIT" switch -q third; hold_lock; exit 0 ;;
      wrongtree-desc-lock) "$REALGIT" switch -q other; "$REALGIT" "\$@" || exit \$?; printf 'x\n' >> other.txt; "$REALGIT" commit -q -am after-ff; "$REALGIT" switch -q third; hold_lock; exit 0 ;;
      refuse-lock) hold_lock; echo 'fatal: Not possible to fast-forward, aborting.' >&2; exit 128 ;;
      after-target) "$REALGIT" "\$@" || exit \$?; bash "\$EG_EVAL" state "\$EG_H" set "\$EG_SET" '"refs/heads/other"' >/dev/null; exit 0 ;;
      kill-parent) kill -TERM "\$PPID"; sleep 0.5; probe_driver; exit 0 ;;
      custom-lock) "$REALGIT" symbolic-ref HEAD refs/custom/other; "$REALGIT" "\$@" || exit \$?; "$REALGIT" symbolic-ref HEAD refs/heads/main; hold_lock; exit 0 ;;
      refuse-desc-lock) "$REALGIT" switch -q backup; printf 'y\n' >> other.txt; "$REALGIT" commit -q -am indep; "$REALGIT" switch -q main; hold_lock; echo 'fatal: Not possible to fast-forward, aborting.' >&2; exit 128 ;;
    esac
    break
  fi
  if [ "\$a" = --contains ] && [ "\${EG_WRAP:-}" = contains-target ]; then   # recover 의 포함 검사 도중 다른 프로세스가 설정을 바꾼다
    bash "\$EG_EVAL" state "\$EG_H" set "\$EG_SET" '"refs/heads/other"' >/dev/null; break
  fi
  if [ "\$a" = --contains ] && [ "\${EG_WRAP:-}" = contains-fail ]; then echo 'fatal: injected contains failure' >&2; exit 128; fi
  if [ "\$a" = diff ] && [ "\${EG_WRAP:-}" = diff-target ]; then   # 예약이 대상에 들어간 뒤, 완료 확정 전 git 검사 도중 설정을 바꾼다
    bash "\$EG_EVAL" state "\$EG_H" set "\$EG_SET" '"refs/heads/other"' >/dev/null; break
  fi
  if [ "\$a" = update-ref ] && [ "\${EG_WRAP:-}" = laterace ]; then
    mkdir -p src; printf 'precious-late-user-data\n' > src/a.txt
    break
  fi
done
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP/fakebin/git"
mkdir -p "$TMP/psfail"; sh_ "$TMP/psfail/ps" 'exit 1'   # ps 실패 경로용
sh_ "$TMP/bin/npm" 'exit 0'
sh_ "$TMP/bin/make" 'exit 0'

# ── check ─────────────────────────────────────────────
setup ck '  cmd: ./ok.sh a;b
  cmd: ls *.txt
  cmd: FOO=1 ./ok.sh
  cmd: curl -s http://localhost:9
  cmd: no-such-cmd-zz9
  cmd: ./noexec.sh' "$(row U1 src/a.txt)"
eg check "$H"
t "check 거부: 셸 메타문자" '[ $RC = 1 ] && hasline "FAIL cmd 1:" "셸 메타문자 ;" && has "BLOCKED: check 거부 6건"'
t "check 거부: 글로빙 문자" 'hasline "FAIL cmd 2:" "글로빙 문자 *"'
t "check 거부: 환경변수 접두사" 'hasline "FAIL cmd 3:" "환경변수 접두사"'
t "check 거부: 금지 패턴" 'hasline "FAIL cmd 4:" "금지 패턴 curl"'
t "check 거부: 없는 명령" 'hasline "FAIL cmd 5:" "명령을 찾지 못함"'
t "check 거부: 실행 비트 없는 ./x" 'hasline "FAIL cmd 6:" "실행 비트 없음"'
setup ck2 '  cmd: ./ok.sh "x # y"   # 따옴표 안 # 은 인자로 남는다
  cmd: git --version          # 주석 안의 ; | 는 보지 않는다' "$(row U1 src/a.txt)"
eg check "$H"
t "check 통과: 따옴표 안 # 보존" '[ $RC = 0 ] && hasline "PASS cmd 1:" "[\"./ok.sh\", \"x # y\"]" && has "OK: check"'
t "check 통과: 주석 속 메타문자는 보지 않음" 'hasline "PASS cmd 2:" "[\"git\", \"--version\"]"'
setup ck3 '  cmd: npm test -- --ci
  cmd: make lint
  cmd: npm ci' "$(row U1 src/a.txt)"
printf '{"scripts":{"test":"jest"}}\n' > "$R/package.json"; printf 'lint:\n\t./ok.sh lint\n' > "$R/Makefile"
OUT=$(PATH="$TMP/bin:$PATH" bash "$EG" check "$H" 2>&1); RC=$?
t "check: npm·make 한 단계 풀어 보이기" '[ $RC = 0 ] && has "→ jest --ci" && has "→ ./ok.sh lint" && has "→ (해석 불가)"'
POLICY='확인 후' setup ck4 "$OKCMD" "$(row U1 src/a.txt)"
eg check "$H"
t "check 거부: auto 인데 자동 승인 줄 없음" '[ $RC = 1 ] && hasline "FAIL 커밋 정책" "자동 승인"'

# ── 파서: # 주석 줄·줄 끝 주석·실제 템플릿 ─────────────
setup pc '  cmd: ./ok.sh
# 주석 줄은 블록을 끊지 않는다
    # 들여쓴 주석 줄
  cmd: ./fail.sh   # 줄 끝 주석
  timeout: 2m      # "1m # 아님" 따옴표 안 # 도 주석 안이다' "$(row U1 src/a.txt)" '# 저장소: x=/nowhere   (주석 줄이라 무시된다)'
eg check "$H"
t "파서: # 주석 줄은 무시하고 블록을 끊지 않는다" '[ $RC = 0 ] && has "완료 조건 cmd: 2줄" && ! has "알 수 없는 줄" && ! has "저장소 x"'
t "파서: timeout·경계 줄 끝 주석을 뗀다" 'has "PASS timeout: 2m" && hasline "PASS 경계 최대 시간" "→ 14400초" && ! hasline "경계" "#"'
TPL="$HERE/../../plugins/mmcode/skills/relay/templates/HANDOFF.md"
R="$TMP/tpl"; P="$R/docs/relay/p1"; H="$P/HANDOFF.md"; mkrepo "$R"; mkdir -p "$P"; cp "$TPL" "$H"
eg check "$H"
t "템플릿 그대로: 주석 줄·줄 끝 주석을 바르게 읽고 자리 표시 값만 거부" '[ $RC = 1 ] && ! has "알 수 없는 줄" && ! has "저장소 줄 형식" && ! hasline "경계" "#" && ! hasline "timeout:" "#" && [ "$(printf "%s\n" "$OUT" | grep -cE "^(PASS|FAIL) 경계 ")" = 3 ]'
R="$TMP/tpl2"; P="$R/docs/relay/p1"; H="$P/HANDOFF.md"; mkrepo "$R"; mkdir -p "$P"; cp "$TPL" "$H"
python3 -I - "$H" <<'PYT'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = re.sub(r'(?m)^(\s+cmd:\s*)\S.*?(\s+#.*)?$', lambda m: m.group(1) + './ok.sh' + (m.group(2) or ''), s, count=1)
s = re.sub(r'(?m)^(\s+최대 반복:\s*)\S+', r'\g<1>6', s)
s = re.sub(r'(?m)^커밋 정책:.*$', '커밋 정책: 자동 승인: U1(보정 단위 포함) / 만료: 계획 완료·중단·최대 반복 또는 최대 시간 도달', s)
s = re.sub(r'(?m)^(\|\s*U1\s*\|(?:[^|]*\|){6})[^|]*', r'\1 src/a.txt ', s)
open(p, 'w', encoding='utf-8').write(s)
PYT
eg check "$H"
t "템플릿 채움: check 통과" '[ $RC = 0 ] && has "PASS 경계 최대 반복: 6 → 6"'
must init "$H"; eg run "$H"; eg run "$H"; must stop "$H" scope
tail2=$(python3 -I - "$H" <<'PYT'
import sys
L = open(sys.argv[1], encoding='utf-8').read().split('\n')
h = L.index('## 재개 지시')
s = next(i for i in range(h, len(L)) if L[i].startswith('```'))
e = next(i for i in range(s + 1, len(L)) if L[i].startswith('```'))
print('\n'.join(L[e - 2:e]))
PYT
)
t "템플릿 채움: 조건 평가·중단 줄은 닫는 펜스 앞에 한 줄씩" '[ "$(grep -c "^최근 조건 평가:" "$H")" = 1 ] && [ "$(grep -c "^# 저장소:" "$H")" = 1 ] && printf "%s\n" "$tail2" | head -n 1 | grep -q "^최근 조건 평가: 2 " && [ "$(printf "%s\n" "$tail2" | tail -n 1)" = "중단: scope" ]'

# ── init ──────────────────────────────────────────────
setup in1 "$OKCMD" "$(row U1 src/a.txt)"
printf 'dirty\n' >> "$R/src/a.txt"; eg init "$H"
t "init 거부: 계획 경로 미커밋 변경" '[ $RC = 1 ] && has "미커밋 변경 src/a.txt" && [ ! -e "$P/goal/state.json" ]'
printf 'a\n' > "$R/src/a.txt"; git -C "$R" switch -q --detach; eg init "$H"
t "init 거부: 분리 HEAD" '[ $RC = 1 ] && has "분리 HEAD"'
git -C "$R" switch -q main
MODE=manual mkhandoff "$OKCMD" "$(row U1 src/a.txt)"; eg init "$H"
t "init 거부: 모드 auto 아님" '[ $RC = 1 ] && has "모드: auto 가 아니다"'
mkhandoff "$OKCMD" "$(row U1 src/a.txt)"; eg init "$H"
t "init: state.json 생성(저장소·경계·시간대)" '[ $RC = 0 ] && [ "$(sget repos.in1.target_ref)" = refs/heads/main ] && [ "$(sget repos.in1.expected_tip)" = "$(git -C "$R" rev-parse HEAD)" ] && [ "$(sget max_iterations)" = 20 ] && [ "$(sget max_duration)" = 14400 ] && [ "$(sget worker_timeout)" = 1800 ] && sget started_at | grep -Eq "[+-][0-9]{2}:[0-9]{2}$"'
eg init "$H"
t "init 거부: state.json 이미 있음" '[ $RC = 1 ] && has "이미 있다"'

# ── run ───────────────────────────────────────────────
setup rn '  cmd: ./ok.sh "x # y"
  cmd: ./fail.sh' "$(row U1 src/a.txt)"
must init "$H"; head0=$(git -C "$R" rev-parse HEAD)
eg run "$H"
t "run: exit 0·1 → 미완료" '[ $RC = 0 ] && [ "$(lastline)" = "DONE: incomplete(units=1,failed=1)" ]'
t "run: 로그에 명령·exit·출력 꼬리" 'grep -qF "arg=x # y" "$P/goal/1.log" && grep -qF "exit: 1" "$P/goal/1.log" && grep -qF "$ ./fail.sh" "$P/goal/1.log"'
t "run: 인계 문서 최근 조건 평가 한 줄·last_eval" 'grep -Eq "^최근 조건 평가: 1 .* 통과 1 실패 1 → goal/eval.md$" "$H" && [ "$(sget last_eval.iteration)" = 1 ]'
mkhandoff '  cmd: ./slow.sh
  timeout: 1s' "$(row U1 src/a.txt)"
s0=$(date +%s); eg run "$H"; s1=$(date +%s)
t "run: 제한 시간 초과 → 실패·프로세스 종료" '[ $RC = 0 ] && [ "$(lastline)" = "DONE: incomplete(units=1,failed=1)" ] && [ $((s1 - s0)) -lt 5 ] && grep -qF "제한 시간 1초 초과" "$P/goal/2.log"'
mkhandoff '  cmd: ./e127.sh
  cmd: ./mark.sh' "$(row U1 src/a.txt)"
rm -f "$MARK"; eg run "$H"
t "run: exit 127 → judge-fail·뒤 cmd 미실행" '[ $RC = 3 ] && has "BLOCKED: judge-fail" && [ ! -e "$MARK" ] && grep -qF "실행 안 함" "$P/goal/3.log"'
t "run: judge-fail → stopped_reason·중단 줄" '[ "$(sget stopped_reason)" = judge-fail ] && grep -q "^중단: judge-fail$" "$H"'
t "run: eval.md 3행" '[ $(wc -l < "$P/goal/eval.md") -eq 3 ]'
t "run: 저장소 추적 파일 변경 0(인계 문서·goal 제외)" '[ -z "$(git -C "$R" status --porcelain -uall -- . ":!docs/relay/p1")" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$head0" ]'

# ── treekey·재사용 ────────────────────────────────────
setup tk '  cmd: ./count.sh' "$(row U1 src/a.txt)"
printf 'n\n' > "$P/notes.md"; git -C "$R" add docs && git -C "$R" commit -q -m docs   # 계획 폴더 일부를 추적한다
must init "$H"; rm -f "$COUNT"
runs() { wc -l < "$COUNT" | tr -d ' '; }
eg run "$H"; eg run "$H"
t "treekey 재사용: 같은 트리" 'has "(이전 실행 · 그 뒤 변경 없음)" && [ "$(runs)" = 1 ] && grep -qF "(이전 실행 · 그 뒤 변경 없음)" "$P/goal/eval.md"'
printf 'n2\n' > "$P/notes.md"; eg run "$H"
t "treekey 재사용: 계획 문서(추적)만 바뀜" 'has "(이전 실행 · 그 뒤 변경 없음)" && [ "$(runs)" = 1 ]'
printf 'u\n' > "$P/new.md"; eg run "$H"
t "treekey 재사용: 계획 문서(미추적)만 바뀜" 'has "(이전 실행 · 그 뒤 변경 없음)" && [ "$(runs)" = 1 ]'
printf 'a1\n' > "$R/src/a.txt"; eg run "$H"; printf 'a2\n' > "$R/src/a.txt"; eg run "$H"
t "treekey 재실행: 수정 중 파일 내용만 더 바뀜" '! has "이전 실행" && [ "$(runs)" = 3 ]'
printf '1\n' > "$R/src/u.txt"; eg run "$H"; printf '2\n' > "$R/src/u.txt"; eg run "$H"
t "treekey 재실행: 미추적 파일 내용만 바뀜" '! has "이전 실행" && [ "$(runs)" = 5 ]'
printf '\000\001\003' > "$R/bin.dat"; eg run "$H"; printf '\000\001\004' > "$R/bin.dat"; eg run "$H"
t "treekey 재실행: 바이너리 내용만 바뀜" '! has "이전 실행" && [ "$(runs)" = 7 ]'
setrow U1 완료; eg run "$H"; eg run "$H"
t "treekey 재실행: 미완료 단위 0개" '! has "이전 실행" && [ "$(runs)" = 9 ] && [ "$(lastline)" = "DONE: complete" ]'
setup ti "$OKCMD" "$(row U1 src/a.txt)"
printf 'docs/\n' >> "$R/.gitignore"; git -C "$R" commit -q -am ignore-docs
eg treekey "$H" ti; k1=$OUT; printf 'z\n' > "$P/zz.md"; eg treekey "$H" ti
t "treekey: docs 가 무시 대상인 저장소" '[ $RC = 0 ] && [ "$OUT" = "$k1" ] && [ "$k1" = "$(git -C "$R" rev-parse "HEAD^{tree}")" ]'
printf 'a9\n' > "$R/src/a.txt"; eg treekey "$H" ti
t "treekey: docs 무시 저장소에서도 작업 파일 변경은 키에 반영" '[ $RC = 0 ] && [ -n "$OUT" ] && [ "$OUT" != "$k1" ]'

# ── 저장소 둘 ─────────────────────────────────────────
mkrepo "$TMP/two"
setup mr "$OKCMD" "$(row U1 src/a.txt)
| U2 | 내용 | x.txt | — | sonnet | ✘ | sonnet | two:x.txt | | 미착수 | | |" "저장소: two=$TMP/two"
eg treekey "$H" two
t "treekey: docs 가 없는 저장소" '[ $RC = 0 ] && [ "$OUT" = "$(git -C "$TMP/two" rev-parse "HEAD^{tree}")" ]'
must init "$H"; must unit "$H" U2 start; printf 'x\n' > "$(wt U2)/x.txt"
must unit "$H" U2 checkwt; must unit "$H" U2 commit -m U2; must unit "$H" U2 merge; must unit "$H" U2 cleanup
t "저장소 둘: 다른 저장소 단위는 그 저장소에만 머지" '[ "$(cat "$TMP/two/x.txt")" = x ] && rowis U2 "two $(git -C "$TMP/two" rev-parse --short=7 HEAD)" && [ "$(git -C "$R" rev-parse HEAD)" = "$(sget repos.mr.init_head)" ] && [ ! -e "$(wt U2)" ]'
mkhandoff "$OKCMD" "| U1 | 내용 | a | — | sonnet | ✘ | sonnet | mr:src/a.txt, two:x.txt | | 미착수 | | |" "저장소: two=$TMP/two"
eg check "$H"
t "check 거부: 단위 하나가 저장소 둘" '[ $RC = 1 ] && has "저장소별로 나눈다"'

# ── 완료 판정·보정·재위임 ─────────────────────────────
setup dn "$OKCMD" "$(row U1 src/a.txt)
$(row U2 lib/b.txt 완료)"
must init "$H"; eg run "$H"
t "완료 판정: 단위 미완료 + cmd 통과 → 미완료" '[ "$(lastline)" = "DONE: incomplete(units=1,failed=0)" ]'
setrow U1 완료; eg run "$H"
t "완료 판정: 단위 전부 완료 + cmd 통과 → 완료" '[ "$(lastline)" = "DONE: complete" ]'
mkhandoff '  cmd: ./fail.sh' "$(row U1 src/a.txt 완료)
$(row U2 lib/b.txt 완료)"
eg run "$H"
t "완료 판정: 단위 전부 완료 + cmd 실패 → 미완료" '[ "$(lastline)" = "DONE: incomplete(units=0,failed=1)" ]'
eg fix "$H" add U2-fix1 --key ./fail.sh --repo dn --files src/a.txt --summary "fail.sh 실패 수정"
t "완료 판정: 원인이 pathspec 안 → 보정 단위 추가(12열 기본값)" '[ $RC = 0 ] && grep -qF "| U2-fix1 | fail.sh 실패 수정 | src/a.txt | U2 | sonnet | ✘ | sonnet | dn:src/a.txt |  | 미착수 |  |  |" "$H" && [ "$(sget fix_units)" = "[{\"round\": 1, \"unit\": \"U2-fix1\", \"key\": \"./fail.sh\"}]" ]'
eg fix "$H" add U2-fix2 --key ./fail.sh --repo dn --files other.txt --summary 밖
t "완료 판정: 원인이 pathspec 밖 → scope 중단" '[ $RC = 1 ] && has "BLOCKED: scope" && [ "$(sget stopped_reason)" = scope ] && ! rowof U2-fix2 >/dev/null'
must clear-stop "$H"
must fix "$H" add U2-fix2 --key ./fail.sh --repo dn --files lib/b.txt --summary 2회차
eg fix "$H" add U2-fix3 --key ./fail.sh --repo dn --files lib/b.txt --summary 3회차
t "완료 판정: 3번째 보정 → fix-cap 중단" '[ $RC = 1 ] && has "BLOCKED: fix-cap" && [ "$(sget stopped_reason)" = fix-cap ] && ! rowof U2-fix3 >/dev/null && grep -q "^중단: fix-cap$" "$H"'
must unit "$H" U2-fix1 start
t "재위임 키: 보정 단위는 등록한 완료 기준 키" '[ "$(sget units.U2-fix1.key)" = ./fail.sh ]'
eg redeleg "$H" ./fail.sh incr; a=$OUT; eg redeleg "$H" ./fail.sh incr; b=$OUT; eg redeleg "$H" ./fail.sh incr
t "재위임 한도: 같은 키 3번째 거부(보정 단위끼리 공유)" '[ "$a" = 1 ] && [ "$b" = 2 ] && [ $RC = 1 ] && has "재위임 한도"'
eg redeleg "$H" integration incr; eg redeleg "$H" integration incr; eg redeleg "$H" integration incr
t "재위임 한도: integration 키도 2회" '[ $RC = 1 ] && [ "$(bash "$EG" redeleg "$H" integration get)" = 2 ]'
eg redeleg "$H" ./fail.sh reset; eg redeleg "$H" ./fail.sh get
t "재위임: reset 뒤 0" '[ "$OUT" = 0 ]'

# ── 외부 커밋 ─────────────────────────────────────────
setup xa "$OKCMD" "$TWO"; must init "$H"; ext; eg unit "$H" U1 start
t "외부 커밋: init 직후 → blocked" '[ $RC = 1 ] && has "expected_tip" && rowis U1 blocked && [ "$(sget stopped_reason)" = blocked:U1 ] && grep -q "^중단: blocked:U1$" "$H" && ! brtip U1 >/dev/null'
setup xb "$OKCMD" "$TWO"; must init "$H"; work U1
must unit "$H" U1 commit -m U1; must unit "$H" U1 merge; must unit "$H" U1 cleanup
ext; eg unit "$H" U2 start
t "외부 커밋: 두 단위 사이 → blocked" '[ $RC = 1 ] && has "expected_tip" && rowis U2 blocked && rowis U1 완료'
setup xc "$OKCMD" "$TWO"; must init "$H"; must unit "$H" U1 start; must unit "$H" U1 commit -m U1
t "무변경 단위: commit → NOCHANGE" '[ "$OUT" = NOCHANGE ]'
ext; eg unit "$H" U1 merge
t "외부 커밋: 무변경 단위 ④ → blocked" '[ $RC = 1 ] && has "expected_tip" && rowis U1 blocked && ! rowof U1 | grep -F "$NOCH" >/dev/null'

# ── 워크트리·흔적 ─────────────────────────────────────
setup w1 "$OKCMD" "$TWO"; must init "$H"; printf 'z\n' >> "$R/lib/b.txt"; eg unit "$H" U1 start
t "흔적: 시작 때 합집합 안 다른 단위 파일 더티 → blocked" '[ $RC = 1 ] && has "미커밋 변경 lib/b.txt" && rowis U1 blocked && ! brtip U1 >/dev/null'
setup w2 "$OKCMD" "$TWO"; must init "$H"; printf 'z\n' >> "$R/src/a.txt"; eg unit "$H" U1 start
t "흔적: 시작 때 pathspec 파일 더티 → blocked" '[ $RC = 1 ] && has "미커밋 변경 src/a.txt"'
setup w3 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1; ext; eg unit "$H" U1 merge
t "흔적: Worker 중 남의 커밋(pathspec 밖) → blocked·워크트리 커밋 보존" '[ $RC = 1 ] && has "expected_tip" && [ -n "$(sget units.U1.commit)" ] && [ "$(brtip U1)" = "$(sget units.U1.commit)" ]'
setup w4 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
git -C "$R" switch -q -c other; eg unit "$H" U1 merge
t "흔적: 같은 OID 의 다른 브랜치로 전환 → blocked" '[ $RC = 1 ] && has "대상 브랜치 refs/heads/main" && [ "$(git -C "$R" rev-parse main)" = "$(sget repos.w4.init_head)" ] && [ "$(git -C "$R" rev-parse other)" = "$(sget repos.w4.init_head)" ]'
setup w5 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
printf 'mine\n' > "$R/src/a.txt"; eg unit "$H" U1 merge
t "흔적: 머지가 바꿀 파일을 밖에서 수정 → blocked" '[ $RC = 1 ] && has "미커밋 변경 src/a.txt" && [ "$(cat "$R/src/a.txt")" = mine ] && [ "$(git -C "$R" rev-parse HEAD)" = "$(sget repos.w5.init_head)" ]'
setup w5b "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
wrap touch unit "$H" U1 merge
t "흔적: 검사 뒤 머지 직전에 같은 파일 수정 → 머지 거부·blocked" '[ $RC = 1 ] && has "머지 거부" && [ "$(cat "$R/src/a.txt")" = race ] && [ "$(git -C "$R" rev-parse HEAD)" = "$(sget repos.w5b.init_head)" ] && [ "$(brtip U1)" = "$(sget units.U1.commit)" ]'
setup w6 "$OKCMD" "$(row U1 src/new.txt)"; must init "$H"
printf 'new.txt\n' > "$R/src/.gitignore"; printf 'old\n' > "$R/src/new.txt"   # 공유 트리에서만 무시되는 파일
must unit "$H" U1 start; printf 'unit\n' > "$(wt U1)/src/new.txt"; must unit "$H" U1 commit -m U1; eg unit "$H" U1 merge
t "흔적: 들어올 새 파일과 겹치는 무시 파일 → 사전 검사 blocked" '[ $RC = 1 ] && has "무시 파일 src/new.txt" && [ "$(cat "$R/src/new.txt")" = old ]'
setup w7 "$OKCMD" "$TWO"; must init "$H"; printf 'x\n' >> "$R/other.txt"; work U1
must unit "$H" U1 commit -m U1; eg unit "$H" U1 merge
t "흔적: pathspec 밖 파일만 더티 → 정상 진행" '[ $RC = 0 ] && rowis U1 완료 && grep -q "^x$" "$R/other.txt" && [ "$(git -C "$R" show HEAD:src/a.txt)" = a1 ]'
setup w8 "$OKCMD" "$TWO"; must init "$H"; work U1; printf 'b1\n' > "$(wt U1)/lib/b.txt"; eg unit "$H" U1 checkwt
t "흔적: 워크트리 변경이 pathspec 밖으로 → 3단계 blocked" '[ $RC = 1 ] && has "pathspec 밖 lib/b.txt" && rowis U1 blocked'
must clear-stop "$H"; eg unit "$H" U1 commit -m U1
t "흔적: 같은 상태로 커밋 → ① blocked·커밋 0" '[ $RC = 1 ] && has "pathspec 밖 lib/b.txt" && [ "$(brtip U1)" = "$(sget units.U1.base_head)" ]'
setup w9 "$OKCMD" "$(row U1 src/)"; must init "$H"; work U1
printf 'n\n' > "$(wt U1)/src/new.txt"; printf '\000\377\001' > "$(wt U1)/src/img.bin"; printf '\000\377\001' > "$TMP/img.exp"
eg unit "$H" U1 checkwt
t "흔적: 신규 파일·바이너리 → 검수 diff 에 포함" '[ $RC = 0 ] && has "src/new.txt" && has "src/img.bin" && has "src/a.txt"'
must unit "$H" U1 commit -m U1; must unit "$H" U1 merge; must unit "$H" U1 cleanup
t "흔적: 신규 파일·바이너리 → 커밋·머지에 포함" 'cmp -s "$R/src/img.bin" "$TMP/img.exp" && [ "$(cat "$R/src/new.txt")" = n ] && [ -z "$(git -C "$R" status --porcelain -- src)" ]'
setup w10 "$OKCMD" "$TWO"; must init "$H"; must unit "$H" U1 start; must unit "$H" U1 commit -m U1; eg unit "$H" U1 merge
t "흔적: Worker 무변경 → 커밋 없이 완료·없음(변경 없음)" '[ $RC = 0 ] && rowis U1 완료 && rowof U1 | grep -F "$NOCH" >/dev/null && [ "$(git -C "$R" rev-parse HEAD)" = "$(sget repos.w10.init_head)" ]'
setup g1 "$OKCMD" "$(row U1 .)"; must init "$H"; must unit "$H" U1 start
mkdir -p "$(wt U1)/.claude"; printf '{}\n' > "$(wt U1)/.claude/settings.json"; eg unit "$H" U1 checkwt
t "권위 관문: 워크트리 변경이 .claude/settings.json → blocked·커밋 0" '[ $RC = 1 ] && has "권위 관문 .claude/settings.json" && ! has "pathspec 밖" && [ "$(brtip U1)" = "$(sget units.U1.base_head)" ]'

# ── 단위 복구 ─────────────────────────────────────────
setup r1 "$OKCMD" "$TWO"; must init "$H"; work U1
must state "$H" set units.U1.stage committing   # commit 하위 명령이 커밋 의도를 남긴 뒤
git -C "$(wt U1)" add -A && git -C "$(wt U1)" commit -q -m manual   # 커밋 직후·기록 전에 끊긴 상황
eg unit "$H" U1 recover
t "복구: 커밋 뒤 끊김 → merge·commit 기록 복원" '[ "$OUT" = merge ] && [ "$(sget units.U1.commit)" = "$(brtip U1)" ]'
must unit "$H" U1 merge; must unit "$H" U1 cleanup
t "복구: 커밋 뒤 → 커밋 한 번만·자산 0" '[ "$(git -C "$R" rev-list --count "$(sget repos.r1.init_head)..HEAD")" = 1 ] && ! brtip U1 >/dev/null && [ ! -e "$(wt U1)" ]'
setup r2 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
git -C "$R" merge -q --ff-only "$(sget units.U1.commit)"   # 머지 직후·기록 전에 끊긴 상황
eg unit "$H" U1 recover
t "복구: ff 뒤 끊김 → cleanup·행 완료·expected_tip" '[ "$OUT" = cleanup ] && rowis U1 완료 && [ "$(sget repos.r2.expected_tip)" = "$(sget units.U1.commit)" ]'
must unit "$H" U1 cleanup; eg unit "$H" U1 recover
t "복구: ff 뒤 → 정리 뒤 done·커밋 한 번만" '[ "$OUT" = done ] && [ "$(git -C "$R" rev-list --count "$(sget repos.r2.init_head)..HEAD")" = 1 ] && ! brtip U1 >/dev/null'
setup r3 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1; must unit "$H" U1 merge
eg unit "$H" U1 recover
t "복구: 행 완료 뒤·정리 전 → cleanup" '[ "$OUT" = cleanup ]'
must unit "$H" U1 cleanup; eg unit "$H" U1 recover
t "복구: 정리 뒤 → done·stage cleaned" '[ "$OUT" = done ] && [ "$(sget units.U1.stage)" = cleaned ]'
setup r4 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1; must unit "$H" U1 merge
git -C "$R" worktree remove "$(wt U1)"   # 워크트리 제거 직후·브랜치 삭제 전에 끊긴 상황
eg unit "$H" U1 recover
t "복구: 워크트리 제거 뒤 끊김 → cleanup" '[ "$OUT" = cleanup ]'
must unit "$H" U1 cleanup
t "복구: 워크트리 제거 뒤 → 브랜치까지 정리" '! brtip U1 >/dev/null && [ "$(sget units.U1.stage)" = cleaned ]'
setup r5 "$OKCMD" "$TWO"; must init "$H"; must unit "$H" U1 start; must unit "$H" U1 commit -m U1; must unit "$H" U1 merge
eg unit "$H" U1 recover
t "복구: 무변경 완료 뒤·정리 전 → cleanup" '[ "$OUT" = cleanup ]'
must unit "$H" U1 cleanup; eg unit "$H" U1 recover
t "복구: 무변경 정리 뒤 → done" '[ "$OUT" = done ] && ! brtip U1 >/dev/null'
setup r6 "$OKCMD" "$TWO"; must init "$H"; eg unit "$H" U1 recover
t "복구: 시작 전 → start" '[ "$OUT" = start ]'
work U1; eg unit "$H" U1 recover
t "복구: Worker 작업 중 → worker" '[ "$OUT" = worker ]'
must state "$H" set units.U1.stage reviewed; eg unit "$H" U1 recover
t "복구: reviewed 에서 끊김 → review(5단계부터)" '[ "$OUT" = review ]'
must unit "$H" U1 commit -m U1; must unit "$H" U1 merge; must unit "$H" U1 cleanup
must unit "$H" U2 start; must state "$H" set units.U2 null   # 브랜치를 만든 직후·기록 전에 끊긴 상황
eg unit "$H" U2 recover
t "복구: 브랜치 생성 뒤 기록 전 끊김 → worker·기록 복원" '[ "$OUT" = worker ] && [ "$(sget units.U2.base_head)" = "$(sget repos.r6.expected_tip)" ]'

# ── 머지 뒤 재검증 ────────────────────────────────────
setup v1 "$OKCMD" "$SRC2"; must init "$H"; work U1; printf 'n\n' > "$(wt U1)/src/n.txt"; must unit "$H" U1 commit -m U1
base=$(sget units.U1.base_head); cm=$(sget units.U1.commit)
git -C "$R" branch other   # 같은 OID 의 브랜치가 머지 전부터 있다(스냅샷에 base 로 잡힌다)
wrap switch-existing unit "$H" U1 merge
t "머지 뒤 재검증: 틈에 같은 OID 다른 브랜치로 전환 → blocked" '[ $RC = 1 ] && has "머지 뒤 재검증 실패" && rowis U1 blocked'
t "머지 뒤 재검증: 체크아웃된 브랜치가 전진했으면 되돌리지 않고 ff_misapplied·정리 안내" '[ "$(git -C "$R" rev-parse other)" = "$cm" ] && [ "$(git -C "$R" rev-parse main)" = "$base" ] && [ "$(brtip U1)" = "$cm" ] && [ "$(sget units.U1.ff_misapplied.cm)" = "$cm" ] && has "자동으로 되돌리지 않는다" && has "git reset"'
t "머지 뒤 재검증: 작업 트리·인덱스는 건드리지 않는다(staged 0)" '[ -e "$R/src/n.txt" ] && [ "$(cat "$R/src/a.txt")" = a1 ] && git -C "$R" diff --cached --quiet && [ -z "$(git -C "$R" status --porcelain -- src)" ]'
setup v2 "$OKCMD" "$SRC2"; must init "$H"; work U1; printf 'n\n' > "$(wt U1)/src/n.txt"; must unit "$H" U1 commit -m U1
base=$(sget units.U1.base_head); cm=$(sget units.U1.commit)
wrap detach unit "$H" U1 merge
t "머지 뒤 재검증: 틈에 분리 HEAD → 소유 불명이라 되돌리지 않고 ff_misapplied·blocked" '[ $RC = 1 ] && has "사람이 확인" && ! git -C "$R" symbolic-ref -q HEAD >/dev/null && [ "$(git -C "$R" rev-parse HEAD)" = "$cm" ] && [ "$(git -C "$R" rev-parse main)" = "$base" ] && [ -e "$R/src/n.txt" ] && [ "$(sget units.U1.ff_misapplied.cm)" = "$cm" ]'
setup v3 "$OKCMD" "$SRC2"; must init "$H"; work U1; printf 'n\n' > "$(wt U1)/src/n.txt"; must unit "$H" U1 commit -m U1
base=$(sget units.U1.base_head); cm=$(sget units.U1.commit)
wrap switch unit "$H" U1 merge
t "머지 뒤 재검증: 틈에 새 브랜치로 전환 → 소유 불명이라 되돌리지 않고 ff_misapplied" '[ $RC = 1 ] && has "사람이 확인" && [ "$(git -C "$R" rev-parse other)" = "$cm" ] && [ "$(git -C "$R" rev-parse main)" = "$base" ] && [ -e "$R/src/n.txt" ]'
eg unit "$H" U1 recover
t "머지 뒤 재검증: ff_misapplied 가 있으면 recover 도 거부" '[ $RC = 1 ] && has "ff_misapplied"'

# ── 워크트리 제거 ─────────────────────────────────────
setup d1 "$OKCMD" "$TWO"; must init "$H"; work U1
mkdir -p "$(wt U1)/src/__pycache__"; printf 'c' > "$(wt U1)/src/__pycache__/x.pyc"
must unit "$H" U1 commit -m U1; must unit "$H" U1 merge; eg unit "$H" U1 cleanup
t "워크트리 제거: 무시 파일(__pycache__)만 남음 → 성공" '[ $RC = 0 ] && [ ! -e "$(wt U1)" ] && [ "$(sget units.U1.stage)" = cleaned ]'
setup d2 "$OKCMD" "$TWO"; must init "$H"; work U1
mkdir -p "$(wt U1)/.relay-logs"; printf 'log\n' > "$(wt U1)/.relay-logs/w.log"
must unit "$H" U1 checkwt; must unit "$H" U1 commit -m U1; must unit "$H" U1 merge; eg unit "$H" U1 cleanup
t "워크트리 제거: .relay-logs 남음 → 옮긴 뒤 성공·커밋 제외" '[ $RC = 0 ] && [ "$(cat "$P/U1/logs/w.log")" = log ] && [ ! -e "$(wt U1)" ] && ! git -C "$R" show --name-only --format= HEAD | grep -F relay-logs >/dev/null'
setup d3 "$OKCMD" "$TWO"; must init "$H"; work U1; printf 's\n' > "$(wt U1)/stray.txt"; eg unit "$H" U1 commit -m U1
t "워크트리 제거: 미추적 비무시 파일 → ①에서 먼저 blocked" '[ $RC = 1 ] && has "pathspec 밖 stray.txt" && [ "$(brtip U1)" = "$(sget units.U1.base_head)" ]'
setup d4 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1; must unit "$H" U1 merge
printf 's\n' > "$(wt U1)/late.txt"; eg unit "$H" U1 cleanup
t "워크트리 제거 실패 → exit 1·stage merged 유지·브랜치 남김" '[ $RC = 1 ] && has "워크트리 제거 실패" && [ "$(sget units.U1.stage)" = merged ] && brtip U1 >/dev/null'
setup d5 "$OKCMD" "$TWO"; must init "$H"; work U1
mkdir -p "$(wt U1)/.relay-logs"; printf 'report\n' > "$(wt U1)/.relay-logs/REPORT.md"; printf 'log\n' > "$(wt U1)/.relay-logs/test.log"
must unit "$H" U1 commit -m U1; must unit "$H" U1 merge; eg unit "$H" U1 cleanup
t "정리: .relay-logs/REPORT.md 는 단위 폴더로·나머지는 logs/ 로" '[ $RC = 0 ] && [ "$(cat "$P/U1/REPORT.md")" = report ] && [ "$(cat "$P/U1/logs/test.log")" = log ] && [ ! -e "$P/U1/logs/REPORT.md" ] && [ ! -e "$(wt U1)" ] && has "옮김: U1/REPORT.md"'
setup d6 "$OKCMD" "$TWO"; must init "$H"; work U1; printf 'old\n' > "$P/U1/REPORT.md"
mkdir -p "$(wt U1)/.relay-logs"; printf 'new\n' > "$(wt U1)/.relay-logs/REPORT.md"
must unit "$H" U1 commit -m U1; must unit "$H" U1 merge; eg unit "$H" U1 cleanup
t "정리: 단위 폴더에 REPORT.md 가 이미 있으면 덮어쓰지 않고 REPORT.1.md" '[ $RC = 0 ] && [ "$(cat "$P/U1/REPORT.md")" = old ] && [ "$(cat "$P/U1/REPORT.1.md")" = new ]'

# ── 경계·만료 ─────────────────────────────────────────
setup b1 "$OKCMD" "$TWO"; must init "$H"; work U1
must state "$H" set units.U1.stage reviewed; must state "$H" set started_at 2020-01-01T00:00:00+00:00
eg unit "$H" U1 commit -m U1
t "경계: 최대 시간(커밋 직전) → limit:duration·행 진행·stage reviewed·커밋 0" '[ $RC = 1 ] && has "limit:duration" && grep -q "^중단: limit:duration$" "$H" && rowis U1 진행 && [ "$(sget units.U1.stage)" = reviewed ] && [ "$(brtip U1)" = "$(sget units.U1.base_head)" ]'
setup b2 "$OKCMD" "$TWO"; must init "$H"; work U1
perl -pi -e 's/^커밋 정책:.*/커밋 정책: 확인 후/' "$H"; eg unit "$H" U1 commit -m U1
t "경계: 자동 승인 만료 → expired·행 진행·커밋 0" '[ $RC = 1 ] && has "expired" && [ "$(sget stopped_reason)" = expired ] && rowis U1 진행 && [ "$(brtip U1)" = "$(sget units.U1.base_head)" ]'

# ── stop·status-json·clean ────────────────────────────
setup s1 "$OKCMD" "$TWO"; must init "$H"; must state "$H" set iterations 20
eg status-json "$H"
t "status-json: 반복·단위 요약" '[ "$(jget iterations)" = 20 ] && [ "$(jget max_iterations)" = 20 ] && [ "$(jget unfinished)" = 2 ] && [ "$(jget blocked)" = 0 ] && [ "$(jget last_eval)" = null ]'
eg stop "$H" limit:iterations
t "stop: limit:iterations → 중단 줄·행 변경 없음" '[ $RC = 0 ] && grep -q "^중단: limit:iterations$" "$H" && rowis U1 미착수 && rowis U2 미착수'
must clear-stop "$H"; eg stop "$H" rotate
t "stop: rotate → stopped_reason 만·중단 줄 없음" '[ "$(sget stopped_reason)" = rotate ] && ! grep -q "^중단:" "$H"'
eg stop "$H" blocked:U2
t "stop: blocked:<단위> → 행 blocked·중단 줄" 'rowis U2 blocked && grep -q "^중단: blocked:U2$" "$H"'
eg status-json "$H"
t "status-json: blocked 집계·중단 사유" '[ "$(jget blocked)" = 1 ] && [ "$(jget stopped_reason)" = blocked:U2 ]'
eg stop "$H" bogus
t "stop: 모르는 사유 → 사용 오류" '[ $RC = 2 ]'
must clear-stop "$H"; eg clean "$H" s1
t "clean: 깨끗하면 통과" '[ $RC = 0 ] && has "OK: clean s1"'
printf 'z\n' >> "$R/lib/b.txt"; eg clean "$H" s1 --pathspec src/a.txt
t "clean: --pathspec 경로만 본다" '[ $RC = 0 ]'
eg clean "$H" s1
t "clean: 합집합 더티 → exit 1" '[ $RC = 1 ] && has "lib/b.txt"'

# ── 되돌린 단위 ───────────────────────────────────────
setup ds "$OKCMD" "$TWO"; must init "$H"; work U1; must redeleg "$H" U1 incr
printf 'b1\n' > "$(wt U1)/lib/b.txt"; eg unit "$H" U1 checkwt                   # 범위 밖 → blocked
printf 'a\n' > "$(wt U1)/src/a.txt"; printf 'b\n' > "$(wt U1)/lib/b.txt"         # 사용자가 워크트리를 정리한다
mkdir -p "$(wt U1)/.relay-logs"; printf 'r\n' > "$(wt U1)/.relay-logs/REPORT.md"
setrow U1 미착수; must clear-stop "$H"; eg unit "$H" U1 discard
t "되돌린 단위: discard → 브랜치 이름 보존·워크트리·기록·카운터 정리" '[ $RC = 0 ] && [ -e "$P/U1/logs/REPORT.md" ] && [ ! -e "$P/U1/REPORT.md" ] && "$REALGIT" -C "$R" rev-parse -q --verify refs/heads/relay/p1/U1.discarded-1 >/dev/null && ! brtip U1 >/dev/null && [ ! -e "$(wt U1)" ] && ! sget units.U1 >/dev/null && [ "$(bash "$EG" redeleg "$H" U1 get)" = 0 ]'
work U1; setrow U1 미착수; eg unit "$H" U1 discard
t "되돌린 단위: 더티 워크트리 → 제거 실패·blocked 되살림" '[ $RC = 1 ] && rowis U1 blocked && grep -q "^중단: blocked:U1$" "$H" && [ -e "$(wt U1)" ]'

# ── 검토 지적 재현(2026-10-20 codex 15건, 재현 조건 그대로 + 보강) ─────────
# #1 머지 뒤 되돌림이 무시 파일을 덮어쓰지 않는다
setup f1 "$OKCMD" "$TWO"; must init "$H"; must unit "$H" U1 start
rm "$(wt U1)/src/a.txt"; must unit "$H" U1 commit -m delete-a
printf '/src/a.txt\n' >> "$R/.git/info/exclude"
wrap ignored-new unit "$H" U1 merge
t "#1 되돌림: 틈에 새 브랜치·무시 파일 → 아무것도 되돌리지 않음·ff_misapplied" '[ $RC = 1 ] && [ "$(cat "$R/src/a.txt")" = user-ignored-data ] && has "사람이 확인" && sget units.U1.ff_misapplied >/dev/null'
setup f1b "$OKCMD" "$TWO"; must init "$H"; must unit "$H" U1 start
rm "$(wt U1)/src/a.txt"; must unit "$H" U1 commit -m delete-a; base=$(sget units.U1.base_head); cm=$(sget units.U1.commit)
git -C "$R" branch other; printf '/src/a.txt\n' >> "$R/.git/info/exclude"
wrap ignored-existing unit "$H" U1 merge
t "#1 되돌림: 되돌릴 ref 가 체크아웃돼 있으면 ref·파일 그대로·ff_misapplied" '[ $RC = 1 ] && has "자동으로 되돌리지 않는다" && [ "$(cat "$R/src/a.txt")" = user-ignored-data ] && [ "$(git -C "$R" rev-parse other)" = "$cm" ] && [ "$(git -C "$R" rev-parse main)" = "$base" ] && [ "$(sget units.U1.ff_misapplied.cm)" = "$cm" ]'

# #2 워크트리 정체성을 확인한 뒤에만 워크트리에서 git 을 돌린다
setup f2 "$OKCMD" "$TWO"; must init "$H"; must unit "$H" U1 start
git -C "$R" worktree remove "$(wt U1)"; mkdir -p "$(wt U1)"
printf 'staged-only-version\n' > "$R/other.txt"; git -C "$R" add other.txt; printf 'working-version\n' > "$R/other.txt"
eg unit "$H" U1 checkwt
t "#2 워크트리 정체성: 지운 워크트리 자리의 빈 폴더 → 아무것도 하지 않고 blocked" '[ $RC = 1 ] && has "워크트리 정체성" && [ "$(git -C "$R" show :other.txt)" = staged-only-version ] && [ "$(cat "$R/other.txt")" = working-version ]'
setup f2b "$OKCMD" "$TWO"; must init "$H"; work U1; git -C "$(wt U1)" switch -q -c elsewhere; eg unit "$H" U1 commit -m U1
t "#2 워크트리 정체성: 워크트리가 다른 브랜치 → blocked·커밋 0" '[ $RC = 1 ] && has "브랜치에 있지 않다" && [ "$(brtip U1)" = "$(sget units.U1.base_head)" ]'
setup f2c "$OKCMD" "$TWO"; must init "$H"; work U1; mv "$(wt U1)" "$TMP/f2c-real"; ln -s "$TMP/f2c-real" "$(wt U1)"
eg unit "$H" U1 checkwt
t "#2 워크트리 정체성: 워크트리 경로가 심볼릭 링크 → blocked" '[ $RC = 1 ] && has "심볼릭 링크"'

# #3 되돌릴 ref 는 머지 전후 스냅샷으로 정한다. 대상 브랜치가 커밋이면 성공이다
setup f3 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1; cm=$(sget units.U1.commit)
git -C "$R" branch other "$cm"
wrap after-switch unit "$H" U1 merge
t "#3 재검증: 머지 뒤 다른 브랜치로 옮겨도 대상 브랜치가 커밋이면 성공·다른 ref 불변" '[ $RC = 0 ] && [ "$(git -C "$R" rev-parse main)" = "$cm" ] && [ "$(git -C "$R" rev-parse other)" = "$cm" ] && rowis U1 완료 && has "주의"'

# #4 .relay-logs 링크를 따라가지 않는다
setup f4 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1; must unit "$H" U1 merge
mkdir -p "$TMP/user-data"; printf 'precious\n' > "$TMP/user-data/data.txt"; ln -s "$TMP/user-data" "$(wt U1)/.relay-logs"
eg unit "$H" U1 cleanup
t "#4 로그 이동: .relay-logs 가 링크 → 옮기지 않고 blocked·기록" '[ $RC = 1 ] && [ "$(cat "$TMP/user-data/data.txt")" = precious ] && [ ! -e "$P/U1/logs/data.txt" ] && sget units.U1.logs_error >/dev/null && [ -e "$(wt U1)" ] && [ "$(sget units.U1.stage)" = merged ]'

# #5 이미 만든 커밋도 검사한다. 이 세션이 커밋 의도를 남기지 않은 커밋은 받지 않는다
setup f5 "$OKCMD" "$TWO"; must init "$H"; must unit "$H" U1 start
mkdir -p "$(wt U1)/.claude"; printf '{}\n' > "$(wt U1)/.claude/settings.json"
git -C "$(wt U1)" add .claude/settings.json && git -C "$(wt U1)" commit -q -m outside-gate   # Worker 가 직접 커밋
eg unit "$H" U1 recover
t "#5 출처 불명 커밋: Worker 가 직접 한 커밋 → recover 가 받지 않고 blocked" '[ $RC = 1 ] && has "출처 불명" && rowis U1 blocked'
must clear-stop "$H"; eg unit "$H" U1 merge
t "#5 출처 불명 커밋: merge 도 blocked·공유 트리 무변경" '[ $RC = 1 ] && has "출처 불명" && [ ! -e "$R/.claude/settings.json" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$(sget repos.f5.init_head)" ]'
setup f5b "$OKCMD" "$TWO"; must init "$H"; work U1; printf 'b1\n' > "$(wt U1)/lib/b.txt"
must state "$H" set units.U1.stage committing
git -C "$(wt U1)" add -A && git -C "$(wt U1)" commit -q -m mixed   # 기록 전에 끊긴 커밋에 pathspec 밖 파일이 섞였다
eg unit "$H" U1 recover
t "#5 커밋 전체 검사: 받은 커밋에 pathspec 밖 파일 → blocked" '[ $RC = 1 ] && has "커밋에 pathspec 밖 파일 lib/b.txt"'
setup f5c "$OKCMD" "$TWO"; must init "$H"; work U1; git -C "$(wt U1)" commit -q -am worker-commit; eg unit "$H" U1 commit -m U1
t "#5 커밋 전 HEAD 확인: 워크트리에 이 세션 것이 아닌 커밋 → blocked" '[ $RC = 1 ] && has "이 세션이 만들지 않은 커밋"'

# #6 자동 승인 범위를 기계로 해석한다
POLICY='자동 승인: U2만 / 만료: 계획 완료' setup f6 "$OKCMD" "$TWO"; eg init "$H"
t "#6 자동 승인: 해석 못 하는 범위(U2만) → init 거부" '[ $RC = 1 ] && hasline "FAIL 커밋 정책" "해석하지 못했다" && [ ! -e "$P/goal/state.json" ]'
POLICY='자동 승인: U2(보정 단위 포함) / 만료: 계획 완료' mkhandoff "$OKCMD" "$TWO"; eg init "$H"
t "#6 자동 승인: 일부 단위만 승인 → init 거부" '[ $RC = 1 ] && has "범위 밖 단위 U1" && [ ! -e "$P/goal/state.json" ]'
POLICY='자동 승인: 전부 / 만료: 계획 완료' mkhandoff "$OKCMD" "$TWO"; eg check "$H"
t "#6 자동 승인: 보정 단위 포함이 없으면 거부" '[ $RC = 1 ] && has "보정 단위 포함"'
POLICY='자동 승인: U1~U2(보정 단위 포함) / 만료: 계획 완료' mkhandoff "$OKCMD" "$TWO"; eg check "$H"; a=$RC
POLICY='자동 승인: U1,U2(보정 단위 포함) / 만료: 계획 완료' mkhandoff "$OKCMD" "$TWO"; eg check "$H"
t "#6 자동 승인: U1~U2·U1,U2 형식 통과" '[ "$a" = 0 ] && [ $RC = 0 ]'
must init "$H"; work U1
perl -pi -e 's/^커밋 정책:.*/커밋 정책: 자동 승인: U2(보정 단위 포함) \/ 만료: 계획 완료/' "$H"
eg unit "$H" U1 commit -m U1
t "#6 자동 승인: 커밋 때 범위 밖 단위 → expired·행 진행·커밋 0" '[ $RC = 1 ] && has "자동 승인 범위" && [ "$(sget stopped_reason)" = expired ] && rowis U1 진행 && [ "$(brtip U1)" = "$(sget units.U1.base_head)" ]'

# #7 제한 시간 뒤 남은 자식 프로세스
setup f7 "$OKCMD" "$(row U1 src/a.txt)"
sh_ "$R/child.sh" 'echo $$ > "$PIDF"; sleep 4; echo child-survived > "$MARK"'   # 자식이 자기 PID 를 남긴다(제한 1초 뒤에도 충분히 살아 있게 4초)
sh_ "$R/parent.sh" './child.sh & wait'
git -C "$R" add parent.sh child.sh && git -C "$R" commit -q -m child-fixture
mkhandoff '  cmd: ./parent.sh
  timeout: 1s' "$(row U1 src/a.txt)"
must init "$H"; rm -f "$MARK" "$PIDF"; eg run "$H"
t "#7 제한 시간: 남은 자식 → 끝내지 않고 timeout-survivors 로 멈춤·기록" '[ $RC = 1 ] && has "timeout-survivors" && [ "$(sget stopped_reason)" = timeout-survivors ] && grep -q "^중단: timeout-survivors$" "$H" && grep -qF "남은 프로세스" "$P/goal/1.log"'
t "B6 제한 시간: survivors 배열에 그 자식의 PID 가 있다" 'survivor_pid "$PIDF"'
sleep 5
t "#7 제한 시간: 남은 프로세스는 기록만 하고 끝내지 않는다(전역 규칙)" '[ "$(cat "$MARK" 2>/dev/null)" = child-survived ]'

# #8 rm -r 은 인자 배열로 본다
setup f8 '  cmd: rm -f -r /nonexistent-eg-x
  cmd: rm -rf /nonexistent-eg-x
  cmd: rm --force --recursive /nonexistent-eg-x
  cmd: rm -R /nonexistent-eg-x
  cmd: rm --rec /nonexistent-eg-x
  cmd: /bin/rm -f -- -r' "$(row U1 src/a.txt)"
eg check "$H"
t "#8 rm 검사: rm -f -r 거부" 'hasline "FAIL cmd 1:" "금지 패턴 rm -r"'
t "#8 rm 검사: rm -rf 거부" 'hasline "FAIL cmd 2:" "금지 패턴 rm -r"'
t "#8 rm 검사: rm --force --recursive 거부" 'hasline "FAIL cmd 3:" "금지 패턴 rm -r"'
t "#8 rm 검사: rm -R 거부" 'hasline "FAIL cmd 4:" "금지 패턴 rm -r"'
t "#8 rm 검사: 긴 옵션 줄임(--rec) 거부" 'hasline "FAIL cmd 5:" "금지 패턴 rm -r"'
t "#8 rm 검사: -- 뒤의 -r 은 파일 이름이라 통과" 'hasline "PASS cmd 6:" "/bin/rm"'

# #9 동시 갱신: 잠그고, 쓰기 직전에 다시 읽어 바꾸는 키·줄만 고친다
setup f9 "$OKCMD" "$TWO"
sh_ "$R/stopper.sh" 'bash "$REVIEW_EG" stop "$REVIEW_H" scope; printf "\n## User note\nkeep-me\n" >> "$REVIEW_H"'
git -C "$R" add stopper.sh && git -C "$R" commit -q -m stopper-fixture
mkhandoff '  cmd: ./stopper.sh' "$TWO"; must init "$H"
export REVIEW_EG="$EG" REVIEW_H="$H"; eg run "$H"
t "#9 동시 갱신: run 중 stop·사용자 메모 → 둘 다 보존" '[ $RC = 0 ] && [ "$(sget stopped_reason)" = scope ] && grep -q "^중단: scope$" "$H" && grep -q "^keep-me$" "$H" && grep -q "^최근 조건 평가: 1 " "$H"'
python3 -I -c 'import fcntl, sys, time; f = open(sys.argv[1], "a"); fcntl.flock(f, fcntl.LOCK_EX); time.sleep(3)' "$P/goal/.lock" &
holder=$!; sleep 1; s0=$(date +%s); eg clear-stop "$H"; s1=$(date +%s); wait "$holder"
t "#9 잠금: 다른 쓰기가 goal/.lock 을 쥐면 풀릴 때까지 기다린다" '[ $RC = 0 ] && [ $((s1 - s0)) -ge 1 ] && [ -z "$(sget stopped_reason)" ]'

# #10 계획 폴더 제외는 기본 저장소에만
mkrepo "$TMP/secondary"; mkdir -p "$TMP/secondary/docs/relay/p1"; printf 'one\n' > "$TMP/secondary/docs/relay/p1/input.txt"
git -C "$TMP/secondary" add docs && git -C "$TMP/secondary" commit -q -m secondary-data
setup f10 '  cmd: ./count.sh' "$(row U1 src/a.txt)
$(row U2 secondary:docs/relay/p1/input.txt)" "저장소: secondary=$TMP/secondary"
must init "$H"; rm -f "$COUNT"; eg run "$H"
printf 'two\n' > "$TMP/secondary/docs/relay/p1/input.txt"; eg clean "$H" secondary
t "#10 보조 저장소: 같은 이름 계획 경로의 변경도 더티" '[ $RC = 1 ] && has "docs/relay/p1/input.txt"'
eg run "$H"
t "#10 보조 저장소: 그 변경이 트리 키에 들어가 재실행" '! has "이전 실행" && [ "$(runs)" = 2 ]'

# #11 공백이 든 경로는 따옴표로. 따옴표 없는 공백은 모호해 거부
setup f11 "$OKCMD" "$(row U1 'src/a b.txt')"; eg check "$H"
t "#11 공백 경로: 따옴표 없는 공백 → 모호해 check 거부" '[ $RC = 1 ] && has "모호한 경로"'
eg init "$H"
t "#11 공백 경로: init 도 거부" '[ $RC = 1 ] && [ ! -e "$P/goal/state.json" ]'
mkhandoff "$OKCMD" "$(row U1 '"src/a b.txt"')"; must init "$H"; must unit "$H" U1 start
printf 'outside\n' > "$(wt U1)/b.txt"; eg unit "$H" U1 commit -m wrong
t "#11 공백 경로: 따옴표로 감싸면 한 경로라 루트 b.txt 는 범위 밖" '[ $RC = 1 ] && has "pathspec 밖 b.txt"'
rm "$(wt U1)/b.txt"; must clear-stop "$H"; setrow U1 진행
printf 'spaced\n' > "$(wt U1)/src/a b.txt"; must unit "$H" U1 commit -m U1; must unit "$H" U1 merge
t "#11 공백 경로: 공백 든 파일이 커밋·머지된다" '[ "$(cat "$R/src/a b.txt")" = spaced ] && rowis U1 완료'
setup f11c "$OKCMD" "$(row U1 '"src/a b.txt"' 완료)
$(row U2 lib/b.txt 완료)"; must init "$H"
eg fix "$H" add U2-fix1 --key ./ok.sh --repo f11c --files '"src/a b.txt", lib/b.txt' --summary 공백
exp="'f11c:src/a b.txt', f11c:lib/b.txt"
t "#11 공백 경로: fix --files·상태표 쓰기도 따옴표 규칙" '[ $RC = 0 ] && rowof U2-fix1 | grep -F "$exp" >/dev/null'
eg check "$H"
t "#11 공백 경로: 쓴 행을 다시 읽어도 같은 경로" '[ $RC = 0 ] && has "src/a b.txt"'

# #12 완료 확정은 대상 브랜치 기준
setup f12 "$OKCMD" "$(row U1 src/a.txt)"; must init "$H"; work U1; must unit "$H" U1 commit -m U1; cm=$(sget units.U1.commit)
git -C "$R" switch -q -c other "$cm"
eg unit "$H" U1 recover
t "#12 완료 확정: 대상 브랜치에 없는 커밋은 완료로 보지 않는다" '[ $RC = 0 ] && [ "$OUT" = merge ] && ! rowis U1 완료'
eg unit "$H" U1 cleanup
t "#12 완료 확정: HEAD 가 대상 브랜치가 아니면 정리하지 않는다" '[ $RC = 1 ] && [ -e "$(wt U1)" ] && brtip U1 >/dev/null && [ "$(git -C "$R" show main:src/a.txt)" = a ] && ! rowis U1 완료'
setup f12b "$OKCMD" "$(row U1 src/a.txt)"; must init "$H"; work U1; must unit "$H" U1 commit -m U1; must unit "$H" U1 merge
git -C "$R" switch -q -c other; eg unit "$H" U1 recover
t "#12 완료 확정: 머지됐어도 HEAD 가 다른 브랜치면 정리로 가지 않는다" '[ $RC = 1 ] && has "대상 브랜치" && [ -e "$(wt U1)" ]'

# #13 상태표: \| 이스케이프·12열 검증·대상 칸만 교체
setup f13 "$OKCMD" '| U1 | a\|b | src/a.txt | — | sonnet | ✘ | sonnet | src/a.txt | | 미착수 | | sentinel-commit |'
must init "$H"; eg stop "$H" blocked:U1
t "#13 상태표: 이스케이프한 | 칸 보존·상태 칸만 바뀜" '[ $RC = 0 ] && grep -qF "| U1 | a\|b | src/a.txt | — | sonnet | ✘ | sonnet | src/a.txt | | blocked | | sentinel-commit |" "$H"'
python3 -I - "$H" <<'PYT'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
open(p, 'w', encoding='utf-8').write(s.replace('| | blocked | | sentinel-commit |', '| blocked | | sentinel-commit |'))
PYT
cp "$H" "$TMP/f13.before"; eg stop "$H" blocked:U1
t "#13 상태표: 칸 수가 머리글과 다르면 쓰지 않는다" '[ $RC = 2 ] && has "칸 11개" && cmp -s "$H" "$TMP/f13.before"'

# #14 stop done·rotate 는 남은 중단 줄을 지운다
setup f14 "$OKCMD" "$TWO"; must init "$H"; must stop "$H" scope; eg stop "$H" done
t "#14 stop done: 남은 중단 줄을 지운다" '[ $RC = 0 ] && [ "$(sget stopped_reason)" = done ] && ! grep -q "^중단:" "$H"'
must stop "$H" scope; eg stop "$H" rotate
t "#14 stop rotate: 남은 중단 줄을 지운다" '[ $RC = 0 ] && [ "$(sget stopped_reason)" = rotate ] && ! grep -q "^중단:" "$H"'
must stop "$H" blocked:U2; eg stop "$H" done
t "#14 stop done: blocked 행이 남으면 거부" '[ $RC = 1 ] && has "blocked 행" && [ "$(sget stopped_reason)" = blocked:U2 ]'

# #15 기록 순서: 로그·eval.md 를 확정한 뒤 state.last_eval
setup f15 "$OKCMD" "$(row U1 src/a.txt)"; must init "$H"; mkdir -p "$P/goal/eval.md"
eg run "$H"
t "#15 기록 순서: eval.md 를 못 쓰면 state.last_eval 은 그대로" '[ $RC = 2 ] && [ "$(sget last_eval)" = null ] && [ -e "$P/goal/1.log" ]'

# ── 검토 2라운드 지적 재현(2026-10-20 codex B1~B7) ─────────
# B1·B2 잘못 전진한 머지는 어떤 ref 도 자동으로 되돌리지 않는다(3라운드: CAS 직전 체크아웃 경쟁). 기록만 남기고 사람에게
setup g1t "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
cm=$(sget units.U1.commit); base=$(sget units.U1.base_head)
git -C "$R" branch other "$base"; git -C "$R" branch third "$cm"
export EG_GITLOG="$TMP/g1t.gitlog"; rm -f "$EG_GITLOG"
wrap wrongtree unit "$H" U1 merge
t "B2 되돌림 없음: other 는 cm 에 남고 main 은 base 그대로, update-ref·read-tree 를 부르지 않는다" '[ $RC = 1 ] && has "자동으로 되돌리지 않는다" && [ "$(git -C "$R" rev-parse other)" = "$cm" ] && [ "$(git -C "$R" rev-parse main)" = "$base" ] && ! grep -q "update-ref\|read-tree" "$EG_GITLOG"'
t "B2 되돌림 없음: ff_misapplied 에 전진한 ref 를 적고 stage 는 merging" '[ "$(sget units.U1.ff_misapplied.ref)" = "[\"refs/heads/other\"]" ] && [ "$(sget units.U1.stage)" = merging ]'
t "B2 되돌림 없음: 제3 브랜치(third)의 작업 트리·인덱스는 그대로" '[ "$(git -C "$R" symbolic-ref --short HEAD)" = third ] && [ "$(cat "$R/src/a.txt")" = a1 ] && [ -z "$(git -C "$R" status --porcelain -- src)" ]'
eg unit "$H" U1 recover
t "B2 되돌림 없음: recover 는 ff_misapplied 가 있으면 사람에게 넘긴다" '[ $RC = 1 ] && has "ff_misapplied"'
unset EG_GITLOG

# ── 검토 3라운드 지적 재현(2026-10-20 codex B1~B5): 머지 예약(merging)·정체성 재확인 ─────────
# ff 는 됐는데 기록 단계가 잠금을 못 얻음 → stage merging 으로 남고, recover 가 대상 브랜치 기준으로 확정한다
setup h1 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
cm=$(sget units.U1.commit)
EG_LOCK="$P/goal/.lock" RELAY_LOCK_WAIT=1 wrap after-lock unit "$H" U1 merge
t "B2' 머지 예약: ff 뒤 잠금 실패 → exit 1·stage merging·merge_intent 보존·expected_tip 미갱신" '[ $RC = 1 ] && has "goal/.lock" && [ "$(sget units.U1.stage)" = merging ] && [ "$(sget units.U1.merge_intent.cm)" = "$cm" ] && [ "$(sget repos.h1.expected_tip)" != "$cm" ] && [ "$(git -C "$R" rev-parse main)" = "$cm" ]'
eg unit "$H" U1 cleanup
t "B2' 머지 예약: merging 인 단위는 cleanup 거부(recover 로)" '[ $RC = 2 ] && has "recover"'
eg unit "$H" U1 merge
t "B2' 머지 예약: merging 인 단위는 merge 재시도 거부(recover 로)" '[ $RC = 2 ] && has "recover"'
sleep 2; eg unit "$H" U1 recover
t "B2' 머지 예약: recover → cleanup, 행 완료·expected_tip=cm·merge_intent 제거" '[ $RC = 0 ] && [ "$(lastline)" = cleanup ] && rowis U1 완료 && [ "$(sget repos.h1.expected_tip)" = "$cm" ] && [ "$(sget units.U1.stage)" = merged ] && absent units.U1.merge_intent'
must unit "$H" U1 cleanup
t "B2' 머지 예약: 이어서 cleanup 정상" '[ "$(sget units.U1.stage)" = cleaned ]'
# 잘못 전진한 ff + 잠금 실패(ff_misapplied 조차 못 적음) → recover 가 merge_intent 로 알아보고 ff_misapplied 를 적는다
setup h2 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
cm=$(sget units.U1.commit); base=$(sget units.U1.base_head)
git -C "$R" branch other "$base"; git -C "$R" branch third "$base"
EG_LOCK="$P/goal/.lock" RELAY_LOCK_WAIT=1 wrap wrongtree-lock unit "$H" U1 merge
t "B2' 미확정 머지: 잠금 실패로 ff_misapplied 를 못 적어도 stage merging 은 남는다" '[ $RC = 1 ] && [ "$(sget units.U1.stage)" = merging ] && absent units.U1.ff_misapplied'
sleep 2; eg unit "$H" U1 recover
t "B2' 미확정 머지: recover 가 other 의 전진을 ff_misapplied 로 적고 사람에게 넘긴다" '[ $RC = 1 ] && has "미확정 머지" && [ "$(sget units.U1.ff_misapplied.ref)" = "[\"refs/heads/other\"]" ] && [ "$(git -C "$R" rev-parse main)" = "$base" ]'
# 커밋 사이에 단위의 정체(base_head)가 바뀌면 기록하지 않는다
setup h3 "$OKCMD" "$TWO"; must init "$H"; work U1
export REVIEW_EG="$EG" REVIEW_H="$H"
cat > "$R/.git/hooks/pre-commit" <<'HOOK'
#!/bin/sh
exec bash "$REVIEW_EG" state "$REVIEW_H" set units.U1.base_head 0000000000000000000000000000000000000000
HOOK
chmod +x "$R/.git/hooks/pre-commit"
eg unit "$H" U1 commit -m U1
t "B4 정체성: 커밋 중 base_head 가 바뀌면 exit 1·stage committing·commit 미기록" '[ $RC = 1 ] && has "커밋 뒤 상태가 바뀌었다" && [ "$(sget units.U1.stage)" = committing ] && [ "$(sget units.U1.commit)" = "" ]'
rm "$R/.git/hooks/pre-commit"

# ── 검토 4라운드 지적 재현(2026-10-20 codex B1~B4): 운전 잠금·예약 스냅샷·저장소 설정 정체성 ─────────
# C1 goal/.driver: git·조건 명령을 돌리는 명령은 한 계획에 하나만. 훅이 쓰는 state set 은 그 잠금 없이 된다
setup h4 "$OKCMD" "$TWO"; must init "$H"; work U1
python3 -I -c 'import fcntl, sys, time; f = open(sys.argv[1], "a"); fcntl.flock(f, fcntl.LOCK_EX); time.sleep(3)' "$P/goal/.driver" &
holder=$!; sleep 1; eg unit "$H" U1 recover
t "C1 운전 잠금: 다른 명령이 goal/.driver 를 쥐면 unit 은 기다리지 않고 거부" '[ $RC = 1 ] && has "goal/.driver"'
eg state "$H" set hook_seen true
t "C1 운전 잠금: state set 은 운전 잠금 없이 된다(훅 경로)" '[ $RC = 0 ] && [ "$(sget hook_seen)" = true ]'
wait "$holder"
# C2 잘못 전진한 ref 에 후속 커밋이 붙어 tip ≠ cm 이어도 예약 스냅샷 대비 'cm 을 새로 포함' 으로 잡는다
setup h5 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
cm=$(sget units.U1.commit); base=$(sget units.U1.base_head)
git -C "$R" branch other "$base"; git -C "$R" branch third "$base"
EG_LOCK="$P/goal/.lock" RELAY_LOCK_WAIT=1 wrap wrongtree-desc-lock unit "$H" U1 merge
t "C2 후속 커밋: 잘못 전진한 ff + 후속 커밋 + 잠금 실패 → stage merging" '[ $RC = 1 ] && [ "$(sget units.U1.stage)" = merging ] && [ "$(git -C "$R" rev-parse other)" != "$cm" ]'
sleep 2; eg unit "$H" U1 recover
t "C2 후속 커밋: recover 가 other(tip ≠ cm)를 ff_misapplied 로 적고 멈춘다" '[ $RC = 1 ] && has "미확정 머지" && [ "$(sget units.U1.ff_misapplied.ref)" = "[\"refs/heads/other\"]" ] && [ "$(git -C "$R" rev-parse main)" = "$base" ]'
# C3 ff 전부터 cm 에 있던 브랜치(backup)는 ff 거부 + 예약 해제 잠금 실패 뒤에도 잘못 전진으로 보지 않는다
setup h6 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
cm=$(sget units.U1.commit); git -C "$R" branch backup "$cm"
EG_LOCK="$P/goal/.lock" RELAY_LOCK_WAIT=1 wrap refuse-lock unit "$H" U1 merge
t "C3 미리 있던 브랜치: ff 거부 + 예약 해제 잠금 실패 → stage merging·main 그대로" '[ $RC = 1 ] && [ "$(sget units.U1.stage)" = merging ] && [ "$(git -C "$R" rev-parse main)" != "$cm" ]'
sleep 2; eg unit "$H" U1 recover
t "C3 미리 있던 브랜치: recover 는 backup 을 전진으로 보지 않고 merge 부터" '[ $RC = 0 ] && [ "$(lastline)" = merge ] && absent units.U1.ff_misapplied && [ "$(sget units.U1.stage)" = committed ]'
must unit "$H" U1 merge
t "C3 미리 있던 브랜치: 이어서 머지 정상" '[ "$(sget units.U1.stage)" = merged ] && [ "$(git -C "$R" rev-parse main)" = "$cm" ]'
# C4 ff 뒤 다른 프로세스가 저장소 설정(target_ref)을 바꾸면 기록하지 않고, recover 도 예약과 다른 설정으로 판정하지 않는다
setup h7 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
cm=$(sget units.U1.commit)
EG_EVAL="$EG" EG_H="$H" EG_SET="repos.h7.target_ref" wrap after-target unit "$H" U1 merge
t "C4 저장소 설정 변경: ff 뒤 target_ref 가 바뀌면 기록하지 않고 stage merging" '[ $RC = 1 ] && has "recover" && [ "$(sget units.U1.stage)" = merging ] && [ "$(sget repos.h7.target_ref)" = refs/heads/other ]'
eg unit "$H" U1 recover
t "C4 저장소 설정 변경: recover 는 예약과 다른 대상 브랜치면 판정하지 않고 멈춘다" '[ $RC = 1 ] && has "저장소 설정" && [ "$(sget units.U1.stage)" = merging ]'

# ── 검토 5라운드 지적 재현(2026-10-20 codex B1~B6): 잠금 수명·recover 중 설정 변경·예약의 경로·refs/heads 밖 ref·독립 전진·스냅샷 없음 ─────────
# D1 부모(eval-goal)가 git 도중 죽어도 git 자식이 goal/.driver 를 물려받아 끝날 때까지 쥔다. 끝나면 풀린다
setup h8 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
EG_DRIVER="$P/goal/.driver" EG_PROBE="$TMP/h8.probe" wrap kill-parent unit "$H" U1 merge
sleep 2   # 부모가 죽은 뒤 git 자식(가짜 git)이 0.5초 뒤에 프로브를 쓴다
t "D1 잠금 수명: 부모가 죽은 뒤에도 git 자식이 사는 동안 goal/.driver 는 잠겨 있다" '[ $RC != 0 ] && [ "$(cat "$TMP/h8.probe")" = LOCKED ]'
drv=$(python3 -I -c 'import fcntl, sys
f = open(sys.argv[1], "a")
try:
    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB); print("FREE")
except BlockingIOError:
    print("LOCKED")' "$P/goal/.driver")
t "D1 잠금 수명: git 자식까지 끝나면 goal/.driver 가 풀린다" '[ "$drv" = FREE ]'
# D2 recover 의 포함 검사 도중 다른 프로세스가 target_ref 를 바꾸면 예약을 두고 멈춘다
setup h9 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
cm=$(sget units.U1.commit)
EG_LOCK="$P/goal/.lock" RELAY_LOCK_WAIT=1 wrap after-lock unit "$H" U1 merge; sleep 2
EG_EVAL="$EG" EG_H="$H" EG_SET="repos.h9.target_ref" wrap contains-target unit "$H" U1 recover
t "D2 recover 중 설정 변경: settle 이 예약을 두고 멈춘다(stage merging·intent 보존·완료 미기록)" '[ $RC = 1 ] && has "바뀌었다" && [ "$(sget units.U1.stage)" = merging ] && [ "$(sget units.U1.merge_intent.cm)" = "$cm" ] && ! rowis U1 완료'
# D3 예약의 저장소 경로와 현재 설정이 다르면(다른 clone 으로 바꿈) 판정하지 않는다
setup h10 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
EG_LOCK="$P/goal/.lock" RELAY_LOCK_WAIT=1 wrap after-lock unit "$H" U1 merge; sleep 2
git clone -q "$R" "$TMP/h10clone" 2>/dev/null; must state "$H" set repos.h10.path "\"$TMP/h10clone\""
eg unit "$H" U1 recover
t "D3 예약의 경로: 저장소 경로가 예약과 다르면 예약을 두고 멈춘다" '[ $RC = 1 ] && has "저장소 설정" && [ "$(sget units.U1.stage)" = merging ]'
# D4 HEAD 가 refs/heads 밖 ref 를 가리킨 채 ff 되면 그 ref 도 잘못 전진으로 잡는다
setup h11 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
cm=$(sget units.U1.commit); base=$(sget units.U1.base_head); git -C "$R" update-ref refs/custom/other "$base"
EG_LOCK="$P/goal/.lock" RELAY_LOCK_WAIT=1 wrap custom-lock unit "$H" U1 merge
t "D4 refs/heads 밖: 잘못 전진 + 잠금 실패 → stage merging" '[ $RC = 1 ] && [ "$(sget units.U1.stage)" = merging ] && [ "$(git -C "$R" rev-parse refs/custom/other)" = "$cm" ]'
sleep 2; eg unit "$H" U1 recover
t "D4 refs/heads 밖: recover 가 refs/custom/other 를 ff_misapplied 로 적고 멈춘다" '[ $RC = 1 ] && [ "$(sget units.U1.ff_misapplied.ref)" = "[\"refs/custom/other\"]" ] && [ "$(git -C "$R" rev-parse main)" = "$base" ]'
# D5 ff 전부터 cm 을 품던 브랜치(backup)가 독립적으로 전진한 것은 '새로 포함' 이 아니다
setup h12 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
cm=$(sget units.U1.commit); git -C "$R" branch backup "$cm"
EG_LOCK="$P/goal/.lock" RELAY_LOCK_WAIT=1 wrap refuse-desc-lock unit "$H" U1 merge
t "D5 독립 전진: ff 거부 + backup 독립 커밋 + 잠금 실패 → stage merging" '[ $RC = 1 ] && [ "$(sget units.U1.stage)" = merging ] && [ "$(git -C "$R" rev-parse backup)" != "$cm" ]'
sleep 2; eg unit "$H" U1 recover
t "D5 독립 전진: recover 는 backup 을 잘못 전진으로 보지 않고 merge 부터" '[ $RC = 0 ] && [ "$(lastline)" = merge ] && absent units.U1.ff_misapplied'
# D6 ff 전 스냅샷이 없는 예약은 판정하지 않는다
setup h13 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
cm=$(sget units.U1.commit); base=$(sget units.U1.base_head)
EG_LOCK="$P/goal/.lock" RELAY_LOCK_WAIT=1 wrap after-lock unit "$H" U1 merge; sleep 2
must state "$H" set units.U1.merge_intent "{\"path\": \"$R\", \"target_ref\": \"refs/heads/main\", \"base\": \"$base\", \"cm\": \"$cm\"}"
eg unit "$H" U1 recover
t "D6 스냅샷 없음: before 없는 예약은 판정하지 않고 멈춘다(예약 보존)" '[ $RC = 1 ] && has "스냅샷이 없다" && [ "$(sget units.U1.stage)" = merging ]'

# ── 검토 6라운드 지적 재현(2026-10-20 codex B1·B2): 조회 실패는 빈 결과가 아니다·대상에 들어간 예약은 완료 확정까지 보존 ─────────
setup h14 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
cm=$(sget units.U1.commit); base=$(sget units.U1.base_head)
git -C "$R" branch other "$base"; git -C "$R" branch third "$base"
EG_LOCK="$P/goal/.lock" RELAY_LOCK_WAIT=1 wrap wrongtree-lock unit "$H" U1 merge; sleep 2
wrap contains-fail unit "$H" U1 recover
t "E1 조회 실패: for-each-ref --contains 가 실패하면 판정하지 않고 예약을 보존한다" '[ $RC = 1 ] && has "for-each-ref" && [ "$(sget units.U1.stage)" = merging ] && [ "$(sget units.U1.merge_intent.cm)" = "$cm" ] && absent units.U1.ff_misapplied'
eg unit "$H" U1 recover
t "E1 조회 실패: 다음 recover 가 other 를 ff_misapplied 로 잡는다" '[ $RC = 1 ] && [ "$(sget units.U1.ff_misapplied.ref)" = "[\"refs/heads/other\"]" ]'
setup h15 "$OKCMD" "$TWO"; must init "$H"; work U1; must unit "$H" U1 commit -m U1
cm=$(sget units.U1.commit)
EG_LOCK="$P/goal/.lock" RELAY_LOCK_WAIT=1 wrap after-lock unit "$H" U1 merge; sleep 2
EG_EVAL="$EG" EG_H="$H" EG_SET="repos.h15.target_ref" wrap diff-target unit "$H" U1 recover
t "E2 확정 전 설정 변경: 완료를 적지 않고 예약을 보존한다(stage merging·intent·행 미완료)" '[ $RC = 1 ] && has "바뀌었다" && [ "$(sget units.U1.stage)" = merging ] && [ "$(sget units.U1.merge_intent.cm)" = "$cm" ] && ! rowis U1 완료'
eg unit "$H" U1 recover
t "E2 확정 전 설정 변경: 다음 recover 는 예약과 다른 설정을 거부한다" '[ $RC = 1 ] && has "저장소 설정"'

# B3 잠금은 state·인계 문서 구간에만. git 훅이 이 스크립트를 불러도 교착되지 않는다
setup g3 "$OKCMD" "$TWO"; must init "$H"; work U1
export REVIEW_EG="$EG" REVIEW_H="$H"
cat > "$R/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env python3
import os, subprocess, sys
try:
    r = subprocess.run(['bash', os.environ['REVIEW_EG'], 'state', os.environ['REVIEW_H'], 'set', 'hook_seen', 'true'],
                       timeout=10, capture_output=True, text=True)
    sys.exit(r.returncode)
except subprocess.TimeoutExpired:
    print('HOOK blocked on goal/.lock')
    sys.exit(1)
HOOK
chmod +x "$R/.git/hooks/pre-commit"
eg unit "$H" U1 commit -m U1
t "B3 잠금: pre-commit 훅이 eval-goal.sh state set 을 불러도 교착 없이 커밋·기록" '[ $RC = 0 ] && [ "$(sget hook_seen)" = true ] && [ "$(sget units.U1.stage)" = committed ] && [ "$(sget units.U1.commit)" = "$(brtip U1)" ]'
python3 -I -c 'import fcntl, sys, time; f = open(sys.argv[1], "a"); fcntl.flock(f, fcntl.LOCK_EX); time.sleep(4)' "$P/goal/.lock" &
holder=$!; sleep 1; s0=$(date +%s); OUT=$(RELAY_LOCK_WAIT=1 bash "$EG" clear-stop "$H" 2>&1); RC=$?; s1=$(date +%s); wait "$holder"
t "B3 잠금: 다른 프로세스가 오래 쥐면 무한히 기다리지 않고 BLOCKED" '[ $RC = 1 ] && has "goal/.lock" && [ $((s1 - s0)) -lt 3 ]'

# B5 만료 조건은 닫힌 집합: 계획 완료·중단·최대 반복·최대 시간(· 또는 '또는'), 또는 YYYY-MM-DD HH:MM
POLICY='자동 승인: 전부(보정 단위 포함) / 만료: 2020-01-01' setup g5 "$OKCMD" "$TWO"; eg init "$H"
t "B5 만료 문법: 날짜만(2020-01-01) → init 거부" '[ $RC = 1 ] && has "만료 조건을 해석하지 못했다" && [ ! -e "$P/goal/state.json" ]'
POLICY='자동 승인: 전부 (보정 단위 포함) / 만료: 내일' mkhandoff "$OKCMD" "$TWO"; eg check "$H"
t "B5 만료 문법: 내일 → check 거부" '[ $RC = 1 ] && has "만료 조건을 해석하지 못했다"'
POLICY='자동 승인: 전부(보정 단위 포함) / 만료: ' mkhandoff "$OKCMD" "$TWO"; eg check "$H"
t "B5 만료 문법: 빈 값 → check 거부" '[ $RC = 1 ] && hasline "FAIL 커밋 정책" "만료 조건이 비었다"'
POLICY='자동 승인: 전부(보정 단위 포함) / 만료: 2026-02-30 10:00' mkhandoff "$OKCMD" "$TWO"; eg check "$H"
t "B5 만료 문법: 없는 날짜(2월 30일) → check 거부" '[ $RC = 1 ] && has "없는 날짜"'
POLICY='자동 승인: 전부(보정 단위 포함) / 만료: 2099-01-01 00:00' mkhandoff "$OKCMD" "$TWO"; eg check "$H"; a=$RC
POLICY='자동 승인: 전부(보정 단위 포함) / 만료: 계획 완료 또는 중단' mkhandoff "$OKCMD" "$TWO"; eg check "$H"
t "B5 만료 문법: 날짜+시각·사건 목록은 통과" '[ "$a" = 0 ] && [ $RC = 0 ]'
must init "$H"; work U1
perl -pi -e 's/^커밋 정책:.*/커밋 정책: 자동 승인: 전부(보정 단위 포함) \/ 만료: 내일/' "$H"; eg unit "$H" U1 commit -m U1
t "B5 만료 문법: 커밋 때 해석 못 하면 실패 폐쇄(expired)·커밋 0" '[ $RC = 1 ] && has "만료 조건을 해석하지 못했다" && [ "$(sget stopped_reason)" = expired ] && [ "$(brtip U1)" = "$(sget units.U1.base_head)" ]'
must clear-stop "$H"
perl -pi -e 's/^커밋 정책:.*/커밋 정책: 자동 승인: 전부(보정 단위 포함) \/ 만료: 2020-01-01 00:00/' "$H"; eg unit "$H" U1 commit -m U1
t "B5 만료 문법: 지난 만료 시각 → expired·커밋 0" '[ $RC = 1 ] && has "만료 시각 2020-01-01 00:00 지남" && [ "$(brtip U1)" = "$(sget units.U1.base_head)" ]'

# B6 ps 실패 경로(가짜 ps 가 실패한다)
setup g6 "$OKCMD" "$(row U1 src/a.txt)"
sh_ "$R/child.sh" 'sleep 2'; sh_ "$R/parent.sh" './child.sh & wait'
git -C "$R" add parent.sh child.sh && git -C "$R" commit -q -m child-fixture
mkhandoff '  cmd: ./parent.sh
  timeout: 1s' "$(row U1 src/a.txt)"; must init "$H"
OUT=$(PATH="$TMP/psfail:$PATH" bash "$EG" run "$H" 2>&1); RC=$?
t "B6 ps 실패: 남은 프로세스 번호를 못 얻으면 '확인 못 함'으로 멈춘다" '[ $RC = 1 ] && has "확인 못 함" && [ "$(sget stopped_reason)" = timeout-survivors ] && sget last_eval.results | grep -F "\"survivors\": null" >/dev/null'
setup g6b '  cmd: ./slow.sh
  timeout: 1s' "$(row U1 src/a.txt)"; must init "$H"
OUT=$(PATH="$TMP/psfail:$PATH" bash "$EG" run "$H" 2>&1); RC=$?
t "B6 ps 실패: 남은 프로세스가 없으면 ps 없이(신호 0 확인) 정상 실패로 본다" '[ $RC = 0 ] && [ "$(lastline)" = "DONE: incomplete(units=1,failed=1)" ]'
sleep 2   # g6 의 자식(sleep 2)이 스스로 끝나기를 기다린다(끝내지 않는다)

# B7 eval.md 원자성: 쓰는 도중 실패해도 기존 이력은 바이트 그대로. 성공해도 제자리 수정이 아니다
# 파일 크기 한도 200블록(204,800바이트, bash 는 1024바이트 단위)에서 eval.md 를 한도 50바이트 아래(204,750바이트)까지 채운다.
# 새 줄을 더하면 한도를 넘는다: 제자리 append 라면 한도까지 일부만 기록돼 기존 이력이 바뀐다. 스크립트 본문(약 78KB)은 한도 안이다.
setup g7 "$OKCMD" "$(row U1 src/a.txt)"; must init "$H"
python3 -I -c 'import sys; open(sys.argv[1], "w", encoding="utf-8").write("- 이전 이력\n" + "x" * (204750 - 17) + "\n")' "$P/goal/eval.md"
cp "$P/goal/eval.md" "$TMP/g7.before"
OUT=$( (ulimit -f 200; bash "$EG" run "$H") 2>&1 ); RC=$?
t "B7 eval.md 원자성: 쓰는 도중 실패(파일 크기 한도) → 기존 이력 바이트 그대로·임시 파일 없음" '[ $RC != 0 ] && has "File too large" && [ "$(wc -c < "$TMP/g7.before" | tr -d " ")" = 204750 ] && cmp -s "$P/goal/eval.md" "$TMP/g7.before" && ! ls -A "$P/goal" | grep -q "^\.tmp-"'
t "B7 기록 순서: 그때 state.last_eval 은 바뀌지 않는다" '[ "$(sget last_eval)" = null ]'
ln "$P/goal/eval.md" "$TMP/g7.link"; cp "$P/goal/eval.md" "$TMP/g7.before2"; eg run "$H"
t "B7 eval.md 원자성: 성공 때도 새 파일로 바꾼다(옛 파일을 잡은 쪽은 바이트 그대로)" '[ $RC = 0 ] && cmp -s "$TMP/g7.link" "$TMP/g7.before2" && grep -q "^- 이전 이력$" "$P/goal/eval.md" && [ "$(grep -c "^- 반복 " "$P/goal/eval.md")" = 1 ]'

echo "통과 $PASS · 실패 $FAIL"
[ "$FAIL" -eq 0 ]
