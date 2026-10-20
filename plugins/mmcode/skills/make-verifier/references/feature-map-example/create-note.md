# 노트 만들기

노트 만들기로 사용자는 브라우저나 CLI에서 제목 있는 노트를 저장하고, 끝내지 않은 초안을 취소하고, 저장된 노트를 사용자에게 보이는 다른 화면에서 한 번 더 확인할 수 있다.

## 하위 기능

- `create-open`은 브라우저 진입점마다 빈 편집기를 연다.
- `create-save`는 제목과 본문을 저장한다.
- `create-cancel`은 끝내지 않은 브라우저 초안을 버린다.
- `create-cli`는 같은 형태의 노트를 터미널에서 만든다.

## 도달 방법 (사용자 시점)

- 브라우저 툴바의 `New note` 버튼을 선택한다.
- 브라우저에서 포커스가 편집 가능한 입력란 밖에 있을 때 `n`을 누른다.
- 터미널에서 `notes create --title <title> --body <body>`를 실행한다.

## 조작하기 (control-notes)

전제 조건:

- Notes가 `http://127.0.0.1:4173`에서 정상 동작한다.
- 제목이 `Release checklist`인 노트가 없다.
- `control-notes doctor`가 기대한 URL과 일회용 데이터 폴더를 보고한다.

- **편집기 열기.** `New note`를 선택한다. `control-notes browser click --role button --name "New note"`를 실행한다. 이름이 `Note editor`인 폼이 나타나고 포커스가 `Title` 텍스트 상자에 있다.
- **내용 입력.** 제목과 본문을 입력한다. `control-notes browser fill --role textbox --name "Title" --value "Release checklist"`와 `control-notes browser fill --role textbox --name "Body" --value "Tag and publish"`를 실행한다. `Save note` 버튼이 활성화된다.
- **노트 저장.** `Save note`를 선택한다. `control-notes browser click --role button --name "Save note"`를 실행한다. 이름이 `Note saved`인 상태 표시가 나타나고 제목이 `Release checklist`로 보인다.
- **저장 유지 확인.** 노트 목록으로 돌아가 노트를 다시 연다. `control-notes browser click --role link --name "All notes"`와 `control-notes browser click --role link --name "Release checklist"`를 실행한다. 편집기에 저장한 두 값이 모두 보인다.
- **초안 취소.** 새 노트를 열고 `Discard me`를 입력한 뒤 `Cancel`을 선택한다. `control-notes browser click --role button --name "New note"`, `control-notes browser fill --role textbox --name "Title" --value "Discard me"`, `control-notes browser click --role button --name "Cancel"`를 실행한다. 노트 목록으로 돌아오고 `Discard me` 링크는 없다.
- **CLI 진입.** 두 번째 노트를 만든다. `control-notes cli -- notes create --title "CLI note" --body "Created from terminal" --format json`을 실행한다. 종료 코드는 `0`이고 stdout에 새 노트 ID와 제목이 있다.
- **증거.** `All notes`에서 저장한 두 노트를 다시 연다. `control-notes browser snapshot --aria --path artifacts/create-note/list.aria.txt`와 `control-notes browser screenshot --path artifacts/create-note/list.png`를 실행한다. 두 산출물에 `Release checklist`와 `CLI note`가 보인다.

## 주의할 점

- 텍스트 상자에 포커스가 있을 때 `n`을 누르면 새 편집기가 열리지 않고 글자가 입력된다.
- 제목은 저장할 때 앞뒤 공백이 잘린다. 초안 입력값이 아니라 화면에 표시된 제목을 기준으로 검사한다.
- 저장 상태 표시만으로는 증거가 부족하다. 목록에서 노트를 다시 연다.
- 임시 데이터(fixture)를 정리할 때 `Release checklist`와 `CLI note`는 지우되, 그 증명 산출물은 남긴다.
