---
summary: IMDF 아카이브에 반드시 한 개 들어가는 manifest.json 객체. 버전·생성 시각·기본 언어를 기록
source: "[[src18. IMDF 아카이브 패키징 규격 조사 — .geojson 묶음에서 ZIP까지]]"
related:
  - "[[IMDF 아카이브]]"
  - "[[IMDF]]"
created: 2026-10-15 21:00
updated: 2026-10-15 21:00
core_keywords:
  - Manifest
---
# Manifest

## 요약

IMDF 아카이브의 관리 정보를 담는 `manifest.json`. 모든 전달물에 별도 파일로 포함해야 한다.

## 핵심 내용

| 필드 | 필수 | 내용 |
| --- | --- | --- |
| `version` | 필수 | 현재 `"1.0.0"`만 허용 |
| `created` | 필수 | 아카이브 패키징 시각(DATE-TIME), 패키징 시점 생성 권장 |
| `generated_by` | 선택 | 감사·문제 해결용 불투명 문자열 |
| `language` | 필수 | Venue 데이터의 기본 언어 태그(예: `en-US`, `ko-KR`) |
| `extensions` | 선택 | 사용한 IMDF 확장 식별자 배열 |

## 관련 링크

- [[IMDF 아카이브]] · [[IMDF]]

## 미해결 질문

- `created`의 시간대 표기 요건 (확인 필요).
