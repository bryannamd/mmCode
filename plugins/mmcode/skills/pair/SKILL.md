---
name: pair
description: 다른 코딩 에이전트에게 코딩을 맡기고 이 세션은 계획·브리프·검증·진행 감시를 맡는다. 상대는 환경으로 고른다. `HC_TERMINAL_ID`가 있으면(Herdr 탭) 같은 탭의 codex 터미널(없으면 만든다), 아니면 `agy` CLI를 headless로 부른다. 사용자가 상대를 지목하면 그쪽을 쓴다. "/pair", "codex에 위임", "codex한테 시켜", "agy한테 시켜", "agy로 구현", "페어 세팅", "Herdr 페어" 요청에 사용. 교차 검토만 맡기는 경우와 코드 변경이 없는 작업에는 쓰지 않는다.
---

# pair — 다른 에이전트와 짝 코딩

이 세션이 계획·브리프·검증·감시를 맡고, 상대 에이전트가 코딩한다. 위임은 구현을 넘기는 것이고 책임은 넘기지 않는다. 이 스킬이 켜져 있으면 코딩 상대는 하나다. 같은 코딩을 하위 에이전트에게도 맡기지 않는다. `S`는 이 스킬 폴더다(Claude는 호출 시 "Base directory for this skill"로, Codex는 스킬 목록의 파일 경로로 안다). 수치·형식 규칙은 기본값이다(plan 0절).

## 0. 상대 고르기

```bash
test -n "${HC_TERMINAL_ID:-}" && echo "Herdr 탭: $HC_TERMINAL_ID"
```

- 성공(Herdr 탭) → **codex**(2절). 사용자가 agy를 지목했으면 agy.
- 이 세션이 codex이면 자기 터미널은 상대가 아니다. 2절의 `codex`를 `claude`로 바꿔 읽는다(상대 탐지는 `.agent == "claude-code"`, 실행은 `-- claude`, 이름 `claude-<내 주소>`). 그것도 안 되면 agy.
- 실패 → **agy**(3절). 사용자가 codex를 지목했으면 Herdr 밖이라는 사실만 알리고 멈춘다. agy로 바꾸지 않는다. `agy` 명령이 없으면 그 사실만 알리고 멈춘다. 다른 상대로 조용히 바꾸지 않는다.

## 1. 공통 규칙

| 맡는 일 | 이 세션 | 상대 |
|---|---|---|
| 요구 분석·설계·브리프·작업 분할 | O | X |
| 코드 작성·수정 | X (한두 줄·긴급 제외) | O |
| 빌드·테스트 실행 | 검증 목적으로 O | codex는 작업 중 O · agy는 X |
| diff 검수·완료 판정 | O | X |
| 커밋·푸시 | 사용자 확인("커밋할까요?") 후에만 | 하지 않는다 |

- **순서**: 분석 → 저장소 확인 → 계획 → 위임 → 검수 → 시험 → 수정 → 재시험 → 최종 검토. 설계·계획·디버깅 전략·완료 판정은 이 세션이 한다.
- **브리프**: 작업 하나에 브리프 하나. 내용·통째 복붙 금지·모델 등급은 plan 3절을 따른다. 완료 기준에는 이 세션이 돌릴 시험을 적는다. 설계·디버깅 전략·완료 판정처럼 판단이 필요한 일은 넘기지 않는다.
- **위임 전 기록**: `git status --short`로 지금 상태를 적어 둔다(git 저장소가 아니면 대상 파일을 백업한다). 상대의 변경을 기존 변경과 구분하기 위해서다.
- **검증**: 상대의 "완료" 보고를 믿지 않는다. 요청한 동작이 구현됐는지, `git diff`(또는 백업과 비교)에 의도한 변경만 있는지, 프로젝트의 시험·타입 검사·lint·빌드가 통과하는지, 알려진 치명적 회귀가 없는지 이 세션이 직접 확인한 뒤에만 승인한다.
- **재위임**: 실패하면 실패한 시험 또는 file:line, 원인, 필요한 변경을 짚어 다시 보낸다. "고쳐 줘"와 로그만 보내지 않는다. 횟수와 원인 가르기는 plan 3절을 따른다.
- **멈춤**: 상대가 빈 응답·권한 거부·한도 초과를 돌려주면 사용자에게 알린다. 다른 상대로 조용히 바꾸지 않는다.

## 2. codex (Herdr 탭)

이후 명령은 이름이 아니라 터미널 주소(예 `t3n`)로 겨냥한다. `hc`의 제한 시간(`--timeout`)은 초 단위다.

### 2.1 codex 터미널 확보

예외: 호출자(relay `auto`)가 작업 디렉터리와 이름을 지정하면 아래 탐지와 재사용을 하지 않는다. 기존 터미널을 쓰지 않고 `--cwd <경로>`·`--name <이름>`으로 새 터미널을 띄우며, 2.3은 `hc run`이 돌려준 주소를 타깃으로 쓴다. 끝나면 호출자가 그 터미널을 `hc kill` 뒤 `hc rm`으로 닫는다.

먼저 2.2로 같은 탭의 codex 주소를 찾는다. 있으면 그 주소를 쓴다. 없으면 내 탭 라벨을 붙여 codex를 띄운다.

