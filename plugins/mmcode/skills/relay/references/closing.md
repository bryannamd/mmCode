# 계획 종료 체크리스트 (close 모드, 항목마다 사용자 확인)

1. `.claude/settings.json` `permissions.additionalDirectories` 에 이 계획 전용으로 넣은 경로 — 제거할지.
2. `.claude/settings.local.json` `permissions.allow` 에 계획 기간 한정으로 넣은 항목(예 `"Bash"`) — 제거(사용자가 직접 편집; 분류기가 자체 수정 차단할 수 있음).
3. scratch/stage/applied-layer 임시 자산(`/private/tmp/<plan>-*`, 스크래치 worktree) — 정리할지.
4. auto 계획이었다면 이 계획의 `relay/<plan>/*` 브랜치(`.discarded-<n>` 포함)와 `docs/relay/<plan>/<unit>/wt/` 워크트리 — 남은 것을 목록으로 보이고 정리할지. 머지된 것만 `git worktree remove`·`git branch -d`로 지운다(강제 삭제 없음). `.discarded-<n>`은 미머지 커밋을 담고 있으니 지울지 사용자가 정한다. 이 실행이 만든 `docs/relay/<plan>/` 문서를 커밋할지도 이때 정한다.
5. 인계 문서 재개 블록에 "계획 종료 <날짜>" 표시, 자동 승인 줄이 있었으면 "소진" 으로 갱신.
6. 관련 메모리(`/memory`)·lessons 갱신: 반복 실수·비자명한 해결책만.
7. 마지막 세션 pane 은 사용자가 닫는다(자기 pane close 금지).
