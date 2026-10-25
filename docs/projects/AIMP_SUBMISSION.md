# AIMP 제출용 편집 (#79 / IMD-68)

## 사용법

- Footprint 카드를 펼쳐 **복제**를 누르면 모양·속성이 같은 새 feature가 생긴다. ID와 일련번호는 새로 발급한다. 복제본의 category를 aerial로 바꿔 ground와 별도로 관리할 수 있다.
- **Footprint를 기준층 Level 외곽에 맞추기**는 선택한 Footprint의 외곽을 ordinal 0 층의 Level로 교체하고 category를 ground로 설정한다. 구멍과 MultiPolygon, 층별 이동·회전·축척을 반영한다. 일회성 복사이며 이후 Level 편집과 자동 동기화하지 않는다. ordinal 0 층이 없거나 사용할 외곽·좌표 변환이 없으면 비활성화 사유를 표시한다.
- 기준층의 ordinal은 **IMDF로 내보내는 값**이다. 직접 작성한 Level의 명시적 `ordinal`을 먼저 읽고, 비어 있을 때만 건물·층 관리의 값을 쓴다. 예를 들어 층 관리 값이 1이고 Level 속성이 0이면 기준층이다. 아직 저장하지 않은 편집도 반영한다. 가져온 GeoJSON은 원본 ordinal을 따르며, 값이 없다고 임의로 0을 붙이지 않는다. 서로 다른 층이 ordinal 0이면 선택을 강요하지 않고 중복 사유를 표시한다. 사용자 프로젝트의 기존 ordinal 값 자체를 자동으로 바꾸지는 않는다.
- Building 정보 입력창에서 display point **찍기/다시 찍기**를 누르면 시트가 닫히고 도면에서 클릭할 수 있다. **삭제**로 제거하고 캔버스 상단 **취소**로 입력을 종료한다. 기존 전역 Building/Venue는 건물·층 관리에서도 같은 동작을 지원한다.
- Venue 표시점은 실제 다각형 내부만 허용한다. 구멍과 서로 떨어진 다각형 사이의 빈 공간은 거부한다. Building 표시점은 Footprint 내부를 사용한다.
- Venue hours는 요일별 **휴무 / 24시간 / 시간 지정**으로 입력한다. 시간 구간을 여러 개 추가할 수 있으며 시·분을 숫자로 입력한다. **운영시간 적용**으로 반영한다. 미설정(null)과 휴무(off)는 다르다.
- 종료가 시작보다 이르면 다음 날 종료로 해석한다. 다음 요일의 휴무 규칙이 야간 시간을 덮어쓰지 않게 저장할 때 날짜별 구간으로 나누고 중복 구간을 합친다. 예: 토요일 22:00–02:00 → `Sa 22:00-24:00; Su 00:00-02:00`.
- 공휴일·날짜·계절·일출/일몰 등은 **고급 OSM 규칙 입력**에서 원문 문자열을 사용할 수 있다. 요일별로 표현할 수 없는 기존 규칙은 고급 모드에서 보존하며 자동 축약하지 않는다. 전체 OSM 문법 검증기는 내장하지 않으므로 고급 문자열의 유효성은 외부 검사로 확인한다.

## 기준

- [IMDF Venue](https://docs.ogc.org/cs/20-094/Venue/index.html)
- [IMDF HOURS](https://docs.ogc.org/cs/20-094/Reference/index.html#hours): OSM opening_hours 형식 문자열. 실제 공지된 정규 운영시간을 입력한다.
- [OSM opening_hours](https://wiki.openstreetmap.org/wiki/Key:opening_hours): 분할 시간, 휴무, 24시간, 자정 넘김 및 고급 문법.

## 검증 및 리뷰 범위

`--footprint-selftest`에 #79 회귀 검사를 연결했다. 새 ID 발급·원본 보존, 실제 다각형 내부 및 구멍 거부, 표시점 삭제/Undo, Footprint 외곽 복사/Undo, ordinal 0 부재, 운영시간 문자열/프로젝트 저장 왕복, 가져온 전역 Building, 다른 층의 정렬 좌표와 IMDF 내보내기를 검사한다.

영향도: **L**. 공통 표시점 판정과 IMDF HOURS 필드의 해석이 바뀌므로 Building/Venue/Footprint 및 저장·내보내기 회귀를 함께 확인한다. #78의 공통 메타데이터와 프로젝트 v7 지원을 통합했으며, Building 표시점은 층별 FeatureGroup 대신 전역 GeoJSON properties에 저장한다. 이전 프로젝트의 휴지통·복구용 메타데이터를 보존한다. AI 검토는 사람의 코드리뷰·승인을 대체하지 않는다. 사용자 지시로 이 단계에서는 로컬 통합·커밋까지만 진행하며 PR 생성·push·원격 merge는 하지 않는다.

AIMP 실제 업로드·승인 및 네이티브 UI 수동 조작은 별도 검증이다. 자체 검사 통과를 AIMP 승인으로 표시하지 않는다.

2026-10-25 로컬 검증: Xcode 툴체인 Debug 빌드 성공, `--footprint-selftest` 83/83, `--building-selftest` 61/61, `--project-selftest` 24/24, 기존 `--selftest` ALL PASS. 외곽 일치는 다른 층에서 이동·회전·축척이 적용된 상태로 복사한 뒤 실제 IMDF 아카이브의 Level/Footprint 좌표를 1e-10도 허용오차로 비교했다.

위 수치는 v7 통합 전 #79 단독 변경의 검사 기록이다. 통합 후에는 #78의 엄격한 공통 내보내기 검증을 그대로 적용하며, 합성 fixture도 명시적 Building 참조·Unit coverage·Venue 범위를 갖추도록 보완했다. `--footprint-selftest --submission-test-project <파일>`로 실제 v7 프로젝트의 전체 모델 왕복·앱 열기·전역 메타데이터/휴지통/이전 원본 보존과 원본 바이트 불변을 추가 확인한다.

v7 통합 검증(2026-10-25): Release 빌드·ad-hoc 서명 검증 성공. `run-self-tests.sh`의 8/8 모드 통과(Self ALL PASS, Building 61/61, Project 24/24, Document open 23/23, Routing 164/164, Drawing Loading 56/56, Footprint 84/84, IMDF Compliance 50/50). 첨부된 실제 v7 프로젝트를 지정한 추가 Debug 검사는 87/87 PASS이며 원본 SHA-256은 검사 전후 동일하다. 별도 실행 앱은 `IM-DFrnt/.build/AIMP-v7/IM-DFrnt.app`에 생성해 기존 앱을 덮어쓰지 않는다. 실제 AIMP 업로드와 UI 수동 조작은 여전히 별도 확인 대상이다.

ordinal 기준층 검색 수정 검증: Release 빌드·서명 및 전체 8/8 모드 통과, Footprint 90/90·IMDF Compliance 50/50. 실제 프로젝트의 검사 전용 복사본을 지정한 검사는 96/96 PASS(기준층 탐색·버튼 활성화·외곽 복사 계산 포함). 열린 앱과 원본 프로젝트는 수정하지 않았다. 새 실행 앱은 `IM-DFrnt/.build/AIMP-v7-ordinal-fix/IM-DFrnt.app`에 생성했다.
