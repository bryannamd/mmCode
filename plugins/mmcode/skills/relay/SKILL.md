---
name: relay
description: 큰 작업을 "단위 표"로 쪼개 브리프→Worker→독립 검수→커밋→인계 한 줄 갱신→새 세션 교체(herdr) 로 이어 달리는 실행 워크플로. auto 모드(완료 조건까지 무인 반복)를 지원한다. 계획 파일과 인계 문서(HANDOFF) 템플릿, 첫 응답 상태표 스크립트, herdr 세션 교체 스크립트, 임시 인덱스 원자 커밋 스크립트 포함. "/relay", "relay auto", "핸드오프 루프", "단위 계획으로 진행", "handoff loop", "세션 교체해", "인계 재개", "단위 끝 커밋하고 다음 세션" 요청에 사용. 일반적인 "계획 세워줘"·단일 작업에는 쓰지 않는다.
---

# relay — 단위 실행 + 세션 인계 반복

CLAUDE.md 의 Advisor/Worker·세션 핸드오프·Git 안전·다중 세션 규칙을 **그대로 전제**한다(여기서 다시 쓰지 않음).
이 스킬은 그 위에 얹는 **절차·문서 형식·스크립트**다. 상세 규칙은 `references/rules.md`, 종료 체크리스트는 `references/closing.md`.

`S`는 이 스킬 폴더다(Claude는 호출 시 "Base directory for this skill"로, Codex는 스킬 목록의 파일 경로로 안다). 프로젝트 산출물은 `docs/relay/<plan>/` 아래(관례가 있으면 그 관례 우선).

## 모드 선택

| 요청 | 모드 |
|---|---|
| 작업 목록을 단위 계획으로 만들어 달라 | `init` |
| 새 세션이 인계 문서로 시작 | `resume` |
| 다음 단위 진행 | `unit` |
| 세션 바꿔서 이어 가라 | `rotate` |
| 완료 조건 명령이 참이 될 때까지 무인 반복 | `auto` |
| 계획 끝·중단 | `close` |

## init — 계획·인계 문서 생성

1. 작업 범위를 읽고 **단위 표**를 만든다: 단위 하나 = 브리프 1 → Worker 1 → 검수 1 → 커밋 1. 열은 `templates/PLAN.md` 고정(단위·내용·파일·선행·모델·병렬·검수·pathspec·상태·종료 시각·커밋). 단위가 6개 넘으면 묶는다.
2. `templates/HANDOFF.md` 를 복제해 재개 블록·세션 연번(`<prefix> (#0)`)·진행률 기준선·상태표를 채운다. **상태표는 인계 문서 한 곳에만** 둔다(계획 파일은 규칙·근거만).
3. 커밋 정책 줄은 기본 `커밋 정책: 확인 후`. 사용자가 이 계획에 한해 자동 승인을 준 경우에만 `자동 승인: <단위 범위> / 만료: <조건>` 을 **같은 줄에** 적는다. 스킬 기본값을 바꾸지 않는다.
4. 임시 권한(additionalDirectories·Bash allow 등)을 넣었으면 인계 문서 "종료 시 제거" 절에 즉시 기록한다.

## resume — 새 세션 첫 응답

1. 인계 문서 **재개 블록·상태표·이월만** 읽는다. 이전 로그·증거 REPORT 재독 금지(필요한 설계·소스만 좁게).
2. 첫 응답에 상태표를 표로 낸다: `bash "$S/scripts/status.sh" <HANDOFF.md>` 출력(현재 단위·완료/남은 단위·진행률·최근 단위 소요·남은 시간 범위).
3. 프롬프트에 이전 pane_id 가 있으면 `herdr agent list` 로 그 pane 이 `idle` 인지 확인 후 `herdr pane close <id>`. `working` 이면 닫지 않고 단위 끝에 재확인. 한 번에 하나만.
4. 첫 작업 착수. 세션 연번은 인계 문서 줄을 읽고 +1 해 갱신.

