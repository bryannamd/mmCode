# 노트 검색

검색으로 사용자는 제목이나 본문 텍스트로 노트를 찾고, 일치한 노트를 살펴보고, 일치 항목 없음과 검색 불가를 구분할 수 있다.

## 하위 기능

- `search-open`은 지원하는 브라우저 진입점마다 검색을 연다.
- `search-match`는 노트 데이터를 바꾸지 않고 제목·본문 일치 항목을 돌려준다.
- `search-open-result`는 결과를 노트 편집기에서 연다.
- `search-empty`는 일치 항목이 없는 검색어를 입력하면 완전한 빈 상태를 보여준다.
- `search-clear`는 검색어를 지우고 최근 노트 화면을 복원한다.
- `search-cli`는 같은 일치 노트를 터미널에서 돌려준다.

## 도달 방법 (사용자 시점)

- 브라우저 툴바의 `Search` 버튼을 선택한다.
- 브라우저에서 포커스가 편집 가능한 입력란 밖에 있을 때 `/`를 누른다.
- 터미널에서 `notes search <query>`를 실행한다.

## 조작하기 (control-notes)

전제 조건:

- Notes가 `http://127.0.0.1:4173`에서 정상 동작한다.
- 일회용 데이터 폴더에 본문이 `Draft budget`인 `Quarterly plan` 노트가 있다.
- `control-notes doctor`가 기대한 URL과 데이터 폴더를 보고한다.

- **툴바 진입.** `Search` 버튼을 선택한다. `control-notes browser click --role button --name "Search"`를 실행한다. 이름이 `Search notes`인 대화상자가 나타나고 포커스가 검색창에 있다.
- **키보드 진입.** 대화상자를 닫고, 페이지에 포커스를 두고, `/`를 누른다. `control-notes browser press --key "/"`를 실행한다. 같은 대화상자가 나타나고 페이지에 슬래시가 입력되지 않는다.
- **제목 일치.** `quarterly`를 입력한다. `control-notes browser fill --role searchbox --name "Search notes" --value "quarterly"`를 실행한다. `Search results` 목록에 `Quarterly plan`이 있고 `Grocery list`는 없다.
- **본문 일치.** 검색어를 `budget`으로 바꾼다. `control-notes browser fill --role searchbox --name "Search notes" --value "budget"`를 실행한다. `Quarterly plan` 결과가 본문 일치 발췌와 함께 계속 보인다.
- **결과 열기.** `Quarterly plan`을 선택한다. `control-notes browser click --role link --name "Quarterly plan"`을 실행한다. 대화상자가 닫히고 편집기 제목이 `Quarterly plan`이다.
- **빈 상태.** 검색을 다시 열고 `volcano`를 입력한다. `control-notes browser fill --role searchbox --name "Search notes" --value "volcano"`를 실행한다. 검색이 끝나면 이름이 `No matching notes`인 상태 표시가 나타난다.
- **검색어 지우기.** `Clear search`를 선택한다. `control-notes browser click --role button --name "Clear search"`를 실행한다. 검색창이 비고 `Recent notes` 영역이 결과 목록을 대체한다.
- **CLI 일치.** 터미널에서 검색한다. `control-notes cli -- notes search "quarterly" --format json`을 실행한다. 종료 코드는 `0`이고 stdout에 제목이 `Quarterly plan`인 객체가 하나 있다.
- **CLI 불일치.** 없는 값을 검색한다. `control-notes cli -- notes search "volcano" --format json`을 실행한다. 종료 코드는 `0`이고 stdout은 `[]`이다.
- **증거.** 결과가 채워진 상태를 남긴다. `control-notes browser snapshot --aria --path artifacts/search/results.aria.txt`와 `control-notes browser screenshot --path artifacts/search/results.png`를 실행한다. 두 산출물 모두 Notes, 검색어, `Quarterly plan`이 식별된다.

## 주의할 점

- 편집기나 검색창에 포커스가 있을 때 `/`를 누르면 검색이 열리지 않고 글자가 입력된다.
- 결과는 짧은 디바운스(입력 후 잠시 대기) 뒤에 갱신된다. 고정 대기 시간(sleep)이 아니라 결과 목록이나 빈 상태 표시를 기다린다.
- 보관된 노트는 사용자가 `Include archived`를 켜지 않으면 제외된다.
- CLI는 기본으로 사람이 읽는 형식을 출력한다. 안정적인 자동 검사에는 `--format json`을 쓴다.
- 결과를 열면 브라우저 상태가 바뀐다. 다른 검색어를 증명하기 전에 검색을 다시 연다.
