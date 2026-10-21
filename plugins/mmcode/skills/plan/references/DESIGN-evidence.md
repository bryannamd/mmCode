# 시험 증거·위임 계약 설계안 — 시험을 믿을 근거를 남기고, 위임 입출력을 파일로

버전: v7 (2026-10-21. v1 → 1R 20건 → v2 → 2R 14건 → v3 → 3R 11건 + 자체 2건 → v4 → 4R 7건 → v5 → 5R 7건 → v6 → 6R 4건 → v7. 7R 판정: codex PASS · agy PASS · 새 지적 0. 검토자: codex GPT-6-Astra high · agy Gemini 4 Argon high, 라운드마다 깨끗한 패널). 출처: 엉클 밥의 "읽지 않고 관문으로 신뢰" 방식(2026-07 2차 보도), superpowers v7.0.0(writing-good-tests·subagent-driven-development·using-git-worktrees). 둘 다 절차가 아니라 장치만 가져온다.

## 한 줄 요약

mmCode 는 이미 증거 우선이다(auto 명령 판정·check-impact 실행 증명·증거 기반 보고). 빠진 것은 "시험 자체를 믿을 근거"와 "위임 입출력의 형식"이다. 이 설계는 ① 시험 증거 3종(잡을 결함·실패 먼저·변형 점검) ② 회신 계약(Worker 회신 상태 4종) ③ 검수 묶음·검수 브리프(검수 입력을 파일로) ④ 시작 평가(auto 반복 0)를 더한다. 새 스킬은 없다. plan 이 정의하고 relay 가 절차·템플릿·스크립트를 맡는다. 변형 점검 1건은 "그 시험이 그 결함을 잡는다"는 증거이지 시험 전체가 옳다는 보장이 아니다(11절).

## 0. 전제·제약 (전역 규칙·기존 규칙 발췌 — 이 설계는 이것을 바꾸지 않는다)

- 커밋·푸시는 사용자 확인 뒤에만. 파괴적 git(`checkout --`·`restore`·`stash`·`reset --hard`·`clean`·`worktree remove --force`·`rm -rf`) 금지. 변형 점검의 되돌리기와 scratch 정리도 이 안에서 한다.
- 다중 세션 공유 워킹트리 규칙: 남의 변경이 있는 파일은 읽기만. 격리가 필요하면 scratch 워크트리(`git worktree add --detach`). 변형 점검도 이 규칙을 따른다.
- 시험 도구가 없는 프로젝트에 도구를 새로 들이지 않는다(plan 4절). 뮤테이션·커버리지 도구도 같다.
- 최소 수정 방침(plan 2절)과 "가드인가 수정인가"(go principles)는 그대로다. superpowers 의 defense-in-depth 는 가져오지 않는다.
- R2 검증 1회 예산: 검수자의 실행은 "변형 점검으로 대상 시험 1회 + 복원 뒤 신규 시험 1회"다. Worker 의 통과 로그를 다시 만들지 않는다.
- R12 문서 분량 상한을 지킨다. 새 템플릿은 4KB 이하다.
- 작업 계획·완료 화면·작업 이해 화면에 줄이나 라벨을 더하지 않는다(plan 1·9절, explain). 완료 화면은 `검사 결과` 값에만 더한다.
- pair 의 agy 는 셸을 못 쓴다(pair 3절). 시험 실행은 이 세션이 한다.
- 한 계획은 한 운전자: `init`·`run`·`unit` 등 git 을 돌리는 하위 명령은 `goal/.driver` 를 명령 내내 쥔다(R14 ⑧). 조건 명령(`run_one`)의 자식은 그 잠금을 물려받지 않는다(`run` 과 같다. 바꾸지 않는다).

## 1. 지키는 것 / 안 하는 것

지키는 것
- 정의는 plan, 절차·템플릿·스크립트는 relay, 기계 부분은 스크립트. 기존 분담 그대로.
- 사람이 보는 질문 지점은 늘리지 않는다. auto 의 유일한 질문 지점(init 확인 1회)은 그대로다.
- 이름은 기존 용어를 잇는다(2절). 영문 토큰은 기계가 읽는 값에만 쓴다.
- 기존 인계 문서·브리프·state.json 과 호환된다. 새 줄이 없으면 Advisor 가 채우고, 새 키가 없으면 스크립트는 "미상"으로 두고 경고 없이 진행한다.
- 경로마다 적용 범위를 표로 정한다(3.5절). 표에 없는 경로는 없다.
- 트리를 바꾸는 단계(변형 점검·시작 평가)는 바꾸기 전에 영속 표시를 남기고, 되돌린 뒤에 지운다. 다음 세션은 표시만 보고 "되돌리지 못한 상태"를 알아본다.

안 하는 것
- 커버리지 %·CRAP 상한을 플러그인 기본 관문으로 두지 않는다. 프로젝트에 도구가 이미 있을 때만 auto `cmd:` 와 검사 결과에 넣는다.
- 전면 TDD 철칙(코드 먼저 쓰면 삭제)은 넣지 않는다. 실패 먼저는 "증거 1줄"이다.
- 세션 시작 훅·스킬 발동 시험·description 정리는 이 설계 밖이다(별도 건).
- 새 스킬·새 경로(go)·새 라벨·새 화면 줄을 만들지 않는다.

## 2. 용어

| 이름 | 뜻 | 왜 이 이름 |
|---|---|---|
| 시험 증거 3종 | 잡을 결함 · 실패 먼저 · 변형 점검. 시험을 믿을 근거 셋 | 계획(Advisor) → 구현(Worker) → 검수(검수자) 한 단계에 하나씩. 4음절 명사 셋 |
| 잡을 결함 | 시험 하나가 잡아야 할 잘못된 구현 하나. 시험을 쓰기 전에 브리프에 적는 한 줄 | superpowers "name the break". "잡는 변경"은 plan 의 정상 수정 "변경"과 겹쳐 뺐다. 결함 = 의도하지 않은 동작 |
| 실패 먼저 | 새 시험을 구현 전에 돌려 남긴 실패 출력 1줄 | plan 4절 기존 용어 "실패 먼저 확인"을 잇는다. 적용 범위만 버그 수정에서 기능까지 넓힌다 |
| 변형 점검 | 검수자가 잡을 결함 하나를 실제로 적용해 그 시험이 그 단언에서 실패하는지 1회 확인 | make-verifier `prove.md` 가 이미 "변형"을 mutation 의 뜻으로 쓴다. "뮤테이션"은 쓰지 않는다 |
| 허수 시험 | 거울 단언(기대값을 대상 코드로 계산)·변경 감지기(상수·문구·내부 구조 그대로 확인)·모의 객체 동작 확인 시험 | 금지 항목 셋을 한 단어로 |
| 회신 계약 | Worker 가 채팅으로 돌려주는 15줄 이내의 고정 형식 | "보고서"는 파일(REPORT.md), "회신"은 채팅. 둘을 가른다 |
| 회신 상태 4종 | `DONE` · `DONE_WITH_CONCERNS` · `BLOCKED` · `NEEDS_CONTEXT` | 회신 첫 줄의 값. 상태표의 단위 상태·`stopped_reason` 과 혼동하지 않게 "회신"을 붙인다. 대문자 토큰은 eval-goal.sh 출력 `DONE: complete`·`BLOCKED: <이유>` 관례 |
| 검수 묶음 | 변경 전체(diff + 신규 파일 = 적재물)와 그 해시·기준·경로를 한 파일에 담은 검수 입력. `review-<회차>[-<slug>].diff` | superpowers review-package. 파일 번호 = 검수 회차 |
| 적재물 | 묶음의 `## diff` 절과 `## 신규 파일` 절을 이어 붙인 것. `git apply` 할 수 있는 패치이고 해시·델타·검증의 공통 대상 | 추적 변경과 미추적 신규 파일을 하나로 다루기 위한 이름 |
| 검수 브리프 | Advisor 가 검수자에게 주는 지시. `templates/REVIEW_BRIEF.md` → `docs/relay/<plan>/<unit>/REVIEW_BRIEF.md` | Worker 브리프 `BRIEF.md` 와 짝. 결과물 `INDEPENDENT_REVIEW.md`(검수서)는 그대로 |
| 진행 표시 | 트리를 바꾸기 전에 남기는 영속 기록. 변형 점검: auto 는 state `units.<u>.mutation`(`unit … review-begin` 이 쓴다), 일반 relay 는 검수서 `변형 점검 진행:` 줄 + 인계 문서 이월 한 줄. 시작 평가: state `initial_eval.status`·`initial_eval.running` | 되돌리지 못한 채 끊겨도 다음 세션이 읽는 자리(recover·resume 첫 응답의 이월)에 남긴다. 읽는 자리가 없는 경로(단독 pair·plan 일꾼)는 제자리 변형을 하지 않는다 |
| 시작 평가 | auto `init` 이 확인 뒤 `cmd:` 를 반복 0으로 한 번 돌린 결과. 다시 돌리는 명령은 `eval-goal.sh start-eval`(시도 번호가 오른다) | "기준선"은 인계 문서 진행률 `기준선: <N>%` 과 겹친다. 반복 번호 0 과 짝 |
| `recheck` | `recover` 의 새 출력어. "Worker 산출물은 그대로, 독립 검수부터". 기존 `review`(검수 통과, 커밋부터)와 다르다 | 변형 점검 도중 끊긴 단위의 재개 지점 |
| 검출/시도 | 완료 화면 `검사 결과` 값 `변형 1/1` 의 뜻. 앞이 실패를 낸 변형 수, 뒤가 시도 수 | 기존 `시험 9/9`(통과/전체)와 같은 "성공/전체" 순서 |

## 3. 시험 증거 3종

### 3.1 잡을 결함 (계획 단계 · Advisor)