재개 블록에 `모드: auto`가 있으면 `goal/state.json`도 읽고 3·4단계 대신 `## auto`의 전이표를 적용한다. 이때 4단계 연번은 `rotated_serial`이 있으면 읽기만 하고 없으면 +1 한다. 다른 모드는 위 그대로다.

## unit — 단위 표준 절차

1. **브리프**: `templates/BRIEF.md` 복제 → `docs/relay/<plan>/<unit>/BRIEF.md`. 파일 경로·정본·완료 기준·검증 명령·"건드리지 말 파일". 코드 통째 복붙 금지. **8KB 이하** — 정본 내용은 옮겨 적지 않고 파일·절 번호로 인용한다.
2. **Worker** 위임(모델 등급은 plan 3절 표를 따른다). Worker 가 테스트를 실행하고 로그를 단위 디렉터리에 저장. 병렬은 서로 다른 파일의 순수 모듈만.
3. **Advisor 확인**: `git diff HEAD -- <path>` + 로그 읽기. 재실행하지 않는다. 결함이면 재위임(완료 기준당 최대 2회).
4. **독립 검수**: 새 컨텍스트(`/code-review` 또는 검수 에이전트)에 diff + 신규 테스트만. 결과를 `INDEPENDENT_REVIEW.md`(판정·발견 표·실행 명령만, 서술 금지). FAIL 이면 수정 → 델타 재검수.
5. **커밋**: 인계 문서 커밋 정책 줄을 읽는다. `확인 후` 면 "커밋할까요?" 후 진행. 다중 세션 흔적이 있으면 `scripts/commit-unit.sh` 2단계(prepare → stat 읽고 → finish). 저장소가 둘 이상이면 저장소별로.
6. **인계 갱신**: 상태표 그 행만(상태·종료 시각·커밋 해시) + 이월 항목. 이월은 **다음 단위를 막는 것만, 항목당 한 줄 120자 이내**, 해소되면 삭제. 막지 않는 minor 는 `docs/relay/<plan>/DEBT.md`(`templates/DEBT.md`) 에 적는다. 서술은 단위 디렉터리 `REPORT.md`(표 3개 + 400단어 이내) 로. 인계 문서가 100줄 또는 12KB 를 넘기면 오래된 절을 `docs/relay/<plan>/archive/` 로 옮긴다.
7. **교체 판단**: 직전 단위의 Worker 또는 검수가 opus 였거나 이 세션에서 2단위를 마쳤으면 `rotate`. sonnet/haiku 단위 뒤에는 교체 없이 다음 단위로 간다(교체 1회 ≈ 10분).

## rotate — 세션 교체 (herdr 전용)

```bash
bash "$S/scripts/rotate.sh" <prefix> <HANDOFF.md> [PLAN.md]
```
Codex 세션에서 실행하면 `ROTATE_KIND=codex` 를 붙여 다음 세션도 codex 로 띄운다(기본 claude).
HERDR_ENV=1 필요. 스크립트가 인계 문서 스냅샷(`archive/HANDOFF.#N.md`, docs 가 gitignore 라 이력이 없기 때문) → pane split → `agent start <prefix>-N` → rename `<prefix> (#N)` → 재개 프롬프트(인계 경로·이전 pane_id 포함) 전송 → 전송 성공 후 세션 연번 갱신까지 한다. 현재 세션은 "교체 완료, 이 세션 종료" 한 줄만 남기고 멈춘다(자기 pane 은 닫지 않는다 — 마지막 보고가 사라짐).
herdr 밖이면 스크립트가 거부한다 → 인계 문서만 갱신하고 사용자에게 새 세션 시작을 안내한다. 다른 오케스트레이터는 쓰지 않는다.

## auto — 완료 조건까지 무인 반복

