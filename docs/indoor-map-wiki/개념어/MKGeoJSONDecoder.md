---
summary: "MapKit(Swift)에서 GeoJSON 데이터를 네이티브 도형 타입으로 디코딩하는 클래스. properties는 파싱하지 않고 opaque Data로만 노출"
source: "[[GeoJSON 디코딩과 렌더링 과정 — MapKit·MapKit JS]], developer.apple.com/documentation/mapkit/mkgeojsondecoder"
related:
  - "[[GeoJSON]]"
  - "[[IMDF]]"
  - "[[importGeoJSON]]"
created: "2026-08-12 00:20"
updated: "2026-08-12 00:20"
core_keywords:
  - MKGeoJSONDecoder
---
# MKGeoJSONDecoder

## 요약

`MKGeoJSONDecoder`는 MapKit(Swift, iOS/macOS 등)에서 GeoJSON 형식의 `Data`를 MapKit이 지도에 바로 표시할 수 있는 네이티브 타입으로 디코딩하는 클래스다.

## 핵심 내용

- 선언: `class MKGeoJSONDecoder`
- 디코딩 메서드: `func decode(_ data: Data) throws -> [any MKGeoJSONObject]` — 원문: "Decodes the provided data into native MapKit types that a map can display."
- 반환되는 `MKGeoJSONObject` 준수 타입 8종: `MKGeoJSONFeature`, `MKGeodesicPolyline`, `MKMultiPoint`, `MKMultiPolygon`, `MKMultiPolyline`, `MKPointAnnotation`, `MKPolygon`, `MKPolyline`.
- GeoJSON Feature 하나는 `MKGeoJSONFeature`로 반환되며, 그 안의 `geometry`는 도형 타입으로 바로 쓸 수 있지만 `properties: Data?`는 원문 그대로 "MapKit exposes these optional properties, but treats them as opaque" — 즉 파싱되지 않은 직렬화 JSON `Data`로만 제공된다. `category`, `name` 같은 개별 값을 쓰려면 앱이 이 `Data`를 별도로 다시 디코딩해야 한다.
- 지원 플랫폼: iOS 13.0+, iPadOS 13.0+, macOS 10.15+, tvOS 13.0+, watchOS 6.0+, visionOS 1.0+.

## 관련 링크

- [[GeoJSON]] — 디코딩 대상 파일 포맷
- [[IMDF]] — 이 디코더로 읽는 대표적 실내 지도 데이터
- [[importGeoJSON]] — 같은 역할을 하는 MapKit JS(웹)의 대응 함수

## 미해결 질문

- `properties: Data?`를 2차 디코딩하는 정확한 권장 API(JSONDecoder 등)가 공식 문서에 명시되어 있는지 — 확인 필요.
