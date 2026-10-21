# 클라이언트용 지도·길찾기 데이터 묶음

이슈: [#54](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/54). 요구사항: `IM-DFrnt 클라이언트용 지도·길찾기 데이터 Export 요구사항`(2026-10-18 초안).

`도구 → 클라이언트용 묶음 내보내기… (지도+길찾기)` 또는 상단 파일 메뉴에서 실행한다. 한 프로젝트의 **모든 층**의 IMDF와 길찾기 그래프를 같은 순간의 프로젝트 데이터 하나에서 만들어 폴더 하나로 저장한다. 기존 `IMDF 아카이브 내보내기`(ZIP, #38)와 `길찾기 내보내기`(그래프 단독)는 그대로 있다.

## 구조

```text
<dataset-id>/                  저장 창에서 정한 폴더 이름 = dataset_id
  dataset.json
  IMDFData/
    manifest.json venue.geojson level.geojson footprint.geojson
    unit.geojson fixture.geojson opening.geojson amenity.geojson   ← 항상 있음(비면 빈 FeatureCollection)
    address.geojson building.geojson …                              ← 프로젝트가 가진 그 밖의 IMDF 파일
  routing-graph.geojson
```

- dataset_id는 영문 소문자·숫자·`.` `_` `-`로 64자 이내다. 한글 프로젝트 이름이면 기본값이 `dataset`이므로 저장 창에서 바꾼다(예: `postech-library`).
- 모든 파일은 UTF-8 JSON이고 키를 정렬해 쓴다. SVG·편집 상태·개인 경로는 넣지 않는다.

## dataset.json (schema 2, 제안)

| 키 | 값 |
| --- | --- |
| `schema_version` | `2` |
| `dataset_id` | 폴더 이름 |
| `layout_version` | 그래프의 `layout_version`과 같은 값(노드 화면의 `도면 버전`) |
| `map_files_sha256` | 위 8종 파일 이름 → SHA-256(앱의 `BundledIndoorNavigationLoader.mapFiles`와 같은 목록) |
| `additional_map_files_sha256` | 그 밖의 `IMDFData/` 파일 → SHA-256 |
| `routing_sha256` | `routing-graph.geojson`의 SHA-256 |
| `shelves_sha256` | `null` — 명시적인 서가 매핑이 없어 `shelves.json`을 만들지 않았다는 뜻 |
| `generated_by` | `"IM-DFrnt"` |

- 해시는 최종 바이트로 계산하고 그 뒤 파일을 바꾸지 않는다. 해시 일치는 좌표 정확도나 보행 가능성을 보장하지 않는다.
- **현재 앱(schema 1)과 호환되지 않는다.** 앱은 `shelves.json`·`shelves_sha256`을 필수로 읽는다. 가짜 매핑을 만들지 않기 위해 별도 버전을 붙였다. 앱 쪽에서 그래프 로딩과 서가 매핑 로딩을 분리하거나 schema 2 adapter를 추가해야 한다(요구사항 4장 경로 2). 최종 schema는 양쪽 담당자가 확정한다.

## 좌표·ID·그래프

- 모든 좌표는 WGS 84 `[경도, 위도]`. SVG 층은 Anchor 변환, IMDF 가져오기 층은 원본 좌표를 쓴다. Polygon 구멍·MultiPolygon은 그대로 둔다.
- level feature id = 층 UUID. 노드 `level_id`·`level`은 함께 낸 `level.geojson`의 UUID·ordinal과 같아야 내보낸다.
- 가져온 IMDF feature는 id·속성을 바꾸지 않는다. 새로 그린 feature의 id는 처음 내보낼 때 발급해 프로젝트에 남기고(자동 저장으로 `.imdfrnt`에 보존), 다음 내보내기에서 같은 id를 쓴다. 노드·연결 UUID는 만들 때 발급한다.
- 그래프는 `RoutingExporter` 구조 그대로다(`schema_version` 1, `routing_config.hard_search_radius_meters`는 탐색 반경이며 간선 길이가 아니다).
- **편집기 제약:** 연결은 양방향(`direction: "undirected"`)만, 두 노드 사이 직선(LineString 2점)만 있다. 벽을 피한 실제 보행 경로를 검증한 것이 아니다. 층간 실제 거리·`traversal_seconds`는 편집기에 없어 넣지 않는다(임시 값도 채우지 않는다).
- 수정 없이 다시 내보내면 `manifest.json`의 `created`(IMDF 규격상 패키징 시각)만 바뀌어 그 해시만 달라진다. 나머지 파일은 바이트까지 같다.
- `layout_version`은 자동으로 올리지 않는다. 지도나 그래프를 고친 뒤에는 노드 화면에서 `도면 버전`을 바꿔야 한다. 갱신 규칙은 합의가 필요하다.

## 막는 오류와 경고

막는 오류(파일을 남기지 않음): 기존 IMDF 아카이브·길찾기 내보내기의 막는 조건 전부(Anchor 부족·좌표 없음·level 다각형 없음/중복·메타데이터·층간 walkway·accessible 계단 등), dataset_id 형식, 비어 있는 venue·level, 파일 안 Feature ID 중복, 잘못된 geometry·범위 밖 좌표·닫히지 않은 ring, level.geojson에 없는 층·ordinal 불일치, 노드 0개, 없는 층·노드 참조, LineString 끝점 불일치, 자기 연결, 길이 0인 같은 층 연결.

경고(내보내되 알림): 타입 간 ID 중복(C5 원본에 있음, 앱 strict 검증에서 거부), 고립 노드, 연결 그룹 분리, 층 외곽 밖 노드(의도한 바깥 출입구인지 확인), 층간 거리·시간 미제공, 서가 매핑 없음.

## 저장

- 작성 중인 도형·임시 문·경도/위도 미입력 기준점이 있으면 묶음에 들어가지 않는다고 먼저 묻는다.
- 같은 이름의 폴더가 있으면 통째로 교체할지 묻는다. 교체를 고르지 않으면 아무것도 바꾸지 않는다.
- 같은 위치의 임시 폴더에 모두 쓰고 다시 읽어 확인한 뒤 한 번에 자리를 바꾼다. 실패하면 임시 폴더만 지우고 기존 폴더는 그대로다.
- 만들기·검증·저장은 백그라운드에서 진행률과 함께 한다.

## 아직 안 되는 것

- IMDF 불러오기는 최상위 `.json`·`.geojson`만 읽어, 원본의 `LICENSE/LICENSE.txt` 같은 파일은 프로젝트에 남지 않고 묶음에도 들어가지 않는다. 라이선스는 따로 넣어야 한다.
- 서가 매핑(`shelves.json`)·층간 거리·단방향 연결·중간 경로점은 편집 기능이 없다.
- postech-library 앱에서 직접 읽어 본 검증은 아직 없다(앱 쪽 adapter 필요).
