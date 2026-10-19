---
summary: "MKGeoJSONDecoder/MKGeoJSONFeature(MapKit, Swift)와 importGeoJSON/GeoJSONDelegate(MapKit JS)의 실제 클래스·메서드 시그니처를 Apple 공식 문서 JSON 데이터에서 확인"
source: "developer.apple.com/documentation/mapkit/*, developer.apple.com/documentation/mapkitjs/* (developer.apple.com/tutorials/data/... JSON 엔드포인트로 조회)"
created: "2026-08-12 00:20"
updated: "2026-08-12 00:20"
---
# MapKit·MapKit JS 공식 문서 — GeoJSON 디코딩·렌더링 API 조사

## 수집 기준

- 수집일: 2026-08-12
- 목적: 사용자가 "geoJSON 파일의 디코딩/렌더링 과정"을 별도 문서로 정리해달라고 요청. src03이 이 주제를 다뤘으나 본문을 확보하지 못해 "일반적 지식 기반의 추정 정보"로만 남아 있었음(src03 참고). developer.apple.com/documentation/의 실제 페이지는 SPA라 WebFetch로 본문이 안 잡히지만(제목만 반환됨), 동일 문서를 서빙하는 DocC JSON 엔드포인트(`developer.apple.com/tutorials/data/documentation/...json`)는 본문이 그대로 잡혀 이를 통해 원문을 확인함.

## 핵심 출처

- Displaying an Indoor Map (개요): https://developer.apple.com/tutorials/data/documentation/mapkit/displaying-an-indoor-map.json
- MKGeoJSONDecoder: https://developer.apple.com/tutorials/data/documentation/mapkit/mkgeojsondecoder.json
- MKGeoJSONFeature: https://developer.apple.com/tutorials/data/documentation/mapkit/mkgeojsonfeature.json
- MKGeoJSONObject: https://developer.apple.com/tutorials/data/documentation/mapkit/mkgeojsonobject.json
- Displaying Indoor Maps with MapKit JS (개요): https://developer.apple.com/tutorials/data/documentation/mapkitjs/displaying-indoor-maps-with-mapkit-js.json
- importGeoJSON: https://developer.apple.com/tutorials/data/documentation/mapkitjs/mapkit/importgeojson.json
- GeoJSONDelegate: https://developer.apple.com/tutorials/data/documentation/mapkitjs/geojsondelegate.json

## 1. MapKit(Swift, iOS) — Displaying an Indoor Map 개요

Abstract 원문: "Use the Indoor Mapping Data Format (IMDF) to show an indoor map with custom overlays and points of interest."

Overview 원문: "The sample app demonstrates decoding, rendering, and styling of a small subset of the IMDF feature types and their properties. Use these examples to create your own indoor map with a style that's consistent with your app's design. You'll need to handle feature categories that are specific to your venue, and configure the map style using your own colors, icons, and level picker."

지원 플랫폼: iOS 17.6+, iPadOS 17.6+, Mac Catalyst 17.6+, Xcode 16.0+. 샘플 코드 다운로드: `DisplayingAnIndoorMap.zip` (이번 조사에서는 zip 내부 코드는 확보하지 않음).

## 2. MKGeoJSONDecoder

Abstract 원문: "An object that decodes GeoJSON objects into MapKit types."

Declaration: `class MKGeoJSONDecoder`

Overview 원문: "The GeoJSON decoder returns objects that conform to the MKGeoJSONObject protocol."

디코딩 메서드:
- Swift: `func decode(_ data: Data) throws -> [any MKGeoJSONObject]`
- Objective-C 원래 이름: `geoJSONObjectsWithData:error:`
- 설명 원문: "Decodes the provided data into native MapKit types that a map can display."
- 매개변수: `Data`(GeoJSON 파일/바이트), `throws`로 에러 처리.

지원 플랫폼: iOS 13.0+, iPadOS 13.0+, macOS 10.15+, tvOS 13.0+, watchOS 6.0+, visionOS 1.0+.

## 3. MKGeoJSONObject (프로토콜)

Abstract 원문: "Objects that the GeoJSON decoder can return."

Overview 원문: "Classes that conform to this protocol represent the types that the GeoJSON decoder can return. There's no reason to create your own classes that conform to this protocol; only MapKit can define classes that the GeoJSON decoder uses."

이 프로토콜을 준수하는 구체 타입(Conforming Types) 전체 목록:
1. `MKGeoJSONFeature`
2. `MKGeodesicPolyline`
3. `MKMultiPoint`
4. `MKMultiPolygon`
5. `MKMultiPolyline`
6. `MKPointAnnotation`
7. `MKPolygon`
8. `MKPolyline`

→ `MKGeoJSONDecoder.decode(_:)`는 GeoJSON 파일 안의 각 도형(Point/LineString/Polygon 등)을 이 목록에 있는 MapKit 네이티브 도형 타입(MKPolygon, MKPolyline, MKPointAnnotation 등)으로, 그리고 Feature 전체는 MKGeoJSONFeature로 변환해 배열로 반환한다.

## 4. MKGeoJSONFeature

Abstract 원문: "The decoded representation of a GeoJSON feature."

Declaration: `class MKGeoJSONFeature : NSObject`

Overview 원문: "A feature is an object with associated geometry and optional properties in JSON that you define. MapKit exposes these optional properties, but treats them as opaque. MKGeoJSONFeature is one of the classes that the GeoJSON decoder (MKGeoJSONDecoder) can return. See the GeoJSON standards specification (RFC 7946 Section 3.2) for more information about Feature objects."

Properties(프로퍼티) 원문 그대로:

| 이름 | 타입 | 설명 |
| --- | --- | --- |
| `geometry` | `[any MKShape & MKGeoJSONObject]` | The shape or shapes associated with the GeoJSON feature. |
| `identifier` | `String?` | An optional identifier the class returns as a string. |
| `properties` | `Data?` | Optional serialized JSON data that corresponds to the properties key. |

→ 핵심 사실: MapKit은 GeoJSON Feature의 `properties`(원본 JSON의 `name`, `category`, `display_point` 등이 들어있던 그 객체)를 **파싱하지 않고 그대로 직렬화된 `Data`로만 노출한다**("treats them as opaque"). 즉 `category`/`name` 같은 개별 값을 실제로 읽으려면, 앱이 이 `Data`를 **자신이 정의한 구조체로 한 번 더 JSON 디코딩**해야 한다. Apple 문서는 이 2차 디코딩에 정확히 어떤 API(JSONDecoder 등)를 쓰라고 명시하지는 않았다 — `Data` 타입이라는 사실 자체만 확인되었고, "JSONDecoder를 쓴다"는 것은 Swift의 일반적 관행이지 이 문서 원문에 적힌 문장은 아니다(확인 필요로 표시).

## 5. MapKit JS — Displaying Indoor Maps with MapKit JS 개요

Abstract 원문: "Use the Indoor Mapping Data Format (IMDF) to show an indoor map with custom overlays and points of interest in your browser."

Overview 원문: "This sample uses the importGeoJSON method from MapKit JS to import data in Indoor Mapping Data Format (IMDF), and render an indoor map in your browser. The sample app demonstrates decoding, rendering, and styling of a small subset of the IMDF feature types and properties. Use these examples to create your own indoor map with a style that is consistent with your app's design. You can handle feature categories specific to your venue, and configure the map style using your own colors, icons, and level picker. This sample code project is associated with WWDC 2019 session 241: Adding Indoor Maps to your App and Website."

층(level) 전환 관련 API는 이 문서의 references/topics 안에서 명시적으로 확인되지 않았다.

## 6. importGeoJSON(data, callback)

Abstract 원문: "Converts imported GeoJSON data to MapKit JS compatible items."

Declaration(시그니처):
```ts
importGeoJSON(
    data: string | GeoJSONTypes.GeoJSON,
    callback?: GeoJSONDelegate | GeoJSONImporterCallback
):
    | ItemCollection<
          GeoJSONTypes.GeoJSON<
              GeoJSONTypes.Geometry,
              GeoJSONTypes.GeoJsonProperties
          >
      >
    | undefined;
```

Parameters 원문:
- `data`: "The original GeoJSON data, either a URL to a GeoJSON file, or a GeoJSON object."
- `callback`: "A callback function or an object that MapKit JS requires if you provide a URL for the data parameter. It's optional, otherwise."

Discussion 원문: "This function converts imported GeoJSON data into MapKit JS items, which are Annotation, Overlay, and ItemCollection objects. Access the original GeoJSON data through the object's data property. You can customize the import by implementing a GeoJSONDelegate delegate: If you provide a GeoJSON object for the data parameter, importGeoJSON returns the result directly. However, the system uses the optional callback, if you provide it. If you provide a URL to a GeoJSON file in the data parameter, you need to provide a callback function or delegate object. **Note:** You must load the geojson library first before accessing the method, otherwise, the method throws an Error."

→ MapKit JS는 각 결과 item의 `data` 프로퍼티로 "원본 GeoJSON 데이터"에 접근할 수 있다고 명시한다. 이 `data`가 MapKit(Swift)의 `properties: Data?`처럼 여전히 직렬화된 바이트인지, 아니면 이미 파싱된 JS 객체인지는 이번 조사에서 원문으로 확정하지 못했다(확인 필요).

## 7. GeoJSONDelegate

Abstract 원문: "A delegate object that controls a GeoJSON import to override default behavior and provide custom style."

제공되는 콜백/메서드 목록(문서에 나열된 이름 그대로):
- `itemForFeature` — Overrides a feature.
- `itemForFeatureCollection` — Overrides a feature collection.
- `itemForLineString` — Overrides a line string.
- `itemForMultiLineString` — Overrides a multiline string.
- `itemForPoint` — Overrides a point.
- `itemForMultiPoint` — Overrides a multipoint object.
- `itemForPolygon` — Overrides a polygon.
- `itemForMultiPolygon` — Overrides a multipolygon.
- `itemForGeometryCollection` — Overrides a geometry collection with the provided item and object.
- `styleForOverlay` — Overrides the style of overlays.
- `geoJSONDidComplete` — Completes the GeoJSON import.
- `geoJSONDidError` — Indicates when the GeoJSON import fails.

## 미해결 질문

- MapKit(Swift)에서 `MKGeoJSONFeature.properties`(Data?)를 실제로 어떤 API로 2차 디코딩하는지(JSONDecoder 사용 여부 등)는 Apple 공식 문서 원문에 명시되지 않음 — 확인 필요.
- MapKit JS `importGeoJSON` 결과 item의 `data` 프로퍼티가 파싱된 객체인지 직렬화된 문자열인지 확인 필요.
- 두 플랫폼 모두 디코딩된 도형을 실제 `MKMapView`/MapKit JS `Map`에 추가(렌더링)하는 구체적 코드는 다운로드 샘플(`DisplayingAnIndoorMap.zip`)에만 있고, 이번 조사에서는 확보하지 못함.
- MapKit/MapKit JS의 층(level) 전환 API 정확한 이름 — 여전히 미확인(src03에서 이어지는 미해결 질문).