- 정의: 시험 하나가 잡아야 할 잘못된 구현 하나를 한 줄로. 예: `재시도 횟수를 2로 바꾸면 test_retry_three 가 실패한다`, `빈 이메일을 통과시키면 test_reject_empty_email 이 실패한다`.
- 누가·언제: 계획자가 브리프의 완료 기준을 쓸 때. 시험을 쓰기 전이다. Worker 가 아니라 요구사항 쪽에서 나온다.
- 범위: 요구사항 시험(plan 4절 "요구사항마다 1개 이상")마다 1줄. 경계값·회귀 시험에는 선택.
- 적을 수 없으면: 그 시험은 관찰할 수 있는 동작을 잡고 있지 않다. 시험을 다시 잡는다. 의도한 결정(상수 값·문구)만 깨뜨릴 수 있는 시험은 변경 감지기다.
- 어디에: `BRIEF.md` Goal 의 완료 기준 아래 `잡을 결함:` 줄. relay 밖 위임(plan 일꾼·pair)은 브리프 본문의 완료 기준 뒤. 계획자 직접 처리(★1~2)는 화면에 쓰지 않고 시험 이름이나 설명에 담는다. 시험 없음 경로는 `잡을 결함: 해당 없음(<이유>)`.

### 3.2 실패 먼저 (구현 단계 · Worker)

- 정의: 새 시험을 구현 전에 한 번 돌려 실패 출력 1줄(시험 이름 + 실패 메시지)을 남긴다. 버그 수정은 재현 실패가 그 증거다(go `bug-fix.md` 그대로).
- 확인할 것: 실패이지 오류가 아니다(기능이 없어서 단언에서 실패. 문법·import·수집 오류면 고치고 다시). 바로 통과하면 기존 동작을 시험한 것이다.
- 어디에: `REPORT.md` 검증 결과 표 아래 `실패 먼저:` 줄(요구사항 시험마다 1줄, 로그 파일명). REPORT 가 없는 경로는 회신 `시험:` 줄에 실패 출력 1줄을 넣는다. 회신 `시험:` 줄의 값은 `실패 먼저 확인|해당 없음|미실행(agy) · Advisor 실행 대기`.
- Worker 가 셸을 못 쓸 때(pair agy): 브리프를 둘로 나눈다. ① 시험만 쓰게 한다 → 이 세션이 돌려 실패를 확인하고 출력 1줄을 적는다 → ② `-c` 로 이어 구현을 맡긴다. 이 추가 호출은 재위임 횟수로 세지 않는다(역량 실패가 아니다). 회신의 `시험:` 줄은 `미실행(agy) · Advisor 실행 대기` 이고, Advisor 가 돌린 뒤 결과를 REPORT(relay 안: `<wt>/.relay-logs/REPORT.md` 에 Advisor 가 채운다)나 회신 요약에 옮긴다.
- 예외: 시험 없음 경로(문구·스타일·도구 없음)는 `해당 없음`. 전면 TDD(코드 먼저 쓰면 삭제)는 요구하지 않는다.

### 3.3 변형 점검 (검수 단계 · 검수자)

- 정의: 브리프의 잡을 결함 중 Advisor 가 고른 하나를 실제 코드에 적용하고 대상 시험을 돌린다. 그 시험이 의도한 단언에서 실패해야 한다.
- 판정은 세 갈래다. ① 검출: 대상 시험이 단언에서 실패했다. ② 미검출(판정 FAIL): 변형이 적용됐는데 시험이 통과했다 — 시험이 허수다. ③ 무효: 문법·import·수집 오류, 환경 오류, 변형이 관찰 동작을 바꾸지 않음, 변형이 적용되지 않음. 무효는 검출로 세지 않고 검수서에 사유를 적는다. 고칠 수 있으면(잘못 고른 변형) 한 번 다시 고른다.
- 전제: 변형 전 같은 시험의 정상 통과 증거는 Worker 의 로그(REPORT 검증 결과)다. 검수자가 다시 만들지 않는다. 로그가 없으면 `무효(통과 증거 없음)` 이고 Worker 쪽 지적이다.
- 횟수: 단위당 1회. 저장소가 둘인 일반 단위는 저장소마다 1회. 완료 화면 `변형 1/1` 은 검출/시도다.
- 진행 표시(변형 전에 반드시). auto: `eval-goal.sh unit <HANDOFF.md> <단위> review-begin <묶음> [<파일>]` — 검수 예약. 잠금 한 번에 `units.<단위>.mutation = {package, file?, sha256?, at}` 과 `stage: reviewing` 을 적는다. `<파일>` 을 주면 `<wt>` 안 그 파일의 sha256 을 재고, 변형 점검이 해당 없음(시험 없음·삭제만 있는 단위·재검수에서 변형 생략)이면 파일 없이 예약만 한다. 가드: `mutation_unrestored` 가 있으면 즉시 Blocked(`ff_misapplied` 와 같다). 이미 `mutation` 이 있으면(recheck 뒤 재검수) 먼저 아래 ①~③ 을 지금 값으로 확인하고 통과했을 때만 새 값으로 바꾼다. 어긋나면 `mutation_unrestored` 를 적고 block. 일반 relay: 검수서(`INDEPENDENT_REVIEW.md`) 판정 줄 아래 `변형 점검 진행: <파일> <sha256> <시각>` 한 줄과 인계 문서 이월에 `<단위>: 변형 점검 진행 <파일> <sha256> — 복원 확인 전 재위임·검수 통과·커밋 금지` 한 줄을 먼저 쓴다(resume 첫 응답이 이월을 읽는다). 단독 pair·plan 일꾼: 읽는 자리가 없으므로 제자리 변형을 하지 않는다(scratch 워크트리 또는 해당 없음).
- 진행 표시 해제. auto: 검수서를 받은 뒤 `eval-goal.sh unit … review-end --pass|--fail`. 잠금 밖에서 ① `checkwt` 와 같은 재스캔·재stage(`wt_ready`·`scan_or_block`·`stage_files` 의 검사 부분을 "실패 사유를 돌려주는" 공통 함수로 묶어 쓴다. 안에서 바로 block 하지 않는다) ② `pack-review.sh --verify <묶음>` ③ `mutation.file` 이 있으면 `<wt>` 의 그 파일 sha256 == `mutation.sha256`. 그 뒤 잠금 한 번(`c.update`)으로 ④ 최신 state 에서 단위 정체(`same_unit`)·`mutation` 이 검사에 쓴 값과 같은지·`mutation_unrestored` 없음·`stopped_reason` 빈 값을 다시 확인하고 `mutation` 삭제 + `stage` 를 `reviewed`(--pass) 또는 `started`(--fail) 로 적는다. 진입 때도 `mutation_unrestored` 가 있으면 즉시 Blocked(review-begin·recover 와 같다. 파일만 되돌리고 표시를 지우지 않은 채 부르면 거부된다). ①의 트리 검사가 실패하면 `stage_files`·② 를 하지 않고 `verify: null` 로 적는다. ①~③ 중 하나라도 어긋나면 먼저 `mutation_unrestored = {file?, sha256?, verify, why}` 를 잠금 한 번으로 적고(`mutation` 은 남긴다) 그 다음 `block(c, U, …)`(행 `blocked`·`stopped_reason blocked:<단위>`·`중단:` 줄. 기존 `u_merge` 와 같은 기록). `.driver` 는 명령 내내 쥔다(unit 은 이미 DRIVING). `--fail` 뒤 커밋을 막는 것은 Advisor 절차다(`u_commit` 은 `started` 를 받는다). 일반 relay: 검수서 줄을 결과 줄로 바꾸고 이월 줄을 지운다.
- 절차(검수자, 제자리: 단일 세션 공유 트리·auto `<wt>`):
  1. 진행 표시를 남긴다. 대상 파일의 해시를 적는다(`shasum -a 256 <파일>`).
  2. 잡을 결함을 편집 도구로 적용한다(문자열 하나 바꾸기 수준).
  3. 대상 시험만 돌린다. 실패 출력 1줄을 검수서에 적는다.
  4. 같은 편집을 거꾸로 적용한다. 해시가 1 과 같은지 확인한다.
  5. 신규 시험을 1회 돌린다(R2 의 "신규 테스트 실행"이자 복원 증거). 4 또는 5 가 어긋나면 `복원 실패` 로 적고 거기서 멈춘다. 더 덮어쓰지 않는다. 진행 표시는 지우지 않는다.
  6. 진행 표시를 해제한다(auto 는 Advisor 가 검수서를 받은 뒤 `review-end`. 일반은 검수서 줄 교체 + 이월 줄 삭제).
  7. `git checkout --`·`git restore`·`git stash`·`git reset --hard` 는 쓰지 않는다.
