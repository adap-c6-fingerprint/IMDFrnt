# 공통 건물과 Level 관리

관련 이슈: [#19](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/19)

브랜치: `feat/#19-building-level-management` (#18 브랜치에서 시작).

리뷰 요청을 반영해 #18 프로젝트 생성·저장/Finder 열기와 #19 공통 건물·Level 관리 변경을 [PR #23](https://github.com/adap-c6-fingerprint/IMDFrnt/pull/23)에 통합한다. PR의 기준 브랜치는 develop이며, #18 PR #24는 통합 PR로 대체한다. 이슈별 변경 커밋과 기존 브랜치는 보존한다.

## 사용 순서

1. 새 프로젝트를 만들고 상단 **건물·층 관리**에서 건물과 층을 추가한다. 각 층의 이름·짧은 이름·ordinal·Level UUID를 편집할 수 있다. UUID는 고유해야 한다. 동일 ordinal의 별도 Level과 다중 건물은 허용하되 내보낼 때 같은 건물·ordinal의 Level이 면적으로 겹치면 차단한다.
2. SVG·PNG·JPG는 현재 선택한 층에 불러온다. 첫 도면을 넣으면 첫 층을 만들며 기존 건물 정보와 저장 위치를 유지한다. 도면 교체는 해당 층에만 적용하고, 기존 태깅·좌표 기준점 초기화를 확인한다. 노드는 유지된다.
3. 완성된 IMDF를 불러오면 기존 층과 도형, Feature UUID, geometry, properties, manifest 및 전역 정보를 프로젝트에 담는다. 이 입력은 새 프로젝트로 시작하며 빈 프로젝트에 넣을 때는 빈 프로젝트의 ID와 저장 위치를 유지한다.
4. 상단 층 선택, 관리 화면의 층 셀, 노드 화면의 층 셀은 같은 선택을 사용한다. 다른 층의 도면·태깅·기준점·노드를 덮어쓰지 않는다.
5. 관리 화면에서 건물·Venue·주소의 `properties`와 Manifest를 JSON으로 편집할 수 있다. Footprint는 새 geometry 입력 또는 **현재 층 윤곽 가져오기**로 만들고 미리보기를 확인한 후 적용한다. 경도·위도의 닫힌 Polygon/MultiPolygon을 사용한다. 기존 Footprint를 수정하면 UUID·건물 참조를 유지하며 실제 저장 좌표를 바꾼다.
6. 층 삭제는 우클릭 메뉴에서 요청하고 확인한다. 해당 층의 도면·도형·태깅·노드와 연결을 삭제한다. Footprint 삭제도 확인하며 새 삭제 버튼은 빨간 레이블을 사용한다. 추가·수정·삭제는 Undo/Redo로 되돌릴 수 있다.
7. `.imdfrnt` 파일에 자동 저장된다. 층 전환과 선택만으로 수정 상태가 바뀌지 않으며, 건물·Footprint·Level 편집은 저장·복구 대상이다.

## 저장 구조

현재 형식은 버전 7이다. 건물 전역 데이터와 공통 Levels를 `buildingProject`에 저장한다. 노드 편집용 RoutingGraph는 이 데이터에서 만든 호환 뷰이며 별도 원본으로 저장하지 않는다. v2~v6는 읽을 수 있지만 이전 앱은 v7을 거절해야 한다. 기존 프로젝트는 별도 백업을 권장한다.

| 위치 | 저장 데이터 |
| --- | --- |
| 프로젝트 전역 | venue·building·address·occupant·relationship·footprint·manifest, 여러 층을 참조하는 Feature, 알 수 없는 JSON 파일과 GeoJSON collection header |
| 각 Level | 공통 층 정보, 내장 도면 원문·파일명·좌표 기준, 실제 GeoJSON Feature, 기존 SVG 태깅 상태, 노드, 층 내부 엣지 |
| 프로젝트 연결 | 층간 엣지, 양 끝 노드 UUID 참조 |

IMDF에서 만든 SVG는 표시용 캐시다. 재열기 시 실제 GeoJSON geometry에서 다시 만든다. 기존 노드를 보존하기 위해 저장된 표시 좌표 변환을 유지한다. `imdfFiles()`는 층별 Feature를 타입별 파일로 모으며 원본 Feature ID·속성·좌표와 collection의 추가 필드를 보존한다. 이 함수는 후속 IMDF 내보내기 구현의 기반이며 이번 작업에서 전체 IMDF ZIP 내보내기 UI를 추가하지 않는다. 클라이언트용 `routing-graph.geojson` 내보내기는 기존 계약을 유지한다.

버전 2·3·4는 열 때 공통 Level로 이전한다. 기존 RoutingFloor UUID·노드·엣지를 유지하며, 기존 SVG 태깅은 같은 SVG를 가진 층에 연결한다. 일치하는 층이 없으면 별도 층에 보존한다. 과거 노드 전용 IMDF 프로젝트에는 원본 GeoJSON이 저장되지 않았으므로 SVG에서 원본 Feature ID·속성을 복원했다고 주장하지 않는다. 새 IMDF 가져오기부터 원본 Feature를 보존한다.

## #78 / IMD-67 — 공통 정보와 공식 IMDF 내보내기

- 상단 `address`, `building`, `occupant`, `relationship`, `manifest`는 현재 층이 아니라 프로젝트 공통 정보를 편집한다. 도면이 없어도 입력 가능하며 층 삭제로 지워지지 않는다. 건물·층 관리의 JSON 편집기와 같은 원본을 쓴다.
- 주소는 여러 개 만들 수 있다. 대표 주소를 공유하고 필요한 층/호실은 별도 주소를 참조한다. Level의 주소가 없으면 Building, Building에도 없으면 Venue 주소를 따르는 공식 모델을 유지한다.
- 기존 층별 메타데이터는 UUID·속성을 보존해 이전한다. 일련번호 참조는 해당 층을 우선하여 UUID로 바꾼다. Manifest 충돌은 복사본을 보존하고 사용할 값을 명시적으로 선택하기 전까지 내보내기를 막는다. 층 하나만 가져오는 경로도 관련 공통 정보를 함께 가져온다.
- 같은 층의 동일 Manifest 충돌을 다시 가져와도 사본을 중복 추가하거나 이미 해결한 상태를 초기화하지 않는다. 처음 보는 충돌 값만 새 사본으로 보관하고 다시 선택을 요구한다. 사본 보존 및 가져오기의 Undo/Redo는 유지한다.
- 다층 파일에서 층 하나를 가져올 때 Address·Building은 선택 층의 편집 도형/원본 GeoJSON과 함께 가져오는 공통 정보가 참조하는 것만 포함한다. Building을 통한 주소 참조도 따라가며, 무관한 건물·주소의 UUID 충돌은 검사하지 않는다. 대상에 Venue/공통 Footprint가 없어 원본을 복사할 때는 그 정보에 필요한 참조도 보존한다. 구형 단일 층 파일의 미연결 공통 정보와 단일 건물·주소의 기존 기본값 경로는 유지한다.
- 가져오기 대상인 Address·Building·Occupant·Relationship의 UUID와 내용이 같으면 기존 정보를 재사용한다. 동일 UUID의 내용이 다르면 파일명과 UUID를 안내하고 가져오기 전체를 중단한다. 층·도면·공통 정보·Undo/Redo 기록은 유지되며, 두 프로젝트의 값을 일치시킨 뒤 다시 가져와야 한다(#79 / IMD-68 자체 리뷰 후속 수정).
- 이미 존재하는 층을 다른 층으로 복사할 때 충돌하는 도형의 내부 ID와 내보내기 UUID를 새로 발급한다. 속성 참조·소유권·문 대여·원본 GeoJSON·출입구 노드 참조도 함께 갱신한다. 복사된 Anchor에 종속된 Occupant/Relationship은 기존 레코드를 바꾸지 않고 새 참조를 가진 별도 레코드로 가져온다. 같은 층을 교체하고 다른 층과 충돌하지 않는 ID는 유지한다.
- 공통 정보는 삭제 시 정보 휴지통으로 이동하며 복원·Undo/Redo를 지원한다. 참조 선택창은 모든 층과 공통 정보를 조회한다. 중복 이름/일련번호 대신 UUID를 저장한다.
- `Detail`, `Kiosk`, `Relationship`을 포함한 공식 16종을 보존한다. Detail·Kiosk는 해당 레이어에서 작도하며 Relationship은 공통 정보에서 JSON Feature 참조를 입력한다. 기존 MultiLineString 및 확장 속성도 재내보내기에 보존한다. 길찾기 `routing-graph.geojson`은 공식 Relationship의 대체물이 아니다.
- 접근성 배열·문 JSON·출입 제어·상관 ID·유효 기간·Section 부모/주소 속성을 입력할 수 있다. 한국어/영어 간편 입력 외 언어는 이름의 JSON 편집기를 사용한다. 기본 언어는 새 프로젝트에서 `ko`이고 이름 LABELS는 Manifest 언어를 포함해야 한다.
- 이름 간편 입력은 Manifest 기본 언어를 포함한다(예: `ko-KR`). 내보낼 때 정확한 기본 언어 라벨이 없고 같은 언어의 일반 라벨(`ko`)이 있으면 기본 태그 라벨도 추가하며, 기존 언어 라벨은 보존한다. 자동 Level 이름·짧은 이름도 기본 태그를 사용한다. 대응하는 이름 자체가 없는 경우는 기존 엄격한 검증에서 계속 차단한다.
- **파일 → IMDF 아카이브 내보내기 (모든 층)**는 타입별 GeoJSON과 Manifest를 ZIP 최상위에 저장한다. 레이어의 개별 내보내기도 같은 전체 프로젝트 검증 뒤 해당 타입을 모든 층에서 모아 저장한다. 개별 파일 하나는 완전한 IMDF 전달물이 아니다.
- 공통 정보 편집기가 열려 있으면 개별 내보내기는 편집 중인 타입을 우선한다(예: Unit 레이어를 유지한 채 Address를 편집하면 Address 출력). 편집기를 닫으면 기존 활성 레이어/길찾기 내보내기로 돌아간다.
- 내보내기 전 Address 최소 1개·Venue 정확히 1개, 필수 속성/카테고리, UUID v4 전역 유일성, 참조 존재·타입·배열 중복·부모 순환, 좌표/Polygon 유효성, Venue 포함·Unit–Level 빈틈/겹침·Opening 경계·Anchor와 display_point 위치를 검사한다. 초안 `.imdfrnt` 저장은 허용한다.
- 실제 건물의 ground/aerial/subterranean 범위, 지면 출입층 ordinal 0 여부, 같은 외벽인 층의 정렬·실측 ±5m 정확도, 조건부 층간 시설/상관 ID 규칙은 현실 정보가 필요하다. 자동으로 주소·카테고리·모양을 추정하지 않는다. 복합 OSM 영업시간과 언어 태그의 IANA 등록 여부도 최종 Apple 검증이 필요하다. 현재 로컬 검증을 Apple 인증이나 전체 규칙 통과 보장으로 표현하지 않는다.
- [Apple 공식 Reference](https://register.apple.com/resources/imdf/reference/reference), [Level](https://register.apple.com/resources/imdf/types/level), [Footprint](https://register.apple.com/resources/imdf/types/footprint). IMDF Sandbox 업로드와 실제 화면 조작은 별도 수동 검증 대상으로 남는다.

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
