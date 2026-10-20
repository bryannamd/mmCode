# 입구 스킬 설계안 (pstack 구조 차용)

> 2026-10-20: mmCode 플러그인(`plugins/mmcode/skills/`)으로 옮기며 스킬 이름을 바꿨다(explain-first→explain, football-manager→plan, handoff-loop→relay, herdr-pair+supervisor-coding→pair, blast-radius→check-impact, benchmark-checklist→check-benchmark, create-*-skill→make-verifier). 아래 본문의 이름·경로는 치환한 것이다.

2026-10-18 · 상태: 적용 완료(이름 `go`). 2절 흐름은 SKILL.md가 정본 — 이후 문구 수정은 SKILL.md에 반영됨

## 한 줄 요약

작업을 시작할 때 부르는 스킬 하나를 만든다. 이 스킬이 작업 종류를 고르고, 맞는 절차를 연다. 절차는 기존 스킬(explain·plan·relay·pair·리뷰·교차검증)을 가리키거나, pstack에서 옮겨 온 짧은 절차 파일이다.

## 1. 지키는 것 / 안 하는 것

- 전역 규칙(CLAUDE.md·AGENTS.md)이 항상 우선한다. 입구는 자율성·승인 경계·모델 등급·커밋 규칙·답변 문체를 다시 정하지 않는다.
- 훅 모드(ponytail·caveman·oh-my-fable)는 그대로 켜진다.
- 기존 스킬은 그대로 둔다. `/explain`·`/plan`·`/relay`를 직접 불러도 된다. 입구는 그 위에 얹힌다.
- Claude와 Codex 공용으로 만든다. 플러그인(`plugins/mmcode/skills/`)으로 양쪽에 로드된다. 도구 이름을 쓰지 않고 "하위 에이전트", "에이전트 도구가 없으면 직접"처럼 쓴다(plan과 같은 방식).
- pstack 플러그인은 설치하지 않는다.

## 2. 부르는 법과 흐름

- `/<이름>` 또는 "입구로 시작해". 처음에는 명시 호출만 받는다. 익숙해지면 description에 자동 트리거 문구를 넣을지 다시 정한다.
- 흐름:
  1. 요청을 읽고 3절 표에서 **경로** 하나를 고른다. 둘 다 맞으면 더 좁은 쪽을 고른다. 맞는 게 없으면 코드 변경은 `기능`, 그 외는 `조사`.
  2. 코드를 바꾸는 경로면 explain 화면을 띄우고 🎯 블록 끝에 `▸ 경로: <이름>` 줄을 더한다(plan이 `▸ 방침:`을 더하는 자리와 같다). 코드를 바꾸지 않는 경로면 화면 대신 한 줄 `▶ 경로: 조사 · 읽기만`을 쓴다.
  3. 절차 파일을 열어 단계를 번호 목록으로 답변에 적는다. 건너뛰는 단계는 `건너뜀: <이유>`로 남긴다.
  4. 단계가 기존 스킬을 가리키면 그 스킬을 따른다.
  5. 끝은 그 절차가 정한 보고 형식으로 한다. 코드 변경은 plan 완료 화면, 조사·진단은 "결론 → 근거(file:line) → 확신도".

## 3. 경로 표

