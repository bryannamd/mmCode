선택: 나
근거:
- docs/plans/orchestration-plan.md:145 검수 상한 초과는 결정 요청으로 올리도록 정한다.
- docs/plans/orchestration-plan.md:330 계획자와 다른 종류 검토자 2종의 의견 중 둘 이상이 같으면 그 결정으로 진행한다.
- docs/plans/orchestration-plan.md:95 완료에는 요구된 검수 증거의 통과가 필요하므로 재검수 미실행 기록만으로 완료할 수 없다.
- docs/relay/orchestration/HANDOFF.md:22 U6은 독립 검수 증거가 필요한 일반 등급이다.
- plugins/mmcode/skills/relay/scripts/phase.sh:325 완료 증거 판정은 마지막 독립 검수 결과가 통과가 아니면 해당 증거를 부족으로 본다.
- plugins/mmcode/skills/relay/scripts/eval-goal.sh:1274 수정한 시작 판정은 단계 전환 명령의 거부를 예외 없이 따르는 한 줄이다.
- tests/relay/eval-goal.test.sh:969 새 시험은 손으로 진행이라 적은 행의 시작 거부와 워크트리·브랜치 미생성을 검사한다.
위험: 회차 상한 예외를 반복하면 검수 범위와 일정이 계속 늘어날 수 있다.
되돌리는 방법: 추가 검수 예외 결정을 철회하고 이미 반영한 수정은 보존한 채 U6을 결정 대기로 남긴다.
