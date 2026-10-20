# relay `auto` 모드 설계안 — 완료 조건까지 무인 반복

> 2026-10-20 · 상태: v17(구현 반영. 코드 검토 6라운드 지적 2건 수정 완료, 시험 199개. 이 수정분은 외부 검토를 거치지 않았다). 출처: moai-adk 팩토리·goal 루프·레인 감시견 조사(2026-10-20). 이 문서는 설계 기록이다. 확정되면 SKILL.md·rules.md·템플릿·스크립트가 정본이 된다. 변경 이력은 13절.

## 한 줄 요약

relay에 모드 하나(`auto`)를 더한다. 사용자가 승인한 범위 안에서, 명령으로 판정되는 완료 조건이 참이 될 때까지 단위 작업을 사람 입력 없이 반복한다. 끝은 완료 보고다. Worker는 단위마다 만든 격리 워크트리 브랜치에서만 쓴다. 이 세션이 그 브랜치에 커밋하고 공유 브랜치에 `--ff-only`로 합친다. 커밋은 사용자가 계획 단위로 미리 준 자동 승인 범위 안에서만 하고, close는 사용자가 돌아와서 한다. 권한은 지금 있는 것만 쓴다. 승인 창이 뜨면 거기서 멈춘다.

## 0. 전제·제약 (전역 규칙 발췌 — 이 설계는 이것을 바꾸지 않는다)

- 커밋·푸시는 사용자가 명시 요청할 때만 한다. 자동 커밋은 인계 문서 `커밋 정책:` 줄에 `자동 승인: <단위 범위> / 만료: <조건>`이 있을 때, 그 범위 안에서만 한다. 푸시는 자동 승인 대상이 아니다.
- 승인 정책·샌드박스·권한을 완화해 자율성을 얻지 않는다. `bypassPermissions`·`--dangerously-skip-permissions`는 쓰지 않는다. 스킬은 권한 모드·허용 목록을 바꾸지 않고, 바꾸라고 요구하지도 않는다.
- 삭제·파괴적 git·배포·외부 전송·전역 설정 변경은 항상 사전 확인한다. 무인 중에는 그 자리에서 멈춘다.
- 하위 에이전트의 완료 보고는 diff·시험으로 확인한다. 재위임은 완료 기준당 2회까지다.
- 중대한 모호성은 추정으로 풀지 않고 멈춘다. 계획에서 벗어난 결정은 사유를 남긴다.
- 세션 교체는 herdr(`HERDR_ENV=1`)에서만 자동이다. 밖에서는 인계 문서를 쓰고 새 세션 시작을 안내한다.
- 스킬은 Claude Code·Codex 공용이다. 바이너리·훅은 두지 않는다.

## 1. 지키는 것 / 안 하는 것

- 지키는 것: relay의 기존 모드(init·resume·unit·rotate·close)·템플릿·R1~R12는 그대로 둔다. `auto`는 `unit` 반복을 감싸는 겉껍질이다. 단위 하나 = 브리프 1 → Worker 1 → 검수 1 → 커밋 1(R4)도 그대로다. 재위임(완료 기준당 2회)은 기존대로 unit 3단계 안에서 돈다. R2(검증 1회)는 이렇게 지킨다: 조건 명령은 반복마다 `eval-goal.sh`가 한 번만 돌리고, Worker 브리프에는 조건 명령 전체를 돌리지 말고 자기 변경의 대상 시험만 돌리라고 적는다.
- `auto`에서만 다른 것 하나: Worker는 단위마다 만든 격리 워크트리 브랜치(`relay/<plan>/<unit>`)에서 일한다. 공유 트리에는 이 세션만 쓴다(ff 머지·문서). 커밋은 워크트리 안에서 하고 공유 브랜치에는 `git merge --ff-only`로만 들어간다. 그래서 공유 트리 변경의 주인이 분명하고, 다른 세션이 공유 브랜치를 움직였으면 ff가 실패해 저절로 멈춘다. Agent 도구의 `isolation: "worktree"` 매개변수는 쓰지 않는다(`.claude/worktrees/`에 워크트리가 하나 더 생긴다). 워크트리 경로는 `docs/relay/<plan>/<unit>/wt/` 하나다. `auto`에서는 단위 하나가 저장소 하나만 다룬다(R4 "단위 = 커밋 1"과 같다). 여러 저장소를 고치는 계획은 init에서 저장소별 단위로 나눈다. `auto`에서는 `commit-unit.sh`를 쓰지 않는다. 워크트리는 자기 인덱스를 가져 공유 인덱스 오염(R11)이 생기지 않는다. R1의 "다른 저장소를 Worker가 직접 편집"은 `auto`에서 "그 저장소의 워크트리에서 편집"으로 바뀐다.
- 안 하는 것: 리더+레인 멀티세션, 큐 DB, 훅, 점수제 심사, 푸시·PR·원격 머지·브랜치 간 통합 머지(로컬 `--ff-only` 머지만 한다), 사용자 대신 승인, 권한 변경 요구, 외부 모델에게 진행 여부를 맡기는 것, 강제 삭제(`worktree remove --force`·`branch -D`).

## 2. 언제 쓰나

- 쓰는 경우: 완료를 명령으로 판정할 수 있다(테스트·빌드·lint·스크립트의 exit 0). 단위가 2개 이상이다. 사람이 지켜보지 않는다. 사용자가 이 계획에 한해 커밋 자동 승인을 줬다.
- 못 쓰는 일(= 5절 권위 관문과 같은 목록): 명령으로 판정하지 못하는 일(화면 느낌·문서 품질). 삭제·파괴적 git·푸시·배포·외부 전송·전역 설정·`.claude/settings*`·사용자 데이터·데이터 이전·금액·인증·공개 인터페이스 변경. 이런 단위가 섞여 있으면 그 단위에서 멈춘다.

## 3. 흐름

```text
init(auto) → 반복 엔진 등록(1회) → [반복] → 완료 보고(close 대기)

[반복] = 경계 점검(앞) → unit 1~6단계(워크트리 브랜치 커밋 → ff 머지) → 이전 pane 정리 → 조건 평가 → 완료면 통합 검수 → 경계 점검(뒤) → 교체 판단(unit 7단계)
분기: 반복은 언제나 `units[*]` 중 `stage ≠ cleaned`인 단위를 4단계의 복구 분기(git 실제 상태 대조)로 먼저 처리한다(행 상태와 무관). 그 뒤 4단계에서 멈추면(blocked·limit·expired) 5단계만 거쳐 9단계로 간다. 미완료 단위가 0개인 반복은 새 단위를 시작하지 않고 6단계부터다.
```

