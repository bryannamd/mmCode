#!/usr/bin/env bash
# relay commit: 공유 인덱스를 건드리지 않는 임시 인덱스 원자 커밋. 2단계.
#   prepare <repo> <msg-file> <path>...   임시 인덱스 read-tree HEAD → add → write-tree → diff --stat 출력 후 멈춤
#   finish  <repo>                         사람이 stat 을 읽고 승인한 뒤: commit-tree -p OLD → update-ref <new> <old> → 공유 인덱스 reset -q -- <paths>
# 절차 근거: 공유 인덱스를 쓰는 다중 세션에서 남의 스테이징이 섞이지 않게 임시 인덱스로 커밋한다(references/rules.md R11).
set -euo pipefail
mode=${1:?prepare|finish}; repo=${2:?repo}; shift 2
state="$repo/.git/relay-commit.state"
case "$mode" in
prepare)
  msg=${1:?msg-file}; shift; [ $# -ge 1 ] || { echo "path 필요" >&2; exit 2; }
  [ -f "$msg" ] || { echo "메시지 파일 없음: $msg" >&2; exit 2; }
  cd "$repo"; idx=$(mktemp); old=$(git rev-parse HEAD); branch=$(git symbolic-ref --short HEAD)
  GIT_INDEX_FILE=$idx git read-tree "$old"
  GIT_INDEX_FILE=$idx git add -A -- "$@"
  tree=$(GIT_INDEX_FILE=$idx git write-tree); rm -f "$idx"
  printf 'old=%q\ntree=%q\nbranch=%q\nmsg=%q\n' "$old" "$tree" "$branch" "$msg" > "$state"
  printf '%s\n' "$@" > "$state.paths"
  echo "== $repo ($branch @ ${old:0:8}) 커밋 후보 트리 ${tree:0:8}"; git diff --stat "$old" "$tree"
  echo "== 위 stat 이 내 파일뿐인지 읽고 승인되면: commit-unit.sh finish $repo";;
finish)
  [ -f "$state" ] || { echo "prepare 상태 없음" >&2; exit 2; }
  cd "$repo"; . "$state"
  [ "$(git rev-parse HEAD)" = "$old" ] || { echo "HEAD 가 이동했다(${old:0:8} → $(git rev-parse --short HEAD)). prepare 부터 다시." >&2; exit 1; }
  new=$(git commit-tree "$tree" -p "$old" -F "$msg")
  git update-ref "refs/heads/$branch" "$new" "$old"
  while IFS= read -r p; do [ -n "$p" ] && git reset -q -- "$p" 2>/dev/null || true; done < "$state.paths"   # 공유 인덱스를 새 HEAD 에 맞춤(워킹트리 무접촉)
  rm -f "$state" "$state.paths"
  git show --stat --format='%h %an %s' HEAD | head -40
  echo "== 잔여 staged(남의 것이어야 함):"; git diff --cached --name-only;;
*) echo "usage: commit-unit.sh prepare <repo> <msg-file> <path>... | finish <repo>" >&2; exit 2;;
esac
