선택: 나
근거:
- docs/plans/orchestration-plan.md:484 사용자가 U7까지 멈추지 않고 진행하도록 지정했다.
- docs/plans/orchestration-plan.md:354 작업 폴더 안의 읽기, 편집, 생성, 삭제는 사전 승인 없이 허용된다.
- docs/plans/orchestration-plan.md:406 U7 확인 항목 2번의 UI 결함 수정과 재검수를 진행하려면 화면이 필요하다.
- docs/plans/orchestration-plan.md:478 모니터 앱은 별도 세션이 진행하고 있어 같은 파일을 수정하면 충돌 위험이 있다.
- docs/plans/monitor-plan.md:134 모니터 앱 코드는 monitor 디렉터리의 Swift 패키지로 분리되어 있어 독립된 작은 화면을 추가하는 편이 안전하다.
위험: 모니터 앱과 화면 역할이 일부 겹치고 시범이 끝난 뒤 정리할 부수 파일이 남는다.
되돌리는 방법: 시범을 위해 새로 만든 정적 화면 파일과 관련 커밋을 git 명령으로 삭제한다.
