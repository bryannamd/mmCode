판정: FAIL

1회차 필수 수정 중 1건은 해결됐다. 3건은 일부 경로가 여전히 미해결이다.
이번 변경에서 새로 생긴 필수 수정은 1건이다.
먼저 저장소별 직렬화와 기록 절의 코드 펜스 해석을 고쳐야 한다.

## 1회차 필수 수정 재확인

1. [P1·필수 수정] 동시 prep·unprep: 미해결.

   근거: `plugins/mmcode/skills/relay/scripts/eval-goal.sh:1959`, `:1966`, `:467`, `:1905`.

   같은 계획의 두 명령은 이제 `.driver`로 직렬화한다.
   그러나 잠금 위치는 저장소가 아닌 `docs/relay/<계획>/goal/.driver`다.
   같은 저장소를 쓰는 다른 계획은 서로 다른 잠금을 잡는다.
   1회차에서 요구한 저장소별 직렬화가 빠졌다.

   재현:
   1. 같은 저장소에 계획 A와 B를 만든다. 설정에는 `Read`만 둔다.
   2. A의 prep를 마지막 설정 읽기 뒤, 설정 쓰기 전에 멈춘다.
   3. B의 prep를 실제 CLI로 실행한다. 종료 코드 0으로 Bash를 넣는다.
   4. A의 쓰기를 재개한다. 양쪽 인계 문서에 `(적용됨)`이 남는다.
   5. A의 unprep를 실행한다. B의 적용 기록이 남았는데 Bash는 삭제된다.

   별도 시험에서도 B의 `.driver`를 잡은 동안 A의 prep가 성공했다.
   `tests/relay/eval-goal.test.sh:1064`는 같은 계획의 잠금만 시험한다.
   설정과 소유 기록의 갱신에는 같은 저장소에서 공유하는 잠금이 필요하다.

2. [P1·필수 수정] 오래된 설정 사본 덮어쓰기: 미해결.

   근거: `plugins/mmcode/skills/relay/scripts/eval-goal.sh:1897`, `:1905`, `:1934`, `:1942`, `:105`.

   기록 잠금을 기다린 뒤 설정을 다시 읽는 수정은 유효하다.
   그러나 마지막 읽기와 `os.replace` 사이의 변경은 여전히 감지하지 않는다.
   unprep도 설정을 읽은 뒤 전체 JSON을 다시 쓴다.

   재현:
   1. 설정을 `env.A=old`, `allow=[Read]`로 만든다.
   2. prep가 마지막 설정 읽기를 마친 뒤 `write_atomic` 진입점에서 외부 변경을 삽입한다.
   3. 외부 작성자는 `env.A=new`, `allow=[Read, Write]`를 실제 파일에 저장한다.
   4. 원래 `write_atomic`을 계속 실행한다.

   결과: `env.A=old`, `allow=[Read, Bash]`. 사용자 변경 두 개가 사라졌다.
   `tests/relay/eval-goal.test.sh:1069`는 마지막 재읽기 이전의 변경만 시험한다.
   저장소별 잠금과 함께, 읽은 버전이 바뀌면 덮어쓰기를 거부하는 검사가 필요하다.

3. [P1·필수 수정] unprep의 임의 경로·예제 기록 해석: 미해결(경로 제한은 해결).

   근거: `plugins/mmcode/skills/relay/scripts/eval-goal.sh:1826`, `:1831`, `:1818`, `:1924`, `:1937`.

   저장소 밖 임의 경로와 저장소 밖을 가리키는 심볼릭 링크는 이제 거부한다.
   일반적인 백틱 코드 블록도 제외한다.
   그러나 `~~~` 코드 펜스를 인식하지 않아 예제 기록으로 사용자 Bash를 지운다.

   재현:
   1. prep를 실행하지 않고 프로젝트 설정에 `allow=[Read, Bash]`를 둔다.
   2. `## 종료 시 제거` 절에 다음 코드 예제를 넣는다.
   3. `<설정 경로>`에는 해당 저장소의 실제 `.claude/settings.local.json` 경로를 쓴다.

   ````text
   ~~~text
   - prep: <설정 경로> permissions.allow "Bash" (적용됨)
   ~~~
   ````

   실제 CLI의 unprep는 종료 코드 0으로 Bash와 예제 기록 줄을 삭제했다.
   결과는 `allow=[Read]`다. prep가 넣지 않은 사용자 허용을 삭제했다.
   이는 1회차의 코드 예제 오인 문제가 남은 경우다. 새 지적으로 중복 계산하지 않는다.

