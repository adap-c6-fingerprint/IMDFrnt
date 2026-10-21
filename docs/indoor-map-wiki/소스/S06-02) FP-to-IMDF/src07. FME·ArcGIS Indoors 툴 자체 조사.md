---
summary: "Safe Software FME(회사·제품·IMDF Reader/Writer)와 Esri ArcGIS Indoors(제품·라이선스·IMDF 익스포트 경로)를 공식 문서로 별도 조사. ArcGIS Indoors→IMDF 최종 변환이 실제로 FME를 재사용한다는 점을 확인"
source: "safe.com, fme.safe.com, docs.safe.com, esri.com, pro.arcgis.com, doc.esri.com"
created: "2026-08-13 00:30"
updated: "2026-08-13 00:30"
---
# FME·ArcGIS Indoors 툴 자체 조사

## 수집 기준

- 수집일: 2026-08-13
- 목적: `02) 도면에서 GeoJSON(IMDF) 추출 전 과정.md`과 `B. 개념어/FME.md`·`ArcGIS Indoors.md`는 IMDF 변환이라는 좁은 목적에서만 두 도구를 다뤘다. 사용자가 "FME/ArcGIS에 대한 문서도 자료조사 후 작성"을 요청해, 두 도구 자체(회사·제품 정체성·라이선스)와 이전에 "확인 필요"로 남겼던 ArcGIS Indoors→IMDF 최종 export 절차를 추가로 조사.

## 핵심 출처

- FME(software) 위키백과 및 검색 결과 종합, fme.safe.com, safe.com
- FME IMDF Reader/Writer 문서: https://docs.safe.com/fme/html/FME-Form-Documentation/FME-ReadersWriters/imdf/imdf.htm
- FME IMDF Format Attributes(주의: 아래 12번 항목 참고): https://docs.safe.com/fme/html/FME-Form-Documentation/FME-ReadersWriters/imdf/Feature_Representation.htm
- Esri, ArcGIS Indoors 제품 개요: https://www.esri.com/en-us/arcgis/products/arcgis-indoors/overview
- ArcGIS Pro 문서, "Prepare Indoors data for IMDF export": https://pro.arcgis.com/en/pro-app/3.0/help/data/indoors/prepare-indoors-data-for-imdf-export.htm
- ArcGIS Pro 도구 문서, "Generate Unit Openings": https://doc.esri.com/en/arcgis-pro/latest/tool-reference/indoors/generate-unit-openings.html
- FME Support, "Converting ArcGIS Indoors Data to IMDF": https://support.safe.com/hc/en-us/articles/25407628986381 (제목만 확인, 본문은 403으로 미확보)

## 1. Safe Software / FME 회사·제품 개요

- Safe Software는 1993년 캐나다 브리티시컬럼비아주 서리(Surrey)에서 Don Murray와 Dale Lutz가 공동 창업했다. 인증된 B Corp(공익법인).
- FME(Feature Manipulation Engine)는 Safe Software가 만든 공간 데이터 ETL(Extract, Transform, Load) 플랫폼이다. "300개 이상의 공간·비공간 데이터 포맷"(다른 페이지에서는 "400개 이상"으로도 서술됨 — 문서마다 수치가 다름, 확인 필요)을 서로 변환·통합한다.
- **FME Form**은 코드 없이(no-code) 데이터 변환 워크플로우를 만드는 저작 환경이다. (과거 명칭은 "FME Desktop"이었으나 이번 조사에서 이름 변경 시점은 확인하지 않음.)
- Gartner Magic Quadrant for Data Integration Tools에서 "Niche Player"로 6년 연속 선정되었다고 서술됨(2025년 기준).

## 2. FME의 IMDF 지원 — 왜 CAD 변환에 FME가 쓰이는가

- 공식 서술: "FME is an ideal tool for creating IMDF datasets, not just because it supports the translation of data to IMDF format, but also because it supports reading several hundred types and formats of data in which source maps might be stored."
- "An organization can use FME to bring indoor mapping data from CAD into Esri ArcGIS Indoors for editing and maintenance, and then set up FME to automatically convert the data from ArcGIS into IMDF." — **이 문장이 핵심.** CAD → (FME) → ArcGIS Indoors(편집·유지관리) → (FME) → IMDF 순서로, FME가 파이프라인의 양 끝(CAD 흡수, IMDF 출력)을 모두 맡고 중간에 ArcGIS Indoors가 편집·관리 단계로 들어가는 조합이 실무에서 쓰인다는 것이 확인된다.
- IMDF 데이터셋의 구조를 다시 한번 확인: "An IMDF dataset is a folder of GeoJSON files with one file per IMDF feature type."

