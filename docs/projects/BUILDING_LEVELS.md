# 공통 건물과 Level 관리

관련 이슈: [#19](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/19)

브랜치: `feat/#19-building-level-management` (#18 브랜치에서 시작).

리뷰 요청을 반영해 #18 프로젝트 생성·저장/Finder 열기와 #19 공통 건물·Level 관리 변경을 [PR #23](https://github.com/adap-c6-fingerprint/IMDFrnt/pull/23)에 통합한다. PR의 기준 브랜치는 develop이며, #18 PR #24는 통합 PR로 대체한다. 이슈별 변경 커밋과 기존 브랜치는 보존한다.

## 사용 순서

1. 새 프로젝트를 만들고 상단 **건물·층 관리**에서 건물과 층을 추가한다. 각 층의 이름·짧은 이름·ordinal·Level UUID를 편집할 수 있다. UUID와 ordinal 중복은 차단한다.
2. SVG·PNG·JPG는 현재 선택한 층에 불러온다. 첫 도면을 넣으면 첫 층을 만들며 기존 건물 정보와 저장 위치를 유지한다. 도면 교체는 해당 층에만 적용하고, 기존 태깅·좌표 기준점 초기화를 확인한다. 노드는 유지된다.
3. 완성된 IMDF를 불러오면 기존 층과 도형, Feature UUID, geometry, properties, manifest 및 전역 정보를 프로젝트에 담는다. 이 입력은 새 프로젝트로 시작하며 빈 프로젝트에 넣을 때는 빈 프로젝트의 ID와 저장 위치를 유지한다.
4. 상단 층 선택, 관리 화면의 층 셀, 노드 화면의 층 셀은 같은 선택을 사용한다. 다른 층의 도면·태깅·기준점·노드를 덮어쓰지 않는다.
5. 관리 화면에서 건물·Venue·주소의 `properties`와 Manifest를 JSON으로 편집할 수 있다. Footprint는 새 geometry 입력 또는 **현재 층 윤곽 가져오기**로 만들고 미리보기를 확인한 후 적용한다. 경도·위도의 닫힌 Polygon/MultiPolygon을 사용한다. 기존 Footprint를 수정하면 UUID·건물 참조를 유지하며 실제 저장 좌표를 바꾼다.
6. 층 삭제는 우클릭 메뉴에서 요청하고 확인한다. 해당 층의 도면·도형·태깅·노드와 연결을 삭제한다. Footprint 삭제도 확인하며 새 삭제 버튼은 빨간 레이블을 사용한다. 추가·수정·삭제는 Undo/Redo로 되돌릴 수 있다.
7. `.imdfrnt` 파일에 자동 저장된다. 층 전환과 선택만으로 수정 상태가 바뀌지 않으며, 건물·Footprint·Level 편집은 저장·복구 대상이다.

## 저장 구조

현재 형식은 버전 5다. 건물 전역 데이터와 공통 Levels를 `buildingProject`에 저장한다. 노드 편집용 RoutingGraph는 이 데이터에서 만든 호환 뷰이며 별도 원본으로 저장하지 않는다.

| 위치 | 저장 데이터 |
| --- | --- |
| 프로젝트 전역 | venue·building·address·footprint·manifest, 여러 층을 참조하는 Feature, 알 수 없는 JSON 파일과 GeoJSON collection header |
| 각 Level | 공통 층 정보, 내장 도면 원문·파일명·좌표 기준, 실제 GeoJSON Feature, 기존 SVG 태깅 상태, 노드, 층 내부 엣지 |
| 프로젝트 연결 | 층간 엣지, 양 끝 노드 UUID 참조 |

IMDF에서 만든 SVG는 표시용 캐시다. 재열기 시 실제 GeoJSON geometry에서 다시 만든다. 기존 노드를 보존하기 위해 저장된 표시 좌표 변환을 유지한다. `imdfFiles()`는 층별 Feature를 타입별 파일로 모으며 원본 Feature ID·속성·좌표와 collection의 추가 필드를 보존한다. 이 함수는 후속 IMDF 내보내기 구현의 기반이며 이번 작업에서 전체 IMDF ZIP 내보내기 UI를 추가하지 않는다. 클라이언트용 `routing-graph.geojson` 내보내기는 기존 계약을 유지한다.

버전 2·3·4는 열 때 공통 Level로 이전한다. 기존 RoutingFloor UUID·노드·엣지를 유지하며, 기존 SVG 태깅은 같은 SVG를 가진 층에 연결한다. 일치하는 층이 없으면 별도 층에 보존한다. 과거 노드 전용 IMDF 프로젝트에는 원본 GeoJSON이 저장되지 않았으므로 SVG에서 원본 Feature ID·속성을 복원했다고 주장하지 않는다. 새 IMDF 가져오기부터 원본 Feature를 보존한다.

## 후속 범위

- #20: IMDF 도형과 독립된 SVG 참고 레이어, 건물 Footprint 배경, 표시·숨김과 불투명도, 도면 캐싱·비동기 로딩·메타데이터 탭바를 추가했다. [사용법과 검증](LEVEL_DRAWINGS.md)을 참고한다.
- #21: 마우스로 독립 DraftShape를 작성하고 꼭짓점을 편집하는 도구. 이번 Footprint 입력은 geometry JSON 편집이며 마우스 작도 도구를 대체하지 않는다.

## 검증

```sh
cd IM-DFrnt
./build-app.sh /private/tmp/IM-DFrntIssue19.app
/private/tmp/IM-DFrntIssue19.app/Contents/MacOS/IM-DFrnt --building-selftest --imdf-test-input /path/to/IMDFData -ApplePersistenceIgnoreState YES
/private/tmp/IM-DFrntIssue19.app/Contents/MacOS/IM-DFrnt --project-selftest -ApplePersistenceIgnoreState YES
/private/tmp/IM-DFrntIssue19.app/Contents/MacOS/IM-DFrnt --routing-selftest -ApplePersistenceIgnoreState YES
/private/tmp/IM-DFrntIssue19.app/Contents/MacOS/IM-DFrnt --selftest -ApplePersistenceIgnoreState YES
```

검사는 SwiftUI/NSApplication 초기화 전에 CLI 진입점에서 시작한다. 5종 검사와 종료 코드·로그를 함께 확인하려면 `./run-self-tests.sh /private/tmp/IM-DFrntIssue19.app`를 실행한다. [Self-test 재현](SELF_TESTS.md)에 실행 조건·입력별 검사 수·리뷰 환경의 재현 실패와 수정 내용을 기록했다.

Building 검사는 독립적인 임시 폴더·UserDefaults에서 저장·재열기·복구, 층별 태깅·기준점·노드, 층간 연결, Footprint geometry 수정과 삭제 확인, Undo/Redo, 기존 형식 이전을 검사한다. 실제 IMDF 입력이 지정되면 파일·Feature·geometry·properties의 왕복 보존도 검사한다. `--legacy-test-input /path/to/old.imdfrnt`로 기존 파일을 읽기 전용으로 이전·왕복 검증할 수 있다. 테스트 모드에서는 실제 사용자 복구본을 읽거나 자동 저장하지 않는다.

UI 시험은 독립된 복구 경로에서 실행할 수 있다.

```sh
open -n /private/tmp/IM-DFrntIssue19.app --args --project-qa-directory /private/tmp/IMDFrnt19UI -ApplePersistenceIgnoreState YES
```

#18·#19는 사용자 수동 테스트 후 닫혔다. #20의 실제 UI 검증은 [층별 도면 검증](LEVEL_DRAWINGS.md)에 별도로 기록한다.
