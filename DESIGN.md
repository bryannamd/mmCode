---
name: mmCode 프로젝트 모니터
description: 메뉴 막대의 고양이와 폭 380pt의 작업 모니터. 답이 필요한 프로젝트와 그 이유를 먼저 보여 준다.
colors:
  ink: "#232845"
  ink-2: "#39406b"
  ink-3: "#4a548c"
  paper: "#fffdf4"
  pink: "#ff4f9a"
  green: "#3fc46f"
  amber: "#ffc23d"
  red: "#ef4b4b"
  on-ink-sub: "#c9d3ee"
  paper-sub: "#4d5677"
  paper-line: "#d9d6c4"
  box: "#eab85f"
  box-2: "#b9822f"
  box-done: "#93dba8"
  box-done-2: "#3f9a5f"
  card-night: "#aab3d6"
  wall: "#c8eee0"
  wall-2: "#8fd6c2"
  baseboard: "#5aa896"
  floor: "#f4bd6c"
  plank: "#dd9c47"
  wood: "#cf7c3c"
  wood-2: "#a35a26"
  screen-on: "#eafcff"
  screen-off: "#55608a"
  code: "#2f8fe8"
  sky: "#8fd0ff"
  lamp-on: "#ffe27a"
  night-ink: "#141833"
  night-wall: "#2f3b76"
  night-wall-2: "#253066"
  night-floor: "#8a6248"
  night-sky: "#141a3c"
typography:
  ground-title:
    fontFamily: "Jua, Apple SD Gothic Neo, Noto Sans KR, Malgun Gothic, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.2
  panel-name:
    fontFamily: "Jua, Apple SD Gothic Neo, Noto Sans KR, Malgun Gothic, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1
    letterSpacing: "0.01em"
  button:
    fontFamily: "Jua, Apple SD Gothic Neo, Noto Sans KR, Malgun Gothic, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1
  list-heading:
    fontFamily: "Jua, Apple SD Gothic Neo, Noto Sans KR, Malgun Gothic, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.2
  nav-button:
    fontFamily: "Jua, Apple SD Gothic Neo, Noto Sans KR, Malgun Gothic, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1
  sign:
    fontFamily: "Jua, Apple SD Gothic Neo, Noto Sans KR, Malgun Gothic, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: "15px"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, Apple SD Gothic Neo, Noto Sans KR, Malgun Gothic, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.3
  field:
    fontFamily: "-apple-system, BlinkMacSystemFont, Apple SD Gothic Neo, Noto Sans KR, Malgun Gothic, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.3
  caption:
    fontFamily: "-apple-system, BlinkMacSystemFont, Apple SD Gothic Neo, Noto Sans KR, Malgun Gothic, sans-serif"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: 1.3
rounded:
  sign: "2px"
  badge: "3px"
  nav: "5px"
  hit: "6px"
  field: "7px"
  button: "8px"
  bubble: "9px"
  panel: "10px"
spacing:
  panel-width: "480px"
  roof-height: "28px"
  scene-height: "216px"
  ground-height: "56px"
  roof-inset: "8px"
  ground-inset-x: "10px"
  ground-inset-y: "6px"
  button-gap: "8px"
  list-inset: "12px"
  hit-min: "40px"