사용자가 승인한 범위 안에서, 명령으로 판정되는 완료 조건이 참이 될 때까지 `unit`을 사람 입력 없이 반복한다. 끝은 완료 보고이고 `close`는 사용자가 돌아와서 한다.
쓰는 경우: 완료를 명령(exit 0)으로 판정할 수 있고, 단위가 2개 이상이고, 사람이 지켜보지 않고, 이 계획에 한해 커밋 자동 승인을 받았을 때. 명령으로 판정하지 못하는 일과 권위 관문 영역(R15)에는 쓰지 않는다.
권한은 지금 있는 것만 쓰고 승인 창이 뜨면 거기서 멈춘다. 푸시·PR·원격 머지·사용자 대신 승인·권한 변경 요구·강제 삭제(`worktree remove --force`·`branch -D`)는 하지 않는다.
규칙은 `references/rules.md` R13(조건)·R14(경계·워크트리·복구)·R15(판단·중단)에 있다. 기계 부분은 `bash "$S/scripts/eval-goal.sh" <하위 명령> <HANDOFF.md> [인자...]`가 맡는다. 하위 명령은 `check`·`init`·`run`·`treekey`·`clean`·`unit`·`fix`·`redeleg`·`stop`·`clear-stop`·`state`·`status-json`이고 인자 없이 부르면 사용법이 나온다. 종료 코드는 0 성공, 1 거부·blocked(마지막 줄 `BLOCKED: <이유>`), 2 사용 오류, 3 judge-fail이다.

```text
init(auto) → 반복 엔진 등록(1회) → [반복] → 완료 보고(close 대기)
[반복] = 경계 점검(앞) → unit 1~6단계(워크트리 브랜치 커밋 → ff 머지) → 이전 pane 정리 → 조건 평가 → 완료면 통합 검수 → 경계 점검(뒤) → 교체 판단(unit 7단계)
```

- 분기 1: 반복은 언제나 `stage ≠ cleaned`인 단위를 4단계의 복구 분기(git 실제 상태 대조)로 먼저 처리한다. 행 상태와는 무관하다.
- 분기 2: 그 뒤 4단계에서 멈추면(blocked·limit·expired) 5단계만 거쳐 9단계로 간다.
- 분기 3: 미완료 단위가 0개인 반복은 새 단위를 시작하지 않고 6단계부터 한다.

