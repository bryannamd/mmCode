# <plan> 실행 계획 — <YYYY-MM-DD>

## 목적·범위
- 한 줄.

## 정본·설계 문서
- 경로 목록(단위별 완료 기준이 가리키는 절 번호 포함).

## 고정 규칙
relay 스킬 `references/rules.md` R1~R12 적용. 이 계획만의 예외:
- (없으면 "없음")

## 검증 명령·환경
- 단위 테스트: `<명령>`
- 통합(2~3단위마다): `<명령>` (환경변수·포트·NODE_PATH 등)
- lint: `<명령>`

## 단위 표 (상태는 HANDOFF.md 상태표가 정본 — 여기엔 정의만)

| 단위 | 내용 | 파일 | 선행 | 모델 | 병렬 | 검수 | pathspec |
|---|---|---|---|---|---|---|---|
| U1 | | | — | sonnet | ✘ | sonnet | repo:path |

## 종료 시 제거할 임시 설정
- (additionalDirectories / allow / scratch)