```bash
me=$(hc get "$HC_TERMINAL_ID")
space=$(printf '%s' "$me" | jq -r '.labels["herdr.space"] // empty')
tab=$(printf '%s' "$me" | jq -r '.labels["herdr.tab"] // empty')
labels=(); [ -z "$space" ] || [ -z "$tab" ] || labels=(--label "herdr.space=$space" --label "herdr.tab=$tab")
hc run --bg --name "codex-$HC_TERMINAL_ID" --cwd "$PWD" \
  ${labels[@]+"${labels[@]}"} -- codex --no-daemon | jq -r '.address'
hc wait <주소> --timeout 60
```

- 라벨 값은 반드시 `hc get "$HC_TERMINAL_ID"`에서 읽은 값을 쓴다. 값이 틀리면 엉뚱한 스페이스가 생긴다. 두 라벨이 다 있어야 같은 탭의 새 패널로 보인다. 하나라도 비면 위 명령은 `--label` 없이 띄운다. 그때는 화면에 보이지 않는다고 사용자에게 알린다.
- 내가 띄운 패널이 이미 3개면 라벨 없이 숨긴다. 숨긴 터미널의 감시·입력 대기·정리는 relay 스킬의 `../relay/references/terminals.md`를 따른다.
- `--no-daemon`을 뺄 수 없다. 빼면 codex의 명령이 hc 밖에서 실행된다.
- 이 일꾼은 부모(이 세션)가 끝나면 같이 끝난다.
- 이름은 살아 있는 터미널끼리 유일해야 한다(`a-z 0-9 - _`, 1~32자). `name_taken`이면 이미 띄운 codex가 있는지 2.2로 다시 본다.
- `hc wait`가 `"reason":"status"`와 `idle`로 돌아오면 준비된 것이다. 아니면 `hc read <주소> --lines 40`으로 화면을 본다.
- 이미 codex가 있는 탭에서 이 블록을 또 실행하지 않는다. 중복 터미널이 생긴다.

### 2.2 상대 주소 확인

```bash
tab=$(hc get "$HC_TERMINAL_ID" | jq -r '.labels["herdr.tab"] // empty')
hc ls --label "herdr.tab=$tab" | jq -r --arg me "$HC_TERMINAL_ID" '.terminals[] | select(.address != $me and .agent == "codex") | .address'
```

출력된 주소가 이후 CLI 타깃이다. 여러 개면 사용자에게 어느 쪽인지 묻는다. hc에는 패널·터미널 이름을 바꾸는 명령이 없으므로 이름을 붙이지 않는다.

### 2.3 위임과 감시

```bash
hc send --wait --timeout 600 <주소> "<브리프>"
hc read <주소> --lines 120
hc get <주소>
```

- `--wait`는 이 전송으로 시작한 턴이 끝나거나 멈추면 돌아온다. 제한 시간이 지나도 종료 코드는 0이고 `"wait":{"reason":"timeout"}`이다. 결과 JSON을 읽는다.
- 승인·질문 UI에 걸리면 `blocked`다. 이때 `hc send`는 거부된다. `hc read`로 화면을 보고 필요한 입력을 사용자에게 묻는다. `--force`로 넘기지 않는다.
- 오래 걸리는 작업은 `hc wait <주소> --timeout <초>`로 다시 기다린다.
- 응답이 화면 밖으로 밀려 `--lines`를 늘려도 안 보이면(대체 화면 버퍼), codex에게 결과를 임시 디렉터리에 Markdown으로 쓰고 경로만 답하게 한 뒤 그 파일을 읽는다.

### 2.4 Herdr 경계

- 사용자가 만든 터미널에는 `hc kill`·`hc rm`·`hc send`를 하지 않는다. 읽기(`hc get`·`hc read`)만 한다. `hc server stop|restart`는 쓰지 않는다.
- CLI 상세는 `hc --skill`과 `hc <명령> --help`가 기준이다.

## 3. agy (headless CLI)

브리프를 파일에 쓰고 프로젝트 루트에서 실행한다.

```bash
agy -p "$(cat <brief-file>)" --mode accept-edits --print-timeout 600s < /dev/null
```

- `< /dev/null`은 필수다. 없으면 호출이 stdin에서 멈출 수 있다.
- 이 모드에서 agy는 파일 읽기·편집만 할 수 있다. 셸 명령은 자동 거부되고, 시도하면 그 턴 전체가 출력도 편집도 없이 끝난다. 그래서 브리프마다 아래 고정 규칙을 넣는다.
- `--dangerously-skip-permissions`를 붙이지 않고 agy 설정을 바꾸지 않는다. 둘 다 사용자 승인이 먼저다.
- 큰 작업은 브리프 여러 개로 나누고, 하나를 검증한 뒤 다음을 보낸다. 같은 맥락에서 교정을 보낼 때는 `-c`(최근 대화 이어가기)를 붙인다.
- 호출자가 작업 디렉터리(relay `auto`의 워크트리)를 지정하면 프로젝트 루트 대신 그곳에서 실행하고 `--add-dir`로 같은 경로를 작업 공간에 더한다.

```bash
cd <워크트리> && agy -p "$(cat <brief-file>)" --mode accept-edits --print-timeout 600s --add-dir <워크트리> < /dev/null
```

- 이때 호출자는 agy 프로세스의 PID와 시작 시각(`ps -o lstart= -p <PID>`)을 기록한다. 재개 때 같은 프로세스가 아직 살아 있는지 확인하는 데 쓴다.

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
