---
summary: "register.apple.com/resources/imdf/의 IMDF 공식 스펙 사이트 — 버전, GeoJSON/RFC 7946 준수, changelog, 확장 모델을 웹으로 조사"
source: "register.apple.com/resources/imdf/ (IMDF 공식 스펙 사이트), register.apple.com/resources/imdf/changelog/specification (변경 이력)"
created: "2026-08-05 17:10"
updated: "2026-08-05 17:10"
---
# IMDF 공식 스펙 사이트 자료 조사

## 수집 기준

- 수집일: 2026-08-05
- 목적: WWDC19 Session 245("Introducing the Indoor Maps Program") 이후 IMDF 규격이 실제로 어떻게 문서화·버전 관리되는지, 세션 내용과 현재 공식 스펙이 어떻게 이어지는지 확인.
- 관점: WWDC19 전사문 기반 가공 지식 문서(`Apple Indoor Maps Program과 IMDF 개요.md`)의 미해결 질문 — "2019년 이후 IMDF 스펙 버전 변화"에 대한 웹 근거 확보.

## 핵심 출처

- IMDF 공식 스펙 사이트  
  https://register.apple.com/resources/imdf/
- IMDF 스펙 changelog  
  https://register.apple.com/resources/imdf/changelog/specification
- IMDF Level 타입 레퍼런스(예시)  
  https://register.apple.com/resources/imdf/types/level
- IMDF Type Designators 레퍼런스  
  https://register.apple.com/resources/imdf/reference/type_designators
- Open Geospatial Consortium(OGC)의 IMDF 표준 페이지  
  https://www.ogc.org/standards/indoor-mapping-data-format/
- OGC IMDF 1.0.0 문서  
  https://docs.ogc.org/cs/20-094/index.html

## 스펙 사이트 개요 (register.apple.com/resources/imdf/)

- 현재 공식 버전은 **1.0.0**이며, 사이트 기준 최종 업데이트일은 **2021-10-19**로 확인된다.
- 사이트는 IMDF를 "실내 위치에 대한 일반화되고 포괄적인 모델을 제공하여 방향 설정, 내비게이션, 발견(discovery)을 위한 기초를 마련하는 규격"으로 설명한다.
- IMDF는 **RFC 7946(GeoJSON 표준)을 완전히 준수**하며, 경량이고 모바일 친화적이라 어떤 기기·OS·브라우저에서도 렌더링 가능하다고 명시한다.
- 공항, 쇼핑몰, 기차역처럼 서로 다른 성격의 대형 시설을 모델링하기 위한 상세 지침을 별도로 제공한다.
- **확장 모델(extension model)**을 제공해, 기관이나 산업이 기본 스펙에 없는 커스텀 피처·검증 규칙을 추가할 수 있게 한다. → WWDC19 세션에서는 다루지 않은 부분으로, 스펙이 세션 이후 확장성 축을 더했음을 시사한다.
- IMDF는 MapKit, Core Location과의 통합, 그리고 실내 측위 기술과 결합한 위치 기반 앱·웹 개발을 지원한다고 서술한다.

## 스펙 changelog — 버전 이력 (역순, 최신이 위)

changelog 페이지에는 개별 릴리스 날짜가 명시돼 있지 않고, 버전 순서와 각 버전의 변경 내용만 정리되어 있다.

- **1.0.0 (정식)**
  - manifest의 `language` 정의 갱신
  - address의 `province`를 선택 항목으로 완화
  - Apple 자체 지침(guidance) 추가
  - 새 카테고리 추가: 휠체어 접근 화장실, 기도실(prayer room), 손 소독 스테이션 등
  - 기존 "chapel" 카테고리 삭제 → 기도실 카테고리로 대체
  - manifest에 `origin` 속성 추가
- **1.0.0.rc.1**
  - IMDF 확장 기능(extension) 추가
  - 법적 이용약관 갱신
  - 새 카테고리 추가: 수하물 찾는 곳(baggage claim), 게이트 구역(gate area), 플랫폼(platform)
- **1.0.0.beta.3**
  - 정밀도(precision) 요구사항 갱신
  - manifest에 `generated_by` 항목 추가
- **1.0.0.beta.2**
  - 공항·쇼핑센터 지침 갱신
  - 대중교통 역사(transit station) 지침 신규 추가
  - opening(문) 타입에 `movablepartition`(이동식 파티션) 추가
  - PHONE 타입을 E.164 규격으로 변경
- **1.0.0.beta**
  - 공개 베타 릴리스
  - 라이선스 및 이용약관 추가
- **1.0.0.alpha**
  - Kiosk(키오스크) 피처 추가
  - "Zone"을 "Geofence"로 명칭 변경

**해석:** WWDC19(2019)는 alpha~beta 시기 전후의 IMDF를 소개했을 가능성이 높고, 세션에서 언급된 kiosk·zone(트리거 region) 개념이 changelog의 alpha 단계 변경 이력과 시기적으로 맞물린다. 정식 1.0.0까지 오면서 카테고리 세분화(기도실, 수하물 찾는 곳 등)와 확장 모델이 추가된 것이 세션 이후의 주요 변화로 보인다. 각 버전의 정확한 릴리스 연도는 changelog 페이지에 날짜가 없어 **확인 필요**로 남는다.

## 관련 레퍼런스 페이지

- `types/level` — level 피처의 필드 스펙(2019 세션에서 언급된 UUID, ordinal, building 참조 등 필드의 공식 정의 위치)
- `reference/type_designators` — IMDF에서 쓰는 타입 코드 체계 레퍼런스

## 미해결 질문

- changelog 각 버전의 실제 릴리스 연월일. (register.apple.com 로그인 후 페이지에서 추가 확인 필요할 수 있음)
- 확장 모델(extension)의 구체적 문법과 등록 절차.
