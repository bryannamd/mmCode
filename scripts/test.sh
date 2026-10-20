#!/usr/bin/env bash
# mmCode 시험 묶음. tests/ 아래 *.test.sh 를 전부 돌리고 통과·실패 수를 한 줄로 낸다.
# 사용: scripts/test.sh   (저장소 어느 위치에서 불러도 된다)
# 종료 코드: 0 = 전부 통과 · 1 = 실패 있음
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
pass=0 fail=0 failed=''
while IFS= read -r f; do
  # 시험 파일마다 따로 돌린다. 하나가 실패해도 나머지는 돈다.
  if bash "$f"; then pass=$((pass + 1)); else fail=$((fail + 1)); failed="$failed ${f#"$root"/}"; fi
done < <([ -d "$root/tests" ] && find "$root/tests" -type f -name '*.test.sh' | sort)
echo "시험 파일 $((pass + fail))개 · 통과 $pass · 실패 $fail${failed:+ ·$failed}"
[ "$fail" -eq 0 ]