| 묶음 | 경로 | 언제 | 따르는 것 | 출처 |
|---|---|---|---|---|
| 알아보기 | 조사 | 어떻게 동작하나·왜 이렇게 만들었나·확실한가 | `playbooks/investigation.md` | pstack 이식 |
| | 실행 중 진단 | 메모리 누수·CPU 공회전·간헐 오류를 살아 있는 프로세스에서 찾기. 결과는 진단만 | `playbooks/runtime-forensics.md` | pstack 이식 |
| | 프로파일 분석 | cpuprofile·trace·heap snapshot 파일 분석. 결과는 진단만 | `playbooks/trace-forensics.md` | pstack 이식 |
| | 변경 영향 범위 | 작은 변경이 어디까지 영향을 주나. "안전한 이유"를 실행으로 증명 | `check-impact` 스킬 | pstack 이식(단독) |
| 고치기·만들기 | 버그 수정 | 재현 → 원인 → 실패 시험 → 수정 | `playbooks/bug-fix.md` → explain → plan | pstack 얇게 + 기존 |
| | 기능 | 새 동작·바뀐 동작 | explain → plan | 기존 |
| | 리팩터 | 동작은 그대로, 구조만 바꿈 | `playbooks/refactoring.md` → plan | pstack 얇게 + 기존 |
| | 시제품 | 묻기 전에 만들어 보고 결정 | `playbooks/prototype.md` | pstack 이식 |
| | 화면 일치 | 두 구현의 픽셀 일치, 스타일 이전 | `playbooks/visual-parity.md` (스크린샷은 정해진 브라우저 도구) | pstack 이식 |
| 측정·개선 | 성능 문제 | 느린 곳을 한 번 고침. 기준선 먼저 | `playbooks/perf-issue.md` + `check-benchmark` | pstack 이식 |
| | 지표 개선 반복 | 지표 하나를 목표까지 가설·측정 반복 | `playbooks/hillclimb.md` | pstack 이식(커밋 줄 수정) |
| 길게 가기 | 긴 작업 | 단위 여러 개·세션 여러 개 | relay `init`/`unit`/`rotate` | 기존 |
| | 재개 | 인계 문서로 새 세션 시작 | relay `resume` | 기존 |
| | 페어 | 다른 코딩 에이전트(codex·agy)가 코딩하고 이 세션은 계획·브리프·검증을 맡는다. 상대는 pair가 환경으로 고른다 | pair | 통합(10-20) |
| 검증·검토 | 코드 리뷰 | 정확성 `/code-review` · 보안 `/security-review` · 과설계는 ponytail 플러그인이 있으면 `/ponytail-review` | 기존 | 기존 |
| | 교차 검증 | 되돌리기 어려운 변경 | CLAUDE.md codex·agy 정책 | 기존 |
| | 검증 스크립트 | 앱을 사용자처럼 돌려 증거를 남기는 스킬 생성 / 동시성·상태기계 형식 검증 | `make-verifier`(동작·형식 모드) | pstack 이식(단독) |
| | 스킬 평가 | 스킬·프롬프트 변경이 행동을 바꾸는지 블라인드 비교 | `playbooks/eval.md` | pstack 이식 |

경로 18개. 새 파일은 절차 10개 + 단독 스킬 4개. 나머지 7개는 기존 스킬을 가리키기만 한다.

## 4. 원칙 (참고 문서 1개)

`references/principles.md`. pstack 24개 중 ponytail·CLAUDE.md와 겹치는 것을 빼고 12개 안팎. 각 2~3줄 한국어.

- 넣는 것: 전제를 의심하기(같은 전제로 2번 실패하면 전제를 먼저 검증) · 숫자를 설명하기(왜 2배가 아닌가) · 동작을 시험하기(구현이 아니라) · 공유 상태는 먼저 나누기 · 재실행해도 같은 결과(멱등) · 분기 대신 구조(상태기계·테이블) · 읽는 사람 부담(30초 안에 "X는 어디서 오나") · 처음부터 재설계 · 선례 없으면 시제품 2~3개 · 검증이 실패하면 검증 방법을 먼저 의심 · 가드 vs 근본 수정 판별 기준("이 상태가 정당한가").
- 빼는 것: laziness·subtract·minimize 본체(ponytail) · prove-it-works 본체(CLAUDE.md 완료 기준) · never-block-on-the-human(규칙 충돌) · build-the-lever(ponytail과 반대) · guard-the-context-window(Advisor/Worker) · encode-lessons(lessons 규칙) · outcome-oriented(공유 트리 충돌) · migrate-callers(삭제 사전 확인 충돌) · experience-first(디자인 가이드) · type-system·boundary(언어별).
- 쓰는 법: 결정을 바꾼 원칙만 보고에 한 줄. 예: `원칙: 전제 의심 · 캐시가 아니라 쿼리를 봄`. 없으면 쓰지 않는다.

## 5. pstack에서 옮길 때 고치는 것 (절차 10개 공통)

