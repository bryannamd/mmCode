#!/usr/bin/env bash
# relay rotate: herdr 새 pane 에 다음 세션을 띄우고 재개 프롬프트를 보낸다.
# 사용: rotate.sh <prefix> <HANDOFF.md> [PLAN.md]   (HERDR_ENV=1 필요)
# 새 세션의 effort 는 환경변수로 정한다: ROTATE_EFFORT=low|medium|high|xhigh|max (없으면 사용자 기본값)
# 새 세션의 에이전트 종류: ROTATE_KIND=claude|codex (없으면 claude). effort 옵션은 claude 에만 넘긴다.
set -euo pipefail
prefix=${1:?prefix}; handoff=${2:?HANDOFF.md}; plan=${3:-}
[ "${HERDR_ENV:-}" = 1 ] || { echo "herdr 밖이다. 인계 문서만 갱신하고 사용자에게 새 세션 시작을 안내하라." >&2; exit 3; }
[ -f "$handoff" ] || { echo "인계 문서 없음: $handoff" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq 필요" >&2; exit 2; }
effort=${ROTATE_EFFORT:-}
case "$effort" in ''|low|medium|high|xhigh|max) ;; *) echo "ROTATE_EFFORT 값이 잘못됐다: $effort" >&2; exit 2 ;; esac
# 빈 배열을 set -u 에서 펼치면 bash 3.2 가 실패하므로 아래에서 ${agent_args[@]+...} 로 쓴다.
kind=${ROTATE_KIND:-claude}
case "$kind" in claude|codex) ;; *) echo "ROTATE_KIND 값이 잘못됐다: $kind" >&2; exit 2 ;; esac
agent_args=(); [ -z "$effort" ] || [ "$kind" != claude ] || agent_args=(-- --effort "$effort")
cur=$(grep -E -m1 "세션 연번:\s*$prefix \(#[0-9]+\)" "$handoff" | sed -E 's/.*\(#([0-9]+)\).*/\1/' || true)
[ -n "$cur" ] || { echo "인계 문서에 '세션 연번: $prefix (#N)' 줄이 없다" >&2; exit 2; }
next=$((cur + 1))
name="${prefix}-${next}"
# 인계 문서 스냅샷 — docs 가 gitignore 라 이력이 없다. 한 번 잘못 쓰면 상태표가 사라진다.
snap_dir="$(dirname "$handoff")/archive"; mkdir -p "$snap_dir"
cp "$handoff" "$snap_dir/HANDOFF.#${cur}.md"
pane=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus | jq -r '.result.pane.pane_id')
[ -n "$pane" ] && [ "$pane" != null ] || { echo "pane split 실패" >&2; exit 1; }
# 새 pane 의 shell 이 뜨기 전에 agent start 하면 agent_pane_busy 로 실패한다(2026-09-16 직접 확인) — 재시도로 기다린다.
for _ in 1 2 3 4 5 6; do
  herdr agent start "$name" --kind "$kind" --pane "$pane" --timeout 60000 ${agent_args[@]+"${agent_args[@]}"} >/dev/null 2>&1 && break
  sleep 2
done
# 이름 충돌 폴백: agent 이름은 소문자·숫자·-_ 만 허용(tab id 는 대문자를 포함하므로 소문자화)
herdr agent list | jq -e --arg n "$name" '.result.agents[] | select(.name == $n)' >/dev/null \
  || herdr agent start "${name}-$(echo "${HERDR_TAB_ID##*:}" | tr 'A-Z' 'a-z')" --kind "$kind" --pane "$pane" --timeout 60000 ${agent_args[@]+"${agent_args[@]}"} >/dev/null
herdr pane rename "$pane" "$prefix (#$next)" >/dev/null || true
prompt="$handoff 의 재개 지시부터 진행(mmcode:relay 스킬 resume 모드)."
[ -n "$plan" ] && prompt="$prompt 계획: $plan."
prompt="$prompt 이전 세션 pane ${HERDR_PANE_ID:-?} 는 idle 확인 후 herdr pane close 로 닫을 것. 첫 응답에 status.sh 상태표를 표시할 것."
if ! herdr agent prompt "$name" "$prompt" --wait --timeout 120000 >/dev/null; then
  echo "prompt 전송 실패 또는 활동 감지 대기 초과 — $name 상태를 herdr agent list 로 확인. 세션 연번은 갱신하지 않았다(#$cur 유지)." >&2; exit 1
fi
# 전송 성공 후에만 세션 연번 갱신 (인계 문서 한 줄)
perl -pi -e "s/(세션 연번:[[:space:]]*\Q$prefix\E \(#)$cur(\))/\${1}$next\${2}/" "$handoff"
echo "교체 완료: pane=$pane agent=$name (#$next) effort=${effort:-기본값}. 이 세션은 여기서 종료한다(자기 pane 은 닫지 않는다)."
