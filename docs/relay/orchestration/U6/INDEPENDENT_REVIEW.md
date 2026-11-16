# U6 독립 검수

대상: 단위 U6 "auto 가 같은 단계 명령과 같은 기록을 쓴다"(`eval-goal.sh`, `phase.sh`, 시험, relay 문서). 검수자: 깨끗한 맥락의 claude 하위 에이전트(opus). 날짜: 2026-11-16.

## 1회차: FAIL

필수 수정 1건: 커밋 뒤 단위가 멈추면 git 머지는 되고 완료 기록만 거부됐다. 그 뒤 `cleanup`까지 가도 기록이 바로잡히지 않았다(재현).

조치: `u_merge`가 기존 머지 전 검사 뒤, git 머지 앞에서 `phase.sh ready`를 본다. `u_cleanup`이 자산을 치우기 전에 빠진 완료 기록을 적는다. 이번 개선 7건 가운데 6건 반영(시험 3건, rules.md R14 ⑦·⑩, R15 ① "그 단위만 남긴다"를 `phase.sh ask`로). `discard`가 resume 뒤 끊긴 경우는 후속 제안으로 남겼다.

## 2회차: FAIL

1회차 필수 수정은 해결 확인. 새 필수 수정 1건: 1회차 조치에서 넣은 `u_start` 예외 때문에 손으로 `진행`이라 적은 행은 열린 정지 지시가 있어도 시작됐다(재현).

조치: 예외 분기를 없앴다. `phase.sh move build`가 거부하면 예외 없이 시작하지 않는다. 시험 1건 추가. 문서 문구 2건 수정. 정리 때 완료 기록 보충을 잡는 시험은 더하지 않았다(후속 제안).

## 회차 상한 처리

2회차 뒤에도 필수 수정이 남아 교차 검토로 정했다(결정 D4, `DECISION_Q2.md`): 계획자 나, codex 나, agy 가. "바뀐 한 곳만 같은 검수자에게 한 번 더 확인받는다"로 진행했다. 되돌리는 방법: 추가 확인을 무효로 하고 U6 커밋을 되돌려 결정 대기로 남긴다.

## 추가 확인(바뀐 한 곳만): PASS

손으로 `진행`이라 적은 행은 정지 지시가 있어도 없어도 시작이 거부되고 워크트리와 브랜치가 생기지 않는다. 정상 시작, `direct resume` 뒤 시작, `phase.sh resume` 뒤 시작은 그대로다. 단계 전환 뒤 워크트리 생성 전에 끊긴 경우는 장치를 두지 않고 `phase.sh move <단위> queued --reason` 뒤 다시 시작한다(R14 ③에 적었다).

## 변형 점검

- 1회차: `unit commit`의 `ready` 삭제, `phase_done`의 중복 방지 삭제, `ready`가 멈춘 단위 통과 → 모두 잡음. `c.reload()` 삭제 → 못 잡음(2회차에 시험 추가).
- 2회차: `u_merge`의 `ready` 삭제 → 잡음. `u_cleanup`의 `phase_done` 삭제 → 못 잡음(후속 제안).
- 추가 확인: `u_start`의 거부 무시 → 5개 시험 실패로 잡음.

## 실행 결과

- `bash tests/relay/eval-goal.test.sh`: 통과 216 · 실패 0.
- `bash tests/relay/phase.test.sh`: 42개 통과. `status.test.sh` 9개, `rotate.test.sh` 29개(일꾼 실행), `scripts/check.sh` 9개.

## 남은 것(후속 제안)

- `discard`가 resume 뒤 끊기면 손으로 `phase.sh move <단위> queued --reason`을 실행한다.
- 정리 때 완료 기록 보충을 잡는 시험이 없다.
- 시험 `#7` 앞의 `sleep 5`: 제한 시간 1초 시험이 부하에 약하다. 원인은 확정하지 못했다.
- 사용자가 `phase.sh`를 직접 부르는 동안 `eval-goal.sh`가 인계 문서를 고치면 한쪽 쓰기가 사라질 수 있다(잠금이 둘이다. 이전부터 있던 문제).