1. **init(auto)**: 기존 init에 더해 재개 블록에 `모드: auto`·`완료 조건:`·`경계:`를 적는다. `커밋 정책:`이 `자동 승인: <보정 단위 포함 단위 전부> / 만료: <조건>` 형식이 아니면 시작하지 않는다. 단위 하나는 저장소 하나다(pathspec 열 `<slug>:<경로>`). `eval-goal.sh check`로 검사하고, 조건·검증·Worker 호출 명령과 만들고 지울 워크트리·브랜치를 사용자에게 보여 한 번 확인받은 뒤 `eval-goal.sh init`이 `goal/state.json`을 만든다. 이 확인이 유일한 질문 지점이다.
2. **반복 엔진**: Claude는 `/loop`(프롬프트 `relay auto 다음 반복 <HANDOFF.md 경로>`)를 init 직후와 resume 첫 턴에 한 번만 등록하고, 완료·중단·교체 성공 때 `stop`한다. Codex는 `/loop`가 없어 한 턴 안에서 반복 본문을 순서대로 돈다. 본문은 Claude와 같고 `resume`을 포함하지 않는다.
3. **경계 점검(앞)**: 최대 시간·최대 반복을 본다(수치는 `eval-goal.sh status-json`, 기준은 R14). 걸리면 9단계로 간다.
4. **unit 1~6단계(워크트리 브랜치 판)**: 단위 시작 검사 → 워크트리 브랜치 `relay/<plan>/<unit>` 생성 → Worker(pane은 단위마다 새로) → Advisor 확인·독립 검수 → 워크트리에서 커밋 → 공유 브랜치에 `--ff-only` 머지 → 정리. 공유 트리에는 이 세션만 쓴다. 명령·순서·복구 분기는 R14, 기계 부분은 `eval-goal.sh unit <HANDOFF.md> <단위>`의 `start`·`checkwt`·`commit -m <메시지>`·`merge`·`cleanup`·`recover`·`discard`다. 독립 검수 통과는 세션이 `eval-goal.sh state set units.<단위>.stage reviewed`로 적는다.
5. **이전 pane 정리**: 교체로 넘어온 세션이면 unit 6단계 뒤에 이전 세션 pane이 `idle`일 때 닫는다(resume 3단계와 같은 규칙).
6. **조건 평가**: `eval-goal.sh run`이 `cmd:`를 순서대로 돌린다(공유 트리, 반복마다 1회). 완료 = 미완료 단위 0개 + 모든 `cmd:` exit 0. exit 126·127은 나머지를 돌리지 않고 `judge-fail`로 중단한다(스크립트가 중단까지 기록하고 exit 3). 같은 트리면 재사용한다(R13).
7. **보정 단위**: 단위가 전부 `완료`인데 `cmd:`가 실패하면 원인을 확인한다. 수정 대상이 모두 계획 pathspec 안일 때만 `eval-goal.sh fix add`로 `U<마지막>-fix<회차>` 단위를 상태표 끝에 더한다. 보정은 계획당 2회차까지이고 그 뒤 또 실패하면 `fix-cap`, 범위 밖이면 `scope`로 중단한다(`fix add`가 검사하고 기록한다). 이어서 9·11단계를 거쳐 다음 반복으로 간다(R14).
8. **통합 검수**: 조건 평가가 완료 판정일 때 단위 간 정합·중복·빠진 연결만 본다(`goal/INTEGRATION_REVIEW.md`). 지적 0이면 `/loop`를 `stop`하고 완료 보고로 간다. 지적이 있으면 7단계로 보정하고, 조건 재통과와 델타 재검수 지적 0이 되어야 완료다.
9. **경계 점검(뒤)·중단**: 최대 시간·최대 반복·보정 상한·`blocked`를 본다. 조건 평가와 통합 검수를 통과해 남은 단위가 없으면 완료 보고가 먼저다. 사유는 `eval-goal.sh stop <사유>`로 `stopped_reason` 하나에 적는다. `blocked:<단위>`면 그 행도 `blocked`가 되고, 실제 중단이면 재개 블록에 `중단: <사유>` 한 줄이 생긴다. 그리고 `/loop`를 `stop`한다. 값 목록은 R15.
10. **완료 보고**: plan 완료 화면을 쓰고 남은 일에 `close 대기`를 적는다(`stopped_reason`=`done`). 단위별 커밋은 자동 승인 범위 안에서 이미 끝나 있다. `close`는 사용자가 돌아와 항목마다 확인하며 한다. 남은 `relay/<plan>/*` 브랜치·워크트리·임시 허용이 있으면 종료 완료로 적지 않는다(`references/closing.md`).
11. **교체 판단·교체**: 판단은 R7 그대로다. herdr 안에서는 같은 턴에서 `eval-goal.sh stop rotate`로 `stopped_reason`을 적고 `rotate.sh`를 실행한다. 종료 코드 0 = 성공(`/loop` stop, "교체 완료" 한 줄). 1 = 생성 전 실패(한 번 더 시도하고 또 실패하면 `rotate-failed`로 중단. 0·1·4 밖의 코드는 재시도 없이 같다). 4 = 새 세션은 떴으나 전송·대기 실패(rotate.sh가 `rotate-uncertain`을 기록하고 새 pane에 `esc`를 보낸다. 이 세션도 `/loop` stop). 연번은 rotate.sh가 전송 전에 +1 하고 `rotated_serial`을 남긴다. 새 세션 첫 턴에서 Claude는 전이표대로 등록만 하고 턴을 끝내고(단위 작업은 첫 깨우기에서 시작), Codex(`ROTATE_KIND=codex`)는 바로 반복 본문에 들어간다. herdr 밖에서는 인계 문서를 갱신하고 `stopped_reason`=`rotate`로 멈춘 뒤 새 세션 시작을 안내한다.
12. **resume 전이표**: 새 세션·중단 뒤·비정상 종료 뒤 공통이다. 사람이 resume를 부른 것이 곧 재개 승인이다. 연번은 실제로 등록·진입하는 행(1·2·4행)에서만 갱신한다. `rotated_serial`이 있으면 읽기만 하고 표시를 지우며, 없으면 +1 한다. 안내만 하는 3·5행은 연번과 표시를 건드리지 않는다.

