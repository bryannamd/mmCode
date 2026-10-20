---
name: pair
description: 다른 코딩 에이전트에게 코딩을 맡기고 이 세션은 계획·브리프·검증·진행 감시를 맡는다. 상대는 환경으로 고른다. `HERDR_ENV=1`(herdr 탭)이면 같은 탭의 codex pane(없으면 만든다), 아니면 `agy` CLI를 headless로 부른다. 사용자가 상대를 지목하면 그쪽을 쓴다. "/pair", "codex에 위임", "codex한테 시켜", "agy한테 시켜", "agy로 구현", "페어 세팅", "herdr 페어" 요청에 사용. 교차 검토만 맡기는 경우와 코드 변경이 없는 작업에는 쓰지 않는다.
---

# pair — 다른 에이전트와 짝 코딩

이 세션이 계획·브리프·검증·감시를 맡고, 상대 에이전트가 코딩한다. 위임은 구현을 넘기는 것이고 책임은 넘기지 않는다. 이 스킬이 켜져 있으면 코딩 상대는 하나다. 같은 코딩을 하위 에이전트에게도 맡기지 않는다. `S`는 이 스킬 폴더다(Claude는 호출 시 "Base directory for this skill"로, Codex는 스킬 목록의 파일 경로로 안다).

## 0. 상대 고르기

```bash
test "${HERDR_ENV:-}" = 1 && printf '%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID"
```

- 성공(herdr 탭) → **codex**(2절). 사용자가 agy를 지목했으면 agy.
- 이 세션이 codex이면 자기 pane은 상대가 아니다. 2절의 `codex`를 `claude`로 바꿔 읽는다(`--kind claude`, agent 이름 `claude`). 그것도 안 되면 agy.
- 실패 → **agy**(3절). 사용자가 codex를 지목했으면 herdr 밖이라는 사실만 알리고 멈춘다. agy로 바꾸지 않는다. `agy` 명령이 없으면 그 사실만 알리고 멈춘다. 다른 상대로 조용히 바꾸지 않는다.

## 1. 공통 규칙

| 맡는 일 | 이 세션 | 상대 |
|---|---|---|
| 요구 분석·설계·브리프·작업 분할 | O | X |
| 코드 작성·수정 | X (한두 줄·긴급 제외) | O |
| 빌드·테스트 실행 | 검증 목적으로 O | codex는 작업 중 O · agy는 X |
| diff 검수·완료 판정 | O | X |
| 커밋·푸시 | 사용자 확인("커밋할까요?") 후에만 | 하지 않는다 |

- **순서**: 분석 → 저장소 확인 → 계획 → 위임 → 검수 → 시험 → 수정 → 재시험 → 최종 검토. 설계·계획·디버깅 전략·완료 판정은 이 세션이 한다.
- **브리프**: 작업 하나에 브리프 하나. 파일 경로·대상 함수·지킬 컨벤션·함정·기대 동작·완료 기준(이 세션이 돌릴 시험)을 압축해 담는다. 소스나 대화를 통째로 붙이지 않는다. 상대가 직접 읽는다. 설계·디버깅 전략·완료 판정처럼 판단이 필요한 일은 넘기지 않는다. 모델 등급은 plan 3절 표를 따른다.
- **위임 전 기록**: `git status --short`로 지금 상태를 적어 둔다(git 저장소가 아니면 대상 파일을 백업한다). 상대의 변경을 기존 변경과 구분하기 위해서다.
- **검증**: 상대의 "완료" 보고를 믿지 않는다. 요청한 동작이 구현됐는지, `git diff`(또는 백업과 비교)에 의도한 변경만 있는지, 프로젝트의 시험·타입 검사·lint·빌드가 통과하는지, 알려진 치명적 회귀가 없는지 이 세션이 직접 확인한 뒤에만 승인한다.
- **재위임**: 실패하면 실패한 시험 또는 file:line, 원인, 필요한 변경을 짚어 다시 보낸다. "고쳐 줘"와 로그만 보내지 않는다. 같은 완료 기준으로 2회까지. 그래도 안 되면 이 세션이 직접 하거나 사용자에게 올린다.
- **멈춤**: 상대가 빈 응답·권한 거부·한도 초과를 돌려주면 사용자에게 알린다. 다른 상대로 조용히 바꾸지 않는다.

## 2. codex (herdr 탭)

### 2.1 codex pane 확보

현재 탭의 에이전트부터 본다.

```bash
herdr api snapshot | jq -r --arg t "$HERDR_TAB_ID" \
  '.result.snapshot.agents[] | select(.tab_id==$t) | "\(.pane_id)\t\(.agent)"'
```