4. 실패한 prep의 기록으로 사용자 Bash 삭제: 해결.

   근거: `plugins/mmcode/skills/relay/scripts/eval-goal.sh:1896`, `:1906`, `:1908`, `:1929`.

   설정 쓰기 전에는 `(적용 전)`, 성공 뒤에는 `(적용됨)`을 기록한다.
   unprep는 `(적용 전)` 기록을 남기고 종료 코드 1로 거부한다.

   재현 시험에서 설정 쓰기에 `OSError`를 주입했다.
   그 뒤 사용자가 Bash를 직접 넣고 실제 CLI로 unprep를 실행했다.
   사용자 Bash와 `(적용 전)` 기록을 모두 보존했다.
   해당 삭제 결함은 해결됐다. 적용 여부가 불명확하면 자동 제거를 거부하는 동작이다.

## 이번 변경으로 생긴 새 지적

1. [P1·필수 수정] 코드 예제 속 제목을 선택해 prep의 Bash 허용을 회수하지 못한다.

   위치: `plugins/mmcode/skills/relay/scripts/eval-goal.sh:1813`, `:1814`, `:1862`, `:1868`, `:1920`.

   `prep_lines`와 `set_record`는 문서 전체에서 첫 `## 종료 시 제거` 줄을 선택한다.
   제목이 코드 펜스 안인지 검사하지 않는다.
   `prep_lines`는 선택한 제목에서 펜스 상태를 새로 시작한다.
   따라서 예제의 닫는 펜스를 여는 펜스로 오인한다.

   재현:
   1. Bash가 없는 설정과 다음 형식의 인계 문서를 준비한다.

   ````markdown
   ## 참고
   ```markdown
   ## 종료 시 제거
   - 없음
   ```

   ## 종료 시 제거
   - 없음
   ````

   2. 실제 CLI로 prep를 실행한다. 종료 코드 0으로 Bash를 넣는다.
   3. 기록은 실제 제거 절이 아닌 `참고` 절의 예제 뒤에 붙는다.
   4. 실제 CLI로 unprep를 실행한다.

   결과: 종료 코드 0, 출력 `prep 기록 없음`, 설정의 Bash는 그대로다.
   문서에는 `(적용 전)`과 `(적용됨)` 줄이 모두 남지만 `prep_lines`는 빈 목록을 반환한다.
   이전 unprep는 문서 전체의 기록을 읽었으므로 이 잔류 문제는 새 파서에서 생겼다.
   문서 시작부터 펜스 상태를 추적해 실제 제목을 선택해야 한다.
   기록 읽기와 삽입도 같은 절 범위를 사용해야 한다.

## 검증

1. `CHANGES2.diff`와 현재 추적 파일 7개의 전체 diff가 바이트 단위로 일치했다.
   `CHANGES.diff`와 비교해 2회차 변경 범위를 구분했다.
   구현·시험 파일과 실제 사용자 설정은 수정하지 않았다.

2. 실행 결과:

   | 명령 | 통과 | 실패 | 종료 코드 |
   |---|---:|---:|---:|
   | `rtk proxy bash scripts/check.sh` | 9 | 0 | 0 |
   | `rtk proxy bash tests/relay/rotate.test.sh` | 30 | 0 | 0 |
   | `rtk proxy bash tests/relay/eval-goal.test.sh` | 240 | 3 | 1 |
   | `rtk proxy python3 /private/tmp/mmcode-review2-check.py` | 6개 시나리오의 assert 통과 | 0 | 0 |

3. eval-goal의 실패 3건은 1회차와 같은 `#7`·`B6` 자식 프로세스 제한 시간 항목이다.
   `child.pid`를 만들지 못했고, 남은 자식 관련 기대값을 충족하지 못했다.
   `group_left`·`run_one`은 HEAD와 구문 트리가 같다.
   이번 변경이 실패 원인이라는 근거는 확보하지 못했다.
   이번에 추가한 prep·unprep 회귀 시험 6개는 모두 통과했다.

4. 임시 재현 스크립트는 현재 원본 Python 함수들을 로드한다.
   마지막 쓰기 직전의 경합과 설정 쓰기 실패만 호출 지점에서 삽입했다.
   코드 예제 두 사례와 실패 뒤 unprep는 실제 CLI로도 재현했다.
   같은 저장소의 다른 계획 잠금도 실제 CLI로 검증했다.
   재현 스크립트: `/private/tmp/mmcode-review2-check.py`.
   임시 저장소: `/private/var/folders/ht/xyh98lwx0119s19thb8hs2w40000gn/T/mmcode-review2-t0x061la/`.

후속 제안: 없음. 요청한 4건과 이번 변경의 회귀만 다뤘다.

미검증: 실제 hc·Claude 신뢰 창, 전원 손실, 전체 시험 묶음.
잔여 위험: 사용자 설정 손실, 사용자 Bash 허용 삭제, 종료 후 전체 Bash 허용 잔류.