| 행 | `stopped_reason` | 재개 블록 `중단:` 줄 또는 상태표 `blocked` 행 | resume가 하는 일 |
|---|---|---|---|
| 1 | `rotate` | 없음 | 비우고 등록(Claude)·진입(Codex) |
| 2 | `""`(비정상 종료: 세션 사망·429·`/loop` 만료·Codex 턴 종료. 사용자가 3행을 거쳐 정리했으면 `stopped_reason`이 `""`여도 4행으로 간다: 3행이 `resume_after_cleanup: true`를 state.json에 남긴다) | 없음 | `units[*].worker`를 본다. herdr agent가 `working`이면 R14의 Worker 중단 절차(`esc` 뒤 `idle` 확인), agy는 기록한 PID·시작 시각이 일치하는 프로세스가 살아 있으면 끝날 때까지 기다린다(최대 `Worker 제한`). 멈추지 않으면 등록하지 않고 그 단위를 `blocked`, `stopped_reason`을 `worker-alive`로 적고 `중단:` 줄을 쓴다(사람이 Worker를 끝낸다). 멈췄으면 그 Worker pane을 닫고(auto 4단계가 새로 띄운다) 상태표와 `git status --short`를 보이고 등록·진입 |
| 3 | 값과 무관 | 하나라도 있음 | 등록하지 않는다. 사유·상태표·단위별 `stage`와 워크트리(더티 여부)·살아 있는 세션(`herdr agent list`)을 보이고 state.json에 `resume_after_cleanup: true`를 적는다. 사용자가 재개 블록(`커밋 정책:` 만료 조건·경계)을 고치고, 되돌릴 `blocked` 행을 `미착수`로 바꾸고(그 단위의 더티 워크트리는 보존·폐기 중 택해 정리), `중단:` 줄을 지우면 다음 resume이 4행이다 |
| 4 | 값과 무관(3행을 거쳐 정리된 뒤) | 둘 다 없음(사용자가 정리함) | 같은 턴에서 이 순서로: ① 2행과 같은 Worker 생존 확인(멈추지 않으면 2행처럼 `worker-alive`로 되돌아간다) ② `미착수`로 되돌린 단위의 Worker pane 닫기, `.relay-logs/` 옮기기, 워크트리 제거(실패하면 여기서 멈추고 `blocked`·`중단:` 줄을 되살린다. 사용자가 직접 정리한다), 브랜치 이름 보존(`.discarded-<n>`), `units[<unit>]`과 `redelegations` 키 초기화 ③ `HEAD ≠ expected_tip`인 저장소가 있으면 외부 커밋을 받아들일지 사용자에게 확인하고, 받아들이면 `expected_tip`을 현재 HEAD로 갱신(거절하면 멈춘다) ④ 경계 블록 재검증 → state.json 상한값 갱신(`started_at`·`iterations` 유지), `stopped_reason` 비움 ⑤ status.sh ⑥ 등록·진입 |
| 5 | `done` | 없음 | 등록하지 않는다. 완료 상태표만 보인다(close 대기) |

재개 뒤 단위 작업은 auto 4단계 규칙으로 돌아간다. 되돌리지 않은 단위는 복구 분기가 이어 할 단계를 정한다. 공유 트리 pathspec은 깨끗해야 한다는 규칙은 재개 때도 같다. `stopped_reason`을 비울 때는 `eval-goal.sh clear-stop`을 쓴다(`중단:` 줄도 지운다).

## close — 종료

`references/closing.md` 항목을 사용자에게 **하나씩 확인**하고 처리한다(임시 권한 제거·add-dir 제거·scratch 정리·`relay/<plan>/*` 브랜치와 워크트리 정리·인계 문서 종료 표시·자동 승인 소진). 사용자 답 없이 제거·유지를 결정하지 않는다.

## 금지

- 인계 문서에 서술 누적, 상태를 두 파일에 중복.
- 검증 결과 없이 "완료" 보고. 실행하지 않은 검증을 pass 로 기록.
- 세션당 3단위 이상, 자기 pane close, 이전 pane 이 working 인데 close.
- 스킬 안에서 커밋 자동 승인·권한 완화를 기본값으로 두는 것.