- 절차(scratch 워크트리: 다중 세션 공유 트리 · 단독 pair · plan 일꾼): 묶음 머리의 `base:` 커밋이 있는지 본다(`git cat-file -e <base>`) → `git worktree add --detach <scratch>/wt <base>` → `pack-review.sh --patch <묶음> | git -C <wt> apply -p1` (적재물은 `--binary`·고정 prefix 라 신규·바이너리 파일도 들어간다) → 5(신규 시험 1회. 통과가 "적용 정상"의 증거) → 1~3(변형. 진행 표시는 검수서·이월에. 단독 경로는 scratch 폴더의 `review-<n>.progress` 파일) → 변형을 거꾸로 적용 → 4(해시 확인) → `pack-review.sh --patch <묶음> | git -C <wt> apply -R -p1` → `git worktree remove <wt>` → 6(진행 표시 해제). 제거가 거부되면(시험이 남긴 미무시 파일) 강제하지 않고 경로를 검수서 `이월` 에 적는다(R14 ⑨ 기준). 시험이 scratch 에서 돌지 않으면(설치·설정 필요) `해당 없음(다중 세션)`. 대상 파일에 남의 미커밋 hunk 가 섞여 있으면(R11 ①) 묶음은 Advisor 가 내 hunk 만 뽑은 패치로 만들고(`--patch-file`, 4.2) 변형 점검은 `해당 없음(남의 hunk 혼재)`. 검수서의 실행 줄은 실제로 한 단계만 적는다.
- 복원 실패·되돌리지 못한 중단은 일반 검수 FAIL 과 다르다. auto 는 재위임 없이 `eval-goal.sh stop blocked:<단위>`(사람이 워크트리를 본다). 일반 relay 는 그 단위를 멈추고 사용자에게 파일 목록을 알린다. 복원이 확인되기 전에는 검수 통과·커밋·재위임으로 가지 않는다.
- auto 추가 검사(Advisor, 묶음이 있는 단위만): 검수서를 받은 뒤 `review-end --pass|--fail`(위). 시험 실행이 남긴 미무시 파일도 ①의 재스캔에서 걸린다(R14 ⑦ (a) 와 같은 기준). 묶음이 없는 무변경 단위는 `review-begin`·`review-end` 를 쓰지 않는다.
- auto 복구(R14 ⑩ 에 더한다): `recover` 는 `mutation_unrestored` 가 있으면 즉시 Blocked(사람이 정리한다). `stage == reviewing` 이면 다른 판정보다 먼저 `review-end` 의 ①~③ 과 같은 검사를 한다(같은 함수. `mutation.file` 이 없으면 ③ 생략). 모두 맞으면 `mutation` 은 그대로 두고 `recheck` 를 답한다 — Worker 산출물은 그대로, 검수 브리프부터 다시(끝나면 `review-end` 가 지운다). 하나라도 어긋나면 `mutation_unrestored` 를 적고 `block()`(`ff_misapplied` 와 같은 "기록하고 멈춤"). 사람 정리: 파일을 되돌린 뒤 `eval-goal.sh state <HANDOFF.md> del units.<단위>.mutation_unrestored` — `stage` 는 `reviewing` 그대로이므로 다음 recover 가 검사 뒤 `recheck` 를 답한다. 단위를 버리려면 기존대로 행을 `미착수` 로 돌려 `discard`. `stage: reviewing` 인 단위를 `u_commit` 이 거부하는 것은 지금 그대로다. 변형 도중 세션이 죽어도 변형된 `<wt>` 위에서 Worker 가 다시 돌지 않는다.
- 일반 relay 복구(SKILL.md resume 3단계에 더한다): 첫 응답의 이월에 `변형 점검 진행` 줄이 있으면 그 단위는 복원 미확인이다. 재위임·검수 통과·커밋을 하지 않고 파일·해시를 사용자에게 보인다. 사용자가 되돌렸다고 하면 Advisor 가 sha256 을 비교해 이월 줄을 지운다.
- 누가: 독립 검수자. 검수를 `/code-review` 로 대신하면 Advisor 가 한다. 검수자가 agy(셸 없음)면 Advisor 가 돌리고 결과를 검수서에 옮긴다. 검수 에이전트 종류는 R8 그대로(cavecrew 가 있으면 그것).
- 기록: `INDEPENDENT_REVIEW.md` `변형 점검:` 줄(바꾼 것 → 시험 이름 → 검출|미검출|무효(<사유>)|복원 실패|해당 없음(<이유>)). 완료 화면 `검사 결과` 값에 `변형 1/1` 을 더한다. 시험 없음·해당 없음이면 표기를 생략한다.

### 3.4 허수 시험 금지 (plan 4절에 한 줄로)

거울 단언·변경 감지기·모의 객체 동작 확인을 만들지 않는다. 기대값은 요구사항에서 손으로 정한 값(리터럴·손으로 검산한 고정값)이다. 기존 문장 "기대값은 구현이 아니라 요구사항에서 정한다. 구현을 그대로 베낀 시험은 만들지 않는다"를 이 이름으로 묶는다.

### 3.5 경로별 적용표

| 경로 | 잡을 결함 | 실패 먼저 | 변형 점검 | 회신 계약 | 묶음·검수 브리프 | 시작 평가 |
|---|---|---|---|---|---|---|
| relay 단위(일반, 단일 세션) | BRIEF | Worker · REPORT | 검수자 · 제자리(진행 표시는 검수서 + 이월) | O · REPORT 경로 | O · 작업 트리 모드 · 단위 폴더 | — |
| relay 단위(일반, 다중 세션) | BRIEF | Worker · REPORT | 검수자 · scratch 워크트리(`base:` 커밋), 안 되면 해당 없음. 남의 hunk 혼재면 해당 없음 | O | O · 남의 hunk 혼재면 `--patch-file` | — |
| relay 단위(auto) | BRIEF | Worker · `<wt>/.relay-logs/REPORT.md` | 검수자 · `<wt>` 안 · `review-begin` → 변형 → `review-end` | O · 재위임 전 `redeleg incr` | O · `--cached` · REPORT 는 `.relay-logs` 경로 | O |
| pair codex(relay 안) | 위 relay 행을 그대로 상속한다(단일·다중·auto 중 해당 행) | | | | | |
| pair agy(relay 안) | BRIEF | 2단계 브리프 · Advisor 실행 · 결과를 Advisor 가 REPORT 에 채움 | 해당 relay 행 그대로(검수자) | O · `시험: 미실행(agy)` | 해당 relay 행 그대로 | 해당 relay 행 그대로 |
| pair codex(단독) | 브리프 본문 | codex 실행 · 회신 `시험:` 줄에 실패 출력 1줄 | scratch 워크트리에서만(제자리 금지). 검수 패스가 있으면 검수자, 없으면 Advisor · 진행 표시는 scratch 폴더 `review-<n>.progress` | O · `REPORT: 해당 없음` + 변경 파일 목록을 회신에 | 묶음은 scratch 폴더 · 검수 브리프는 검수 패스가 있을 때 · REPORT 대체 입력(4.3) | — |
| pair agy(단독) | 브리프 본문 | 2단계 브리프 · Advisor 실행 · 회신 요약에 1줄 | pair codex(단독)과 같다 | O · `시험: 미실행(agy)` | pair codex(단독)과 같다 | — |
| plan 일꾼(★3+, relay 밖) | 지시문 | Worker · 회신 `시험:` 줄에 1줄 | scratch 워크트리에서만. plan 5·6절 검수자, 없으면 Advisor | O · `REPORT: 해당 없음` + 변경 파일 목록 | 묶음은 scratch 폴더 · 검수 브리프 선택 · REPORT 대체 입력 | — |
| ★1~2 직접 처리 | 시험 이름·설명 | 계획자 · 완료 화면 `검사 결과` 와 실행 로그 | 선택(검수 패스가 있을 때 검수자) | — | — | — |
| 시험 없음(위 어느 경로든) | `해당 없음(<이유>)` | 해당 없음 | 해당 없음 · 화면 `변형` 생략 | 그 경로 규칙대로 | 그 경로 규칙대로 | 그 경로 규칙대로 |

시험 없음은 3종만 면제다. 회신·묶음·검수서·시작 평가는 그 경로의 규칙을 그대로 상속한다(★1~2 직접 처리는 원래 `—`).

## 4. 위임 계약

### 4.1 회신 계약 (Worker → Advisor, 채팅)

채팅 회신은 15줄 이내. 상세는 전부 `REPORT.md`(없는 경로는 회신에). 형식은 `BRIEF.md` 끝의 `## 회신` 절과 pair 2절·3절 브리프 틀에 그대로 들어 있어 Worker 가 베껴 쓴다.

```text
- 상태: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
- 변경 파일: <N>개 (목록은 REPORT. REPORT 가 없는 경로는 여기에 목록)
- 시험: <통과/전체> · 실패 먼저 <확인|해당 없음|미실행(agy) · Advisor 실행 대기> (REPORT 가 없는 경로는 실패 출력 1줄도 여기에)
- 우려·막힌 점: <BLOCKED·NEEDS_CONTEXT 는 여기에 구체적으로. 없으면 "없음">
- REPORT: <경로 | 해당 없음>
```

| 회신 상태 | 뜻 | Advisor 처리(relay unit 3단계 · plan 3절) |
|---|---|---|
| `DONE` | 완료 기준 전부 충족, 시험 통과(또는 Advisor 실행 대기) | diff·로그 확인 → 독립 검수 |
| `DONE_WITH_CONCERNS` | 완료했으나 정확성·범위에 의심이 있다 | 우려를 먼저 읽는다. 정확성·범위면 검수 전에 해소(재위임 또는 직접). 관찰(파일이 커졌다 등)이면 DEBT 후보로 적고 검수 |
| `NEEDS_CONTEXT` | 브리프에 없는 정보가 필요하다 | 재위임 원인 `brief`. 정보를 더해 같은 등급·effort 로 다시 맡긴다. 횟수 1 소모 |
| `BLOCKED` | 할 수 없다 | plan 3절 원인 가르기: `env` 면 환경을 고치거나 중단, `capability` 면 등급 한 단계 상향, 못 가르면 `unknown` 으로 두고 재현·로그 보강 |

- auto: `NEEDS_CONTEXT` 의 답은 R15 ① 판단 사다리(디스크 증거 → `decisions.md` → 범위 안 계획자 판단)로 구한다. 구했으면 `eval-goal.sh redeleg <키> incr` 뒤 재위임. 사다리 끝(사람 결정)이거나 `BLOCKED(env)` 면 재위임 없이 `eval-goal.sh stop blocked:<단위>`. `BLOCKED(capability)` 는 R14 ⑥ 그대로(상향 1회, `redeleg incr`).
- 커밋 줄은 없다. Worker 는 커밋하지 않는다(relay 5단계·pair 규칙).
- 브리프에 "하위 에이전트·검수자를 띄우지 않는다. 검수는 Advisor 가 따로 보낸다" 한 줄을 넣는다. Worker 가 띄운 검수는 같은 diff 를 두 번 보는 비용이고 판정으로 세지 않는다.
- Worker 구현 완료(`DONE`)와 Advisor 검증 완료는 다르다. 회신 `시험:` 줄이 `Advisor 실행 대기` 면 Advisor 가 돌린 뒤에야 검수로 간다.

### 4.2 검수 묶음 `scripts/pack-review.sh`

```text
사용: pack-review.sh [-C <저장소|워크트리>] --round <n> [--slug <이름>] [--cached | --range <base>..<head> | --patch-file <패치>] <출력 폴더> [-- <경로>...]
      pack-review.sh --verify <묶음>      # 적재물을 다시 만들어 해시 비교. 아무것도 쓰지 않는다
      pack-review.sh --patch <묶음>       # 적재물을 stdout 에. git apply -p1 용
출력: <출력 폴더>/review-<n>[-<slug>].diff 경로 한 줄
종료: 0 썼다·같다 · 1 변경 없음·다르다·기준 HEAD 바뀜 · 2 사용 오류·묶음 머리 못 읽음 · 3 이미 있음(덮어쓰지 않는다)
```

