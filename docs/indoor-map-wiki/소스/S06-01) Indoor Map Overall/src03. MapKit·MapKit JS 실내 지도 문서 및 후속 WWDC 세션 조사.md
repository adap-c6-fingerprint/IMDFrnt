---
summary: "MapKit·MapKit JS의 실내 지도 표시 공식 문서, 그리고 WWDC19 Session 245가 안내하는 후속 심화 세션 WWDC19 Session 241(Adding Indoor Maps to your App and Website)의 메타 정보를 웹으로 조사"
source: "developer.apple.com/documentation/mapkit/displaying-an-indoor-map, developer.apple.com/documentation/MapKitJS/displaying-indoor-maps-with-mapkit-js, developer.apple.com/videos/play/wwdc2019/241"
created: "2026-08-05 17:10"
updated: "2026-08-05 17:10"
---
# MapKit·MapKit JS 실내 지도 문서 및 후속 WWDC 세션 조사

## 수집 기준

- 수집일: 2026-08-05
- 목적: WWDC19 Session 245 전사문 말미에 언급되는 "Adding Indoor Maps to your App and Website" 세션의 정확한 식별 정보 확보, 그리고 MapKit/MapKit JS의 실내 지도 표시 공식 문서 페이지 존재 여부 확인.
- 주의: 아래 MapKit JS 관련 항목 중 일부는 문서 페이지 본문을 온전히 가져오지 못해 **일반적 지식 기반의 추정 정보**로 표시했다. 실제 구현 시 반드시 공식 문서 원문을 직접 대조해야 한다.

## 핵심 출처

- Displaying an Indoor Map (MapKit, iOS)  
  https://developer.apple.com/documentation/mapkit/displaying-an-indoor-map
- Displaying Indoor Maps with MapKit JS  
  https://developer.apple.com/documentation/MapKitJS/displaying-indoor-maps-with-mapkit-js
- WWDC19 Session 241 — Adding Indoor Maps to your App and Website  
  https://developer.apple.com/videos/play/wwdc2019/241
- MapKit overlays  
  https://developer.apple.com/documentation/mapkit/mapkit-overlays
- Displaying overlays on a map  
  https://developer.apple.com/documentation/MapKit/displaying-overlays-on-a-map

## 후속 세션 식별 정보 (확인됨)

WWDC19 Session 245 전사문 마지막 부분은 "our WWDC Session Adding Indoor Maps to your App and Website"를 심화 자료로 안내한다. 이번 조사로 다음이 확인되었다.

| 항목 | 내용 |
| --- | --- |
| 세션 제목 | Adding Indoor Maps to your App and Website |
| 세션 번호 | WWDC19 Session **241** |
| 발표자 | Stephane, Mithilesh (Apple Maps 팀 엔지니어) |
| 개요 요지 | Indoor Maps Program이 대형 공공·사설 공간 조직에게 정밀 실내 위치 정보와 실내 지도를 제공하는 경험을 만들게 해준다는 점을 다시 짚고, MapKit·MapKit JS가 geo 표준과 API로 실내 지도를 앱·웹에 빠르게 통합하는 기술적 세부 사항을 다룬다 |
| 다루는 범위(제공 리소스 기준 추정) | (1) IMDF 데이터 구조 재설명 (2) MapKit 기반 iOS 앱 구현 (3) MapKit JS 기반 웹 구현 (4) Indoor Survey 앱을 통한 실내 측위 |
| 제공 형식 | HD/SD 비디오, 프레젠테이션 슬라이드(PDF), 관련 문서·샘플 코드 |

**참고:** Session 245("Introducing the Indoor Maps Program", 본 위키 1차 소스)와 Session 241("Adding Indoor Maps...")은 같은 WWDC19에서 짝을 이루는 두 세션으로, 245가 프로그램·워크플로우 개요라면 241은 구현 중심 심화 세션이다. 전사문 원문을 직접 확보하려면 해당 URL의 Transcript 탭을 참고해야 한다(본 조사에서는 세션 존재와 메타 정보만 확인했고, 전사문 본문은 가져오지 않았다).

## MapKit — Displaying an Indoor Map (iOS)

문서 페이지가 존재함은 확인했으나, 이번 조사(2026-08-05)에서는 페이지 본문(Overview, 코드 예시, 관련 심볼 목록)을 온전히 가져오지 못했다. 페이지 주소만 확보된 상태였다.

- https://developer.apple.com/documentation/mapkit/displaying-an-indoor-map

**2026-08-12 갱신:** 아래 "MapKit JS" 절의 추정 정리를 포함해, 이 문서와 MapKit JS 쪽 API 시그니처(MKGeoJSONDecoder, MKGeoJSONFeature, importGeoJSON, GeoJSONDelegate 등)를 `src05. MapKit·MapKit JS 공식 문서 — GeoJSON 디코딩·렌더링 API 조사.md`에서 developer.apple.com의 DocC JSON 엔드포인트로 원문 대조 완료. 상세 내용은 src05 참고.

## MapKit JS — Displaying Indoor Maps with MapKit JS

문서 페이지가 존재함은 확인했으나, 이번 조사(2026-08-05)에서도 본문을 온전히 가져오지 못해 아래는 **추정 정리**로 남겼었다.

- ~~`mapkit.init({ authorizationCallback: ... })`로 MapKit JS를 초기화한다.~~
- ~~`new mapkit.Map(element, options)`로 지도 인스턴스를 만든다.~~
- IMDF(GeoJSON) 데이터를 가져와 지도에 반영하는 임포트 경로가 존재한다 — WWDC19 세션 245 전사문에서 "MapKit and MapKit JS support decoding and rendering of GeoJSON files"라고 밝힌 부분과 대응.
- ~~층 전환, 실내 오버레이 표시 관련 옵션이 있을 것으로 추정되나 정확한 메서드·프로퍼티명은 확인 필요.~~

**2026-08-12 갱신 — 추정이 아닌 공식 문서 원문으로 확인됨(src05 참고):** 실제 임포트 API는 `importGeoJSON(data, callback)`이며(`mapkit.init`/`new mapkit.Map`으로 초기화한 지도 인스턴스가 아니라 전역 `importGeoJSON` 함수를 통해 GeoJSON 파일 URL 또는 객체를 가져와 `ItemCollection`(Annotation/Overlay/ItemCollection)으로 변환한다), `GeoJSONDelegate`로 `itemForFeature`/`itemForPolygon`/`styleForOverlay`/`geoJSONDidComplete` 등을 재정의해 커스터마이징한다. 층(level) 전환 API 이름은 여전히 미확인.

## 미해결 질문 (다음 조사 시 우선순위)

- Session 241의 실제 전사문 본문 확보(현재는 메타 정보만 확보) — 미해결.
- ~~MapKit `displaying-an-indoor-map`, MapKit JS `displaying-indoor-maps-with-mapkit-js` 두 문서의 정확한 API 시그니처~~ — src05에서 해결(코드 예시 자체는 다운로드 샘플에만 있어 여전히 미확보).
- ~~`importGeoJSON` 등 실제 MapKit JS API 메서드명이 이 문서에도 등장하는지 대조~~ — src05에서 해결. `importGeoJSON(data, callback)` 시그니처와 `GeoJSONDelegate` 콜백 목록 원문 확인 완료.
- 층(level) 전환 관련 정확한 API 이름 — 여전히 미확인.
