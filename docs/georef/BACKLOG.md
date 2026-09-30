# 자동 georeference 백로그

작성일: 2026-09-30

관련 상위 이슈: [#4 — 지도에 도면 정렬하여 Footprint 찍기](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/4)

현재 저장소: [adap-c6-fingerprint/IMDFrnt](https://github.com/adap-c6-fingerprint/IMDFrnt). 이전 작업의 보존과 이슈 재등록 내역은 [이관 기록](MIGRATION.md)에 남겼다.

사용자가 제공한 `AUTO_GEOREF_TASK.md`를 기반으로, 이후 확정한 제품 범위를 적용한 구현 계획이다. 각 이슈에 작업 목록과 측정 가능한 완료 조건을 기록했다. 선행 단계의 완료 조건을 통과한 뒤 다음 단계에 착수한다.

## 확정한 범위

- 대상은 건물 전체 도면이다. 부분 홀 도면의 위치 추정과 partial sliding은 이번 구현에서 제외한다.
- 출입구 대응과 실내·실외 경로 연결은 클라이언트가 담당한다. 출입구 매칭, 출입구 기반 도로 점수, juso 출입구 파일 로더는 이번 릴리스의 필수 항목에서 제외한다.
- 일반 평면 지도에서 주소 또는 대략 위치를 입력하고, 주변 건물 후보를 수집한다. 검색 결과의 대표 좌표를 ControlPoint로 사용하지 않는다.
- 벡터 도면은 알려진 미터 축척을 고정한다. 모르는 단위를 임의로 미터로 간주하지 않는다.
- 매칭은 독립 패키지로 구현한다. 앱 연동은 Swift 6와 async/await를 사용한다.
- 지도 footprint는 후보 정합과 QA에 사용한다. IMDF Venue/Footprint 기하는 변환된 도면에서 생성한다.

## 사용자 흐름

1. 주소 또는 대략 위치를 입력한다.
2. 전체 도면 외곽과 주변 건물을 자동으로 비교한다.
3. 모든 게이트를 통과하면 `AUTO_ACCEPT` 결과를 표시한다.
4. 건물 또는 방향이 모호하면 `NEEDS_REVIEW`로 최대 4개 후보를 보여준다. 필요한 경우에만 건물 선택과 방향 선택을 나눈다.
5. 후보 영역에 포커스가 있을 때 `←`/`→`로 후보를 전환하고 Return으로 확정한다. 같은 동작의 화면 버튼도 제공한다.
6. Escape 또는 ‘판단하기 어려움’은 보류로 남긴다. ‘해당 없음’은 거부로 처리한다.

후보를 바꿔도 북쪽, 지도 카메라와 축척을 유지한다. 방향키는 생성된 가설을 순회하며 임의 회전을 만들지 않는다. 미리보기는 저장하지 않고, 최종 선택만 한 번에 적용·실행 취소한다. 자동 검토 흐름에서는 위경도 직접 입력을 요구하지 않는다.

## 구현 순서

| 단계 | 이슈 | 선행 | 핵심 완료 조건 |
|---|---|---|---|
| M0 | [#6 패키지·CRS·Provider·캐시](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/6) | 없음 | 좌표 왕복 < 1 mm, Bessel 정의 검증, 결정성·캐시 정책 |
| M1 | [#7 입력 어댑터·합성 fixture](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/7) | #6 | 동일 seed 해시, 전체 도면 20종 외곽 면적 오차 ≤ 2% |
| M2 | [#8 다중 가설·rigid/eave 정합](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/8) | #7 | 가설 포함률 ≥ 99%, 비대칭 성공률 ≥ 95%, median 오차 ≤ 1.5 m |
| M3 | [#9 모호성 게이트·검토 CLI](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/9) | #8 | 무단서 대칭 골든 100% 검토, 자동 수락 오답 ≤ 1% |
| M4 | [#10 방위·주소·인접 건물 단서](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/10) | #9 | 독립 방위 단서가 있는 대칭 사례 자동 수락 ≥ 90%, 오답 ≤ 1% |
| M5 | [#11 실제 Provider·provenance](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/11) | #10 | 출처·라이선스·snapshot 기록 100%, 후보 포함률 ≥ 99% |
| M6 | [#12 실제 데이터 벤치마크](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/12) | #11 | 정확도·모호성 지표와 표본 수, 후보 ≤ 50개 p95 ≤ 10 s |
| M7 UI | [#13 S7·방향키 검토 UX](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/13) | #12 | 2/4방향 후보 검토, 입력 충돌 방지, 확정·실행 취소 |
| M7 IMDF | [#14 extension·도면 기하·sidecar](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/14) | #13 | validator 통과, 좌표 7자리, 도면 유래 기하 |
| M7 Raster | [#15 래스터·단위 미확정 입력](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/15) | #14 | 축척 bound·불확실성 기록, IMDF 출력 검증 |

M7은 앱 통합, IMDF 출력, 입력 확장을 각각 검토할 수 있도록 세 이슈로 나눴다. 모든 이슈에 `enhancement` 라벨과 `logichoon-redo` 담당자를 지정했다.

## 정확도와 수락 기준

아래 수치는 구현 후 측정할 목표이며 현재 실측 결과가 아니다.

| 지표 | 목표 |
|---|---|
| 비대칭 합성 사례 자동 성공률 | max-corner error ≤ 5 m인 AUTO_ACCEPT ≥ 95% |
| 자동 수락 오답률 | AUTO_ACCEPT 중 max-corner error > 5 m 비율 ≤ 1% |
| 모호성 탐지 | recall ≥ 95%, precision ≥ 80% |
| 처리 시간 | 네트워크 제외, 후보 ≤ 50개, p95 ≤ 10 s |
| 결정성 | 같은 입력·provider snapshot·확정된 provenance 시각 계약에서 동일 바이트 |

합성 정답 변환에 대한 오차, provider 간 기하 차이, 실제 지상 위치의 절대 오차를 구분해 보고한다. 작은 형상 RMS나 높은 IoU만으로 실제 위치 ±5 m 충족을 선언하지 않는다. confidence는 보정된 확률로 표시하지 않는다.

## 명세와 달라진 항목

- 부분 도면은 제품 입력에서 제외한다. 원 명세의 3홀 중 끝 홀 golden 및 partial UX는 이번 릴리스의 완료 조건으로 사용하지 않는다.
- 출입구 기반 단서는 제외한다. 원 명세의 출입구 golden과 M4 수락 기준을 독립 방위 단서 사례로 대체한다. 단서가 없으면 대칭 후보를 검토로 보낸다.
- 원 명세의 ‘골든 5종’ 표기와 G1–G6 목록을 정리해, 이번 범위에 맞는 6종을 #7에 명시했다.
- 독립 패키지의 확정 rigid transform은 projected CRS 경로로 직접 적용한다. 생성한 ControlPoint를 기존 자유 어파인으로 다시 fit해 확정 변환을 바꾸지 않는다.
- 전체 결과는 기본적으로 ZIP 밖 `georef.json`에 기록한다. ZIP 내부 포함 요구가 생기면 사용자와 확인한다.

## 해당 단계에서 확정할 사항

- **M0:** 실제 실행 시각 `created`와 출력 바이트 결정성이 충돌한다. 시각의 입력·분리 정책을 구현 전에 사용자와 확정한다.
- **M5:** 실제 Provider의 응답, 인증키, 한도와 라이선스를 공식 자료로 확인한다. 응답·정책이 명세와 다르거나 라이선스 해석이 필요하면 추측하지 않고 사용자에게 확인한다.
- **M6:** 사용 가능한 독립 비교 데이터와 표본 수를 기록한다. 확보하지 못한 지표는 미측정으로 남긴다.
- **M7:** 사용 가능한 IMDF validator의 이름·버전을 기록한다. extension 거부와 환경 차이는 사용자에게 확인한다.

## 진행 관리

저장소 루트 [PROGRESS.md](../../PROGRESS.md)에 날짜, 완료 항목, 실제 지표와 명세 차이를 기록한다. 구현은 이슈별 `<type>/#<이슈번호>-<작업내용>` 브랜치에서 진행한다. 현재 상태는 전 단계 미착수이며 다음 작업은 #6이다.