- 모드 넷. 작업 트리(기본): `git diff --stat HEAD -- <경로>...` + `git diff --binary -U10 HEAD -- <경로>...` + 미추적 파일(`git ls-files -z -o --exclude-standard -- <경로>...` 를 NUL 로 읽어 각각 저장소 루트에서 상대 경로로 `git diff --binary --no-index -- /dev/null <파일>`. exit 1 은 "차이 있음"이므로 정상). 커밋 전 diff 라 기준은 HEAD 다. `--cached`(auto, `checkwt` 뒤): `git diff --cached --stat HEAD` + `--binary -U10`. 신규 파일은 `add -A` 로 이미 들어 있다. `--range`(커밋 범위: 통합 검수 `init_head..HEAD`, 커밋 뒤 재검수): `git log --oneline` + `--stat` + `--binary -U10`. 기준은 Advisor 가 적어 둔 base(auto 는 state.json `init_head`·`expected_tip`)이고 `HEAD~1` 은 쓰지 않는다. `--patch-file`(다중 세션에서 Advisor 가 R11 ① 로 내 hunk 만 뽑은 패치): 적재물 = 그 파일. 받을 때 `git apply --numstat -p1 <패치>` 로 패치 문법·경로 해석만 본다(`--check` 는 현재 트리에 정방향 적용 가능한지도 보므로 이미 적용된 내 hunk 에서 실패한다. 트리·인덱스는 건드리지 않는다). 이 모드의 `--verify` 는 묶음 속 적재물의 자체 해시 확인일 뿐 작업 트리나 hunk 소유권을 검증하지 않는다. `--cached`·`--range`·`--patch-file` 에서 `-- <경로>...` 를 생략하면 `path:` 줄이 없고 전체가 범위다.
- 모든 diff 는 `git -c color.ui=false -c core.quotePath=false -c diff.noprefix=false diff --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ …` 로 돌린다(`--no-ext-diff`·`--no-textconv` 는 `diff` 뒤의 하위 명령 옵션이다. 전역 위치에 두면 `unknown option` 으로 exit 129). 사용자 git 설정(`diff.noprefix`·external diff·textconv)에 따라 출력이 달라지지 않고, 적재물은 항상 `git apply -p1` 로 적용된다. 설정 자체는 바꾸지 않는다.
- 경로는 상태표 pathspec 열에서 `<slug>:` 를 뗀 `<경로>` 만 넘긴다. 저장소가 둘이면 저장소마다 `-C <저장소> --slug <slug>` 로 따로 부른다. 파일 번호 `<n>` 은 검수 회차이고 Advisor 가 준다(자동 증가 없음). 같은 이름의 파일이 있으면 exit 3 으로 거부한다. 쓰기는 같은 폴더의 임시 파일에 완성한 뒤 `ln <임시> <최종>`(이미 있으면 실패) → 임시 삭제로 게시한다. 실패한 중간 파일은 최종 이름으로 남지 않는다.
- 묶음 머리(기계용 줄, 한 줄에 하나. 셸 eval 없이 읽는다): `repo: <절대 경로>` · `mode: worktree|cached|range|patch` · `base: <전체 OID>`(worktree·cached 는 HEAD, range 는 base, patch 는 HEAD) · `head: <전체 OID>`(range 만) · `path: <경로>`(경로마다 한 줄. 없으면 전체) · `slug: <이름>`(있을 때) · `payload-sha256: <적재물 해시>`. 사람용 제목 줄은 `# 검수 묶음 <n> — <출력 폴더 이름> — <저장소 폴더명> <모드> <sha7> — <YYYY-MM-DD HH:MM>`. 절은 `## 파일`(stat)·`## 커밋`(range)·`## diff`·`## 신규 파일`(작업 트리)·`## 회차 <n-1> 이후 변경`(회차 2 이상).
- 적재물 = `## diff` 절 본문 + `## 신규 파일` 절 본문(절 제목 줄은 뺀 순수 패치 바이트열). 생성·해시(`payload-sha256`)·`--patch` 출력·회차 간 `diff -u` 가 모두 같은 함수 `payload()` 의 같은 바이트열을 쓴다. `--patch` 는 `sed` 로 두 절의 본문만 잘라 붙인다.
- 변경 없음: 적재물이 비었을 때만 exit 1 과 `변경 없음`. 미추적 파일만 있어도 묶음을 쓴다. `--cached` 가 비면 `변경 없음(checkwt 를 돌렸는지 확인)`. 무변경 단위(R14 ⑦ (c) `NOCHANGE`)는 묶음 없이 4.4 의 무변경 검수로 간다.
- 회차 2 이상: 같은 폴더의 `review-<n-1>[-<slug>].diff` 적재물과 지금 적재물을 `diff -u`(exit 1 정상)해 `## 회차 <n-1> 이후 변경` 절에 넣는다. diff 의 diff 라 hunk 머리가 밀리면 잡음이 섞인다 — 참고용이고 판정은 전체 적재물로 한다(검수 브리프 4항). 이전 묶음이 없으면 절 대신 `이전 묶음 없음 — 전체 검수` 한 줄을 쓰고 검수 브리프도 재검수가 아니라 전체 검수로 쓴다.
- `--verify <묶음>`: 머리의 `repo:`·`mode:`·`base:`·`head:`·`path:` 로 적재물을 `payload()` 로 다시 만들어 `payload-sha256` 과 비교한다. worktree·cached 모드에서 현재 HEAD 가 `base:` 와 다르면 `기준 HEAD 가 바뀜` 으로 exit 1(커밋 뒤에는 뜻이 없다). `mode: patch` 는 재생성할 수 없어 파일 해시만 다시 잰다. 파일을 쓰거나 바꾸지 않는다. cached 모드는 인덱스를 비교한다 — 작업 파일의 복원 증거로는 `review-end` 가 재stage 와 파일 sha256 을 함께 본다(3.3).
- `--patch <묶음>`: 적재물을 그대로 stdout 에 낸다. `git apply -p1` 과 `git apply -R -p1` 에 쓴다.
- 크기가 300KB 를 넘으면 stderr 에 `주의: 묶음 <KB> — 검수자가 나눠 읽는다` 를 찍고 그래도 쓴다. R8(300줄 넘는 파일 cat 금지)은 검수자가 묶음 하나를 읽는 것으로 대신한다. 바이너리 파일은 `--binary` 로 적재물에 들어가지만 사람이 읽을 수 없으므로 `## 파일` 의 `Bin` 표시를 검수 브리프가 따로 확인 대상으로 적는다.
- bash 만 쓴다(python 없음). 인계 문서를 읽지 않는다. 출력 폴더는 relay 단위 폴더이거나(relay 밖 위임은) scratch 폴더다.

### 4.3 검수 브리프 `templates/REVIEW_BRIEF.md` (Advisor → 검수자)

4KB 이하. Advisor 가 복제해 `docs/relay/<plan>/<unit>/REVIEW_BRIEF.md`(relay 밖은 묶음과 같은 scratch 폴더)에 채운다. 고정 규칙은 템플릿 본문에 있고 Advisor 는 경로·대상·회차만 채운다. 절 일곱.

1. 읽을 것(실제 절대 경로, 이 순서): 브리프(`BRIEF.md`. relay 밖은 브리프 본문 파일) · 보고서(일반 `…/<unit>/REPORT.md`, auto 는 `<wt>/.relay-logs/REPORT.md` — 정리 전이라 단위 폴더에 없다. REPORT 가 없는 경로는 대체 입력: Worker 회신 전문을 저장한 파일 + 실행 로그 경로) · 보고서가 가리키는 로그 파일 · 검수 묶음 `review-<n>[-<slug>].diff`(변경의 전부. 잘린 hunk 가 있을 때만 그 파일을 연다) · 브리프가 절 번호로 인용한 정본의 그 절(좁게). 회차 2 이상: 이전 검수서 `INDEPENDENT_REVIEW.md` 와 이전 묶음.
2. 규칙: 보고서(또는 회신)를 믿지 않는다(주장마다 diff·로그로 확인. 못 한 주장은 "미확인 주장" 행에 적는다) · 범위는 diff(밖은 이름 붙일 수 있는 위험 하나를 볼 때만 — 호출 지점·락 순서·공유 상태 — 무엇을 왜 봤는지 적는다) · 뺄 것(지워도 되는 장치·시험·절차) 1개 이상, 없으면 `없음` · 하위 에이전트 금지 · 작업 디렉터리 밖은 건드리지 않는다 · 트리를 바꾸는 것은 변형 점검 1회뿐이고 바꾸기 전에 진행 표시를 남긴다 · 시험 실행은 3.3 의 3·5 단계 두 번뿐(R2) · 지적은 file:line·문제·수정 요구, 심각도는 실제 영향, 칭찬·서술 금지 · `Bin` 파일은 열어 확인한다.
3. 변형 점검(1회): 작업 디렉터리(auto 는 `<wt>` 절대 경로. 공유 트리 경로는 쓰지 않는다 / scratch 면 그 경로)·대상(잡을 결함 중 Advisor 가 고른 1개·파일·대상 시험 명령)·방식(제자리|scratch 워크트리|Advisor 대행|해당 없음)·진행 표시(auto 는 Advisor 가 `review-begin` 을 이미 돌렸음을 적는다 / 일반은 검수서+이월 / scratch 단독은 `review-<n>.progress`)와 3.3 절차.
4. 재검수일 때(회차 2 이상): 이전 검수서 지적 #1~#N 마다 해소|미해소 + file:line. "시도함"은 미해소. 새 결함은 묶음의 `## 회차 <n-1> 이후 변경` 절을 길잡이로 찾되 판정은 전체 적재물로 한다. 묶음 밖 관찰은 DEBT 후보. 변형 점검은 고친 파일을 다시 점검할 때만. 이전 묶음이 없으면 전체 검수다.
5. 통합 검수일 때(auto 8단계): 묶음은 `--range init_head..HEAD`(경로 생략 = 전체), 변형 점검 해당 없음, 지적은 단위 간 정합·중복·빠진 연결만(기존 범위). 결과는 `goal/INTEGRATION_REVIEW.md`.
6. 돌려줄 것: `INDEPENDENT_REVIEW.md` 형식으로 그 파일에 쓴다(출력이 다른 형식인 에이전트 — cavecrew 등 — 는 Advisor 가 옮겨 적는다). 채팅 회신은 `판정: PASS|FAIL · 지적 N건 · 변형 점검 검출|미검출|무효|복원 실패|해당 없음` 한 줄.
7. 티어: R3(순수 모듈 sonnet · 트랜잭션·권한·동시성 opus · 재위임으로 올린 코드는 그 등급 이상).

