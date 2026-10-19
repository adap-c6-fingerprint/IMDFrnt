---
summary: IMDF 데이터를 전달하는 단위. manifest.json과 Feature Type별 .geojson 파일을 ZIP으로 묶은 것
source: "[[src18. IMDF 아카이브 패키징 규격 조사 — .geojson 묶음에서 ZIP까지]]"
related:
  - "[[IMDF]]"
  - "[[Manifest]]"
  - "[[GeoJSON]]"
  - "[[Feature Type]]"
created: 2026-10-15 21:00
updated: 2026-10-15 21:00
core_keywords:
  - IMDF 아카이브
---
# IMDF 아카이브

## 요약

IMDF 데이터의 전달 단위다. 표준은 ZIP 압축 파일(확장자 `.zip`)로 전달하도록 규정하며, 안에 `manifest.json`과 Feature Type별 `.geojson` 파일을 둔다.

## 핵심 내용

- 필수: `manifest.json`, `address.geojson`, `venue.geojson`. 나머지 14종은 선택.
- 각 `.geojson`은 동질적인 FeatureCollection이다.
- 문자열은 UTF-8.
- 패키징 절차와 IM-DFrnt 구현 상태: [[14) .geojson 파일을 모아 IMDF 아카이브로 패키징하는 과정]]

## 관련 링크

- [[IMDF]] · [[Manifest]] · [[GeoJSON]] · [[Feature Type]]

## 미해결 질문

- `.imdf` 확장자의 실제 사용처 (확인 필요).
