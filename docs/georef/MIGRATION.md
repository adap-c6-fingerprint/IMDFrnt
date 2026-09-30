# 저장소 이관 기록

이관일: 2026-09-30

현재 작업 저장소는 [adap-c6-fingerprint/IMDFrnt](https://github.com/adap-c6-fingerprint/IMDFrnt)다. 이후 코드, 이슈, 백로그 및 진행 기록은 이 저장소를 사용한다.

## 이관한 작업

| 항목 | 새 저장소 상태 |
|---|---|
| 레거시 앱 | `develop`의 `b106845495045f2d48f1cbc9ee97f8837457514a` 보존 |
| 일반 평면 지도·보조 앵커 자동화 | `feature/anchor-map-automation`의 `ed8250b57cc51fb57573aa8caea8af72184a6f6c`가 기존 작업과 동일함을 확인 |
| 백로그·진행 문서 | 이전 문서 커밋 `e55a76d5d64644330d17691a89d02260a6d687e7`을 보존하고 `docs/#4-georef-backlog`에서 새 저장소 링크로 갱신 |
| 기존 이슈 및 PR 기록 | 새 저장소에 이슈 #1–#4와 과거 PR 기록 #5가 존재함을 확인 |
| 자동 georeference 백로그 | #6–#15를 새로 등록하고 담당자·라벨·선행 관계·완료 조건을 복원 |
| 상위 이슈 목록 | 새 저장소 #4에 백로그 체크리스트를 연결 |
| 이전 UX 개념 시안 | [archive/review-prototype.html](archive/review-prototype.html)에 원본 보존. 현재 제품 범위와의 차이는 [설명](archive/README.md)에 기록 |

앵커 보조 자동화 커밋은 README와 Swift 소스 9개 파일의 변경이다. 새 저장소의 동일 커밋 해시로 코드 보존을 확인했다. 이관 과정에서는 앱 코드를 수정하지 않았다. 과거 빌드·selftest 결과를 새 명세의 M0–M7 평가 통과로 간주하지 않는다.

## 이슈 대응표

번호는 이번 재등록에서도 유지되었다. 이후 참조는 아래 새 저장소 링크를 사용한다.

| 단계 | 이슈 |
|---|---|
| M0 | [#6](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/6) |
| M1 | [#7](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/7) |
| M2 | [#8](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/8) |
| M3 | [#9](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/9) |
| M4 | [#10](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/10) |
| M5 | [#11](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/11) |
| M6 | [#12](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/12) |
| M7 UI | [#13](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/13) |
| M7 IMDF | [#14](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/14) |
| M7 Raster | [#15](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/15) |

## 로컬 작업 경로

- 현재 저장소: `/Users/dd/Downloads/IMDFrnt`
- `origin`: `https://github.com/adap-c6-fingerprint/IMDFrnt.git`
- 이전 로컬 체크아웃의 `origin`도 새 주소로 변경했다.

## 유지하는 제품 범위

전체 건물 도면을 대상으로 한다. 출입구 대응·실내외 경로 연결과 부분 홀 배치는 제외한다. 모호한 후보는 방향키 또는 버튼으로 비교·확정하거나 보류할 수 있게 한다. 새 명세의 구현은 미착수이며 다음 작업은 #6이다.