Advisor 쪽 규칙(relay unit 4단계에 적는다): 검수 브리프에 "이건 지적하지 마"·"minor 로만"·"계획이 정한 것이니 넘어가"를 쓰지 않는다. 반박은 검수서를 받은 뒤 plan 5절 방식(실물 확인·이유 한 줄)으로 한다. "미확인 주장" 행은 Advisor 가 증거(로그·재실행·재현)로 해소한다. 해소 못 하면 REPORT 미검증 항목과 완료 화면 `남은 일` 에 적고 완료라 쓰지 않는다.

### 4.4 검수서 `INDEPENDENT_REVIEW.md` 변경

판정 줄·발견 표는 그대로. 둘째 줄 `검수 범위:` 를 `검수 입력: review-<n>[-<slug>].diff + BRIEF + REPORT · 실행: 변형 점검 1회 + 신규 시험 1회 · 티어: <sonnet|opus>` 로 바꾼다. 표 아래 줄 세 개를 더한다.

```text
변형 점검: <바꾼 것 한 줄> → <시험 이름> 검출 | 미검출(판정 FAIL) | 무효(<사유>) | 복원 실패 | 해당 없음(<이유>)
검토에서 뺀 것(이유): - (없으면 "없음")
미확인 주장(보고서에 있으나 diff·로그로 확인 못 함): - (없으면 "없음")
```

- 변형 전에는 그 자리에 `변형 점검 진행: <파일> <sha256> <시각>` 이 먼저 들어간다(진행 표시. 일반 relay 는 인계 문서 이월에도 같은 줄). 결과 줄로 바뀌기 전의 검수서·이월은 "되돌리지 못한 상태"로 읽는다(resume 3단계).
- 재검수(회차 2 이상)는 같은 파일 끝에 `## 재검수 <n>` 절을 더한다: 지적별 해소|미해소 표 + 새 결함 표 + 변형 점검 줄(했을 때만).
- 무변경 단위(묶음 없음): 빈 diff 는 "할 일이 없었다"의 증거가 아니다. 검수 브리프는 묶음 대신 저장소·HEAD(OID)·pathspec·완료 기준·Worker 가 "이미 충족됨"의 근거로 든 코드 경로와 로그를 전달한다. 검수자는 그 코드를 읽고 대상 시험을 1회 돌려(R2 안) 완료 기준이 실제로 충족되는지 판정한다. 시험 도구가 없는 프로젝트면 대상 시험 대신 plan 4절의 실제 확인으로 대신하고 그렇게 적는다. 판정 줄은 `판정: PASS|FAIL · 변경 없음`, `변형 점검: 해당 없음(변경 없음)`. `--verify` 는 돌리지 않는다(묶음이 없다).

## 5. 시작 평가 (auto · `eval-goal.sh init` · `start-eval`)

- 왜: 지금 `init` 은 `cmd:` 를 돌리지 않는다(`cmd_init` 은 `iterations=0`·`last_eval=None` 만 적는다). 계획 전부터 실패하던 조건이 있으면 보정 단위 2회차를 그것이 먹고 `fix-cap` 으로 멈춘다. 원인이 계획 밖이었다는 사실을 아무도 모른다.
- 흐름(`init`): `check`(정적) → 사용자 확인 1회(명령 목록·자산·"승인 창이 뜨면 멈춤" — 지금 그대로) → 기존 검사 뒤 잠금 안에서 state.json 을 먼저 쓴다(`started_at`, `initial_eval: {status: "running", attempt: 1, started_at}`. 시작 평가 시간도 최대 시간에 든다) → 잠금을 푼 채 `cmd:` 를 반복 0으로 한 번 돌린다(아래 "실행 소유 기록") → 사후 검사: 저장소별 `HEAD`·`target_ref`·계획 경로 `dirty` 를 다시 본다(어긋나면 `halt = judge-fail` 과 0.log 에 `시작 평가가 계획 경로를 더럽혔다: <파일>`. 부작용은 되돌리지 않고 보고한다) → 최종 기록(아래) → 결과 출력(`시작 평가: 통과 N/M` + 명령별 exit). 질문은 늘지 않는다.
- 실행 소유 기록(`evaluate(c, cmds, root, tsec, owner)` — `cmd_run` 의 실행·수집 부분을 함수로 떼어 둘이 같이 쓴다. `owner` 는 시작 평가에서만 넘기고 `cmd_run` 은 `None` 이라 일반 `run` 은 그대로다): 명령마다 ⓐ 띄우기 전에 잠금 한 번으로 `initial_eval.running = {cmd, k, attempt, phase: "spawning"}` 를 적는다(예약) ⓑ `run_one` 이 자식을 띄운 직후 `on_spawn(pid, lstart, ppid)` 을 부르면 잠금 한 번으로 `running` 을 `{…, pid, lstart, ppid, phase: "running", out: "goal/0-<k>.out"}` 로 바꾼다(`ps` 가 실패하거나 빈 값이면 `lstart: null` 로 적고 예외를 내지 않는다). `owner` 가 있으면 `run_one` 은 출력을 TemporaryFile 대신 `goal/0-<k>.out` 에 바로 쓴다(실행 중에도 디스크에 남는다. 다음 시도가 덮어쓴다) ⓒ 명령이 끝나면(정상·제한 시간·126/127 모두) `owner` 가 있으면 정상 종료 뒤에도 `group_left(pid)` 로 남은 프로세스를 확인한다(지금 `run_one` 은 제한 시간 분기에서만 본다. 일반 `run` 은 그대로). 남은 것이 있거나 확인하지 못하면 제한 시간 생존과 같이 `timeout-survivors` 로 멈춘다. 그 다음 그 명령의 블록(`$ cmd`·exit·꼬리 50줄·생존 목록 또는 `확인 못 함`)을 `goal/0.log` 에 덧붙이고(머리 `# 반복 0 · 시도 <n>` 은 첫 명령 전에 쓴다. 이전 시도의 0.log 는 덮어쓴다), 그 다음 잠금 한 번으로 `running` 을 `{…, phase: "ended", exit, survivors: [...]|null}` 로 바꾼다 ⓓ 다음 명령은 ⓐ 부터. `running` 은 최종 기록에서만 지운다. 직접 띄운 pid 가 죽었다는 것은 실행이 끝났다는 증거가 아니다(제한 시간 뒤 하위 프로세스가 남을 수 있다) — 끝남의 증거는 `phase: ended` 와 `survivors` 가 빈 목록이라는 영속 기록뿐이다.
- 최종 기록(이 순서): `eval.md` 의 `- 반복 0 (시작) …` 줄(있으면 교체, 없으면 첫 줄) → 인계 문서 `최근 조건 평가: 0 …` 줄 → 잠금 한 번(`c.update`)으로 `initial_eval = {status: "done"|"halted:<사유>", attempt, at, cmds, results}` 를 적고, 멈출 사유가 있으면 같은 갱신에서 `stopped_reason = <사유>` 까지. `running` 은 모든 명령이 `ended` 이고 `survivors` 가 빈 목록으로 확인됐을 때만 같은 갱신에서 지운다. 생존이 있거나 확인하지 못했으면(`timeout-survivors`) `running = {…, phase: ended, survivors}` 를 남겨 둔다 — 사람이 그 프로세스를 정리하고 `state <HANDOFF.md> del initial_eval.running` 으로 지우기 전에는 `start-eval` 이 거부된다(미정리 실행 표식은 `running` 하나다. `results[*].survivors` 는 기록일 뿐 가드가 아니다) → 그 뒤 인계 문서 `중단:` 줄(`stop()` 의 set_line 부분. 상태와 사유가 한 갱신에 있으므로 이 줄을 쓰기 전에 죽어도 아래 우선 규칙이 잡는다). `judge-fail` 은 exit 3, `timeout-survivors` 는 exit 1.
- 실패해도 init 은 성공이다. 계획 목적이 "실패하는 시험을 고치기"인 경우가 흔하다. 세션 첫 보고에 `시작 평가: 통과 1/2 · 실패 <cmd>` 한 줄을 적는다. 단순 제한 시간 초과(생존 없음)는 그 `cmd:` 의 실패일 뿐 멈추지 않는다.
- 멈춘 뒤: state.json 이 있으므로 재-init 은 "state.json 이 이미 있다"로 거부된다. resume 가 아래 우선 규칙으로 3행 처리를 한다(사람이 0.log 의 생존 목록과 `initial_eval.running` 을 보고 그 pid 하나를 끝내거나 명령을 고친다). 정리 뒤 4행 ④½ 이 시작 평가를 다시 돌린다.
- `start-eval <HANDOFF.md>`(새 하위 명령, DRIVING): 조건 — state.json 이 있고 `initial_eval` 키가 있고(옛 state 는 미상이라 대상이 아니다) `status ≠ "done"` 이고 `units` 가 비어 있고 `stopped_reason` 이 비어 있다. `running` 이 있으면 `phase: ended` 이고 `survivors` 가 빈 목록일 때만 통과한다. `spawning`(소유 미확정)·`running`(끝났다는 증거 없음. pid 가 죽어 있어도 같다)·`ended` 인데 `survivors` 가 비어 있지 않거나 `null`(확인 못 함)이면 거부한다(`BLOCKED: 시작 평가 실행이 끝났다는 기록이 없다 — 0-<k>.out·pid <pid> 를 확인하고 `state del initial_eval.running`` 으로 사람이 정리한다). 살아 있는 프로세스 판정은 참고 정보로만 보인다(`os.kill(pid, 0)` 존재 확인 → 살아 있으면 `ps -o lstart=` 비교. `lstart` 가 `null` 이거나 `ps` 가 실패하면 "살아 있을 수 있음"). 이름 검색·그룹 종료는 하지 않는다. 조건이 맞으면 `attempt` 를 +1 하고 `status: running`·`running` 삭제를 한 갱신으로 적은 뒤 위 "돌린다 → 사후 검사 → 최종 기록" 을 다시 한다. `done` 을 확정하는 최종 갱신에서 `resume_after_cleanup` 도 지운다. `init` 도 같은 함수를 부른다.
- 전이표 변경(SKILL.md `## auto` 12단계): 행을 고르기 전에 우선 규칙 — "`initial_eval` 키가 있고 `status ≠ done`(`running` 이든 `halted:*` 든)이면: `resume_after_cleanup` 이 없으면 `stopped_reason`·`중단:` 줄과 무관하게 3행 처리다(등록하지 않고 `initial_eval`·`running`·0.log 생존 목록을 보이고 `resume_after_cleanup: true` 를 적는다). `resume_after_cleanup: true` 이고 `중단:` 줄·`blocked` 행이 없으면 4행이다(④½ 이 `start-eval` 로 `done` 을 확정하기 전에는 ⑤·⑥·Worker 진입을 하지 않는다. `start-eval` 이 거부되면 다시 3행 처리). `status: done` 이거나 키가 없는 옛 state 는 기존 행으로 간다." / 4행 ③ 에 "단위가 아직 없을 때 외부 커밋을 받아들이면 `expected_tip` 과 함께 `init_head` 도 현재 HEAD 로 갱신한다(통합 검수 범위)" / 4행 ④ 와 ⑤ 사이에 새 단계 "④½ `initial_eval` 이 있고 `status ≠ done` 이면 `eval-goal.sh start-eval`. 거부되거나 멈추면 3행으로 되돌아간다(`resume_after_cleanup` 은 지운다)". `clear-stop`·경계 갱신 뒤라서 `stopped_reason` 조건과 어긋나지 않는다. 4행 ⑥(등록·진입)에서도 `resume_after_cleanup` 을 지운다 — 지금 전이표는 이 키를 지우는 단계가 없어 뒤의 비정상 종료(2행)가 4행으로 잘못 갈 수 있다. 이 설계에서 같이 고친다.
- `iterations`·`last_eval` 은 건드리지 않는다. 시작 평가는 재사용 대상이 아니다(R13 ⑦ 재사용은 `last_eval` 기준).
- 귀속 규칙(R14 ⑪ 에 더한다): 단위가 전부 `완료`인데 실패한 `cmd:` 가 시작 평가에서도 실패했고, 어느 단위의 완료 기준도 그 조건을 겨냥하지 않았고, 계획자가 0.log 와 지금 로그를 비교해 같은 원인임을 확인했으면 보정 단위가 아니라 `eval-goal.sh stop scope` 로 중단한다. 세 조건 중 하나라도 못 채우면 보정 단위다. `fix add --key <cmd>` 는 `initial_eval.results` 의 같은 명령(둘 다 `nocomment()` 로 정규화해 비교)이 실패였으면 `주의: 이 조건은 시작 평가에서도 실패했다(0.log)` 를 찍는다. 거부하지는 않는다. `initial_eval` 이 없거나 `status ≠ done` 인 state 는 "시작 결과 미상"이고 경고도 귀속도 없다.
- `status-json` 에 `initial_eval: {status, attempt, passed, failed, running}` 를 더한다(없으면 `null`). status.sh 표시는 바꾸지 않는다.
- `state del <키>`(새 하위 명령. 호출 형태는 다른 것과 같이 `eval-goal.sh state <HANDOFF.md> del <키>`): 잠금 안에서 키 하나를 지운다(`set … null` 은 값 `null` 을 남기므로 다르다. 없는 중간 경로는 만들지 않는다). `mutation_unrestored`·`initial_eval.running` 정리와 시험에 쓴다. USAGE 에도 적는다.
- state.json 필드(DESIGN-auto.md 8절에 추가): `initial_eval = {status: running|done|halted:<사유>, attempt, started_at, at?, cmds?, results?:[{cmd, exit, timeout, survivors?}], running?: {cmd, k, attempt, phase: spawning|running|ended, pid?, lstart?, ppid?, out?, exit?, survivors?}}` 또는 없음(옛 state). `units.<단위>.mutation = {package, file?, sha256?, at}`(검수 예약·변형 점검 진행 표시) · `units.<단위>.mutation_unrestored = {file?, sha256?, verify, why}`(기록하고 멈춤) · `stage` 값에 `reviewing` 추가 · `recover` 출력어에 `recheck` 추가.