1. **init(auto)**: 기존 init에 더해 완료 조건 블록(4절)과 경계 블록(5절)을 인계 문서 재개 블록에 적고, `docs/relay/<plan>/goal/state.json`(8절)을 만든다. `커밋 정책:` 줄은 `자동 승인: <범위> / 만료: <조건>` 형식이고 `<범위>`는 `전부`·`U1~U4`·`U1,U3` 중 하나에 `(보정 단위 포함)`을 붙인 것이고, `<조건>`은 `계획 완료`·`중단`·`최대 반복`·`최대 시간`(각각 뒤에 `도달`을 붙여도 된다)을 `·`나 `또는`으로 이은 것 또는 `YYYY-MM-DD HH:MM`(로컬 시각)이다. 다른 값은 거부한다(해석 못 하는 만료를 무기한으로 보지 않는다). init은 모든 단위와 보정 단위가 범위 안이어야 통과하고, 커밋 때 범위 밖 단위는 `expired`로 멈춘다(`eval-goal.sh check`가 해석한다. 해석 불가·빈 값·만료 없음은 거부). 상태표 pathspec 열은 `<저장소>:<경로>`다. 단위 하나의 pathspec은 저장소 하나여야 한다(아니면 init이 단위를 저장소별로 나누라고 거부한다). 검사·명령은 `<경로>`만 떼어 `git -C <저장소>`로 돌린다. 계획 pathspec 합집합에 든 파일은 공유 트리에서 HEAD와 같아야 한다(`git status --porcelain -uall -- <합집합 경로> ':!docs/relay/<plan>'`이 비어 있음. 4단계 검사와 같은 식). 저장소별로 `init_head`(현재 HEAD)·`expected_tip`(처음엔 `init_head`, 단위가 머지될 때마다 그 커밋으로 갱신)·`target_ref`(`git symbolic-ref HEAD`, 분리 HEAD면 거부)를 state.json에 적는다. 아니면 시작하지 않는다(사용자가 먼저 정리한다). pathspec 밖의 변경은 두되 커밋 대상에 넣지 않는다. 조건 명령·검증 명령·Worker 호출 명령 목록과, 이 계획이 만들고 정리할 자산(`docs/relay/<plan>/<unit>/wt/` 워크트리와 `relay/<plan>/<unit>` 브랜치 — 머지 완료·깨끗할 때만 지우고 강제 삭제는 없다)을 사용자에게 보인다. 이 확인이 0절 "삭제 사전 확인"과 closing 3항(scratch 정리)을 이 계획에 한해 미리 받는 것이다. `npm`·`yarn`·`pnpm`·`make`로 시작하는 조건 명령은 package.json·Makefile에서 한 단계 풀어 실제 실행 줄도 함께 보인다. "무인 중 승인 창이 뜨면 멈춘다"는 사실을 함께 확인받는다. 사용자가 그 명령들을 미리 허용할지는 사용자 몫이고 시작 조건이 아니다. 조건·경계·자동 승인을 사용자가 확인한 뒤 시작한다. 이 승인 1회가 유일한 질문 지점이다.
2. **반복 엔진**: Claude Code에서는 `/loop`를 쓴다(프롬프트: `relay auto 다음 반복 <HANDOFF.md 경로>`). 세션에 반복은 하나만 둔다. 등록하는 지점은 init 직후와 resume 첫 턴(12단계의 전이표가 허용할 때), 둘뿐이다(Claude만). 완료·중단·교체 성공 직후에는 `stop`으로 끝낸다. Codex에는 `/loop`가 없다(codex-cli 0.163.0 도움말 기준). Codex 세션은 한 턴 안에서 같은 반복 본문을 순서대로 돈다. 반복 본문은 두 쪽이 같다.
3. **경계 점검(앞)**: 최대 시간·최대 반복(5절). 걸리면 단위 밖 중단(9단계).
4. **unit 1~6단계(워크트리 브랜치 판)**: 단위 시작 때 저장소의 공유 트리에서 두 가지를 본다. `git rev-parse HEAD`가 `expected_tip`과 같다(다르면 init 뒤나 단위 사이에 남의 커밋이 들어온 것). 계획 pathspec **합집합** 파일이 HEAD와 같다(`git status --porcelain -uall -- <합집합 경로> ':!docs/relay/<plan>'` 비어 있음). 하나라도 어긋나면 그 단위를 `blocked`로 적고 9단계로 간다. 통과하면 상태표 행을 `진행`으로 바꾸고 `git worktree add -b relay/<plan>/<unit> <wt> HEAD`로 격리 워크트리 브랜치를 만들고 state.json `units[<unit>]`에 `repo`·`base_head`(= 이때의 HEAD)·`branch`·`wt`·`stage: started`·완료 기준 키를 적는다. **Worker 띄우기**(단위 시작, 재위임, 복구 분기 "Worker부터"에서 pane이 없을 때 공통): herdr codex는 `herdr pane split --cwd <wt>` + `agent start <이 세션이 정한 이름>`, agy는 `cd <wt>`에서 `agy -p … --add-dir <wt>`. 탭에 이미 있는 사용자 pane은 쓰지 않는다. 위임·읽기·대기는 state에 적은 agent 이름으로 한다(pair 2.2의 이름 탐지·2.3의 고정 `codex` 타깃은 쓰지 않는다). 띄운 pane id·agent 이름(agy는 PID·시작 시각)을 `units[<unit>].worker`에 적는다(갱신). 브리프에 네 줄을 더한다: 작업 디렉터리 = 워크트리 경로, 공유 트리와 `docs/relay/` 금지, 조건 명령 전체를 돌리지 말고 대상 시험만, 로그는 `<wt>/.relay-logs/`(워크트리 안. Worker의 쓰기 범위 안이라 승인 창이 뜨지 않는다. 커밋 제외). 시험 캐시는 보통 gitignore 대상이라 두어도 된다(무시 파일은 `git worktree remove`를 막지 않는다. git 2.56.0에서 직접 확인). **워크트리 정체성**(워크트리에서 git 명령을 하나라도 돌리기 전에 매번): `worktree list`에 등록돼 있고, `rev-parse --show-toplevel`이 실제 경로와 같고, `--git-common-dir`이 저장소 것과 같고, 현재 브랜치가 `relay/<plan>/<unit>`이며, 경로에 심볼릭 링크가 없어야 한다. 아니면 아무것도 하지 않고 `blocked`(워크트리 자리가 빈 폴더로 바뀌면 `reset`이 공유 인덱스를 지우기 때문이다. 코드 검토에서 재현). **3단계 Advisor 확인**: 먼저 `git -C <wt> reset -q HEAD`로 인덱스를 비운다(Worker가 직접 `git add`한 것을 무효화). `git -C <wt> status --porcelain -uall`에서 `.relay-logs/`를 뺀 전체를 본다. pathspec 밖 파일이나 권위 관문 파일이 있으면 즉시 `blocked`(파일 목록 이월). 없으면 `git -C <wt> add -A -- <경로> ':!.relay-logs'`로 새 파일까지 인덱스에 올리고 `git -C <wt> diff --cached HEAD`로 본다(미추적 신규 파일·바이너리 포함). 재위임은 3단계 안에서 2회까지, 같은 워크트리에서 이어 한다. 재위임 전에 `reset -q HEAD`로 인덱스만 비운다(작업 파일은 그대로). **4단계 독립 검수**: 같은 cached diff + 신규 시험. 통과하면 `stage: reviewed`. 지적이 있으면 수정은 Worker 재위임으로 한다(같은 완료 기준 키의 2회 카운터를 쓴다. 넘으면 `blocked`). 재위임 전 `reset -q HEAD`, 수정 뒤 3단계 상태 검사·`add -A`·cached diff를 다시 만들어 델타 재검수한다. **5단계 커밋**(워크트리 안): ① 재검사(최대 시간·자동 승인 만료·권위 관문·`reset -q HEAD` 뒤 `git -C <wt> status --porcelain -uall`에서 `.relay-logs/`를 뺀 전부가 pathspec 안) ② `git -C <wt> add -A -- <경로> ':!.relay-logs'` ③ staged diff가 비어 있으면 커밋을 만들지 않는다(검증된 무변경 단위. 기록은 ④ 통과 뒤에 한다). 비어 있지 않으면 워크트리 HEAD가 `base_head`인지 확인하고 `stage: committing`을 먼저 적은 뒤 `git -C <wt> commit`(단위 메시지) → `stage: committed`, `commit` 기록(복구는 `committing`·`committed` 표시가 있고 부모가 `base_head`인 커밋만 자기 것으로 받는다). 잠금을 풀고 git을 돌린 뒤 다시 잠가 기록할 때는 `stage`·`commit`뿐 아니라 단위의 정체(`repo`·`base_head`·`branch`·`wt`)와 저장소 설정(`repos[slug].path`·`target_ref`)이 그대로인지도 비교한다. 하나라도 바뀌었으면 기록하지 않고 `blocked`(recover로 확인) ④ 무변경이든 아니든 공유 트리에서 확인한다: `git symbolic-ref HEAD`가 `target_ref`와 같다(분리 HEAD·다른 브랜치면 `blocked`), `git rev-parse HEAD`가 `base_head`(= `expected_tip`)와 같다(다른 세션이 공유 브랜치를 움직였으면 `blocked`. pathspec 밖 커밋이어도 같다. 무인 중 공유 브랜치는 이 세션만 움직인다는 전제다), `git status --porcelain -uall -- <합집합 경로> ':!docs/relay/<plan>'`이 비어 있다. 커밋이 있으면 들어올 새 파일 목록을 `git diff --name-only --diff-filter=A <base_head> relay/<plan>/<unit>`으로 구해, 비어 있지 않을 때만 `git ls-files -o -i --exclude-standard -- <그 파일들>`이 비어 있는지 본다(겹치는 무시 파일이 있으면 `blocked`). 무변경이면 여기서 `commit: 없음(변경 없음)`을 적고 REPORT에 사유를 적는다. 커밋이 있으면 ff 전 스냅샷(`for-each-ref` 전체 ref와 분리 HEAD 워크트리의 HEAD)을 뜬 뒤 잠근 채 `stage: merging`과 `merge_intent={path, target_ref, base, commit, before=스냅샷}`을 먼저 적고(ff 뒤 기록에 실패해도 복구가 같은 스냅샷으로 미확정 머지를 알아보게), `git merge --ff-only --no-autostash --no-overwrite-ignore relay/<plan>/<unit>`. 거부되면 예약을 거두고(`committed`) 공유 트리를 건드리지 않은 채 `blocked`다. 워크트리 브랜치의 커밋은 그대로 남는다. 머지 직전에 `for-each-ref refs/heads`를 스냅샷하고, 머지 뒤 재검증한다: `git rev-parse <target_ref> == <commit>`이면 성공이다(그 사이 HEAD가 바뀌었어도). 아니면 **어떤 ref도 되돌리지 않는다**. 작업 트리·인덱스도 건드리지 않는다(검사와 `read-tree` 사이에 생긴 파일을 덮어쓰는 경쟁, 그리고 체크아웃되지 않은 ref를 확인한 뒤 `update-ref` 사이에 누가 그 브랜치를 체크아웃해 작업 트리가 어긋나는 경쟁을 코드 검토가 재현했다). 스냅샷과 비교해 `<commit>`을 새로 포함하게 된 대상 외 ref(`for-each-ref --contains`, 전체 ref. 후속 커밋이 붙어 tip이 `<commit>`이 아니어도 잡힌다. 스냅샷 oid가 그대로이거나 그 oid가 이미 `<commit>`을 품고 있던 ref — 미리 만든 백업과 그 독립 전진 — 는 제외)와 그렇게 된 분리 HEAD를 `units[<unit>].ff_misapplied={ref[], detached[], base, cm}`에 남기고 `blocked`다(사람이 `git reset`·`git switch`로 정리. 이 기록이 있으면 merge·recover를 거부한다). `merging`인 단위는 merge·cleanup을 거부하고 recover만 받는다: 저장소 설정(경로·대상 브랜치)이 예약과 다르거나 예약에 스냅샷이 없으면 판정하지 않고 예약을 둔 채 멈춘다. 대상에 들어간 예약은 완료 확정까지 보존하고, 완료 확정(`expected_tip`·`stage`·예약 삭제)은 잠금 안에서 단위 정체·저장소 설정·예약을 다시 비교한 한 번의 갱신으로 한다. ff 전에 끊긴 예약만 따로 거둔다. `for-each-ref --contains` 조회가 실패하면 빈 결과로 보지 않고 예약을 둔 채 멈춘다. `<commit>`이 `target_ref`의 조상이면 머지된 것으로 확정(`expected_tip` 갱신 뒤 cleanup), 예약 스냅샷 대비 대상 외 ref나 분리 HEAD가 `<commit>`을 새로 포함하게 됐으면 `ff_misapplied`·`blocked`, 둘 다 아니면 ff 전에 끊긴 것이므로 한 번의 갱신으로 `committed`로 되돌려 merge부터. 머지·복구 전에는 `git diff --name-only <base_head> <commit>` 전체에 pathspec 밖·권위 관문 검사를 한다(이미 만들어진 커밋이 검사를 우회하지 못하게). 통과하면 `expected_tip`을 `<commit>`으로(무변경이면 그대로), 상태표 행을 `완료`(커밋 열·종료 시각)로 적고 `stage: merged` ⑤ 정리: 그 단위의 Worker pane(이 세션이 띄운 것만)을 닫고, `<wt>/.relay-logs/`가 있으면 `REPORT.md`는 `docs/relay/<plan>/<unit>/REPORT.md`로, 나머지는 `docs/relay/<plan>/<unit>/logs/`로 옮기고(이름이 겹치면 번호를 붙인다. 원본·목적지·부모에 심볼릭 링크가 있으면 옮기지 않고 `logs_error` 기록), `git worktree remove <wt>`(미추적 비무시 파일이 남아 있으면 실패한다. 그런 파일은 ①에서 이미 걸렸을 것이다), 성공하면 `git branch -d relay/<plan>/<unit>`(머지됐으니 성공한다. 무변경이면 tip == base_head라 역시 성공). 둘 다 성공해야 `stage: cleaned`. 제거에 실패하면 `branch -d`도 하지 않고 `stage: merged`로 두고 이월에 적는다. 6단계 인계 갱신은 공유 트리의 `docs/relay/<plan>/`에 이 세션이 쓴다. `resume`은 반복 본문에 없다. **복구 분기**(매 반복 시작과 재개 때, `stage ≠ cleaned`인 단위마다. `stage`는 참고값이고 git 실제 상태가 기준이다): 먼저 브랜치가 있고 tip ≠ `base_head`인데 `units[<unit>].commit`이 비어 있으면 `commit = tip`으로 채운다(커밋 직후·기록 전 중단). 그 다음: `commit`이 해시이고 `target_ref`의 조상이거나 `commit: 없음(변경 없음)`이면 머지된 단위다(완료 확정과 자산 정리는 HEAD가 `target_ref`일 때만 한다) → 남은 Worker pane·로그·워크트리·브랜치를 ⑤대로 정리하고, 행이 미완료면 `완료`·커밋·종료 시각을 적고, `expected_tip`을 맞춘다. 브랜치가 있고 tip ≠ `base_head`이고 조상이 아니면 → ④부터. 브랜치가 있고 tip == `base_head`이면 → `reviewed`면 5단계부터, 아니면 Worker부터(pane이 없으면 새로 띄운다). 브랜치도 `commit`도 없고 행이 미완료면 → 단위 시작부터. 사용자가 `blocked` 행을 `미착수`로 되돌린 단위는 다시 쓰지 않는다: Worker pane을 닫고(전이표 4행에서) `.relay-logs/`를 옮긴 뒤 워크트리를 제거하고(실패하면 사용자가 직접 정리할 때까지 멈춘다), 브랜치는 미머지 커밋이 있어 `branch -d`가 안 되므로 지우지 않고 `relay/<plan>/<unit>.discarded-<n>`으로 이름을 바꿔 보존한다(지울지는 close에서 사용자가 정한다). discard 때 `.relay-logs/`는 `REPORT.md`까지 `logs/`로 간다. 그 뒤 현재 HEAD 기준으로 처음부터 한다.
5. **이전 pane 정리**: 교체로 넘어온 세션이면 이전 세션 pane이 아직 열려 있을 수 있다(resume 3단계가 `working`이면 닫지 않으므로). unit 6단계 뒤에 한 번 더 보고 `idle`이면 닫는다. 규칙은 resume 3단계와 같다.
6. **조건 평가**: `scripts/eval-goal.sh run <HANDOFF.md>`가 조건 블록의 `cmd:` 줄을 순서대로 실행한다(실행 환경은 4절, 공유 트리). 기록 순서는 로그(`docs/relay/<plan>/goal/<반복번호>.log`) → `goal/eval.md` 한 줄(임시 파일+rename) → 인계 문서 한 줄 → state.json `last_eval`이다. 명령은 자기 세션 묶음(`start_new_session`)으로 띄운다. 인계 문서에는 최신 결과 한 줄만 둔다(R12). exit 126·127이 나오면 나머지 `cmd:`를 돌리지 않고 즉시 `judge-fail`로 중단한다(9단계). 재사용: `last_eval`에 대상 저장소별 트리 키를 적어 둔다. 트리 키 = 임시 인덱스(`GIT_INDEX_FILE`)에 `git read-tree HEAD` → `git add -A -- . ':!docs/relay/<plan>'` → `git rm -r --cached -q --ignore-unmatch docs/relay/<plan>` → `git write-tree`가 낸 트리 해시. 계획 폴더가 gitignore 대상이면 제외 pathspec이 `add`를 exit 1로 끝낸다(git 2.56.0에서 직접 확인: "paths are ignored"). 그때는 제외 없이 `add -A`한다(무시 대상이라 어차피 올라가지 않는다). 계획 폴더 제외는 인계 문서가 든 기본 저장소에만 적용한다(보조 저장소의 같은 경로는 실제 작업 파일이다). 추적·미추적·바이너리·삭제를 한 번에 잡고, 이 실행의 문서는 뺀다. 모든 대상 저장소에서 트리 키가 같을 때만 재실행 없이 `(이전 실행 · 그 뒤 변경 없음)`으로 재사용한다. 상태표에 미완료(`미착수`·`진행`·`보류`·`blocked`) 단위가 0개일 때의 평가는 재사용하지 않고 항상 새로 실행한다(완료 보고로 갈 수 있는 평가라서. 통합 검수 전에 실행되므로 이 기준으로 정한다). 완료 판정은 두 가지가 동시에 참일 때다: 미완료 단위 0개, 그리고 모든 `cmd:`가 exit 0. 단위가 남았는데 `cmd:`가 전부 통과해도 완료가 아니다.
7. **보정 단위**: 단위가 전부 `완료`인데 `cmd:`가 실패하면 계획자가 실패 원인을 확인한다. 수정 대상 파일이 모두 계획 pathspec 합집합 안에 있을 때만 보정 단위를 상태표 끝에 더한다. 수정 파일이 두 저장소에 걸치면 저장소별로 보정 단위를 나눈다(단위당 저장소 1개). 이름은 `U<마지막 원래 단위>-fix<회차>-<저장소 slug>`(저장소 하나면 slug 생략). `fix_units`에 회차·단위명·완료 기준 키를 적는다. 그 뒤 9단계(경계 점검 뒤)·11단계(교체 판단)를 거쳐 다음 반복으로 간다(8단계와 같다). 2회차까지 쓴 뒤 6단계나 8단계가 또 실패하면 단위를 더하지 않고 `fix-cap`으로 9단계에 간다. 파일을 특정하지 못하거나 pathspec 밖이거나 새 기능·목표가 필요하면 범위 확장이므로 `scope`로 중단한다(plan 8절 `❓` 상황). 보정은 계획당 최대 2회차다(한 회차에 저장소별 단위 여러 개가 생길 수 있다). 보정 단위의 재위임 횟수는 완료 기준 키로 센다. 키는 실패한 `cmd:` 줄이거나, 통합 검수 지적이면 `integration`이다. 같은 키의 보정 단위들은 한 카운터(2회)를 나눠 쓴다. 상태표 12열 기본값: 단위=위 이름, 내용=실패 요약 한 줄, 파일·pathspec=수정 대상 파일, 선행=직전 행 단위, 모델·검수=직전 단위와 같게, 병렬=`✘`, 가중치=빈칸, 상태=`미착수`, 종료 시각·커밋=빈칸.
8. **통합 검수**: 조건 평가가 완료 판정이면 반복 안에서 통합 검수를 돌린다. 범위는 단위별 검수가 못 본 것만이다: 단위 간 정합·중복·빠진 연결. 첫 회는 저장소별 `git diff <init_head> HEAD -- <계획 pathspec>`, 이후는 같은 검수자에게 바뀐 부분만(plan 5절과 같다). 결과는 `docs/relay/<plan>/goal/INTEGRATION_REVIEW.md`(판정·지적 표·검수자 종류·검수 시점 저장소별 HEAD)에 쓰고 state.json `integration`(저장소별 기준 HEAD·미해소 지적 번호·검수자 종류)이 가리킨다. 보정 직후 세션이 교체되면 새 세션은 같은 종류의 검수자(새 컨텍스트)에게 이 파일과 기준 HEAD 이후의 diff만 준다. 지적 0이면 `/loop`를 `stop`하고 완료 보고로 간다. 지적이 있으면 보정 단위 규칙(7단계)으로 보정 단위를 더하고 경계 점검(뒤)으로 이어간다. 보정 뒤 반복에서는 조건 평가를 새로 통과하고 델타 재검수까지 지적 0이어야 완료다.
9. **경계 점검(뒤)와 중단**: 최대 시간·최대 반복·보정 상한·`blocked`(5절). 조건 평가와 통합 검수를 모두 통과해 남은 단위가 없으면 완료 보고가 우선한다. 중단 기록은 `stopped_reason` 하나로 모은다. 단위 실행 중 멈춤은 그 단위 행을 `blocked`로 적고 `blocked:<단위>`. 단위 밖 멈춤은 행을 바꾸지 않고 `limit:iterations`·`limit:duration`·`expired`(자동 승인 만료)·`judge-fail`(126·127)·`scope`·`fix-cap`. 교체 불확실은 `rotate-uncertain`, 교체 생성 실패는 `rotate-failed`(11단계), Worker를 멈추지 못한 재개는 `worker-alive`(12단계), 제한 시간 뒤 프로세스 잔존은 `timeout-survivors`(4절). `stop done`·`stop rotate`는 남은 `중단:` 줄을 지우고, `blocked` 행이 있으면 `stop done`을 거부한다. 이 값들일 때만 재개 블록에 `중단: <사유>` 한 줄을 같이 쓴다. 정상 교체 `rotate`와 완료 `done`은 `stopped_reason`에만 적고 `중단:` 줄은 쓰지 않는다. status.sh도 `rotate`·`done`은 중단으로 표시하지 않는다. 커밋 직전 재검사(4단계 ①)에서 `limit:duration`·`expired`로 멈추면 그 단위 행은 `진행`으로 두고 `stage`는 `reviewed`로 남는다. 재개 때 복구 분기가 5단계부터 잇는다. 멈추는 모든 경로에서 `/loop`를 `stop`한다. 빈 `stopped_reason`은 "반복 중"만 뜻한다.
10. **완료 보고**: plan 완료 화면을 쓰고 남은 일에 `close 대기`를 적는다. `stopped_reason`은 `done`. 단위별 커밋은 자동 승인 범위 안에서 이미 끝나 있다. `close`는 사용자가 돌아와 결과를 확인한 뒤 기존 절차대로 항목마다 확인하며 한다. 임시 허용·add-dir 제거·남은 워크트리·브랜치(`.discarded-<n>` 포함) 정리가 남아 있으면 종료 완료로 적지 않는다. close 체크리스트(closing.md)에 "이 계획의 `relay/<plan>/*` 브랜치와 워크트리" 항목을 더한다.
11. **교체 판단과 교체**: 판단은 R7 그대로다(직전 단위의 Worker나 검수가 opus급이었거나 이 세션에서 2단위를 마쳤을 때). herdr 안에서는 같은 턴 안에서 이 순서로 한다. `stopped_reason`에 `rotate`를 적는다 → rotate.sh 실행 → 결과별 처리. rotate.sh는 종료 코드로 단계를 구분한다(9절): exit 0 = 새 세션이 프롬프트를 받고 활동을 시작함, exit 1 = 새 세션을 만들기 전에 실패(pane 분할·agent start), exit 4 = 새 세션은 떴는데 프롬프트 전송이나 대기에 실패. exit 4로 나가기 전에 rotate.sh 자신이 `stopped_reason`을 `rotate-uncertain`으로 바꾸고 재개 블록에 `중단: rotate-uncertain` 줄을 쓰고 새 pane에 `esc`를 보낸다(새 세션이 뒤늦게 `rotate`를 읽고 시작하는 일을 막고, 전이표가 3행으로 간다). exit 0이면 `/loop`를 `stop`하고 "교체 완료" 한 줄을 남기고 턴을 끝낸다. exit 1이면 rotate.sh를 한 번 더 시도한다. 또 exit 1이거나 0·1·4가 아닌 종료 코드(기존 exit 2: 인계 문서 없음·jq 없음·옵션 오류·연번 줄 없음)면 재시도 없이 `stopped_reason`을 `rotate-failed`로 적고 `중단:` 줄을 쓰고 `/loop`를 `stop`한다(이 세션은 이미 R7의 2단위를 마쳤으므로 단위를 더 하지 않는다). 사람이 새 세션을 연다(전이표 3·4행). 어느 실패 경로든 미리 적어 둔 `rotate`는 그대로 두지 않고 위 값으로 바꾼다. exit 4면 이 세션도 `/loop`를 `stop`한다. 사람이 두 세션 상태를 보고 정리한다(12단계). 세션 연번은 rotate.sh가 agent start 성공 뒤, 프롬프트 전송 전에 +1 하고 state.json에 `rotated_serial: true`를 남긴다. 이 동작은 인계 문서에 `모드: auto`가 있을 때만이다. 일반 모드의 rotate.sh는 지금 그대로다(전송 뒤 갱신, state.json 없음). 새 세션의 첫 턴은 종류별로 다르다. Claude: 12단계 전이표대로 state.json·재개 블록·상태표만 읽고, `stopped_reason`이 정확히 `rotate`일 때만 비우고(`rotated_serial`도 지운다), 상태표를 내고, 반복 엔진을 등록한 뒤 바로 턴을 끝낸다. 단위 작업은 첫 깨우기에서 시작한다. 그래야 rotate.sh의 `--wait`가 제때 돌아온다. Codex: 같은 읽기·확인·상태표 출력 뒤 그 턴 안에서 바로 반복 본문에 들어간다. rotate.sh는 `ROTATE_KIND`로 프롬프트 문구를 가르고, Codex는 턴 종료가 아니라 활동 시작(`--until working --until blocked`)만 기다린다. herdr 밖에서는 Claude·Codex 모두 교체 조건에서 인계 문서를 갱신하고 `stopped_reason`을 `rotate`로 적은 뒤 멈추고 사용자에게 새 세션 시작을 안내한다. 무인 실행은 거기서 끝난다.
12. **resume 전이표**(새 세션·중단 뒤·비정상 종료 뒤 공통. 사람이 resume를 부른 것 자체가 재개 승인이다). 연번 갱신은 실제로 등록·진입하는 행(1·2·4행)에서만 한다: `rotated_serial`이 있으면 연번을 읽기만 하고 표시를 지운다. 없으면 +1 한다. 안내만 하는 행(3·5행)은 연번과 표시를 건드리지 않는다.

   | 행 | `stopped_reason` | 재개 블록 `중단:` 줄 또는 상태표 `blocked` 행 | resume가 하는 일 |
   |---|---|---|---|
   | 1 | `rotate` | 없음 | 비우고 등록(Claude)·진입(Codex) |
   | 2 | `""`(비정상 종료: 세션 사망·429·`/loop` 만료·Codex 턴 종료. 사용자가 3행을 거쳐 정리했으면 `stopped_reason`이 `""`여도 4행으로 간다: 3행이 `resume_after_cleanup: true`를 state.json에 남긴다) | 없음 | `units[*].worker`를 본다. herdr agent가 `working`이면 5절의 `esc`·`idle` 절차, agy는 기록한 PID·시작 시각이 일치하는 프로세스가 살아 있으면 끝날 때까지 기다린다(최대 `Worker 제한`). 멈추지 않으면 등록하지 않고 그 단위를 `blocked`, `stopped_reason`을 `worker-alive`로 적고 `중단:` 줄을 쓴다(사람이 Worker를 끝낸다). 멈췄으면 그 Worker pane을 닫고(4단계가 새로 띄운다) 상태표와 `git status --short`를 보이고 등록·진입 |
   | 3 | 값과 무관 | 하나라도 있음 | 등록하지 않는다. 사유·상태표·단위별 `stage`와 워크트리(더티 여부)·살아 있는 세션(`herdr agent list`)을 보이고 state.json에 `resume_after_cleanup: true`를 적는다. 사용자가 재개 블록(`커밋 정책:` 만료 조건·경계)을 고치고, 되돌릴 `blocked` 행을 `미착수`로 바꾸고(그 단위의 더티 워크트리는 보존·폐기 중 택해 정리), `중단:` 줄을 지우면 다음 resume이 4행이다 |
   | 4 | 값과 무관(3행을 거쳐 정리된 뒤) | 둘 다 없음(사용자가 정리함) | 같은 턴에서 이 순서로: ① 2행과 같은 Worker 생존 확인(멈추지 않으면 2행처럼 `worker-alive`로 되돌아간다) ② `미착수`로 되돌린 단위의 Worker pane 닫기, `.relay-logs/` 옮기기, 워크트리 제거(실패하면 여기서 멈추고 `blocked`·`중단:` 줄을 되살린다. 사용자가 직접 정리한다), 브랜치 이름 보존(`.discarded-<n>`), `units[<unit>]`과 `redelegations` 키 초기화 ③ `HEAD ≠ expected_tip`인 저장소가 있으면 외부 커밋을 받아들일지 사용자에게 확인하고, 받아들이면 `expected_tip`을 현재 HEAD로 갱신(거절하면 멈춘다) ④ 경계 블록 재검증 → state.json 상한값 갱신(`started_at`·`iterations` 유지), `stopped_reason` 비움 ⑤ status.sh ⑥ 등록·진입 |
   | 5 | `done` | 없음 | 등록하지 않는다. 완료 상태표만 보인다(close 대기) |

   재개 뒤 단위 작업은 4단계 규칙으로 돌아간다. 되돌리지 않은 단위는 복구 분기가 이어 할 단계를 정한다. 공유 트리 pathspec은 깨끗해야 한다는 규칙은 재개 때도 같다.

