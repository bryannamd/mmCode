# board-pilot 실행 계획 (2026-11-16)

## 목적·범위
- mmCode 실행 체계(계획 `docs/plans/orchestration-plan.md` U7)를 실제 화면 기능 3개로 시범한다.
- 만드는 것: `board/`의 정적 화면. 이벤트 파일(`.mmcode/events.jsonl`)을 읽어 단위별 단계, 결정 대기열, 열린 지시를 보여 준다.
- 화면은 읽기만 한다. 답과 지시는 화면이 보여 주는 `phase.sh` 명령을 복사해 터미널에서 실행한다.
- 범위 밖: `monitor/`(다른 세션의 앱), 플러그인 스킬 파일, 훅 등록.

## 정본·설계 문서
- 기록 형식과 명령: `plugins/mmcode/skills/relay/SKILL.md` unit 6단계, `plugins/mmcode/skills/relay/scripts/phase.sh` 머리 주석.
- 시범 확인 항목 6개: `docs/plans/orchestration-plan.md` 9절 "U7 확인 항목".
- 화면 기준: 이 문서의 "화면 기준" 절.

## 고정 규칙
relay 스킬 `references/rules.md` R1~R12 적용. 이 계획만의 예외:
- 일꾼은 Claude 하위 에이전트(sonnet) 하나다. 독립 검수와 UI 검수는 깨끗한 맥락의 하위 에이전트가 한다.
- 단위마다 로컬 커밋은 묻지 않는다(2026-11-16 사용자 승인). 푸시는 하지 않는다.
- 시범 중의 `direct stop-after`·`direct resume`은 계획자가 사용자 역할로 보낸다(확인 항목 3·4를 보기 위한 입력이다).

## 검증 명령·환경
- 단위 시험: `node --test 'board/*.test.mjs'`
- 화면 확인: 저장소 최상위에서 `python3 -m http.server 8765` 뒤 `http://localhost:8765/board/` (브라우저 확인은 ego-browser 스킬)
- 불변 검사: `bash scripts/check.sh`

## 화면 기준
- 열었을 때 1초 안에 "내가 나서야 하나"에 답한다. 열린 결정과 열린 정지·중단 지시가 가장 위에 가장 크게 보인다. 없으면 조용하다.
- 폭 360px과 1200px에서 가로 스크롤 없이 읽힌다.
- 상태를 색만으로 구분하지 않는다(글자 표시를 함께 쓴다). 글자 대비 4.5:1 이상. 밝은 색 구성과 어두운 색 구성을 모두 지원한다.
- 누를 수 있는 것은 40×40px 이상이고 키보드 초점이 보인다.
- 이벤트 파일을 못 읽으면 이유와 할 일(서버로 열기 또는 파일 고르기)을 보여 준다.
- 외부 서버에서 받는 글꼴·스크립트·이미지를 쓰지 않는다.

## 단위 표 (상태는 HANDOFF.md 상태표가 정본. 여기엔 정의만)

| 단위 | 내용 | 파일 | 선행 | 모델 | 병렬 | 검수 | pathspec |
|---|---|---|---|---|---|---|---|
| B1 | 단위 보드: 계획별로 단위를 단계 열(대기·구현·검증·검수·완료)에 놓는다. 멈춘 단위에 멈춤 이유를 붙인다. 이벤트 파일 읽기(서버 경로, 파일 고르기) | board/index.html, board/board.js, board/board.test.mjs | — | sonnet | ✘ | opus | mmCode:board |
| B2 | 결정 대기열: 열린 결정을 맨 위에 보여 주고 답하는 명령을 복사하게 한다. 답한 결정은 접어 둔다 | board/index.html, board/board.js, board/board.test.mjs | B1 | sonnet | ✘ | opus | mmCode:board |
| B3 | 열린 지시: 정지·중단 지시가 열려 있으면 위쪽 띠로 알리고 푸는 명령을 보여 준다. 메시지·순서 변경 지시는 접수와 적용을 따로 표시한다 | board/index.html, board/board.js, board/board.test.mjs | B2 | sonnet | ✘ | opus | mmCode:board |

## 완료 기준 (단위마다)
- B1: 이벤트 줄 목록을 주면 / `reduce(events)`가 / 계획별 단위의 단계와 멈춤 이유를 돌려준다. 단계 이벤트가 없는 계획은 나오지 않는다. 깨진 줄은 건너뛰고 건너뛴 수를 돌려준다 / 잡을 결함: 다른 계획의 같은 이름 단위가 섞임, 되돌아간 단위(review→build)가 옛 단계에 남음, `unit.resume` 뒤에도 멈춤 표시가 남음 / 검사: `node --test 'board/*.test.mjs'`, 화면은 실제 확인(360px·1200px)
- B2: 결정 이벤트를 주면 / `reduce(events)`가 / 열린 결정과 답한 결정을 나눠 돌려준다. 답 명령 문자열은 따옴표가 든 답도 셸에서 안전하다 / 잡을 결함: 답한 결정이 열린 목록에 남음, 다른 계획의 결정 ID와 섞임, 선택지의 따옴표로 명령이 깨짐 / 검사: `node --test 'board/*.test.mjs'`, 화면은 실제 확인
- B3: 지시 이벤트를 주면 / `reduce(events)`가 / 열린 지시(적용 여부 포함)를 돌려준다. 정지·중단은 `applied` 뒤에도 `resume`이 닫기 전까지 열려 있다. `resume` 지시는 목록에 나오지 않는다 / 잡을 결함: 적용된 정지 지시가 사라짐, 닫힌 지시가 남음, 거부된 메시지가 남음 / 검사: `node --test 'board/*.test.mjs'`, 화면은 실제 확인
- 위험 등급: B1 일반, B2 일반, B3 일반. 셋 다 화면이 있다.

## 종료 시 제거할 임시 설정
- 화면 확인용 `python3 -m http.server`(시작한 세션이 자기 것만 끝낸다).