## 6. 흐름 (relay 단위 하나, 전후)

```text
지금:  브리프 → Worker → Advisor 확인(diff+로그) → 독립 검수(diff+신규 시험) → 커밋 → 인계 갱신
뒤:    브리프(+잡을 결함·회신 계약) → Worker(+실패 먼저) → 회신 상태로 가르기 → Advisor 확인
       → pack-review → 검수 브리프 → 독립 검수(묶음 + 진행 표시 → 변형 점검 1회 → 복원 → 신규 시험 1회) → 커밋 → 인계 갱신
auto:  init(+시작 평가) → [반복] 위와 같되 묶음은 --cached, 변형 점검은 <wt> 안(review-begin → 변형 → review-end. 묶음이 있는 단위만)
```

## 7. 파일 변경 목록

| 파일 | 변경 | 이유 |
|---|---|---|
| `plan/SKILL.md` 3절 | 위임 지시 내용에 "시험마다 잡을 결함 한 줄 · 회신 계약 · 하위 에이전트·검수자 금지" / 회신 상태 4종 → 재위임 원인 매핑 / agy 2단계 브리프는 횟수에 안 셈 | 계약의 정의는 plan |
| `plan/SKILL.md` 4절 | "실패 먼저 확인(버그 수정)" 줄을 "시험 증거 3종" 줄로 바꾸고 "허수 시험 금지" 줄 추가. 3.5 적용표의 요지(직접 처리·시험 없음) | 정의 한 곳 |
| `plan/SKILL.md` 9절 | `검사 결과` 값에 `변형 N/N`(검출/시도)을 더하는 규칙 한 줄. 해당 없음이면 생략 | 라벨 추가 없이 보고 |
| `go/playbooks/bug-fix.md` 4단계 | 인용 `4절 "실패 먼저 확인"` → `4절 "실패 먼저"` | 이름 일치 |
| `relay/SKILL.md` resume 3단계·unit 1~4단계 | resume: 이월의 `변형 점검 진행` 줄 → 복원 미확인 처리 / 1: 잡을 결함·회신 계약 / 2: 회신 15줄 / 3: 회신 상태로 먼저 가르기(auto 는 `redeleg incr`·`stop`) / 4: pack-review → REVIEW_BRIEF → 진행 표시(검수서+이월) → 검수서(행 3개), 사전 판단 금지, 미확인 주장 해소 책임, 무변경 검수, `/code-review` 대체 시 변형 점검은 Advisor | 절차는 relay |
| `relay/SKILL.md` auto 1·4·8·12단계 | 1: "init 이 시작 평가(반복 0)를 돌려 결과를 보인다" / 4: 검수 전 `review-begin`, 검수 뒤 `review-end --pass|--fail`(묶음 있는 단위만) / 8: 통합 검수 묶음 `--range` / 12: 전이표 앞 우선 규칙(`initial_eval.status ≠ done` → 3행), 4행 ③ `init_head` 갱신·④½ `start-eval` | |
| `relay/references/rules.md` | R2(검수자 실행 = 변형 1회 + 신규 시험 1회) · R12(REVIEW_BRIEF 4KB, 검수서 행 3개) · R13 ⑥(시작 평가·`start-eval`·`running`) · R14 ⑤(`review-begin`·`review-end`·복원 실패) ⑩(`mutation` 분기·출력어 `recheck`) ⑪(귀속 규칙) · 증거 디렉터리 줄에 `REVIEW_BRIEF.md`·`review-<n>.diff` | |
| `relay/templates/BRIEF.md` | Goal 에 `잡을 결함:` / 규칙에 하위 에이전트 금지 / 검증에 실패 먼저 / 끝에 `## 회신` 5줄 | |
| `relay/templates/REPORT.md` | 검증 결과 표 아래 `실패 먼저:` 줄 | |
| `relay/templates/INDEPENDENT_REVIEW.md` | 둘째 줄 갱신 + 행 3개 + 진행 표시 줄·`## 재검수 <n>`·무변경 규칙 주석 | |
| `relay/templates/REVIEW_BRIEF.md` (신규) | 4.3 | 검수 입력을 형식으로 |
| `relay/scripts/pack-review.sh` (신규) | 4.2 | |
| `relay/scripts/eval-goal.sh` | `evaluate(owner)` 분리와 `run_one(on_spawn)`(시작 평가만) / `cmd_init` 시작 평가·실행 소유 기록·사후 검사·최종 기록 한 갱신 / 새 `start-eval`·`state del`·`unit … review-begin [<파일>]`·`review-end --pass|--fail`(`cmd_unit` 의 추가 인자 허용에 둘 추가) / `recover` 의 `reviewing` 분기·`mutation_unrestored` 가드·출력어 `recheck` / `cmd_fix add` 경고 / `status-json` 필드 | 5절·3.3 |
| `relay/references/DESIGN-auto.md` 8절 | `initial_eval`(`running` 포함)·`units.<u>.mutation`·`mutation_unrestored`·`stage: reviewing`·출력어 `recheck` | 기록 |
| `relay/README.md` | auto 시작 3단계에 "시작 평가 결과를 보여 준다" / 기본 사용 3단계에 "검수는 묶음 파일로" | |
| `pair/SKILL.md` 2.3·3절 | codex 브리프·agy 브리프 틀에 회신 계약 5줄(`Status:` 첫 줄, `REPORT: 해당 없음` 허용, 실패 출력 1줄) · 하위 에이전트 금지 · agy 2단계 브리프 | codex·agy Worker 도 같은 계약 |
| `tests/relay/pack-review.test.sh` (신규) | 9절 P1~P13 | |
| `tests/relay/eval-goal.test.sh` | 9절 I1~I13 + 기존 fixture 재배치 | |
| 버전 3곳(check.sh 버전 일치 검사 대상) | 0.2.0 → 0.3.0 | 새 스크립트·템플릿·state 필드·하위 명령 |

