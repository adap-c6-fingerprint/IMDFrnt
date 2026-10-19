---
summary: GeoJSON과 IMDF의 좌표가 놓이는 측지계. RFC 7946이 WGS 84 / urn:ogc:def:crs:OGC::CRS84, 십진도, 경도-위도 순서로 고정했으며 대체 좌표계 지정 기능은 제거됐다. EPSG:4326은 축 순서가 반대라 정확한 식별자가 아니다
source: "[[11) 실내 지도의 위치 정확도 — ±5m는 어디서 오는가]], [[src16. 실내 지도 위치 정확도 허용 오차 기준 조사]], RFC 7946 §4, OGC IMDF 1.0.0"
related:
  - "[[좌표 정밀도]]"
  - "[[수평 위치 정확도]]"
  - "[[GeoJSON]]"
created: "2026-08-30 16:10"
updated: "2026-08-30 16:10"
core_keywords:
  - WGS 84
---
# WGS 84

## 요약

WGS 84(World Geodetic System 1984)는 GPS가 쓰는 전 지구 측지계이며, **GeoJSON과 IMDF의 좌표가 놓이는 좌표계**다. IMDF 스펙 본문에는 이 이름이 한 번도 나오지 않는데, 좌표계를 직접 정하지 않고 RFC 7946에서 **상속**하기 때문이다.

## 핵심 내용

- IMDF는 좌표계를 스스로 규정하지 않는다. IMDF 1.0.0 전 페이지에 `WGS`·`EPSG`·`4326`·`coordinate reference system` 문자열이 **한 번도 등장하지 않는다.**
- 상속 경로: IMDF가 "A Feature object represents ... as an **RFC 7946 compliant** GeoJSON object"라고 선언하고, RFC 7946 §4가 좌표계를 못 박는다.
- RFC 7946 §4 원문: "The coordinate reference system for all GeoJSON coordinates is a geographic coordinate reference system, using the **World Geodetic System 1984 (WGS 84)** datum, with **longitude and latitude units of decimal degrees**. This is equivalent to the coordinate reference system identified by the OGC URN **`urn:ogc:def:crs:OGC::CRS84`**."
- 선택적 세 번째 성분은 WGS 84 기준 타원체 위·아래의 **미터 단위 높이**다.

### 실무에서 어긋나기 쉬운 두 가지

1. **`EPSG:4326`이라고 쓰면 축 순서가 반대다.** EPSG:4326은 축 순서가 **위도-경도**로 정의돼 있는데 GeoJSON은 **경도-위도** 순이다. 값이 같아 보여도 식별자로는 정확하지 않다. 올바른 식별자는 `urn:ogc:def:crs:OGC::CRS84`다.
2. **파일에 `crs` 멤버를 넣으면 안 된다.** 2008년 GeoJSON 규격에는 대체 좌표계를 지정하는 기능이 있었지만 RFC 7946에서 제거됐다 — "the use of alternative coordinate reference systems was specified in [GJ2008], but it has been removed from [RFC 7946]."

## 관련 링크

- [[좌표 정밀도]] — 이 좌표를 몇 자리까지 기록할 것인가
- [[수평 위치 정확도]] — 이 좌표가 실제 지상 위치와 얼마나 어긋나도 되는가
- [[11) 실내 지도의 위치 정확도 — ±5m는 어디서 오는가]] — 전체 맥락

## 미해결 질문

- 없음.
