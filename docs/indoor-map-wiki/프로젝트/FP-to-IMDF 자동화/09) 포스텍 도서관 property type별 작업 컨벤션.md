# 포스텍 도서관 — property type별 작업 컨벤션

- 대상: `포스텍 도서관_261017_1651.imdfrnt`(앱 지원 폴더, 레포 밖) 2층. 저장 시각 2026-10-19 12:34
- 근거: 프로젝트 파일에 실제로 들어간 값(휴지통 25개 제외) + IMDFrnt 레포 `PropertySchema.swift`·`PROGRESS.md`. 2026-10-19 확인
- 아래 "규칙"은 지금까지 입력된 값에서 읽어 낸 관행이다. 정해진 규칙과 다르면 고쳐 주세요.

## 공통

| 항목 | 규칙 |
|---|---|
| `id` | 앱이 UUID 자동 부여. 직접 넣지 않음 |
| 이름표 | `type-NNN`(예: `unit-063`). 번호는 계속 증가, 지운 번호 재사용 안 함 |
| `level_id` | 지금 층으로 자동 지정(우측 패널에서 편집 불가) |
| `display_point` | 편집 불가(자동) |
| `alt_name`·`restriction`·`accessibility` 등 | 항상 null로 둠 |
| `name` | **ko만 입력, en은 빈칸**. 빈 en은 내보낼 때 빠짐 |
| 같은 이름 여러 개 | 그대로 허용(엘리베이터 ×2) 또는 뒤에 번호(`EPS 1/2/3`, `공조실`·`공조실 2`) |
| 위치 구분 | 이름 앞에 방향(`서편 사무실 통로`, `서편 탕비실`) |
| 원본 직접 수정 | 앱 종료 → `.before-<작업>-YYMMDD.imdfrnt.bak` 백업 → 처리 → 다시 열어 확인 |

## unit (101개)

- 도형: 면 단위로 저장. **unit끼리 겹침 0** 유지, 폭 0.1 미만 빈틈은 맞닿은 길이가 가장 긴 이웃 unit에 흡수
- 벽을 `structure` unit으로 일괄 생성하지 않음(10-18에 만든 176개는 사용자 지시로 삭제)
- category 칸은 최근 고른 값이 위로 옴(10-19 기능)

| category | 개수 | 넣는 공간 | 이름 |
|---|---:|---|---|
| `nonpublic` | 19 | 직원 사무실·처장실·직원 회의실, 공조실·EPS, 청소도구실·창고, 비공개 학위논문실, 사무실 안 계단 | 넣음 (3개 빈칸) |
| `room` | 6 | 이용자가 들어가는 작은 방(외국인지원센터, 상담실, POSTECH1986 Zone 등) | 넣음 |
| `walkway` | 9 | 복도·통로(사무실 안 통로 포함) | 큰 복도는 빈칸, 사무실 통로만 이름 |
| `walkway.island` | 1 | 복도 안 섬 | 빈칸 |
| `column` | 11 | 기둥(넓이 약 23으로 거의 같음) | 빈칸 |
| `structure` | 3 | 벽 | 빈칸 |
| `stairs` / `elevator` | 2 / 2 | 계단 / 엘리베이터 | `2층 계단`, `엘리베이터` |
| `lobby`·`lounge`·`terrace`·`mothersroom`·`library` | 각 1 | 메인 로비, 라운지, 테라스, 수유실, DVD존 | 넣음 |
| `storage` | 1 | 서편 탕비실 | 넣음 |
| `unspecified` | 1 | 아직 정하지 못한 곳 | 빈칸 |
| (null) | 41 | **미태깅** | — |

- 확인 필요: 탕비실은 `storage`인데 청소도구실·정리용품창고는 `nonpublic`이다. 직원 전용 창고류를 어느 쪽으로 통일할지 정해야 한다.

## fixture (33개)

- 도형: 면 단위 또는 선 단위(도면 개체를 골라 하나로 저장, 10-19 추가). `name`은 모두 비워 둠

| category | 개수 | 넣는 것 |
|---|---:|---|
| `furniture` | 18 | 서가·테이블 등 가구 덩어리(크기 제각각) |
| `equipment` | 9 | 같은 모양 반복되는 장비(넓이 약 17.5로 동일) |
| `desk` | 1 | 큰 데스크 |
| `obstruction` | 1 | 작은 장애물 |
| (null) | 4 | **미태깅** (fixture-009·011·017·018) |

## opening (28개)

- 도형: **선분 하나(꼭짓점 2개)**로 문 자리를 그음. 다른 레이어보다 먼저 만드는 선행 단계
- 속성은 28개 모두 null — **category(문 종류) 아직 미입력**

## level · footprint · building

| type | 규칙 |
|---|---|
| level | 층당 1개. 층 이름(`2층`)·`ordinal`(2)은 **건물·층 관리**에서 넣음 — feature 속성 칸은 현재 모두 null |
| footprint | 1개, 속성 모두 null |
| building | 1개, `category: unspecified`, 나머지 null |
| address·occupant·manifest | 레이어 없이 좌측 목록 **'정보 입력'** 창에서 넣음(10-19 추가). 이 프로젝트엔 아직 없음 |
| section | 면 단위 `unit 모양 기준`으로 unit과 같은 모양으로 저장(10-19 추가). 이 프로젝트엔 아직 없음 |

## 남은 일

- unit category null 41개, fixture null 4개, opening category 28개 입력
- level 속성(`name`·`ordinal`·`category`)이 내보낼 때 층 정보에서 채워지는지 확인 필요
