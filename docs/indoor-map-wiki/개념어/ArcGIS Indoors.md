---
summary: "Esri ArcGIS Pro의 실내 지도 확장. CAD/BIM 도면을 Indoors Geodatabase로 임포트해 실내 GIS 데이터셋을 만드는 데 쓰인다"
source: "[[도면에서 GeoJSON(IMDF) 추출 전 과정]], cloudpointgeo.com"
related:
  - "[[IMDF]]"
  - "[[FME]]"
  - "[[지오레퍼런싱]]"
  - "[[04) ArcGIS Indoors]]"
  - "[[03) FME]]"
created: "2026-08-13 00:00"
updated: "2026-08-13 00:30"
core_keywords:
  - ArcGIS Indoors
---
# ArcGIS Indoors

## 요약

ArcGIS Indoors는 Esri ArcGIS Pro의 실내 지도 확장으로, CAD·BIM 도면을 실내 GIS 데이터셋(Indoors Geodatabase)으로 임포트하는 지오프로세싱 도구를 제공한다. IMDF 제작 워크플로우에서 Safe Software(FME)와 함께 언급되는 경로 중 하나다.

## 핵심 내용

- 선행 작업: "Define Projection" 도구로 좌표계(대개 지역 State Plane)를 정의하고, "Georeference 도구"로 이동·회전·스케일 조정을 거쳐 CAD 레이어를 실제 지리적 위치에 정렬한다.
- CAD 파일: Excel 템플릿을 채운 뒤 지오프로세싱 도구 **"Import Floorplans To Indoors Geodatabase"** 실행.
- BIM 파일: 지오프로세싱 도구 **"Import BIM to Indoors Dataset"** 실행.
- **후속 확인(2026-08-13):** Indoors Geodatabase → IMDF export는 **Esri 자체 기능이 아니라 FME를 재사용한다.** "Generate Unit Openings" 도구로 IMDF가 요구하는 LineString Opening을 먼저 만든 뒤, ArcGIS Pro의 Data Interoperability Extension(FME 엔진 내장)으로 FME Hub 배포 "ArcGIS Indoors Model to IMDF" 워크벤치를 실행한다. 자세한 내용과 원문 인용은 [[04) ArcGIS Indoors]] 참고.
- ArcGIS Indoors는 IMDF 변환 전용 도구가 아니라 자산·공간·안전 관리를 아우르는 실내 GIS 제품군이며, 라이선스는 Indoors Pro/Indoors Maps/Indoors Spaces 3종으로 나뉜다.

## 관련 링크

- [[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]] — ArcGIS Indoors 경로가 정리된 문서
- [[04) ArcGIS Indoors]] — 제품·라이선스·IMDF export 절차를 다룬 심화 문서
- [[IMDF]] — 이 도구로 만드는 데이터의 최종 목표 규격
- [[FME]] — IMDF export 시 실제로 재사용되는 엔진
- [[지오레퍼런싱]] — Georeference 도구가 수행하는 작업의 개념 문서

## 미해결 질문

- "ArcGIS Indoors Model to IMDF" FME 워크벤치 자체의 세부 내용 — 원문 페이지 403으로 미확보.
