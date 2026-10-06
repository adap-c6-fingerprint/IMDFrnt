# 길찾기 노드 편집

브랜치: `feat/routing-node-editor`. 기존 IMDF 태깅 앱의 `CanvasView`, 도면 좌표 변환, 확대·이동, 실행취소, `.imdfrnt` 저장·자동 저장을 재사용한다. 길찾기 그래프는 IMDF 태깅 결과와 별도로 보관한다.

## 사용 순서

1. `도면 열기…`에서 SVG·PNG·JPG 원본을 연다. 왼쪽 `길찾기 노드 편집` 또는 ⌘⇧N으로 들어간다.
2. `클라이언트 층 목록 가져오기…`에서 클라이언트가 사용하는 `level.geojson` 또는 `IndoorMapDocument` JSON을 선택한다. 층별 ID와 번호를 맞춘다. 직접 추가·이름 편집·층 번호 편집도 가능하다. 한 건물의 층 목록을 사용한다.
3. 각 층을 선택하고 `이 층 도면 불러오기…`로 해당 층의 원본을 연다. 새 층에 다른 층 도면을 자동 복사하지 않는다. 이미지는 프로젝트에 내장되므로 원본 파일을 옮겨도 작업을 다시 열 수 있다.
4. `노드 찍기`에서 원하는 위치를 클릭한다. 기존 핀 클릭은 선택, 핀 드래그는 위치 이동이다. 이름·카테고리는 바로 반영된다. 메타데이터는 JSON 객체로 입력하고 `메타데이터 적용`을 누른다.
5. `노드 연결`에서 두 핀을 차례로 클릭한다. 다른 층으로 전환하면 시작 핀을 유지한다. 층간 연결은 양쪽 모두 같은 종류의 계단 또는 엘리베이터여야 한다. 계단은 휠체어 접근 불가로 기록한다. 연결은 양방향이다.
6. `선택·이동`에서 핀 또는 연결선을 선택한 뒤 Delete로 지운다. 노드 삭제는 연결도 함께 지운다. 연결 삭제는 노드를 보존한다. ⌘Z / ⌘⇧Z로 되돌리거나 다시 실행한다. 텍스트 편집 중 Delete는 글자만 지운다.
7. `작업 저장`(⌘S)으로 도면·층·노드·연결·메타데이터·좌표 기준점을 `.imdfrnt`에 저장한다. 자동 저장에도 포함한다.
8. `길찾기 내보내기…`로 전체 층을 `routing-graph.geojson` 한 파일에 내보낸다.

## 실제 좌표

첫 층은 메인 도면과 기존 Anchor 쌍을 가져온다. 각 층은 독립적인 Anchor 쌍을 갖는다. `좌표 기준점` 도구에서 도면을 클릭하고 실제 경도·위도를 입력한다. 일직선에 있지 않은 최소 3쌍이 있어야 내보낼 수 있다. 도면 교체 시 해당 층의 기존 기준점을 초기화한다. 이미 찍은 노드의 도면 좌표는 유지하므로, 좌표계가 다른 도면으로 교체했다면 위치를 확인한다. 교체도 실행취소할 수 있다.

클라이언트에 전달하는 좌표는 WGS 84 `[경도, 위도]`다. 픽셀 좌표를 경위도로 대체해서 내보내지 않는다. 층 번호는 클라이언트 `Level.ordinal` 규칙을 따른다: 지상 1층 0, 위층 양수, 지하 음수. `level_id`는 클라이언트 층 UUID에 맞춘다.

## 클라이언트 계약

기준 소스: [Fingerprint의 최소 길찾기 그래프 fixture](https://github.com/adap-c6-fingerprint/2026-C6-M06-Fingerprint/blob/8274d1d7a82ea39a24dda59d1898fd111831b072/FingerprintTests/Fixtures/minimal-routing-graph.geojson), `feature/indoor-routing-foundation`의 `8274d1d`. 확인 시점의 해당 브랜치에는 그래프 로더·경로 탐색 구현이 없고, 이 fixture와 이를 읽는 테스트가 있다. 따라서 아래는 fixture와 일치하는 출력 계약이며 iOS 앱에서 실제 경로 탐색까지 검증한 결과는 아니다.

| 대상 | 필드 |
|---|---|
| 파일 | `type: FeatureCollection`, `schema_version: 1`, `layout_version`, `routing_config.hard_search_radius_meters`, `features` |
| 노드 | `type: Feature`, 문자열 `id`, `properties.role: node`, `properties.level`, `geometry.type: Point`, `[경도, 위도]` |
| 연결 | `properties.role: edge`, `from`, `to`, `accessible`, `direction: undirected`, `category`, `geometry.type: LineString` |
| 편집기에서 추가한 노드 속성 | `level_id`, `name`, `category`, `metadata` (JSON 객체) |

노드 기본 카테고리는 `waypoint`이고 `entrance`, `stairs`, `elevator`, `destination`을 편집할 수 있다. 연결 카테고리는 `walkway`, `stairs`, `elevator`다. 노드와 연결 UUID는 생성 시 한 번 발급하고 저장·재열기·반복 내보내기에 유지한다.

자기 자신 연결, 같은 두 노드의 중복 연결, 삭제된 노드 참조를 방지한다. 끊어진 노드와 서로 연결되지 않은 그룹 수를 화면에 표시한다. 잘못된 메타데이터, 중복 층 ID·번호, 유효하지 않은 좌표, 기준점 부족, 잘못된 층간 연결은 내보내기를 막고 이유를 표시한다. 연결되지 않은 그래프는 편집 중일 수 있으므로 경고만 표시한다.

## 저장 호환성

프로젝트 버전은 3이다. 기존 버전 2 파일은 `routing` 필드 없이도 열리고, 기존 태깅을 보존한다. 새 파일은 `routing`에 층별 SVG/내장 이미지·Anchor·노드·연결·내보내기 설정을 담는다. 이전 앱은 버전 3을 지원하지 않으므로 새 작업은 새 앱에서 연다.

## 검사

```sh
./build-app.sh
./IM-DFrnt.app/Contents/MacOS/IM-DFrnt --routing-selftest
./IM-DFrnt.app/Contents/MacOS/IM-DFrnt --selftest
```

노드 자체 검사는 클릭·선택·연결·삭제·이동·층 전환·층간 연결·실행취소·메타데이터·좌표 내보내기·버전 2 읽기·이미지 내장 저장을 확인한다. 검사 실행은 사용자 자동 저장본을 읽거나 덮어쓰지 않는다.

후속 확장 후보: 연결 중간 점/꺾은선 편집, 연결 위에 찍은 노드로 연결 분할, 일방통행 및 경로 가중치, 길찾기 미리보기. 클라이언트 계약을 확인한 뒤 추가한다.