components:
  roof:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    height: "{spacing.roof-height}"
    padding: "0 8px"
  ground:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.ground-title}"
    height: "{spacing.ground-height}"
    padding: "6px 10px"
  ground-turn:
    backgroundColor: "{colors.pink}"
    textColor: "{colors.ink}"
  nav-button:
    backgroundColor: "{colors.ink-2}"
    textColor: "{colors.paper}"
    typography: "{typography.nav-button}"
    rounded: "{rounded.nav}"
    padding: "4px 8px 3px"
  nav-button-hover:
    backgroundColor: "{colors.ink-3}"
    textColor: "{colors.paper}"
  nav-button-pressed:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
  alert-pill:
    backgroundColor: "{colors.pink}"
    textColor: "{colors.ink}"
    typography: "{typography.caption}"
    rounded: "{rounded.bubble}"
    padding: "4px 8px"
  button-primary:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    rounded: "{rounded.button}"
    height: "32px"
    padding: "1px 12px 0"
  button-primary-turn:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.pink}"
  button-outline:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.button}"
    rounded: "{rounded.button}"
    height: "32px"
    padding: "1px 12px 0"
  button-outline-turn:
    backgroundColor: "{colors.pink}"
    textColor: "{colors.ink}"
  face-icon:
    backgroundColor: "{colors.paper}"
    size: "36px"
  stage-sign:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.sign}"
    rounded: "{rounded.sign}"
    padding: "1px 6px 0"
  stage-sign-night:
    backgroundColor: "{colors.card-night}"
    textColor: "{colors.ink}"
  bubble:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.sign}"
    rounded: "{rounded.bubble}"
    padding: "1px 7px 0"
  message-field:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.field}"
    rounded: "{rounded.field}"
    height: "26px"
    padding: "0 8px"
  tag:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sign}"
    padding: "1px 5px 0"
  tag-turn:
    backgroundColor: "{colors.pink}"
    textColor: "{colors.ink}"
  tag-halt:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
  list:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    height: "{spacing.scene-height}"
    padding: "8px 12px 12px"
---

# Design System: mmCode 프로젝트 모니터

## macOS 앱 · 작업 모니터

사용자가 첫 화면에서 알고 싶은 것은 내 답을 기다리는 프로젝트와 그 이유다. 폭 380pt의 상단에 프로젝트 이름, 요청 종류, 실제 질문과 가능한 답을 모은다. 선택지를 읽을 수 있는 요청은 이 자리에서 답한다. 할 일이 없으면 그 사실을 먼저 말하고 현재 작업 인원을 보여 준다.

프로젝트 목록은 확인 필요, 작업 중, 그 밖의 상태 순이다. 행 전체가 상세 보기 버튼이다. 각 행에는 프로젝트명, 상태 글자, 작업이나 담당자가 있다. ‘확인 필요’로 요청만 좁힐 수 있고 프로젝트가 일곱 개 이상이면 이름 검색을 제공한다. 프로젝트 상세에서는 담당자를 눌러 메시지를 보낸다. 작업 기록과 픽셀 사무실은 이름이 적힌 버튼으로 연다.

제목은 시스템 글꼴 19pt, 질문과 설명은 13pt, 프로젝트명은 14pt다. 요청은 연한 살구색, 평상시는 세이지색을 쓴다. 고양이·개·개구리 초상은 기존 하네스와 털색을 이어받고, 명단용으로 표정을 크게 그린다. 메뉴 막대는 기존의 23×18pt 단색 고양이 아이콘을 사용한다.

아래 토큰과 항목은 초기 HTML 시안 `docs/plans/monitor-office-mock.html`의 기록이다. 네이티브 앱의 현재 기준은 위 절과 `monitor/Sources/`에 있다.

## Overview

**Creative North Star: "단면도 그림책"**

패널 자체가 건물의 단면이다. 지붕은 길 찾기를 맡는다. 방은 현황을 보여 준다. 지반은 사용자가 나설 일을 말한다. 사용자는 지반의 색으로 나설지 말지를 안다.

그림은 굵은 남색 외곽선과 채도 있는 단색 면으로 그린다. 픽셀 동물이 사무실에서 일한다. 장소가 단계이고, 상자가 단위다. 아무 일이 없으면 화면이 조용하다. 상태 점과 줄 목록으로 된 메뉴 막대 표준 배치를 쓰지 않는다.

정보의 자리는 고정한다. 내용만 바뀐다. 낮과 밤에 틀은 그대로이고 장면의 색만 바뀐다.

**Key Characteristics:**
- 패널은 지붕, 장면, 지반의 세 층이다.
- 분홍은 "당신 차례"라는 한 가지 뜻만 가진다.
- 움직이는 것은 모두 정보다.
- 같은 정보를 글자 목록으로도 제공한다.
- 그림자는 패널 바깥에만 있다. 패널 안은 평평하다.

## Colors

남색 틀 안에 민트 벽과 살구 바닥이 있고, 분홍 하나가 사용자를 부른다.

