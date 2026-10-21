---
summary: "Esri의 실내 시설관리 GIS 제품 ArcGIS Indoors — 라이선스 구조와, Data Interoperability Extension(FME 엔진 내장)을 통해 실제로는 FME를 재사용해 IMDF로 export하는 절차 정리"
source: "01-2) 소스 --------------------/S06) Indoor Map/S06-02) FP-to-IMDF/src07. FME·ArcGIS Indoors 툴 자체 조사.md"
related:
  - "[[ArcGIS Indoors]]"
  - "[[IMDF]]"
  - "[[03) FME]]"
  - "[[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]]"
core_keywords:
  - ArcGIS Indoors
created: "2026-08-13 00:30"
updated: "2026-08-13 00:30"
---
# ArcGIS Indoors

## 요약

ArcGIS Indoors는 Esri의 실내 매핑·공간관리 소프트웨어로, `02) 도면에서 GeoJSON(IMDF) 추출 전 과정.md`에서는 CAD/BIM을 Indoors Geodatabase로 반입하는 경로로만 짧게 다뤘다. 실제로는 **IMDF 변환 전용 도구가 아니라 시설관리(자산·공간·안전) 전반을 다루는 훨씬 큰 실내 GIS 제품군**이며, IMDF 익스포트는 그중 "Apple 실내 측위 연동"을 위한 한 기능이다. 이 문서는 제품 자체와, 이전에 확인하지 못했던 **Indoors Geodatabase → IMDF 최종 변환 절차**를 정리한다.

## 1. 제품 개요와 라이선스

- 공식 설명: "실내 공간 및 건물 관리를 위한 포괄적인 실내 매핑 소프트웨어." CAD·BIM·라이다 및 기타 시설 데이터를 하나의 지도로 통합한다.
- 주요 용도: 자산 관리(IT·시설·보안 담당자가 실내 자산 위치 파악), 안전·보안(사람·공간·자산 위치 시각화), 공간 예약 관리(업무 공간 할당·예약·재배치 계획), 실내 내비게이션(방문객·점유자 길찾기).
- 라이선스 3종:
  - **Indoors Pro** — ArcGIS Pro 확장, GIS 전문가용 실내 지도 제작 도구.
  - **Indoors Maps** — ArcGIS Enterprise/Online용 조직 확장, 무제한 사용자 접근.
  - **Indoors Spaces** — Indoors Maps에 추가하는 공간 계획·관리(할당·예약) 기능.

## 2. Indoors Geodatabase → IMDF export 절차 (이전 "확인 필요" 해소)

`02) 도면에서 GeoJSON(IMDF) 추출 전 과정.md`과 그 근거 소스(src06)는 "Indoors Geodatabase에서 최종 IMDF로 export하는 절차가 Esri 자체 기능인지 FME를 재사용하는지 확인하지 못했다"고 남겼다. 이번 조사로 **FME를 재사용하는 것으로 확인됐다.**

절차:

1. **Generate Unit Openings** 지오프로세싱 도구 실행 — 공식 설명: "Creates unit openings as line features that model the location and physical extent of an entrance." IMDF의 Opening은 LineString(선) geometry가 요구되는데, ArcGIS Indoors의 문(door)은 기본적으로 다른 방식(도면 심볼 등)으로 표현되므로, 이 도구로 선 형태의 Opening 피처를 별도 생성해야 한다: "Line features that represent openings are **required** to export indoor data to the Indoor Mapping Data Format (IMDF) for use in Apple indoor positioning." 부가 이유: "Modeling openings as lines simplifies maps by avoiding complex door symbology."
2. **ArcGIS Pro의 Data Interoperability Extension**(Esri가 FME 엔진을 라이선스해 내장한 확장 기능)으로, **FME Hub에서 배포되는 "ArcGIS Indoors Model to IMDF" 워크벤치**를 실행한다(WebSearch 스니펫 기준 확인 — 원문 페이지는 403으로 직접 대조 못 해 확인 필요로 표시).
3. 산출된 IMDF(.geojson zip)를 [[IMDF Sandbox]]로 검증한다.

즉 ArcGIS Indoors 자체에는 IMDF를 직접 출력하는 고유 기능이 없고, **Esri 제품 안에 내장된 FME(Data Interoperability Extension)를 다시 호출해 변환한다** — [[03) FME]]가 정리한 "CAD → ArcGIS Indoors → FME → IMDF" 파이프라인의 마지막 화살표가 정확히 이 지점이다.

## 관련 링크

- [[03) FME]] — ArcGIS Indoors → IMDF 변환을 실제로 수행하는 엔진(Data Interoperability Extension)
- [[IMDF]] — 이 도구로 만드는 데이터의 최종 목표 규격
- [[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]] — CAD/BIM을 ArcGIS Indoors로 반입하는 앞 단계

## 미해결 질문

- "ArcGIS Indoors Model to IMDF" FME 워크벤치 자체의 세부 내용 — 원문 페이지 403으로 미확보.
- Data Interoperability Extension이 FME Form/Server와 정확히 어떤 라이선스·기능 관계인지.
