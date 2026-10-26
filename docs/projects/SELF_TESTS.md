# Self-test 재현

## 현재 검증 결과 — #82 / IMD-70 Sandbox 내보내기 (2026-10-26)

- Debug·Release 빌드 및 ad-hoc 서명 검증 성공. 별도 앱 `IM-DFrnt/.build/Opening-boundary-sandbox/IM-DFrnt.app`으로 CLI 8/8 통과: Self ALL PASS, Building 61/61, Project 24/24, Document open 23/23, Routing 164/164, Drawing Loading 56/56, **Footprint 93/93, IMDF Compliance 169/169**.
- 새 회귀 27건은 경계 불일치만 있는 합성 입력에서 일반 ZIP 차단·검사 전용 ZIP 허용, 우회 UUID/결과 안내, Opening/다른 타입 출력 보존, 실제 ZIP 저장·재가져오기, 이후 일반/클라이언트 검증 유지와 정상 경계 허용을 확인한다.
- UUID 중복/형식·참조·필수 속성·좌표/geometry·Unit–Level 빈틈·Venue 포함·display_point·Manifest 언어·미해결 Manifest·Footprint 이전 미완료·JSON 손상이 함께 있을 때 검사용 모드에서도 차단되는지 확인했다.
- 로그: `imdfrnt-self-tests.KFf3yO`(로컬 임시 폴더). 사용자 프로젝트와 기존 앱은 수정하지 않았다. 네이티브 메뉴/저장 패널 직접 조작·실제 Sandbox/AIMP 업로드·사람 리뷰/승인은 별도다. 아래는 이전 검증 기록이다.

## PR #80 메타데이터 후속 리뷰 3건 검증 기록 (2026-10-26)

- Debug·Release 빌드와 ad-hoc 서명 검증 성공. 별도 앱 `IM-DFrnt/.build/AIMP-metadata-review/IM-DFrnt.app`으로 CLI 전체 8/8 통과: Self ALL PASS, Building 61/61, Project 24/24, Document open 23/23, Routing 164/164, Drawing Loading 56/56, **Footprint 93/93, IMDF Compliance 142/142**.
- 새 회귀 29건: 메타데이터 편집 중 개별 내보내기 대상 선택/편집 종료 후 복구, 비문자열·공백·줄바꿈 이름 fallback, 다중 건물에서 관련 Building/Address 선택 및 실제 가져오기, 무관한 충돌 무시·관련 충돌/중복 UUID 원자적 중단, Undo/Redo·저장 왕복, Venue/공통 Footprint 및 Occupant의 종속 주소, Footprint의 현재 참조 우선, 구형 단일 층 정보와 단일 기본값 보존을 확인했다.
- 로그: `imdfrnt-self-tests.tLtBdd`(로컬 임시 폴더). 기존 앱·사용자 프로젝트·무관한 파일 권한 변경은 보존했다. 저장 형식은 v7 그대로이며 기존 검사도 유지한다.
- 내보낼 타입 선택은 저장 패널을 열지 않고 실제 명령이 사용하는 상태 선택 로직으로 검사했다. 네이티브 저장 패널·GUI 수동 조작·AIMP 제출·사람 리뷰/승인은 별도다. 아래 수치는 각 시점의 과거 실행 기록이다.

## PR #80 추가 리뷰 7건 검증 기록 (2026-10-26)

