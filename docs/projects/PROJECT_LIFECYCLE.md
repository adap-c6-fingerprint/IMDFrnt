# 프로젝트 생성과 저장

관련 이슈: [#18](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/18)

브랜치: `feat/#18-new-project-save`

## 사용 순서

1. 화면 왼쪽 위 **파일 → 새 프로젝트** 또는 ⌘N으로 새 작업을 시작한다. 도면·태깅·Anchor·노드·연결·선택·임시 편집·실행취소 기록을 초기화한다.
2. 도면이 없는 상태도 **작업 저장**(⌘S)에서 원하는 이름·폴더의 `.imdfrnt`로 저장할 수 있다. 이후 도면이나 IMDF를 불러오면 빈 프로젝트의 ID와 저장 위치를 유지한다.
3. **작업 열기**(⌘⇧O)로 전체 작업을 다시 연다. **다른 이름으로 저장**(⌘⇧S)은 쓰기가 성공한 뒤에만 현재 저장 위치를 바꾼다.
4. 상단에서 프로젝트 이름과 `저장되지 않음 / 수정사항 있음 / 저장됨`을 확인한다. 노드 선택·화면 전환 등 저장되지 않는 UI 상태는 수정사항으로 표시하지 않는다.

## 저장하지 않은 변경사항

새 프로젝트, 다른 작업·도면·IMDF 열기, 창 닫기, 앱 종료는 현재 저장하지 않은 변경사항을 먼저 확인한다.

- **저장**: 필요하면 저장 위치를 선택하고 저장이 성공한 뒤 계속한다.
- **저장하지 않음**: 새 작업으로 교체하거나 종료한다. 명시적으로 저장한 파일은 보존한다.
- **취소**: 현재 프로젝트를 유지한다. 저장 창에서 취소하거나 파일 쓰기에 실패해도 현재 작업을 유지한다.

30초 자동 저장은 복구본을 갱신한다. 사용자가 지정한 프로젝트 파일은 ⌘S 등 명시적인 저장으로 갱신한다. 복구본과 실제 저장 파일의 상태를 구분하고, 저장하지 않고 종료한 변경사항이 다음 실행에서 다시 나타나지 않게 한다. 수정 없이 저장한 프로젝트를 닫으면 저장 확인을 띄우지 않는다.

새 프로젝트의 UUID는 새로 발급한다. 파일 형식 버전은 프로젝트마다 증가하는 값이 아니라 현재 schema version `5`다. 기존 버전 2·3·4 파일은 공통 Level 구조로 이전한다. [건물과 Level 관리](BUILDING_LEVELS.md)를 참고한다. 기존 파일에서 `hasDrawing`이 없으면 도면이 있는 것으로 읽으며 새 버전에서는 실제 도면·작업 데이터를 각 Level 안에 저장한다.

## 검증

Finder 연결: 앱은 `.imdfrnt`·이전 `.imdfproj`를 프로젝트 문서 타입의 Editor/Owner로 등록한다. `/Applications` 또는 `~/Applications` 같은 일반 설치 경로에서 Finder 연결에 사용할 수 있다. `/private/tmp` 테스트 앱은 기본 연결 후보에서 제외될 수 있다. 기존에 다른 기본 앱을 지정했다면 Finder의 정보 가져오기 → 다음으로 열기에서 변경할 수 있다.

앱 시작 전 파일 요청은 환경 연결 후 처리한다. 이전 복구 작업을 먼저 확인하고 미저장 변경은 저장/폐기/취소를 거친다. 같은 프로젝트를 다시 열면 현재 미저장 편집을 유지한다. 가져오기·모달 중에는 요청을 대기시키며, 여러 파일을 한 번에 전달하면 부분 교체 없이 거절한다. 파일 메뉴와 외부 열기는 같은 검증·저장 위치·복구 처리를 사용한다.

```sh
cd IM-DFrnt
./build-app.sh /private/tmp/IM-DFrntIssue18.app
/private/tmp/IM-DFrntIssue18.app/Contents/MacOS/IM-DFrnt --project-selftest
/private/tmp/IM-DFrntIssue18.app/Contents/MacOS/IM-DFrnt --document-open-selftest
/private/tmp/IM-DFrntIssue18.app/Contents/MacOS/IM-DFrnt --routing-selftest
/private/tmp/IM-DFrntIssue18.app/Contents/MacOS/IM-DFrnt --selftest
```

검사는 SwiftUI/NSApplication 초기화 전에 CLI 진입점에서 시작한다. 5종 검사와 종료 코드·로그를 함께 확인하려면 `./run-self-tests.sh /private/tmp/IM-DFrntIssue18.app`를 실행한다. [Self-test 재현](SELF_TESTS.md)에 실행 조건·입력별 검사 수·리뷰 환경의 재현 실패와 수정 내용을 기록했다.

프로젝트 검사는 임시 폴더와 독립적인 UserDefaults에서 파일을 실제로 쓰고 읽는다. 새 ID·초기화·빈 프로젝트·기존 전체 데이터·수정/Undo 상태·원본을 바꾸지 않는 자동 저장·복구·폐기·저장 실패·저장 창 취소 결과·이전 형식 호환을 검사한다. 모든 검사 모드에서는 실제 사용자 복구본을 읽거나 자동 저장하지 않는다. 문서 열기 CLI 검사는 AppDelegate의 공통 요청 처리 경로를 확인하며 실제 Finder 이벤트·버튼 입력은 별도 UI 검증이다.

사용자 작업을 건드리지 않는 UI 시험은 아래처럼 별도 복구 경로로 실행할 수 있다.

```sh
open -n /private/tmp/IM-DFrntIssue18.app --args --project-qa-directory /private/tmp/IMDFrnt18UI
```

2026-10-12: UI 자동화 연결이 `Sky Computer Use native pipe startup failed`로 실패해 실제 메뉴·파일 대화상자·창 닫기의 입력 검증과 최종 화면 캡처는 미완료다. 자동 검사 통과와 실제 UI 확인을 구분하며 #18 이슈는 열어 둔다.

2026-10-13 최종 검사: 프로젝트 23/23 PASS, 실제 C5 IMDF 폴더·ZIP을 포함한 노드 편집 104/104 PASS, 기존 회귀 ALL PASS, 릴리즈 빌드·서명 검사 통과. ZIP은 클라이언트의 실제 C5 IMDF 폴더를 압축해 검증했다. 사용자 복구 파일 SHA-256이 검사 전과 같음을 확인했다. 로그는 `/private/tmp/imdfrnt18-project-final.log`, `imdfrnt18-routing-final.log`, `imdfrnt18-regression-final.log`에 기록했다.

Finder 리뷰 보완: 문서 열기 23/23 PASS, 프로젝트 23/23 PASS, Routing 104/104 PASS, 기존 회귀 ALL PASS. 별도 번들 ID·복구 경로에서 앱 시작 시/실행 중의 시스템 파일 전달을 확인했다. 일반 설치 경로에서는 기본 연결 앱 조회와 `open file.imdfrnt`가 실제 프로젝트를 여는 것도 확인했다. 테스트 앱 등록·설치는 정리했다. Finder UI의 물리적 더블클릭과 저장 확인 버튼 입력은 자동화 연결 오류로 별도 미확인이다.