`codex` 줄이 있으면 2.2로 간다. 이 세션 혼자(pane 하나)면 세로 분할 후 codex를 띄운다.

```bash
pane=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus \
       | jq -r '.result.pane.pane_id')
herdr agent start codex --kind codex --pane "$pane" \
  || herdr agent start "codex-${HERDR_TAB_ID##*:}" --kind codex --pane "$pane"
```

- `--direction right`는 세로 분할이다(왼쪽 이 세션, 오른쪽 codex).
- `--no-focus`를 유지한다. 사용자 포커스를 뺏지 않는다.
- agent 이름은 살아 있는 에이전트끼리 유일해야 한다. `codex`가 다른 탭에서 점유 중이면 첫 명령이 실패하므로 탭 범위 이름으로 다시 시도한다(위 `||`).
- `agent start`는 pane이 셸 프롬프트 상태여야 하고 기본 30초까지 준비를 기다린다. 타임아웃이면 pane은 남아 있으니 `herdr agent start ... --pane "$pane" --timeout 60000`으로 다시 시도한다.
- 이미 codex가 있는 탭에서 이 블록을 또 실행하지 않는다. 중복 pane이 생긴다.

### 2.2 pane 이름 붙이기

```bash
bash "$S/scripts/rename-panes.sh" --current
```

같은 탭에 claude+codex가 있을 때만 동작하고, 감지된 종류대로 pane 라벨과 agent 이름을 붙인다. 여러 번 실행해도 안전하다. 출력의 `agent-name`이 이후 CLI 타깃이다. 이름이 이미 점유돼 `(use pane id ...)`로 나오면 그 pane id를 타깃으로 쓴다.

### 2.3 위임과 감시

```bash
herdr agent prompt codex "<브리프>" --wait --timeout 600000
herdr agent read codex --source recent-unwrapped --lines 120
herdr agent get codex
```

- `--wait`는 idle/done/blocked 중 첫 안정 상태에서 돌아온다. 승인·질문 UI에 걸리면 `blocked`다. `agent read`로 내용을 보고 필요한 입력을 정한다.
- 오래 걸리는 작업은 `herdr agent wait codex --until blocked --timeout ...`로 승인 요청만 따로 기다린다.
- 응답이 화면 밖으로 밀려 `--lines`를 늘려도 안 보이면(대체 화면 버퍼), codex에게 결과를 임시 디렉터리에 Markdown으로 쓰고 경로만 답하게 한 뒤 그 파일을 읽는다.

### 2.4 herdr 경계

- 사용자가 만든 pane·탭·워크스페이스를 닫지 않는다. `herdr server stop`은 쓰지 않는다.
- herdr CLI 상세는 설치된 바이너리가 기준이다. `herdr agent`, `herdr pane`처럼 그룹만 실행해 확인한다(맨 `herdr`는 TUI를 띄우므로 쓰지 않는다).

## 3. agy (headless CLI)

브리프를 파일에 쓰고 프로젝트 루트에서 실행한다.

```bash
agy -p "$(cat <brief-file>)" --mode accept-edits --print-timeout 600s < /dev/null
```

- `< /dev/null`은 필수다. 없으면 호출이 stdin에서 멈출 수 있다.
- 이 모드에서 agy는 파일 읽기·편집만 할 수 있다. 셸 명령은 자동 거부되고, 시도하면 그 턴 전체가 출력도 편집도 없이 끝난다. 그래서 브리프마다 아래 고정 규칙을 넣는다.
- `--dangerously-skip-permissions`를 붙이지 않고 agy 설정을 바꾸지 않는다. 둘 다 사용자 승인이 먼저다.
- 큰 작업은 브리프 여러 개로 나누고, 하나를 검증한 뒤 다음을 보낸다. 같은 맥락에서 교정을 보낼 때는 `-c`(최근 대화 이어가기)를 붙인다.

브리프 틀:

```text
## Task
<one scoped change>

## Files
<paths and target functions — agy reads the code itself, do not paste whole files>

## Constraints
<conventions to follow, pitfalls, what must not change>

## Expected behavior
<inputs → outputs, edge cases>

## Acceptance criteria
<tests this session will run>

## Fixed rules
- Do NOT run any shell or terminal commands. Use only file read and file edit tools.
- Do not run tests, builds, or git. The supervisor runs them.
- Change only the files listed above. No unrelated changes, no redesign.
- Report: changed files, implementation summary, tests run (write "none"), uncertainties.
```

## 4. 경계

- 상대는 `git commit`·`git push`·파괴적 git 명령을 실행하지 않는다. 커밋·푸시는 사용자 확인 후 이 세션이 한다.
- 전역·프로젝트 규칙(CLAUDE.md·AGENTS.md)이 이 스킬보다 우선한다.