- Debug·Release 빌드 및 ad-hoc 서명 검증 성공. 별도 앱 `IM-DFrnt/.build/AIMP-review-safety/IM-DFrnt.app`으로 전체 CLI 8/8 통과: Self ALL PASS, Building 61/61, Project 24/24, Document open 23/23, Routing 164/164, Drawing Loading 56/56, **Footprint 93/93, IMDF Compliance 113/113**.
- 새 회귀 검사는 운영시간 중간/마지막/중복 삭제·지연 입력·재로딩·시간 값 비교/문자열 보존, 지역 태그 이름 표시, 꼭짓점 이동 차단과 정상 이동 유지, 점 Feature 범위 거부 시 상태 보존 및 선형 투영 유지, 반복 Manifest 충돌/해결 상태/새 충돌/Undo/Redo/저장 왕복, IMDF 준수 검사의 PASS/FAIL 요약을 확인한다.
- 로그: `imdfrnt-self-tests.VZ7JRY`(로컬 임시 폴더). 실패 요약은 `summary(total: 3, failures: 1)`의 `2/3 FAIL` 및 정상 `3/3 PASS`를 직접 검사했다. 사용자 프로젝트와 기존 앱은 수정하지 않았다.
- 실제 GUI 조작·Apple Sandbox/AIMP 제출·사람 코드리뷰/승인은 별도다. 안정 ID와 지연 입력의 모델 경계 검사를 GUI 수동 재현으로 표현하지 않는다. 성능 캐시·주석 커버리지는 계속 제외한다.

## PR #80 리뷰 1~6번 검증 기록

- Debug·Release 빌드 및 ad-hoc 서명 검증 성공. 별도 앱 `IM-DFrnt/.build/AIMP-coderabbit-fixes/IM-DFrnt.app`으로 전체 CLI 8/8 모드 통과: Self ALL PASS, Building 61/61, Project 24/24, Document open 23/23, Routing 164/164, Drawing Loading 56/56, **Footprint 93/93, IMDF Compliance 83/83**.
- IMDF Compliance에는 층 복사 시 내부/export UUID 재발급·참조/소유권/대여 갱신·저장 왕복·Undo/Redo·같은 층 교체 시 identity 유지·원본 GeoJSON 및 종속 Occupant 이전·최종 내보내기 중복 검사, 지역 언어 태그와 추가 언어 보존, 면 선택 모드의 표시점/Anchor 우선 입력 회귀 검사를 포함한다.
- 로그: `imdfrnt-self-tests.eKKzMA`(실행 환경의 임시 폴더). 이후 재실행은 새 로그 폴더를 만든다. 아래 날짜별 수치는 각 시점의 과거 실행 기록이며 최신 결과와 구분한다.
- 실패 요약의 별도 음성 검사: 존재하지 않는 `--submission-test-project` 경로를 지정한 Footprint 검사는 의도대로 종료 코드 1과 `93/94 FAIL`을 출력했다. 정상 8/8 검사와 별도의 오류 입력 검사다.
- 실제 GUI 클릭·Apple Sandbox/AIMP 제출·사람 코드리뷰/승인은 별도 확인 대상이다. 성능 캐시와 문서 주석 커버리지는 사용자 지시로 변경하지 않았다.

## #78 / IMD-67 초기 검증 기록

`--imdf-compliance-selftest`는 완전한 합성 IMDF와 오류 입력을 이용해 필수 정보·참조·공간 관계, 16종 보존, Polygon 구멍, 공통 정보 이전·층 삭제·가져오기·Undo/Redo·Manifest 충돌을 검사한다. `run-self-tests.sh`는 이제 기존 6종과 Footprint·IMDF 준수 검사의 총 8종을 실행한다.

개별 GeoJSON과 ZIP이 동일한 최종 데이터 검증을 사용한다. UI 저장 패널을 호출하던 과거 테스트는 직접 validator/build를 호출하도록 바꿨다. 파일 저장 대화상자, GPS 지도 클릭, 실제 IMDF Sandbox 업로드나 Apple 승인까지 검증한 것으로 해석하지 않는다.

2026-10-25 로컬 Debug 실행: 8/8 모드 통과. Building 61/61, Project 24/24, Document open 23/23, Routing 164/164, Drawing Loading 56/56, Footprint 56/56, IMDF Compliance 50/50, 전체 엔진 ALL PASS. 별도 실제 5층 프로젝트 이전·왕복 검사는 63/63이고 원본 SHA-256은 동일했다. 검증용 .app은 CLI 문서 연결 검사에 필요한 저장소 Info.plist·샘플을 함께 넣은 임시 번들이다. 실제 GUI를 실행한 결과가 아니다.

