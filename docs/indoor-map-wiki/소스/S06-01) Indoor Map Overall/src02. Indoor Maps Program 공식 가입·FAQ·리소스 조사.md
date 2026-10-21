---
summary: "register.apple.com/resources/indoor/program의 가입 절차, FAQ, 추가 리소스 페이지를 웹으로 조사 — WWDC19 세션의 등록·팀 관리·측위 설명을 현재 공식 페이지 기준으로 보강"
source: "register.apple.com/resources/indoor/program/joining_program, /faq, /additional_resources, /indoor_maps"
created: "2026-08-05 17:10"
updated: "2026-08-05 17:10"
---
# Indoor Maps Program 공식 가입·FAQ·리소스 조사

## 수집 기준

- 수집일: 2026-08-05
- 목적: WWDC19 세션에서 소개된 "조직 등록 → 팀 관리 → 장소 claim" 흐름과 "large 기준"을 현재 공식 프로그램 페이지로 다시 확인.
- 관점: 가공 지식 문서의 미해결 질문 — "50 square meters 수치가 오기인지", "5가지 role의 구체 범위"에 대한 근거 확보 시도.

## 핵심 출처

- Apple Indoor Maps 메인  
  https://register.apple.com/indoor
- Indoor Maps Program 메인  
  https://register.apple.com/resources/indoor/program
- 가입 절차(Joining the Indoor Program)  
  https://register.apple.com/resources/indoor/program/joining_program
- FAQ  
  https://register.apple.com/resources/indoor/program/faq
- 추가 리소스  
  https://register.apple.com/resources/indoor/program/additional_resources
- Apple Maps 내 실내 지도(Indoor Maps in Apple Maps)  
  https://register.apple.com/resources/indoor/program/indoor_maps
- Apple Indoor Maps Program 소개 PDF  
  https://register.apple.com/resources/indoor/Apple-Indoor-Maps-Program.pdf
- Apple Indoor Maps 가이드라인 PDF  
  https://register.apple.com/resources/indoor/Apple-Indoor-Maps-Guidelines.pdf

## 자격(eligibility) — "large" 기준 재확인

- 현재 공식 페이지들은 WWDC19 세션에서 언급된 "50㎡", "연 500만 명 방문" 같은 **구체적 수치를 제시하지 않는다.** 대신 "공항, 쇼핑센터, 아레나, 병원, 대학, 사설 오피스 빌딩처럼 큰 공공·사설 공간을 가진 조직"이라는 정성적 기준과, "거의 모든 대형 venue의 소유자 또는 운영자에게 적합하다(appropriate for the owners or operators of almost any large venue, public or private)"는 문구로 설명한다.
- → WWDC19 세션 전사문의 "50 square meters"라는 수치는 현재 공식 페이지 어디에서도 재확인되지 않는다. 세션 당시 구두 발표에서만 언급된 수치이거나, 오기(가공 지식 문서에서 제기한 "50,000㎡" 가능성 포함)일 수 있다는 정황이 이 조사로 보강된다. 다만 명확한 반증도 아니므로 **여전히 확인 필요** 상태로 남는다.
- 기술 요구사항 측면에서는 "정확한 실내 측위를 위해서는 상대적으로 안정적인 Wi-Fi 네트워크가 필요하다"는 조건이 명시된다.
- 사설(private) 장소는 Apple Maps에 실내 지도가 노출될 수 없지만, 자체 앱·웹사이트용 지도는 계속 만들 수 있다는 점은 WWDC19 세션 설명과 일치한다.

## 가입 절차

- 조직 대표자가 **Apple Business Register(ABR)**에서 신청한다.
- Apple이 신청서를 받은 뒤 통상 "며칠 내(within a few days)" 응답한다.
- 승인된 조직은 ABR을 통해 관리자가 팀원을 추가 초대할 수 있고, 이를 통해 "조직이 프로그램 멤버십에 대한 완전한 통제(complete control over the program membership)"를 유지한다. → WWDC19 세션의 "관리자가 팀원을 관리하고 역할을 부여한다"는 설명과 같은 맥락이나, 이 페이지는 **역할(role) 5종의 구체적 명칭·권한을 나열하지 않는다.** 5가지 role의 세부 정의는 이번 조사로도 확인되지 않아 여전히 미해결로 남는다.
- 승인 후 조직은 ABR을 통해 건물 평면도·세부 정보 업로드, 테넌트(occupant) 정보 제공, 실내 지도 업데이트 업로드를 진행한다.