바꾸지 않는 것: go(경로·playbook — bug-fix 한 단어 제외), explain, check-impact, check-benchmark, make-verifier, `scripts/check.sh`(새 스크립트는 자동 검사 대상), PLAN·HANDOFF·DEBT 템플릿, state.json 기존 키, 화면 줄, `run_one` 의 잠금 상속(없음).

## 8. 사용 방법 (사용자 눈에 달라지는 것)

1. 작업 계획 화면은 그대로다. 브리프에 `잡을 결함:` 줄이 생긴다. 예: `잡을 결함: 재시도 횟수를 2로 바꾸면 test_retry_three 가 실패한다`.
2. Worker 회신이 5줄짜리 고정 형식이 된다. 첫 줄 상태로 다음 행동이 정해진다.
3. 검수가 파일(브리프·보고서·로그·묶음)로 간다. 검수서에 `변형 점검:`·`검토에서 뺀 것:`·`미확인 주장:` 줄이 생긴다. 변형 점검이 "미검출"이면 시험을 다시 쓴다.
4. 완료 화면 `검사 결과` 에 `변형 1/1` 이 붙는다(해당 없으면 안 붙는다).
5. auto 는 init 직후 `시작 평가: 통과 N/M` 한 줄을 본다. 이미 실패하던 조건은 같은 원인으로 확인되면 보정 단위를 먹지 않고 `scope` 로 멈춘다. 시작 평가 도중 끊기면 재개 때 먼저 다시 돈다.
6. 시험 없음 경로(문구·스타일·도구 없음)는 3종이 `해당 없음` 이다. 나머지 절차는 그 경로 그대로다.
7. agy 가 Worker 면 "시험 먼저 → 이 세션이 실패 확인 → 구현" 두 번으로 간다.

## 9. 확인 방법

- `scripts/check.sh` 9개 통과(새 스크립트 실행 비트·`bash -n`, 경로 참조, 금칙어, 버전 일치). U2 가 `scripts/pack-review.sh` 를 참조하므로 U3 가 먼저다.
- `tests/relay/pack-review.test.sh` P1~P13: 작업 트리 모드 stat·diff·신규 파일 절·머리 줄(P1) / 미추적 파일만 있어도 씀(P2) / `--cached`(P3) / `--range` 커밋 목록·`head:`·경로 생략(P4) / 변경 없음 exit 1·파일 없음(P5) / 같은 이름 exit 3·임시 파일 없음(P6) / `--slug`·`-C`·공백 경로(P7) / 회차 2 의 `이후 변경` 절에 신규 파일 수정분 포함(P8) / `--verify` 같음·다름·`기준 HEAD 가 바뀜`·아무것도 안 씀(P9) / `--patch` 를 `diff.noprefix=true` 가 설정된 저장소의 scratch 워크트리에 `apply -p1`·`apply -R -p1` 해 깨끗해짐(바이너리 포함)(P10) / 사용 오류 exit 2(P11) / 300KB 경고(P12) / `--patch-file` 모드와 그 `--verify`, 이미 적용된 내 hunk 와 남의 hunk 가 같은 파일에 있어도 받음(P13).
- `tests/relay/eval-goal.test.sh` I1~I13: `init` 뒤 `goal/0.log`·eval.md `반복 0 (시작)`·`최근 조건 평가: 0`·`initial_eval.status=done`·`attempt=1`·`running` 없음(I1) / 실패 명령에도 exit 0, `iterations` 0, `last_eval` null(I2) / exit 126 → `judge-fail`·`stopped_reason` 이 `status` 와 같은 갱신에 기록·뒤 명령 미실행·재-init 거부(I3) / 생존 프로세스(제한 시간·정상 종료 뒤 자식 잔류 둘 다) → `timeout-survivors`·`status=halted:…`·0.log 에 생존 목록·`running` 유지, `clear-stop` 뒤 `start-eval` 거부, `state del initial_eval.running` 뒤 통과(I4) / 사후 검사 더럽힘 → `judge-fail` 과 0.log 줄(I5) / `fix add --key` 경고, 주석 붙은 키도 매칭(I6) / 옛 state(키 없음) → 경고 없음·`status-json` null·`start-eval` 거부(I7) / `status-json` 수치·`running`(I8) / 시작 평가 도중 부모 사망(자식 생존) → `status=running`·`running.phase=running`·pid 남음·`0-<k>.out` 에 출력, `start-eval` 은 pid 가 죽어도 `ended` 기록이 없으면 거부, 사람이 `state del initial_eval.running` 한 뒤 `attempt=2` 로 `done`·`resume_after_cleanup` 삭제, eval.md 반복 0 줄은 1개(I9) / `running.phase=spawning` 또는 `ended`+`survivors` 비어 있지 않음 또는 `null` → `start-eval` 거부, `ended`+빈 목록 → 통과(I10) / `recover`: `stage=reviewing`+`mutation` 있음 + 인덱스는 같고 작업 파일만 변형된 채 → BLOCKED·`mutation_unrestored`(mutation 유지), 복원된 채 → `recheck`·`mutation` 유지, `mutation_unrestored` 있으면 즉시 Blocked(I11) / `review-begin`(파일 있음·없음)·`review-end --pass` 가 `stage`·`mutation` 을 한 갱신에 바꾸고 `--fail` 은 `started`, 기존 `mutation` 위 `review-begin` 은 검사 뒤 교체(I12) / `state del` 과 `stopped_reason` 이 있을 때 `start-eval` 거부(I13).
- 기존 fixture 재배치(U4 범위): `must init` 뒤 `run` 을 돌리는 시험들은 init 이 이제 `cmd:` 를 돌리므로 설정을 바꾼다 — 인계 문서를 통과하는 명령으로 `init` 한 뒤 `cmd:` 줄을 바꾸고(새 helper `setcmd`) `run` 한다. 대상: 271·584·609~610·621·874행의 `must init`(생존·카운터·stopper fixture), 679행의 `mkdir -p goal/eval.md`(init 이 파일을 만들므로 오류 주입 방식 변경), 265행 `eval.md 3행` → 4행, COUNT 초기화 위치. 시험 수는 실제 결과를 적는다.
- 변형 점검을 이 설계 자체에 적용한다: pack-review.sh 의 신규 파일 절을 적재물에서 빼면 P8·P10 이, `--verify` 비교를 항상 참으로 바꾸면 P9 가, prefix 고정을 빼면 P10 이, `cmd_init` 의 시작 평가 호출을 지우면 I1 이, 사후 검사를 지우면 I5 가, `running` 예약(ⓐ)을 빼면 I10 이, `recover` 의 재stage 를 빼면 I11 이, `review-end` 의 sha256 비교를 빼면 I12 가 실패하는지. 각 구현 단위의 완료 기준에 넣는다.
- 문서 따라가기: 처음 읽는 에이전트 역할로 일곱 경로를 손으로 따라가 본다 — 일반 relay 단위(단일·다중 세션) · 일반 단일 세션에서 변형 도중 끊김 → 다음 세션 resume · auto 무변경 단위 · pair codex 단독 · pair agy(2단계) · ★1~2 직접 처리 · 저장소 둘인 일반 단위. 빠진 연결이 있으면 설계로 돌아온다.

## 10. 만드는 순서 (relay 단위)

