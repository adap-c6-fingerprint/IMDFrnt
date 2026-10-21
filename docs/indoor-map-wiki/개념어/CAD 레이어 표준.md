---
summary: CAD 도면의 레이어 이름을 규약에 따라 통일하는 표준. 도면 선분에 의미(벽·문·창·방)를 부여하는 유일한 기계 판독 단서이며, 도면→IMDF 자동 변환의 전제 조건
source: "[[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]], doc.esri.com(Prepare CAD for ArcGIS Indoors)"
related:
  - "[[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]]"
  - "[[ArcGIS Indoors]]"
  - "[[폴리곤화]]"
  - "[[IMDF]]"
created: 2026-08-20 00:00
updated: 2026-08-20 00:00
core_keywords:
  - CAD 레이어 표준
---
# CAD 레이어 표준

## 요약

CAD 도면의 모든 엔티티는 레이어에 속하고, 좌표값 자체에는 "이 선이 벽인지 문인지"라는 정보가 없다. 따라서 **레이어 이름이 의미 정보의 유일한 기계 판독 단서**다. CAD 레이어 표준은 이 이름을 분야·요소 코드 규약으로 통일해, 도면을 자동 변환·관리할 수 있게 만드는 명명 체계를 말한다.

## 핵심 내용

- Esri ArcGIS Pro 공식 문서는 "Consistent layer naming across CAD drawings allows for a well-organized and extendable data conversion and management process"라며 **U.S. National CAD Standard**의 AEC(Architecture·Engineering·Construction) Naming convention 준수를 권장한다.
- 이 규약은 `A-WALL`, `A-DOOR`처럼 분야 코드(A = Architectural)와 요소 코드를 조합하는 방식이다.
- 실제 변환에서는 레이어 이름을 대상 피처 타입에 연결하는 **매핑 테이블**을 선언한다. [[ArcGIS Indoors]]의 Excel 구성 파일이 그 예로, `UNITS`(방을 이루는 닫힌 폴리라인 레이어), `UNIT_LINES`(닫히지 않은 선분으로 방을 구성하는 경우), `OPENINGS`(폴리곤 생성 시 닫아야 할 문 레이어), `DETAILS`(벽·문·창 등 내부 디테일) 컬럼으로 구성된다.
- **자동화의 실체:** 도면→IMDF 변환의 "자동화"는 도구가 도형을 보고 방을 알아맞히는 것이 아니라, **레이어 → 피처 타입 매핑을 사람이 한 번 선언하고 그 뒤로 재사용하는 것**이다.
- **자동화가 막히는 지점:** 도면마다 레이어 이름이 제각각이면 이 매핑 테이블을 매번 새로 만들어야 한다. CAD→IMDF 변환이 완전 자동화되지 못하는 근본 이유가 여기 있다. Safe Software 직원의 표현도 같은 맥락이다 — "CAD is likely the hardest data to properly convert to IMDF, since it allows a great deal of latitude in the presentation and topology of the features."

## 관련 링크

- [[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]] — 레이어 분류가 자동 그룹화 3축 중 첫 축으로 쓰이는 맥락
- [[ArcGIS Indoors]] — Excel 매핑 구성 파일로 레이어를 피처 클래스에 연결
- [[폴리곤화]] — 레이어로 골라낸 선분을 닫힌 면으로 묶는 다음 단계
- [[IMDF]] — 매핑의 최종 목적지가 되는 규격

## 미해결 질문

- U.S. National CAD Standard의 전체 레이어 코드 목록 원문 — 유료 표준이라 이번 조사에서 미확보.
- 한국 건축 도면에서 통용되는 레이어 명명 관행이 있는가, 있다면 NCS와 어떻게 대응시키는가.
