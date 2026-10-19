---
summary: "IMDF(GeoJSON) 파일을 MapKit(Swift)은 MKGeoJSONDecoder+MKGeoJSONFeature로, MapKit JS는 importGeoJSON+GeoJSONDelegate로 디코딩·렌더링하는 실제 API 구조 정리"
source: "01-2) 소스 --------------------/S06) Indoor Map/S06-01) Indoor Map Overall/src05. MapKit·MapKit JS 공식 문서 — GeoJSON 디코딩·렌더링 API 조사.md"
related:
  - "[[GeoJSON]]"
  - "[[IMDF]]"
  - "[[MKGeoJSONDecoder]]"
  - "[[importGeoJSON]]"
core_keywords:
  - GeoJSON
  - MKGeoJSONDecoder
  - importGeoJSON
created: "2026-08-12 00:20"
updated: "2026-08-12 00:20"
---
# GeoJSON 디코딩과 렌더링 과정 — MapKit·MapKit JS

## 요약

WWDC19 세션(Session 245)은 "MapKit과 MapKit JS는 GeoJSON 파일의 디코딩과 렌더링을 지원한다"고만 짧게 언급한다. 이 문서는 그 "디코딩·렌더링"이 실제로 어떤 API로 이뤄지는지, Apple 공식 문서(developer.apple.com)를 직접 조사해 정리한다. 핵심은 **두 플랫폼 모두 디코딩이 한 번에 끝나지 않는다는 점**이다 — 도형(geometry)은 네이티브 타입으로 바로 디코딩되지만, 이름·카테고리 같은 속성(properties)은 별도로 다시 다뤄야 한다.

## 1. MapKit(Swift, iOS) — 2단계 디코딩

### 1.1 1단계: 도형(geometry) 디코딩 — `MKGeoJSONDecoder`

```swift
class MKGeoJSONDecoder
func decode(_ data: Data) throws -> [any MKGeoJSONObject]
// "Decodes the provided data into native MapKit types that a map can display."
```

- `Data`(GeoJSON 파일 바이트)를 넣으면, `MKGeoJSONObject` 프로토콜을 준수하는 MapKit 네이티브 타입 배열을 반환한다.
- `MKGeoJSONObject`를 준수하는 구체 타입 8종: `MKGeoJSONFeature`, `MKGeodesicPolyline`, `MKMultiPoint`, `MKMultiPolygon`, `MKMultiPolyline`, `MKPointAnnotation`, `MKPolygon`, `MKPolyline`.
- 즉 GeoJSON의 `Polygon`은 `MKPolygon`으로, `Point`는 `MKPointAnnotation`으로 이런 식으로 이미 MapKit이 다룰 수 있는 도형 객체로 자동 변환된다. Feature 전체(도형+속성 묶음)는 `MKGeoJSONFeature`로 반환된다.

### 1.2 2단계: 속성(properties) 디코딩 — `MKGeoJSONFeature.properties`

`MKGeoJSONFeature`의 프로퍼티:

| 이름 | 타입 | 설명 |
| --- | --- | --- |
| `geometry` | `[any MKShape & MKGeoJSONObject]` | The shape or shapes associated with the GeoJSON feature. |
| `identifier` | `String?` | An optional identifier the class returns as a string. |
| `properties` | `Data?` | Optional serialized JSON data that corresponds to the properties key. |

공식 문서 원문: "A feature is an object with associated geometry and optional properties in JSON that you define. **MapKit exposes these optional properties, but treats them as opaque.**"

- 여기가 핵심이다. IMDF Unit Feature의 `properties` 안에 있던 `category`("room"), `name`({"en": "Ball Room"}), `display_point` 같은 값들을, 1단계의 `MKGeoJSONDecoder.decode(_:)`는 **읽어서 구조화해주지 않는다.** 그냥 원본 JSON 바이트 그대로인 `Data`로만 넘겨준다("opaque" = 내용을 들여다보지 않고 그대로 통째로 전달).
- 따라서 `category`나 `name` 값을 실제로 쓰려면, 앱이 이 `properties: Data?`를 **자신이 정의한 구조체로 한 번 더 JSON 디코딩**해야 한다. 즉 "GeoJSON → MapKit 네이티브 도형"이라는 1차 디코딩과, "properties Data → 앱이 정의한 Codable 구조체"라는 2차 디코딩, 두 단계가 필요하다.
- 확인 필요: Apple 공식 문서 원문에는 이 2차 디코딩에 정확히 `JSONDecoder`를 쓰라는 문장은 없다. `Data` 타입이라는 사실만 명시돼 있고, 그것을 어떤 방법으로 파싱할지는 앱 개발자의 재량이다(단, `Data`가 곧 직렬화된 JSON이라는 설명 자체는 원문에 있으므로, Swift에서 이를 구조화하려면 `JSONDecoder`/`JSONSerialization` 같은 표준 JSON 파서를 쓰는 것이 일반적인 방법이다 — 이는 Swift의 일반 관행이지 이 문서가 규정한 절차는 아니다).

