---
summary: "Safe Software의 공간 데이터 ETL 플랫폼 FME — 회사 배경, FME Form, IMDF Reader/Writer 지원 방식, CAD→ArcGIS Indoors→IMDF로 이어지는 실무 파이프라인에서의 역할 정리"
source: "01-2) 소스 --------------------/S06) Indoor Map/S06-02) FP-to-IMDF/src07. FME·ArcGIS Indoors 툴 자체 조사.md"
related:
  - "[[FME]]"
  - "[[IMDF]]"
  - "[[GeoJSON]]"
  - "[[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]]"
  - "[[04) ArcGIS Indoors]]"
core_keywords:
  - FME
created: "2026-08-13 00:30"
updated: "2026-08-13 00:30"
---
# FME

## 요약

FME(Feature Manipulation Engine)는 캐나다 Safe Software가 만든 공간 데이터 ETL(Extract, Transform, Load) 플랫폼으로, `02) 도면에서 GeoJSON(IMDF) 추출 전 과정.md`에서 다룬 CAD→IMDF 변환의 실무 도구다. 이 문서는 FME 자체가 어떤 회사·제품인지, 그리고 IMDF 워크플로우 안에서 정확히 어떤 역할을 맡는지를 별도로 정리한다.

## 1. 회사·제품 배경

- Safe Software는 1993년 캐나다 브리티시컬럼비아주 서리(Surrey)에서 Don Murray와 Dale Lutz가 공동 창업했다. 인증된 B Corp(공익법인)이다.
- FME는 "300개 이상"(다른 공식 페이지에서는 "400개 이상"으로도 서술 — 출처마다 수치가 달라 확인 필요) 공간·비공간 데이터 포맷을 서로 변환·통합하는 ETL 도구다.
- **FME Form**은 코드 작성 없이(no-code) 데이터 변환 워크플로우를 만드는 저작 환경이다.
- Gartner Magic Quadrant for Data Integration Tools에서 "Niche Player"로 6년 연속(2025년 기준) 선정되었다고 서술된다.

## 2. IMDF Reader/Writer

- FME는 IMDF를 읽고 쓰는 전용 Reader/Writer를 내장한다: "supports both reading from and writing to IMDF."
- IMDF Writer는 하나의 zip 파일에 Feature Type별 GeoJSON 파일(levels, units, openings, venue, address, building, footprints 등)을 담아 출력한다 — "An IMDF dataset is a folder of GeoJSON files with one file per IMDF feature type."
- FME가 IMDF 제작에 적합한 이유(공식 서술): "not just because it supports the translation of data to IMDF format, but also because it supports reading several hundred types and formats of data in which source maps might be stored." — 즉 출력(IMDF)뿐 아니라 입력(CAD/BIM/GIS 등 원본 도면 포맷) 쪽 지원 범위가 넓다는 점이 핵심 장점으로 제시된다.

## 3. 실무 파이프라인에서의 위치 — CAD → ArcGIS Indoors → IMDF

공식 서술: "An organization can use FME to bring indoor mapping data from CAD into Esri ArcGIS Indoors for editing and maintenance, and then set up FME to automatically convert the data from ArcGIS into IMDF."

즉 실무에서 FME는 파이프라인의 **양 끝**을 맡는 경우가 많다:

```
CAD 원본 도면
  → FME (CAD를 읽어 ArcGIS Indoors로 반입)
  → ArcGIS Indoors (편집·유지관리 — 04) ArcGIS Indoors 참고)
  → FME (ArcGIS Indoors 데이터를 IMDF로 자동 변환)
  → IMDF(.geojson zip)
```

`02) 도면에서 GeoJSON(IMDF) 추출 전 과정.md`이 정리한 "FME 경로"(AutoCAD DWG 3부작 튜토리얼)는 이 중 CAD를 직접 IMDF로 바로 변환하는 단순화된 경로였고, 이 문서에서 확인한 "CAD→ArcGIS Indoors→IMDF" 경로는 중간에 ArcGIS Indoors의 시설관리 기능(자산·공간 관리)을 함께 쓰고 싶을 때 선택하는 조합이다. 두 경로 모두 최종 출력(IMDF Writer)은 FME가 맡는다는 점은 같다.

## 관련 링크

- [[IMDF]] — FME가 최종적으로 만드는 산출물 규격
- [[GeoJSON]] — FME Writer가 출력하는 파일 포맷
- [[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]] — FME를 이용한 CAD 직접 변환 경로(3부작 튜토리얼)
- [[04) ArcGIS Indoors]] — FME와 조합되는 시설관리형 실내 GIS 제품

## 미해결 질문

- FME가 지원하는 정확한 포맷 개수(공식 페이지마다 300개/400개로 다르게 서술).
- FME Form의 과거 명칭(FME Desktop 등)과 개명 시점.
- IMDF Writer의 전체 필수 파라미터 목록 — 일부(Default Language, Coordinate System 등)만 확인됨.
