# relay 고정 규칙 (범용판)

| # | 규칙 | 이유 |
|---|---|---|
| R1 | 다른 저장소를 만져야 하면 `.claude/settings.json` `permissions.additionalDirectories` 에 등록하고 Worker 가 직접 편집한다. stage/manifest/apply 복사 절차를 만들지 않는다. 등록은 인계 문서 "종료 시 제거" 절에 기록 | 이전 계획에서 stage/apply 가 단위당 가장 큰 낭비였음 |
| R2 | 검증 1회. Worker 가 실행한 로그를 Advisor 가 읽고 diff 만 검토. 검수자는 diff + 신규 테스트만 실행. 무거운 통합 테스트는 2~3단위마다 1회(단위 끝 `run_in_background`). lint 는 pathspec 파일만(`eslint <files>`), 전체 lint·기준선 비교 로그 금지 | 실행 3회 → 1회. 전체 lint 로그는 회당 600KB+ |
| R3 | 검수 티어: 순수 모듈·테스트 = sonnet(`/code-review low` 대체 가능), 저장 트랜잭션·권한 경계·lease·동시성 = opus. 적대 프로브는 opus 검수에서만 | 검수 비용 절반 이하 |
| R4 | 단위 크기: 브리프 1 → Worker 1 → 검수 1 → 커밋 1. 인계 문서는 단위 끝에 상태표 한 행만 갱신 | 의식 횟수 절반 |
| R5 | Worker 티어는 plan 3절 표를 따른다. 같은 탭에 codex 가 있으면 순수 모듈은 codex(`pair`) | 토큰 단가 |
| R6 | 병렬은 서로 다른 파일의 순수 모듈만. 같은 파일 체인은 직렬. 병렬 편집은 `isolation: worktree` 또는 별도 파일 | 충돌 회피, 병렬은 시간만 줄이고 토큰은 안 줄임 |
| R7 | 직전 단위의 Worker 또는 검수가 opus 였거나 세션에서 2단위를 마쳤을 때만 세션 교체. sonnet/haiku 단위 뒤에는 이어서 진행. 세션당 최대 2단위 | 교체 1회 ≈ 10분. 09-16 계획에서 세션 11개/단위 10개 |
| R8 | 300줄 넘는 파일은 `cat` 금지(`grep`/`sed -n`). 조사·1~2파일 수정·diff 검수는 압축 출력 에이전트(caveman 플러그인의 cavecrew 가 있으면 그것, 없으면 일반 하위 에이전트) | 메인 컨텍스트 유입 감소 |
| R9 | 푸시·배포·활성화·승인 파일·외부 전송은 항상 사용자 확인. 커밋은 인계 문서 정책 줄이 정한다(기본 확인 후) | Git 안전 규칙 |
| R10 | 저장소가 둘 이상이면 단위 표 pathspec 열에 저장소별로 적고, 커밋도 저장소별로. 다른 세션의 `.gitignore`·정책 변경으로 미추적이 되면 이월 항목에 기록 | 이전 계획에서 테스트 파일이 조용히 미추적됨 |
| R11 | 다중 세션 흔적(`git status --short` 에 내 것 아닌 변경)이 있으면 diff 는 `git diff HEAD -- <path>`, 커밋은 `scripts/commit-unit.sh` 2단계 — `prepare <repo> <msg-file> <path>...`(임시 인덱스에 `read-tree HEAD` → 내 경로만 add → `write-tree` → `diff --stat` 출력 후 멈춤) → 사람이 stat 을 읽고 내 파일만인지 확인 → `finish <repo>`(`commit-tree -p OLD` → `update-ref <new> <old>`, old 가 다르면 실패 → 공유 인덱스 `reset -q -- <paths>`). 함정: ① 같은 파일에 남의 hunk 가 섞이면 내 hunk 만 패치로 뽑아 **HEAD 기준** blob 에 적용한다(인덱스의 낡은 blob 에 적용하면 남의 커밋을 되돌린다) ② `git add` 뒤 남의 커밋으로 HEAD 가 움직이면 내 인덱스 blob 이 낡아 남의 변경을 되돌리는 hunk 가 생긴다 — 커밋 직전 `git log -1` 로 HEAD 를 다시 확인한다 ③ 임시 인덱스로 커밋한 신규 파일은 공유 인덱스에 없어 `D `(삭제)로 보인다 — finish 의 `reset -q -- <paths>` 가 그래서 필요하다 ④ 검증과 커밋을 한 호출로 묶지 않는다(출력에 남의 파일이 보여도 이미 커밋된 뒤다) ⑤ `git stash`·`reset --hard` 금지 | 공유 인덱스 오염 |
| R12 | 문서 분량 상한: BRIEF 8KB(정본은 절 번호 인용) · REPORT 표 3개 + 400단어 · INDEPENDENT_REVIEW 판정·발견 표·실행 명령만 · 인계 문서 이월 항목당 한 줄 120자, 해소 즉시 삭제, 막지 않는 minor 는 `DEBT.md` | 09-16 계획 REPORT 1,000~5,300단어·검수서 700~3,500단어, 다음 세션은 읽지 않는 문서 |

## 진행률·남은 시간 산정

- 진행률 = 기준선 + Σ(완료 단위 가중치). 가중치 열이 비면 (100 − 기준선) / 단위 수 로 균등. ±10%p 로 보고, 파일·테스트 개수로 환산하지 않는다.
- 남은 시간 = 최근 완료 단위들의 `종료 시각` 간격 중 4시간 초과(밤샘·대기)를 제외한 값의 중앙값 × 남은 단위 수, 범위는 1·3사분위 × 남은 단위 수. 커밋이 없는 단위도 종료 시각은 적는다.

## 증거 디렉터리

`docs/relay/<plan>/<unit>/` 에 `BRIEF.md`·`REPORT.md`·`INDEPENDENT_REVIEW.md`·테스트/lint 로그. 인계 문서는 이 디렉터리를 가리키기만 한다. 인계 문서 스냅샷은 `docs/relay/<plan>/archive/HANDOFF.#N.md`(rotate 마다 자동), 미해소 minor 는 `docs/relay/<plan>/DEBT.md`.
