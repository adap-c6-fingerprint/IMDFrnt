---
summary: 지리 공간 피처를 기하 형태와 속성으로 표현하는 JSON 기반 텍스트 포맷. IMDF의 파일 표현 방식
source: "[[Apple Indoor Maps Program과 IMDF 개요]], WWDC19 Session 245"
related:
  - "[[IMDF]]"
  - "[[MKGeoJSONDecoder]]"
  - "[[importGeoJSON]]"
created: 2026-08-05 16:40
updated: 2026-08-12 00:20
core_keywords:
  - GeoJSON
---
# GeoJSON

## 요약

GeoJSON은 지리 공간 피처(점·선·다각형 등)를 기하 형태와 속성(properties)으로 표현하는 JSON 기반 텍스트 포맷이다. IMDF 아카이브는 여러 개의 GeoJSON 파일 묶음으로 표현되며, MapKit과 MapKit JS가 GeoJSON의 디코딩·렌더링을 지원한다.

## 핵심 내용

- 각 피처는 고유 UUID, 피처 타입(예: level), 기하 형태(geometry), 속성을 가진다.
- 예시(IMDF의 level 피처): 공개 접근 가능 건물이면 `restriction`이 `null`, 실내 여부, 엘리베이터 버튼에 표시되는 이름(`L1`), 단일 building ID와의 연관 등이 담긴다.
- 사람이 읽을 수 있는 단순 텍스트라서, 포괄적인 실내 정보를 담으면서도 도구 간 교환이 쉽다.
- MapKit/MapKit JS로 지도 위 오버레이·어노테이션으로 표시할 수 있다.
- 실제 디코딩은 MapKit(Swift)에서는 [[MKGeoJSONDecoder]], MapKit JS(웹)에서는 [[importGeoJSON]]이 담당한다. 두 API 모두 도형(geometry)은 네이티브 타입으로 바로 변환하지만, `properties`는 그대로 파싱하지 않거나(Swift: opaque `Data`) 별도 확인이 필요해(JS: `data` 프로퍼티), 자세한 내용은 [[06) GeoJSON 디코딩과 렌더링 과정 — MapKit·MapKit JS]] 참고.

## 관련 링크

- [[IMDF]] — GeoJSON 파일 묶음으로 구성되는 실내 지도 규격
- [[MKGeoJSONDecoder]] — MapKit(Swift)의 GeoJSON 디코더
- [[importGeoJSON]] — MapKit JS의 GeoJSON 임포트 함수

## 미해결 질문

- IMDF가 표준 GeoJSON에 부가한 제약·확장 규칙은 구체적으로 무엇인가.