### Primary
- **차례 분홍** (`pink`, #ff4f9a): "당신 차례"에만 쓴다. 쓰는 곳은 지반의 바탕, 호출 벨, 주의 표시 판, 지붕의 다른 층 알림, 목록의 멈춤 꼬리표다. 대상 상태는 결정 대기, 단위 막힘, 환경·한도, 입력 대기다.

### Secondary
- **완료 초록** (`green`, #3fc46f): 시험대의 통과 등과 완료 선반의 깃발.
- **진행 호박** (`amber`, #ffc23d): 시험대의 실행 중 등과 평소의 호출 벨.
- **정지 빨강** (`red`, #ef4b4b): 시험대의 실패 등과 문 옆의 사용자 정지 표지판.
- **상자 호박** (`box` #eab85f, 아랫단 `box-2` #b9822f): 대기와 진행 중인 단위.
- **상자 초록** (`box-done` #93dba8, 아랫단 `box-done-2` #3f9a5f): 완료한 단위.

### Neutral
- **남색 잉크** (`ink`, #232845): 지붕, 지반, 외곽선, 종이 위의 글자.
- **남색 2단** (`ink-2`, #39406b): 지붕 버튼의 바탕.
- **남색 3단** (`ink-3`, #4a548c): 지붕 버튼의 hover 바탕, "예시" 표지의 테두리, 목록의 스크롤 막대.
- **종이** (`paper`, #fffdf4): 이름표, 말풍선, 목록의 바탕, 남색 위의 글자.
- **남색 위 보조 글자** (`on-ink-sub`, #c9d3ee): 지붕의 완료 수, 지반의 둘째 줄.
- **종이 위 보조 글자** (`paper-sub`, #4d5677): 목록의 보조 줄, 입력란의 예시 문구.
- **종이 위 구분선** (`paper-line`, #d9d6c4): 목록의 줄 구분선.
- **밤 이름표** (`card-night`, #aab3d6): 밤 장면의 단계 이름표와 건물의 층 이름표.

### 장면 색
- 낮: 벽 `wall`, 벽 아랫단 `wall-2`, 걸레받이 `baseboard`, 바닥 `floor`, 바닥 줄 `plank`, 나무 `wood`와 `wood-2`, 켜진 화면 `screen-on`, 꺼진 화면 `screen-off`, 화면의 코드 줄 `code`, 하늘 `sky`, 켜진 천장등 `lamp-on`.
- 밤: 외곽선 `night-ink`, 벽 `night-wall`, 벽 아랫단 `night-wall-2`, 바닥 `night-floor`, 하늘 `night-sky`.
- 장면 색의 전체 목록은 시안의 `PAL` 표다. 낮(`day`)과 밤(`night`)이 같은 이름을 쓴다. 장면 색을 바꿀 때는 `PAL` 표만 고친다.
- 건물 보기에서는 층마다 벽 색이 다르다. 값은 시안의 `WALLS` 표에 있다. 낮과 밤에 4개씩이다.

### Named Rules
**분홍 한 가지 뜻 규칙.** 분홍 면과 분홍 표시는 "당신 차례"에만 쓴다. 입력 대기(터미널이 사용자의 입력을 기다리는 상태)도 "당신 차례"다. 사용자 정지는 사용자가 건 상태이므로 분홍을 쓰지 않는다. 사용자 정지는 남색 바탕과 빨강 표지판으로 표시한다.

**같은 틀 규칙.** 낮과 밤에 지붕과 지반은 같은 남색(`ink`)이다. 밤에는 장면의 색만 `PAL.night`로 바뀐다. 지반의 얼굴 그림은 밤에도 낮 색으로 그린다.

**색과 모양 규칙.** 상태를 색만으로 구분하지 않는다. 분홍 표시에는 물음표나 느낌표가 함께 있다. 지반과 목록에는 글자가 함께 있다.

## Typography

**Display Font:** Jua (대체: Apple SD Gothic Neo, Noto Sans KR, Malgun Gothic, sans-serif)
**Body Font:** 시스템 글꼴 (-apple-system, BlinkMacSystemFont, 대체는 위와 같음)

**Character:** Jua는 둥근 한글 제목 글꼴이다. 제목, 버튼, 이름표에 쓴다. 문장과 숫자는 시스템 글꼴로 쓴다. Jua는 굵기가 400 하나다.

### Hierarchy
- **지반 제목** (`ground-title`, Jua 400, 17px, 1.2): 지반의 첫째 줄. 질문이나 상태 한 문장. 패널에서 가장 큰 글자다.
- **패널 이름** (`panel-name`, Jua 400, 16px, 1, 자간 0.01em): 지붕의 프로젝트 이름.
- **버튼** (`button`, Jua 400, 14px, 1): 지반의 버튼.
- **목록 제목** (`list-heading`, Jua 400, 14px, 1.2): 목록 보기의 구역 제목. 목록의 이름 글자는 같은 글꼴 13px이다.
- **지붕 버튼** (`nav-button`, Jua 400, 13px, 1): 건물 버튼과 목록 버튼. 건물의 층 이름표도 13px이다.
- **이름표** (`sign`, Jua 400, 12px, 줄 높이 15px): 단계 이름표와 말풍선. 목록의 꼬리표는 같은 글꼴 11px에 줄 높이 14px이다.
- **본문** (`body`, 시스템 400, 12px, 1.3): 패널의 기본 글자. 숫자는 폭이 같은 숫자(`tabular-nums`)로 쓴다.
- **입력** (`field`, 시스템 400, 13px): 메시지 입력란.
- **보조** (`caption`, 시스템 600, 11px): 지반의 둘째 줄, 지붕의 완료 수, 알약 표지, 목록의 보조 줄. 지붕의 완료 수와 "예시" 표지와 목록의 보조 줄은 굵기가 400이다.

### Named Rules
**10pt 바닥 규칙.** 앱 패널(240pt)의 글자는 화면 10pt보다 작게 쓰지 않는다. 지반 제목은 Jua 13pt다(2026-11-17). 시안(480px)의 글자 크기 표는 비율 참고용이다.

**글꼴 두 개 규칙.** Jua는 제목, 버튼, 이름표에만 쓴다. 문장과 숫자에는 시스템 글꼴을 쓴다.

## Layout

패널의 폭은 480px이다. 위에서 아래로 세 층이다.

**앱 패널 크기(2026-11-17 사용자 요청).** 앱은 240×180pt다. 지붕 22pt, 장면 240×108pt(480×216 그림을 0.5배로, 그림 한 칸이 레티나 2px), 지반 50pt다. 지붕과 지반은 화면 pt로 그린다. 앱은 아래 "440px 이하" 규칙을 따른다. 지붕에는 진행 칸과 알림 문구가 없고, 다른 층 알림은 건물 버튼을 분홍으로 칠해 알린다. 지반은 위 줄에 제목, 아래 줄에 작은 글과 버튼(높이 24pt)이다. 장면의 상자 번호는 그리지 않는다.

| 층 | 크기 | 맡은 일 |
|---|---|---|
| 지붕 | 28px | 길 찾기와 다른 층의 알림 |
| 장면 | 480×216 | 사무실이나 건물의 단면. 논리 해상도 240×108을 2배로 확대한다 |
| 지반 | 56px | 지금 보는 층의 일 한 줄과 버튼 |

- 지붕은 왼쪽부터 건물 버튼, 프로젝트 이름, 상자 진행 칸(칸 하나 10×8px), 완료 수, 빈 칸, 다른 층 알림, 목록 버튼, "예시" 표지 순서다. 요소 사이는 8px이고 옆 여백은 8px이다.
- 지반은 왼쪽부터 얼굴 칸(36px 원), 글 두 줄, 버튼 순서다. 요소 사이는 10px이고 여백은 위아래 6px, 옆 10px이다. 버튼 사이는 8px이다.
- 장면은 가로세로 비율 480:216을 지킨다. 캔버스는 보간 없이 확대한다(`image-rendering: pixelated`).
- 목록 보기는 장면 자리(높이 216px)에 놓인다. 지반은 목록 보기에서도 같은 자리에 있다. 목록은 두 단(5:6)이고 여백은 12px이다.
- 사무실의 자리는 왼쪽부터 문, 대기 선반, 책상 3개, 시험대, 벽 화면, 완료 선반이다. 앞줄에 소파와 호출 벨이 있다. 벽에 단계 이름표 5개(대기, 구현, 검증, 검수, 완료)가 있다.
- 건물 보기에서 층 하나는 논리 높이 21px이고 층 간격은 23px이다. 층마다 이름표, 상자 진행 칸, 캐릭터가 있다. 캐릭터의 크기는 사무실 보기와 같다.
- 패널의 폭이 440px 이하이면 다음과 같이 바뀐다. 지붕의 상자 진행 칸을 숨긴다. 다른 층 알림은 짧은 문구로 바꾼다. 지반은 줄을 바꾸고 버튼이 아래 줄로 내려간다. 목록은 한 단이 된다. 단계 이름표는 11px이 된다.

### Named Rules
**한 번만 말하기 규칙.** 같은 사실을 두 번 적지 않는다. 지붕은 다른 층의 알림만 말한다. 지반은 지금 보는 층의 일만 말한다. 건물 보기의 지반은 모든 층 중에서 가장 급한 일 하나를 말한다.

**자리 고정 규칙.** 정보의 자리는 바꾸지 않는다. 내용만 바꾼다. 지반은 상태가 달라져도 얼굴 칸, 글, 버튼의 순서가 같다.

**40px 클릭 영역 규칙.** 누를 수 있는 것의 클릭 영역은 가로세로 40px 이상이다. 앱 패널(240pt)에서는 높이 24pt 이상이다. 보이는 크기가 작으면 보이지 않는 영역을 넓힌다. 예외는 선반의 상자 하나다. 상자의 클릭 영역은 24×32px이다. 선반에서 상자는 화면 24px 간격으로 붙어 있다. 그래서 가로는 넓히지 않고 세로만 넓힌다.

## Elevation & Depth

패널 안은 평평하다. 그림자를 쓰지 않는다. 깊이는 2px 남색 외곽선과 그리는 순서로 나타낸다. 장면에서는 발의 y값이 큰 것을 나중에 그린다. 그래서 앞줄의 캐릭터가 뒷줄의 가구를 가린다.

주의 표시는 장면 캔버스 위의 별도 캔버스에 그린다. 그 위에 단계 이름표, 클릭 영역, 말풍선이 차례로 놓인다.

### Shadow Vocabulary
- **패널 테두리와 바깥 그림자** (`box-shadow: 0 0 0 2px #232845, 0 18px 40px rgba(35,40,69,.2), 0 6px 14px rgba(35,40,69,.14), 0 1px 3px rgba(35,40,69,.2)`): 패널이 바탕 화면 위에 떠 있음을 나타낸다. 패널 하나에만 쓴다.
- **선택 테두리** (`box-shadow: inset 0 0 0 2px #fffdf4, 0 0 0 2px #232845`): 장면에서 선택한 캐릭터나 상자.
- **초점 테두리** (`outline: 2px solid`, 간격 2px): 남색 바탕 위에서는 종이색, 종이 바탕과 분홍 바탕 위에서는 남색이다. 장면의 클릭 영역은 종이색 2px 선 바깥에 남색 4px 띠를 더한다.

### Named Rules
**안은 평평하게 규칙.** 패널 안의 요소에는 그림자를 넣지 않는다. 구분은 외곽선과 면의 색으로 한다.

## Shapes

- 장면의 그림은 사각형만으로 그린다(`fillRect`). 곡선과 보간이 없다.
- 장면의 외곽선은 논리 1px이다. 화면에서는 2px이다. 장면 위의 이름표와 말풍선, 지반의 버튼도 2px 남색 테두리를 쓴다. 그래서 그림과 글자 요소의 선 굵기가 같다.
- 목록의 꼬리표, 알약 표지, 구분선은 1.5px이다.
- 모서리는 쓰임에 따라 다르다. 이름표와 꼬리표는 2px이다. "예시" 표지는 3px이다. 지붕 버튼은 5px이다. 장면의 클릭 영역은 6px이다. 입력란은 7px이다. 지반 버튼과 알약 표지는 8px이다. 말풍선과 다른 층 알림은 9px이다. 패널은 10px이다. 얼굴 칸은 원이다.
- 벽에 붙은 것(이름표)은 각지고, 떠 있는 것(말풍선, 알림)은 둥글다.

## Components

### 지반
지반은 사용자가 나설 일을 말하는 자리다.
- **평소:** 남색 바탕에 종이색 글자. 첫째 줄은 상태 한 문장이다. 둘째 줄은 진행 중인 단위다. 버튼은 "단위 후 정지"와 "중단"이고 둘 다 테두리 버튼이다.
- **당신 차례:** 분홍 바탕에 남색 글자. 얼굴 칸에 묻는 캐릭터의 얼굴이나 막힌 상자가 나온다. 첫째 줄은 질문이다. 채운 버튼 하나가 주된 답이다.
- **사용자 정지:** 남색 바탕 그대로다. 얼굴 칸에 정지 표지판이 나온다. 채운 버튼은 "계속"이다.
- **즉시 중단 확인:** "지금 모두 멈출까요?"를 한 번 묻는다. 채운 버튼은 "멈춘다"이고 테두리 버튼은 "취소"다.
- **선택:** 캐릭터나 상자를 누르면 요약 한 줄이 나온다. 캐릭터는 이름, 하네스, 모델, effort, 상태다. 상자는 단계와 가장 최근 증거다. 닫는 X 버튼이 있다.
- **메시지 입력:** 글 자리가 이름표와 입력란(높이 26px, 모서리 7px, 종이색)으로 바뀐다. 버튼은 "보내기"와 X다.
- **전환:** 바탕색은 0.3초 동안 `cubic-bezier(.16,1,.3,1)`로 바뀐다. 분홍으로 바뀔 때 안의 요소가 7px 아래에서 0.32초 동안 올라온다. 요소마다 0.05초씩 늦게 시작한다.
- **얼굴 칸:** 36px 원, 종이색 바탕, 2px 테두리. 안의 그림은 16×16 캔버스를 32px로 확대한다. 그림 종류는 얼굴, 벨, 정지 표지판, 상자, 건물이다.

### 버튼
- **지반 버튼:** 높이 32px, 모서리 8px, 2px 테두리, Jua 14px. 최소 폭 40px. 클릭 영역은 위아래로 6px씩 넓힌다.
- **채운 버튼:** 지반의 글자색으로 채운다. 남색 지반에서는 종이색 바탕에 남색 글자다. 분홍 지반에서는 남색 바탕에 분홍 글자다. 지반에 하나만 둔다.
- **테두리 버튼:** 바탕이 투명하다. hover에서 바탕이 옅게 바뀐다(남색 지반 `rgba(255,253,244,.16)`, 분홍 지반 `rgba(35,40,69,.14)`).
- **X 버튼:** 32×32px, 테두리 없음, 12px X 그림(선 굵기 2.4).
- **지붕 버튼:** Jua 13px, 모서리 5px, 바탕 `ink-2`. hover는 `ink-3`이다. 켜진 상태는 종이색 바탕에 남색 글자다. 보이는 높이는 20px이고 클릭 영역은 아래로 16px, 위로 4px 넓힌다.
- **상태:** 누르면 0.96배로 줄어든다(0.15초, `cubic-bezier(.2,0,0,1)`). 쓸 수 없는 버튼은 불투명도 0.5다.

### 다른 층 알림
- 지붕의 분홍 알약이다. 모서리 9px, 시스템 글꼴 600 11px, 남색 글자.
- 다른 층에 "당신 차례"가 있을 때만 보인다. 누르면 건물 보기가 열린다.
- 건물 보기에서는 숨긴다. 지반이 같은 일을 말하기 때문이다.

### 이름표와 말풍선
- **단계 이름표:** 종이색 바탕, 2px 남색 테두리, 모서리 2px, Jua 12px. 밤에는 바탕이 `card-night`다. 누를 수 없다.
- **말풍선:** 종이색 바탕, 2px 남색 테두리, 모서리 9px, Jua 12px, 꼬리 6px. 최대 폭은 장면의 62%이고 넘치면 말줄임표로 자른다.
- 말풍선은 상태가 바뀐 직후 3.2초 동안만 보인다. 한 번에 가장 최근 것 하나만 보인다. 상자, 다른 캐릭터의 얼굴, 머리 위 표시를 차례로 피해서 자리를 잡는다.
- 말풍선에는 지금 쓰는 도구와 대상을 한 줄로 적는다.

### 캐릭터
종은 하네스이고 털 무늬는 모델이다. 시안의 `HARNESS` 표와 `COAT` 표가 원본이다. 종이나 무늬를 바꿀 때는 그 표만 고친다.

| 하네스 | 종 | 모델과 털 무늬 | 모르는 모델 |
|---|---|---|---|
| claude-code | 고양이 | fable 턱시도, opus 삼색, sonnet 치즈 태비, haiku 흰색 | 회색 민무늬 |
| codex | 개 | 기본 모델 비글, 가벼운 모델 점박이 | 비글 |
| agy | 개구리 | 기본 모델 민무늬, 가벼운 모델 점박이 | 민무늬 |

- 종은 윤곽으로 갈린다. 고양이는 귀가 서 있다. 개는 귀가 턱 아래까지 늘어진다. 개구리는 귀가 없고 눈이 머리 위로 튀어나온다.
- 털 무늬는 색과 무늬가 함께 다르다. 색만으로 구분하지 않는다.
- 머리띠와 역할 소품은 없다. 역할(계획자, 일꾼, 검수자)은 이름과 자리로 읽는다.
- 크기는 폭 12, 높이 약 16 논리 픽셀이다. 머리는 12×11이고 개구리만 12×10이다. 장면에서 2배로 확대한다.
- 개구리의 초록(#1f8a7a)은 완료 초록과 겹치지 않게 짙은 청록으로 쓴다.
- 동작이 상태다. 타자는 작업, 걷기는 이동, 손들기는 결정 대기, 입력 대기, 환경·한도, 감은 눈은 휴식과 사용자 정지다.
- 머리 위의 작은 표시는 종이색 판(9×8)에 그린다. 종류는 확인 중(점 3개), 사용자 정지(세로 줄 2개), 완료(체크)다. 휴식은 판 없이 z 글자 2개다.

### 상자
- 단위 하나가 상자 하나다. 크기는 11×9 논리 픽셀이다. 상자가 놓인 자리가 단계다.
- 대기와 진행은 호박색이고 완료는 초록이다. 아랫단에 짙은 줄이 있다.
- 상자에는 단위 번호를 5×5 숫자로 그린다. 숫자는 한 자리만 그린다.
- 캐릭터가 상자를 머리 위로 들고 옮긴다. 상자를 든 캐릭터가 담당자다.
- 지붕의 상자 진행 칸과 건물 층의 상자 칸도 같은 두 색을 쓴다.

### 주의 표시
- 주의 표시는 장면 위의 별도 층에 픽셀로 그린다. 분홍 판에 남색 외곽선이다.
- **결정 대기:** 호출 벨이 분홍으로 바뀌고 좌우로 1px 흔들린다. 캐릭터의 머리 위에 물음표 판(11×9)이 나온다.
- **단위 막힘:** 상자 위에 느낌표 판(7×9)이 나온다.
- **환경·한도:** `hc` 상태가 `error`인 캐릭터의 머리 위에 느낌표 판(11×9)이 나온다. 멈춤 기록이 환경·한도이면 사무실 문 위에 느낌표 판(11×13)이 나온다. 건물 보기의 판과 같은 모양이다.
- **입력 대기:** `hc` 상태가 `blocked`인 터미널이다. 캐릭터가 손을 들고 머리 위에 물음표 판(11×9)이 나온다. 지반에 "터미널에서 입력을 기다립니다"라고 적는다.
- **건물 보기:** 주의가 필요한 층의 오른쪽에 판(11×13)이 나온다. 결정 대기와 입력 대기는 물음표, 단위 막힘과 환경·한도는 느낌표다.
- 판은 깜박이지 않는다. 1px 위아래로 움직인다. 프레임이 멈춰도 분홍이 남는다.
- 주의 상태(결정 대기, 단위 막힘, 환경·한도, 입력 대기, 사용자 정지)에는 글자 말풍선을 쓰지 않는다. 글은 지반에 적는다.
- 사용자 정지는 문 옆의 빨강 표지판으로 표시한다. 분홍 판을 쓰지 않는다.

### 장소의 불빛
- 책상에서 작업 중이면 모니터와 천장등이 켜진다. 모니터의 코드 줄이 2프레임으로 움직인다.
- 시험대의 3색 등은 빨강, 호박, 초록 순서다. 실행 중에는 호박 등이 2프레임으로 켜졌다 꺼진다. 통과는 초록, 실패는 빨강이다.
- 벽 화면은 검수할 상자가 있을 때만 켜진다.
- 캐릭터가 드나들 때만 문이 열린다.

### 목록 보기
- 같은 정보를 글자로 보여 준다. 종이색 바탕에 남색 글자다.
- 구역은 담당자, 단위, 지시 기록이다. 건물에서 열면 프로젝트 구역 하나다.
- 줄은 1.5px 구분선(`paper-line`)으로 나눈다. 보조 줄은 11px `paper-sub`다.
- 꼬리표는 1.5px 테두리, 모서리 2px, Jua 11px이다. 단계 꼬리표는 종이색이다. 결정 대기, 단위 막힘, 환경·한도 꼬리표는 분홍이다. 사용자 정지 꼬리표는 남색 바탕에 종이색 글자다.
- 지시 기록은 지시마다 "접수"와 "적용됨"을 따로 적는다.

### 움직임
- 움직임은 실제 이벤트가 있을 때만 만든다. 일하는 것처럼 보이게 하는 무작위 움직임을 넣지 않는다.
- 그림은 2프레임이다. 프레임은 0.34초마다 바뀐다(약 3Hz). 화면은 초당 12번까지만 다시 그린다.
- 걷는 속도는 초당 논리 30px이다.
- 움직임 줄이기 설정(`prefers-reduced-motion`)에서는 프레임을 바꾸지 않는다. 캐릭터는 걷지 않고 목적지에 바로 놓인다. 지반의 전환, 버튼의 누름 축소, hover 전환을 끈다.

## Do's and Don'ts

### Do:
- **Do** 분홍(#ff4f9a)을 결정 대기, 단위 막힘, 환경·한도, 입력 대기에만 쓴다.
- **Do** 지붕과 지반을 낮과 밤에 같은 남색(#232845)으로 둔다. 밤에는 장면의 색만 바꾼다.
- **Do** 누를 수 있는 것의 클릭 영역을 40px 이상으로 만든다. 예외는 선반의 상자(24×32px)뿐이다.
- **Do** 글자를 11px 이상으로 쓴다.
- **Do** 글자와 바탕의 대비를 4.68:1 이상으로 둔다. 가장 낮은 쌍은 분홍 바탕 위의 남색 글자다.
- **Do** 주의 표시에 물음표나 느낌표 모양을 함께 그린다.
- **Do** 종과 털 무늬를 `HARNESS` 표와 `COAT` 표에서만 정한다.
- **Do** 지반에 채운 버튼을 하나만 둔다.
- **Do** 움직임 줄이기 설정에서 프레임을 멈춘다.

### Don't:
- **Don't** 분홍을 장식, 강조, 사용자 정지에 쓰지 않는다.
- **Don't** 같은 사실을 지붕과 지반에 함께 적지 않는다.
- **Don't** 주의 상태에 글자 말풍선을 쓰지 않는다.
- **Don't** 캐릭터에 머리띠나 역할 소품을 붙이지 않는다.
- **Don't** 이벤트가 없는데 움직이는 그림을 넣지 않는다.
- **Don't** 패널 안의 요소에 그림자를 넣지 않는다.
- **Don't** 주의 표시를 깜박이게 하지 않는다. 1px 움직임만 쓴다.
- **Don't** 장면 캔버스를 보간해서 확대하지 않는다.
- **Don't** 상태 점과 줄 목록으로 된 메뉴 막대 표준 배치를 쓰지 않는다.
