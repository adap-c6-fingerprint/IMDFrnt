---
summary: Apple이 정의한 실내 공간 모델링 규격. 여러 GeoJSON 파일 묶음으로 실내 지도를 표현하는 사실상의 교환 표준
source: "[[Apple Indoor Maps Program과 IMDF 개요]], WWDC19 Session 245"
related:
  - "[[Indoor Maps Program]]"
  - "[[IMDF Sandbox]]"
  - "[[GeoJSON]]"
  - "[[지오레퍼런싱]]"
  - "[[LABELS]]"
  - "[[Display Point]]"
  - "[[IMDF 아카이브]]"
  - "[[nonpublic]]"
  - "[[RESTRICTION-CATEGORY]]"
  - "[[대칭차]]"
  - "[[walkway]]"
created: 2026-08-05 16:40
updated: 2026-10-19 14:45
core_keywords:
  - IMDF
---
# IMDF

## 요약

IMDF(Indoor Mapping Data Format)는 Apple이 정의한 실내 공간 모델링 규격이다. 여러 개의 GeoJSON 파일 묶음(아카이브)으로 표현되며, 실내 데이터의 사실상 교환 표준(de facto exchange standard)으로 빠르게 자리 잡았다. 많은 GIS·BIM 플랫폼이 이미 IMDF 생성·편집을 지원한다.

## 핵심 내용

- 실내 지도를 여러 **레이어**로 나누고, 각 레이어는 여러 **피처(feature)**를 담는다.
- 세 개의 핵심 파일이 venue의 기본 정보를 준다: **manifest**(관리 정보), **address**(우편 주소), **venue**(장소 전체 형태).
- 피처 계층: building → level → unit/opening → section/trigger region → kiosk/fixture → amenity → anchor·unit address·occupant.
- 유닛은 절대 서로 겹치면 안 되고, 레벨은 유닛으로 완전히 덮여야 하며, 통로(walkway)도 자기 카테고리를 가진 유닛이다.
- CAD/BIM/GIS 파일을 Safe Software([[FME]]), Autodesk, Esri([[ArcGIS Indoors]]) 등 업계 표준 도구로 IMDF로 변환한다. 변환의 전 과정(지오레퍼런싱·레이어 정리·속성 부여·검증)은 [[02) 도면에서 GeoJSON(IMDF) 추출 전 과정]] 참고.
- 각 피처는 고유 UUID, 카테고리, 기하 형태를 가진다. 개발자 관점에서는 "포괄적 정보를 담은 단순 텍스트(GeoJSON) 파일"이다.
- 전체 Feature Type은 16개(Address, Amenity, Anchor, Building, Detail, Fixture, Footprint, Geofence, Kiosk, Level, Occupant, Opening, Relationship, Section, Unit, Venue)이며, "Label"이라는 이름의 독립 Feature Type은 없다. 이름(라벨) 표시는 Unit·Kiosk·Amenity·Section·Opening·Occupant 등 각 Feature의 `properties` 안 `name`/`alt_name` 속성([[LABELS]] 타입)이 담당하고, 이를 지도에 그릴 좌표는 별도의 `display_point` 속성([[Display Point]] 타입)이 담당한다. 자세한 근거는 [[05) 라벨에 관하여]] 참고.

## 관련 링크

- [[Indoor Maps Program]] — IMDF를 중심으로 돌아가는 Apple 프로그램
- [[IMDF Sandbox]] — IMDF 시각화·검증·편집 도구
- [[GeoJSON]] — IMDF의 파일 표현 포맷
- [[지오레퍼런싱]] — IMDF를 지구 좌표에 정렬
- [[LABELS]] — 각 Feature의 name/alt_name 속성 데이터 타입
- [[Display Point]] — 각 Feature의 라벨 표시 좌표 속성 데이터 타입
- [[IMDF 아카이브]] — manifest.json과 .geojson 묶음을 ZIP으로 전달하는 단위, 패키징은 [[14) .geojson 파일을 모아 IMDF 아카이브로 패키징하는 과정]]
- [[Feature Type]] — `feature_type` 필드에 들어가는 16개 분류값
- [[UNIT-CATEGORY]] — Unit 피처의 하위 분류 열거형
- [[nonpublic]]·[[RESTRICTION-CATEGORY]] — 방문자 출입 불가·제한 구역의 표현, 정리는 [[15) 비개방 구역은 IMDF에서 어떻게 그리는가 — nonpublic과 restriction]]
- [[대칭차]]·[[walkway]] — Unit이 층을 빈틈·겹침 없이 채우는 규칙과 통로 병합 규칙, 정리는 [[16) Unit 레이어 태깅 규칙 — 무엇을 한 Unit으로 자르고 어떤 category를 붙이는가]]
- [[08) IMDF Feature Type·카테고리 전체 레퍼런스]] — Feature Type 16종과 카테고리 열거형 15종의 전체 값 목록
- [[19) name·category 필수 입력 여부 — Feature Type 16종 한눈에 보기]] — category는 칸이 있으면 필수, name은 Venue·Level·Occupant만 필수

## 미해결 질문

- 2019년 이후 IMDF 스펙 버전 변화와 최신 규격은 무엇인가.
