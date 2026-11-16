선택: 나
근거:
- docs/plans/orchestration-plan.md:350 시범 변경은 계획의 격리 작업 폴더 안에서 git으로 되돌릴 수 있어야 한다.
- docs/plans/orchestration-plan.md:355 공유 폴더의 미커밋 변경을 포함한 작업 폴더 밖 쓰기는 사용자 결정을 기다려야 한다.
- docs/plans/orchestration-plan.md:364 모니터는 별도 세션이 진행하므로 시범 파일을 분리하는 나가 작업 충돌을 줄인다.
- docs/plans/orchestration-plan.md:445 시범은 화면이 있는 실제 기능 3개를 요구하므로 실제 이벤트 기록을 읽는 세 기능으로 한정한다.
- docs/plans/monitor-plan.md:154 기존 모니터도 이벤트 기록을 읽어 단계와 멈춤을 표시하므로 시범 화면과 역할이 겹친다.
- docs/plans/monitor-plan.md:161 기존 모니터의 지시와 결정 답 보내기는 상위 계획 U4에 의존하는 미구현 기능이다.
위험: 시범 화면이 별도 모니터로 굳어져 같은 표시 규칙을 두 곳에서 유지할 위험이 있다.
되돌리는 방법: 시범 전용 파일 변경만 되돌리고 이벤트 기록과 기존 모니터는 보존한다.