1. Cursor 도구·기능 이름 제거: Task · AskQuestion · create-skill · cursor-team-kit(deslop·control-ui) · Bugbot · cloud agent · `/loop`.
2. 커밋·PR 지시 → "단위 끝에 커밋할지 묻는다"(Git 안전 규칙). "Opening a PR" 마무리 → plan 완료 화면.
3. 모델 슬러그(grok·opus-xhigh) → plan 등급 표.
4. 답변 형식 지시(unslop·Writing the reply) → 삭제. caveman·STE가 담당.
5. 영어 → 한국어. 한 문장 한 뜻. 코드·명령·파일명은 그대로.
6. 길이: 절차 1개 ≤30줄, 입구 SKILL.md ≤150줄, 원칙 ≤60줄.
7. 단독 스킬 4개: `.cursor/skills/` → `.claude/skills/`, 어댑터 참조 줄 삭제, `how`/`why`/`unslop` 언급 삭제. 본문 한국어.

## 6. 파일 배치

```
plugins/mmcode/skills/<이름>/
  SKILL.md
  playbooks/{investigation,bug-fix,refactoring,perf-issue,hillclimb,
             runtime-forensics,trace-forensics,prototype,visual-parity,eval}.md
  references/principles.md
plugins/mmcode/skills/check-impact/SKILL.md
plugins/mmcode/skills/check-benchmark/SKILL.md
plugins/mmcode/skills/make-verifier/SKILL.md (+ references/feature-map-example/*)
(링크 없음 — 플러그인이 Claude·Codex 양쪽에 로드된다)
```

새 파일 약 16개. 기존 파일 수정 없음. CLAUDE.md 수정 없음(원하면 "플러그인·스킬·도구 라우팅"에 한 줄 추가. 별도 승인).

## 7. 안 가져오는 것

- 절차: autopilot-full/stack · shipping · babysit · orchestrate · worktree-cleanup · opening-a-pr · pause-safely · session-pickup · multi-phase-plan · authoring-a-skill (relay·skill-creator가 담당하거나 규칙 충돌).
- 스킬: setup-pstack · make-bot-ui · no-comments · interrogate · arena · swarm · architect(design-red-flags.md만 후속 검토) · how · why(epistemics.md는 조사 절차의 확신도 표기로 흡수) · teach · recall · ketchup · unslop · bro · technical-writing · automate-me · reflect · correct(우선순위만 lessons 규칙에 반영. 별도 건) · figure-it-out · tdd · typescript-best-practices.
- 원칙 12개(4절 "빼는 것").

## 8. 만드는 순서와 확인 방법

| 단위 | 내용 | 확인 |
|---|---|---|
| 1 | 입구 SKILL.md + principles.md + 링크 | frontmatter가 `---`로 시작. 링크가 symlink. `/<이름>` 호출 시 경로 표가 뜸 |
| 2 | 절차 10개 이식 | Cursor 잔재 grep 0건(`cursor\|Task\|AskQuestion\|grok\|deslop\|bugbot\|/loop\|pr merge\|--force`). 커밋 지시는 "묻는다" 형태만. 각 ≤30줄 |
| 3 | 단독 스킬 4개 이식 + 링크 | 같은 grep 0건. `.cursor` 0건. 예제 폴더 포함 |
| 4 | 시험 호출 3건 | 성능 요청→perf-issue, 조사 요청→investigation, 버그→bug-fix로 가는지. 완료 화면 형식 유지 |

Codex 쪽 인식은 `codex debug prompt-input 'hello' | grep -o 'mmcode:[a-z-]*'`로 확인한다(모델 호출 없음).

## 9. 정해야 할 것

1. 입구 이름. 후보: `go`(짧고 기존 `run` 스킬과 안 겹침) · `start` · `do` · 직접 지정.
2. 이식 절차 본문 언어: 한국어(기본. 기존 스킬과 같음) / 영어 유지.

## 10. 보장하지 못하는 것

- 입구가 "확인 창에서 엔터만 치는" 습관을 바꾸지 않는다. 그건 `ask`→`deny` 분리 건이다.
- 절차 이식 뒤 pstack 업스트림 변경은 자동 반영되지 않는다. 분기마다 `git -C <사본> pull` 후 diff로 수동 반영한다.
