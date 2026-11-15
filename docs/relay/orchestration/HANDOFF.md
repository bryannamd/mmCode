# HANDOFF — orchestration

## 재개 지시

```text
계획: docs/plans/orchestration-plan.md. 규칙: mmcode:relay 스킬 (resume 모드).
세션 연번: orch (#0)
커밋 정책: 단위마다 로컬 커밋(2026-11-16 사용자 승인. 묻지 않는다. 푸시는 하지 않는다)
목표: mmCode의 실행 능력을 유지하면서 진행 상황을 한눈에 보이게 하고, 사용자 개입과 세션 교체 뒤 재개를 연결한다
다음 작업: U2 — 얇은 한 바퀴(이벤트 파일, 단계 전환 명령). 첫 응답에 status.sh 상태표.
```

## 상태표

| 단위 | 내용 | 파일 | 선행 | 모델 | 병렬 | 검수 | pathspec | 가중치 | 상태 | 종료 시각 | 커밋 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| U1 | 환경: rotate.sh와 pair가 hc에서 동작 | relay/scripts/rotate.sh, pair | — | opus | ✘ | sonnet | mmCode:plugins | | 완료 | 2026-11-15 08:46 | mmCode 4f62d5c |
| U2 | 얇은 한 바퀴: 이벤트 파일, 단계 전환 명령, 검사 결과 기록, 상태표 생성 | relay/scripts/phase.sh, tests/relay/phase.test.sh | U1 | sonnet | ✘ | sonnet | mmCode:plugins,tests | | 진행 | | |
| U3 | 증거: 완료 기준 형식, 실패 먼저, 변형 점검, 위험 등급. 스킬 문서 낱말 정리 | plan, relay 문서와 템플릿 | U2 | sonnet | ✘ | sonnet | mmCode:plugins,tests | | 미착수 | | |
| U4 | 사람: 결정과 지시 이벤트, 단위 후 정지, 즉시 중단, 계속 | relay/scripts/phase.sh, 훅 | U3 | sonnet | ✘ | sonnet | mmCode:plugins,tests | | 미착수 | | |
| U5 | 화면: 모니터 조회와 지시 보내기(별도 세션) | docs/plans/monitor-plan.md | U2 | | ✘ | | | | 미착수 | | |
| U6 | 단위 자동이 같은 명령을 쓴다. 기록에서 재개. 계획 자동 | relay/scripts/eval-goal.sh, rules.md | U4 | opus | ✘ | opus | mmCode:plugins,tests | | 미착수 | | |
| U7 | 실제 기능 3개 안팎으로 시범 | 대상 프로젝트(미정) | U6 | | ✘ | | | | 미착수 | | |

상태 값: `미착수` / `진행` / `완료` / `보류` / `blocked`. U1은 phase.sh가 생기기 전에 끝나 손으로 적었다. U2부터는 phase.sh가 상태·종료 시각·커밋 칸을 쓴다.

## 진행률
기준선: 0% (2026-11-15, 계획 확정 시점)

## 이월
- 전체: U7까지 멈추지 않고 진행한다(2026-11-16 사용자). 실행 중 사용자의 결정이 필요한 판단은 codex와 agy 교차 검토로 정한다(계획 7.1절). 푸시와 치명적인 명령은 하지 않는다 (U7)
- U7: 시범 대상 프로젝트를 사용자가 정해야 한다 (U7)

## 확인된 실패
- 없음

## 종료 시 제거
- 없음
