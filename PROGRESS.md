# IM-DFrnt 진행 기록

## 2026-10-15 — #37 Opening 두 점 태깅

- [이슈 #37](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/37)에 목표·작업 목록·완료 조건을 기록하고, #21 커밋 위에 `feat/#37-opening-two-point`를 만들었다(#21 PR 병합 후 병합).
- C5 도면은 문 회전 호가 점선(짧은 선분 여러 개)이라 곡선 하나로 고를 수 없었다(#35). '문 임시로 닫기' 창은 유지하고 문짝·호를 고르는 단계를 없앴다. 흐름은 **문 선 양 끝 두 점 찍기 → 임시 문 저장(Return) → '모두 Openings 레이어에 반영하기'**다. 창 안의 클릭은 점만 찍고, 찍은 점을 다시 누르면 지운다.
- 새 임시 문과 반영된 opening은 도면 개체를 소유하지 않으며 좌표는 찍은 두 점(LineString)이다. `TemporaryDoor`의 문짝·호 id는 선택 항목으로 바꿨다. 예전 방식의 임시 문은 변환하지 않고 그대로 읽고 저장하며, 반영하면 예전처럼 문·호를 그 opening이 소유한다.
- 자체점검: 기본 입력·C5 SVG 6/6 모드 통과(#37 신규 11항목 포함). 실제 사용자 프로젝트 입력은 Drawing Loading 50/51로, 기존 실패 1건("층 선택·캐시는 저장 데이터 변경 없음", develop에서도 재현)만 남는다. 입력 원본 SHA-256은 검사 전후 동일하다.
- 실제 화면의 점 찍기·저장·반영은 확인하지 않았다(CLI 검사만). 수동 확인 대상으로 남긴다.

## 2026-10-15 — #21 점 단위 편집·면 계산 버퍼링 해소

- [이슈 #21](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/21)을 "모든 레이어 점 단위 편집 + 면 단위 혼용"으로 확장 기록한 뒤 `feat/#21-point-face-editing`에서 작업했다. 1차 사용성 검증(#35)의 "도면 첨부·unit 레이어 생성 시 로딩이 매우 오래 걸림"(#39)의 원인 분석을 포함한다. PR #43은 소스 없이 Xcode·Finder 파일만 병합되어 이 PR로 소스를 올린다.
- 모든 property type 레이어의 기본 작업을 점 단위 편집으로 바꿨다. 꼭짓점·교점을 찍어 DraftShape를 만들고 시작점을 다시 누르면 닫혀 저장된다(⌥ 클릭은 새 점, Delete는 마지막 점, ESC는 취소, Return은 닫기). 자기 교차·넓이 0인 도형은 확정하지 않는다. 꼭짓점 이동/고정 토글과 점 추가·삭제·이동의 Undo/Redo를 지원한다. LineString(opening)은 두 점, Point는 한 점으로 바로 저장한다. 점으로 그린 도형은 원본 SVG 개체를 소유하지 않으며 좌표(`polygonRings`·`drawnVertices`)가 정본이다. `drawnVertices`는 선택적 필드라 이전 파일도 읽힌다.
- 면 단위 선택은 polygon·multipolygon type에서 상단바로 전환해 쓴다. footprint는 제외한다. 선분(개체) 단위로 feature를 만드는 캔버스 경로는 property type 레이어에서 없앴다.
- 원인: `ClosedPolygonFinder.split`이 모든 선분 쌍을 비교했다(C5 도면 선분 74,916개, 약 28억 회). 격자로 비교 상대를 좁혀 4.96초 → 0.033초, 조각 136,352개·면 9,764개로 결과가 같다. `SnapPointExtractor`도 격자로 바꿨다. 예전 개체 상자 필터는 곡선 기준점만 써서 곡선이 부풀어 나간 부분의 교차를 놓쳤다(C5에서 교차 27개 추가). 개체 상자 필터를 되돌리면 결과가 완전히 같음을 확인했다.
- 면·점·점 진행률 분모를 `DerivedGeometry`로 묶어 백그라운드에서 계산한다. 층 캐시는 "SVG 파싱·색인"과 "면·점" 열쇠를 나눠 제외 개체·임시 문만 바뀌면 파싱을 다시 하지 않는다. 레이어 생성·보조 개체 제외는 메인 스레드에서 면을 다시 찾지 않는다. 자체점검에서는 결과 확인을 위해 그 자리에서 계산한다.
- 다각형 진행률 막대를 점 기준으로 바꿨다. 분모는 보조 개체를 포함한 전체 꼭짓점·교점 수, 분자는 태깅된 점과 제외로 사라진 점이다. 면 단위로 저장해도 점 기준이다.
- 측정(Release, CLI): C5 도면 첫 층 준비 약 5.4초 → 0.56초, unit 레이어 생성 메인 스레드 약 5초 정지 → 0.02ms, 보조 개체 제외 후 재계산 백그라운드 약 0.6초. 실제 사용자 프로젝트(개체 16,738개) 첫 층 준비 5.7초 → 1.44초.
- 자체점검: 기본 입력·C5 SVG 모두 6/6 모드 통과(SVG ALL PASS 584항목, Building 27/27, Project 23/23, Document open 24/24, Routing 100/100, Drawing Loading 54/54). 실제 사용자 프로젝트 입력에서는 Drawing Loading 1건("층 선택·캐시는 저장 데이터 변경 없음")이 실패하며 develop에서도 같은 실패가 재현되는 기존 문제다. 입력 원본 SHA-256은 검사 전후 동일하다.
- 실제 화면의 클릭·드래그·키 입력은 확인하지 않았다(CLI 검사만). 수동 확인 대상으로 남긴다.

## 2026-10-15 — #36 .imdfrnt 프로젝트 열기 진입점

- 구현 전에 [이슈 #36](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/36)을 등록하고, PR #33이 병합된 develop에서 `fix/#36-project-open-entry`를 만들었다.
- 빈 캔버스에 `프로젝트 열기 (.imdfrnt)…` 버튼을 추가했다. macOS File 메뉴와 앱 안의 파일 메뉴도 같은 이름으로 맞추고 ⌘⇧O를 유지했다. 파일 선택 창에도 프로젝트 확장자와 복원되는 도면·층·노드·연결을 안내한다.
- 기존 `openProject()`와 비동기 검증·미저장 작업 확인 경로를 재사용했다. 중복 열기 방지와 이전 `.imdfproj` 선택·취소·손상 입력 보호를 유지한다.
- Xcode Release(arm64·x86_64) 빌드·엄격한 서명·diff 검사를 통과했다. 문서 폴더의 실제 v4 백업을 읽기 전용으로 사용해 6/6 CLI 모드 통과: SVG ALL PASS, Building 30/30, Project 23/23, Document open 24/24, Routing 100/100, Drawing Loading 61/61. 실제 백업의 6개 층·노드 72개·연결 87개와 메타데이터, v4→v5 왕복·클라이언트 출력 보존을 검증했다. 원본 SHA-256은 검사 전후 동일하다.
- 최신 앱을 `--project-qa-directory /private/tmp/IMDFrnt36-UI-QA`로 실행했다. UI 자동화는 `Sky Computer Use native pipe startup failed`로 연결되지 않아 실제 버튼·파일 메뉴·파일 선택 창 클릭과 화면 배치는 수동 확인 대상으로 남긴다.
- 빌드 로그: `/private/tmp/imdfrnt-issue36-build.log`. 회귀 결과: `/private/tmp/imdfrnt-issue36-self-tests.log`, `/private/var/folders/y_/53_320qj4pqcgw5hp41cgr2m0000gp/T/imdfrnt-self-tests.Jrm6EV`.

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

## 2026-10-17 — 직접 저장 제거, 프로젝트별 단일 자동 저장 파일

- 사용자 결정: 직접 저장(작업 저장·다른 이름으로 저장)을 없애고 프로젝트마다 자동 저장 파일 하나만 쓴다. 파일은 `~/Library/Application Support/IM-DFrnt/새 도면_YYMMDD_HHmm.imdfrnt`이며 같은 분에 겹치면 `_2`를 붙인다. 빈 프로젝트는 내용이 생기기 전까지 파일을 만들지 않는다.
- `IMDF 불러오기…` 바로 아래에 `.imdfrnt 불러오기…`(⌘⇧O)를 두고, 자동 저장 폴더에서 시작하는 선택 창을 연다. 앱 메뉴·상단 파일 메뉴·왼쪽 사이드바·빈 캔버스·길찾기 화면에 적용했다.
- 전환·종료 전 "저장할까요?" 확인을 없애고 자동 저장 후 진행한다. 저장 실패 시에만 취소/계속을 묻는다. 예전 공용 복구본 `autosave.imdfrnt`는 첫 실행에서 `새 도면_…` 이름으로 옮겨 연다.
- 검사는 실제 자동 저장 폴더 대신 임시 폴더를 쓴다. 기본 sandbox 6개 모드 exit 0: 기존 회귀 ALL PASS, Building 27/27, Project 22/22, Document open 23/23, Routing 100/100, Drawing Loading 54/54. 실제 UI 버튼 입력은 미확인.
- [사용법](docs/projects/PROJECT_LIFECYCLE.md).

## 2026-10-17 — #53 프로젝트 선택 화면과 저장 후 전환

- [이슈 #53](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/53): 앱을 켜면 지난 작업이 자동으로 열려 프로젝트를 고를 수 없고, `.imdfrnt`를 불러오면 지금 프로젝트에 합쳐지는지 바뀌는지 알 수 없다는 피드백.
- 프로젝트 선택 창(`App/ProjectPicker.swift`)을 추가했다. 자동 저장 폴더의 프로젝트를 최근 수정 순으로 보여 주고 층 개수·층 이름·수정 시각과 `현재 열림`/`지난 작업`을 표시한다. 층 이름은 SVG·편집 상태를 건너뛰는 가벼운 디코딩으로 백그라운드에서 읽는다.
- 앱 시작 시 지난 작업을 자동으로 열지 않고 선택 창을 띄운다. 저장된 프로젝트가 없으면 빈 시작 화면, Finder로 파일을 열며 시작하면 선택 창 없이 그 파일을 연다. 진입점은 파일 → 프로젝트 선택…(⌥⌘O)과 상단 프로젝트 이름.
- 다른 프로젝트 열기·새 프로젝트 만들기는 `‘A’ 프로젝트를 저장하고 ‘B’ 프로젝트로 전환할까요?`를 묻는다(선택 창·.imdfrnt 불러오기·Finder 공통, 빈 새 프로젝트는 묻지 않음). 전환 후 배너로 이전 프로젝트가 따로 저장되어 있음을 알리고, 선택 창에서 취소하면 목록으로 돌아간다.
- 자체점검(레포 밖 scratch 빌드): Project 24/24, Document open 23/23(.app 번들), Building 27/27, Routing 100/100, Drawing Loading 54/54, 기존 회귀 ALL PASS. 실제 화면의 선택 창·전환 확인은 미확인.

## 2026-10-17 — #49 개체 편집 (Control 클릭으로 점 교체·끼우기)

- [이슈 #49](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/49) 작업 목록에 엔진 디버깅 5번을 추가했다. 선택한 순서대로만 잇던 방식은 중간 점을 지우고 새 점을 찍으면 새 점이 맨 끝에 붙어 도형이 꼬였다.
- 작성 중인 도형의 점마다 순번(1, 2, 3 …)을 표시한다(모든 레이어). 이미 찍은 점을 Control+클릭하면 그 점과 뒤 순번이 흐려지고, 새 점을 찍은 뒤 흐린 점을 누르면 새 점이 빠진 순번 자리에 들어간다. 같은 점을 두 번 누르면 빼지 않고 그 뒤에 끼운다. 이어지면 흐린 점이 모두 살아난다.
- 이어 붙이지 않고 Control을 떼면 그 자리가 끊긴 채 남는다(`PointDraft.breaks`). polygon·multipolygon은 경고하고 닫기를 막으며, 끊긴 뒤쪽 점을 Control로 두 번 누르면 다시 잇는다. 아무것도 바꾸지 않고 떼면 그대로 둔다. 편집 상태는 `PointDraft` 안에 있어 cmd+z로 함께 되돌아간다.
- 저장된 polygon·multipolygon 도형도 꼭짓점을 Control+클릭하면 그 링을 작성 중 도형으로 꺼내 같은 방식으로 고친다. 이어진 채 Control을 떼면(또는 시작점·Return) 원래 feature의 링을 바꾸고, ESC는 원래 도형을 그대로 둔다. Control을 누른 채로는 꼭짓점 끌기를 시작하지 않는다.
- 자체점검(레포 밖 scratch 빌드): 기존 회귀 ALL PASS(개체 편집 13항목 신규), Project 24/24, Document open 23/23(.app 번들), Building 27/27, Routing 100/100, Drawing Loading 54/54. 실제 화면의 Control+클릭 입력(우클릭으로 바뀌지 않는지 포함)은 미확인.

## 2026-10-18 — #49 MultiPolygon 지정·구멍, 면 단위 기준 변경

- [이슈 #49](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/49) 작업 목록에 추가. IMDF 스펙은 unit·section·geofence·level·footprint·fixture·venue의 geometry를 `POLYGONAL`(Polygon 또는 MultiPolygon)로 정하는데, 앱은 fixture 외에는 링 하나만 만들 수 있었다(위키 src10·src15).
- 우측 패널 feature 카드에서 저장한 다각형을 MultiPolygon으로 지정한다(`FeatureGroup.multiPolygon`, 선택적 필드라 이전 파일 호환). 지정 중에 다각형을 닫거나 면을 저장하면 그 feature에 링으로 더한다. 구멍은 따로 저장하지 않고 링끼리 감싸는 관계로 정한다(`RingNesting`, 홀수 번 감싸이면 구멍): 기존을 감싸면 기존이 구멍, 기존 안쪽이면 새 것이 구멍. 어긋나게 겹치거나 같은 모양이면 거절하고, 꼭짓점 이동·Control 편집으로 겹치게 되는 것도 막는다. 다각형이 하나일 때만 Polygon으로 되돌린다.
- 캔버스는 링을 짝홀 규칙으로 칠해 구멍이 비어 보이고, 다각형을 받는 중인 feature는 점선 테두리다. GeoJSON은 바깥 다각형마다 바로 안쪽 구멍을 안쪽 링으로 붙인 MultiPolygon으로 내보낸다(링 방향은 기존처럼 정렬하지 않음).
- 면 단위는 도면 개체(SVG 선분)가 아니라 **저장된 개체의 경계로 막힌 면**만 고른다(`App/SavedFeatureFaces.swift`). 상단바에서 '현재 레이어 기준 / 모든 레이어 기준'을 고르며, 지금 레이어에 같은 모양으로 저장된 면은 고를 수 없다. 이렇게 만든 feature는 면 기록 없이 링만 두어 점으로 그린 도형처럼 꼭짓점 이동·Control 편집이 된다. footprint는 종전대로 면 단위 대상이 아니다.
- 기존 면 단위 자체점검(제외 모드·드래그·저장·fixture 묶기·진행률)은 도면 개체 면을 전제로 해서 저장된 개체 기준으로 다시 썼다. 자체점검: 기존 회귀 ALL PASS(MultiPolygon 9항목·면 기준 6항목 신규), Project 24/24, Document open 23/23(.app 번들), Building 27/27, Routing 100/100, Drawing Loading 54/54. 실제 화면 확인은 미확인.

- 추가(#49): 점 단위에서 이미 개체로 저장된 꼭짓점도 다시 골라 새 개체를 만든다. 예전에는 도면의 꼭짓점·교점만 찍혀, ⌥로 만든 점이나 저장된 개체 경계로 만든 면의 꼭짓점은 "꼭짓점·교점이 아닌 자리"로 막혔고 옆 unit과 같은 좌표를 공유할 수 없었다(같은 층 unit 사이 틈·겹침 금지). 이제 도면 점과 이 층 모든 개체의 꼭짓점 중 가장 가까운 점에 그 좌표 그대로 붙는다. 자체점검 2항목 추가.

- 추가(#49): unit 레이어 상단바(점·면 단위 모두)와 도구 메뉴에 '빈틈·겹침' 토글을 두었다. 켜면 같은 층 unit 사이의 빈틈은 빨간 점무늬, 겹침은 빨간 빗금으로 도면에 칠하고 개수를 보여 준다(`App/UnitCoverage.swift`, CoreGraphics 교집합·합집합·차집합). 빈틈은 이 층에 level 다각형이 있으면 level에서 unit 전체를 뺀 곳, 없으면 unit에 둘러싸인 빈 곳이다. MultiPolygon unit의 구멍은 짝홀 규칙으로 빠진다. 0.03 폭처럼 무늬가 안 들어가는 얇은 틈도 보이게 빨간 테두리를 함께 긋는다. 자체점검 6항목 추가. 실제 화면 확인은 미확인.

- 추가(#49): 캔버스의 일련번호 태그(unit-014 등)에 마우스를 올리면 그 개체를 주황색(카드를 펼쳤을 때와 같은 강조색)으로 칠하고, 떼면 초록색으로 돌아간다. 태그는 Canvas에 그린 그림이라 그릴 때 태그 사각형을 기억해 두고 `onContinuousHover`로 마우스 위치를 판정한다. 모든 레이어에 적용된다. 실제 화면 확인은 미확인.

## 2026-10-18 — #38 모든 층을 합친 IMDF 아카이브 내보내기

- [이슈 #38](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/38)에 목표·작업 목록·완료 조건을 채웠다. 기존 내보내기는 지금 층·지금 type 하나의 `.geojson`이었는데, IMDF는 type 하나의 파일에 모든 층을 담고 `level_id`로 층을 가린다.
- `Export/IMDFArchive.swift`: 모든 층의 feature를 `{type}.geojson`으로 합쳐 `manifest.json`과 함께 ZIP 최상위에 담는다(`/usr/bin/zip -j`, 불러오기의 `/usr/bin/unzip`과 짝). 규격은 OGC 20-094 Archives·Manifest 절(위키 src18)과 C5 예제를 따랐다. 규격상 확장자는 `.zip`이라 저장 창 기본값도 `.zip`이다.
- 각 층의 level feature id는 그 층의 UUID이고, 같은 층 feature의 빈 `level_id`를 채운다. level의 빈 ordinal·name·short_name은 건물·층 관리 값, 건물·주소가 하나뿐이면 빈 `building_ids`·`address_id`도 채운다. 일련번호는 층마다 따로 매겨지므로 참조는 같은 층을 먼저 찾는다. `address`·`venue`는 필수 파일이라 비어도 넣고 경고한다. 새로 발급한 id는 층별 대장(`editing.ids`)에 되돌려 넣는다.
- 층별 Anchor 미지정·좌표 없음·level 다각형 없음/중복은 층 이름을 붙여 막는다. 가져온 IMDF의 feature·헤더·기타 파일은 그대로 싣는다. 진행률 팝업과 함께 백그라운드에서 만들며 도구 메뉴(⌘⇧E)·상단 파일 메뉴에 있다.
- 자체점검: 기존 회귀 ALL PASS(아카이브 10항목 신규), Project 24/24, Document open 23/23(.app 번들), Building 27/27, Routing 100/100, Drawing Loading 54/54. 레포 밖 임시 진단으로 C5 예제 IMDF를 불러와 그대로 내보내면 12개 파일 모두 feature id·내용이 원본과 같고 manifest의 `created`만 새 시각이다. 실제 화면 확인과 Apple 검증 도구 확인은 미확인.

## 2026-10-18 — fixture 똑같이 생긴 개체에 같은 태깅

- fixture 레이어 점 단위에서 점을 하나라도 찍으면 그 점이 놓인 도면 개체와 똑같이 생긴 개체(`보조 개체 제외`의 쌍둥이 판정 `twinKey`, 위치만 빼고 모양·스타일 비교)를 보라색으로 표시하고, 작성 중인 도형을 그 자리로 옮긴 모양을 점선으로 미리 보여 준다(`App/FixtureTwins.swift`). 상단바에 개수가 뜬다.
- 기준 개체는 찍은 점을 가장 많이 가진 개체(같으면 작은 쪽)다. 옮긴 자리에도 도면 점이 있어야 쌍둥이로 인정해, 옆 벽 점이 섞였거나 보조 개체로 뺀 자리는 빠진다. ⌥로 만든 점은 판정에 쓰지 않는다. 회전·반전된 모양은 찾지 않는다.
- 상단바 `닫을 때 함께 저장`을 켜고 도형을 닫으면 자리마다 개별 Polygon fixture를 함께 저장한다(실행취소 한 칸). 우측 패널 fixture 카드의 `같은 태깅으로 저장`은 카드의 속성을 그대로 가진 fixture를 자리마다 두고, 이미 같은 모양으로 저장된 자리는 속성만 맞춘다. 카드를 펼치면 그 자리가 보라 점선으로 보인다.
- 자체점검 7항목 추가.

## 2026-10-18 — 펼친 unit과 겹치는 unit 빨강, 이름표로 구멍 뚫기

- unit 레이어에서 우측 패널 카드를 펼치면 그 unit(주황)과 넓이 있게 겹치는 다른 unit을 빨간색으로 칠하고 이름표도 빨강으로 바꾼다. 벽만 맞닿은 이웃은 겹침이 아니다. 점·면 단위 모두 보인다(`App/UnitOverlapHoles.swift`).
- 펼친 unit이 MultiPolygon이면 빨간 이름표를 눌러 그 모양대로 구멍을 뚫는다. 통째로 안쪽이면 상대 링을 좌표 그대로 구멍으로 더하고, 걸쳐 있으면 겹친 만큼 깎아 낸다(CoreGraphics 차집합 뒤 꼭짓점·교점을 원래 좌표로 되돌림). MultiPolygon이 아니면 지정하라는 안내만 띄운다. 이름표를 누른 클릭은 점 찍기·면 고르기로 넘어가지 않는다.
- 자체점검 6항목 추가. 기존 회귀 ALL PASS, Building 27/27, Project 24/24, Routing 100/100, Drawing Loading 54/54(레포 밖 scratch 빌드). Document open(.app 번들)과 실제 화면 확인은 미확인.

## 2026-10-18 — unit 빈틈은 level 기준

- 사용자 결정: unit 빈틈은 **level 다각형에서 unit 전체를 뺀 곳**만 센다. level이 없을 때 unit에 둘러싸인 빈 곳을 빈틈으로 보던 대체 규칙을 없앴다(건물 바깥 테두리 쪽 빈 곳을 놓쳤다). level이 없으면 빈틈은 계산하지 않고 상단바에 `level 없어 빈틈 미계산`을 띄운다. 겹침은 종전대로 level과 무관하다. unit이 하나도 없으면 level 전체가 빈틈이다.
- 자체점검: 대체 규칙 항목을 level 기준 2항목으로 바꿨다. 기존 회귀 ALL PASS, Building 27/27, Project 24/24, Routing 100/100, Drawing Loading 54/54. 실제 화면 확인은 미확인.

## 2026-10-18 — unit 보조 선분·자르기·점 끼우기, level 기준 면 선택

- unit 레이어 점 단위 상단바에 도구 `그리기 / 보조 선분 / 자르기 / 점 끼우기`를 두었다(`App/UnitTools.swift`).
  - 보조 선분: 두 점을 찍어 긋는다(꼭짓점·교점에 붙고, 없으면 저장된 개체의 변·다른 보조 선분 위에 붙는다). feature가 아니라 내보내지 않고 면 단위의 모든 기준에서 면을 나누는 경계로만 쓴다. 층마다 `FeatureStore.guides`에 저장되어 실행취소·층 전환·프로젝트 파일을 함께 탄다(선택 키라 이전 파일 호환). Control+클릭으로 하나, 상단바 버튼으로 모두 지운다. 캔버스에 청록 점선으로 보인다.
  - 자르기: 점을 이어 선을 긋고 Return(또는 마지막 점 다시 누르기·상단바 버튼)으로, 선이 가로지른 unit을 조각마다 나눈다. 가장 큰 조각이 원래 unit을 잇고 나머지는 원래 속성을 그대로 가진 새 unit이다. 선이 닿지 않은 MultiPolygon의 다른 섬은 원래 unit에 남는다. 좌표는 CoreGraphics 계산 뒤 원래 꼭짓점·교점으로 되돌린다.
  - 점 끼우기: 저장된 unit의 변 위를 누르면 그 자리(변 위에 도면 점이 있으면 그 점)에 꼭짓점을 넣는다. 같은 변을 쓰는 이웃 unit에도 함께 넣는다.
- 면 단위 기준에 `level 기준`(unit 레이어 전용)을 추가했다. 경계는 level 외곽선·unit 경계·보조 선분·문 선이고, level 안에서 unit이 아직 덮지 않은 곳만 고를 수 있다. 면 추적이 섬을 구멍으로 빼지 못해 기존 '모든 레이어 기준'에서는 level 외곽선 면이 unit 전체를 덮은 채 잡혔다. 이제 안쪽에 떠 있는 unit 자리는 구멍으로 빠지고(그 자리를 눌러도 바깥 면이 잡히지 않음), 구멍 있는 면은 MultiPolygon unit으로 저장된다.
- 포스텍 도서관 2층(읽기 전용 진단): level 기준 면 4개(가장 큰 것은 복도 등 넓이 20,350·구멍 49개), 면 넓이 합 20,529 ≈ 빈틈 넓이 합 20,536, 계산 0.58초(경계가 같으면 캐시). 큰 면은 보조 선분으로 나눠 저장하는 것을 전제로 한다.
- 자체점검 17항목 추가. 기존 회귀 ALL PASS, Building 27/27, Project 24/24, Routing 100/100, Drawing Loading 54/54. 실제 화면 확인은 미확인.

- 추가: 점 단위 상단바가 unit 도구·긴 안내로 캔버스 폭을 넘어 오른쪽이 잘렸다(실제 화면 피드백). 넘치면 가로 스크롤로 바뀌는데 스크롤 막대가 숨겨져 잘린 것처럼만 보였다. 안내 문장을 둘째 줄로 내리고, `CanvasBarFit`이 스크롤할 때 스크롤 막대를 보이게 했다(모든 상단바 공통).

## 2026-10-18 — property type 레이어 투명도는 표시된 다각형 기준

- 사용자 결정: 레이어 투명도는 도면 원본 개체가 아니라 표시된 다각형 기준이다. property type 레이어(unit·fixture 등)의 슬라이더 값은 이제 도면 SVG 개체에 곱하지 않고, 그 type으로 저장된 다각형·선·점(점 단위 화면, 면 단위의 저장된 면, 다른 레이어 도형 표시)에 곱한다(`polygonOpacity(for:)`). 다른 레이어의 도형도 각자 자기 레이어 값을 따르고, 예전 방식(구성원 개체)으로 태깅한 개체 선은 주인 type 값을 따른다. 상위·하위 기본 레이어와 속성 필터 레이어는 종전대로 도면 개체 기준이다. 작성 중인 점·도면 꼭짓점·아직 고르지 않은 면·이름표는 투명도를 타지 않는다.
- 자체점검 2항목 추가. 기존 회귀 ALL PASS, Building 27/27, Project 24/24, Routing 100/100, Drawing Loading 54/54. 실제 화면 확인은 미확인.

- 추가(실제 화면 피드백): unit-114(level 기준으로 저장한 복도, 바깥 링 591점·구멍 49개 MultiPolygon)를 펼쳐도 면이 주황으로 칠해지지 않았다. 면 단위는 저장된 unit을 '같은 모양의 면'으로만 칠하는데, level 기준에서는 덮인 곳이 면에서 빠지고, 다른 기준에서는 구멍 때문에 면이 다른 모양으로 잘려 주인 없는 면(다시 고를 수 있는 면)이 됐다. ① 같은 모양이 아니어도 지금 레이어의 feature가 99% 이상 덮은 면은 그 feature의 면으로 본다(`coveringFeature`). ② 대응하는 면이 없는 저장된 feature는 면 단위에서 링을 직접 칠한다(펼치면 주황). 포스텍 도서관 2층: 현재 레이어 기준 고를 수 있는 면 14 → 4개(나머지는 이미 덮인 자리), unit-114가 면 1개를 가짐. 면 계산(경계가 바뀔 때만) 0.11 → 0.56초. 자체점검 3항목 추가, 6개 모드 통과. 실제 화면 확인은 미확인.

## 2026-10-18 — Shift+클릭으로 저장된 꼭짓점 빼기

- 저장된 도형에서 꼭짓점 하나만 빼는 방법이 없었다(Control 편집은 바꾸기·끼우기만, Delete는 작성 중 도형의 마지막 점만). 점 단위에서 작성 중인 도형이 없을 때 저장된 도형(지금 레이어)의 꼭짓점을 Shift+클릭하면 뺀다. 링이 3점 미만이 되거나, 꼬이거나, 같은 feature의 다른 다각형과 어긋나게 겹치면 빼지 않는다. 선(LineString)은 3점 이상일 때만 뺀다. 같은 점을 쓰는 이웃 도형은 건드리지 않고 알림으로 알린다. 실행취소 한 칸.
- 자체점검 5항목 추가, 6개 모드 통과. 실제 화면 확인은 미확인.

## 2026-10-18 — 고른 다각형의 점 순서(파랑), 빈틈·겹침 구분과 이름표

- 우측 패널에서 펼친 지금 레이어 feature의 꼭짓점을 파란 점으로 찍고(첫 점은 속 빈 큰 원) 순번 이름표를 단다. 링이 여럿이면 `링번호·순번`(예: 2·5)이다. 점·면 단위 모두, 화면에 보이는 점만 600개까지 단다. 저장된 도형을 Control로 고치는 중이면 작성 중 도형의 순번이 대신 보인다.
- 빈틈·겹침 표시: 빈틈은 노란 점무늬, 겹침은 빨간 빗금으로 색까지 나눴다. 조각마다 이름표를 단다 — `빈틈-01 · 넓이`, `겹침-01 unit-012×unit-031 · 넓이`(위→아래, 왼→오른 순 번호). 상단바 개수도 색을 나눴다. `UnitCoverage.Result.overlapPairs`로 겹침마다 두 unit을 기록한다.
- 자체점검 2항목 추가(점 순서 표시는 화면 그리기라 자체점검 대상이 아님), 6개 모드 통과. 실제 화면 확인은 미확인.

## 2026-10-18 — 포스텍 도서관 2층 겹침 정리·벽 structure unit, 실오라기 방지

- 사용자 결정으로 원본 프로젝트(`포스텍 도서관_261017_1651.imdfrnt`)를 레포 밖 일회성 처리로 고쳤다(앱 종료 상태, 처리 전 백업 보관). ① unit 겹침 8곳(모두 넓이 0.5 미만)을 두 unit 중 큰 쪽에서 깎았다(unit-005·011·017·022·057·063·086의 링만 바뀜, 좌표는 원래 꼭짓점·교점으로 되돌림). ② level 빈틈 안에 통째로 든 도면 면 중 평균 폭 3 미만(벽 두께 띠) 294개를 맞닿은 것끼리 묶어 category `structure` unit 176개(넓이 5,501)로 저장했다. 벽 unit이 기존 unit과 만든 넓이 0.002 이하 겹침 15곳은 벽 unit 쪽에서 깎았다. ③ 복도 등 나머지 빈틈 80곳(넓이 14,487)은 사용자 지시로 손대지 않았다. 결과: unit 274 · 겹침 0. 다시 열어 확인.
- 실오라기 원인(겹친 8쌍 실측): T자 접점에서 꼭짓점이 이웃 변에서 0.002~0.05 벗어남(7쌍), 같은 모서리를 0.01~0.02 떨어진 다른 점으로 찍음(2쌍). 방지(`App/SnapAlignment.swift`): 점을 찍을 때와 다각형을 저장할 때(점 그리기·Control 편집·면 단위 저장) 같은 type 이웃(unit은 level 포함)의 꼭짓점에서 0.1 안이면 그 꼭짓점, 아니면 변에서 0.1 안이면 변 위 투영점으로 맞춘다. 그 꼭짓점이 이웃 변 한가운데 놓이면 이웃 변에도 꼭짓점을 넣어 함께 쓰게 한다. 맞춘 결과가 꼬이면 원래 링을 쓴다. 알림에 맞춘 꼭짓점 수와 함께 고친 이웃을 덧붙인다.
- 자체점검 5항목 추가, 6개 모드 통과. 실제 화면 확인은 미확인.

## 2026-10-18 — #54 클라이언트용 지도·길찾기 데이터 묶음 Export

- [이슈 #54](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/54). 요구사항 문서(postech-library 요청 초안) E1~E7·5장을 기준으로 `도구 → 클라이언트용 묶음 내보내기… (지도+길찾기)`를 추가했다(`Export/ClientDataset.swift`). 계약 문서는 [`docs/routing/CLIENT_DATASET.md`](docs/routing/CLIENT_DATASET.md).
- 한 순간의 프로젝트 데이터로 `IMDFArchive.build`와 `RoutingExporter.collection`을 함께 돌려 `<dataset-id>/IMDFData/`(앱이 읽는 8종은 항상)·`routing-graph.geojson`·`dataset.json`을 만든다. 최종 바이트를 다시 읽어 통합 검증(노드 level_id·ordinal ↔ level.geojson, 간선 끝점, 자기 연결·길이 0, 파일 안 ID 중복, ring 닫힘·좌표 범위, 필수 venue·level)하고 SHA-256을 기록한다.
- 서가 매핑은 편집기에 없어 만들지 않고 `shelves_sha256: null`로 표시한다. 앱의 schema 1은 `shelves_sha256`이 필수라 호환되지 않으므로 **schema 2**로 붙였다(합의 필요, 앱 쪽 adapter 필요).
- 적용 안 된 입력(작성 중 도형 등) 안내, 기존 폴더는 교체 확인, 임시 폴더에서 완성 후 한 번에 교체(실패 시 기존 보존), 백그라운드 처리. 새로 발급한 feature id는 프로젝트에 되돌려 넣는다.
- 자체점검 17항목(합성 2개 층·같은 층/층간 연결·해시·재Export 바이트 동일·막는 조건·교체 보존) + 실제 C5 입력 1항목. 6개 모드 통과(Routing 117/117), 실제 C5 입력 포함 Routing 120/120. C5는 알려진 타입 간 UUID 중복(amenity·unit) 1건을 경고한다. 실제 화면 확인·postech-library 앱에서 읽기는 미확인.

## 2026-10-18 — #52 우측 패널 category 필터, category 한국어 표기

- [이슈 #52](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/52)에 작업 목록을 더해 재사용했다(같은 category UI 기능).
- category 필터(`UI/CategoryFilterBar.swift`): 우측 패널 카드 목록 위에서 이 레이어에 저장된 category(개수, null 포함)를 여러 개 고르면 그 feature만 카드 목록에 남고, 캔버스에서도 그 feature의 도형(점 단위 도형·면 단위 면·대응 면 없는 저장 도형·다른 레이어 도형·예전 방식 구성원 개체)과 이름표만 그린다. 머리글 개수는 `보이는 수 / 전체 수`. 모든 레이어에 따로 적용되고, 실행취소 대상이 아니라 `AppEnvironment.categoryFilters`에 두며 새 프로젝트·층 전환 때 비운다. 걸러진 카드가 펼쳐져 있으면 접는다. 빈틈·겹침 표시는 필터와 무관하다.
- category 한국어 표기(`Model/CategoryLabel.swift`): 드롭다운 값 전부(unit·amenity·opening·section·geofence·fixture·footprint·level·building·venue)에 `한국어(영어)`로 보인다. 저장·내보내기 값은 영어 원문 그대로다. 같은 값이 type마다 뜻이 다르면 type별로 둔다(opening `service` = 서비스 출입구). 검색 칸은 한국어로도 찾는다("화장실" → `restroom` 계열). occupant는 자유 입력이라 원문만 보인다. 번역은 화면용 이름이며 스펙 원문 정의가 아니다.
- 사용자 지시로 포스텍 도서관 2층의 Claude가 만든 `structure` unit 176개(unit-117~292)를 원본 프로젝트에서 지웠다(레포 밖 일회성 처리, 앱 종료 상태, 백업 `포스텍 도서관_261017_1651.before-structure-delete-261018.imdfrnt.bak`). 다른 데이터의 참조는 없었다. unit 번호 카운터를 남은 최대 번호(116)로 되돌렸다. 남은 것: unit 113 · opening 26 · fixture 8 · footprint 1 · level 1. 위 "겹침 정리"의 사용자 unit 7개 수정은 되돌리지 않았다.
- 사용자 지시로 같은 프로젝트의 미세한 빈틈을 이웃 unit에 흡수시켰다(레포 밖 일회성 처리, 앱 종료 상태, 백업 `포스텍 도서관_261017_1651.before-sliver-absorb-261018.imdfrnt.bak`). 계기: unit-086 주변의 얇은 틈 중 일부가 벽 자리 빈틈과 이어져 있어 나중에 벽 unit으로 함께 태깅될 수 있었다. 기준: level에서 unit 전체를 뺀 빈틈 중 **폭 0.1 미만**인 부분(앱 스냅 허용치와 같은 값, 가장 얇은 벽 띠 약 0.5보다 충분히 작다). 벽 빈틈에 붙은 얇은 조각은 각진 모서리를 보존하는 열림 연산(mitre)으로 떼어 냈다. 20곳(벽 빈틈에 이어진 것 15, 막힌 것 5, 넓이 합 2.05, 가장 큰 것 0.76)을 맞닿은 길이가 가장 긴 unit에 합쳤다 — unit-022·023·032·048·057·066·085·086·087·090·092·097·106. 링 수·방향은 그대로이고, 꼭짓점은 기존 좌표로 되돌렸다. 결과: 빈틈 넓이 10,941.57 → 10,939.52, 겹침 쌍 0 → 0, unit-086에 닿은 빈틈은 벽 자리 빈틈 하나뿐. 폭 10⁻⁹ 이하의 계산 오차 수준 4곳은 남는다(앱 최소 넓이 기준 미만). 앱에서 다시 열어 화면 확인은 미확인.
- 추가(실제 화면 피드백 "이름표를 눌러도 선택이 안 된다"): 캔버스 이름표 클릭은 펼친 unit과 겹친 빨간 이름표만 처리하고 나머지는 점 찍기·면 고르기로 넘기고 있었다. 이제 빨간 이름표가 아니면 그 feature를 고른다(우측 카드를 그것만 펼침, 다시 누르면 접음, 모든 레이어). 점 단위에서 이름표 바로 밑 꼭짓점의 끌기가 먼저 잡히던 것도, 누른 자리가 이름표면 꼭짓점 끌기를 시작하지 않게 막았다. 고른 카드가 목록 밖이면 우측 패널이 그 카드까지 스크롤한다. 기존 점검 "이름표 클릭이 아닌 unit은 종전 클릭으로 넘긴다"를 새 동작으로 바꾸고 1항목 추가.
- 추가(#38, 실제 화면 피드백 "level id에 층 관리에서 설정한 층이 들어가지 않는다"): 우측 패널 level_id 칸은 이 층에 그린 level feature의 일련번호를 고르는 칸이었고, 층 관리의 층과 연결되지 않았다. IMDF 아카이브는 level feature id를 층 UUID로 바꾸면서 빈 level_id만 채워, 일련번호를 골라 둔 feature는 level_id가 실제 level id와 어긋났다. 이제 level_id는 **지금 층(층 관리)의 UUID(소문자)로 자동**이다 — 패널은 층 이름·ordinal·UUID를 보여 주고 편집을 막는다. `GeoJSONExporter.levelID`가 있으면 슬롯 값과 상관없이 level_id와 level feature id를 그 값으로 쓴다(아카이브·type별 `.geojson` 공통). 층 관리 층이 없으면 종전대로다. 자체점검 1항목 추가.
- 추가(#31, 실제 화면 피드백 "도면 정렬에서 도면이 지도 위에 안 뜬다"): '이 층을 지도 가운데에 올리기'가 지도 범위와 상관없이 눌려, 처음 열린 전국 보기에서 누르면 도면 크기를 화면 폭의 절반으로 잡아 대한민국 중심(위도 35.86·경도 127.79)에 폭 약 7km로 올라갔다(포스텍 도서관 2층 저장값으로 확인, 1단위 = 8.4m). 다시 들어오면 그 중심을 300m로 비춰 빈 곳만 보였고, 이미 올린 층은 다시 올릴 길이 없었다. 화면 가로 폭이 3km(`AppEnvironment.maxPlacingWidthMeters`)를 넘으면 올리기를 막고 확대 안내를 띄운다. 층 카드에 '지도 가운데로 가져오기'를 두어 이미 올린 층을 지금 지도 가운데·화면 폭에 맞춰 되찾는다(회전·순서·표시·투명도 유지, 확정 해제, 실행취소 한 칸, 잠긴 층은 불가). 자체점검 3항목 추가.
- 추가(#31, 실제 화면 피드백 "도면이 정렬되면 아무 버튼도 안 눌린다 — 위성/지도 전환·돌아가기·확대축소·지도 이동 모두, 하단 바만 눌림"): 손 동작 겹(`interactionLayer`)이 도면 테두리 모양 전체를 `contentShape`로 잡았는데, 도면이 화면보다 크면(위 7km 도면) 모양이 지도 밖으로 나가고 SwiftUI는 뷰 밖이라도 모양 안이면 클릭을 받는다. 지도 겹은 화면 순서상 상단 바들 위·하단 바 아래라 창 위쪽 버튼이 전부 막혔다. 받는 자리를 지도 화면과의 교집합으로 잘랐다. 도면 위의 스크롤·핀치는 손 동작 겹이 먹어 지도까지 가지 않았으므로, `MapAlignMapController`가 로컬 이벤트 모니터로 지도가 직접 받지 않는 자리의 스크롤·핀치를 지도에 넘긴다. 도면이 화면을 덮으면 끌 자리가 없어, ⌥ 끌기·Anchor 찍기 모드 끌기·잠긴 층 끌기는 도면 위에서도 지도를 옮긴다(끌지 않고 누른 것은 종전 클릭). 화면 동작이라 자체점검 대상이 아니다 — 6개 모드 회귀 통과(document-open은 위와 같은 3항목), 실제 화면 확인 필요.
- 사용자 지시로 남은 빈틈 2곳(unit-085·unit-086에 붙은 것, 넓이 0.0034·0.0136)을 같은 방식으로 흡수했다(레포 밖 일회성 처리, 앱 종료 상태, 원본이 시험 실행 뒤 바뀌어 최신본으로 다시 계산, 백업 `포스텍 도서관_261017_1651.before-sliver-absorb2-261018.imdfrnt.bak`). 층 빈틈 넓이 0.0170 → 0, unit 겹침 쌍 0 → 0, 다시 재 보면 얇은 빈틈 0곳.
- 추가(사용자 지시 "이름표를 누르면 category·이름을 지정할 수 있게, category가 필요한 모든 레이어"): 이름표를 눌러 feature가 골라지면 그 이름표에 작은 편집 창(`UI/FeatureTagEditor.swift`)이 뜬다. category 목록이 있는 레이어는 category(검색 칸, `한국어(영어)` 표기), 이름을 쓰는 레이어는 name(en·ko)을 담고, 칸은 우측 패널과 같은 `PropertySlotRow`라 저장·되돌리기도 같다. 다시 눌러 접거나 빨간 이름표로 구멍을 뚫으면 창을 닫는다. 자체점검 1항목(레이어별 칸 구성) 추가, selftest 732·building 28·project 25·routing 118·drawing-loading 55 통과. 실제 화면 확인 필요.
- 추가(실제 화면 피드백 "확대/축소가 너무 민감하고, category 검색·unit 선택·화면 이동 등에서 버벅임이 많다"): 포스텍 도서관 2층(도면 개체 64,006개, feature 157개)으로 재 보니(디버그 빌드) 개체 표시 상태 사전을 통째로 다시 만드는 데 324 ms가 걸렸고, 이름표 hover·카드 펼침·category 필터가 바뀔 때마다 이 사전을 버렸다. 또 그리기는 프레임마다 6만 개를 모두 돌았다(그리기 전 준비만 28 ms). 고친 것: (1) hover·펼침·필터는 해당 feature의 구성원·빌린 개체만 다시 판정(`refreshRenderStates(owners:)`, 324 → 0.07 ms), (2) 개체마다 읽던 지금 층·활성 레이어·`@Published` 저장소를 사전 만들 때 한 번만 읽기(`RenderStateContext`, 통째로 다시 만들기 324 → 24 ms), (3) 확대해 일부만 볼 때 격자(`SpatialIndex.drawIndices`)로 화면 안 개체만 돌기(화면이 도면의 25%·5%일 때 28 → 10·2 ms, 절반 넘게 보이거나 범위를 모르면 종전처럼 전체), (4) 면·겹침·빈틈 캐시가 매번 링·선분 전체를 모아 비교하던 것을 `geometryRevision` 번호로 먼저 확인, (5) 검색 칸 목록 거르기를 한 번만. 확대는 휠 한 줄 10%·한 번 최대 40%·핀치 그대로였던 것을 지수 배율(휠 한 줄 4%, 트랙패드 ⌘스크롤 점당 0.3%, 핀치 0.6배)로 바꾸고 한 번에 최대 16%로 묶었다. 자체점검 3항목(부분 갱신 = 통째 갱신, 확대 민감도, 화면 안만 그리기) 추가, selftest 734·building 27·project 24·routing 117·drawing-loading 54 통과. 실제 화면 확인 필요.
- 자체점검 4항목 추가. selftest·building·project·routing·drawing-loading 통과, document-open은 CLI 바이너리 직접 실행이라 Info.plist 3항목이 실패(번들 실행 환경 차이, 이번 변경과 무관). 실제 화면 확인은 미확인.

## 2026-10-19 — #31 지도 정렬 화면을 네이버 지도로

- 사용자 지시로 지도 정렬 화면의 지도를 MapKit에서 **네이버 지도 Web Dynamic Map v3**(WKWebView)로 바꿨다(`UI/MapAlign/AlignMapView.swift`, `UI/MapAlign/NaverMapPage.swift`). 장소 검색과 기존 Anchor 화면(1:1 찍기)은 종전 MapKit 그대로다.
- 일반 지도·위성·위성+이름은 `NORMAL`·`SATELLITE`·`HYBRID`. 도면 선·테두리·손잡이·Anchor·꼭짓점은 지도 안의 `OverlayView`(SVG)로 그려 지도 타일과 함께 움직인다(MapKit 오버레이와 같은 이유로 흔들림 없음). 도면 선은 처음 한 번만 SVG 경로로 넘기고(백그라운드에서 만듦) 정렬이 바뀌면 변환 행렬만, 투명도는 투명도만 바꾼다.
- 손 동작용 화면 ↔ 위경도 변환은 지도가 움직일 때마다 받은 범위(남서·북동)와 화면 크기로 Swift가 웹 메르카토르 식으로 계산한다(`NaverMapViewport`). 도면 위 스크롤은 지도로 넘기고, 트랙패드 핀치는 쌓아 두었다가 한 단계씩 확대한다(네이버 웹 지도는 정수 단계). ⌥ 끌기 등 지도 끌기는 시작 범위 기준으로 중심을 옮긴다.
- 인증: 스크립트는 `maps.js?ncpKeyId=<Client ID>`. Client ID는 상단 바 열쇠 버튼(또는 지도가 안 뜰 때 나오는 안내 칸)에서 넣고 이 Mac의 UserDefaults(`naverMapsClientID`)에만 저장한다 — 레포·프로젝트 파일에 키를 넣지 않는다. 페이지를 `http://localhost/`로 띄우므로 네이버 클라우드 콘솔 Application의 Web 서비스 URL에 `http://localhost`를 등록해야 한다. Client ID 없음·인증 실패(`navermap_authFailure`)·불러오기 실패를 나눠 안내한다.
- MapKit 때의 확대 한계 1m는 네이버 기본 최대 확대 단계로 바뀐다(실제 화면 확인 필요).
- 자체점검 8항목 추가(범위 읽기·화면 변환 왕복·메르카토르 세로·끌기 방향·잘못된 범위·SVG 경로·페이지 구성). 페이지 JS는 node에서 문법 검사와 가짜 `naver.maps`로 겹 추가·이동·투명도·순서·제거를 돌려 오류를 하나 고쳤다(붙이자마자 draw가 불리면 멈춤). selftest 743·building 28·project 25·routing 118·drawing-loading 55 통과, document-open은 위와 같은 3항목. 실제 네이버 키로 화면 확인은 미확인.

## 2026-10-19 — category를 정한 feature의 이름표

- 사용자 지시로 캔버스 이름표 중 category가 있는 feature는 진한 초록(`ClosedPolygonAppearance.categorizedLabelFill`) 바탕으로 칠하고, 이름표 바로 위에 작은 글씨(8pt)로 category를 `한국어(영어)` 표기로 단다(흰 바탕). 강조(주황)·겹침(빨강) 이름표가 우선이고, 누르는 자리는 이름표 그대로다. 모든 레이어 공통. 화면 그리기라 자체점검 대상이 아니다 — 5개 모드 회귀 통과, 실제 화면 확인 필요.
