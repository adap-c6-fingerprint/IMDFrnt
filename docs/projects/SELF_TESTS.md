# Self-test 재현

관련 이슈: [#18](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/18), [#19](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/19). 통합 리뷰: [PR #23](https://github.com/adap-c6-fingerprint/IMDFrnt/pull/23).

## 실행

```sh
cd IM-DFrnt
./build-app.sh /private/tmp/IM-DFrntReviewFollowup.app
./run-self-tests.sh /private/tmp/IM-DFrntReviewFollowup.app
```

스크립트는 도면 로딩 검사를 포함한 6개 모드를 별도 프로세스로 실행한다. 각 종료 코드, 전체 stdout/stderr, macOS 버전·아키텍처·검사한 실행 파일의 SHA-256을 출력된 로그 폴더에 기록한다. 검사 진입 표시와 PASS 요약이 없거나 실패가 있으면 스크립트도 실패한다. 파일은 보존되므로 리뷰어가 원문 로그를 확인할 수 있다.

개별 실행도 가능하다. `open --args` 대신 번들 안의 실행 파일을 직접 호출해야 종료 코드와 stdout/stderr를 확인할 수 있다. 문서 타입 검사는 빌드된 앱의 Info.plist를 읽으므로 `.app` 실행 파일을 사용한다.

```sh
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --selftest
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --building-selftest
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --project-selftest
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --document-open-selftest
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --routing-selftest
/private/tmp/IM-DFrntReviewFollowup.app/Contents/MacOS/IM-DFrnt --drawing-loading-selftest
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
