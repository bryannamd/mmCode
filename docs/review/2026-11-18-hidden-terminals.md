# 숨긴 터미널 시험과 교차 검토 (2026-11-18)

계기: 한 세션(2026-EBS Wiki 탭)이 판정 스크립트 6개에 패널 라벨을 붙여 동시에 띄웠다. 패널 6개가 한꺼번에 떠서 화면으로 확인할 수 없었다. 사용자 지시: 패널은 3개까지, 넘으면 패널을 열지 않고 진행. 그리고 숨겨도 입력 대기·종료·알림이 확실한지 교차 검토.

정리한 절차: `plugins/mmcode/skills/relay/references/terminals.md`.

## 직접 실행한 시험 (mmCode 세션 t3d, herdr-core)

| 시험 | 결과 |
|---|---|
| 라벨 없이 띄운 bash에 `hc read`·`hc send` | 읽기와 입력 모두 됨 |
| 숨긴 bash가 `exit 0` | 부모에게 `<hc>t7s cb-ok exited (exit 0). Last lines: ok</hc>` |
| 숨긴 bash가 `exit 3` | 부모에게 `exited (exit 3)`와 마지막 출력 |
| 숨긴 bash를 내가 `hc kill` | 알림 없음. `state: finished`, `signal: 1` |
| 숨긴 부모 bash 안에서 띄운 자식, 부모를 `hc kill` | 자식도 `finished`(`signal: 1`). 자식의 `die_with_parent: true` |
| 숨긴 bash가 `read`로 입력 대기 | `hc wait --timeout 20`이 `reason: timeout`만 돌려줌. 알림 없음 |
| 숨긴 agy가 막힘 | 부모에게 `<hc>t7n rv-panel-agy is blocked (auth)</hc>` 알림 |
| 신뢰 안 된 폴더에서 숨긴 claude | `hc wait`가 바로 `blocked`, `hc get`의 `status`: `kind: permission`, `msg: trust this folder`. 승인하지 않고 닫음 |
| 숨긴 터미널에 `hc label … herdr.space=… herdr.tab=…` | `herdr-app ls`에서 패널 0개 → 1개 |
| 꺼낸 뒤 `hc label … herdr.space= herdr.tab=` | 패널이 남음(다시 숨겨지지 않음) |

## 교차 검토

| 회차 | codex | agy |
|---|---|---|
| 1 | FAIL: 스크립트 입력 대기를 사용자가 모르는 경로, 대기 반환과 완료 구분, 세는 기준, 일괄 규칙 불일치 | FAIL: 입력 대기 무한 블로킹, 고아 터미널, 세는 기준·규칙 충돌, 알림 시점 |
| 2 | FAIL: 복구 절차가 흩어짐, 꺼내기가 3개 한도를 넘김, `hc wait` 예시에 제한 시간 없음 | PASS(이번 개선: 같은 `hc wait` 예시) |

2회차 지적 반영: 절차를 `terminals.md` 한 곳에 모으고 전역 문서는 이 파일을 가리키게 했다. 패널이 3개면 꺼내지 않고 `hc attach <주소>`를 안내한다. `CODEX_VERIFY.md`의 대기 예시에 `--timeout`을 넣었다. 고아 터미널은 `die_with_parent` 기본값으로 생기지 않음을 시험으로 확인했고, `--no-parent` 터미널은 숨기지 않게 했다.

## 보장하지 못하는 것

- `hc attach`로 사용자가 숨긴 터미널에 들어가 입력하는 경로는 도움말만 읽었고 실행하지 않았다.
- 스크립트를 `< /dev/null`로 띄우면 입력 대기 대신 실패로 끝난다는 것은 일반적인 동작이고, 이번에 시험하지 않았다.
- herdr-core 판이 바뀌면 알림 형식이 달라질 수 있다.

## 절차 파일 교차 검토 (`terminals.md`)

| 회차 | codex | agy |
|---|---|---|
| 1 | FAIL: `/dev/null` 실패 보장 단정, `first_message.sent` 뒤 재전송 없음, `reason: message` 뒤 재대기 없음, 알림 꺼짐·지연, 시험과 도움말 구분 | FAIL: 미검증 단정, 재대기 없음, `hc attach` 실행 위치·빠져나오기, 스크립트 사유, 패널 수 표현, 취소 처리 |
| 2 | FAIL(P2 2건): 에이전트 종료 알림은 시험하지 않음, 취소를 모두 `미실행`으로 보고 | PASS |

2회차 P2 2건은 문장으로 고쳤다(시험 범위 명시, 취소 보고를 `미실행`·`중단`으로 구분). 회차 상한 2회라 3회차 검토는 하지 않았다.
