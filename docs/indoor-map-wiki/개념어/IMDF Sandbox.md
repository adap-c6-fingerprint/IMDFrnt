---
summary: IMDF를 브라우저에서 시각화·검색·검증하고 간단히 편집하는 Apple의 로컬 처리 도구
source: "[[Apple Indoor Maps Program과 IMDF 개요]], WWDC19 Session 245"
related:
  - "[[IMDF]]"
  - "[[Indoor Maps Program]]"
created: 2026-08-05 16:40
updated: 2026-08-05 16:40
core_keywords:
  - IMDF Sandbox
---
# IMDF Sandbox

## 요약

IMDF Sandbox는 IMDF 아카이브를 브라우저에서 시각화·검색하고, 검증 결과를 관찰하며, 간단한 편집을 하는 도구다. Indoor Maps Program에 IMDF를 업로드할 때 쓰는 **것과 동일한 검증 엔진**을 사용하되, 그 결과를 사람이 이해하기 쉽게 해석·시각화한다.

## 핵심 내용

- **UI:** 지도 렌더링, 레벨 선택기, 방위 나침반, 좌측 디렉터리(업체·서비스·건물·레벨 탐색), 상단 검색 바, Home의 검증 에러·경고 링크.
- **에러 vs 경고:** 에러는 파일 수락을 막는다(예: 유닛 겹침 — 겹친 영역 주황색 표시, 참조 레벨 밖 유닛). 프로그램 수락을 위해 에러는 0이어야 한다. 경고는 여러 use case에 걸쳐 발생할 수 있는 조건으로, 규격·업무를 이해한 사람이 중요도를 판단한다.
- **편집:** 겹침 영역을 한쪽 유닛에서 제거하는 등 가벼운 수정을 지원한다.
- **로컬 처리:** 모든 작업이 브라우저 로컬에서 이뤄지고 Apple과 공유되지 않는다. 변경 유지는 Download IMDF로 저장해야 한다.
- **접근성:** Indoor Maps Program 건물주가 아니어도 Apple ID만 있으면 누구나 사용 가능하다.

## 관련 링크

- [[IMDF]] — Sandbox가 다루는 대상 포맷
- [[Indoor Maps Program]] — 동일 검증 엔진을 쓰는 상위 프로그램

## 미해결 질문

- Sandbox가 지원하는 편집 범위의 한계는 어디까지인가.