## 3. ArcGIS Indoors → IMDF 최종 export 절차 (이전 src06의 "확인 필요" 해소)

src06 작성 시점에는 "Indoors Geodatabase에서 최종 IMDF로 export하는 절차가 Esri 자체 기능인지 FME를 재사용하는지 확인하지 못했다"고 남겼다. 이번 조사로 **FME를 재사용하는 것으로 확인됐다.**

- ArcGIS Pro 공식 문서(Prepare Indoors data for IMDF export) 원문: "If you need to export your Indoors geodatabase or indoor dataset to IMDF, use the **Generate Unit Openings** geoprocessing tool" — Indoors 데이터를 IMDF로 내보내기 전 준비 도구다.
- WebSearch 스니펫 기준(원문 페이지는 403으로 직접 대조 못 함, 확인 필요 표시): "Converting the indoors model to IMDF requires using the **Data Interoperability Extension** to run the **ArcGIS Indoors Model to IMDF workbench**, available for download on **FME Hub**. The download contains two workbenches, a template, and a read-me file that describes the workflow to prepare the Indoors data, update the templates, and use the IMDF Sandbox to validate the exported IMDF file."
- 즉 절차는: ArcGIS Indoors Geodatabase 준비(Generate Unit Openings 등) → **ArcGIS Pro의 Data Interoperability Extension**(FME 엔진을 내장한 Esri 확장 기능)으로 FME Hub에서 배포되는 **"ArcGIS Indoors Model to IMDF" 워크벤치**를 실행 → IMDF(.geojson zip) 산출 → IMDF Sandbox로 검증.
- **Generate Unit Openings** 도구 자체의 목적(공식 원문): "Creates unit openings as line features that model the location and physical extent of an entrance." 그리고 "Line features that represent openings are **required** to export indoor data to the Indoor Mapping Data Format (IMDF) for use in Apple indoor positioning." — ArcGIS Indoors의 문(door)은 기본적으로 다른 방식(도면 심볼 등)으로 표현되는데, IMDF의 Opening(LineString) 요구사항에 맞추려면 이 도구로 선 형태의 Opening 피처를 별도 생성해야 한다는 뜻이다. "Modeling openings as lines simplifies maps by avoiding complex door symbology"라는 이유도 함께 서술된다.

## 4. Esri / ArcGIS Indoors 제품 개요

- ArcGIS Indoors 공식 설명: "실내 공간 및 건물 관리를 위한 포괄적인 실내 매핑 소프트웨어." CAD·BIM·라이다 및 기타 시설 데이터를 하나의 지도로 통합한다.
- 주요 용도(공식 서술 기반): 자산 관리, 안전·보안, 공간 예약 관리(업무 공간 할당·예약·재배치 계획), 실내 내비게이션.
- 라이선스 3종:
  - **Indoors Pro** — ArcGIS Pro 확장, GIS 전문가용 실내 지도 제작 도구.
  - **Indoors Maps** — ArcGIS Enterprise/Online용 조직 확장, 무제한 사용자 접근.
  - **Indoors Spaces** — Indoors Maps에 추가하는 공간 계획·관리(할당·예약) 기능.
- → ArcGIS Indoors는 IMDF 변환 전용 도구가 아니라, **시설관리(자산·공간·안전) 전반을 다루는 훨씬 큰 실내 GIS 제품군**이며, IMDF 익스포트는 그중 "Apple 실내 측위 연동"을 위한 한 기능일 뿐이라는 게 이번 조사로 명확해졌다.

## 참고: 신뢰하지 않은 조사 결과

`Feature_Representation.htm`(FME IMDF Format Attributes) 페이지를 조회했을 때 반환된 요약은 `json_polygon`에 `occupant`를, `json_point`에도 `occupant`를 동시에 포함시켰고, `unit`·`kiosk`는 네 분류 어디에도 포함하지 않는 등 이미 src04에서 원문으로 확정한 사실(Occupant는 geometry `null`, Unit·Kiosk는 Polygon)과 명백히 모순된다. 이는 WebFetch 요약 과정의 오류로 판단해 **이 표는 채택하지 않았다.** 이 페이지가 필요하면 원문을 직접 열어 재확인해야 한다.

## 미해결 질문

- FME가 지원하는 정확한 포맷 개수(300개 vs 400개, 출처 페이지마다 다름).
- ArcGIS Indoors "Model to IMDF" FME 워크벤치의 세부 내용(원문 페이지 403으로 미확보).
- `Feature_Representation.htm`의 실제 원문(위 모순 발견으로 재확인 필요).
- FME Form의 과거 명칭(FME Desktop 등)과 개명 시점.