## 4. 완료 조건 문법 (인계 문서 재개 블록)

```text
완료 조건:
  cmd: npm test -- --runInBand           # exit 0 이어야 한다
  cmd: ./scripts/lint-changed.sh         # 복합 명령은 스크립트 파일로
  timeout: 10m                           # cmd 하나의 제한 시간. 생략하면 10m
```

- `cmd:` 한 줄은 단순 명령 하나다. 따옴표 밖의 `#`부터 줄 끝까지 주석이다(`shlex.split(..., comments=True)`. 따옴표 안 `#`는 인자로 남는다. 2026-10-20 실행으로 확인). 셸 메타문자(`;` `|` `&` `` ` `` `$` `(` `)` `<` `>`)·글로빙 문자(`*` `?` `[`)·환경변수 접두사(`FOO=bar cmd`)가 있으면 거부한다. 필요하면 스크립트 파일로 감싼다. `eval-goal.sh check`가 init에서 검사한다. 검사와 실행 모두 인계 문서가 속한 저장소 루트(공유 트리)에서 한다.
- 실행 환경: 작업 디렉터리는 저장소 루트. 셸을 거치지 않고 인자 배열로 직접 실행한다. 환경 변수는 세션 것을 그대로 쓴다. 종료 코드는 그 명령의 것이다. 파이프가 없으니 가려지는 실패도 없다.
- 첫 단어 검사: `./`나 `/`로 시작하면 루트 기준으로 파일이 있고 실행 비트가 있어야 한다. 그 밖은 `command -v`로 풀려야 한다. 안 되면 init에서 거부한다. 실행 결과가 exit 126·127이면 판정 명령 자체의 오류다. 즉시 `judge-fail`로 중단한다. 그 밖의 0이 아닌 종료 코드는 조건 미달이다.
- 외부 전송·삭제·푸시·권한 상승 패턴(`curl` `wget` `ssh` `scp` `git push` `rm -r` `sudo`)이 들어 있으면 거부한다. `rm`은 argv 기준으로 본다: 인자 어디에 있든 `rm` 뒤 `--` 앞의 모든 옵션에서 `r`·`R`·`--recursive`(줄임 포함)를 찾는다. 이 검사는 문자열 검사라 스크립트 안의 동작까지 보지 못한다. 그래서 조건 명령은 init에서 사용자가 목록(한 단계 푼 실행 줄 포함)을 보고 확인한 것만 쓴다. 문자열 검사는 그 위의 안전망이다.
- 제한 시간을 넘긴 `cmd:`는 실패로 적고 직접 띄운 프로세스만 끝낸다. 그 뒤 같은 프로세스 묶음(pgid)에 남은 프로세스가 있는지 먼저 신호 0(존재 확인만, 아무것도 끝내지 않음)으로 보고, 있으면 `ps -A -o pid=,pgid=`로 번호를 얻어 끝내지 않고 `timeout-survivors`로 중단한다(전역 규칙: 기록하지 않은 프로세스는 죽이지 않는다. 이름 패턴은 쓰지 않는다. ps가 실패하면 "확인 못 함"으로 역시 중단). 스스로 새 세션을 만든 손자 프로세스는 찾지 못한다.
- 상태표 전부 완료 조건은 적지 않아도 항상 붙는다(3절 6단계). 모델이 스스로 채점하는 조건은 두지 않는다.
- 조건은 빠른 것으로 둔다(대상 패키지 테스트, 바뀐 파일 lint). 전체 스위트·통합 테스트는 2~3단위마다 1회다(R2).

## 5. 경계 (인계 문서 재개 블록)

```text
경계:
  최대 반복: 12       # 기본은 단위 수 × 2. 보정 단위 반복도 센다
  최대 시간: 4h       # state.json started_at(시간대 포함) 기준 벽시계
  Worker 제한: 30m    # Worker 호출 1회의 대기 상한(herdr --timeout · agy --print-timeout)
```

- 최대 시간은 반복 앞·커밋 직전·반복 뒤에서 본다. 뒤에서만 보면 멈춘 명령·Worker·승인 창이 4시간을 무력화한다. `cmd:`는 4절 제한 시간, Worker는 `Worker 제한`으로 끊는다. 승인 창은 끊지 못한다. 승인 창이 뜨면 무인 실행은 거기서 멈춘 것이고, 사람이 답하면 그 반복을 이어간다. 이어갈 때 커밋 직전 재검사(3절 4단계)가 만료를 잡는다.
- 정체 경계는 두지 않는다. 재위임이 unit 안에서 2회로 끝나므로 모든 반복은 단위를 `완료`하거나 중단한다. 보정 단위가 계속 실패하는 경우는 보정 상한(2)과 최대 반복이 막는다.
- 권위 관문(2절 목록과 같다): 단위 브리프에 들어 있으면 그 단위를 시작하지 않고 `blocked`다. 작업 중 Worker 보고나 워크트리 diff에서 그 영역에 닿은 것이 드러나도 같은 처리다. 이때 커밋·머지하지 않는다. 닿은 파일 목록을 이월에 적고 워크트리는 그대로 둔다. 6절 사다리로 넘지 않는다.
- 다중 세션 흔적: 공유 브랜치는 무인 중에 이 세션만 움직인다는 전제다. 단위 시작과 ff 머지 직전에 `HEAD == expected_tip`, `symbolic-ref HEAD == target_ref`, 계획 pathspec 합집합이 깨끗함을 확인하고, 하나라도 어긋나면 머지하지 않고 `blocked`다. 머지 뒤에는 대상 ref가 실제로 전진했는지 재검증하고, 틀렸으면 되돌리지 않고 기록만 남긴 채 멈춘다(3절 4단계 ④). 검사와 머지 사이의 틈은 `--ff-only`가 막는다: 그 사이에 누가 공유 브랜치를 움직이면 ff가 거부되고, 머지가 바꿀 파일을 건드렸으면 git이 덮어쓰기를 거부한다. 머지가 바꾸지 않는 파일을 그 틈에 남이 고친 것은 머지에 섞이지 않고 공유 트리에 미커밋으로 남으며, 계획 pathspec 합집합 안이면 다음 단위 시작 검사에서 걸린다(합집합 밖이면 커밋 대상이 아니다). pathspec 밖 미커밋 변경은 커밋 대상이 아니므로 흔적으로 보지 않는다. 이 실행이 만드는 문서(`docs/relay/<plan>/`)도 커밋 대상에 넣지 않는다. 문서를 커밋할지는 close에서 사용자가 정한다. 워크트리 안 변경이 pathspec 밖으로 번지면 3단계 상태 검사와 커밋 전 검사(4단계 ①)가 잡는다. R11의 사람 확인 단계는 이 검사들로 대신한다.
- Worker 실패·중단: 재위임 2회(기존). 횟수는 state.json에 완료 기준 키별로 적는다. 반복·세션 교체로 초기화되지 않는다. 넘으면 그 단위 행을 `blocked`로 적는다. Worker pane이 죽거나 `Worker 제한`을 넘긴 것도 실패 1회로 센다. 제한을 넘긴 Worker는 먼저 멈춘다: herdr에서는 그 pane에 `esc`를 보내고 최대 2분 안에 `idle`이 되는지 본다. `idle`이 되면 같은 워크트리에서 재위임하고, 안 되면 그 단위를 `blocked`로 적고 중단한다(쓰기 주체 둘 금지). 같은 절차를 전이표 `""` 행의 재개 때도 쓴다(세션이 죽어도 Worker pane은 살아 있을 수 있다). agy는 `--print-timeout`이 프로세스를 끝낸다. 재위임 브리프에는 "워크트리에 이전 시도의 수정이 남아 있다. `git status`·`git diff HEAD`로 먼저 본다(agy는 이 세션이 그 목록을 브리프에 적어 준다)"를 적는다. 2회를 넘겨 멈출 때 워크트리는 되돌리지 않고 파일 목록을 이월에 적는다.
- 세션 자체가 죽거나 429·빈 응답이 이어지면 반복은 그냥 멈춘다. 자동 복구는 없다(11절). 재개는 12단계 전이표의 `""` 행이다.

## 6. 사람 없을 때 판단 사다리

단위 중 판단이 필요하면 순서대로 간다.

1. 디스크 증거(REPORT.md·로그·diff)가 답을 주면 그대로 따른다.
2. `docs/relay/<plan>/goal/decisions.md`에 같은 질문의 기록이 있으면 따른다.
3. 범위 안이고 되돌릴 수 있고 0절 규칙에 닿지 않는 설계·구현 판단이면 계획자(이 세션)가 정한다. 질문·판단·근거를 decisions.md에 한 줄로 적는다. 이것은 plan 3절의 계획자 역할 그대로다.
4. 그 밖은 `blocked`를 적고 멈춘다. 질문과 필요한 결정을 인계 문서 이월에 한 줄로 적는다.

권위 관문과 범위 밖 변경은 사다리 대상이 아니다. 항상 4다. 외부 모델(codex·agy)의 답으로 진행 여부를 정하지 않는다.

## 7. 권한

- 지금 있는 권한으로만 돈다. 스킬은 권한 모드·허용 목록을 바꾸지 않고 바꾸라고 요구하지도 않는다. Claude Code와 Codex 모두 각자의 기존 승인 정책 그대로다.
- 무인 중에 승인 창이 뜨면 거기서 선다. 그 반복은 사람이 답할 때까지 멈춘 것이다. state.json에는 마지막 반복 번호만 남고, 사람이 답하면 그 자리에서 이어간다. 최대 시간은 그동안에도 흐른다.
- 사용자가 스스로 계획 기간 한정 허용을 넣기로 했다면 기존 R1·closing 2항 절차를 따른다. 인계 문서 "종료 시 제거"에 적고 close에서 제거를 확인한다. 스킬은 이것을 권하지 않고 시작 조건으로 삼지도 않는다.
- Worker가 agy면 셸을 못 쓴다. 시험은 이 세션이 워크트리에서 돌린다(pair 3절).

## 8. 인계 문서·상태 파일 변경

- templates/HANDOFF.md 재개 블록에 3줄: `모드: auto`, `완료 조건:`(블록), `경계:`(블록). `커밋 정책:` 줄은 기존 한 줄 형식을 쓴다: `커밋 정책: 자동 승인: <단위 범위> / 만료: <조건>`(status.sh 54행이 이 줄을 읽는다). 별도 줄을 만들지 않는다.
- 재개 블록 아래 두 줄: `최근 조건 평가: <반복번호> <시각> <통과/실패 수> → goal/eval.md`, 그리고 실제 중단 시에만 `중단: <사유>`. 통합 검수 결과는 `goal/INTEGRATION_REVIEW.md`.
- 상태표 상태 값에 `blocked` 추가(미착수/진행/완료/보류/blocked). 보정 단위는 상태표 끝에 더한다(열 기본값은 3절 7단계).
- 단위 폴더 `docs/relay/<plan>/<unit>/wt/`가 격리 워크트리다. Worker 로그는 작업 중 `<wt>/.relay-logs/`, 정리 때 `docs/relay/<plan>/<unit>/logs/`로 옮긴다. 브랜치는 `relay/<plan>/<unit>`. ff 머지와 정리 뒤 워크트리·브랜치를 지운다. 남아 있으면 그 단위의 `stage`가 `cleaned`가 아닌 것이다.
- `docs/relay/<plan>/goal/state.json`(신규, 기계가 쓰는 유일한 상태): `started_at`(시간대 포함 ISO 8601), `max_iterations`·`max_duration`·`worker_timeout`(init 때 경계 블록에서 복사, 12단계 재개 때 갱신), `iterations`, `last_eval`(반복번호·시각·결과·저장소별 트리 키), `fix_units`, `redelegations`(완료 기준 키별: 단위·`cmd:` 줄·`integration`), `integration`(기준 HEAD·미해소 지적 번호·검수자 종류), `repos`(저장소별 `init_head`·`expected_tip`·`target_ref`), `units`(단위별 `repo`·`base_head`·`branch`·`wt`·`stage`(started/reviewed/committed/merged/cleaned)·`commit`(해시 또는 `없음(변경 없음)`)·`worker`(pane·agent 또는 PID·시작 시각)), `fix_units`(회차·단위명·완료 기준 키), `stopped_reason`(3절 9단계 값), `resume_after_cleanup`(3행이 남김), `rotated_serial`(rotate.sh가 연번을 올렸음), 단위별 `merge_intent`(머지 예약)·`ff_misapplied`·`logs_error`. 쓰기는 `goal/.lock`에 `flock`을 잡고 저장 직전에 다시 읽어 바꾸는 키·줄만 적용한다(rotate.sh의 연번 갱신과 edit_file도 같은 잠금). git·조건 명령을 돌리는 하위 명령(`init`·`run`·`clean`·`unit`·`fix`·`redeleg`)은 `goal/.driver`를 명령 내내 쥔다(기다리지 않고 거부): 한 계획을 두 프로세스가 동시에 운전해 서로의 예약을 지우는 것을 막는다. 이 잠금 fd는 git 자식에게만 물려준다(조건 명령에는 안 준다). 그래서 스크립트가 git 도중 죽어도 git이 끝날 때까지 잠금이 산다. `stop`·`clear-stop`·`state`는 상태만 고치므로 이 잠금을 잡지 않는다(훅이 불러도 교착 없음). 잠금은 read-modify-write 구간에만 잡고 git 명령·조건 명령 실행 중에는 풀어 둔다(git 훅이나 명령이 eval-goal.sh를 다시 부르면 교착한다. 코드 검토에서 재현). 패턴: 잠금 안에서 의도 기록 → 해제 → git → 다시 잠그고 재읽기·검증 → 결과 기록. 잠금을 쥔 채 git·조건 명령을 실행하면 코드가 오류를 낸다. 다른 프로세스가 잠금을 `RELAY_LOCK_WAIT`초(기본 30) 넘게 쥐면 기다리지 않고 `blocked`다. 상태표는 12열이어야 하고 `\|`를 인식하며 대상 셀만 바꾼다. pathspec 열은 쉼표로 나누고 항목마다 shlex로 푼다(따옴표 없는 공백은 거부). resume는 이 파일과 재개 블록·상태표만 읽는다(기존 resume 1단계와 같다).

## 9. 파일 변경 목록

| 파일 | 변경 |
|---|---|
| relay/SKILL.md | 모드 표에 `auto` 1행. `## auto` 절에 3절 흐름(반복 본문 12단계, 전이표). resume 절에 `모드: auto`면 12단계 전이표 적용. resume 4단계 연번은 `auto`에서 `rotated_serial`이 있으면 읽기만, 없으면 +1(다른 모드는 그대로) |
| relay/references/rules.md | R13 조건 문법·실행 환경·거부 기준·제한 시간. R14 경계·워크트리 브랜치 커밋·`--ff-only` 머지 전제(`HEAD == base_head`·`target_ref`)·복구 분기·보정 단위·재위임 키·Worker 중단. R15 판단 사다리·권위 관문·중단 값·전이표 |
| relay/templates/HANDOFF.md | 8절 |
| relay/templates/BRIEF.md | `auto`일 때 쓰는 줄 4개: 작업 디렉터리 = 워크트리 경로, 공유 트리·`docs/relay/` 금지, 조건 명령 전체 금지·대상 시험만, 로그는 `<wt>/.relay-logs/` |
| relay/scripts/eval-goal.sh (신규) | `check`(따옴표 밖 주석·shlex 분할·메타문자·글로빙·접두사·금지 패턴·첫 단어·실행 비트), `run`(인자 배열 실행·제한 시간·로그·eval.md·인계 문서 한 줄·state.json·상태표 완료 판정·트리 키 재사용 판정·미완료 0개면 새로·126/127 즉시 중단), `treekey`(임시 인덱스 read-tree HEAD → add -A 에서 docs 제외 → write-tree), `clean`(`repo:path` 파싱, pathspec 깨끗함·`HEAD == base_head`·`target_ref` 검사·무시 파일 충돌), `unit`(워크트리 브랜치 생성·행 `진행`·상태 검사(`-uall`, `.relay-logs` 제외)·커밋·무변경 처리·ff 머지·머지 뒤 재검증·`expected_tip` 갱신·로그 이동·정리·stage 기록·복구 분기 판정·되돌린 단위 브랜치 이름 보존). bash + python3, 외부 의존 없음 |
| relay/scripts/rotate.sh | `--print-prompt`(herdr 밖에서도 재개 프롬프트만 출력). 인계 문서에 `모드: auto`가 있을 때만: 연번 갱신(42행)을 agent start 성공 뒤·프롬프트 전송 전으로 옮기고 state.json에 `rotated_serial` 기록, 종료 코드 1 = 생성 전 실패·4 = 생성 뒤 전송·대기 실패(나가기 전에 `stopped_reason`=`rotate-uncertain`·`중단:` 줄 기록 + 새 pane에 `esc`). 일반 모드는 지금 그대로. 공통 수정 3개(기존 버그): 32행의 존재 확인을 `select(.name == $n and .pane_id == $pane)`으로 고친다(지금은 다른 탭의 동명 에이전트가 있으면 폴백을 건너뛰고 프롬프트가 엉뚱한 에이전트로 간다). 이름 충돌이면 27~30행 재시도 없이 바로 폴백한다. `agent start`가 끝내 실패하면 만든 pane을 `herdr pane close`로 닫고 exit 1. 33행 폴백 때 `name` 변수를 새 이름으로 갱신(지금은 38행 prompt가 옛 이름으로 가서 실패한다). `모드: auto`면 프롬프트에 종류별 지시(Claude: 전이표대로 등록만 하고 턴 종료 / Codex: 읽고 바로 반복 본문). `ROTATE_KIND=codex`면 38행 `--wait`를 `--until working --until blocked`로 |
| relay/scripts/status.sh | `blocked` 단위를 미완료로 집계·표시(27행). `$(dirname HANDOFF)/goal/state.json`을 읽어 경계 잔여(반복·시간)와 `중단:` 사유 1줄(`rotate`·`done`은 중단으로 표시하지 않음). 미완료 단위가 있으면 진행률 상한 99%(38행 빈 가중치 0.0 문제) |
| pair/SKILL.md | 2.1에 "호출자가 작업 디렉터리와 agent 이름을 지정하면 기존 pane을 재사용하지 않고 그 경로로 새 pane을 띄우며, 2.2 이름 붙이기를 건너뛰고 2.3은 그 이름을 타깃으로 쓰며, 끝나면 호출자가 그 pane을 닫는다" 한 줄(`auto`가 쓴다). 3절 agy 호출에 `cd <워크트리> && agy … --add-dir <워크트리>` 예와 PID·시작 시각 기록 |
| relay/references/closing.md | 항목 추가: 이 계획의 `relay/<plan>/*` 브랜치(`.discarded-<n>` 포함)·워크트리 정리 여부 |
| go/SKILL.md | 경로 표 `긴 작업` 행에 "완료 조건이 명령이면 relay `auto`". `재개` 행에 "`모드: auto`면 전이표대로" |

## 10. 확인 방법

| 단위 | 입력 | 기대 결과 |
|---|---|---|
| eval-goal.sh check | 주석 포함 정상 2종(따옴표 안 `#` 포함), 메타문자·글로빙·환경변수 접두사·금지 패턴·없는 명령·실행 비트 없는 `./x` 6종 | 2종 통과(인자 보존), 6종 거부 메시지 |
| eval-goal.sh run | 임시 인계 문서로 exit 0·1·127·제한 시간 초과 | eval.md 3행(127은 즉시 중단이라 뒤 cmd 미실행), 로그, 127은 `stopped_reason`=`judge-fail` + `중단:` 줄, 초과는 실패. 인계 문서·goal/ 밖 추적 파일 변경 0 |
| treekey·재사용 | 통과 직후 같은 트리 / `docs/relay/<plan>/`만 바뀜(추적·미추적 각각) / 수정 중 파일 내용만 더 바뀜 / 미추적 파일 내용만 바뀜 / 바이너리 내용만 바뀜 / 미완료 단위 0개 | 재사용 / 재사용·재사용 / 재실행 / 재실행 / 재실행 / 재실행 |
| 완료 판정 | 단위 미완료 + cmd 통과 / 단위 전부 완료 + cmd 실패(pathspec 안) / 같은 상황(pathspec 밖) / 3번째 보정 | 미완료 / 보정 단위 추가 / `scope` 중단 / `fix-cap` 중단 |
| 재위임 키 | 같은 `cmd:`의 fix1에서 2회 실패 뒤 fix2 / 통합 지적 fix1·fix2 | 3번째 재위임 거부 → `blocked` / `integration` 키로 같은 결과 |
| 경계 | 가짜 state.json으로 최대 반복·최대 시간(앞 점검) / 최대 시간(커밋 직전) | 중단, `stopped_reason`·`중단:` 기록, 행 상태 변경 없음 / 중단, 단위 행 `진행` 유지(`stage` reviewed), 커밋 0 |
| 워크트리·흔적 | 단위 시작 때 계획 합집합 안 다른 단위 파일 더티 / 단위 시작 때 pathspec 파일 더티 / Worker 작업 중 공유 브랜치에 남이 커밋(pathspec 밖 포함) / 공유 트리가 같은 OID의 다른 브랜치로 전환 / 머지가 바꿀 파일을 밖에서 수정 / 들어올 새 파일과 겹치는 무시 파일 / pathspec 밖 파일만 더티 / 워크트리 변경이 pathspec 밖으로 번짐 / 신규 파일·바이너리 포함 단위 / Worker가 아무것도 안 바꿈 | `blocked` / `blocked` / `HEAD ≠ base_head` → `blocked`, 워크트리 커밋 보존 / `target_ref` 불일치 → `blocked` / 머지 거부 → `blocked` / 사전 검사 `blocked` / 정상 진행 / 3단계·커밋 전 `blocked` / 검수·커밋·머지에 모두 포함 / 커밋 없이 행 `완료`·`없음(변경 없음)` |
| 단위 복구 | git 동작 직후·state 기록 전에 중단: 커밋 뒤·ff 뒤·행 완료 뒤 정리 전·워크트리 제거 뒤 브랜치 삭제 전 / 무변경 완료 뒤 정리 전 / `reviewed`에서 중단 | 실제 상태 대조로 ④·정리·행 완료 기록 / 정리 / 5단계부터. 같은 커밋이 두 번 들어가지 않고 자산이 남지 않음 |
| 외부 커밋 | init 직후 단위 시작 전 / 두 단위 사이 / 무변경 단위 ④ 시점 | 각각 `HEAD ≠ expected_tip` → `blocked` |
| 머지 뒤 재검증 | 체크아웃되지 않은 다른 브랜치가 전진 / 체크아웃된 브랜치가 전진 / 분리 HEAD로 전환된 뒤 ff | 세 경우 모두 되돌리지 않는다(`update-ref`·`read-tree` 호출 없음): `ff_misapplied`·`blocked`, 작업 트리·인덱스·대상 브랜치 불변, recover는 사람에게 넘김 |
| 머지 예약 | ff 성공 뒤 기록 단계가 잠금을 못 얻음 / 잘못 전진한 ff + 잠금 실패 / `merging`인 단위에 merge·cleanup | `merging`·`merge_intent` 보존, recover → 완료·`expected_tip` 갱신·cleanup / recover가 `ff_misapplied`를 적고 `blocked` / 거부(recover로) |
| 정체성 재확인 | 커밋 중 훅이 state의 `base_head`를 바꿈 / ff 뒤 다른 프로세스가 `repos[slug].target_ref`를 바꿈 | exit 1, `stage: committing` 유지, `commit` 미기록 / 기록하지 않고 `merging` 유지, recover는 "대상 브랜치 설정이 예약과 다르다"로 멈춤 |
| 운전 잠금 | 다른 명령이 `goal/.driver`를 쥔 채 `unit … recover` / 그때 `state set` / 스크립트가 git 도중 죽음 | 기다리지 않고 거부(`goal/.driver`) / 된다 / git 자식이 사는 동안 잠겨 있고 끝나면 풀린다 |
| 예약 판정 보류 | `--contains` 조회가 실패(exit 128) / 예약이 대상에 들어간 뒤 완료 확정 전 git 검사 도중 `target_ref`를 바꿈 | 예약을 두고 멈춤, 다음 recover가 잘못 전진을 잡음 / 완료를 적지 않고 예약 보존, 다음 recover는 설정 불일치로 거부 |
| 예약 판정 보류 | recover의 포함 검사 도중 다른 프로세스가 `target_ref`를 바꿈 / `repos[slug].path`가 다른 clone으로 바뀜 / HEAD가 `refs/heads` 밖 ref를 가리킨 채 ff / 미리 `<commit>`에 있던 백업이 독립 전진 / 예약에 스냅샷 없음 | 예약을 두고 멈춤 / 같음 / 그 ref를 `ff_misapplied`로 적고 멈춤 / 전진으로 보지 않고 `merge`부터 / 예약을 두고 멈춤 |
| 예약 스냅샷 | 잘못 전진한 ref에 후속 커밋이 붙은 뒤 잠금 실패 / ff 전부터 `<commit>`에 있던 브랜치 + ff 거부 + 예약 해제 잠금 실패 | recover가 그 ref(tip ≠ `<commit>`)를 `ff_misapplied`로 적고 멈춤 / recover가 그 브랜치를 전진으로 보지 않고 `merge`부터 |
| 워크트리 제거 | 무시 파일(`__pycache__`)만 남음 / `.relay-logs/` 남음 / 미추적 비무시 파일 남음 | 제거 성공 / 옮긴 뒤 성공 / ①에서 먼저 `blocked` |
| 독립 검수 반복 | 지적 → 재위임 2회 뒤 또 지적 | `blocked` |
| pane 수명 | 탭에 사용자 codex pane이 있는 상태로 시작 / U1 정리 뒤 U2 시작 / 세션 사망 뒤 Worker 생존 상태로 resume | 사용자 pane은 쓰지 않고 `--cwd <wt>` 새 pane, state의 이름으로 위임 / U1 pane 닫힘, U2는 새 워크트리 pane / `esc`·`idle` 뒤 닫고 새 pane |
| treekey | docs가 무시 대상인 저장소 / docs가 없는 저장소 | 둘 다 정상 해시 |
| 교체 실패 | rotate.sh exit 1 두 번 / exit 2 / agent start 실패 뒤 pane 잔존 여부 | `rotate-failed`·`중단:` 줄, 단위 추가 실행 없음 / 재시도 없이 같은 결과 / pane 0개 |
| 권위 관문 | 브리프에 `git push` 포함 / 워크트리 diff가 `.claude/settings.json`에 닿음 | 단위 시작 전 `blocked` / 적용 없이 `blocked`, 파일 목록 이월 |
| 전이표 | `rotate`(+`rotated_serial`) / `""`(Worker 생존, 멈춤) / `""`(Worker 생존, 안 멈춤) / `""`인데 `blocked` 행만 있음 / `blocked:U2`+`중단:` 줄 → 그 상태로 resume 두 번 / 둘 다 정리(+`rotated_serial`, 되돌린 단위 있음) / `rotate-uncertain`(+`중단:` 줄) / `done` | 등록·연번 유지 / `esc`·`idle` 뒤 pane 닫고 등록·연번 +1 / `worker-alive` 중단 / 3행(미등록) / 미등록·사유, 연번·표시 불변 / 생존 확인 → 정리(브랜치 이름 보존) → 상한 갱신·카운터 초기화 → status.sh → 등록·연번 유지 / 미등록·세션 목록 / 미등록·완료 표 |
| 통합 검수 | 지적 1건 → 보정 → 델타 재검수 0건 / 지적 직후 교체 → 새 세션 | 그제야 완료 보고 / INTEGRATION_REVIEW.md와 기준 HEAD 이후 diff로 델타 재검수 |
| status.sh | `blocked` 단위 1개 / 전부 완료 + `중단:` 줄 / `stopped_reason`=`rotate` / 보정 단위 미완료 + 가중치 지정 | 미완료 집계·`blocked 1` / `계획 중단: <사유>` / 중단 표시 없음 / 진행률 99% 이하 |
| rotate.sh | `--print-prompt`로 `모드: auto` 인계 문서(herdr 밖), `ROTATE_KIND` claude·codex / 연번 시점 / exit 코드 / exit 4 경로 | 종류별 문구 / 전송 전 1회 +1·`rotated_serial` / 1·4 구분 / `rotate-uncertain` 기록·`esc` 전송 |
| 문서 | 저장소 루트 `scripts/check.sh` | 통과. `/loop`는 금칙어 목록에 없다 |
| 시험 호출(herdr 안, Claude) | 작은 저장소, 단위 2개(하나는 신규 파일 포함), `cmd: <test>` | 교체 1회 포함해 완료 보고까지. 푸시 0, 설정 파일 변경 0, 승인 창 0, rotate.sh exit 0, 연번 정확히 +1, 워크트리·브랜치·Worker pane 0개 잔존. Worker 제한 초과 1회를 넣어 `esc` 뒤 `idle`·재위임 동작 확인 |
| 시험 호출(herdr 안, Codex) | 같은 저장소 | 한 턴 안 반복으로 2단위 완료 또는 R7에서 `ROTATE_KIND=codex` 교체(rotate.sh `--until working`으로 즉시 반환) |
| 시험 호출(herdr 밖) | 같은 저장소 | R7 교체 조건에서 인계 문서 갱신·`rotate` 기록 후 멈추고 안내. 수동 새 세션 resume에서 연번 +1 |

## 11. 보장하지 못하는 것

- herdr 밖에서는 세션 교체가 없다. 교체 조건에서 멈춘다.
- Codex 세션은 `/loop`가 없다(codex-cli 0.163.0 도움말 기준). 한 턴 안 반복만 된다. 턴이 끝나면 사람이 다시 시킨다(전이표 `""` 행).
- `/loop`의 자가 페이스는 이 환경의 ScheduleWakeup 도구 정의 기준으로 깨우기 간격 60초~3,600초이고 `stop: true`로 끝난다. 7일 뒤 만료와 세션 resume 시 백그라운드 감시 소멸은 moai 문서 기준이고 직접 확인하지 않았다. 만료되면 멈춘 것으로 본다. 다시 켜는 것은 사람이 한다.
- herdr 에이전트 상태 값은 idle·working·blocked·done·unknown 다섯 가지이고 `herdr agent prompt`·`herdr agent wait` 둘 다 `--until`을 반복 지정할 수 있다(CLI 도움말에서 직접 확인). `--timeout`은 대기 상한일 뿐 Worker 실행을 끝내지 않는다. 그래서 5절이 `esc` 뒤 `idle` 확인을 둔다. `esc`가 실제로 Worker의 쓰기를 멈추는지, agy `--print-timeout`이 프로세스를 끝내는지는 10절 시험 호출에서 확인한다. 상태 판정의 정확도는 herdr에 달려 있다.
- 조건 명령의 부작용은 문자열 검사와 한 단계 풀기로 다 막지 못한다. 하위 스크립트 안의 삭제·푸시·외부 전송은 보지 않는다. 사용자가 init에서 확인한 명령만 쓴다는 전제에 기댄다. 이것이 0절 "사전 확인"의 이 설계에서의 형태다. 스크립트 내부 전수 검사는 범위 밖으로 둔다.
- 워크트리 격리는 공유 트리의 변경 소유권을 분명히 하지만, Worker가 워크트리 밖 경로를 절대 경로로 건드리는 것까지 막지는 못한다. 브리프 금지와 ff 머지 직전 깨끗함 검사가 그 안전망이다. 워크트리 브랜치 커밋의 작성자는 이 세션의 git 설정을 따른다.
- git 훅이 띄운 오래 사는 프로세스가 `goal/.driver` fd를 물려받으면 그것이 끝날 때까지 운전 명령이 거부된다(메시지는 "다른 eval-goal 명령이 실행 중"). 닫히는 쪽으로 실패하므로 두지만, 그런 훅은 두지 않는 것이 맞다.
- 머지 뒤 재검증에 실패하면(대상 브랜치가 아닌 곳이 전진) 자동 복구가 없다. 잘못 전진한 ref는 사람이 정리할 때까지 그대로 남고, 그 계획은 멈춘다. 자동 되돌림은 확인과 `update-ref` 사이의 체크아웃 경쟁 때문에 뺐다(v14).
- 토큰 비용 상한은 없다. 최대 반복·최대 시간이 대신한다.
- 429·세션 사망의 자동 복구는 없다. 멈추고 사람이 resume한다.
- 외부 자원(DB·네트워크)이 필요한 조건 명령은 그 자원이 죽으면 실패로 보여 보정 단위를 소모한다.

## 12. 정해야 할 것

1. 모드 이름: `auto` / `until-done` / 직접 지정.
2. 보정 단위 상한 2개가 맞는지(재위임 2회와 같은 수로 맞춤).
3. 최대 반복 기본값 단위 수 × 2, Worker 제한 30m, Worker 중단 대기 2분이 맞는지.

(결정됨) 자동 커밋: `auto`에서는 `커밋 정책:` 줄의 자동 승인이 필수. 이유: "확인 후"면 첫 단위 5단계에서 멈추고, 단위당 커밋 1개(R4)도 깨진다.
(결정됨) 권한: 기존 권한으로만 돈다. 승인 창이 뜨면 멈춘다. 허용 추가는 시작 조건이 아니다.
(결정됨) 정체 경계는 두지 않는다. 재위임이 unit 안에서 끝나 완료 수가 안 느는 반복이 생기지 않는다.
(결정됨) 단위 하나는 저장소 하나다. 여러 저장소는 단위를 나눈다(R4).
(결정됨) 무인 중 공유 브랜치는 이 세션만 움직인다. 남의 커밋이 들어오면 pathspec과 무관하게 멈춘다(rebase로 넘기지 않는다).
(결정됨) Worker는 격리 워크트리 브랜치에서만 쓰고 공유 브랜치에는 `--ff-only`로만 합친다. 이유: 공유 트리 변경의 소유권 없이는 R11의 사람 확인을 기계로 대신할 수 없고, 패치 적용 방식은 미추적 파일·바이너리·적용 중 중단을 다루지 못한다.

## 13. 변경 이력

- v17 (2026-10-20): 코드 검토 6라운드(codex) 2건 반영(시험 199개). `--contains` 조회 실패를 빈 결과로 바꾸지 않고 멈춤(B1). 대상에 들어간 예약은 완료 확정(finish)까지 보존, 확정과 예약 삭제를 같은 갱신에서(B2). 이 두 수정은 외부 검토 없이 자체 시험만 거쳤다.
- v16 (2026-10-20): 코드 검토 5라운드(codex) 6건 반영(시험 195개). `goal/.driver` fd를 git 자식에게 물려줘 스크립트가 죽어도 git이 끝날 때까지 잠금 유지(B1). 예약 해제·완료 확정을 잠금 안 정체·설정 재검사 + 한 번의 갱신으로(B2). 예약에 저장소 경로 보존, 다르면 보류(B3). 스냅샷·포함 검사를 전체 ref로(B4). 이전 oid가 이미 `<commit>`을 품던 ref의 독립 전진은 제외(B5). 스냅샷 없는 예약은 판정 보류(B6).
- v15 (2026-10-20): 코드 검토 4라운드(codex) 4건 반영(시험 186개). 계획 운전 잠금 `goal/.driver`(두 프로세스의 머지·recover 교차 방지, B1). 머지 예약에 ff 전 스냅샷 보존, 전진 판정은 "`<commit>`을 새로 포함하게 된 대상 외 ref"(후속 커밋이 붙어도 잡고, 미리 있던 브랜치는 제외. B2·B3). 정체성 비교에 저장소 설정(`path`·`target_ref`) 포함, recover는 예약과 다른 대상 브랜치면 멈춤(B4). 예약 해제는 한 번의 갱신으로.
- v14 (2026-10-20): 코드 검토 3라운드(codex) 잔여 5건 반영(시험 177개). 자동 ref 되돌림 전부 삭제(체크아웃 경쟁 B1) → 항상 `ff_misapplied`·멈춤. ff 전에 `merging`·`merge_intent` 예약, `merging`은 merge·cleanup 거부·recover가 git 상태로 확정(B2). 다시 잠글 때 단위 정체(`repo`·`base_head`·`branch`·`wt`) 비교(B4). rotate.sh 연번 예약(`claim`)을 잠금 아래 읽기·+1·쓰기 한 번에(B3, 동시 호출 시험). 시험 보강(B5).
- v13 (2026-10-20): 잔여 4건 수정 반영(시험 168개). 되돌림은 ref만·체크아웃된 브랜치는 되돌리지 않음, 잠금은 git 실행 중 해제·대기 상한, 만료 문법에 `도달` 허용, 생존 프로세스는 신호 0으로 확인, rotate.sh 연번 갱신도 잠금 안(perl 제거). 10절 머지 경쟁 기대 결과 정정.
- v12 (2026-10-20): 코드 검토 2라운드(codex) 결과. 11건 해소 확인, 잔여 4건 정정: 되돌림은 ref만(체크아웃되지 않은 ref에 한해 CAS, 작업 트리 불변), 잠금은 git 실행 중 해제, 만료 문법 닫힌 집합, rotate.sh 연번 갱신도 잠금 안. 시험 보강(자식 PID 포함 검사·eval.md 원자성).
- v11 (2026-10-20): 구현 반영. eval-goal.sh 1차 코드 검토(codex, 깨끗한 맥락) 15건 — critical 2건은 리드가 직접 재현 — 을 수정한 결과를 설계에 맞춰 적었다: 워크트리 정체성 검사, `committing` 단계와 출처 불명 커밋 거부, 머지·복구 전 `base..commit` 전체 검사, ref 스냅샷 기반 되돌림과 `ff_misapplied`, 완료 확정은 `target_ref` 기준, 자동 승인 범위 문법, `rm` argv 검사, `timeout-survivors`, `goal/.lock`, 기본 저장소만 제외, pathspec 따옴표 규칙, 상태표 `\|`·12열, `stop done` 규칙, 기록 순서, 로그 이동·링크 거부. 시험 150개.
- v10 (2026-10-20): 8라운드. codex 새 문제 3건·미해소 1건·새 지적 2건, agy 새 문제 3건·미해소 1건·새 지적 12건 반영. 복구 진입을 행 상태가 아니라 `stage ≠ cleaned`로, 매 반복 시작에 먼저(codex A1·agy A-B4). 보정 단위 이름에 회차·저장소 slug, `fix_units`에 키, `fix-cap` 시점(codex A-B5·agy B6). 되돌림에 `read-tree -u -m`·분리 HEAD 처리(codex A-B2·agy B2). 무변경 기록을 ④ 통과 뒤로(codex A-B6·agy A-1). ①·4행에 `.relay-logs/` 제외·이동(codex B1·agy A-B1·B5·B7). 외부 커밋 뒤 재개는 사용자 확인 뒤 `expected_tip` 갱신(codex B2). 복구 분기 맨 앞에서 `commit = tip` 복원(agy B3). 독립 검수 지적 수정도 재위임 2회 한도(agy B4). 되돌린 단위 워크트리 제거 실패 시 멈춤(agy B5). 복구·재위임 때 Worker pane 새로 띄움(agy B8). 3·5단계 시작에 `reset -q HEAD`(agy B9). close에 브랜치·워크트리 항목, closing.md 변경(agy B10). 10절 앞 점검·커밋 직전 구분(agy B11). init 검사 `-uall`·docs 제외 통일(agy B12). rotate.sh 32행 동명 에이전트 버그(기존)·즉시 폴백(agy B1). `resume_after_cleanup`으로 `""`+정리 뒤 4행 진입(agy A-4). 직접 확인: 무시 파일은 `git worktree remove`를 막지 않음(git 2.56.0). 반영하지 않음: codex A-5(일곱 번째, 같은 이유).
- 8라운드 종료 사유: 1라운드 36건 → 8라운드 16건으로 줄었지만 0이 되지 않았다. 남은 지적은 전부 앞선 수정의 2차 결과(복구 순서·틈새 경쟁·이름 규칙)이고, 두 검토자 모두 핵심(`eval-goal.sh`·auto용 rotate/status 동작·복구 전이)은 "실행 검증 전에는 확인 불가"로 판정했다. 다음 단계는 문서 검토가 아니라 `eval-goal.sh` 구현과 10절 시험이다.
- v9 (2026-10-20): 7라운드. codex 미해소 4건·새 문제 2건·새 지적 2건, agy 미해소 2건·새 문제 1건·새 지적 10건 반영. 단위 시작 검사를 계획 pathspec 합집합으로(codex A-B3). 복구 분기를 `commit`·조상 여부·자산 잔존으로 재정의, 행 `완료` 기록을 ④ 직후로(codex A1·agy A-B4·B1). 보정 단위 저장소별 분할·회차 상한·`integration` 기준 HEAD 저장소별(codex A-B5·agy B10). 4행 순서: 생존 확인 → 정리 → state 갱신 → status.sh → 등록, 못 멈추면 `worker-alive`(codex A-B6·agy B5·B10). 머지 뒤 대상 ref 재검증·자기 전진 CAS 되돌림(codex A-B2). 무변경 단위도 ④ 검사(codex A-B6new). `expected_tip`으로 단위 사이 외부 커밋 감지(codex B1). rotate.sh 비정상 종료 전부 처리·`rotate` 값 되돌림·pane 누수·이름 폴백 수정(codex B2·agy B7). Worker 로그는 `<wt>/.relay-logs/`에 두고 커밋 제외·정리 때 이동(agy A-B1). 7단계도 9·11단계 경유(agy B3). 전이표 3행은 값과 무관(agy B4). 단위 시작 때 행 `진행`(agy B6). `-uall`·지적 수정 전 `reset`(agy B8). 더티면 `branch -d` 생략·`merged` 유지(agy B9). 되돌린 단위 브랜치는 `.discarded-<n>`으로 보존(agy A-B7). 무시 파일 검사 입력 = 추가 파일 목록(agy B2). 반영하지 않음: codex A-5(여섯 번째, 같은 이유).
- v8 (2026-10-20): 6라운드. codex 미해소 6건·새 문제 1건·새 지적 7건, agy 미해소 2건·새 문제 1건·새 지적 12건 반영. Worker 로그를 `docs/relay/<plan>/<unit>/logs/`로(워크트리 깨끗함 보장)(codex B1·B7·agy B1). treekey는 `add -A -- . ':!docs/…'` + `--ignore-unmatch`(codex B3·agy B2). 3단계 시작·커밋 전 전체 상태 검사, 재위임 전 `reset HEAD`, 커밋 직전 `add -A` 재실행(agy B3). 복구 분기를 git 실제 상태로, `stage` `reviewed` 추가(codex A1·B3·agy B4·B5). 연번 갱신은 1·2·4행에서만(agy A-B5·B6). 되돌린 단위는 워크트리·브랜치 정리 뒤 새로, `""` 재개 때 Worker pane 닫기(agy B7·codex A-B6). 단위당 저장소 1개(codex A-B5·agy A-B6·B8). ff 전제 `HEAD == base_head` + `target_ref`(agy B9·codex B2). `--no-autostash --no-overwrite-ignore` + 무시 파일 충돌 검사(codex B1). exit 1은 재시도 1회 뒤 `rotate-failed`(codex B4). init 승인에 워크트리·브랜치 정리 포함(codex B5). 무변경 단위 처리(codex B6). `init_head` 기준 통합 검수(agy B10). 문구 정리: 안 하는 것·패치 참조·"3행"(codex B7·agy B11·B12). ff 틈의 남의 미커밋 수정 설명 정정(codex A-B3). agy PID·시작 시각 기록, state 이름으로 위임(codex A-B6·A-B4). 반영하지 않음: codex A-5(다섯 번째, 같은 이유).
- v7 (2026-10-20): 5라운드. codex 미해소 1건(A-5 제외)·새 문제 2건·새 지적 7건, agy 새 문제 2건·새 지적 11건 반영. 패치 적용을 버리고 워크트리 브랜치 커밋 + `--ff-only` 머지로 전환: 워크트리는 ff 뒤 깨끗해져 제거 가능, 신규 파일·바이너리는 커밋에 포함, `stage`(started/committed/merged/cleaned)로 중단 복구, 검사~머지 틈은 ff가 막음, `commit-unit.sh` 미사용(codex B3 미해소·B1·B2·B3 새·agy A5·B1·B2·B5). Worker pane은 단위마다 새로 띄우고 정리 때 닫음, 사용자 pane 미사용(codex B4·agy B3). 다중 저장소: `repo:path` 파싱·저장소별 워크트리(codex B5·agy B6). 세션 사망 뒤 Worker 생존 확인(codex B6). Worker 로그 위치(codex B7). rotate.sh 새 동작은 `모드: auto`에서만, exit 4면 `중단:` 줄도 기록(agy B4·B7). 전이표: 연번 규칙 공통화·`blocked` 행만 남은 경우·카운터 초기화·stage별 복구(codex A3·agy B9). 분기 명시: 멈추면 6~8 생략, 미완료 0개면 6단계부터, "커밋부터" 재개(agy B8). 자동 승인 범위에 보정 단위 포함(agy B10). BRIEF에 R2 줄·로그 줄, Agent `isolation` 미사용 명시(agy B11). 트리 키 임시 인덱스 초기화 명시(codex 확인 불가 항목). 반영하지 않음: codex A-5(네 번째, 같은 이유).
- v6 (2026-10-20): 4라운드. codex 미해소 2건·새 문제 1건·새 지적 4건, agy 새 문제 3건·새 지적 9건 반영. 반영하지 않음: codex A-5(세 번째, 같은 이유). Worker 격리 워크트리 + 패치 적용 + pathspec 깨끗함 검사로 변경 소유권 확보, baseline_status 삭제(codex B-3 미해소·B1·agy A5·B2·B6). resume 전이표 6행으로 등록 조건 모순 해소, 수동 새 세션 연번 +1·`rotated_serial`(codex B-1 새 문제·minor3·agy A3·A2·B1·B3). 트리 키 = 임시 인덱스 write-tree(바이너리·추적 문서 포함)(codex B5·minor4). 재사용 금지 기준 = 미완료 0개 평가(agy B7). `중단:` 줄은 실제 중단에만, status.sh 표시(agy B4). rotate.sh가 exit 4 전에 `rotate-uncertain` 기록·`esc`, 새 세션은 정확히 `rotate`일 때만(agy B5). 재개 때 경계 재검증·상한 갱신(codex B2). 커밋 직전 중단 시 단위 행 `진행`·이월 한 줄(agy B8). 126/127 즉시 중단·10절 기대 결과 정정(agy B9). 11절에 `prompt --until` 확인·워크트리 한계 추가.
- v5 (2026-10-20): 3라운드. codex 미해소 2건·새 문제 1건·새 지적 6건, agy 새 문제 2건·새 지적 9건 반영. 반영하지 않음 1건: codex A-5(하위 스크립트 내부 부작용 전수 확인) — 설계로 막을 수 없는 한계라 11절에 범위 밖으로 명시. rotate.sh 종료 코드 1/4 구분, exit 4면 두 세션 다 멈춤(codex B1). Codex 첫 턴은 반복 본문 진입, Claude만 등록·종료(codex B2·agy#1·#2). 연번은 rotate.sh 한 곳에서 전송 전 갱신(agy#3). 모든 중단 경로가 `stopped_reason`을 씀(codex B1 미해소·agy#2). 통합 지적 키 `integration`, INTEGRATION_REVIEW.md·state.json `integration`(codex B3·B4·agy#4). 내용 해시(codex B5·agy#8). 따옴표 밖 `#`만 주석, 실행 확인(codex B6). baseline에 blob 해시(codex B3 새 문제·agy#6 — v6에서 워크트리 방식으로 대체). 중단 뒤 resume 때 baseline 갱신(agy#5 — v6에서 대체). 보정 단위 12열 기본값(agy#7). state.json에 상한값(agy#9). R2 해석(codex A18).
- v4 (2026-10-20): 2라운드. codex 미해소 4건·새 문제 2건·새 지적 3건, agy 새 지적 12건 반영(agy 1라운드 16건은 전부 해소 확인). 통합 검수를 반복 안으로, 델타 재검수까지 0건이어야 완료(agy#1·codex B2). rotate.sh 성공 뒤 `/loop` stop, 실패면 유지, 새 세션 첫 턴은 등록만, Codex는 `--until working`(agy#2). 단위 행 `blocked`와 단위 밖 중단 구분(agy#3). 재사용 판정·마지막 평가는 새로(agy#4·codex A18). agy Worker는 셸 불가 대응(agy#5). 재위임은 unit 안, 정체 경계 삭제(agy#6). `#` 주석·shlex·글로빙·실행 비트·루트 실행(agy#7). `커밋 정책:` 한 줄 형식(agy#8). status.sh가 state.json 읽기, 진행률 99% 상한(agy#9). 뒤 점검에 최대 시간, 완료 우선(agy#10). 보정 단위 판정 주체·관문 사후 적발 처리(agy#11). 도식 문구·이전 pane 정리 단계(agy#12). 조건 명령 한 단계 풀어 보이기(codex A5 일부). 커밋 직전 재검사(codex A9). Worker 제한 초과 시 `esc`·`idle` 확인(codex A11). 재위임 키를 완료 기준으로(codex A13). rotate.sh `--print-prompt`(codex A20). 중단 뒤 resume는 등록 안 함(codex B1). baseline·docs 제외(codex B3).
- v3 (2026-10-20): codex(GPT-6-Astra high) 독립 검토 20건 중 8건은 v2에서 이미 반영, 11건 추가 반영, 1건 일부 반영. 권한 전제 삭제(#3·#7). Codex 교체는 `ROTATE_KIND=codex`, 못 하는 것은 `/loop`뿐(#2). 2절 제외 목록과 5절 관문 일치(#4). 조건 명령은 사용자 확인 목록 + 문자열 안전망(#5). 반복 엔진 하나·시작 지점 둘·stop 시점(#6). unit 7단계를 반복 본문 끝으로(#8). 최대 시간 앞뒤 점검·Worker 제한·state.json(#9). 실행 환경·126/127 구분(#12). 재위임 횟수 보존(#13). 보정 단위는 pathspec 안(#17). 통합 검수 범위 한정(#18 일부). 통합 검수 뒤 조건 재평가(#19). 10절 표·3경우(#20). v2에서 이미 반영: #1·#10·#11·#14·#15·#16.
- v2 (2026-10-20): agy(Gemini 4 Argon high) 독립 검토 16건 중 14건 반영, 2건 일부 반영. resume을 반복 본문에서 뺌(#1). 자동 승인 줄 필수(#2). 끝을 완료 보고로, close는 사용자(#3). `/loop` 시작 시점 통일(#4). 사다리의 외부 모델 질의 삭제(#5·#15). 권한 절 정정(#6). rotate 전 `/loop` 중지(#7, v4에서 순서 재정의). `model:` 삭제, cmd 거부 규칙·제한 시간(#8·#10). 완료 판정에 상태표 전부 완료, 보정 단위 상한 2(#9). 정체 기준 변경(#10·#15, v4에서 삭제). Worker 사망·다중 세션 흔적(#11 일부·#12). 이력은 goal/ 아래, status.sh blocked 집계(#13). 통합 검수 역할 구분, go 재개 행(#14). 10절 확인 항목(#16). 자체 검수: 126 추가, 결정 기록 위치, 비용 상한 없음.
