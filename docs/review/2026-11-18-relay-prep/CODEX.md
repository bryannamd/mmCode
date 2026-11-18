판정: FAIL

권한 설정의 동시 갱신과 중단 복구에 필수 수정 4건이 있다.
먼저 prep·unprep의 설정 변경과 소유 기록을 함께 보호해야 한다.

지적

1. [필수 수정] 동시 prep·unprep가 기록 없는 Bash 허용을 남긴다.

   위치: `plugins/mmcode/skills/relay/scripts/eval-goal.sh:1852`, `:1855`, `:1869`, `:1895`, `:1904`.

   prep는 인계 기록을 쓴 뒤 잠금을 풀고 설정을 쓴다.
   unprep는 그 사이에 실행될 수 있다.
   prep·unprep는 명령 전체를 보호하는 `.driver`에도 포함되지 않는다.

   재현 순서:
   1. Bash가 없는 설정에서 prep가 인계 기록을 쓴다.
   2. 설정을 쓰기 전에 unprep를 실행한다.
   3. unprep는 Bash가 없으므로 기록만 지운다.
   4. prep가 계속 실행되어 Bash를 넣는다.

   실행 결과: `Bash=true, prep_record=false`.
   이후 unprep는 제거할 기록을 찾지 못한다.
   원본 함수의 `c.edit(rec)` 반환 직후 unprep를 삽입해 재현했다.
   이 시점에는 인계 잠금이 이미 풀려 있다.

   수정: 저장소별 잠금으로 설정과 기록의 읽기·갱신 전체를 직렬화한다.
   같은 저장소의 다른 계획도 같은 잠금을 사용해야 한다.
   위 순서를 고정하는 회귀 시험이 필요하다.

2. [필수 수정] 오래된 설정 사본이 사용자의 변경을 덮어쓴다.

   위치: `plugins/mmcode/skills/relay/scripts/eval-goal.sh:1836`, `:1855`, `:1875`, `:1887`.

   prep는 설정을 미리 읽고 인계 기록을 쓴 뒤, 처음 읽은 설정 전체를 저장한다.
   기록 잠금을 기다리는 동안 설정이 바뀌어도 다시 읽지 않는다.
   unprep도 설정을 읽고 쓰는 구간을 보호하지 않는다.
   `write_atomic`은 반쪽 파일을 막지만, 오래된 값의 덮어쓰기는 막지 못한다.

   재현: prep가 기록을 쓴 직후 사용자가 `env.A`를 `old`에서 `new`로 바꾼다.
   같은 시점에 `permissions.allow`에 `Write`도 넣는다.
   prep가 끝나면 `env.A=old`, `allow=[Read, Bash]`가 된다.
   사용자 변경 두 개가 모두 사라졌다.

   수정: 설정 갱신을 잠금으로 보호하고, 최신 내용에 필요한 항목만 반영한다.
   협조하지 않는 외부 작성자의 변경도 감지하면 덮어쓰기를 거부해야 한다.
   현재 정상 왕복 시험(`tests/relay/eval-goal.test.sh:1034`)은 이 손실을 잡지 못한다.

3. [필수 수정] unprep가 문서 속 임의 경로를 수정한다.

   위치: `plugins/mmcode/skills/relay/scripts/eval-goal.sh:1806`, `:1869`, `:1887`.

   unprep는 문서 전체에서 `- prep:` 줄을 찾는다.
   `## 종료 시 제거` 절인지, 코드 예제인지 구분하지 않는다.
   경로가 이 계획의 저장소 설정 파일인지도 검사하지 않는다.

   재현: `## 참고`의 코드 블록에 다음 줄을 넣는다.

   ```text
   - prep: /private/tmp/<fixture>/fake-home/.claude.json permissions.allow "Bash" (sample)
   ```

   대상 JSON에 `permissions.allow=[Read, Bash]`를 둔다.
   실제 CLI로 `unprep`를 실행하면 종료 코드 0으로 `[Read]`로 바뀐다.
   이 파일은 저장소 밖이며 prep가 만든 기록도 아니다.

   따라서 `~/.claude.json`도 경로만 일치하면 쓰기 대상이 될 수 있다.
   `trusted_dirs()` 자체는 읽기 전용이지만, unprep 경로에는 그 보장이 없다.
   실제 사용자 전역 설정은 건드리지 않고 가짜 홈에서 재현했다.

   수정: 제거 절의 실제 기록만 읽는다.
   경로는 계획에 등록된 저장소의 `.claude/settings.local.json`으로 제한한다.
   심볼릭 링크로 범위를 벗어나는 경로도 거부해야 한다.

