# 길찾기 노드 편집

최신 작업: [#17](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/17), `feat/#17-command-node-export` (기존 `feat/routing-node-editor`에서 이어짐). 기존 IMDF 태깅 앱의 `CanvasView`, 도면 좌표 변환, 확대·이동, 실행취소, `.imdfrnt` 저장·자동 저장을 재사용한다. 길찾기 그래프는 IMDF 태깅 결과와 별도로 보관한다.

## 사용 순서

1. `IMDF 불러오기…`(⌘⇧I)에서 완성된 IMDF ZIP 또는 폴더를 선택한다. 폴더 안의 `manifest.json`이나 `level.geojson`도 선택할 수 있다. SVG·이미지를 먼저 열 필요가 없다.
2. IMDF의 층 UUID·ordinal·이름과 층별 공간을 자동으로 가져오고 노드 편집 화면으로 이동한다. 왼쪽에서 작업할 층을 선택한다. 현재는 건물 하나의 지도(ordinal 중복 없음)를 지원한다.
3. level·unit·section·fixture·detail·opening·amenity의 원본 공간을 표시한다. amenity는 unit 참조로 해당 층에 배치하고, Polygon의 구멍과 MultiPolygon을 유지한다. IMDF의 위경도를 사용하므로 좌표 기준점을 추가할 필요가 없다.
4. **⌘ Command를 누른 채 원하는 빈 위치를 클릭**해 현재 층에 노드를 추가한다. 모든 노드 편집 도구에서 사용할 수 있다. 일반 클릭은 선택이며 노드를 추가하지 않는다. 기존 핀에 ⌘+클릭해도 선택만 하고 중복 생성하지 않는다. 일반 핀 드래그는 위치 이동이고 ⌘+드래그는 추가·이동을 하지 않는다. 핀 지름은 화면 기준 8pt이고 선택해도 커지지 않으며 주변에 파란빛만 표시한다. 핀 아래에는 짧은 UUID를 8pt·50% 불투명도로 연하게 표시하고 접두사가 겹치면 구분되는 길이까지 늘린다. 이름을 입력하면 핀 위에 표시한다. 이름·카테고리는 바로 반영된다. 메타데이터는 JSON 객체로 입력하고 `메타데이터 적용`을 누른다.
5. **⌥ Option을 누르고 핀에서 다른 핀으로 드래그**한다. 선이 포인터를 따라오고 대상 핀에 가까워지면 파란빛으로 표시하며 마우스를 놓으면 연결한다. 출발 핀의 위치는 유지한다. 빈 곳에 놓거나 Escape를 누르면 취소한다. `노드 연결` 도구에서는 Option 없이도 같은 드래그를 사용할 수 있다. 다른 층의 계단·엘리베이터는 이 도구에서 두 핀을 차례로 클릭하고, 층 전환 중 시작 핀을 유지한다. 층간 연결은 양쪽 모두 같은 종류의 계단 또는 엘리베이터여야 한다. 계단은 휠체어 접근 불가로 기록한다. 연결은 양방향이다.
6. `선택·이동`에서 핀 또는 연결선을 선택한 뒤 Delete로 지운다. 노드 삭제는 연결도 함께 지운다. 연결 삭제는 노드를 보존한다. ⌘Z / ⌘⇧Z로 되돌리거나 다시 실행한다. 텍스트 편집 중 Delete는 글자만 지운다.
7. `작업 저장`(⌘S)으로 지도·층·노드·연결·메타데이터·좌표 변환을 `.imdfrnt`에 저장한다. 자동 저장에도 포함한다. 다시 열면 IMDF 노드 편집 화면으로 바로 돌아온다.
8. `길찾기 내보내기…`로 전체 층을 `routing-graph.geojson` 한 파일에 내보낸다. GeoJSON은 JSON 형식이며 최상위 `FeatureCollection`에 Point 노드와 LineString 연결이 함께 들어간다. `.imdfrnt`는 편집 작업 저장용이고 클라이언트에 전달하는 파일은 이 GeoJSON이다.

## 실제 좌표

IMDF 입력은 모든 층에 동일한 북쪽 위 방향 표시 좌표계를 사용한다. 위경도에서 화면 좌표로 변환한 계수를 저장하고 역변환하므로, 별도의 좌표 추정이나 수동 기준점 없이 노드의 WGS 84 좌표를 얻는다. 층별 지도와 변환 계수는 프로젝트에 내장되어 원본 ZIP·폴더를 옮겨도 작업을 다시 열 수 있다. 새 IMDF는 새 프로젝트로 열어 이전 작업 파일을 덮어쓰지 않는다.

SVG·PNG·JPG 원본을 쓰는 기존 흐름도 유지한다. `도면 열기…` → `길찾기 노드 편집`에서 시작하고, `클라이언트 층 목록 가져오기…`로 층 정보를 맞춘 뒤 각 층에 도면을 불러온다. 이 흐름은 각 층에서 일직선에 있지 않은 좌표 기준점 3쌍 이상이 필요하다. 원본 도면 교체 시 기존 기준점을 초기화한다.

클라이언트에 전달하는 좌표는 WGS 84 `[경도, 위도]`다. 픽셀 좌표를 경위도로 대체해서 내보내지 않는다. 층 번호는 클라이언트 `Level.ordinal` 규칙을 따른다: 지상 1층 0, 위층 양수, 지하 음수. `level_id`는 클라이언트 층 UUID에 맞춘다.

## 클라이언트 계약

기준 소스: [Fingerprint의 최소 길찾기 그래프 fixture](https://github.com/adap-c6-fingerprint/2026-C6-M06-Fingerprint/blob/8274d1d7a82ea39a24dda59d1898fd111831b072/FingerprintTests/Fixtures/minimal-routing-graph.geojson), `feature/indoor-routing-foundation`의 `8274d1d`. 2026-10-07 원격 브랜치를 다시 fetch해 같은 커밋임을 확인했다. 해당 브랜치에는 그래프 로더·경로 탐색 구현이 없고, 이 fixture와 JSON을 읽어 헤더를 확인하는 [테스트](https://github.com/adap-c6-fingerprint/2026-C6-M06-Fingerprint/blob/8274d1d7a82ea39a24dda59d1898fd111831b072/FingerprintTests/RoutingFoundationTests.swift)가 있다. 따라서 아래는 fixture와 일치하는 출력 계약이며 iOS 앱에서 실제 경로 탐색까지 검증한 결과는 아니다. 테스트의 `synthetic-v1`은 샘플의 도면 버전 값이며 사용자 내보내기는 설정한 `layout_version`을 사용한다.

| 대상 | 필드 |
|---|---|
| 파일 | `type: FeatureCollection`, `schema_version: 1`, `layout_version`, `routing_config.hard_search_radius_meters`, `features` |
| 노드 | `type: Feature`, 문자열 `id`, `properties.role: node`, `properties.level`, `geometry.type: Point`, `[경도, 위도]` |
| 연결 | `properties.role: edge`, `from`, `to`, `accessible`, `direction: undirected`, `category`, `geometry.type: LineString` |
| 편집기에서 추가한 노드 속성 | `level_id`, `name`, `category`, `metadata` (JSON 객체) |

노드 기본 카테고리는 `waypoint`이고 `entrance`, `stairs`, `elevator`, `destination`을 편집할 수 있다. 연결 카테고리는 `walkway`, `stairs`, `elevator`다. 노드와 연결 UUID는 생성 시 한 번 발급하고 저장·재열기·반복 내보내기에 유지한다.

자기 자신 연결, 같은 두 노드의 중복 연결, 삭제된 노드 참조를 방지한다. 끊어진 노드와 서로 연결되지 않은 그룹 수를 화면에 표시한다. 잘못된 메타데이터, 중복 층 ID·번호, 유효하지 않은 좌표, 기준점 부족, 잘못된 층간 연결은 내보내기를 막고 이유를 표시한다. 연결되지 않은 그래프는 편집 중일 수 있으므로 경고만 표시한다.

## 저장 호환성

프로젝트 버전은 4이다. 기존 버전 2·3 파일을 열 수 있고 기존 태깅과 노드 작업을 보존한다. 새 파일은 `routing`에 층별 지도/내장 이미지·IMDF 좌표 변환 또는 Anchor·노드·연결·내보내기 설정을 담는다. 이전 앱은 버전 4를 거절하므로 새 작업은 새 앱에서 연다.

## 검사

```sh
./build-app.sh
./IM-DFrnt.app/Contents/MacOS/IM-DFrnt --routing-selftest
./IM-DFrnt.app/Contents/MacOS/IM-DFrnt --selftest
```

노드 자체 검사는 클릭·선택·연결·삭제·이동·층 전환·층간 연결·실행취소·메타데이터·좌표 내보내기·버전 2·3 읽기·이미지 내장 저장·IMDF 공간과 구멍·기준점 없는 좌표 내보내기·IMDF 저장 재열기를 확인한다. 연결 드래그의 미리보기·대상 스냅·빈 곳/자기 자신/삭제된 노드에 놓기·Option+Escape 취소·층 전환 취소·실행취소 및 표시 ID 충돌·저장 유지도 검사한다. 실제 클라이언트 C5 입력은 `--imdf-test-input <IMDF 폴더> --imdf-test-zip <ZIP>`을 추가해 검증한다. 검사 실행은 사용자 자동 저장본을 읽거나 덮어쓰지 않는다.

Command 클릭 검사에는 일반 빈 곳 클릭 방지, 도구별 추가, 기존 핀 선택·중복 방지, 층별 추가, 실행취소·UUID 복원, 도면 밖·가져오기 중 추가 방지가 포함된다. 실제 C5 입력과 함께 `--routing-imdf-test-output <파일.geojson>`을 지정하면 생산 내보내기 코드로 생성한 노드 2개·연결 1개의 검사용 파일을 남긴다. 원본 IMDF 층 정보까지 비교하려면 저장소 루트에서 다음을 실행한다.

```sh
python3 scripts/validate-routing-export.py <파일.geojson> \
  --fixture <클라이언트>/FingerprintTests/Fixtures/minimal-routing-graph.geojson \
  --levels <클라이언트>/Fingerprint/App/Domain/IMDF/C5/IMDFData/level.geojson
```

검사기는 샘플 필수 필드·타입, 양방향 연결 ID 참조, 끝점 좌표, UUID/ordinal 일치를 확인한다. 이름·메타데이터·추가 카테고리는 편집기의 확장 속성이다. 향후 클라이언트 로더가 이 속성을 해석하는지는 로더 구현 후 별도로 확인해야 한다.

후속 확장 후보: 연결 중간 점/꺾은선 편집, 연결 위에 찍은 노드로 연결 분할, 일방통행 및 경로 가중치, 길찾기 미리보기. 클라이언트 계약을 확인한 뒤 추가한다.