## FAQ 핵심 항목

| 질문 주제 | 요지 |
| --- | --- |
| Apple Maps에 실내 지도 추가 | 소유자·운영자의 명시적 허가가 있어야 공개 접근 가능한 건물의 실내 지도를 Apple Maps에 추가한다 |
| IMDF·지도의 제3자 공유 | Apple Maps에 표시되는 실내 지도 자체는 MapKit·MapKit JS로 재공개되지 않는다. 조직이 오버레이 API로 직접 지도를 표시하는 것은 별개다 |
| Wi-Fi AP 변경 시 재조사 필요성 | 경미한 변경은 재조사가 필요 없지만, Wi-Fi 네트워크 전체 교체 시에는 재조사가 필요하다 |
| 층(floor level) 정보 접근 경로 | Core Location API와 Safari 브라우저를 통해 제공된다 |
| 실내 측위에 데이터(네트워크) 연결 필요 여부 | 최초 핑거프린트 다운로드 시에는 필요하지만, 다운로드 후에는 불필요하다 — WWDC19 세션의 "네트워크 연결 없이 동작" 설명과 일치 |
| Wi-Fi 네트워크 별도 개선 필요 여부 | 건물 전체에 충분한 2.4GHz Wi-Fi 커버리지가 있으면 별도 개선이 필요 없다 |
| BLE 비콘 필요 여부 | Apple 실내 측위는 비콘을 사용하지 않는다 — Wi-Fi 핑거프린팅만으로 동작한다는 WWDC19 세션 설명과 일치 |
| 실내 경로 안내(routing) API 제공 여부 | Apple이 자체 제공하지 않으며, 제3자 개발사의 API로 구현해야 한다 |
| iOS 외 플랫폼 지원 여부 | 지원하지 않는다 |
| 제3자 IMDF 지원 도구 | 20개 이상의 파트너 솔루션이 나열되어 있다 |
| 프로그램 참여 가능 국가 | 전 세계 200개국 이상이 등록 대상이다 |

## 추가 리소스 페이지 목록

| 분류 | 이름 | 설명 | URL |
| --- | --- | --- | --- |
| 공식 문서 | IMDF 스펙 | IMDF 공식 사양 문서 | https://register.apple.com/resources/imdf/ |
| 공식 문서 | 실내 점유자(Occupant) CSV 스펙 | 공간 식별자에 점유자 정보를 연결하는 CSV 형식 지침·샘플 | https://indoor-occupants-spec.geo.apple.com/indoor/resources/occupant-specs/ |
| 개발 도구 | IMDF Sandbox | IMDF를 보고 검증하고 소규모 편집하는 온라인 도구 | https://register.apple.com/indoor/imdf-sandbox |
| 개발 도구 | MapKit | iOS 앱에서 IMDF를 실내 지도로 렌더링하는 프레임워크 | https://developer.apple.com/documentation/mapkit |
| 개발 도구 | MapKit JS | 웹사이트에서 실내 지도를 표시하는 JavaScript API | https://developer.apple.com/maps/mapkitjs/ |
| 개발 도구 | Indoor Survey 앱 | iOS에서 실내 측위를 활성화·테스트하는 앱(WWDC19 세션에서 시연된 서베이 앱) | 페이지 내 별도 URL 미기재 |
| 개발 도구 | Indoor Survey 도움말 | 실내 서베이 기법·절차 상세 안내 | https://help.apple.com/indoorsurvey |
| 학습 자료 | WWDC 2019 Session 241 | "실내 지도를 앱·웹사이트에 추가하기" — WWDC19 Session 245(본 위키의 1차 소스)가 안내하는 후속 심화 세션 | http://developer.apple.com/wwdc/245 (원문 표기 그대로; 세션 번호 표기가 혼재되어 있어 `src03`에서 재확인) |
| 외부 파트너 | Safe Software | IMDF 변환·데이터 파이프라인 통합 플랫폼(CAD/BIM/GIS → IMDF) | partners@safe.com |

## 미해결 질문

- 5가지 role의 구체적 명칭과 권한 범위 — 이번 조사로도 확인되지 않음. ABR 로그인 후 실제 팀 관리 화면에서만 확인 가능할 가능성.
- "50㎡" 등 WWDC19 세션의 구체적 수치가 현재도 유효한 내부 기준인지, 발표 당시의 예시일 뿐인지는 Apple에 직접 문의해야 확정 가능.
