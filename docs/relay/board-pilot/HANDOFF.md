# HANDOFF — board-pilot

## 재개 지시

```text
계획: docs/relay/board-pilot/PLAN.md. 규칙: mmcode:relay 스킬 (resume 모드). 스킬 문서는 이 저장소의 plugins/mmcode/skills/relay/SKILL.md 를 읽는다(설치된 사본이 옛 판일 수 있다).
세션 연번: board (#0)
커밋 정책: 단위마다 로컬 커밋(2026-11-16 사용자 승인. 묻지 않는다. 푸시는 하지 않는다)
목표: 이벤트 파일을 읽어 단위별 단계, 결정 대기열, 열린 지시를 보여 주는 정적 화면을 board/ 에 만든다(실행 체계 시범)
다음 작업: B1 — 단위 보드. 첫 응답에 phase.sh show 와 status.sh 상태표.
```

## 상태표

| 단위 | 내용 | 파일 | 선행 | 모델 | 병렬 | 검수 | pathspec | 가중치 | 상태 | 종료 시각 | 커밋 | 등급 | 화면 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| B1 | 단위 보드와 이벤트 파일 읽기 | board/index.html, board/board.js, board/board.test.mjs | — | sonnet | ✘ | opus | mmCode:board | 40 | 진행 | | | 일반 | ✔ |
| B2 | 결정 대기열 | board/index.html, board/board.js, board/board.test.mjs | B1 | sonnet | ✘ | opus | mmCode:board | 30 | 미착수 | | | 일반 | ✔ |
| B3 | 열린 지시 | board/index.html, board/board.js, board/board.test.mjs | B2 | sonnet | ✘ | opus | mmCode:board | 30 | 미착수 | | | 일반 | ✔ |

상태 값: `미착수` / `진행` / `완료` / `보류` / `blocked`. `phase.sh` 로 옮긴 단위의 상태·종료 시각·커밋 칸은 스크립트가 쓴다. 그 칸을 손으로 고치지 않는다.

## 진행률
기준선: 0% (2026-11-16, 시범 시작 전)

## 이월
- 없음

## 확인된 실패

## 종료 시 제거
- 화면 확인용 로컬 서버(띄운 세션이 끝낸다)
