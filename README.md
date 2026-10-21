# mmCode

**밀리미터 단위로 일하는 코딩 에이전트 절차.** Claude Code와 Codex에서 같은 이름으로 부르는 스킬 묶음이다.

> Work in millimeters. Explain, plan, pair, relay, check, prove.

## 왜 mm인가

mm은 밀리미터다. 자에서 가장 작은 눈금이고, 눈대중과 측정을 가르는 단위다. 코딩 에이전트가 일하는 방식도 그래야 한다고 본다. 크게 짐작해서 한 번에 밀어붙이지 않는다. 이해한 내용을 먼저 말하고(explain) 계획을 세운다(plan). 그다음 단위로 쪼개 넘기고(relay), 변경이 닿는 범위를 재고(check-impact), 수치를 믿기 전에 점검하고(check-benchmark), 증명을 남긴다(make-verifier). 큰 일도 밀리미터 눈금으로 간다.

m²로 읽어도 된다. 변경 하나가 덮는 면적을 먼저 재는 습관이 이 묶음의 절반이다.

## 들어 있는 스킬

| 이름 | 하는 일 |
|---|---|
| `go` | 작업 입구. 요청을 읽고 경로 18개 중 하나를 골라 그 절차를 연다 |
| `explain` | 코드를 고치기 전에 "작업 이해" 화면으로 이해한 내용과 범위를 먼저 보여준다 |
| `plan` | 계획자·일꾼으로 나눠 계획하고, 엄격한 시험과 교차 검토로 실행한다 |
| `pair` | 다른 코딩 에이전트(codex·agy)에 코딩을 맡기고, 이 세션은 계획·검증을 맡는다 |
| `relay` | 큰 작업을 단위 표로 쪼개 브리프 → 작업 → 검수 → 커밋 → 인계 순서로 세션을 넘기며 이어 달린다 |
| `check-impact` | 작은 변경이 diff 밖 어디를 깨뜨릴 수 있는지 찾고, 안전한 이유를 실행으로 증명한다 |
| `check-benchmark` | 성능 수치를 보고하거나 그 수치로 결정하기 전에 7가지 질문으로 점검한다 |
| `make-verifier` | 프로젝트 전용 검증 스킬을 만든다. 동작 모드(`verify-<app>`)와 형식 모드(`prove-<area>`)가 있다 |
| `probe` | 설치 확인용. 표식 한 줄을 출력하고 멈춘다 |

흐름은 이렇다. `go`가 경로를 고르고, 코드를 바꾸는 경로면 `explain` 화면을 먼저 띄운 뒤 `plan`이 계획하고 실행한다. 길어지면 `relay`로 세션을 넘기고, 코딩 상대가 있으면 `pair`로 맡긴다. 변경 영향이 걱정되면 `check-impact`로, 성능 수치를 말하기 전에는 `check-benchmark`로 점검한다. 같은 증명을 반복해야 하면 `make-verifier`로 프로젝트 전용 검증 스킬을 남긴다.

## 설치

### Claude Code

```sh
claude plugin marketplace add bryannamd/mmCode
claude plugin install mmcode@mmcode
```

### Codex

```sh
codex plugin marketplace add https://github.com/bryannamd/mmCode
codex plugin add mmcode@mmcode
```

Codex는 설치할 때 플러그인을 `$CODEX_HOME/plugins/cache/` 아래에 복사한다. 플러그인이 갱신되면 `codex plugin remove mmcode@mmcode` 뒤에 `codex plugin add mmcode@mmcode`를 다시 실행해야 반영된다. GitHub 주소로 등록한 마켓이면 그 앞에 `codex plugin marketplace upgrade mmcode`로 스냅샷을 먼저 갱신한다. Claude Code는 GitHub에서 설치했으면 `claude plugin update mmcode@mmcode`로 갱신하고, 로컬 폴더에서 설치했으면 폴더를 바로 읽으므로 `/reload-plugins`로 충분하다.

로컬 사본으로 쓰려면 저장소를 받은 뒤 위 명령의 주소 자리에 그 폴더 경로를 넣는다.

## 부르는 법

| | Claude Code | Codex |
|---|---|---|
| 입구 | `/go` 또는 `/mmcode:go` | `$mmcode:go` |
| 개별 스킬 | `/explain`, `/relay`, `/pair`, … | `$mmcode:explain`, `$mmcode:relay`, `$mmcode:pair`, … |
| `plan` | `/mmcode:plan` (`/plan`은 Claude Code 내장 명령과 겹친다) | `$mmcode:plan` |

## 전제

- 스킬은 커밋·푸시·승인 경계·모델 등급 같은 전역 규칙을 다시 정하지 않는다. 프로젝트의 CLAUDE.md·AGENTS.md가 항상 우선한다.
- 스킬이 "전역 규칙을 따른다"고 하는 자리는 다음 네 가지가 있다고 전제한다. 커밋·푸시는 사용자 확인 뒤에만 한다. 하위 에이전트에 맡긴 결과는 diff와 시험으로 확인한다. 공유 워킹트리에서 `stash`·`reset --hard`·`checkout --` 같은 파괴적 git 명령을 쓰지 않는다. 교차 검토용 외부 에이전트(codex·agy)의 호출법과 한도 확인 방법이 정해져 있다. 전역 규칙이 없으면 그 자리에서 보수적으로 행동한다. 확인하고 진행하고, 교차 검토는 `미실행 · 전역 규칙 없음`으로 적는다.
- `pair`의 codex 경로와 `relay`의 세션 교체는 herdr 터미널 탭(`HERDR_ENV=1`) 안에서만 동작한다. herdr 밖에서 `pair`는 agy 경로를 쓰고, `relay`는 인계 문서를 쓴 뒤 새 세션 시작을 안내한다.
- 스킬 본문은 한국어다. 작업 이해·작업 계획·작업 완료 화면은 터미널 폭 50칸 기준으로 그린다.
- 규칙은 두 층이다(plan 0절). 전역 규칙·증거 보고·완료 보고 확인은 불변이고, 그 밖의 수치·형식·절차는 기본값이라 이유를 적고 벗어날 수 있다.

## 규칙을 더하기 전에

- 새 규칙이나 수치를 더하기 전에 `go`의 스킬 평가 절차(`plugins/mmcode/skills/go/playbooks/eval.md`)로 플러그인이 있을 때와 없을 때를 같은 과제로 블라인드 비교한다. 비교 없이 더하지 않는다. 비교 기록은 `docs/`에 남긴다.
- 수치가 있는 규칙에는 정한 이유(사건·날짜)를 붙인다. 그 사건이 지금 모델에서 재현되지 않으면 삭제 후보다.

## 라이선스

MIT
