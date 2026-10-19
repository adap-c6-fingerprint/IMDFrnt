---
summary: "MapKit JS(웹)에서 GeoJSON 데이터를 Annotation/Overlay/ItemCollection으로 변환해 지도에 표시하는 임포트 함수"
source: "[[GeoJSON 디코딩과 렌더링 과정 — MapKit·MapKit JS]], developer.apple.com/documentation/mapkitjs/mapkit/importgeojson"
related:
  - "[[GeoJSON]]"
  - "[[IMDF]]"
  - "[[MKGeoJSONDecoder]]"
created: "2026-08-12 00:20"
updated: "2026-08-12 00:20"
core_keywords:
  - importGeoJSON
---
# importGeoJSON

## 요약

`importGeoJSON`은 MapKit JS(웹)에서 GeoJSON 파일 URL 또는 GeoJSON 객체를 MapKit JS가 다룰 수 있는 항목(Annotation·Overlay·ItemCollection)으로 변환하는 함수다. MapKit(Swift)의 `MKGeoJSONDecoder`에 대응하는 웹 쪽 진입점이다.

## 핵심 내용

- 시그니처:
```ts
importGeoJSON(
    data: string | GeoJSONTypes.GeoJSON,
    callback?: GeoJSONDelegate | GeoJSONImporterCallback
): ItemCollection<...> | undefined;
```
- `data`: GeoJSON 파일 URL 또는 GeoJSON 객체. `callback`: `data`가 URL이면 필수, 객체를 직접 넘기면 선택.
- 원문: "This function converts imported GeoJSON data into MapKit JS items, which are Annotation, Overlay, and ItemCollection objects. Access the original GeoJSON data through the object's `data` property."
- 주의: "You must load the geojson library first before accessing the method, otherwise, the method throws an Error."
- `GeoJSONDelegate`를 구현하면 `itemForFeature`, `itemForPolygon`, `styleForOverlay` 등으로 임포트 결과를 재정의할 수 있고, `geoJSONDidComplete`/`geoJSONDidError`로 완료·에러를 처리한다.

## 관련 링크

- [[GeoJSON]] — 임포트 대상 파일 포맷
- [[IMDF]] — 이 함수로 읽는 대표적 실내 지도 데이터
- [[MKGeoJSONDecoder]] — 같은 역할을 하는 MapKit(Swift, 앱)의 대응 클래스

## 미해결 질문

- 결과 item의 `data` 프로퍼티가 파싱된 JS 객체인지 직렬화된 문자열인지 확인 필요.
- 층(level) 전환 관련 API 이름 미확인.