관련 이슈: [#18](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/18), [#19](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/19). 통합 리뷰: [PR #23](https://github.com/adap-c6-fingerprint/IMDFrnt/pull/23).

## 실행

```sh
cd IM-DFrnt
./build-app.sh /private/tmp/IM-DFrntReviewFollowup.app
./run-self-tests.sh /private/tmp/IM-DFrntReviewFollowup.app
```

스크립트는 도면 로딩·Footprint·IMDF 준수 검사를 포함한 8개 모드를 별도 프로세스로 실행한다. 각 종료 코드, 전체 stdout/stderr, macOS 버전·아키텍처·검사한 실행 파일의 SHA-256을 출력된 로그 폴더에 기록한다. 검사 진입 표시와 PASS 요약이 없거나 실패가 있으면 스크립트도 실패한다. 파일은 보존되므로 리뷰어가 원문 로그를 확인할 수 있다.

개별 실행도 가능하다. `open --args` 대신 번들 안의 실행 파일을 직접 호출해야 종료 코드와 stdout/stderr를 확인할 수 있다. 문서 타입 검사는 빌드된 앱의 Info.plist를 읽으므로 `.app` 실행 파일을 사용한다.

```sh
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --selftest
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --building-selftest
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --project-selftest
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --document-open-selftest
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --routing-selftest
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --drawing-loading-selftest
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --footprint-selftest
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --imdf-compliance-selftest
```

실제 입력에 대한 추가 검사는 선택 사항이다. 지정한 원본은 읽기 전용이며 이전한 내용은 검사 전용 임시 경로에 쓴다.

```sh
./run-self-tests.sh /private/tmp/IM-DFrntReviewFollowup.app \
  --imdf-test-input /path/to/IMDFData \
  --imdf-test-zip /path/to/IMDF.zip \
  --legacy-test-input /path/to/old.imdfrnt
```

## 검사 진입과 범위

도면 로딩 검사는 메타데이터 우선 표시, 비동기 응답, 마지막 선택, 캐시 및 층별 데이터 보존과 참고 레이어 저장을 검사한다. `--drawing-test-svg /path/to/drawing.svg` 또는 `--drawing-test-project /path/to/project.imdfrnt`로 실제 입력을 지정할 수 있다. 원본은 읽기 전용으로 사용한다. 선택 로직 측정과 실제 화면 검증의 범위는 [층별 도면](LEVEL_DRAWINGS.md)에 기록한다.

기존 병합 커밋 `61022bf6`에서는 `applicationDidFinishLaunching`에서 검사를 시작했다. AppKit/LaunchServices 초기화가 exit 134로 실패하면 검사 코드에 도달하지 못한다는 리뷰 피드백을 받았다. 현재 `IMDFrntMain`은 CLI 인자를 먼저 확인해 SwiftUI 앱과 NSApplication을 만들기 전에 검사를 실행한다. 첫 로그는 `== CLI self-test: before AppKit application startup ==`다. 일반 앱 실행은 기존 SwiftUI [`App.main()`](https://developer.apple.com/documentation/swiftui/app/main())으로 연결한다.

`--document-open-selftest`는 번들 문서 타입과 파일 입출력, 요청 대기·취소·실패·복구, AppDelegate의 공통 파일 요청 처리 함수를 검사한다. NSApplication을 생성하지 않는지도 확인한다. 실제 Finder 이벤트 전달, 메뉴·모달·시트의 버튼 입력과 화면 렌더링을 검사한 것으로 해석하지 않는다. 이 범위는 별도 UI 확인이 필요하다.

모든 검사 모드에서는 사용자 복구본을 읽거나 자동 저장하지 않는다. 프로젝트·건물·문서 열기 검사는 검사 전용 임시 폴더와 UserDefaults를 사용한다.

## 2026-10-13 검증

이후 PR #27 리뷰 회귀 결과는 아래 **2026-10-15 검증**을 참고한다.

macOS 27.0.1 (26A434), arm64, Apple Swift 6.4에서 Release 빌드 및 ad-hoc 서명 검사에 성공했다. UUID nil 비교와 deprecated `onChange` 경고 5곳을 수정한 빌드 로그에는 경고가 없다. CLI 검사는 실행 권한을 확장하지 않은 기본 sandbox 실행에서도 모두 종료 코드 0으로 통과했다.

| 모드 | 기본 입력 | 실제 C5 폴더·ZIP 및 기존 v4 입력 포함 |
| --- | --- | --- |
| `--selftest` | ALL PASS | ALL PASS |
| `--building-selftest` | 27/27 PASS | 37/37 PASS |
| `--project-selftest` | 23/23 PASS | 23/23 PASS |
| `--document-open-selftest` | 24/24 PASS | 24/24 PASS |
| `--routing-selftest` | 100/100 PASS | 104/104 PASS |

사용자 기존 복구 파일 SHA-256은 검사 전과 같다. 이번 실제 입력 검사 로그 폴더는 `/var/folders/y_/53_320qj4pqcgw5hp41cgr2m0000gp/T/imdfrnt-self-tests.6FySw3`다. 이 경로는 해당 로컬 환경의 일시적인 증거이며, 재실행하면 새 폴더가 생성된다.

이전 PR에 기재된 통과 결과는 당시 로컬 실행 기록이다. 리뷰어의 환경에서 독립 재현되지 않았다는 피드백과 구분한다. 새 실행 경로의 통과 결과 또한 위 환경에서 확인한 결과이며 별도 리뷰 환경의 재실행을 대신하지 않는다.

일반 실행도 사용자 작업과 분리한 QA 프로세스에서 시도했다. 프로세스 샘플은 SwiftUI `App.main()` → `NSApplicationMain` → AppKit 이벤트 루프 진입을 확인했다. UI 도구는 `Sky Computer Use native pipe startup failed`로 실패했고 접근성 대체 조회에서도 기존·신규 IM-DFrnt 프로세스의 창을 조회하지 못했다. 초기 화면과 건물·층 관리 시트의 실제 렌더링·입력은 검증한 것으로 표시하지 않는다.

## 2026-10-15 검증

PR #27의 두 P2에 대해 `DrawingLoadingReviewSelfTest`를 도면 검사에 연결했다. 수정 전 코드의 동일 기본 입력은 40/49 PASS였고 수정 후 49/49 PASS다. Feature·노드 없이 기준점만 수정한 SVG/PNG/JPG 열기의 확인·취소·복구본/Undo 보존, 저장 취소·저장 승인·폐기 승인·손상 입력, 캐시 없는 Undo 후 열린 링 경고 2곳과 캐시된 Undo/Redo를 검사한다.

Swift 6 Release 빌드·서명과 6/6 모드를 통과했다. 실제 C5 폴더와 현재 테스트 프로젝트를 지정한 결과는 Building 34/34, Project 23/23, Document open 24/24, Routing 102/102, Drawing Loading 46/46 및 SVG ALL PASS다. 층마다 수행하는 항목이 있어 도면 검사 수는 입력 층 수에 따라 달라진다. 로그는 `/private/var/folders/y_/53_320qj4pqcgw5hp41cgr2m0000gp/T/imdfrnt-self-tests.LUiJi2`에 있다.

확인 응답을 주입한 실제 비동기 파일 열기와 편집 명령의 검증이다. 네이티브 Finder 이벤트·alert 버튼 입력을 실제로 확인한 결과로 해석하지 않는다.