| 단위 | 내용 | 파일 | 선행 | 모델·effort | 검수 | 완료 기준 |
|---|---|---|---|---|---|---|
| U1 | plan 3·4·9절 문안, bug-fix 한 단어 | plan/SKILL.md, go/playbooks/bug-fix.md | — | sonnet low | sonnet | check.sh 통과 · 2절 용어와 일치 |
| U3 | pack-review.sh(모드 4·`--verify`·`--patch`·prefix 고정·원자 게시) + 시험 P1~P13 | relay/scripts/pack-review.sh, tests/relay/pack-review.test.sh | — | sonnet low. 스크립트+시험이 150줄을 넘으면 opus low(plan 3절) | sonnet | 시험 통과 · 변형 3건 잡힘 |
| U2 | 템플릿 4개 + relay unit 1~4단계·auto 4·8단계 + R2·R12·증거 디렉터리 + pair 2.3·3절 | relay/templates/*, relay/SKILL.md, rules.md, pair/SKILL.md | U1, U3 | sonnet low | sonnet | check.sh 통과 · REVIEW_BRIEF ≤ 4KB · BRIEF ≤ 8KB |
| U4 | `evaluate(owner)`·`run_one(on_spawn)`·시작 평가·`start-eval`·실행 소유 기록·사후 검사·최종 기록 + `review-begin`/`review-end`·`state del` + recover `reviewing`·`recheck`·가드 + fix add 경고 + status-json + 시험 I1~I13·fixture 재배치 + R13 ⑥·R14 ⑤⑩⑪ + auto 1·12단계·전이표 우선 규칙 + resume 3단계 + README + DESIGN-auto 8절 | eval-goal.sh, eval-goal.test.sh, rules.md, relay/SKILL.md, relay/README.md, DESIGN-auto.md | U2 | opus medium(상태 파일·잠금·중단 기록·복구) | opus | 시험 전부 통과 · 변형 4건 잡힘 |
| U5 | 버전 0.3.0 + check.sh·test.sh 전체 | 버전 3곳 | U1~U4 | haiku low | Advisor | 전부 통과. 실패 원인 판단은 Advisor |

U1 과 U3 는 병렬 가능(다른 파일). U2 와 U4 는 `relay/SKILL.md`·`rules.md` 를 같이 만지므로 직렬(U3 → U2 → U4).

## 11. 보장하지 못하는 것

- 잡을 결함이 사소하면 변형 점검도 사소하다. 의미 있는 결함을 고르는 것은 계획자의 판단이고 기계가 검사하지 않는다.
- 변형 점검 1건은 "그 시험이 그 결함을 잡는다"는 증거다. 시험 묶음 전체가 옳다거나 다른 결함도 잡는다는 보장은 아니다. 도구 기반 뮤테이션(전체 연산자 뒤집기)을 대신하지 않는다. 도구가 있는 프로젝트는 그 도구를 `cmd:` 에 둔다.
- 단일 세션 제자리 변형 중(수 초)에 다른 세션이 생기면 변형된 내용을 볼 수 있다. 다중 세션 흔적은 변형 전 `git status --short` 로 보지만 그 뒤에 생긴 세션은 못 본다. 진행 표시는 "되돌리지 못했다"를 알려 줄 뿐 막지는 못한다.
- 시작 평가는 `cmd:` 한 벌 실행 비용(제한 시간 상한)을 init 에 더한다. `cmd:` 의 부작용(파일 생성)은 되돌리지 않고 보고만 한다. 조건 명령의 자식은 `.driver` 를 물려받지 않으므로 부모가 죽은 뒤 남은 자식은 `run` 때와 같이 사람이 끝낸다(0.log 생존 목록).
- 회신 계약·검수 브리프는 지시일 뿐이다. 길게 답하는 Worker·형식을 어기는 검수자를 기계가 막지는 않는다.
- 시작 실패와 현재 실패가 "같은 원인"인지는 계획자가 로그를 비교해 판단한다. 같은 명령 문자열이라는 것만으로 같다고 보지 않는다.
- scratch 워크트리 제거가 거부되면(시험이 남긴 파일) 사람이 정리한다. 강제 삭제는 하지 않는다.
- `group_left` 는 같은 프로세스 그룹의 잔류만 본다. 그룹을 떠난 하위 프로세스가 끝났다는 증명은 아니다(일반 `run` 과 같은 한계).
- 시작 평가 도중 부모가 죽으면 자식은 `.driver` 없이 돈다. `initial_eval.running` 의 pid·lstart·ppid·`0-<k>.out` 이 단서다. 끝났다는 영속 기록(`ended` + 빈 `survivors`)이 없으면 `running` 이 남고 `start-eval` 은 거부된다. 사람이 확인한 뒤 `state <HANDOFF.md> del initial_eval.running` 으로 푼다(fail-closed). 하위 프로세스가 남았는지는 기계가 확정하지 못한다 — 직접 pid 가 죽었다는 것만으로는 끝났다고 보지 않는다. 띄운 직후 기록 전에 죽는 아주 짧은 틈은 `spawning` 으로 남고 pid 는 없다.

## 12. 정해야 할 것

1. 변형 점검 횟수: 단위당 1회(설계) vs 요구사항 시험마다 1회. 설계는 비용(R2) 때문에 1회.
2. 회신 상태 4종 토큰: 영문(설계) vs 한글(`완료`·`완료-우려`·`막힘`·`정보 필요`). 설계는 기계 값 관례를 따른다.
3. 검수 브리프를 새 템플릿으로(설계) vs INDEPENDENT_REVIEW.md 상단에 지시 포함. 설계는 입력(브리프)과 출력(검수서)을 가른다.
4. 시작 평가 실패 시 init 거부 여부. 설계는 거부하지 않는다(계획 목적이 실패 고치기일 수 있다).
5. 다중 세션의 변형 점검을 scratch 워크트리로 할지(설계) 항상 `해당 없음` 으로 둘지.
6. `recheck` 라는 출력어 이름(대안: `rereview`). 7. 버전 0.3.0.

## 13. 변경 이력

- v1 (2026-10-21): 초안.
- v2 (2026-10-21): codex 10건·agy 10건 반영(상세는 v2 기록. 요지: 용어 셋 교체, 3.3 판정 세 갈래·복원 실패 분리·scratch, 3.2 agy 2단계, 3.5 적용표, 4.2 `--round`·`--slug`·`--range`·`--verify`, 4.4 무변경, 4.1 auto 사다리, 5절 state 선기록·중단 기록·`nocomment`, 9·10절 시험·순서).
- v3 (2026-10-21): 2라운드 codex 7건·agy 7건 + 부분 해소 8건 반영. 묶음 머리에 `repo:`·`mode:`·`base:`·`head:`·`path:`·`payload-sha256:` 기계용 줄, 적재물(diff+신규 파일) 정의, `--binary`·색상 끔·NUL 경로, `--patch`, 이미 있음 exit 3·원자 게시, `--verify` 가 기준 HEAD 변경을 거부(codex B1·B2, agy 1·5) · scratch 는 `--patch` 적용 → 5단계 → 변형 → `apply -R` → `worktree remove`, 거부 시 이월(codex B3, agy 2) · 진행 표시(state `mutation`·`stage: reviewing` / 검수서 `변형 점검 진행:`)와 recover 의 `--verify` 분기·`mutation_unrestored`(codex B6, agy 7) · 적용표: pair agy 를 relay 안/단독으로 분리, 시험 없음은 경로 규칙 상속, REPORT 없는 경로의 회신 `시험:` 줄과 대체 입력(codex B5, agy 4) · 무변경 검수는 코드·로그·대상 시험 1회로 "이미 충족" 판정(codex B7) · 시작 평가: `initial_eval.status` running/done/halted, 사후 검사를 기록 전으로, `start-eval` 하위 명령, 전이표 2·3·4행(codex B4, agy 3) · `--verify` 는 묶음 있는 단위만(agy 6) · 검수 브리프에 작업 디렉터리(agy 7) · U3 상향 기준 150줄, fixture 재배치 목록(codex 10·시작 평가 메모) · `.driver` 를 조건 명령 자식에 안 넘기는 것은 `run` 과 같다고 0절·11절에 명시(codex B4 일부, 바꾸지 않음).
- v4 (2026-10-21): 3라운드 codex 6건·agy 5건 + 자체 2건 반영. auto 변형 점검을 `unit … review-begin`/`review-end --pass|--fail` 두 하위 명령으로 묶어 진행 표시·재stage·`--verify`·파일 sha256·`mutation` 삭제·`stage` 확정을 각각 잠금 한 번에(codex B1·B2, agy B1) · `recover` 는 재stage 뒤 검사하고 새 출력어 `recheck`(기존 `review`=커밋부터 유지), 불일치는 `block()` 으로 `mutation_unrestored`(codex B1·B2, agy B1, 자체 1·2) · `state del` 신설(agy B1) · 일반 relay 진행 표시를 인계 문서 이월에도 쓰고 resume 3단계가 읽음, 단독 pair·plan 일꾼은 제자리 변형 금지(scratch 만)(codex B6, agy B5) · scratch 는 `base:` 커밋으로 만들고 `-p1` 적용, 4·6 단계 포함, 남의 hunk 혼재는 `--patch-file` 묶음 + 변형 해당 없음(codex B5, agy B3) · pack-review: prefix 고정(`--src-prefix=a/ --dst-prefix=b/`, `diff.noprefix=false`), `payload()` 는 절 제목 없는 본문, `-- <경로>` 선택, `--patch-file` 모드(codex B5, agy B4) · 시작 평가: `start-eval` 은 전이표 4행 ④½(clear-stop·경계 갱신 뒤), 4행 ③ 이 `init_head` 도 갱신, eval.md 반복 0 줄 교체, 0.log 시도 머리, `initial_eval.running={cmd,pid,lstart,attempt,log}` 실행 소유 기록과 생존 중 거부, 옛 state 제외(codex B3·B4, agy B2) · 시험 I9~I12·P13 추가, 문서 따라가기에 "변형 도중 끊김 → resume" 경로(codex B4·표 A).
- v5 (2026-10-21): 4라운드 codex 5건(major 2)·agy 2건 반영. 실행 소유 기록의 생명주기 — 명령마다 `running` 예약(`spawning`) → `on_spawn` 으로 pid·lstart·ppid(`running`) → 0.log 는 명령마다 바로 덧붙임 → `running` 은 최종 기록에서만 삭제, `start-eval` 은 `spawning`·생존·`ps` 실패를 모두 거부(fail-closed), `on_spawn` 은 시작 평가에서만(codex B1, agy #2) · `halted` 와 `stopped_reason` 을 한 갱신에 적고, 전이표 앞에 우선 규칙(`initial_eval.status ≠ done` 이면 3행)(codex B2) · git 옵션 위치 수정(codex B3) · `review-end` 는 ①~③ 잠금 밖, ④ 만 한 갱신에 재확인 후 적음, 실패 사유는 block 전에 영속화(codex B4) · `review-begin [<파일>]` 로 예약과 변형 대상을 분리, 기존 `mutation`·`mutation_unrestored` 가드, `recheck` 는 `stage == reviewing` 기준, 사람 정리 절차, NOCHANGE+도구 없음은 실제 확인(codex B5, agy #1) · `--patch-file` 은 `git apply --check -p1` 형식 확인·소유권 미검증 명시(codex 구현 정합) · 시험 I10·I13 추가.
- v6 (2026-10-21): 5라운드 codex 4건(major 2)·agy 3건 반영. 전이표 우선 규칙에 `resume_after_cleanup` 뒤 4행 진입과 `done` 확정 전 Worker 진입 금지(codex B1, agy #1) · 실행 소유 기록에 `phase: ended`+`exit`+`survivors` 영속 기록을 더하고 `start-eval` 은 "끝났다는 기록"만 믿는다(직접 pid 죽음은 증거가 아님), 출력은 `goal/0-<k>.out` 에 바로 쓴다, `on_spawn` 의 `ps` 실패는 `lstart: null`(codex B2, agy #2) · `--patch-file` 검사는 `git apply --numstat -p1`(codex B3) · `review-end` 도 `mutation_unrestored` 즉시 거부·예약 동일성 확인·트리 검사 실패 시 `verify: null`(codex B4, agy #3) · `state <HANDOFF.md> del` 호출 형태·USAGE, I 번호 일치(agy #3).
- v7 (2026-10-21): 6라운드 codex 2건(major 1)·agy 2건 반영. 최종 기록은 모든 명령이 `ended`+빈 `survivors` 일 때만 `running` 을 지우고, 생존·확인 불가면 남겨 `start-eval` 가드를 유지(codex B1, agy #1) · 시작 평가는 정상 종료 뒤에도 `group_left` 로 잔류 확인(codex B2) · `start-eval` 의 `done` 확정과 4행 ⑥ 에서 `resume_after_cleanup` 삭제(agy #2) · 복구 예시 호출 형태 수정(codex 표 A).
- 7R (2026-10-21): codex PASS · agy PASS. 새 지적 없음. 11절에 `group_left` 한계 한 줄(codex 확인 불가 메모).
