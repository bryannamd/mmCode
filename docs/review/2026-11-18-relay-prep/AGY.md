# 교차 검토 결과: relay auto 사전 조건·시간 상한·교체 실패 문구

## 판정
PASS

## 검토 기준별 확인 결과

### 1. 권한 경계
- 기존 설정 보존: `load_settings`가 `permissions.deny`, `env` 등 기존 JSON 구조를 그대로 유지합니다. `allow` 배열의 맨 뒤에만 `"Bash"`를 추가하고 제거합니다. 사용자가 원래 설정한 `"Bash"`는 `bash_allowed`가 감지하여 `prep` 대상에서 제외하므로 `unprep`도 건드리지 않습니다.
- 기록 선행 보장: `cmd_prep`는 `settings.local.json`을 수정하기 전에 인계 문서 `## 종료 시 제거` 절에 기록을 먼저 저장합니다. 기록 없이 권한만 남는 경로는 없습니다.
- 전역 설정 불변: `trusted_dirs`는 `~/.claude.json`을 읽기 전용으로만 참조합니다. 스크립트가 전역 설정 파일을 수정하는 경로는 없습니다.

### 2. 실패 시 안전
- 원자적 쓰기: `write_atomic`이 임시 파일 생성 뒤 `os.replace`로 원자적 교체를 수행하므로 파일 손상 위험이 없습니다.
- 손상 JSON 보호: `load_settings`에서 문법 오류나 `allow` 타입 불일치를 감지하면 `Blocked`를 발생시키고 수정을 중단합니다.
- 동시 실행 보호: 인계 문서 편집은 `c.locked()`(`goal/.lock`) 잠금 안에서 수행합니다.
- 중단 복구: `prep`이나 `unprep` 실행 도중 프로세스가 끊겨도, 다음 실행에서 기존 기록을 바탕으로 멱등하게 복구하거나 잔여 기록을 안전하게 정리합니다.

### 3. 시간 계산
- 중단 중 시간 정지: `stopped_at`을 기준으로 경과 시간을 차감하므로 중단 상태에서 경과 시간(`elapsed`)이 흐르지 않습니다.
- 중단 해제 누적: `clear-stop`과 `state set stopped_reason ""` 모두 `unpause`를 호출하여 중단 구간을 `paused_sec`에 누적 정수로 더하고 `stopped_at`을 삭제합니다. 중단과 재개가 반복되어도 시간 계산이 어긋나지 않습니다.
- 기존 형식 호환: 새 키(`paused_sec`, `stopped_at`)가 없는 기존 `state.json`은 0 및 `None`으로 안전하게 처리되어 기존 벽시계 방식으로 정상 동작합니다.

### 4. 시험 검증
- 시간 정지, 누적 합산, 중복 중단 시 최초 시각 유지, 기존 `state.json` 호환성을 검증합니다.
- 폴더 신뢰 누락/통과, Bash 허용 누락/통과, 중복 `prep` 방지, 기존 Bash 보존, 설정 파일 신규 생성/비우기 처리를 검증합니다.
- 세션 교체 준비 실패 시 `hc get`의 `status`, `kind`, `msg` 추출 및 폴더 신뢰 안내 문구 출력을 모의 상태로 검증합니다.

---

## 지적

1. 등급: 이번 개선
- 위치: `eval-goal.sh:1887`
- 문제: `cmd_unprep`의 파일 쓰기 호출(`write_atomic`)이 예외 처리 블록 밖에 있습니다.
- 근거: 쓰기 권한 부족 등으로 `write_atomic`이 실패하면 `OSError`가 발생하여 스크립트가 즉시 비정상 종료합니다. `try...except Blocked` 범위를 `write_atomic`까지 확장하거나 `(Blocked, OSError)`를 함께 잡아야 실패한 파일 목록을 `bad`에 남기고 나머지 파일을 계속 처리할 수 있습니다.

2. 등급: 이번 개선
- 위치: `eval-goal.sh:1806`
- 문제: `PREP` 정규식이 줄 앞 공백을 허용하지 않습니다.
- 근거: `PREP = re.compile(r'- prep: (.+) permissions\.allow "Bash"')`는 줄 시작 문자가 반드시 `-`여야 합니다. 사용자 편집이나 마크다운 서식 정리기가 목록 앞에 들여쓰기 공백을 넣으면(`  - prep: ...`) 정규식이 일치하지 않아 `unprep`가 항목을 건너뜁니다. `re.compile(r'^\s*-\s*prep:\s*(.+?)\s+permissions\.allow\s+"Bash"')`로 유연하게 검사하는 구성이 안전합니다.

3. 등급: 이번 개선
- 위치: `eval-goal.sh:118-120`
- 문제: 시스템 시계 변경 시 `elapsed`가 음수를 반환할 수 있습니다.
- 근거: `return max(0.0, e - max(0.0, since(st['stopped_at']))) if st.get('stopped_at') else max(0.0, e)` 형태로 하한을 두면 `status-json`의 `elapsed_sec`에 음수가 기록되는 현상을 방지합니다.

4. 등급: 후속 제안
- 위치: `eval-goal.sh:1829-1836`
- 문제: 복수 저장소 설정에서 서로 다른 slug가 동일한 실제 디렉터리 경로를 참조하면 `todo`에 동일한 파일이 중복 등록됩니다.
- 근거: 경로 집합(`seen = set()`)을 활용해 파일 단위로 중복을 걸러내면 동일 설정 파일에 대한 중복 쓰기와 인계 문서 내 중복 기록을 방지할 수 있습니다.

5. 등급: 후속 제안
- 위치: `tests/relay/eval-goal.test.sh:425-443`
- 문제: 복수 저장소 환경과 손상된 JSON 환경에 대한 `prep`/`unprep` 시험이 비어 있습니다.
- 근거: 단일 저장소 케이스만 시험하고 있습니다. 다중 저장소 환경 처리와 `settings.local.json` 문법 오류 시 `Blocked`로 원본을 보존하는 처리를 검증하는 시험을 추가할 필요가 있습니다.

---

## 뺄 것

- 대상: `eval-goal.sh:1857-1861` (`cmd_prep` 내부의 폴더 신뢰 검사 및 안내 출력)
- 근거: `prep` 명령의 고유 목적은 `settings.local.json`에 Bash 허용을 추가하고 인계 문서에 기록하는 작업입니다. 폴더 신뢰 누락 검사는 직전의 `eval-goal.sh check`가 이미 `FAIL 폴더 신뢰`로 동일한 안내를 출력하고 거부합니다. 또한 `prep` 직후 호출되는 `eval-goal.sh init` 역시 `do_check`를 호출하여 재확인합니다. `prep`가 자체적으로 폴더 신뢰를 수정할 수 없고 실패해도 정상 종료(exit 0)하므로, 이 5줄 블록은 단순 중복 출력에 해당합니다. 지워도 기능과 안전성에 영향이 없습니다.
