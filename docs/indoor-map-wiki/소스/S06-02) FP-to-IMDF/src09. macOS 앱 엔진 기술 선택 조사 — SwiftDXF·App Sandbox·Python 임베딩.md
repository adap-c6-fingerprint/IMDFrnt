---
summary: "FtI 자동화 툴의 UI를 macOS 앱으로 만든다는 제약이 확정되면서, 엔진 언어를 Python(ezdxf)에서 Swift로 바꿀 근거(SwiftDXF)와 그 대안들(Python 임베딩), macOS App Sandbox의 외부 바이너리 실행 제약을 조사"
source: "github.com/SecondMouseAU/SwiftDXF, developer.apple.com/forums, zameermanji.com, swift forums, medium.com(Swift2Go), pythonguis.com"
created: "2026-08-14 00:00"
updated: "2026-08-14 00:00"
---
# macOS 앱 엔진 기술 선택 조사 — SwiftDXF·App Sandbox·Python 임베딩

## 수집 기준

- 수집일: 2026-08-14
- 목적: `02) FP-to-IMDF 자동화/01) FtI 자동화 툴 아키텍쳐.md` 작성 중 "최종 UI는 macOS 앱으로 만들 수 있어야 한다"는 제약이 추가되어, 엔진을 Python(ezdxf) 기반으로 유지하며 macOS 앱에 Python을 심을지, 아니면 엔진 자체를 Swift로 옮길지 결정하기 위해 조사.
- 이 조사는 `01)` 문서 2.1·3·5·6절의 근거이며, 지금까지 이 파일이 없어 인용 시 출처가 문서에 명시되지 않았던 것을 사용자 요청으로 보강한다.

## 1. SwiftDXF (핵심 결정 근거)

- 저장소: https://github.com/SecondMouseAU/SwiftDXF
- 라이선스: **MIT**.
- 지원 엔티티(모델 스페이스 한정): LINE, CIRCLE, ARC, ELLIPSE, POINT, TEXT/MTEXT, LWPOLYLINE, POLYLINE/VERTEX, DIMENSION. 각 엔티티는 레이어·색상 정보를 함께 노출한다(예: `.line(a, b, layer, color)`).
- 검증 주장 원문: "Across an 11-file corpus (~62,000 entities, mixed R12 drawings), SwiftDXF matches `ezdxf` exactly — every entity count and every coordinate scalar, to the bit." — 파일별 엔티티 개수와, 정의 좌표로부터 계산한 기하 다이제스트(digest) 두 가지를 비교하는 방식으로 검증했다고 서술.
- 지원 범위 밖으로 명시된 것: "DWG, binary DXF, block/insert expansion, splines, hatches, and writing." 모델링되지 않은 엔티티는 "skipped, not fatal"로 처리된다. BLOCKS 정의 자체(블록 안 도형)는 읽지 않고 모델 스페이스만 처리한다.
- **한계**: 이 정보는 WebFetch로 GitHub README를 요약 조회한 결과이며, README 원문 전체를 직접 대조하지는 않았다. 실제 채택 전 원문 재확인 필요.

## 2. macOS App Sandbox의 외부 바이너리 실행 제약

- App Sandbox는 `com.apple.security.app-sandbox` entitlement로 코드서명해야 활성화되며, 활성화되면 시스템이 `/System/Library/Sandbox/Profiles/application.sb` 프로파일을 적용한다.
- 새로 생성된 프로세스(서브프로세스)는 부모 프로세스의 샌드박스를 상속한다 — 즉 샌드박스 앱이 실행한 서브프로세스도 기본적으로 같은 제약을 받는다.
- 임시 예외(temporary exception) entitlement 키로 일부 제약을 완화할 수 있으나, 예를 들어 사용자가 Open 파일 다이얼로그로 특정 위치를 직접 선택해야 그 위치에 대한 임시 접근 권한이 부여되는 식의 제약이 따른다.
- 앱 번들 자체와, 그 안에 포함된 바이너리·프레임워크(.framework)·동적 라이브러리(.dylib) 각각에 entitlement 파일(상속 관계를 기술하는 child entitlement 포함)이 필요할 수 있다.
- → `01)` 문서가 "ODA File Converter를 서브프로세스로 실행하는 것이 App Sandbox 안에서 가능한지 별도 검증 필요(B-3 스파이크)"라고 남긴 리스크의 근거.
- 출처: Apple Developer Forums 스레드 다수(WebSearch 스니펫 종합), zameermanji.com 블로그 — 개별 원문 페이지 전체를 하나하나 대조하지는 않음(확인 필요).

## 3. Python을 macOS 앱에 임베딩하는 대안들 (기각된 경로, 기록용)

- **PyInstaller**: 활성 Python 인터프리터를 포함해 필요한 파일을 전부 모아 단일 폴더 또는 단일 실행 파일로 묶는 도구. 크로스플랫폼 목적에 적합하다고 서술됨.
- **py2app**: macOS 전용 `.app` 번들 생성 도구, PyInstaller와 비슷한 freezing 방식.
- **Swift에서 직접 임베딩**: `PYTHONHOME`/`PYTHONPATH` 환경변수를 설정하고 `Py_Initialize()`를 호출해 Swift 코드 안에서 Python 인터프리터를 쓰는 방식 — 다만 이 경우 바이너리 크기가 약 100MB 이상 커진다고 서술됨.
- **Caerbannog**: macOS 앱에 Python 인터프리터를 심는 Swift 패키지로, Swift로 작성한 모듈을 Python에서 import하는 것까지 지원한다고 서술됨.
- 공통 주의사항: macOS에 기본 내장된 시스템 Python을 그대로 쓰면 안 된다(버전을 앱이 통제할 수 없음) — 반드시 별도로 배포해야 한다는 지적이 여러 출처에서 공통적으로 나타남.
- → 이 세 방식 모두 기술적으로는 가능하나, SwiftDXF라는 순수 Swift 대안이 존재해 `01)` 문서는 이 경로를 채택하지 않기로 했다. 다만 SwiftDXF의 한계(1절 — block/insert 미확장 등)가 실제로 문제가 될 경우, 이 절의 방식들이 대안으로 재검토될 수 있다.

## 미해결 질문

- SwiftDXF README 원문 전체 미대조(WebFetch 요약에 의존).
- macOS App Sandbox 관련 각 Apple Developer Forums 스레드의 원문 전체 미대조(검색 스니펫 종합).
- PyInstaller/py2app/Caerbannog 임베딩 방식들의 App Store 심사 통과 사례·리스크는 이번 조사에서 깊이 다루지 않음.
