# 프로젝트 생성과 저장

관련 이슈: [#18](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/18), [#53 프로젝트 선택·저장 후 전환](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/53)

브랜치: `feat/#18-new-project-save`

## 사용 순서

1. 화면 왼쪽 위 **파일 → 새 프로젝트** 또는 ⌘N으로 새 작업을 시작한다. 도면·태깅·Anchor·노드·연결·선택·임시 편집·실행취소 기록을 초기화한다.
2. 직접 저장 기능(작업 저장·다른 이름으로 저장)은 없다. 프로젝트마다 **자동 저장 파일 하나**가 자동 저장 폴더 `~/Library/Application Support/IM-DFrnt/`에 `새 도면_YYMMDD_HHmm.imdfrnt` 이름으로 생긴다. 예: 2026-10-17 15:30에 처음 저장 → `새 도면_261017_1530.imdfrnt`. 같은 분에 또 만들면 `_2`, `_3`을 붙인다. 빈 프로젝트는 내용이 생기기 전까지 파일을 만들지 않는다.
3. **IMDF 불러오기…** 바로 아래의 **.imdfrnt 불러오기…**(⌘⇧O)는 자동 저장 폴더에서 시작하는 파일 선택 창을 연다. 앱 메뉴·상단 파일 메뉴·왼쪽 사이드바·빈 캔버스·길찾기 화면에 있다. 이전 `.imdfproj`도 고를 수 있다. 폴더 밖의 `.imdfrnt`를 열거나 Finder에서 열면 그 파일 자체가 이 프로젝트의 자동 저장 파일이 된다.
4. **파일 → 프로젝트 선택…**(⌥⌘O) 또는 상단의 프로젝트 이름을 누르면 프로젝트 선택 창이 뜬다. 자동 저장 폴더의 프로젝트를 최근 수정 순으로 보여 주며 각 항목에 층 목록·수정 시각·`현재 열림`/`지난 작업` 표시가 붙는다. `.imdfrnt` 하나는 건물 하나(모든 층 포함)이고, 다른 프로젝트를 열면 지금 프로젝트에 **합쳐지지 않고 교체**된다.
5. 다른 프로젝트로 넘어가거나 새 프로젝트를 만들 때(선택 창·.imdfrnt 불러오기·Finder 열기 공통) `‘A’ 프로젝트를 저장하고 ‘B’ 프로젝트로 전환할까요?`를 묻는다. **저장하고 전환**을 누르면 지금 프로젝트를 자기 파일에 저장한 뒤 바꾸고, 전환 후 배너에 이전 프로젝트가 따로 저장되어 있음을 알린다. 선택 창에서 취소하면 목록으로 돌아간다. 빈 새 프로젝트에서는 묻지 않는다.
6. 상단에서 프로젝트 이름과 `빈 프로젝트 / 자동 저장 대기 / 자동 저장됨`을 확인한다. 노드 선택·화면 전환 등 저장되지 않는 UI 상태는 변경으로 치지 않는다.

## 자동 저장

30초마다 내용이 바뀌었으면 프로젝트의 자동 저장 파일 하나에 덮어쓴다. 새 프로젝트, 다른 작업·도면·IMDF 열기, 창 닫기, 앱 종료 전에도 한 번 자동 저장하고 확인 없이 진행한다. 이 저장이 실패했을 때만 `취소 / 계속`을 묻는다. 계속하면 마지막 자동 저장 이후 변경이 사라진다.

앱을 다시 켜면 지난 작업을 바로 열지 않고 프로젝트 선택 창을 띄운다(저장된 프로젝트가 없으면 빈 시작 화면). Finder에서 파일을 열며 시작했으면 선택 창 없이 그 파일을 연다. 이전 버전이 쓰던 공용 복구본 `autosave.imdfrnt`(또는 `.imdfproj`)가 남아 있으면 지우지 않고 `새 도면_…` 이름으로 바꾼 뒤 목록에 `지난 작업`으로 보인다.

새 프로젝트의 UUID는 새로 발급한다. 파일 형식 버전은 프로젝트마다 증가하는 값이 아니라 현재 schema version `5`다. 기존 버전 2·3·4 파일은 공통 Level 구조로 이전한다. [건물과 Level 관리](BUILDING_LEVELS.md)를 참고한다. 기존 파일에서 `hasDrawing`이 없으면 도면이 있는 것으로 읽으며 새 버전에서는 실제 도면·작업 데이터를 각 Level 안에 저장한다.

## 검증

Finder 연결: 앱은 `.imdfrnt`·이전 `.imdfproj`를 프로젝트 문서 타입의 Editor/Owner로 등록한다. `/Applications` 또는 `~/Applications` 같은 일반 설치 경로에서 Finder 연결에 사용할 수 있다. `/private/tmp` 테스트 앱은 기본 연결 후보에서 제외될 수 있다. 기존에 다른 기본 앱을 지정했다면 Finder의 정보 가져오기 → 다음으로 열기에서 변경할 수 있다.

앱 시작 전 파일 요청은 환경 연결 후 처리한다. 지난 작업을 먼저 열고, 다른 파일로 바꾸기 전에 현재 작업을 자동 저장한다. 같은 프로젝트를 다시 열면 현재 미저장 편집을 유지한다. 가져오기·모달 중에는 요청을 대기시키며, 여러 파일을 한 번에 전달하면 부분 교체 없이 거절한다. 파일 메뉴와 외부 열기는 같은 검증·저장 위치·복구 처리를 사용한다.

```sh
cd IM-DFrnt
./build-app.sh /private/tmp/IM-DFrntIssue18.app
/private/tmp/IM-DFrntIssue18.app/Contents/MacOS/IM-DFrnt --project-selftest
/private/tmp/IM-DFrntIssue18.app/Contents/MacOS/IM-DFrnt --document-open-selftest
/private/tmp/IM-DFrntIssue18.app/Contents/MacOS/IM-DFrnt --routing-selftest
/private/tmp/IM-DFrntIssue18.app/Contents/MacOS/IM-DFrnt --selftest
```

검사는 SwiftUI/NSApplication 초기화 전에 CLI 진입점에서 시작한다. 5종 검사와 종료 코드·로그를 함께 확인하려면 `./run-self-tests.sh /private/tmp/IM-DFrntIssue18.app`를 실행한다. [Self-test 재현](SELF_TESTS.md)에 실행 조건·입력별 검사 수·리뷰 환경의 재현 실패와 수정 내용을 기록했다.

프로젝트 검사는 임시 폴더와 독립적인 UserDefaults에서 파일을 실제로 쓰고 읽는다. 새 ID·초기화·빈 프로젝트·`새 도면_YYMMDD_HHmm` 이름과 `_2` 구분·프로젝트당 파일 하나·전체 데이터 재열기·수정/Undo 상태·전환 전 자동 저장·저장 실패·공용 복구본 이전·이전 형식 호환을 검사한다. 모든 검사 모드는 실제 자동 저장 폴더 대신 임시 폴더를 쓴다. 문서 열기 CLI 검사는 AppDelegate의 공통 요청 처리 경로를 확인하며 실제 Finder 이벤트·버튼 입력은 별도 UI 검증이다.

사용자 작업을 건드리지 않는 UI 시험은 아래처럼 별도 자동 저장 폴더로 실행할 수 있다.

```sh
open -n /private/tmp/IM-DFrntIssue18.app --args --project-qa-directory /private/tmp/IMDFrnt18UI
```

2026-10-12: UI 자동화 연결이 `Sky Computer Use native pipe startup failed`로 실패해 실제 메뉴·파일 대화상자·창 닫기의 입력 검증과 최종 화면 캡처는 미완료다. 자동 검사 통과와 실제 UI 확인을 구분하며 #18 이슈는 열어 둔다.

2026-10-13 최종 검사: 프로젝트 23/23 PASS, 실제 C5 IMDF 폴더·ZIP을 포함한 노드 편집 104/104 PASS, 기존 회귀 ALL PASS, 릴리즈 빌드·서명 검사 통과. ZIP은 클라이언트의 실제 C5 IMDF 폴더를 압축해 검증했다. 사용자 복구 파일 SHA-256이 검사 전과 같음을 확인했다. 로그는 `/private/tmp/imdfrnt18-project-final.log`, `imdfrnt18-routing-final.log`, `imdfrnt18-regression-final.log`에 기록했다.

Finder 리뷰 보완: 문서 열기 23/23 PASS, 프로젝트 23/23 PASS, Routing 104/104 PASS, 기존 회귀 ALL PASS. 별도 번들 ID·복구 경로에서 앱 시작 시/실행 중의 시스템 파일 전달을 확인했다. 일반 설치 경로에서는 기본 연결 앱 조회와 `open file.imdfrnt`가 실제 프로젝트를 여는 것도 확인했다. 테스트 앱 등록·설치는 정리했다. Finder UI의 물리적 더블클릭과 저장 확인 버튼 입력은 자동화 연결 오류로 별도 미확인이다.
