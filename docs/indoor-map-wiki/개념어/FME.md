---
summary: "Safe Software의 데이터 변환(ETL) 소프트웨어. Apple이 IMDF 제작 공식 파트너로 명시하며, CAD/BIM/GIS 도면을 IMDF(GeoJSON)로 변환하는 데 쓰인다"
source: "[[도면에서 GeoJSON(IMDF) 추출 전 과정]], fme.safe.com, support.safe.com, register.apple.com/resources/indoor"
related:
  - "[[IMDF]]"
  - "[[GeoJSON]]"
  - "[[지오레퍼런싱]]"
  - "[[03) FME]]"
  - "[[04) ArcGIS Indoors]]"
created: "2026-08-13 00:00"
updated: "2026-08-13 00:30"
core_keywords:
  - FME
---
# FME

## 요약

FME(Feature Manipulation Engine)는 Safe Software가 만든 데이터 변환(ETL) 소프트웨어로, 400개 이상의 공간 데이터 포맷(CAD, BIM, GIS, Excel 등)을 서로 변환할 수 있다. Apple Indoor Maps Program의 Additional Resources 페이지가 IMDF 제작 공식 파트너로 명시하는 도구이며, CAD/BIM 도면을 IMDF(GeoJSON)로 변환하는 실무에 널리 쓰인다.

## 핵심 내용

- IMDF Reader/Writer를 내장해 GeoJSON 기반 IMDF를 읽고 쓸 수 있다("supports both reading from and writing to IMDF").
- AutoCAD DWG → IMDF 변환은 대표적으로 3단계로 이뤄진다: ① PreProcess(좌표 추출·지오레퍼런싱·속성 명명), ② AutoCAD에서 레이어별 수동 정리(Units 빈 영역=벽 처리, 기둥→Columns 레이어), ③ Writer로 Feature Type별 GeoJSON을 담은 zip 출력 + 지오레퍼런싱 재적용(`ApplyGeoreferencing`) + 검증.
- Writer는 하나의 zip 파일에 levels, units, openings, venue, address, building, footprints 등 Feature Type별 GeoJSON 파일을 담아 출력한다.
- 검증은 IMDFValidator로 수행하고, 이후 Apple Maps Connect로 제출한다.
- Safe Software 직원 코멘트: "CAD is likely the hardest data to properly convert to IMDF, since it allows a great deal of latitude in the presentation and topology of the features, and IMDF is pretty rigid in its requirements."
- 회사: Safe Software(1993년 캐나다 서리 설립, Don Murray·Dale Lutz 공동창업, B Corp). 제품군 중 **FME Form**이 코드 없이 데이터 변환 워크플로우를 만드는 저작 환경이다.
- 실무에서는 "CAD → FME → ArcGIS Indoors(편집·유지관리) → FME → IMDF"처럼, FME가 파이프라인 양 끝(원본 흡수·IMDF 출력)을 모두 맡는 조합도 쓰인다. 자세한 내용은 [[03) FME]] 참고.

## 관련 링크

- [[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]] — FME 워크플로우 전체 정리
- [[03) FME]] — 회사 배경·ArcGIS Indoors와의 조합까지 다룬 심화 문서
- [[IMDF]] — FME가 최종적으로 만드는 산출물 규격
- [[GeoJSON]] — FME Writer가 출력하는 파일 포맷
- [[지오레퍼런싱]] — FME 전처리 단계에서 이뤄지는 좌표 정렬

## 미해결 질문

- FME IMDF Writer의 전체 필수 파라미터 목록(manifest 필드 등) — 일부만 확인됨.