### 1.3 렌더링(지도에 추가) 단계

Apple 개요 문서 원문: "The sample app demonstrates decoding, rendering, and styling of a small subset of the IMDF feature types and their properties. ... You'll need to handle feature categories that are specific to your venue, and configure the map style using your own colors, icons, and level picker."

- 디코딩된 `MKPolygon`/`MKPolyline`/`MKPointAnnotation` 등을 `MKMapView`에 오버레이·어노테이션으로 추가하고, 2차 디코딩한 `category` 값에 따라 스타일(색상·아이콘)을 입히는 것이 렌더링 단계로 서술된다.
- 확인 필요: 오버레이 추가·스타일링의 정확한 코드(`addOverlay` 호출 형태, `MKOverlayRenderer` 구현 등)는 다운로드 가능한 샘플 프로젝트(`DisplayingAnIndoorMap.zip`) 안에만 있고, 이번 조사에서 그 코드 자체는 확보하지 못했다.

## 2. MapKit JS — `importGeoJSON`

### 2.1 시그니처

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

- `data`: GeoJSON 파일 URL 문자열 또는 GeoJSON 객체.
- `callback`: `data`가 URL이면 필수, GeoJSON 객체를 직접 넘기면 선택.
- 공식 문서 원문: "This function converts imported GeoJSON data into MapKit JS items, which are Annotation, Overlay, and ItemCollection objects. Access the original GeoJSON data through the object's `data` property."
- 주의사항 원문: "You must load the geojson library first before accessing the method, otherwise, the method throws an Error."

### 2.2 `GeoJSONDelegate` — 커스터마이징

임포트 결과를 재정의(override)하는 콜백들: `itemForFeature`, `itemForFeatureCollection`, `itemForLineString`, `itemForMultiLineString`, `itemForPoint`, `itemForMultiPoint`, `itemForPolygon`, `itemForMultiPolygon`, `itemForGeometryCollection`, `styleForOverlay`. 완료·에러 처리: `geoJSONDidComplete`, `geoJSONDidError`.

### 2.3 결과 구조

`importGeoJSON`의 반환값은 `ItemCollection`(Annotation·Overlay·중첩 ItemCollection을 담는 트리 구조)이다. 각 item은 `data` 프로퍼티로 "원본 GeoJSON 데이터"에 접근할 수 있다고 문서는 설명한다.

- 확인 필요: 이 `data` 프로퍼티가 MapKit(Swift)의 `properties: Data?`처럼 여전히 직렬화된 바이트/문자열인지, 아니면 이미 파싱된 JS 객체(그래서 `.category`, `.name` 처럼 바로 접근 가능한지)는 이번 조사의 공식 문서 원문에서 확정하지 못했다.
- 층(level) 전환과 관련된 API 이름은 조사 범위 안에서 확인되지 않았다.

## 3. 두 플랫폼 비교

| 구분 | MapKit (Swift) | MapKit JS |
| --- | --- | --- |
| 진입 API | `MKGeoJSONDecoder.decode(_:)` | `importGeoJSON(data, callback)` |
| 반환 타입 | `[any MKGeoJSONObject]` (MKPolygon, MKGeoJSONFeature 등) | `ItemCollection` (Annotation/Overlay/ItemCollection) |
| 속성(properties) 접근 | `MKGeoJSONFeature.properties: Data?` — opaque, 2차 디코딩 필요 | item의 `data` 프로퍼티 — 파싱 여부 확인 필요 |
| 커스터마이징 지점 | 문서에 명시된 델리게이트/프로토콜 없음(확인 필요) | `GeoJSONDelegate`(itemForFeature 등 콜백) |
| 실제 렌더링(오버레이 추가) 코드 | 샘플 프로젝트에만 존재, 미확보 | 샘플 프로젝트에만 존재, 미확보 |

## 관련 링크

- [[GeoJSON]] — 이 문서가 다루는 디코딩 대상 파일 포맷
- [[IMDF]] — 디코딩되는 데이터의 실제 내용(Unit·Opening 등 Feature Type)
- [[MKGeoJSONDecoder]] — MapKit(Swift)의 GeoJSON 디코더
- [[importGeoJSON]] — MapKit JS의 GeoJSON 임포트 함수
- [[05) 라벨에 관하여]] — `category`/`name`이 `properties` 안에 있다는 구조가 왜 "2차 디코딩"을 요구하는지의 배경

## 미해결 질문

- `MKGeoJSONFeature.properties`(Data?)를 앱이 실제로 어떤 API(JSONDecoder 등)로 다시 디코딩하는지 — 공식 문서 원문에 명시 없음.
- MapKit JS `importGeoJSON` 결과 item의 `data` 프로퍼티가 파싱된 객체인지 직렬화된 문자열인지 확인 필요.
- 두 플랫폼 모두 디코딩된 도형을 실제 지도에 추가하는 렌더링 코드(오버레이 추가, 스타일 렌더러) — 다운로드 샘플에서 확보 필요.
- MapKit/MapKit JS의 층(level) 전환 API 정확한 이름 — 미확인.