4. [필수 수정] 실패한 prep의 기록으로 사용자 Bash 허용을 지운다.

   위치: `plugins/mmcode/skills/relay/scripts/eval-goal.sh:1837`, `:1852`, `:1855`, `:1882`.

   인계 기록을 먼저 쓰므로 설정 쓰기가 실패해도 소유 기록은 남는다.
   unprep는 그 기록만으로 현재 Bash 허용이 prep 소유라고 판단한다.

   재현 순서:
   1. Bash가 없는 설정에서 prep를 실행한다.
   2. 인계 기록 저장 뒤 설정 쓰기에 `OSError`를 주입한다.
   3. 사용자가 설정에 Bash를 직접 넣는다.
   4. unprep를 실행한다.

   실행 결과: prep가 넣지 않은 사용자 Bash 허용이 삭제된다.
   기록과 실제 적용 상태를 구분하지 않아 중단 후 복구가 안전하지 않다.

   수정: 적용 전 기록만으로 자동 삭제하지 않는다.
   적용 여부와 예상 설정 상태를 검증하고, 소유권이 불명확하면 기록을 남긴 채 거부한다.
   설정 쓰기 실패와 재실행을 포함한 회귀 시험이 필요하다.

검증

1. 제공된 `CHANGES.diff`와 현재 7개 파일의 diff가 바이트 단위로 일치했다.
   변경 함수, 호출 경로, 설정 저장 함수, relay 규칙과 시험을 함께 읽었다.
   한 계획의 정상 실행과 같은 저장소의 명령 중첩을 검토 범위로 삼았다.

2. 기존 시험 결과:

   | 실행 명령 | 통과 | 실패 | 종료 코드 |
   |---|---:|---:|---:|
   | `rtk proxy bash tests/relay/eval-goal.test.sh` | 234 | 3 | 1 |
   | `rtk proxy bash tests/relay/rotate.test.sh` | 30 | 0 | 0 |
   | `rtk proxy bash tests/relay/phase.test.sh` | 42 | 0 | 0 |
   | `rtk proxy bash tests/relay/status.test.sh` | 9 | 0 | 0 |

3. eval-goal의 실패 3건은 기존 `#7`·`B6` 자식 프로세스 제한 시간 시험이다.
   최초 실행에서는 `child.pid`가 생성되지 않았다.
   해당 사례만 분리하자 현재 코드와 HEAD 코드 모두 2개 통과, B6 1개 실패였다.
   두 코드 모두 남은 프로세스 번호를 조회하지 못했다.
   관련 `group_left`·`run_one` 구현은 HEAD와 동일하다.
   최초 실패 3건 전체의 원인이 이번 변경이라는 근거는 없다.

4. 이번 eval-goal 추가 시험 21개는 모두 통과했다.
   반복 중단·재개, 중복 stop, 옛 state.json의 시간 계산도 통과했다.
   새 키가 없는 옛 상태는 기존 벽시계 계산을 유지한다.
   stop 전에 발생한 승인 창 대기는 계속 시간에 포함된다(`references/rules.md:44`).

5. 잘못된 JSON을 실제 CLI로 시험했다.
   prep는 종료 코드 1로 거부했고, 설정과 인계 문서 바이트를 보존했다.
   파일 자체의 원자적 저장과 두 파일 사이의 일관성은 구분해야 한다.

6. 지적 1·2·4는 임시 저장소에서 원본 함수를 로드해 호출 사이 동작과 실패를 삽입했다.
   지적 3은 실제 CLI로도 재현했다.
   기존 시험에는 이 네 사례가 없어 모두 놓친다.
   소스·시험 파일과 실제 사용자 설정은 수정하지 않았다.

뺄 것

1. `plugins/mmcode/skills/relay/scripts/eval-goal.sh:1857`의 폴더 신뢰 재검사·출력 5줄.
   폴더 신뢰 검사는 이미 check와 init의 `prereqs`가 맡는다.
   prep에서는 Bash 설정 변경만 맡기면 같은 안내를 중복할 필요가 없다.

미검증·잔여 위험: 실제 hc·Claude 신뢰 창과 전원 손실은 시험하지 않았다.
필수 수정 전에는 기록 없는 전체 Bash 허용과 사용자 설정 손실이 발생할 수 있다.
