---
name: relay
description: 큰 작업을 "단위 표"로 쪼개 브리프→Worker→독립 검수→커밋→인계 한 줄 갱신→새 세션 교체(herdr) 로 이어 달리는 실행 워크플로. 계획 파일과 인계 문서(HANDOFF) 템플릿, 첫 응답 상태표 스크립트, herdr 세션 교체 스크립트, 임시 인덱스 원자 커밋 스크립트 포함. "/relay", "핸드오프 루프", "단위 계획으로 진행", "handoff loop", "세션 교체해", "인계 재개", "단위 끝 커밋하고 다음 세션" 요청에 사용. 일반적인 "계획 세워줘"·단일 작업에는 쓰지 않는다.
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

## close — 종료

`references/closing.md` 항목을 사용자에게 **하나씩 확인**하고 처리한다(임시 권한 제거·add-dir 제거·scratch 정리·인계 문서 종료 표시·자동 승인 소진). 사용자 답 없이 제거·유지를 결정하지 않는다.

## 금지

- 인계 문서에 서술 누적, 상태를 두 파일에 중복.
- 검증 결과 없이 "완료" 보고. 실행하지 않은 검증을 pass 로 기록.
- 세션당 3단위 이상, 자기 pane close, 이전 pane 이 working 인데 close.
- 스킬 안에서 커밋 자동 승인·권한 완화를 기본값으로 두는 것.
