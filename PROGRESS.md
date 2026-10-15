# IM-DFrnt 진행 기록

## 2026-10-15 — #32 Xcode 프로젝트 추가

- 구현 전에 [이슈 #32](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/32)에 목표·작업 목록·완료 조건을 기록하고, 병합된 develop에서 `chore/#32-xcode-project`를 만들었다.
- `IM-DFrnt/IM-DFrnt.xcodeproj`에 macOS 앱 타깃과 공유 `IM-DFrnt` Scheme을 추가했다. 기존 `Sources/IMDFrnt`의 Swift 파일 101개를 직접 컴파일하며 폴더 동기화로 새 Swift 파일도 포함한다. Swift 6·macOS 14 설정을 유지한다.
- Xcode에서 `IM-DFrnt → My Mac → ⌘R`로 실행할 수 있다. 로컬 ad-hoc 서명을 사용하며 개발자 Team을 지정하지 않고 Debug·Release를 빌드했다. Debug 서명의 `get-task-allow`도 확인했다.
- 앱·문서 연결 정보를 `Configuration/Info.plist`로 옮겨 Xcode와 `build-app.sh`가 공유한다. 기존 리뷰 수정 앱의 메타데이터와 완전히 같고, 두 Xcode 앱과 Swift Package 앱에서 `.imdfrnt`/`.imdfproj`·SVG/PNG/JPG 등록, 실행 파일명, 샘플 리소스와 서명을 확인했다.
- Xcode 27.0에서 프로젝트·Scheme 인식, Debug 및 Release(arm64·x86_64) 빌드, 기존 Swift Package 번들 빌드와 엄격한 서명 검사를 통과했다. Swift 컴파일 경고는 없고 Xcode의 AppIntents 메타데이터 추출 생략 경고만 남는다. 최초 sandbox 빌드는 SwiftUI 매크로 실행이 제한돼 실패했으며, 같은 명령을 sandbox 밖에서 실행해 통과했다.
- Xcode Release 앱에서 기본 입력으로 CLI 6/6 모드 통과: SVG ALL PASS, Building 27/27, Project 23/23, Document open 24/24, Routing 100/100, Drawing Loading 49/49. 로그: `/private/tmp/imdfrnt-issue32-xcode-self-tests.log`, `/private/var/folders/y_/53_320qj4pqcgw5hp41cgr2m0000gp/T/imdfrnt-self-tests.g2sctE`. 빌드 로그: `/private/tmp/imdfrnt-issue32-xcode-debug.log`, `/private/tmp/imdfrnt-issue32-xcode-release.log`, `/private/tmp/imdfrnt-issue32-spm-build.log`.
- Xcode에 프로젝트 열기를 요청했다. UI 자동화는 `Sky Computer Use native pipe startup failed`로 연결되지 않아 Xcode의 실제 ⌘R 조작·앱 화면은 별도 확인 대상이다. CLI 성공을 GUI 확인으로 표시하지 않는다.

## 2026-10-15 — PR #27 P2 리뷰 반영

- 코드 변경 전 #20에 두 P2의 재현·수정·완료 조건을 기록했다. 기존 PR #27과 `feat/#20-level-drawing-management`에서 수정한다.
- Finder SVG/이미지 열기에서도 비동기 검증 후 기존 미저장 변경 확인을 실행한다. 기준점만 수정한 작업도 저장·폐기·취소를 거치며, 취소/저장 창 취소/손상 입력에서는 기준점·도면·복구본·Undo 기록을 바꾸지 않는다. 명시적 층 도면 가져오기의 기존 확인 흐름을 유지한다.
- 준비된 도면과 색인을 설치한 뒤 `refreshOpenRingGaps()`를 호출한다. 캐시 없는 Undo에서 도면이 nil일 때 비워진 경고를 다시 계산한다.
- 실제 수정 전 코드에 회귀 검사를 추가해 기본 입력 40/49 PASS(9개 실패)로 두 문제를 재현했다. SVG·PNG·JPG 확인 누락과 취소 시 데이터 변경, 저장 취소 무시/저장 누락, 실제 틈 2곳인데 경고가 0개인 Undo가 실패했다. 수정 후 같은 기본 입력은 49/49 PASS다.
- Swift 6 Release 빌드(경고 없음), 번들 서명, diff 검사를 통과했다. 실제 C5 폴더·현재 사용자 테스트 프로젝트로 6/6 CLI 모드 통과: SVG ALL PASS, Building 34/34, Project 23/23, Document open 24/24, Routing 102/102, Drawing Loading 46/46. 도면 검사 수는 입력 층 수에 따라 달라진다.
- 로그: `/private/var/folders/y_/53_320qj4pqcgw5hp41cgr2m0000gp/T/imdfrnt-self-tests.LUiJi2`; 동일 기본 입력의 수정 전/후 로그: `/private/tmp/imdfrnt-pr27-review-before-test.log`, `/private/tmp/imdfrnt-pr27-review-fixed-test.log`. 검사 앱: `/private/tmp/IMDFrntPR27Review-Fixed.app`.
- 검사는 실제 비동기 열기·Undo 명령과 확인 응답 주입을 사용한다. Finder 이벤트/네이티브 alert 버튼을 실제로 클릭해 검증한 것으로 표시하지 않는다.

## 2026-10-14 — #20 층별 도면·#26 전환 버퍼링

- 구현 전 #20·서브 이슈 #26에 작업 목적과 완료 조건을 기록하고, 병합된 develop에서 `feat/#20-level-drawing-management`를 만들었다. #18·#19는 닫힌 상태를 유지한다.
- 실제 사용자 테스트 프로젝트의 SVG(3,442개/1,563개 개체)를 확인했다. Light SVG의 기존 전환 로직은 매번 5.29~5.34초가 걸렸다. 캐시된 실제 층 재전환은 약 0.3~0.5ms이며 재파싱·파생 계산이 증가하지 않는다. 화면 첫 프레임까지의 시간이 아닌 선택 명령·도면 모델 적용 시간이다.
- 최초 준비는 약 5.3초이고 백그라운드에서 수행한다. 메인 액터의 10ms 간격 확인 작업이 424회 실행되어 응답성을 확인했다. 도면보다 먼저 층 메타데이터·탭바를 적용하고 마지막 선택만 반영한다.
- SVG/이미지 읽기·파싱과 도면 색인·Path·다각형 진행률을 캐싱했다. 도면 캐시는 최대 6개/추정 128 MiB, 준비 작업은 최대 2개이며 인접 층을 미리 준비한다. 교체·삭제·Undo·프로젝트 교체에서 오래된 비동기 결과를 막고 로딩 중 이전 층 색인을 비운다.
- IMDF 위의 SVG 참고 레이어와 건물 Footprint 배경을 분리했다. SVG 원문·파일명·층별 표시/불투명도와 건물 전역 Footprint 표시 설정을 v5의 선택적 필드로 저장한다. 원본 IMDF geometry·투영·노드 좌표와 기존 파일 이전을 유지한다. 참고 도면 삭제는 빨간 버튼·확인·취소·Undo를 지원한다.
- Swift 6 언어 모드 Release 빌드·ad-hoc 서명·diff 검사를 통과했다. 원래 UI 코드의 actor/Sendable 경고를 정리했고 최종 빌드 경고는 없다. SVG ALL PASS, Building 34/34, Project 23/23, Document open 24/24, Routing 102/102, Drawing Loading 30/30으로 6개 모드 모두 종료 코드 0이다. C5 폴더와 실제 사용자 테스트 프로젝트를 읽기 전용으로 사용했다.
- 로그: `/private/var/folders/y_/53_320qj4pqcgw5hp41cgr2m0000gp/T/imdfrnt-self-tests.AhTbpG`. 앱: `/Users/dd/Applications/IM-DFrntIssue20.app`. [사용법과 수동 확인](docs/projects/LEVEL_DRAWINGS.md)을 기록했다.
- UI 자동화가 `Sky Computer Use native pipe startup failed`로 연결되지 않고 테스트 창도 조회하지 못했다. 실행 프로세스와 모델·명령 검증을 실제 버튼 입력·화면 검증으로 해석하지 않는다. 원본 복구본과 분리한 QA 복사본으로 앱을 실행하며 실제 탭·Picker·레이어·삭제 알림 확인은 미완료로 남긴다.

## 2026-10-08 — 삭제 확인 통일·선택 엣지 Delete

- 구현 전에 기존 [UI 이슈 #16](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/16)에 요청과 완료 조건을 추가하고 `feat/#16-floor-node-ui`에서 이어서 진행했다.
- 층 우클릭 메뉴를 빨간 `층 삭제`로 표시하고 말줄임표를 없앴다. macOS 네이티브 메뉴에 빨간 attributed title과 휴지통을 지정하며, 메뉴가 열린 동안 캔버스의 키보드 처리를 중지한다. 셀 전체의 클릭 영역과 접근성 선택·메뉴 동작을 유지한다.
- 층·노드·엣지·길찾기 기준점 및 도면 편집의 개체·Anchor·임시 문 삭제 버튼을 빨간 레이블/아이콘으로 통일하고 공통 확인 alert를 거치게 했다. 선택한 노드·엣지의 Delete/Forward Delete도 같은 확인을 요청하며 취소가 기본 버튼이다.
- 확인 요청은 대상 ID와 프로젝트 ID를 고정한다. 취소·중복 입력·선택 변경·문서 전환으로 다른 데이터를 삭제하지 않으며, 확정한 엣지는 양 끝 노드를 남긴다. 삭제 확정은 한 번의 실행 취소로 복구한다. Anchor 삭제도 기존 실행 취소 기록을 사용하도록 연결했다.
- 릴리즈 빌드·서명 검사 통과. 실제 C5 폴더·ZIP 포함 Routing 104/104 PASS, 기존 회귀 ALL PASS. 확인 취소/확정·중복 요청·대상 변경·문서 전환·저장/재열기·텍스트 입력 보호·실행 취소/다시 실행을 검사했다.
- 실제 UI에서 선택한 엣지의 Delete → alert → 취소, 연결 삭제 버튼 → 확정(25→24개, 노드 유지) → ⌘Z 복구를 확인했다. 노드 삭제 alert의 연결 4개 안내와 취소, 활성화된 `층 삭제` 메뉴의 말줄임표 제거·2층 alert·취소도 확인했다. 캔버스 노드·연결에 비시각적 접근성 선택 동작을 추가했다.
- 메뉴·버튼의 빨간색 자체를 최종 화면으로 확인하는 작업은 화면 캡처 오류로 미완료다. 실제 메뉴 동작과 명시적 빨간색 지정은 확인했으며, 기존 셀 여백 클릭·전체 카테고리 변경·Option 유지 드래그의 실제 입력 검증과 함께 이슈를 열어 둔다.
- 최신 앱을 실행해 둔 상태다. 검증 후 자동 저장 routing 전체가 이번 작업 전 백업과 동일하다: 층 6개·노드 17개·연결 25개. 로그: `/tmp/imdfrnt-delete-alert-routing-20261008.log`, `/tmp/imdfrnt-delete-alert-regression-20261008.log`.

## 2026-10-08 — 층 셀 선택·우클릭 삭제 확인·노드 색상

- 구현 전에 기존 [UI 이슈 #16](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/16)에 요청과 완료 조건을 추가했다. `feat/#17-command-node-export`의 `ed9dd4c`에서 `feat/#16-floor-node-ui`를 만들었다.
- 층 셀 전체에 클릭 영역을 지정하고 상시 휴지통 버튼을 없앴다. 우클릭의 `층 삭제…`를 선택하면 층 이름·노드 수·층간 연결 삭제 범위를 안내하는 alert가 뜨고 취소/삭제를 선택한다. 기존 층·노드·연결 삭제와 실행 취소를 재사용한다.
- 노드 색상을 일반 통로·교차점 파랑, 출입구 초록, 계단 주황, 엘리베이터 보라, 목적지 분홍으로 구분한다. 카테고리 메뉴도 같은 색상을 표시한다. 저장·내보내기의 카테고리 문자열과 선택 광택·핀 크기·하단 ID는 유지한다.
- 릴리즈 빌드 및 서명 검사 통과. 실제 C5 폴더·ZIP 포함 자체 검사 83/83 PASS, 기존 회귀 ALL PASS. UI에서 층 선택·우클릭 메뉴·삭제 alert·취소를 확인하고, 검증용 빈 층의 삭제 확정·실행 취소를 확인한 뒤 층 추가 자체도 되돌렸다.
- 화면에서 파랑·초록·주황 핀과 하단 ID를 확인했다. 좌표 클릭 자동화의 `noWindowsAvailable` 오류 및 이후 사용자 화면 변경 감지로 셀의 빈 여백 클릭과 보라·분홍을 포함한 카테고리 변경의 실제 입력 검증은 미완료로 기록한다.
- 최신 앱을 실행했다. 검증 후 자동 저장본의 routing 전체가 백업과 동일하며 기존 6개 층·노드 18개·연결 26개를 보존했다. 로그: `/tmp/imdfrnt-floor-node-routing-20261008.log`, `/tmp/imdfrnt-floor-node-regression-20261008.log`.

## 2026-10-07 — Command 클릭 노드 추가·클라이언트 출력 점검

- 구현 전에 컨벤션에 맞춘 [이슈 #17](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/17)을 등록했다. 담당자 `logichoon-redo`, 라벨 `enhancement`, 작업 브랜치 `feat/#17-command-node-export`다.
- 모든 노드 편집 도구에서 ⌘+클릭으로 현재 층에 노드를 추가한다. 일반 클릭은 선택, 기존 핀의 ⌘+클릭도 선택만 하고 중복 생성·연결을 하지 않는다. ⌘+드래그는 노드 이동·추가와 화면 이동을 하지 않으며 Option 드래그 연결을 유지한다. 입력 시작 시 modifier를 기억해 마우스를 놓기 전에 Command를 놓아도 클릭 의도를 유지한다.
- 지정한 클라이언트 원격 브랜치를 fetch해 최신 HEAD가 `8274d1d`임을 다시 확인했다. 그래프 로더·경로 탐색 구현은 없고 최소 GeoJSON fixture 및 헤더를 읽는 테스트가 있다.
- 내보내기는 JSON 기반 `routing-graph.geojson`이다. 실제 생산 코드로 샘플 및 C5 지도 노드 2개·연결 1개를 내보내고 클라이언트 fixture의 필수 필드·타입·좌표·연결 ID 참조를 검사했다. C5 출력은 원본 IMDF 층 UUID·ordinal도 일치한다. 형식 변경이 필요한 불일치는 없었다. 이름·메타데이터·추가 카테고리 해석과 실제 경로 탐색은 클라이언트 로더 구현 이후 검증한다.
- 자체 검사 83/83, 기존 회귀 ALL PASS, 릴리즈 빌드 통과. 사용자 자동 저장본을 별도 백업했으며 검사 실행은 자동 저장본을 읽거나 덮어쓰지 않는다.
- 출력 검사기는 잘못된 노드 참조·위경도 순서·접근성 타입·층 ordinal·schema_version 타입의 오류 입력 5개를 모두 거절했다. 서명 검사 통과 및 사용자 routing 저장 데이터가 백업과 동일함을 확인했다.
- 최종 UI 확인·재실행은 자동화 도구의 `Sky Computer Use native pipe startup failed`가 재연결 뒤에도 반복되어 완료하지 못했다. Command modifier의 클릭 처리 자체는 자체 검사로 확인했고 실제 마우스 입력 경로는 코드 검토 범위다. 업데이트 앱 번들은 빌드 완료 상태다.
- 재사용 가능한 출력 검사기 `scripts/validate-routing-export.py`와 [사용법](docs/routing/NODE_EDITOR.md)을 추가했다.

## 2026-10-06 — 노드 표시와 드래그 연결 UX 개선

- [이슈 #16](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/16)에 관련 UI 요청을 하나로 묶었다. 이슈를 먼저 기록하라는 요청 이후의 추가 변경은 등록 후 진행했고, 이후 작업 규칙을 `AGENTS.md`에 남겼다.
- `C6 GitHub 작업 컨벤션`에 맞춰 #16의 본문을 목표·작업 목록·완료 조건으로 정리하고 담당자 `logichoon-redo`와 `enhancement` 라벨을 지정했다. 구현과 자동 검증 완료 항목은 체크하고 실제 UI 확인 2개는 미완료로 유지한다. 향후 이슈 작성 규칙에도 본문 형식·체크박스·담당자·라벨을 반영했다.
- 핀을 화면 기준 지름 8pt로 줄이고 선택 시 크기 변경 없이 주변에 파란빛을 표시한다. 짧은 UUID는 핀 하단에 8pt·50% 불투명도로 표시하고 이름은 위에 표시한다. 줌·회전에도 표시 크기와 글자 방향을 유지한다. 표시 ID 접두사가 겹치면 구분되는 길이까지 늘리며 원본 UUID를 바꾸지 않는다.
- Option + 핀 드래그로 포인터를 따라오는 연결선을 표시하고 대상 노드에서 놓으면 연결한다. 연결 중 노드를 이동하지 않으며 빈 곳·자기 자신에 놓기와 Escape는 취소한다. `노드 연결` 도구의 일반 드래그와 층간 두 번 클릭도 유지한다.
- 연결 미리보기는 저장·실행취소 기록에서 제외하고 실제 연결만 한 번 기록한다. 삭제·층 전환·문서 전환·실행취소에서 임시 연결을 정리한다.
- 실제 C5 IMDF 폴더·ZIP을 포함한 자체 검사 70/70 통과, 기존 회귀 검사 ALL PASS. 실제 UI에서 핀 선택·연결 도구 드래그·빈 곳 취소·연결 실행취소를 확인했다. 자동화 도구는 Option을 누른 채 드래그하는 입력을 지원하지 않아 해당 modifier 입력 자체는 실제 UI 검증에서 제외했다.
- 하단 ID 변경을 포함한 최종 릴리즈 빌드·서명 검사 통과. 최신 앱에서 저장된 IMDF를 다시 열었고 사용자 노드 2개와 전체 routing 저장 데이터가 검사 전 백업과 동일함을 확인했다. 최종 화면 캡처는 도구가 창을 왜곡해 반환해 하단 글자의 시각 검증에 사용하지 못했다.
- [사용법과 출력 계약](docs/routing/NODE_EDITOR.md).

## 2026-10-06 — 완성된 IMDF 입력 후 노드 편집

- 사용자가 노드 편집은 IMDF를 만든 이후의 작업이라고 명확히 했다. SVG·이미지를 먼저 열던 진입 흐름을 수정했다.
- `IMDF 불러오기…`(⌘⇧I)로 ZIP·폴더 또는 그 안의 manifest.json/level.geojson을 열면 층별 지도와 실제 층 UUID·ordinal을 가져오고 노드 편집 화면으로 바로 이동한다.
- 원본 level·unit·fixture·opening·amenity 등의 지오메트리를 재사용한다. Polygon 구멍과 MultiPolygon을 유지하고 amenity의 unit 참조를 층으로 연결한다. 모든 층이 같은 표시 좌표계를 공유한다.
- IMDF 위경도로 노드를 바로 내보내므로 수동 기준점이 필요 없다. 지도와 가역 좌표 변환을 프로젝트 버전 4에 내장하고 기존 버전 2·3 작업을 읽는다. IMDF 재열기는 노드 화면으로 진입한다.
- ZIP은 파일을 디스크에 풀지 않고 필요한 항목만 읽는다. 가져오기는 백그라운드에서 수행하고 입력 오류 시 현재 작업을 유지한다. 새 IMDF는 새 프로젝트로 열어 이전 작업 파일을 덮어쓰지 않는다.
- 실제 클라이언트 C5 IMDF 폴더·ZIP(6개 층) 포함 자체 검사 57/57 통과, 기존 회귀 검사 ALL PASS. 실제 UI에서 ZIP 선택·층별 지도·노드 2개 배치·연결·GeoJSON 저장을 확인했고 출력의 위경도 및 실제 level ID를 검사했다. UI 검사 도구의 일시적 시간 초과는 화면 관찰로 정상 가져오기를 확인했다.
- 현재는 ordinal이 중복되지 않는 건물 하나의 IMDF를 지원한다. 클라이언트 그래프 로더·길찾기 실행은 이전 기록과 같이 별도 작업이다.
- [사용법](docs/routing/NODE_EDITOR.md).

## 2026-10-06 — 길찾기 노드 편집

- 사용자의 요청으로 자동 정합 구현을 기존 코드에서 분리했다. 폐기 전 최종 코드는 로컬 `archive/georef-prototype-2026-10-06` (`e18c542`)에 보관하고, `8da60ab`에서 `feat/routing-node-editor`를 시작했다.
- 기존 `CanvasView`와 좌표 변환·확대·이동, 실행취소, 프로젝트 저장·자동 저장을 재사용했다. 기존 태깅 작업은 별도로 유지한다.
- 층별 원본 SVG·PNG·JPG 불러오기, 클릭으로 노드 추가·선택, 이름·카테고리·JSON 메타데이터 편집, 드래그 이동, Delete, 연결선 선택·삭제, 양방향 연결, 계단·엘리베이터 층간 연결을 구현했다.
- 노드 삭제는 연결을 함께 정리하고 실행취소로 복원한다. 텍스트 편집 중 Delete는 글자만 지운다. 층 삭제도 실행취소 가능하다. 연결 없는 노드 및 그래프의 분리된 그룹 수를 표시한다.
- 클라이언트 `level.geojson` 또는 `IndoorMapDocument`의 층 목록을 가져와 UUID·ordinal을 맞출 수 있다. 층별 좌표 기준점으로 실제 WGS 84 좌표를 만든다.
- 전체 층의 그래프를 클라이언트 테스트 fixture에 맞춘 GeoJSON으로 내보낸다. 확인한 클라이언트 `feature/indoor-routing-foundation` (`8274d1d`)에는 아직 그래프 로더·경로 탐색 구현이 없으므로, iOS에서 길찾기 실행까지 검증했다고 주장하지 않는다.
- 프로젝트 버전 3에 그래프·층별 도면·기준점을 저장하며 버전 2 파일도 읽는다. 새 화면에서 합성 데모를 자동 적재하지 않는다.
- 검증: 릴리즈 빌드·서명 검사, 노드 자체 검사, 기존 회귀 검사, 실제 UI의 클릭·이름 편집·텍스트 Delete·노드 Delete·연결·실행취소·PNG 원본 불러오기·새 층 분리. 클라이언트 fixture의 필수 키·타입·연결 참조도 출력과 비교했다.
- [사용법과 출력 계약](docs/routing/NODE_EDITOR.md). 아래 자동 정합 기록은 이전 작업의 이력이다.

## 2026-09-30 — 백로그 등록

### 완료

- 사용자 제공 AUTO_GEOREF_TASK 명세와 이후 제품 범위 확정을 바탕으로 [백로그](docs/georef/BACKLOG.md)를 작성했다.
- GitHub 이슈 #6–#15를 등록했다. 목표, 작업 체크리스트, 완료 조건, 선행 의존 관계, 라벨과 담당자를 지정했다.
- 기존 관련 이슈 #4의 원래 요청은 보존하고, 백로그를 후속 목록으로 연결한다.
- 방향키 기반 후보 검토, 보류·해당 없음, 최종 적용·실행 취소 동작을 #13에 기록했다.

### 최초 등록 당시 구현 상태

아래는 10개 이슈로 등록했던 시점의 기록이다. 이후 기능 단위 통합 결과는 이 문서의 최신 항목과 BACKLOG.md에서 관리한다.

| 단계 | 이슈 | 상태 |
|---|---|---|
| M0 | #6 | 미착수 |
| M1 | #7 | 미착수 |
| M2 | #8 | 미착수 |
| M3 | #9 | 미착수 |
| M4 | #10 | 미착수 |
| M5 | #11 | 미착수 |
| M6 | #12 | 미착수 |
| M7 UI | #13 | 미착수 |
| M7 IMDF | #14 | 미착수 |
| M7 Raster | #15 | 미착수 |

### 측정 지표

이번 작업은 백로그 등록 단계다. 매칭 성공률, 자동 수락 오답률, 모호성 탐지율, 처리 시간과 실제 위치 정확도는 아직 측정하지 않았다.

`feature/anchor-map-automation`의 기존 보조 정합 프로토타입(commit `ed8250b`)은 별도 선행 작업이다. 일반 지도와 후보 생성 경험을 제공하지만, 이 백로그의 독립 패키지·고정 metric scale·다중 가설·모호성 게이트 완료로 계산하지 않는다.

### 명세와 제품 범위의 차이

- 전체 건물 도면만 대상으로 하고 부분 홀 정합은 제외한다.
- 출입구 대응과 실내·실외 경로 연결은 클라이언트 범위다. 출입구 및 관련 도로 단서, 출입구 로더를 필수 항목에서 제외한다.
- 출입구 단서 평가 대신 독립 방위 단서를 사용하는 대칭 평가를 #10에 기록했다.
- M7을 UI 통합, IMDF 출력, 래스터 입력으로 나눴다.
- `created` 시각과 결정성 계약은 M0에서 구현 전에 확정한다. Provider 응답·정책 및 validator 차이는 해당 단계에서 확인한다.

### 다음 단계

[#6 — 독립 georef 패키지와 좌표계·Provider·캐시 기반](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/6). 이번 백로그 작업에서 구현은 시작하지 않았다.

## 2026-09-30 — 저장소 이관

- 이후 작업 저장소를 `adap-c6-fingerprint/IMDFrnt`로 변경했다. 현재 로컬 경로는 `/Users/dd/Downloads/IMDFrnt`다.
- 기존 레거시 및 앵커 보조 자동화 커밋이 새 저장소에 동일한 해시로 존재함을 확인했다.
- 누락된 백로그 이슈 10개를 새 저장소 #6–#15로 재등록했다. 담당자·라벨·완료 조건·선행 관계를 유지했다.
- 이전 백로그·진행 문서 커밋을 보존하고 활성 링크를 새 저장소로 바꿨다. #4에는 새 이슈 목록을 연결한다.
- 이전 HTML UX 개념 시안은 원본 참고 자료로 보존했다. 현재 범위에서 출입구 대응이 제외된 사실을 함께 기록했다.
- [이관 기록](docs/georef/MIGRATION.md)에 커밋, 이슈와 로컬 경로를 정리했다.

이관은 코드 보존 및 기록 복원 작업이다. 매칭 성공률·runtime 측정이나 새 엔진 구현 상태는 변경하지 않았다.

## 2026-09-30 — 기능 단위 통합과 기존 지도 조회 재사용

### 판단 근거

- 사용자가 이슈 분할이 많다고 지적했고, 지도 데이터 연동은 이미 구현되어 있다고 알려줬다.
- `feature/anchor-map-automation`의 `ed8250b` 소스를 확인했다. `PlaceSearch.swift`의 MapKit 검색, `BuildingFootprints.swift`의 OSM API 0.6 조회, `AnchorScreen.swift`의 일반 지도 및 조회 연결이 존재한다.
- 이 기능을 재개발하는 독립 이슈 대신 기존 결과를 엔진에 연결하고 필요한 검증을 보완한다.

### 백로그 조정

- 활성 백로그를 핵심 기능 3개와 후속 확장 1개로 통합했다.
- #7–#12를 #6의 내부 작업·완료 조건으로 옮기고 통합 사유를 기록해 닫았다. 닫힘은 백로그 통합에 따른 것이며, 구현 상태는 #6에서 관리한다.
- #13의 선행 관계를 #6으로 바꿨다. #14는 #13, 후속 #15는 #14에 연결한다.
- M0–M7의 상세 검증 순서는 문서와 기능 체크리스트에 유지한다.
- M5를 기존 MapKit/OSM 경로의 Candidate·provenance 연결 및 정책·캐시·실패 처리 검증으로 조정했다. 추가 Provider 개발은 이번 필수 범위에서 제외한다.

| 활성 이슈 | 기능 | 상태 |
|---|---|---|
| #6 | 전체 건물 자동 정합 엔진 | 미착수, 기존 지도 조회 재사용 |
| #13 | 자동 후보·방향키 검토 UX | 미착수 |
| #14 | 확정 결과 저장·IMDF 출력 | 미착수 |
| #15 | 래스터 입력 확장 | 후속·미착수 |

소스 확인과 백로그 정리만 진행했다. 신규 정합의 정확도·runtime 지표는 아직 측정하지 않았다.

## 2026-09-30 — #4 중복 종료

- #4의 도면 정렬·기준점 지정 범위가 #6(자동 정합 엔진)·#13(후보 검토 UX)으로 통합되었음을 확인했다. 출력은 #14에서 관리한다.
- #4에 `duplicate` 라벨과 `Duplicate of #6` 및 관련 범위 설명을 남기고 닫았다. 기존 본문·검토 기록을 보존했다.
- 활성 이슈의 #4 참조는 ‘통합 전 요청’으로 바꿨다. #4를 진행 중인 상위 작업으로 관리하지 않는다.
- 닫힘·라벨·대체 이슈 링크를 GitHub API로 확인했다. 구현 상태와 정확도·runtime 측정 상태는 유지한다.

## 2026-10-13 — #18 새 프로젝트 생성·기존 작업 저장

- `feat/#18-new-project-save`를 #16이 머지된 `develop`의 `c32cc62`로 맞추고 구현 전 #18에 계획·담당자·라벨을 기록했다.
- 파일 메뉴·⌘N으로 새 프로젝트를 만들고 document·feature·Anchor·routing·선택·임시 편집·Undo/Redo를 초기화한다. 새 UUID와 현재 schema version 4를 기록한다.
- 도면 없는 프로젝트 저장/재열기를 지원한다. 빈 프로젝트에 도면·IMDF를 넣을 때 ID와 저장 위치를 유지한다.
- 새 프로젝트·다른 입력 열기·창 닫기·종료에서 저장/저장하지 않음/취소를 확인한다. 저장 창 취소·파일 쓰기 실패는 기존 데이터를 유지한다.
- 프로젝트 이름·저장 상태를 표시한다. 자동 저장은 복구본만 갱신하며 저장하지 않고 종료한 변경을 다음 실행에서 복원하지 않는다.
- 최종 검사: Project 23/23 PASS, 실제 C5 IMDF 폴더·ZIP 포함 Routing 104/104 PASS, 기존 회귀 ALL PASS, 릴리즈 빌드·서명 검사 통과. 사용자 복구 파일 SHA-256 보존 확인.
- 정상 ZIP 입력은 실제 클라이언트 C5 IMDF 폴더를 압축해 검증했다. 처음 지정한 다운로드 ZIP은 IMDF의 level.geojson이 없는 다른 형식이라 거절됐으며 원본은 변경하지 않았다.
- UI 도구의 `Sky Computer Use native pipe startup failed`로 실제 파일 메뉴·저장 대화상자·종료 입력과 캡처는 미확인이다. 완료로 표시하거나 이슈를 닫지 않는다.
- 실행 앱: `/private/tmp/IM-DFrntIssue18Final.app`. 상세 사용법과 검사 절차: `docs/projects/PROJECT_LIFECYCLE.md`.

## 2026-10-13 — #18 리뷰 보완: Finder 프로젝트 열기

- [#18에 리뷰 보완 목표와 완료 조건](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/18#issuecomment-6137561168)을 먼저 기록했다. `.imdfrnt` UTI만 있고 앱의 프로젝트 문서 타입과 외부 파일 이벤트가 없던 P2 지적을 수정했다.
- `.imdfrnt`·이전 `.imdfproj`를 Editor/Owner 문서로 등록하고 SVG·PNG·JPEG 연결을 유지한다. 환경 연결 전 요청을 대기하고, 파일 메뉴와 Finder의 검증·미저장 확인·복구 처리를 공유한다.
- 현재 프로젝트 재요청은 미저장 편집을 유지하며 가져오기·모달 중에는 기다린다. 여러 파일 요청은 부분 교체 없이 거절한다.
- 문서 열기 23/23 PASS, 프로젝트 23/23 PASS, 실제 C5 폴더·ZIP 포함 Routing 104/104 PASS, 기존 회귀 ALL PASS, 릴리즈 빌드 통과. 일반 설치 경로의 별도 번들 ID·복구 경로에서 기본 파일 연결과 앱 시작/실행 중의 실제 시스템 파일 전달을 확인했다. 검증용 등록과 앱은 정리했다.
- Finder UI의 물리적 더블클릭과 저장 확인 버튼 입력은 도구 연결 오류로 미확인이다. 시스템 파일 전달 검증과 구분한다.
- Finder 수정은 #18 브랜치/PR에서만 커밋한다. #19는 갱신된 #18을 기준으로 #19 기능 커밋만 비교하도록 유지한다.
- 로그: `/private/tmp/imdfrnt-finder18-open-test.log`, `imdfrnt-finder18-project-test.log`, `imdfrnt-finder18-routing-test.log`, `imdfrnt-finder18-regression-test.log`.
## 2026-10-13 — #19 공통 건물·Level 관리

- [#19](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/19)에 구현 시작·완료 조건을 먼저 기록하고 `feat/#19-building-level-management`를 #18 브랜치에서 생성했다. #18은 아직 develop에 병합되지 않아 이 브랜치는 #18에 의존한다.
- `.imdfrnt` 버전 5에서 건물 전역 IMDF 정보와 공통 Level을 저장한다. 각 층이 도면·GeoJSON Feature·기존 태깅·기준점·노드·층 내부 엣지를 가지며 층간 엣지는 프로젝트에 보관한다. RoutingGraph는 기존 노드 화면·내보내기용 호환 뷰다.
- 상단 공통 층 선택과 건물·층 관리 화면을 추가했다. 이름·shortName·ordinal·Level UUID 편집, 중복 차단, 확인 후 층 삭제 및 Undo/Redo를 지원한다. 첫 SVG 입력과 복구에서 이미 작성한 건물 정보를 보존한다.
- IMDF 폴더·ZIP의 JSON/GeoJSON과 manifest, 원본 Feature ID·geometry·properties·참조·unknown fields·collection header를 보존한다. 화면용 SVG는 재열기 시 실제 geometry로 재구성하며 기존 노드 좌표 변환을 유지한다. 기존 v4 노드 전용 파일에 없던 원본 Feature 메타데이터를 SVG에서 복원하는 기능은 포함하지 않는다.
- 건물·Venue·주소 properties와 Manifest의 JSON 편집, 실제 위경도 Polygon/MultiPolygon으로 Footprint 생성·수정·삭제·미리보기와 Undo/Redo를 추가했다. SVG 참고 레이어 표시/투명도는 #20, 독립 DraftShape 마우스 작도는 #21에서 진행한다. 전체 IMDF ZIP 내보내기 UI는 후속 범위다.
- 최종 검증: Building 37/37 PASS, Project 23/23 PASS, 실제 C5 폴더·ZIP 포함 Routing 104/104 PASS, 기존 회귀 ALL PASS. C5 6개 층·unit 167개·건물 1개·Footprint 2개와 원본 GeoJSON 왕복을 확인했다.
- 사용자 실제 v4 복구본의 6개 층·노드 72개·연결 87개를 읽기 전용으로 이전해 데이터·UUID·메타데이터·연결 및 클라이언트 GeoJSON 출력 바이트가 동일함을 확인했다. 원본 복구 파일 SHA-256은 검사 전과 같다.
- 앱: `/private/tmp/IM-DFrntIssue19.app`. 로그: `/private/tmp/imdfrnt19-building-final.log`, `imdfrnt19-project-final.log`, `imdfrnt19-routing-final.log`, `imdfrnt19-regression-final.log`. 실제 UI 입력 검증은 `Sky Computer Use native pipe startup failed`로 미완료여서 이슈를 열어 둔다.
- [사용법과 저장 구조](docs/projects/BUILDING_LEVELS.md).

## 2026-10-13 — 팀 리뷰 요청에 따른 #18·#19 통합 PR

- 리뷰어는 stacked PR을 없애고 #18 변경을 포함한 하나의 PR로 다시 리뷰해 달라고 요청했다. 사용자가 통합 PR 방향을 선택해 이전 이슈별 PR 유지 방안을 변경했다.
- #18 생성·저장 및 Finder 수정, #19 건물·공통 Level 관리 커밋을 보존하고 PR #23의 기준을 develop로 변경한다. PR #24는 PR #23으로 대체한다. #18 브랜치와 분리 전 #19 로컬 백업을 유지한다.
- 통합 코드 검증: Building 37/37 PASS, Document open 23/23 PASS, Project 23/23 PASS, 실제 C5 폴더·ZIP 포함 Routing 104/104 PASS, 기존 회귀 ALL PASS, 릴리즈 빌드·서명 통과. 사용자 복구 파일 SHA-256 보존 확인.
- 남은 UI 확인은 완료로 표시하지 않는다. #20 참고 레이어·투명도, #21 DraftShape 마우스 작도는 후속 범위다.
- 로그: `/private/tmp/imdfrnt-integrated-building.log`, `imdfrnt-integrated-document-open.log`, `imdfrnt-integrated-project.log`, `imdfrnt-integrated-routing.log`, `imdfrnt-integrated-regression.log`.

## 2026-10-13 — PR #23 리뷰 후속: UUID·검사 진입·빌드 경고

- [기존 #19에 후속 목표와 완료 조건](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/19#issuecomment-6140485244)을 먼저 기록했다.
- non-optional UUID의 항상 참인 nil 비교를 제거했다. 발급 대장과 재열기 대장에서 optional UUID를 실제로 꺼내고, 기록이 없으면 실패하며 원래 UUID와 같은지 비교한다.
- 검사가 AppKit/LaunchServices 초기화 뒤에 시작해 리뷰 환경에서 exit 134로 재현되지 못한 피드백을 반영했다. CLI 검사 분기를 SwiftUI 앱 시작 전 진입점으로 옮기고 문서 검사의 NSApplication 초기화 의존성을 제거했다. 일반 앱은 SwiftUI 앱 진입점으로 연결한다.
- deprecated `onChange` 5곳을 두 인자 API로 변경했다. Release 빌드 로그 경고 없음, ad-hoc 서명 검사 통과.
- 기본 sandbox CLI 실행으로 5개 모드 모두 exit 0: 기본 Building 27/27·Document open 24/24·Project 23/23·Routing 100/100·기존 회귀 ALL PASS. 실제 C5 폴더·ZIP·기존 v4 입력을 포함하면 Building 37/37·Routing 104/104 PASS. 사용자 원본 복구 파일 SHA-256 유지.
- `IM-DFrnt/run-self-tests.sh`가 모드별 종료 코드·전체 로그·환경·바이너리 SHA-256을 남긴다. 문서 CLI 검사는 공통 요청 처리와 선언·입출력을 확인하며 실제 Finder 이벤트·UI 버튼 입력은 별도 검증이다.
- [재현 명령과 검증 범위](docs/projects/SELF_TESTS.md). UI 도구 연결은 다시 `Sky Computer Use native pipe startup failed`로 실패했으며 건물·층 관리 UI 확인은 완료로 표시하지 않는다.
