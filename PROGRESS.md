# IM-DFrnt 진행 기록

## 2026-10-28 — #99 / IMD-80 길안내 전용 내보내기

- PR98이 merge된 최신 develop `9c6b841`에서 `feat/#99-navigation-only-export`를 만들고 기존 IMD-80/#99를 재사용했다. 이후 개발에도 ponytail을 기본 적용한다. 기존 그래프 exporter·관계 JSON 인코더·안전한 폴더 writer를 재사용하며 SQLite/새 의존성·일반 검증 우회 플래그는 넣지 않는다.
- 파일 → 노드/엣지 내보내기…와 노드 화면 버튼에서 `routing-graph.geojson`·`navigation-feature-links.json`·`navigation.json` 세 파일만 저장한다. 모든 층/노드/엣지/메타데이터·양방향 관계·층/그룹 목록/해시를 보존한다. 장소 UUID는 기존 대장을 따르고 신규 발급은 저장 성공 후에만 반영한다.
- IMDFData/도형·SVG·이미지 생성/파싱 및 IMDFArchive/AIMP 검사는 하지 않는다. 좌표·참조·유일 배정과 저장 손상/덮어쓰기 보호는 유지한다. v9 저장·원본 지도·기존 IMDF·그래프 단독/지도+길찾기 묶음의 계약은 그대로다. 관계 인코더만 공유하며 기존 묶음의 IMDF 대조 검사는 유지한다.
- Debug/Release 앱 전체8/8·Release 서명 검증 통과: Self ALL PASS, Building61, Project24, Document23, Routing323(추가19), Drawing56, Footprint93, Compliance169. 로그 `imdfrnt-self-tests.bEqFGP`/`imdfrnt-self-tests.3dU4hu`. 불완전 IMDF/SVG와 무관한 출력, 신규/기존/가져온/폐기 UUID, 관계 1:N·빈 DB, 실제 파일/해시·덮어쓰기, 저장 v9 왕복과 기존 묶음 검사 유지를 확인했다. 검수 앱 `IM-DFrnt/.build/IMD80-navigation-only/IM-DFrnt.app`.
- 새 전용 형식을 읽는 소비 앱 adapter와 실제 iOS 길안내/Apple 업로드는 범위 밖이다. GUI 저장 패널·실제 큰 프로젝트 저장은 사람 최종 검수로 남긴다. 검증·커밋 후 누적 ponytail/팀 셀프 리뷰·PR·CodeRabbit을 진행하고 자동 승인/merge하지 않는다.
- PR100 CodeRabbit Major2건 후속: 생성·쓰기만 `Task.detached`로 옮기고 시작 스냅샷·중복 실행 잠금·기존 진행 UI/안전 writer를 재사용했다. 실패 때 대장은 유지하고 성공 후 메인 액터에서 반영한다. 메뉴 명령 등으로 프로젝트가 바뀌면 오래된 대장을 덮어쓰지 않고 재출력을 안내한다. local imported 장소의 다른 층/누락 참조는 새 전용 출력에서만 차단하고 현재 층을 포함한 다중 층 Fixture는 허용한다. 기존 장소 조회/편집·IMDF 경로는 바꾸지 않았다.
- 최종 Debug/Release 전체8/8, Routing333/333(최초 대비 추가29), strict 서명·diff 검사 통과. 비동기 성공/실패/확인 교체/중복 실행/생성 실패 시 기존 파일 보존/저장 중 상태 교체와 imported 층 참조 회귀10개를 추가했다. 로그 `imdfrnt-self-tests.mGd5iH`/`imdfrnt-self-tests.Uqs2RC`, 최신 검수 앱 `IM-DFrnt/.build/IMD80-navigation-only-reviewed/IM-DFrnt.app`. Minor인 같은 층 길이0 엣지 추가 검사와 docstring coverage 경고는 Major/Critical만 처리하는 범위에 따라 보류한다. 해당 엣지는 기존 그래프 exporter처럼 출력될 수 있으므로 소비 측에서 구분해야 한다. 실제 GUI·큰 프로젝트·소비 앱 통합은 여전히 미검증이다.

## 2026-10-28 — #97 / IMD-79 노드·엣지 화면 성능

- 이전 PR96 병합 후 최신 develop `1554688`에서 `fix/#97-routing-performance`를 만들고 기존 GitHub #97/Linear IMD-79를 재사용했다. 공식 ponytail `09c434ab`의 ponytail/ponytail-review를 설치·읽고 새 캐시 계층 대신 기존 읽기 경로의 중복 계산만 제거했다.
- 엣지마다 `env.routing.node`를 읽으면 매번 `projectContents` 구성/Footprint 동기화/그래프 평탄화를 반복했고 표시 대상도 엣지마다 노드를 선형 검색했다. 렌더링·히트테스트·사각형 선택·접근성·엣지 목록이 한 번 읽은 그래프와 임시 UUID 사전을 재사용하도록 했다. 층 통계도 같은 평가에서 한 번만 구하고 노드 Canvas가 쓰지 않는 도면 편집용 renderStates는 일반 편집 분기로 옮겼다.
- UI·기존 선택 거리/순서·층간/그룹 필터·노드/엣지/장소 연결·Undo/Redo와 IMDF·그래프·클라이언트 묶음 출력 및 저장 v9는 유지한다. 사전은 저장하지 않고 매번 최신 값에서 만들므로 무효화 규칙·새 의존성·파일 모델은 추가하지 않았다. 기존 사용자 파일·열린 앱·32개 모드 전용 로컬 변경도 보존한다.
- 변경 전 경로를 독립 기준으로 비교하는 회귀 검사17개를 추가했다(Debug Routing304/304, 전체8/8). 1,000노드/999엣지 Release 표본3회 중앙값은 기준268.671ms→현재1.104ms, 포스텍 실제 도면/태깅 데이터에 같은 수의 노드를 넣은 조회는740.734ms→1.440ms(각 성능 검사9/9)였다. 모두 같은 엣지를 선택했고 저장 본문·IMDF·그래프 출력 불변 및 이동 Undo/Redo를 확인했다. 초기 저장 바이트 비교의 실패는 savedAt 차이였으며 검사에서 시각만 고정했다. Release 서명 검증 통과, 최종 전체 검사 로그는 PR/이슈에 기록한다.
- 최종 Debug/Release 앱 전체8/8·Release 서명 검증 통과(Self ALL PASS, Building61, Project24, Document23, Routing304, Drawing56, Footprint93, Compliance169). 로그 `imdfrnt-self-tests.92kZfe`/`imdfrnt-self-tests.ixUUki`, 성능 로그 `/tmp/imd79-qa.nuU2bj`.
- 검수 앱은 `IM-DFrnt/.build/IMD79-routing-performance/IM-DFrnt.app`. 별도 성능 플래그는 실제 프로젝트를 읽기만 하고 메모리에서 그래프를 구성한다. 수치는 최근접 엣지 조회 단위이며 실제 화면/GPU 드래그 지연·VoiceOver·좁은 창 검증을 대신하지 않는다. 영향도 M: 노드 편집 화면의 연결된 렌더링/선택 경로 내 최적화이며 데이터 계약은 불변. 커밋 후 누적 ponytail/팀 셀프 리뷰와 CodeRabbit 확인, In Review에서 사람 검수·승인·merge를 기다린다.

## 2026-10-28 — #95 / IMD-78 Unit·Fixture와 도착 노드 연결

- 최신 develop `bdd2991`에서 `feat/#95-routing-feature-links`를 만들고 기존 IMD-78/#95를 재사용했다. 사용자 정정대로 엣지가 아닌 노드를 연결하며, 장소 하나에는 노드 하나 / 노드 하나에는 여러 장소를 허용한다.
- 장소 연결 도구에서 노드→현재 층의 Unit/Fixture 면을 클릭한다. 겹친 면은 직접 고르고 구멍·0% 레이어는 제외한다. 선택 외곽선·양쪽 조회/해제를 제공한다. 기존 배정은 확인 후 교체하며 Undo/Redo를 지원한다. 확인 중 소유 노드·층/프로젝트/도면 요청이 바뀌면 오래된 요청을 적용하지 않는다.
- 노드의 선택적 `featureLinks`를 정본으로 저장하고 장소 역조회는 파생한다. v9 저장으로 구버전의 조용한 유실을 막고 v2~v8 읽기를 유지한다. 기존 버전 고정 검사 기대값만 갱신했다. 층 복사 시 내부/출력 ID 재발급을 따라가며 연결된 공통 도형도 선택 층의 사본으로 가져온다. 노드/층 삭제는 해당 연결을 함께 없애고 Undo로 복구한다.
- 기존 IMDF 원본·그래프 단독 출력·좌표·노드/엣지 관리 로직은 유지한다. 클라이언트 묶음에만 `navigation-feature-links.json`의 양방향 인덱스와 선택적 파일명/SHA-256을 추가한다. 실제 출력 IMDF UUID·층·노드·프로젝트 배정·역인덱스를 검증한다. 연결이 없으면 기존 묶음 구성을 유지한다. 삭제/휴지통 연결은 복원/해제를 안내하고 묶음만 차단한다.
- Debug/Release 빌드·서명 검증·최종 전체 CLI8/8 통과: Self ALL PASS, Building61, Project24, Document23, Routing287(추가39), Drawing56, Footprint93, Compliance169. `LC_ALL=C bash run-self-tests.sh .build/IMD78-node-feature-links-verified/IM-DFrnt.app`, 로그 `imdfrnt-self-tests.hXGriU`. 이전 검증도8/8이었으며 최종본은 같은 프로젝트 재열기 후 오래된 확인 요청 방지를 추가했다.
- 검수 앱 `IM-DFrnt/.build/IMD78-node-feature-links-verified/IM-DFrnt.app`. 현재 열린 앱·사용자 프로젝트·무관한 실행 권한 변경은 보존했다. 실제 GUI 클릭/확인창/좁은 창/확대·팬·PNG/JPG 및 실제 iOS 로더/경로 탐색 연동은 미검증이며 사람 최종 검수/후속 작업이다. 새 파일은 v9 지원 앱에서 연다.
- 영향도 L: 노드 저장 형식·버전 및 클라이언트 묶음의 선택적 데이터 계약과 UI/가져오기/검증이 연결된다. 커밋 후 전체 누적 셀프 리뷰·PR·CodeRabbit Major/Critical 확인 뒤 In Review로 넘기며 AI 승인/자동 merge는 하지 않는다.
- PR #96 첫 CodeRabbit 검토에서 Major/Critical은 없고 선형 조회 최적화 Trivial 1건만 있었다(비차단임을 봇도 확인). 후속 로컬 UI 리소스 검사에서 `NSImage(systemSymbolName: "link.badge.minus", ...)`가 nil임을 확인해, 해제 액션이 보이도록 텍스트 `연결 해제` 버튼으로 바꿨다. 연결/저장/출력 로직은 변경하지 않는다. 최종 검증과 최신 head 리뷰를 갱신한다.

## 2026-10-28 — #92 / IMD-76 노드 화면 층별 레이어 불투명도

- PR #91이 머지된 최신 develop `a1c89ec`에서 `feat/#92-routing-map-layers`를 만들고 IMD-76/GitHub #92에 범위·완료 조건을 기록했다.
- 노드 화면 왼쪽 하단에 Fixture·Unit·배경 0~100% 슬라이더/수치를 추가했다. 배경 → Unit → Fixture → 기존 노드/엣지 순서로 합성하며 기본값은 100/35/80%다. 면과 선을 레이어 단위로 합성하고 0%에서 그 레이어 그리기를 생략한다.
- 현재 층의 기존 태깅/직접 그린 면과 IMDF 원본 도형을 분리 표시한다. 구멍/MultiPolygon·공통 층 참조를 유지하고 원본/편집 UUID 중복·휴지통 부활을 막는다. IMDF 합성 SVG를 배경으로 중복 그리지 않고 타입별 표시 캐시만 만든다. 원본 SVG/이미지·참고 도면은 배경에 포함한다.
- 보기 설정은 층별 세션 상태로만 유지하고 프로젝트 전환 시 초기화한다. IMDF 편집 화면 레이어 설정·데이터 관리·좌표·노드/엣지 편집·Undo·파일 v8·저장/내보내기는 유지한다. 기존 확대 리셋 수정과 사용자 파일/무관한 실행 권한 변경도 보존한다.
- Debug/Release 빌드·ad-hoc 서명 검증 성공. `LC_ALL=C bash run-self-tests.sh .build/IMD76-routing-layers/IM-DFrnt.app` 전체 8/8 통과: Self ALL PASS, Building61, Project24, Document23, Routing248(추가28), Drawing56, Footprint93, Compliance169. 최종 로그 `imdfrnt-self-tests.qsqUkQ`, 검수 앱 `IM-DFrnt/.build/IMD76-routing-layers/IM-DFrnt.app`.
- 첫 전체 실행도 앱 exit는 모두 0이었지만 색상 경고가 섞인 로그의 awk UTF-8 판독이 실패해 7/8로 집계됐다. 검사 조건은 유지한 채 byte locale에서 재실행해 8/8을 확인했다. 공통 검사 스크립트는 변경하지 않았다.
- 작은 실제 Canvas 벡터 이미지로 순서·0/50/100% 합성을 검사했다. NSApplication 전 headless ImageRenderer는 이 환경에서 CGImage 픽셀을 표시하지 못하므로 실제 PNG/JPG 표시·슬라이더 마우스 조작·좁은 창·확대/팬 GUI는 사람 최종 검수로 남긴다. 현재 열린 앱은 교체/종료하지 않았다.
- 영향도 M: 노드 표시 기능의 UI·세션 상태·렌더링 캐시가 연결되지만 저장/IMDF 계약은 바꾸지 않는다. 커밋 후 셀프 리뷰·PR·CodeRabbit Major/Critical 확인 뒤 In Review로 넘기고 사람 리뷰·승인·merge를 기다린다.

## 2026-10-28 — #90 / IMD-75 노드·엣지 화면 확대 리셋 방지

- PR #89가 반영된 최신 develop `23cbc26`에서 `fix/#90-routing-viewport-reset`를 만들고 기존 #90에 수정 범위·완료 조건을 기록했다.
- 노드 화면에서 캔버스 크기가 바뀔 때마다 `fit`하던 경로를 초기 비유효 크기 → 유효 크기일 때만 실행하도록 제한했다. 선택 패널/창 크기 변화는 확대·이동 상태를 덮어쓰지 않는다. onAppear·문서 fingerprint·층 전환·수동 맞춤 경로와 다른 편집 화면은 유지한다.
- IMDF 관리·노드/엣지 데이터·그룹·좌표 변환·저장 v8·내보내기는 변경하지 않았다. 기존 앱·원본 프로젝트·무관한 파일 실행 권한 변경도 보존했다.
- Debug/Release 빌드·ad-hoc 서명 검증 성공. Release 전체 CLI 8/8 통과: Self ALL PASS, Building61, Project24, Document23, Routing220(추가12), Drawing56, Footprint93, Compliance169. 로그 `imdfrnt-self-tests.sqNAbL`, 검증 앱 `IM-DFrnt/.build/IMD75-viewport-fix/IM-DFrnt.app`.
- 검사는 크기 변경 시 맞춤 여부와 모델 조작 후 문서/층 트리거 불변을 확인한다. 실제 SwiftUI 창의 배율·화면 픽셀을 조작한 GUI 검사는 아니므로 확대/팬 → 노드·엣지 편집 → 창 리사이즈 → 맞춤·층 전환은 사람 최종 검수로 남긴다.
- 영향도 S: 노드 편집의 한정된 크기 변경 이벤트 경로만 수정하고 공유 데이터 계약은 유지한다. 커밋 후 셀프 리뷰와 PR/CodeRabbit Major·Critical 검토를 수행하며 사용자 지침에 따라 자동 merge하지 않는다.

## 2026-10-28 — #88 / IMD-73 길찾기 엣지 그룹

- 최신 develop `1146120`에서 `feat/#88-edge-groups`를 만들고 연결된 기존 이슈 #88에 범위·완료 기준을 구체화했다.
- 그룹 UUID·이름 관리, Shift 클릭/드래그 다중 선택, 일괄 배정·해제, 수동 새 연결 기본 그룹, 전체/미배정/지정 그룹 필터를 추가했다. 필터는 캔버스·히트테스트·선택·배정에 공통 적용한다. 기존 핀 이동·연결과 자동 노드/엘리베이터 배치는 유지한다.
- 그룹/배정은 기존 프로젝트·Undo snapshot에 추가한다. 층 가져오기에서 UUID/이름 충돌은 가져온 그룹만 재발급한다. 새 파일은 v8로 저장해 이전 앱의 조용한 그룹 유실을 차단하고 v2~v7 읽기를 유지한다. IMDF 도형·관리·좌표·출력 계약은 바꾸지 않는다.
- 길찾기 GeoJSON에 배정된 엣지만 `group_id`·`group_name`을 추가한다. IMDFrnt는 안내 엔진이 아니므로 실제 소비 앱 수정 없이 동일 그룹=직진/그룹 변경=안내 판단 규칙을 문서화했다. 층 전환·도착·안전 안내는 별도 유지해야 한다.
- Debug·Release 빌드 및 ad-hoc 서명 검증 성공. 전체 CLI 8/8 통과: Self ALL PASS, Building 61/61, Project 24/24, Document open 23/23, Routing 208/208(추가44건), Drawing Loading 56/56, Footprint 93/93, IMDF Compliance 169/169. 검증 앱은 `IM-DFrnt/.build/IMD73-edge-groups-verified/IM-DFrnt.app`, 로그는 `imdfrnt-self-tests.NrPw5j`다. GUI/소비 앱 실기기 확인은 사람 검수로 남긴다.
- Release 첫 전체 검사는 6/8 모드 통과였으며 실패 2건은 Self/Footprint의 고정 v7 기대값이었다(동작 회귀 아님). 현재 v8 기대값으로 수정하고 전체 재검증한다. 추가 클라이언트 묶음 검사까지 Routing 208/208 통과했다.
- 영향도 L: 길찾기 저장·내보내기 계약과 UI·선택/Undo·층 가져오기가 연결된다. 커밋 후 셀프 리뷰, CodeRabbit Major/Critical 해소 뒤 In Review로 이동하며 사람 리뷰·승인·merge는 별도다. 기존 앱·사용자 프로젝트·무관한 파일 권한 변경은 보존한다.
- [PR #89](https://github.com/adap-c6-fingerprint/IMDFrnt/pull/89)를 생성하고 커밋 후 셀프 리뷰 및 CodeRabbit 전체 리뷰/후속 리뷰를 요청했다. 최신 커밋의 CodeRabbit 검토 완료 전에는 통과로 간주하지 않는다.

## 2026-10-26 — #82 / IMD-70 Opening 경계 오류만 허용하는 Sandbox 내보내기

- 최신 develop `e9f4704`에서 `feat/#82-opening-boundary-export`를 생성했다. 기존 #82에 목적·검증 조건을 기록하고 새 이슈는 만들지 않았다.
- **파일 → Sandbox 검사용 내보내기… (Opening 경계 오류만 우회)**를 추가했다. 명시적 검사 전용 정책에서만 Opening–Unit 경계 불일치를 차단 오류 대신 안내로 남긴다. 기본 파일명에 `-sandbox`를 붙이고 저장 패널에 범위를 표시한다. 문자열 오류 필터링이나 전역 검증 해제는 사용하지 않는다.
- 일반 ZIP·개별 GeoJSON·클라이언트 묶음과 모든 다른 검사/사전 차단을 유지한다. 정책은 호출 단위로 전달하고 저장하거나 재사용하지 않는다. 도형·속성·참조·UUID를 자동 수정하거나 Opening을 누락하지 않는다. 저장 형식은 v7 그대로다.
- Debug·Release 빌드·ad-hoc 서명과 CLI 8/8 통과: Self ALL PASS, Building 61/61, Project 24/24, Document open 23/23, Routing 164/164, Drawing Loading 56/56, Footprint 93/93, IMDF Compliance 169/169(새 회귀 27건). 일반/검사 전용 차이, 혼합 오류 차단, ZIP 저장·재가져오기, 원본/출력 보존 및 정책 누출 방지를 검사했다.
- 검증 앱은 `IM-DFrnt/.build/Opening-boundary-sandbox/IM-DFrnt.app`, 로그는 `imdfrnt-self-tests.KFf3yO`다. 기존 앱·사용자 프로젝트·무관한 권한 변경은 보존한다. GUI 메뉴/저장 패널 직접 조작·실제 Sandbox/AIMP 업로드는 미검증이다.
- 영향도 M: 별도 내보내기 기능의 UI·검증·출력 연결이 바뀌지만 일반 출력 계약과 저장 구조는 유지한다. 사람 리뷰·승인 경로를 적용하고 PR 생성 후 merge는 하지 않는다.

## 2026-10-26 — #79 / IMD-68 / PR #80 메타데이터 후속 리뷰 3건

- 개별 내보내기는 열린 공통 정보 편집기의 타입을 우선한다. 편집기가 닫히면 기존 활성 레이어·길찾기 내보내기를 유지한다.
- 다층 프로젝트의 층 가져오기는 선택 층과 실제 복사할 공통 정보에서 도달하는 Building·Address만 충돌 검사/병합한다. 무관한 정보는 가져오지 않으며, 필요한 정보의 UUID 충돌은 기존처럼 변경 전에 전체 중단한다. Building 경유 주소·Venue/공통 Footprint 종속, 구형 단일 층의 미연결 공통 정보와 기존 단일 기본값 경로를 보존한다. Occupant/Relationship의 선택 필터는 유지한다.
- 다국어 캔버스 이름은 모든 fallback에서 공백·줄바꿈과 빈 문자열을 건너뛴다. ko/en 기본·지역 태그 우선순위는 유지한다.
- Debug·Release 빌드·ad-hoc 서명과 CLI 전체 8/8 통과: Footprint 93/93, IMDF Compliance 142/142(새 회귀 29건). 실제 가져오기 충돌/부분 반영 방지·Undo/Redo·저장 왕복, Footprint 현재 참조·기본값 및 편집 대상 선택을 포함한다. 앱은 `.build/AIMP-metadata-review/IM-DFrnt.app`, 로그는 `imdfrnt-self-tests.tLtBdd`다.
- 기존 앱·사용자 프로젝트·무관한 권한 변경은 보존한다. 기존 브랜치에서 커밋·PR #80 반영을 진행하며, 누적 영향도 L과 사람 리뷰/승인 경로를 유지한다. GUI 파일 저장 패널·AIMP 제출은 미검증이고 merge는 하지 않는다.

## 2026-10-26 — #79 / IMD-68 / PR #80 추가 리뷰 7건

- 운영시간 구간은 안정 ID로 조회·편집·삭제하며 삭제 후 지연 입력은 무시한다. 동일 시간 재로딩은 ID를 유지하고 시간 값 비교와 hours 문자열 형식은 그대로다.
- 표시점/Anchor 입력 중 꼭짓점 드래그를 시작하지 않으며, 점형 Feature에만 기존 범위 검사를 연결한다. 선형 투영·면형 검사·일반 꼭짓점 이동은 유지한다. 캔버스 이름은 기본 태그 우선 및 지역 태그 fallback을 적용한다.
- 동일 Manifest 충돌을 다시 보관하거나 해결 상태를 해제하지 않는다. 새로운 충돌만 재확인하며 이전 사본·Undo/Redo를 보존한다.
- IMDF 준수 검사 요약은 실제 실패 수에 따라 PASS/FAIL을 출력한다. 길찾기 저장 문서의 v7 저장·v2~v6 읽기·buildingProject 공통 구조를 갱신했다.
- Debug·Release 빌드·서명 및 CLI 전체 8/8 통과: Footprint 93/93, IMDF Compliance 113/113. 새 검사 30건은 안정 ID/삭제/지연 입력, 이름 표시, 우선 입력, 점 범위, 반복 충돌, 저장/Undo/Redo와 요약을 포함한다. 앱은 `.build/AIMP-review-safety/IM-DFrnt.app`이며 기존 앱·프로젝트는 보존한다.
- 성능 캐시·주석 커버리지와 무관한 기존 파일 권한 변경은 제외한다. 누적 영향도 L이며 GUI/AIMP 수동 검증·사람 코드리뷰/승인은 별도다. 사용자 요청에 따라 커밋·push 후 `@coderabbitai review`를 요청한다.

## #79 / IMD-68 / PR #80 — CodeRabbit 리뷰 1~6번 후속

- 충돌하는 복사 도형의 내부 ID와 export UUID를 새로 발급하고 속성 참조·소유권·대여·GeoJSON·출입구 노드 및 종속 Occupant/Relationship 참조를 함께 갱신한다. 같은 층 교체 시 충돌하지 않는 ID는 유지한다.
- Manifest 기본 언어 태그를 이름 간편 입력과 자동 Level 이름에 적용한다. 출력에는 일반 언어 라벨에서 정확한 기본 태그를 보완하고 기존 언어를 유지하며 엄격한 검증은 완화하지 않는다.
- 표시점/Anchor 클릭을 이름표·면·점 선택보다 우선 처리한다. Footprint 테스트 요약은 실패 수에 따라 PASS/FAIL을 표시한다.
- 검사 문서·README의 현재 모드 수/목록/결과와 길찾기 level_id/ordinal 계약을 갱신했다. 이전 시점의 검사 기록은 역사로 구분해 보존한다.
- Debug·Release 빌드와 서명, 전체 CLI 8/8 통과(Footprint 93/93, IMDF Compliance 83/83). 별도 앱 `.build/AIMP-coderabbit-fixes/IM-DFrnt.app`이며 기존 앱·프로젝트는 수정하지 않았다. 누적 영향도 L, 실제 GUI/AIMP와 사람 리뷰/승인은 별도다.
- 사용자 지시로 성능 개선·주석 커버리지(7·8번)는 제외한다. 기존 파일 권한 변경을 제외하고 로컬 커밋만 진행한다.

## 2026-10-25 — #79 / IMD-68 자체 리뷰 후속: Building 표시점

- Building 표시점을 지정할 때 `building_ids`로 해당 Building을 참조하는 Footprint만 검사한다. 다른 건물 또는 연결되지 않은 Footprint에서는 기존 표시점을 바꾸지 않는다. UUID 대소문자를 구분하지 않는다.
- 다중 건물 허용/거부와 연결 누락 회귀 검사를 추가했다. 기존 합성 fixture에도 명시적 건물 참조를 설정했다.
- Debug·Release 빌드와 ad-hoc 서명 검증 성공. 별도 앱 `.build/AIMP-v7-review-fix/IM-DFrnt.app`으로 전체 CLI 8/8 통과: Self ALL PASS, Building 61/61, Project 24/24, Document open 23/23, Routing 164/164, Drawing Loading 56/56, Footprint 93/93, IMDF Compliance 64/64. 두 P2의 회귀 경로를 재검수했다.
- 누적 영향도 L이며 사람 코드리뷰·승인과 실제 GUI/AIMP 제출 검증은 남아 있다. 기존 앱·프로젝트는 변경하지 않았고 PR·push는 수행하지 않는다.

## 2026-10-25 — #79 / IMD-68 자체 리뷰 후속: 공통 UUID 충돌

- 층 가져오기 전에 관련 공통 정보를 병합할 수 있는지 검사한다. 동일 UUID·동일 내용은 재사용하고, 내용 충돌이나 UUID 누락은 안내 후 전체 가져오기를 중단한다. UUID의 대소문자는 구분하지 않는다.
- Address·Building·Occupant·Relationship 충돌과 부분 반영 방지, 층·도면·편집 상태·Undo/Redo 보존, 동일 레코드 재사용 회귀 검사를 추가했다. Debug 빌드 및 IMDF Compliance 64/64 PASS.
- 기존 파일 권한 변경은 이번 수정에 포함하지 않는다. PR·push 없이 기존 #79 브랜치에서 로컬 커밋한다.

## 2026-10-25 — #78 / IMD-67 Apple IMDF 공통 정보·내보내기

- Linear IMD-67 / GitHub #78에 공식 문서 대조와 재현된 10개 수정 항목을 먼저 기록하고, develop 2179869에서 `feat/#78-imdf-standard-export`를 만들었다. Push·PR 생성은 하지 않는다.
- Address·Building·Occupant·Manifest 편집을 프로젝트 공통 원본으로 통합했다. 기존 층별 메타데이터는 수명 UUID·속성·참조·편집 원본을 보존해 이전하며, 옛 개체 소유권을 해제한다. 휴지통/복원/Undo/Redo와 층 단위 가져오기의 공통 정보 보존을 포함한다. Manifest 충돌은 사용자가 선택한다.
- 공식 16종을 타입 목록과 내보내기에 포함하고 Detail·Kiosk·Relationship 및 컬렉션 헤더·foreign member를 보존한다. 선택 속성의 null 고정을 풀어 문·접근성·상관 ID·유효 기간·부모 관계·다국어 JSON을 편집한다. 다중 건물·합법적 동일 ordinal을 허용한다.
- ZIP·개별 GeoJSON·클라이언트 묶음의 최종 검증을 공유한다. 필수 레코드/속성·공식 category·UUID v4/참조·부모 순환·기하 유효성·Venue 포함·Unit–Level·Opening 경계·Anchor/display_point 위치를 검사한다. 점 작도 도형의 display_point와 플래그 없는 Polygon 구멍 출력을 수정했다. Footprint category를 출력 시 ground로 추정하지 않는다.
- 프로젝트 형식은 v7이며 v2~v6 읽기를 유지한다. 이전 앱의 조용한 데이터 유실을 방지한다. 초안 저장과 공식 IMDF 전달 검증은 구분한다.
- Debug 빌드 및 8/8 CLI 모드 통과: SelfTest ALL PASS, Building 61/61, Project 24/24, Document open 23/23, Routing 164/164, Drawing Loading 56/56, Footprint 56/56, IMDF Compliance 50/50. 실제 5층 완료 프로젝트의 이전·저장·재열기 63/63, 원본 SHA-256 검사 전후 동일.
- 실제 화면 조작·Apple IMDF Sandbox 업로드는 미검증이다. 실측 위치·층/시설의 현실 의미·조건부 상관 관계·복합 OSM hours·언어 하위 태그의 IANA 등록 등은 수동/Apple 검증을 남긴다. 로컬 검증을 Apple 인증이나 모든 의미 규칙 자동 충족으로 표현하지 않는다. [공통 정보와 출력 사용법](docs/projects/BUILDING_LEVELS.md#78--imd-67--공통-정보와-공식-imdf-내보내기).

## 2026-10-24 — #74 / IMD-64 전역 Footprint와 층 정렬

- Footprint는 메인 화면의 기존 레이어·점 작도·꼭짓점 편집 UI를 사용하며 건물 전역의 한 저장소를 공유한다. GPS 없이도 작도한다. 기존 층별 편집/GeoJSON Footprint를 ID·원본 속성과 함께 이전한다.
- Anchor 지정은 Footprint와 실제 지도의 대응점을 지정하는 화면으로 연결했다. Level 정렬 화면에서는 Footprint와 층 외곽만 표시하고 층별 대응점, 표시·불투명도, 이동·회전·균일 크기를 조절한다.
- 층 → Footprint → GPS 변환을 태깅·가져온 IMDF·길찾기 내보내기에 반영한다. 원본 도면 좌표를 덮어쓰지 않으며 저장·Undo/Redo를 지원한다.
- CLI 검증: Footprint 17/17, Building 61/61, Project 24/24, Routing 164/164, 전체 SelfTest ALL PASS. 검증용 앱에서 메인 레이어 열기, Footprint Anchor 화면·GPS 수치 수정, Level 정렬 화면·회전·층 숨김·대응점 화면 배치를 확인했다. 지도 타일 로딩/실제 지도 클릭까지 검증한 것은 아니다.
- 상세 사용자 흐름: [전역 Footprint 사용법](docs/projects/GLOBAL_FOOTPRINT.md).

## 2026-10-24 — 신기능 13항(B안): 수직 이동 노드의 층별 복제

- 구현 방식은 **B안(수동 기준 노드의 층별 복제)**으로 정했다. A안(엘리베이터 전면 자동 계산)은 이번 범위에 넣지 않았다.
- 계단·엘리베이터·에스컬레이터 노드를 고르면 정보 패널의 `층별 복제`에서 대상 층을 체크해 같은 위경도의 노드를 만든다(`VerticalReplication.swift`). 층마다 도면 좌표계가 달라 위경도를 거쳐 옮기며, 이를 위해 `GeoAffineTransform.inverse`와 `ProjectLevelInfo.localPoint(for:)`를 추가했다.
- 같은 시설은 `RoutingNode.verticalGroupID`(선택 항목)로 묶는다. 엘리베이터는 묶음 안에서 층 번호가 이웃한 노드끼리 연결하고, 계단·에스컬레이터는 노드만 복제한다. `escalator` 카테고리를 추가했다. 내보내기 노드에 `vertical_group_id`가 붙는다.
- 반복 실행은 중복 노드·연결을 만들지 않고, 이미 있는 묶음 노드의 위치는 덮어쓰지 않는다. 같은 자리(1 m 이내)의 수동 노드는 새로 만들지 않고 묶음에만 넣는다. 좌표가 없는 층은 건너뛴다. 실행취소 한 번으로 복제와 연결이 함께 되돌아간다.
- 정하지 않은 것: 기준 노드를 옮겼을 때 복제본 동기화(하지 않음), 층별 위치가 다른 경우의 보정은 복제 뒤 각 노드를 직접 옮기는 방식이다.
- 자체점검(Debug): Routing 139/139(신규 20항목), `--selftest` ALL PASS, Building 60/60, Project 24/24. 실제 화면의 패널 배치·체크박스·복제 버튼은 확인하지 않았다(CLI 검사만). 수동 확인 대상으로 남긴다.
## 2026-10-24 — #69 IMDF opening 중앙 출입구 노드 자동 배치 (신기능 14항)

- 노드 편집 상단의 `출입구 노드 자동 배치` 버튼으로 실행한다(가져오기 직후 자동 실행은 하지 않는다). 실행취소 한 번으로 전부 되돌아간다.
- 중앙은 opening `LineString`의 **길이 기준 중간점**이다. 두 점이면 중점이고, 점 나열 방향을 뒤집거나 화면을 확대·회전해도 같다(`OpeningEntrancePlacer`).
- 노드는 `category = entrance`, opening이 속한 층의 UUID·좌표로 만든다. 원본 opening 도형은 건드리지 않고 연결(edge)도 만들지 않는다.
- 노드에 `sourceOpeningID`(opening id)를 남겨 재실행 때 중복을 막는다. 사용자가 옮기거나 이름을 바꾼 노드는 덮어쓰지 않고, 중앙에 이미 수동 노드(0.3 m 이내)가 있으면 새로 만들지 않는다. 노드를 지우면 다음 실행에서 다시 만들어진다.
- 중앙을 못 구하는 opening(geometry 없음·LineString 아님·좌표 오류·길이 0·id 없음)은 노드를 만들지 않고 오른쪽 패널에 사유를 표시한다.
- `sourceOpeningID`는 선택 항목이라 이전 프로젝트 파일도 그대로 열린다. 내보내기 형식은 바뀌지 않는다.
- 자체점검(Debug, scratch 빌드): Routing 140/140(신규 24항목), `--selftest` ALL PASS, Building 60/60, Project 24/24, Drawing Loading 56/56, Document open 20/23(기존 scratch 빌드 한계: Info.plist 항목). 실제 창에서 버튼을 누르는 흐름은 확인하지 않았다.

## 2026-10-20 — #31 브랜치 추가 작업: 정보 type 공식 스펙 대조·입력 가이드

- address·building·occupant·manifest의 입력 칸을 OGC IMDF 1.0(Apple 제출 원문)과 Apple `IMDF.zip`의 검증 규칙(`imdf-validations-1.0.3.csv`)·범주 파일(`categories_20210728.csv`)에 맞췄다.
- address: `unit` 입력 가능. `country`는 ISO 3166 목록, `province`는 한국이면 ISO 3166-2 17개 목록에서 고르고 그 밖의 나라는 형식만 점검한다.
- building: `alt_name`·`restriction`(employeesonly·restricted) 입력 가능. occupant: `hours`·`phone`·`website` 입력 가능, category를 Apple 범주 파일 1116종 목록으로 채웠다. 스펙에 없는 `level_id`에도 비표준 표시를 붙였다.
- manifest: `version`은 1.0.0 고정 표시, `extensions` 칸 추가, `created`는 소수 초 없는 DATE-TIME으로 쓴다.
- 칸 아래에 입력 가이드를 보이고, Apple Violation이면 빨간 글씨, Warning이면 주황 글씨로 고치는 방법을 보인다(`PropertyRules`). Violation이 남으면 IMDF 내보내기를 막고 층·일련번호·칸을 알려준다. 글자칸은 앞뒤 공백을 떼고 phone은 공백·하이픈·괄호를 뗀다.
- occupant 업종 한국어 표기는 아직 없어 영어로 보인다. occupant `validity`·`correlation_id`는 null로 둔다.
- 자체점검(Debug): `--selftest` ALL PASS, Building 60/60(신규 13항목), Project 24/24, Routing 117/117, Drawing Loading C5·포스텍 각 56/56, Document open 20/23(기존 scratch 빌드 한계). 실제 창에서는 확인하지 않았다.

## 2026-10-20 — #31 브랜치 추가 작업: 빈 층에서 .imdfrnt 불러오기

- 새 층을 만들고 빈 캔버스나 사이드바의 `.imdfrnt 불러오기`를 누르면 지금 프로젝트가 저장되고 고른 프로젝트로 전환됐다. `openProject()`가 언제나 프로젝트 전환 경로(`openDocumentAsync`)만 탔기 때문이다.
- 이제 지금 층이 비어 있고 다른 층에 작업이 있으면(`importsProjectIntoActiveLevel`), 고른 파일의 층 하나를 지금 층에 넣는다(`LevelProjectImport.swift`). 도면·태깅·anchor·지도 정렬·노드·층 안 연결·상태가 들어오고, 층 ID·이름·층 번호는 지금 층 것을 유지한다. 층간 연결은 가져오지 않는다.
- 파일에 작업된 층이 여럿이면 어느 층을 넣을지 묻는다(이름이 같은 층이 기본). 노드 ID가 겹치면 새 ID로 바꾼다. IMDF에서 온 층의 GeoJSON 층 ID도 지금 층 ID로 바꾼다. 불러온 것은 '최근 작업' 시각으로 찍지 않는다.
- 모든 층이 비어 있거나 작업된 층에서 누르면 예전처럼 프로젝트를 전환한다. 실행취소 한 번이면 빈 층으로 돌아간다.
- 같은 날 상태 아이콘을 `Menu`에서 버튼·팝오버로 바꿔 상태 색이 보이게 하고, Feature Type 줄의 위아래 여백을 넓혔다(36b355e).
- 자체점검(Debug): Building 47/47(신규 7항목), `--selftest` ALL PASS, Project 24/24, Document open 20/23(기존 scratch 빌드 한계). 실제 창에서 누르는 흐름은 확인하지 않았다.

## 2026-10-20 — #31 브랜치 추가 작업: Feature Type 상태·순서·정렬 (신기능 12항)

- [이슈 #31](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/31)에 추가 작업으로 기록하고 `feat/#31-map-align`에 포함했다.
- 좌측 'PROPERTY TYPE'을 'FEATURE TYPE'으로 바꾸고, 층에 귀속되지 않는 정보 type(address·building·manifest·occupant)은 층 탭이 있는 상단바(`LevelTabBar`) 오른쪽으로 옮겼다.
- 상태(`LayerWorkStatus`: Complete·In Review·In Progress·Todo)는 사용자가 아이콘 메뉴로 고른다. 층 type은 `ProjectLevel.workStatus`에 층마다, 정보 type은 `BuildingProject.metadataWorkStatus`에 하나씩 둔다. 층의 완료는 계산값이다 — 좌측 type이 모두 Complete이면 상단바의 그 층에 초록 체크가 붙는다.
- 상단바의 층과 좌측 type은 끌어서 순서를 바꾼다(`levelDisplayOrder`·`featureTypeOrder`). 층 번호(ordinal)는 바꾸지 않는다. 좌측 목록은 사용자 지정·완료 순·미완료 순·최근 작업 순으로 정렬하며, 정렬 기준은 이 Mac에 저장한다.
- 최근 작업은 `perform` 전후 feature를 비교해 바뀐 type의 시각을 `ProjectLevel.lastEdited`에 남긴다. 레이어를 열거나 상태만 바꾼 것은 남지 않고, 실행취소하면 시각도 되돌아간다.
- '레이어' 섹션의 표시·투명도·닫기를 각 feature type 줄 아래로 옮겼다. 기본·속성 필터 레이어는 '기본·필터 레이어' 섹션에 남겼다.
- 새 필드는 모두 선택 항목이라 이전 프로젝트 파일도 그대로 열린다.
- 자체점검(Debug): `--selftest` ALL PASS, Building 40/40(신규 13항목), Drawing Loading C5·포스텍 각 56/56, Routing 117/117, Project 24/24. Document open 20/23은 기존 scratch 빌드 한계(`.app` Info.plist 없음)다.
- 실제 화면의 끌어서 옮기기·상태 메뉴·정렬 메뉴는 확인하지 않았다(CLI 검사만). 수동 확인 대상으로 남긴다.

## 2026-10-20 — #31 브랜치 추가 작업: amenity 창·겹침 이름표·opening 저장 지연

- [이슈 #31](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/31)에 추가 작업 목록과 완료 조건을 기록하고 `feat/#31-map-align`에 포함했다.
- amenity: 점을 찍어 저장하면 그 feature를 고르고 `tagEditorRequest`로 캔버스에 category·name 창을 요청한다. 캔버스는 다음 그리기에서 생긴 이름표 자리에, 없으면 찍은 점 위에 창을 띄운다.
- 엔진 디버깅 6번: '빈틈/겹침' 토글이 켜지면 겹침 이름표가 같은 자리·같은 글꼴로 빨간 unit 이름표 위에 그려져 구멍 뚫기 입구를 덮었다. 겹침 이름표를 조각 상자 위쪽 안에 달고 feature 이름표보다 먼저 그린다. 토글은 클릭 경로에 관여하지 않는다.
- 엔진 디버깅 7번: 파생 기하 열쇠에 opening 선(닫는 선분)이 있어 opening 하나를 저장할 때마다 도면 전체 면 찾기가 다시 돌았다. 그 결과 `closedPolygonFaces`는 10-18 면 단위가 저장된 feature 경계 방식(`faceModeFaces`)으로 바뀐 뒤 자체점검만 읽었다. 면 찾기·`closedPolygonFaces`·열쇠의 `closingSegments`를 없앴다. 층 불러오기에서도 면 찾기 시간이 빠진다.
- 측정(Debug, CLI, 실프로젝트 사본): opening 하나 저장 포스텍 도서관 2층 약 1.3~1.8초 → 0.17초, C5 0.035초. 열쇠가 그대로라 백그라운드 재계산과 "점·면 계산 중" 팝업이 일어나지 않는다.
- 자체점검(Debug): `--selftest` ALL PASS(신규 2항목), Drawing Loading C5·포스텍 각 56/56, Routing 117/117, Project 24/24, Building 27/27. Document open 20/23의 실패 3건은 scratch 빌드에 `.app` Info.plist가 없어서 나며 수정 전 HEAD에서도 같다.
- 실제 화면의 amenity 창·겹침 이름표 클릭·opening 연속 저장은 확인하지 않았다(CLI 검사만). 수동 확인 대상으로 남긴다.

## 2026-10-15 — #37 Opening 두 점 태깅

- [이슈 #37](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/37)에 목표·작업 목록·완료 조건을 기록하고, #21 커밋 위에 `feat/#37-opening-two-point`를 만들었다(#21 PR 병합 후 병합).
- C5 도면은 문 회전 호가 점선(짧은 선분 여러 개)이라 곡선 하나로 고를 수 없었다(#35). '문 임시로 닫기' 창은 유지하고 문짝·호를 고르는 단계를 없앴다. 흐름은 **문 선 양 끝 두 점 찍기 → 임시 문 저장(Return) → '모두 Openings 레이어에 반영하기'**다. 창 안의 클릭은 점만 찍고, 찍은 점을 다시 누르면 지운다.
- 새 임시 문과 반영된 opening은 도면 개체를 소유하지 않으며 좌표는 찍은 두 점(LineString)이다. `TemporaryDoor`의 문짝·호 id는 선택 항목으로 바꿨다. 예전 방식의 임시 문은 변환하지 않고 그대로 읽고 저장하며, 반영하면 예전처럼 문·호를 그 opening이 소유한다.
- 자체점검: 기본 입력·C5 SVG 6/6 모드 통과(#37 신규 11항목 포함). 실제 사용자 프로젝트 입력은 Drawing Loading 50/51로, 기존 실패 1건("층 선택·캐시는 저장 데이터 변경 없음", develop에서도 재현)만 남는다. 입력 원본 SHA-256은 검사 전후 동일하다.
- 실제 화면의 점 찍기·저장·반영은 확인하지 않았다(CLI 검사만). 수동 확인 대상으로 남긴다.

## 2026-10-15 — #21 점 단위 편집·면 계산 버퍼링 해소

- [이슈 #21](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/21)을 "모든 레이어 점 단위 편집 + 면 단위 혼용"으로 확장 기록한 뒤 `feat/#21-point-face-editing`에서 작업했다. 1차 사용성 검증(#35)의 "도면 첨부·unit 레이어 생성 시 로딩이 매우 오래 걸림"(#39)의 원인 분석을 포함한다. PR #43은 소스 없이 Xcode·Finder 파일만 병합되어 이 PR로 소스를 올린다.
- 모든 property type 레이어의 기본 작업을 점 단위 편집으로 바꿨다. 꼭짓점·교점을 찍어 DraftShape를 만들고 시작점을 다시 누르면 닫혀 저장된다(⌥ 클릭은 새 점, Delete는 마지막 점, ESC는 취소, Return은 닫기). 자기 교차·넓이 0인 도형은 확정하지 않는다. 꼭짓점 이동/고정 토글과 점 추가·삭제·이동의 Undo/Redo를 지원한다. LineString(opening)은 두 점, Point는 한 점으로 바로 저장한다. 점으로 그린 도형은 원본 SVG 개체를 소유하지 않으며 좌표(`polygonRings`·`drawnVertices`)가 정본이다. `drawnVertices`는 선택적 필드라 이전 파일도 읽힌다.
- 면 단위 선택은 polygon·multipolygon type에서 상단바로 전환해 쓴다. footprint는 제외한다. 선분(개체) 단위로 feature를 만드는 캔버스 경로는 property type 레이어에서 없앴다.
- 원인: `ClosedPolygonFinder.split`이 모든 선분 쌍을 비교했다(C5 도면 선분 74,916개, 약 28억 회). 격자로 비교 상대를 좁혀 4.96초 → 0.033초, 조각 136,352개·면 9,764개로 결과가 같다. `SnapPointExtractor`도 격자로 바꿨다. 예전 개체 상자 필터는 곡선 기준점만 써서 곡선이 부풀어 나간 부분의 교차를 놓쳤다(C5에서 교차 27개 추가). 개체 상자 필터를 되돌리면 결과가 완전히 같음을 확인했다.
- 면·점·점 진행률 분모를 `DerivedGeometry`로 묶어 백그라운드에서 계산한다. 층 캐시는 "SVG 파싱·색인"과 "면·점" 열쇠를 나눠 제외 개체·임시 문만 바뀌면 파싱을 다시 하지 않는다. 레이어 생성·보조 개체 제외는 메인 스레드에서 면을 다시 찾지 않는다. 자체점검에서는 결과 확인을 위해 그 자리에서 계산한다.
- 다각형 진행률 막대를 점 기준으로 바꿨다. 분모는 보조 개체를 포함한 전체 꼭짓점·교점 수, 분자는 태깅된 점과 제외로 사라진 점이다. 면 단위로 저장해도 점 기준이다.
- 측정(Release, CLI): C5 도면 첫 층 준비 약 5.4초 → 0.56초, unit 레이어 생성 메인 스레드 약 5초 정지 → 0.02ms, 보조 개체 제외 후 재계산 백그라운드 약 0.6초. 실제 사용자 프로젝트(개체 16,738개) 첫 층 준비 5.7초 → 1.44초.
- 자체점검: 기본 입력·C5 SVG 모두 6/6 모드 통과(SVG ALL PASS 584항목, Building 27/27, Project 23/23, Document open 24/24, Routing 100/100, Drawing Loading 54/54). 실제 사용자 프로젝트 입력에서는 Drawing Loading 1건("층 선택·캐시는 저장 데이터 변경 없음")이 실패하며 develop에서도 같은 실패가 재현되는 기존 문제다. 입력 원본 SHA-256은 검사 전후 동일하다.
- 실제 화면의 클릭·드래그·키 입력은 확인하지 않았다(CLI 검사만). 수동 확인 대상으로 남긴다.

## 2026-10-15 — #36 .imdfrnt 프로젝트 열기 진입점

- 구현 전에 [이슈 #36](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/36)을 등록하고, PR #33이 병합된 develop에서 `fix/#36-project-open-entry`를 만들었다.
- 빈 캔버스에 `프로젝트 열기 (.imdfrnt)…` 버튼을 추가했다. macOS File 메뉴와 앱 안의 파일 메뉴도 같은 이름으로 맞추고 ⌘⇧O를 유지했다. 파일 선택 창에도 프로젝트 확장자와 복원되는 도면·층·노드·연결을 안내한다.
- 기존 `openProject()`와 비동기 검증·미저장 작업 확인 경로를 재사용했다. 중복 열기 방지와 이전 `.imdfproj` 선택·취소·손상 입력 보호를 유지한다.
- Xcode Release(arm64·x86_64) 빌드·엄격한 서명·diff 검사를 통과했다. 문서 폴더의 실제 v4 백업을 읽기 전용으로 사용해 6/6 CLI 모드 통과: SVG ALL PASS, Building 30/30, Project 23/23, Document open 24/24, Routing 100/100, Drawing Loading 61/61. 실제 백업의 6개 층·노드 72개·연결 87개와 메타데이터, v4→v5 왕복·클라이언트 출력 보존을 검증했다. 원본 SHA-256은 검사 전후 동일하다.
- 최신 앱을 `--project-qa-directory /private/tmp/IMDFrnt36-UI-QA`로 실행했다. UI 자동화는 `Sky Computer Use native pipe startup failed`로 연결되지 않아 실제 버튼·파일 메뉴·파일 선택 창 클릭과 화면 배치는 수동 확인 대상으로 남긴다.
- 빌드 로그: `/private/tmp/imdfrnt-issue36-build.log`. 회귀 결과: `/private/tmp/imdfrnt-issue36-self-tests.log`, `/private/var/folders/y_/53_320qj4pqcgw5hp41cgr2m0000gp/T/imdfrnt-self-tests.Jrm6EV`.

## 2026-10-15 — #32 Xcode 프로젝트 추가

- 구현 전에 [이슈 #32](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/32)에 목표·작업 목록·완료 조건을 기록하고, 병합된 develop에서 `chore/#32-xcode-project`를 만들었다.
- `IM-DFrnt/IM-DFrnt.xcodeproj`에 macOS 앱 타깃과 공유 `IM-DFrnt` Scheme을 추가했다. 기존 `Sources/IMDFrnt`의 Swift 파일 101개를 직접 컴파일하며 폴더 동기화로 새 Swift 파일도 포함한다. Swift 6·macOS 14 설정을 유지한다.
- Xcode에서 `IM-DFrnt → My Mac → ⌘R`로 실행할 수 있다. 로컬 ad-hoc 서명을 사용하며 개발자 Team을 지정하지 않고 Debug·Release를 빌드했다. Debug 서명의 `get-task-allow`도 확인했다.
- 앱·문서 연결 정보를 `Configuration/Info.plist`로 옮겨 Xcode와 `build-app.sh`가 공유한다. 기존 리뷰 수정 앱의 메타데이터와 완전히 같고, 두 Xcode 앱과 Swift Package 앱에서 `.imdfrnt`/`.imdfproj`·SVG/PNG/JPG 등록, 실행 파일명, 샘플 리소스와 서명을 확인했다.
- Xcode 27.0에서 프로젝트·Scheme 인식, Debug 및 Release(arm64·x86_64) 빌드, 기존 Swift Package 번들 빌드와 엄격한 서명 검사를 통과했다. Swift 컴파일 경고는 없고 Xcode의 AppIntents 메타데이터 추출 생략 경고만 남는다. 최초 sandbox 빌드는 SwiftUI 매크로 실행이 제한돼 실패했으며, 같은 명령을 sandbox 밖에서 실행해 통과했다.
- Xcode Release 앱에서 기본 입력으로 CLI 6/6 모드 통과: SVG ALL PASS, Building 27/27, Project 23/23, Document open 24/24, Routing 100/100, Drawing Loading 49/49. 로그: `/private/tmp/imdfrnt-issue32-xcode-self-tests.log`, `/private/var/folders/y_/53_320qj4pqcgw5hp41cgr2m0000gp/T/imdfrnt-self-tests.g2sctE`. 빌드 로그: `/private/tmp/imdfrnt-issue32-xcode-debug.log`, `/private/tmp/imdfrnt-issue32-xcode-release.log`, `/private/tmp/imdfrnt-issue32-spm-build.log`.
- Xcode에 프로젝트 열기를 요청했다. UI 자동화는 `Sky Computer Use native pipe startup failed`로 연결되지 않아 Xcode의 실제 ⌘R 조작·앱 화면은 별도 확인 대상이다. CLI 성공을 GUI 확인으로 표시하지 않는다.

## 2026-10-15 — PR #27 P2 리뷰 반영

- 코드 변경 전 #20에 두 P2의 재현·수정·완료 조건을 기록했다. 기존 PR #27과 `feat/#20-level-drawing-management`에서 수정한다.
- Finder SVG/이미지 열기에서도 비동기 검증 후 기존 미저장 변경 확인을 실행한다. 기준점만 수정한 작업도 저장·폐기·취소를 거치며, 취소/저장 창 취소/손상 입력에서는 기준점·도면·복구본·Undo 기록을 바꾸지 않는다. 명시적 층 도면 가져오기의 기존 확인 흐름을 유지한다.
- 준비된 도면과 색인을 설치한 뒤 `refreshOpenRingGaps()`를 호출한다. 캐시 없는 Undo에서 도면이 nil일 때 비워진 경고를 다시 계산한다.
- 실제 수정 전 코드에 회귀 검사를 추가해 기본 입력 40/49 PASS(9개 실패)로 두 문제를 재현했다. SVG·PNG·JPG 확인 누락과 취소 시 데이터 변경, 저장 취소 무시/저장 누락, 실제 틈 2곳인데 경고가 0개인 Undo가 실패했다. 수정 후 같은 기본 입력은 49/49 PASS다.
- Swift 6 Release 빌드(경고 없음), 번들 서명, diff 검사를 통과했다. 실제 C5 폴더·현재 사용자 테스트 프로젝트로 6/6 CLI 모드 통과: SVG ALL PASS, Building 34/34, Project 23/23, Document open 24/24, Routing 102/102, Drawing Loading 46/46. 도면 검사 수는 입력 층 수에 따라 달라진다.
- 로그: `/private/var/folders/y_/53_320qj4pqcgw5hp41cgr2m0000gp/T/imdfrnt-self-tests.LUiJi2`; 동일 기본 입력의 수정 전/후 로그: `/private/tmp/imdfrnt-pr27-review-before-test.log`, `/private/tmp/imdfrnt-pr27-review-fixed-test.log`. 검사 앱: `/private/tmp/IMDFrntPR27Review-Fixed.app`.
- 검사는 실제 비동기 열기·Undo 명령과 확인 응답 주입을 사용한다. Finder 이벤트/네이티브 alert 버튼을 실제로 클릭해 검증한 것으로 표시하지 않는다.

## 2026-10-14 — #20 층별 도면·#26 전환 버퍼링

- 구현 전 #20·서브 이슈 #26에 작업 목적과 완료 조건을 기록하고, 병합된 develop에서 `feat/#20-level-drawing-management`를 만들었다. #18·#19는 닫힌 상태를 유지한다.
- 실제 사용자 테스트 프로젝트의 SVG(3,442개/1,563개 개체)를 확인했다. Light SVG의 기존 전환 로직은 매번 5.29~5.34초가 걸렸다. 캐시된 실제 층 재전환은 약 0.3~0.5ms이며 재파싱·파생 계산이 증가하지 않는다. 화면 첫 프레임까지의 시간이 아닌 선택 명령·도면 모델 적용 시간이다.
- 최초 준비는 약 5.3초이고 백그라운드에서 수행한다. 메인 액터의 10ms 간격 확인 작업이 424회 실행되어 응답성을 확인했다. 도면보다 먼저 층 메타데이터·탭바를 적용하고 마지막 선택만 반영한다.
- SVG/이미지 읽기·파싱과 도면 색인·Path·다각형 진행률을 캐싱했다. 도면 캐시는 최대 6개/추정 128 MiB, 준비 작업은 최대 2개이며 인접 층을 미리 준비한다. 교체·삭제·Undo·프로젝트 교체에서 오래된 비동기 결과를 막고 로딩 중 이전 층 색인을 비운다.
- IMDF 위의 SVG 참고 레이어와 건물 Footprint 배경을 분리했다. SVG 원문·파일명·층별 표시/불투명도와 건물 전역 Footprint 표시 설정을 v5의 선택적 필드로 저장한다. 원본 IMDF geometry·투영·노드 좌표와 기존 파일 이전을 유지한다. 참고 도면 삭제는 빨간 버튼·확인·취소·Undo를 지원한다.
- Swift 6 언어 모드 Release 빌드·ad-hoc 서명·diff 검사를 통과했다. 원래 UI 코드의 actor/Sendable 경고를 정리했고 최종 빌드 경고는 없다. SVG ALL PASS, Building 34/34, Project 23/23, Document open 24/24, Routing 102/102, Drawing Loading 30/30으로 6개 모드 모두 종료 코드 0이다. C5 폴더와 실제 사용자 테스트 프로젝트를 읽기 전용으로 사용했다.
- 로그: `/private/var/folders/y_/53_320qj4pqcgw5hp41cgr2m0000gp/T/imdfrnt-self-tests.AhTbpG`. 앱: `/Users/dd/Applications/IM-DFrntIssue20.app`. [사용법과 수동 확인](docs/projects/LEVEL_DRAWINGS.md)을 기록했다.
- UI 자동화가 `Sky Computer Use native pipe startup failed`로 연결되지 않고 테스트 창도 조회하지 못했다. 실행 프로세스와 모델·명령 검증을 실제 버튼 입력·화면 검증으로 해석하지 않는다. 원본 복구본과 분리한 QA 복사본으로 앱을 실행하며 실제 탭·Picker·레이어·삭제 알림 확인은 미완료로 남긴다.

## 2026-10-08 — 삭제 확인 통일·선택 엣지 Delete

- 구현 전에 기존 [UI 이슈 #16](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/16)에 요청과 완료 조건을 추가하고 `feat/#16-floor-node-ui`에서 이어서 진행했다.
- 층 우클릭 메뉴를 빨간 `층 삭제`로 표시하고 말줄임표를 없앴다. macOS 네이티브 메뉴에 빨간 attributed title과 휴지통을 지정하며, 메뉴가 열린 동안 캔버스의 키보드 처리를 중지한다. 셀 전체의 클릭 영역과 접근성 선택·메뉴 동작을 유지한다.
- 층·노드·엣지·길찾기 기준점 및 도면 편집의 개체·Anchor·임시 문 삭제 버튼을 빨간 레이블/아이콘으로 통일하고 공통 확인 alert를 거치게 했다. 선택한 노드·엣지의 Delete/Forward Delete도 같은 확인을 요청하며 취소가 기본 버튼이다.
- 확인 요청은 대상 ID와 프로젝트 ID를 고정한다. 취소·중복 입력·선택 변경·문서 전환으로 다른 데이터를 삭제하지 않으며, 확정한 엣지는 양 끝 노드를 남긴다. 삭제 확정은 한 번의 실행 취소로 복구한다. Anchor 삭제도 기존 실행 취소 기록을 사용하도록 연결했다.
- 릴리즈 빌드·서명 검사 통과. 실제 C5 폴더·ZIP 포함 Routing 104/104 PASS, 기존 회귀 ALL PASS. 확인 취소/확정·중복 요청·대상 변경·문서 전환·저장/재열기·텍스트 입력 보호·실행 취소/다시 실행을 검사했다.
- 실제 UI에서 선택한 엣지의 Delete → alert → 취소, 연결 삭제 버튼 → 확정(25→24개, 노드 유지) → ⌘Z 복구를 확인했다. 노드 삭제 alert의 연결 4개 안내와 취소, 활성화된 `층 삭제` 메뉴의 말줄임표 제거·2층 alert·취소도 확인했다. 캔버스 노드·연결에 비시각적 접근성 선택 동작을 추가했다.
- 메뉴·버튼의 빨간색 자체를 최종 화면으로 확인하는 작업은 화면 캡처 오류로 미완료다. 실제 메뉴 동작과 명시적 빨간색 지정은 확인했으며, 기존 셀 여백 클릭·전체 카테고리 변경·Option 유지 드래그의 실제 입력 검증과 함께 이슈를 열어 둔다.
- 최신 앱을 실행해 둔 상태다. 검증 후 자동 저장 routing 전체가 이번 작업 전 백업과 동일하다: 층 6개·노드 17개·연결 25개. 로그: `/tmp/imdfrnt-delete-alert-routing-20261008.log`, `/tmp/imdfrnt-delete-alert-regression-20261008.log`.

## 2026-10-08 — 층 셀 선택·우클릭 삭제 확인·노드 색상

- 구현 전에 기존 [UI 이슈 #16](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/16)에 요청과 완료 조건을 추가했다. `feat/#17-command-node-export`의 `ed9dd4c`에서 `feat/#16-floor-node-ui`를 만들었다.
- 층 셀 전체에 클릭 영역을 지정하고 상시 휴지통 버튼을 없앴다. 우클릭의 `층 삭제…`를 선택하면 층 이름·노드 수·층간 연결 삭제 범위를 안내하는 alert가 뜨고 취소/삭제를 선택한다. 기존 층·노드·연결 삭제와 실행 취소를 재사용한다.
- 노드 색상을 일반 통로·교차점 파랑, 출입구 초록, 계단 주황, 엘리베이터 보라, 목적지 분홍으로 구분한다. 카테고리 메뉴도 같은 색상을 표시한다. 저장·내보내기의 카테고리 문자열과 선택 광택·핀 크기·하단 ID는 유지한다.
- 릴리즈 빌드 및 서명 검사 통과. 실제 C5 폴더·ZIP 포함 자체 검사 83/83 PASS, 기존 회귀 ALL PASS. UI에서 층 선택·우클릭 메뉴·삭제 alert·취소를 확인하고, 검증용 빈 층의 삭제 확정·실행 취소를 확인한 뒤 층 추가 자체도 되돌렸다.
- 화면에서 파랑·초록·주황 핀과 하단 ID를 확인했다. 좌표 클릭 자동화의 `noWindowsAvailable` 오류 및 이후 사용자 화면 변경 감지로 셀의 빈 여백 클릭과 보라·분홍을 포함한 카테고리 변경의 실제 입력 검증은 미완료로 기록한다.
- 최신 앱을 실행했다. 검증 후 자동 저장본의 routing 전체가 백업과 동일하며 기존 6개 층·노드 18개·연결 26개를 보존했다. 로그: `/tmp/imdfrnt-floor-node-routing-20261008.log`, `/tmp/imdfrnt-floor-node-regression-20261008.log`.

## 2026-10-07 — Command 클릭 노드 추가·클라이언트 출력 점검

- 구현 전에 컨벤션에 맞춘 [이슈 #17](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/17)을 등록했다. 담당자 `logichoon-redo`, 라벨 `enhancement`, 작업 브랜치 `feat/#17-command-node-export`다.
- 모든 노드 편집 도구에서 ⌘+클릭으로 현재 층에 노드를 추가한다. 일반 클릭은 선택, 기존 핀의 ⌘+클릭도 선택만 하고 중복 생성·연결을 하지 않는다. ⌘+드래그는 노드 이동·추가와 화면 이동을 하지 않으며 Option 드래그 연결을 유지한다. 입력 시작 시 modifier를 기억해 마우스를 놓기 전에 Command를 놓아도 클릭 의도를 유지한다.
- 지정한 클라이언트 원격 브랜치를 fetch해 최신 HEAD가 `8274d1d`임을 다시 확인했다. 그래프 로더·경로 탐색 구현은 없고 최소 GeoJSON fixture 및 헤더를 읽는 테스트가 있다.
- 내보내기는 JSON 기반 `routing-graph.geojson`이다. 실제 생산 코드로 샘플 및 C5 지도 노드 2개·연결 1개를 내보내고 클라이언트 fixture의 필수 필드·타입·좌표·연결 ID 참조를 검사했다. C5 출력은 원본 IMDF 층 UUID·ordinal도 일치한다. 형식 변경이 필요한 불일치는 없었다. 이름·메타데이터·추가 카테고리 해석과 실제 경로 탐색은 클라이언트 로더 구현 이후 검증한다.
- 자체 검사 83/83, 기존 회귀 ALL PASS, 릴리즈 빌드 통과. 사용자 자동 저장본을 별도 백업했으며 검사 실행은 자동 저장본을 읽거나 덮어쓰지 않는다.
- 출력 검사기는 잘못된 노드 참조·위경도 순서·접근성 타입·층 ordinal·schema_version 타입의 오류 입력 5개를 모두 거절했다. 서명 검사 통과 및 사용자 routing 저장 데이터가 백업과 동일함을 확인했다.
- 최종 UI 확인·재실행은 자동화 도구의 `Sky Computer Use native pipe startup failed`가 재연결 뒤에도 반복되어 완료하지 못했다. Command modifier의 클릭 처리 자체는 자체 검사로 확인했고 실제 마우스 입력 경로는 코드 검토 범위다. 업데이트 앱 번들은 빌드 완료 상태다.
- 재사용 가능한 출력 검사기 `scripts/validate-routing-export.py`와 [사용법](docs/routing/NODE_EDITOR.md)을 추가했다.

## 2026-10-06 — 노드 표시와 드래그 연결 UX 개선

- [이슈 #16](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/16)에 관련 UI 요청을 하나로 묶었다. 이슈를 먼저 기록하라는 요청 이후의 추가 변경은 등록 후 진행했고, 이후 작업 규칙을 `AGENTS.md`에 남겼다.
- `C6 GitHub 작업 컨벤션`에 맞춰 #16의 본문을 목표·작업 목록·완료 조건으로 정리하고 담당자 `logichoon-redo`와 `enhancement` 라벨을 지정했다. 구현과 자동 검증 완료 항목은 체크하고 실제 UI 확인 2개는 미완료로 유지한다. 향후 이슈 작성 규칙에도 본문 형식·체크박스·담당자·라벨을 반영했다.
- 핀을 화면 기준 지름 8pt로 줄이고 선택 시 크기 변경 없이 주변에 파란빛을 표시한다. 짧은 UUID는 핀 하단에 8pt·50% 불투명도로 표시하고 이름은 위에 표시한다. 줌·회전에도 표시 크기와 글자 방향을 유지한다. 표시 ID 접두사가 겹치면 구분되는 길이까지 늘리며 원본 UUID를 바꾸지 않는다.
- Option + 핀 드래그로 포인터를 따라오는 연결선을 표시하고 대상 노드에서 놓으면 연결한다. 연결 중 노드를 이동하지 않으며 빈 곳·자기 자신에 놓기와 Escape는 취소한다. `노드 연결` 도구의 일반 드래그와 층간 두 번 클릭도 유지한다.
- 연결 미리보기는 저장·실행취소 기록에서 제외하고 실제 연결만 한 번 기록한다. 삭제·층 전환·문서 전환·실행취소에서 임시 연결을 정리한다.
- 실제 C5 IMDF 폴더·ZIP을 포함한 자체 검사 70/70 통과, 기존 회귀 검사 ALL PASS. 실제 UI에서 핀 선택·연결 도구 드래그·빈 곳 취소·연결 실행취소를 확인했다. 자동화 도구는 Option을 누른 채 드래그하는 입력을 지원하지 않아 해당 modifier 입력 자체는 실제 UI 검증에서 제외했다.
- 하단 ID 변경을 포함한 최종 릴리즈 빌드·서명 검사 통과. 최신 앱에서 저장된 IMDF를 다시 열었고 사용자 노드 2개와 전체 routing 저장 데이터가 검사 전 백업과 동일함을 확인했다. 최종 화면 캡처는 도구가 창을 왜곡해 반환해 하단 글자의 시각 검증에 사용하지 못했다.
- [사용법과 출력 계약](docs/routing/NODE_EDITOR.md).

## 2026-10-06 — 완성된 IMDF 입력 후 노드 편집

- 사용자가 노드 편집은 IMDF를 만든 이후의 작업이라고 명확히 했다. SVG·이미지를 먼저 열던 진입 흐름을 수정했다.
- `IMDF 불러오기…`(⌘⇧I)로 ZIP·폴더 또는 그 안의 manifest.json/level.geojson을 열면 층별 지도와 실제 층 UUID·ordinal을 가져오고 노드 편집 화면으로 바로 이동한다.
- 원본 level·unit·fixture·opening·amenity 등의 지오메트리를 재사용한다. Polygon 구멍과 MultiPolygon을 유지하고 amenity의 unit 참조를 층으로 연결한다. 모든 층이 같은 표시 좌표계를 공유한다.
- IMDF 위경도로 노드를 바로 내보내므로 수동 기준점이 필요 없다. 지도와 가역 좌표 변환을 프로젝트 버전 4에 내장하고 기존 버전 2·3 작업을 읽는다. IMDF 재열기는 노드 화면으로 진입한다.
- ZIP은 파일을 디스크에 풀지 않고 필요한 항목만 읽는다. 가져오기는 백그라운드에서 수행하고 입력 오류 시 현재 작업을 유지한다. 새 IMDF는 새 프로젝트로 열어 이전 작업 파일을 덮어쓰지 않는다.
- 실제 클라이언트 C5 IMDF 폴더·ZIP(6개 층) 포함 자체 검사 57/57 통과, 기존 회귀 검사 ALL PASS. 실제 UI에서 ZIP 선택·층별 지도·노드 2개 배치·연결·GeoJSON 저장을 확인했고 출력의 위경도 및 실제 level ID를 검사했다. UI 검사 도구의 일시적 시간 초과는 화면 관찰로 정상 가져오기를 확인했다.
- 현재는 ordinal이 중복되지 않는 건물 하나의 IMDF를 지원한다. 클라이언트 그래프 로더·길찾기 실행은 이전 기록과 같이 별도 작업이다.
- [사용법](docs/routing/NODE_EDITOR.md).

## 2026-10-06 — 길찾기 노드 편집

- 사용자의 요청으로 자동 정합 구현을 기존 코드에서 분리했다. 폐기 전 최종 코드는 로컬 `archive/georef-prototype-2026-10-06` (`e18c542`)에 보관하고, `8da60ab`에서 `feat/routing-node-editor`를 시작했다.
- 기존 `CanvasView`와 좌표 변환·확대·이동, 실행취소, 프로젝트 저장·자동 저장을 재사용했다. 기존 태깅 작업은 별도로 유지한다.
- 층별 원본 SVG·PNG·JPG 불러오기, 클릭으로 노드 추가·선택, 이름·카테고리·JSON 메타데이터 편집, 드래그 이동, Delete, 연결선 선택·삭제, 양방향 연결, 계단·엘리베이터 층간 연결을 구현했다.
- 노드 삭제는 연결을 함께 정리하고 실행취소로 복원한다. 텍스트 편집 중 Delete는 글자만 지운다. 층 삭제도 실행취소 가능하다. 연결 없는 노드 및 그래프의 분리된 그룹 수를 표시한다.
- 클라이언트 `level.geojson` 또는 `IndoorMapDocument`의 층 목록을 가져와 UUID·ordinal을 맞출 수 있다. 층별 좌표 기준점으로 실제 WGS 84 좌표를 만든다.
- 전체 층의 그래프를 클라이언트 테스트 fixture에 맞춘 GeoJSON으로 내보낸다. 확인한 클라이언트 `feature/indoor-routing-foundation` (`8274d1d`)에는 아직 그래프 로더·경로 탐색 구현이 없으므로, iOS에서 길찾기 실행까지 검증했다고 주장하지 않는다.
- 프로젝트 버전 3에 그래프·층별 도면·기준점을 저장하며 버전 2 파일도 읽는다. 새 화면에서 합성 데모를 자동 적재하지 않는다.
- 검증: 릴리즈 빌드·서명 검사, 노드 자체 검사, 기존 회귀 검사, 실제 UI의 클릭·이름 편집·텍스트 Delete·노드 Delete·연결·실행취소·PNG 원본 불러오기·새 층 분리. 클라이언트 fixture의 필수 키·타입·연결 참조도 출력과 비교했다.
- [사용법과 출력 계약](docs/routing/NODE_EDITOR.md). 아래 자동 정합 기록은 이전 작업의 이력이다.

## 2026-09-30 — 백로그 등록

### 완료

- 사용자 제공 AUTO_GEOREF_TASK 명세와 이후 제품 범위 확정을 바탕으로 [백로그](docs/georef/BACKLOG.md)를 작성했다.
- GitHub 이슈 #6–#15를 등록했다. 목표, 작업 체크리스트, 완료 조건, 선행 의존 관계, 라벨과 담당자를 지정했다.
- 기존 관련 이슈 #4의 원래 요청은 보존하고, 백로그를 후속 목록으로 연결한다.
- 방향키 기반 후보 검토, 보류·해당 없음, 최종 적용·실행 취소 동작을 #13에 기록했다.

### 최초 등록 당시 구현 상태

아래는 10개 이슈로 등록했던 시점의 기록이다. 이후 기능 단위 통합 결과는 이 문서의 최신 항목과 BACKLOG.md에서 관리한다.

| 단계 | 이슈 | 상태 |
|---|---|---|
| M0 | #6 | 미착수 |
| M1 | #7 | 미착수 |
| M2 | #8 | 미착수 |
| M3 | #9 | 미착수 |
| M4 | #10 | 미착수 |
| M5 | #11 | 미착수 |
| M6 | #12 | 미착수 |
| M7 UI | #13 | 미착수 |
| M7 IMDF | #14 | 미착수 |
| M7 Raster | #15 | 미착수 |

### 측정 지표

이번 작업은 백로그 등록 단계다. 매칭 성공률, 자동 수락 오답률, 모호성 탐지율, 처리 시간과 실제 위치 정확도는 아직 측정하지 않았다.

`feature/anchor-map-automation`의 기존 보조 정합 프로토타입(commit `ed8250b`)은 별도 선행 작업이다. 일반 지도와 후보 생성 경험을 제공하지만, 이 백로그의 독립 패키지·고정 metric scale·다중 가설·모호성 게이트 완료로 계산하지 않는다.

### 명세와 제품 범위의 차이

- 전체 건물 도면만 대상으로 하고 부분 홀 정합은 제외한다.
- 출입구 대응과 실내·실외 경로 연결은 클라이언트 범위다. 출입구 및 관련 도로 단서, 출입구 로더를 필수 항목에서 제외한다.
- 출입구 단서 평가 대신 독립 방위 단서를 사용하는 대칭 평가를 #10에 기록했다.
- M7을 UI 통합, IMDF 출력, 래스터 입력으로 나눴다.
- `created` 시각과 결정성 계약은 M0에서 구현 전에 확정한다. Provider 응답·정책 및 validator 차이는 해당 단계에서 확인한다.

### 다음 단계

[#6 — 독립 georef 패키지와 좌표계·Provider·캐시 기반](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/6). 이번 백로그 작업에서 구현은 시작하지 않았다.

## 2026-09-30 — 저장소 이관

- 이후 작업 저장소를 `adap-c6-fingerprint/IMDFrnt`로 변경했다. 현재 로컬 경로는 `/Users/dd/Downloads/IMDFrnt`다.
- 기존 레거시 및 앵커 보조 자동화 커밋이 새 저장소에 동일한 해시로 존재함을 확인했다.
- 누락된 백로그 이슈 10개를 새 저장소 #6–#15로 재등록했다. 담당자·라벨·완료 조건·선행 관계를 유지했다.
- 이전 백로그·진행 문서 커밋을 보존하고 활성 링크를 새 저장소로 바꿨다. #4에는 새 이슈 목록을 연결한다.
- 이전 HTML UX 개념 시안은 원본 참고 자료로 보존했다. 현재 범위에서 출입구 대응이 제외된 사실을 함께 기록했다.
- [이관 기록](docs/georef/MIGRATION.md)에 커밋, 이슈와 로컬 경로를 정리했다.

이관은 코드 보존 및 기록 복원 작업이다. 매칭 성공률·runtime 측정이나 새 엔진 구현 상태는 변경하지 않았다.

## 2026-09-30 — 기능 단위 통합과 기존 지도 조회 재사용

### 판단 근거

- 사용자가 이슈 분할이 많다고 지적했고, 지도 데이터 연동은 이미 구현되어 있다고 알려줬다.
- `feature/anchor-map-automation`의 `ed8250b` 소스를 확인했다. `PlaceSearch.swift`의 MapKit 검색, `BuildingFootprints.swift`의 OSM API 0.6 조회, `AnchorScreen.swift`의 일반 지도 및 조회 연결이 존재한다.
- 이 기능을 재개발하는 독립 이슈 대신 기존 결과를 엔진에 연결하고 필요한 검증을 보완한다.

### 백로그 조정

- 활성 백로그를 핵심 기능 3개와 후속 확장 1개로 통합했다.
- #7–#12를 #6의 내부 작업·완료 조건으로 옮기고 통합 사유를 기록해 닫았다. 닫힘은 백로그 통합에 따른 것이며, 구현 상태는 #6에서 관리한다.
- #13의 선행 관계를 #6으로 바꿨다. #14는 #13, 후속 #15는 #14에 연결한다.
- M0–M7의 상세 검증 순서는 문서와 기능 체크리스트에 유지한다.
- M5를 기존 MapKit/OSM 경로의 Candidate·provenance 연결 및 정책·캐시·실패 처리 검증으로 조정했다. 추가 Provider 개발은 이번 필수 범위에서 제외한다.

| 활성 이슈 | 기능 | 상태 |
|---|---|---|
| #6 | 전체 건물 자동 정합 엔진 | 미착수, 기존 지도 조회 재사용 |
| #13 | 자동 후보·방향키 검토 UX | 미착수 |
| #14 | 확정 결과 저장·IMDF 출력 | 미착수 |
| #15 | 래스터 입력 확장 | 후속·미착수 |

소스 확인과 백로그 정리만 진행했다. 신규 정합의 정확도·runtime 지표는 아직 측정하지 않았다.

## 2026-09-30 — #4 중복 종료

- #4의 도면 정렬·기준점 지정 범위가 #6(자동 정합 엔진)·#13(후보 검토 UX)으로 통합되었음을 확인했다. 출력은 #14에서 관리한다.
- #4에 `duplicate` 라벨과 `Duplicate of #6` 및 관련 범위 설명을 남기고 닫았다. 기존 본문·검토 기록을 보존했다.
- 활성 이슈의 #4 참조는 ‘통합 전 요청’으로 바꿨다. #4를 진행 중인 상위 작업으로 관리하지 않는다.
- 닫힘·라벨·대체 이슈 링크를 GitHub API로 확인했다. 구현 상태와 정확도·runtime 측정 상태는 유지한다.

## 2026-10-13 — #18 새 프로젝트 생성·기존 작업 저장

- `feat/#18-new-project-save`를 #16이 머지된 `develop`의 `c32cc62`로 맞추고 구현 전 #18에 계획·담당자·라벨을 기록했다.
- 파일 메뉴·⌘N으로 새 프로젝트를 만들고 document·feature·Anchor·routing·선택·임시 편집·Undo/Redo를 초기화한다. 새 UUID와 현재 schema version 4를 기록한다.
- 도면 없는 프로젝트 저장/재열기를 지원한다. 빈 프로젝트에 도면·IMDF를 넣을 때 ID와 저장 위치를 유지한다.
- 새 프로젝트·다른 입력 열기·창 닫기·종료에서 저장/저장하지 않음/취소를 확인한다. 저장 창 취소·파일 쓰기 실패는 기존 데이터를 유지한다.
- 프로젝트 이름·저장 상태를 표시한다. 자동 저장은 복구본만 갱신하며 저장하지 않고 종료한 변경을 다음 실행에서 복원하지 않는다.
- 최종 검사: Project 23/23 PASS, 실제 C5 IMDF 폴더·ZIP 포함 Routing 104/104 PASS, 기존 회귀 ALL PASS, 릴리즈 빌드·서명 검사 통과. 사용자 복구 파일 SHA-256 보존 확인.
- 정상 ZIP 입력은 실제 클라이언트 C5 IMDF 폴더를 압축해 검증했다. 처음 지정한 다운로드 ZIP은 IMDF의 level.geojson이 없는 다른 형식이라 거절됐으며 원본은 변경하지 않았다.
- UI 도구의 `Sky Computer Use native pipe startup failed`로 실제 파일 메뉴·저장 대화상자·종료 입력과 캡처는 미확인이다. 완료로 표시하거나 이슈를 닫지 않는다.
- 실행 앱: `/private/tmp/IM-DFrntIssue18Final.app`. 상세 사용법과 검사 절차: `docs/projects/PROJECT_LIFECYCLE.md`.

## 2026-10-13 — #18 리뷰 보완: Finder 프로젝트 열기

- [#18에 리뷰 보완 목표와 완료 조건](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/18#issuecomment-6137561168)을 먼저 기록했다. `.imdfrnt` UTI만 있고 앱의 프로젝트 문서 타입과 외부 파일 이벤트가 없던 P2 지적을 수정했다.
- `.imdfrnt`·이전 `.imdfproj`를 Editor/Owner 문서로 등록하고 SVG·PNG·JPEG 연결을 유지한다. 환경 연결 전 요청을 대기하고, 파일 메뉴와 Finder의 검증·미저장 확인·복구 처리를 공유한다.
- 현재 프로젝트 재요청은 미저장 편집을 유지하며 가져오기·모달 중에는 기다린다. 여러 파일 요청은 부분 교체 없이 거절한다.
- 문서 열기 23/23 PASS, 프로젝트 23/23 PASS, 실제 C5 폴더·ZIP 포함 Routing 104/104 PASS, 기존 회귀 ALL PASS, 릴리즈 빌드 통과. 일반 설치 경로의 별도 번들 ID·복구 경로에서 기본 파일 연결과 앱 시작/실행 중의 실제 시스템 파일 전달을 확인했다. 검증용 등록과 앱은 정리했다.
- Finder UI의 물리적 더블클릭과 저장 확인 버튼 입력은 도구 연결 오류로 미확인이다. 시스템 파일 전달 검증과 구분한다.
- Finder 수정은 #18 브랜치/PR에서만 커밋한다. #19는 갱신된 #18을 기준으로 #19 기능 커밋만 비교하도록 유지한다.
- 로그: `/private/tmp/imdfrnt-finder18-open-test.log`, `imdfrnt-finder18-project-test.log`, `imdfrnt-finder18-routing-test.log`, `imdfrnt-finder18-regression-test.log`.
## 2026-10-13 — #19 공통 건물·Level 관리

- [#19](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/19)에 구현 시작·완료 조건을 먼저 기록하고 `feat/#19-building-level-management`를 #18 브랜치에서 생성했다. #18은 아직 develop에 병합되지 않아 이 브랜치는 #18에 의존한다.
- `.imdfrnt` 버전 5에서 건물 전역 IMDF 정보와 공통 Level을 저장한다. 각 층이 도면·GeoJSON Feature·기존 태깅·기준점·노드·층 내부 엣지를 가지며 층간 엣지는 프로젝트에 보관한다. RoutingGraph는 기존 노드 화면·내보내기용 호환 뷰다.
- 상단 공통 층 선택과 건물·층 관리 화면을 추가했다. 이름·shortName·ordinal·Level UUID 편집, 중복 차단, 확인 후 층 삭제 및 Undo/Redo를 지원한다. 첫 SVG 입력과 복구에서 이미 작성한 건물 정보를 보존한다.
- IMDF 폴더·ZIP의 JSON/GeoJSON과 manifest, 원본 Feature ID·geometry·properties·참조·unknown fields·collection header를 보존한다. 화면용 SVG는 재열기 시 실제 geometry로 재구성하며 기존 노드 좌표 변환을 유지한다. 기존 v4 노드 전용 파일에 없던 원본 Feature 메타데이터를 SVG에서 복원하는 기능은 포함하지 않는다.
- 건물·Venue·주소 properties와 Manifest의 JSON 편집, 실제 위경도 Polygon/MultiPolygon으로 Footprint 생성·수정·삭제·미리보기와 Undo/Redo를 추가했다. SVG 참고 레이어 표시/투명도는 #20, 독립 DraftShape 마우스 작도는 #21에서 진행한다. 전체 IMDF ZIP 내보내기 UI는 후속 범위다.
- 최종 검증: Building 37/37 PASS, Project 23/23 PASS, 실제 C5 폴더·ZIP 포함 Routing 104/104 PASS, 기존 회귀 ALL PASS. C5 6개 층·unit 167개·건물 1개·Footprint 2개와 원본 GeoJSON 왕복을 확인했다.
- 사용자 실제 v4 복구본의 6개 층·노드 72개·연결 87개를 읽기 전용으로 이전해 데이터·UUID·메타데이터·연결 및 클라이언트 GeoJSON 출력 바이트가 동일함을 확인했다. 원본 복구 파일 SHA-256은 검사 전과 같다.
- 앱: `/private/tmp/IM-DFrntIssue19.app`. 로그: `/private/tmp/imdfrnt19-building-final.log`, `imdfrnt19-project-final.log`, `imdfrnt19-routing-final.log`, `imdfrnt19-regression-final.log`. 실제 UI 입력 검증은 `Sky Computer Use native pipe startup failed`로 미완료여서 이슈를 열어 둔다.
- [사용법과 저장 구조](docs/projects/BUILDING_LEVELS.md).

## 2026-10-13 — 팀 리뷰 요청에 따른 #18·#19 통합 PR

- 리뷰어는 stacked PR을 없애고 #18 변경을 포함한 하나의 PR로 다시 리뷰해 달라고 요청했다. 사용자가 통합 PR 방향을 선택해 이전 이슈별 PR 유지 방안을 변경했다.
- #18 생성·저장 및 Finder 수정, #19 건물·공통 Level 관리 커밋을 보존하고 PR #23의 기준을 develop로 변경한다. PR #24는 PR #23으로 대체한다. #18 브랜치와 분리 전 #19 로컬 백업을 유지한다.
- 통합 코드 검증: Building 37/37 PASS, Document open 23/23 PASS, Project 23/23 PASS, 실제 C5 폴더·ZIP 포함 Routing 104/104 PASS, 기존 회귀 ALL PASS, 릴리즈 빌드·서명 통과. 사용자 복구 파일 SHA-256 보존 확인.
- 남은 UI 확인은 완료로 표시하지 않는다. #20 참고 레이어·투명도, #21 DraftShape 마우스 작도는 후속 범위다.
- 로그: `/private/tmp/imdfrnt-integrated-building.log`, `imdfrnt-integrated-document-open.log`, `imdfrnt-integrated-project.log`, `imdfrnt-integrated-routing.log`, `imdfrnt-integrated-regression.log`.

## 2026-10-13 — PR #23 리뷰 후속: UUID·검사 진입·빌드 경고

- [기존 #19에 후속 목표와 완료 조건](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/19#issuecomment-6140485244)을 먼저 기록했다.
- non-optional UUID의 항상 참인 nil 비교를 제거했다. 발급 대장과 재열기 대장에서 optional UUID를 실제로 꺼내고, 기록이 없으면 실패하며 원래 UUID와 같은지 비교한다.
- 검사가 AppKit/LaunchServices 초기화 뒤에 시작해 리뷰 환경에서 exit 134로 재현되지 못한 피드백을 반영했다. CLI 검사 분기를 SwiftUI 앱 시작 전 진입점으로 옮기고 문서 검사의 NSApplication 초기화 의존성을 제거했다. 일반 앱은 SwiftUI 앱 진입점으로 연결한다.
- deprecated `onChange` 5곳을 두 인자 API로 변경했다. Release 빌드 로그 경고 없음, ad-hoc 서명 검사 통과.
- 기본 sandbox CLI 실행으로 5개 모드 모두 exit 0: 기본 Building 27/27·Document open 24/24·Project 23/23·Routing 100/100·기존 회귀 ALL PASS. 실제 C5 폴더·ZIP·기존 v4 입력을 포함하면 Building 37/37·Routing 104/104 PASS. 사용자 원본 복구 파일 SHA-256 유지.
- `IM-DFrnt/run-self-tests.sh`가 모드별 종료 코드·전체 로그·환경·바이너리 SHA-256을 남긴다. 문서 CLI 검사는 공통 요청 처리와 선언·입출력을 확인하며 실제 Finder 이벤트·UI 버튼 입력은 별도 검증이다.
- [재현 명령과 검증 범위](docs/projects/SELF_TESTS.md). UI 도구 연결은 다시 `Sky Computer Use native pipe startup failed`로 실패했으며 건물·층 관리 UI 확인은 완료로 표시하지 않는다.

## 2026-10-17 — 직접 저장 제거, 프로젝트별 단일 자동 저장 파일

- 사용자 결정: 직접 저장(작업 저장·다른 이름으로 저장)을 없애고 프로젝트마다 자동 저장 파일 하나만 쓴다. 파일은 `~/Library/Application Support/IM-DFrnt/새 도면_YYMMDD_HHmm.imdfrnt`이며 같은 분에 겹치면 `_2`를 붙인다. 빈 프로젝트는 내용이 생기기 전까지 파일을 만들지 않는다.
- `IMDF 불러오기…` 바로 아래에 `.imdfrnt 불러오기…`(⌘⇧O)를 두고, 자동 저장 폴더에서 시작하는 선택 창을 연다. 앱 메뉴·상단 파일 메뉴·왼쪽 사이드바·빈 캔버스·길찾기 화면에 적용했다.
- 전환·종료 전 "저장할까요?" 확인을 없애고 자동 저장 후 진행한다. 저장 실패 시에만 취소/계속을 묻는다. 예전 공용 복구본 `autosave.imdfrnt`는 첫 실행에서 `새 도면_…` 이름으로 옮겨 연다.
- 검사는 실제 자동 저장 폴더 대신 임시 폴더를 쓴다. 기본 sandbox 6개 모드 exit 0: 기존 회귀 ALL PASS, Building 27/27, Project 22/22, Document open 23/23, Routing 100/100, Drawing Loading 54/54. 실제 UI 버튼 입력은 미확인.
- [사용법](docs/projects/PROJECT_LIFECYCLE.md).

## 2026-10-17 — #53 프로젝트 선택 화면과 저장 후 전환

- [이슈 #53](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/53): 앱을 켜면 지난 작업이 자동으로 열려 프로젝트를 고를 수 없고, `.imdfrnt`를 불러오면 지금 프로젝트에 합쳐지는지 바뀌는지 알 수 없다는 피드백.
- 프로젝트 선택 창(`App/ProjectPicker.swift`)을 추가했다. 자동 저장 폴더의 프로젝트를 최근 수정 순으로 보여 주고 층 개수·층 이름·수정 시각과 `현재 열림`/`지난 작업`을 표시한다. 층 이름은 SVG·편집 상태를 건너뛰는 가벼운 디코딩으로 백그라운드에서 읽는다.
- 앱 시작 시 지난 작업을 자동으로 열지 않고 선택 창을 띄운다. 저장된 프로젝트가 없으면 빈 시작 화면, Finder로 파일을 열며 시작하면 선택 창 없이 그 파일을 연다. 진입점은 파일 → 프로젝트 선택…(⌥⌘O)과 상단 프로젝트 이름.
- 다른 프로젝트 열기·새 프로젝트 만들기는 `‘A’ 프로젝트를 저장하고 ‘B’ 프로젝트로 전환할까요?`를 묻는다(선택 창·.imdfrnt 불러오기·Finder 공통, 빈 새 프로젝트는 묻지 않음). 전환 후 배너로 이전 프로젝트가 따로 저장되어 있음을 알리고, 선택 창에서 취소하면 목록으로 돌아간다.
- 자체점검(레포 밖 scratch 빌드): Project 24/24, Document open 23/23(.app 번들), Building 27/27, Routing 100/100, Drawing Loading 54/54, 기존 회귀 ALL PASS. 실제 화면의 선택 창·전환 확인은 미확인.

## 2026-10-17 — #49 개체 편집 (Control 클릭으로 점 교체·끼우기)

- [이슈 #49](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/49) 작업 목록에 엔진 디버깅 5번을 추가했다. 선택한 순서대로만 잇던 방식은 중간 점을 지우고 새 점을 찍으면 새 점이 맨 끝에 붙어 도형이 꼬였다.
- 작성 중인 도형의 점마다 순번(1, 2, 3 …)을 표시한다(모든 레이어). 이미 찍은 점을 Control+클릭하면 그 점과 뒤 순번이 흐려지고, 새 점을 찍은 뒤 흐린 점을 누르면 새 점이 빠진 순번 자리에 들어간다. 같은 점을 두 번 누르면 빼지 않고 그 뒤에 끼운다. 이어지면 흐린 점이 모두 살아난다.
- 이어 붙이지 않고 Control을 떼면 그 자리가 끊긴 채 남는다(`PointDraft.breaks`). polygon·multipolygon은 경고하고 닫기를 막으며, 끊긴 뒤쪽 점을 Control로 두 번 누르면 다시 잇는다. 아무것도 바꾸지 않고 떼면 그대로 둔다. 편집 상태는 `PointDraft` 안에 있어 cmd+z로 함께 되돌아간다.
- 저장된 polygon·multipolygon 도형도 꼭짓점을 Control+클릭하면 그 링을 작성 중 도형으로 꺼내 같은 방식으로 고친다. 이어진 채 Control을 떼면(또는 시작점·Return) 원래 feature의 링을 바꾸고, ESC는 원래 도형을 그대로 둔다. Control을 누른 채로는 꼭짓점 끌기를 시작하지 않는다.
- 자체점검(레포 밖 scratch 빌드): 기존 회귀 ALL PASS(개체 편집 13항목 신규), Project 24/24, Document open 23/23(.app 번들), Building 27/27, Routing 100/100, Drawing Loading 54/54. 실제 화면의 Control+클릭 입력(우클릭으로 바뀌지 않는지 포함)은 미확인.

## 2026-10-18 — #49 MultiPolygon 지정·구멍, 면 단위 기준 변경

- [이슈 #49](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/49) 작업 목록에 추가. IMDF 스펙은 unit·section·geofence·level·footprint·fixture·venue의 geometry를 `POLYGONAL`(Polygon 또는 MultiPolygon)로 정하는데, 앱은 fixture 외에는 링 하나만 만들 수 있었다(위키 src10·src15).
- 우측 패널 feature 카드에서 저장한 다각형을 MultiPolygon으로 지정한다(`FeatureGroup.multiPolygon`, 선택적 필드라 이전 파일 호환). 지정 중에 다각형을 닫거나 면을 저장하면 그 feature에 링으로 더한다. 구멍은 따로 저장하지 않고 링끼리 감싸는 관계로 정한다(`RingNesting`, 홀수 번 감싸이면 구멍): 기존을 감싸면 기존이 구멍, 기존 안쪽이면 새 것이 구멍. 어긋나게 겹치거나 같은 모양이면 거절하고, 꼭짓점 이동·Control 편집으로 겹치게 되는 것도 막는다. 다각형이 하나일 때만 Polygon으로 되돌린다.
- 캔버스는 링을 짝홀 규칙으로 칠해 구멍이 비어 보이고, 다각형을 받는 중인 feature는 점선 테두리다. GeoJSON은 바깥 다각형마다 바로 안쪽 구멍을 안쪽 링으로 붙인 MultiPolygon으로 내보낸다(링 방향은 기존처럼 정렬하지 않음).
- 면 단위는 도면 개체(SVG 선분)가 아니라 **저장된 개체의 경계로 막힌 면**만 고른다(`App/SavedFeatureFaces.swift`). 상단바에서 '현재 레이어 기준 / 모든 레이어 기준'을 고르며, 지금 레이어에 같은 모양으로 저장된 면은 고를 수 없다. 이렇게 만든 feature는 면 기록 없이 링만 두어 점으로 그린 도형처럼 꼭짓점 이동·Control 편집이 된다. footprint는 종전대로 면 단위 대상이 아니다.
- 기존 면 단위 자체점검(제외 모드·드래그·저장·fixture 묶기·진행률)은 도면 개체 면을 전제로 해서 저장된 개체 기준으로 다시 썼다. 자체점검: 기존 회귀 ALL PASS(MultiPolygon 9항목·면 기준 6항목 신규), Project 24/24, Document open 23/23(.app 번들), Building 27/27, Routing 100/100, Drawing Loading 54/54. 실제 화면 확인은 미확인.

- 추가(#49): 점 단위에서 이미 개체로 저장된 꼭짓점도 다시 골라 새 개체를 만든다. 예전에는 도면의 꼭짓점·교점만 찍혀, ⌥로 만든 점이나 저장된 개체 경계로 만든 면의 꼭짓점은 "꼭짓점·교점이 아닌 자리"로 막혔고 옆 unit과 같은 좌표를 공유할 수 없었다(같은 층 unit 사이 틈·겹침 금지). 이제 도면 점과 이 층 모든 개체의 꼭짓점 중 가장 가까운 점에 그 좌표 그대로 붙는다. 자체점검 2항목 추가.

- 추가(#49): unit 레이어 상단바(점·면 단위 모두)와 도구 메뉴에 '빈틈·겹침' 토글을 두었다. 켜면 같은 층 unit 사이의 빈틈은 빨간 점무늬, 겹침은 빨간 빗금으로 도면에 칠하고 개수를 보여 준다(`App/UnitCoverage.swift`, CoreGraphics 교집합·합집합·차집합). 빈틈은 이 층에 level 다각형이 있으면 level에서 unit 전체를 뺀 곳, 없으면 unit에 둘러싸인 빈 곳이다. MultiPolygon unit의 구멍은 짝홀 규칙으로 빠진다. 0.03 폭처럼 무늬가 안 들어가는 얇은 틈도 보이게 빨간 테두리를 함께 긋는다. 자체점검 6항목 추가. 실제 화면 확인은 미확인.

- 추가(#49): 캔버스의 일련번호 태그(unit-014 등)에 마우스를 올리면 그 개체를 주황색(카드를 펼쳤을 때와 같은 강조색)으로 칠하고, 떼면 초록색으로 돌아간다. 태그는 Canvas에 그린 그림이라 그릴 때 태그 사각형을 기억해 두고 `onContinuousHover`로 마우스 위치를 판정한다. 모든 레이어에 적용된다. 실제 화면 확인은 미확인.

## 2026-10-18 — #38 모든 층을 합친 IMDF 아카이브 내보내기

- [이슈 #38](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/38)에 목표·작업 목록·완료 조건을 채웠다. 기존 내보내기는 지금 층·지금 type 하나의 `.geojson`이었는데, IMDF는 type 하나의 파일에 모든 층을 담고 `level_id`로 층을 가린다.
- `Export/IMDFArchive.swift`: 모든 층의 feature를 `{type}.geojson`으로 합쳐 `manifest.json`과 함께 ZIP 최상위에 담는다(`/usr/bin/zip -j`, 불러오기의 `/usr/bin/unzip`과 짝). 규격은 OGC 20-094 Archives·Manifest 절(위키 src18)과 C5 예제를 따랐다. 규격상 확장자는 `.zip`이라 저장 창 기본값도 `.zip`이다.
- 각 층의 level feature id는 그 층의 UUID이고, 같은 층 feature의 빈 `level_id`를 채운다. level의 빈 ordinal·name·short_name은 건물·층 관리 값, 건물·주소가 하나뿐이면 빈 `building_ids`·`address_id`도 채운다. 일련번호는 층마다 따로 매겨지므로 참조는 같은 층을 먼저 찾는다. `address`·`venue`는 필수 파일이라 비어도 넣고 경고한다. 새로 발급한 id는 층별 대장(`editing.ids`)에 되돌려 넣는다.
- 층별 Anchor 미지정·좌표 없음·level 다각형 없음/중복은 층 이름을 붙여 막는다. 가져온 IMDF의 feature·헤더·기타 파일은 그대로 싣는다. 진행률 팝업과 함께 백그라운드에서 만들며 도구 메뉴(⌘⇧E)·상단 파일 메뉴에 있다.
- 자체점검: 기존 회귀 ALL PASS(아카이브 10항목 신규), Project 24/24, Document open 23/23(.app 번들), Building 27/27, Routing 100/100, Drawing Loading 54/54. 레포 밖 임시 진단으로 C5 예제 IMDF를 불러와 그대로 내보내면 12개 파일 모두 feature id·내용이 원본과 같고 manifest의 `created`만 새 시각이다. 실제 화면 확인과 Apple 검증 도구 확인은 미확인.

## 2026-10-18 — fixture 똑같이 생긴 개체에 같은 태깅

- fixture 레이어 점 단위에서 점을 하나라도 찍으면 그 점이 놓인 도면 개체와 똑같이 생긴 개체(`보조 개체 제외`의 쌍둥이 판정 `twinKey`, 위치만 빼고 모양·스타일 비교)를 보라색으로 표시하고, 작성 중인 도형을 그 자리로 옮긴 모양을 점선으로 미리 보여 준다(`App/FixtureTwins.swift`). 상단바에 개수가 뜬다.
- 기준 개체는 찍은 점을 가장 많이 가진 개체(같으면 작은 쪽)다. 옮긴 자리에도 도면 점이 있어야 쌍둥이로 인정해, 옆 벽 점이 섞였거나 보조 개체로 뺀 자리는 빠진다. ⌥로 만든 점은 판정에 쓰지 않는다. 회전·반전된 모양은 찾지 않는다.
- 상단바 `닫을 때 함께 저장`을 켜고 도형을 닫으면 자리마다 개별 Polygon fixture를 함께 저장한다(실행취소 한 칸). 우측 패널 fixture 카드의 `같은 태깅으로 저장`은 카드의 속성을 그대로 가진 fixture를 자리마다 두고, 이미 같은 모양으로 저장된 자리는 속성만 맞춘다. 카드를 펼치면 그 자리가 보라 점선으로 보인다.
- 자체점검 7항목 추가.

## 2026-10-18 — 펼친 unit과 겹치는 unit 빨강, 이름표로 구멍 뚫기

- unit 레이어에서 우측 패널 카드를 펼치면 그 unit(주황)과 넓이 있게 겹치는 다른 unit을 빨간색으로 칠하고 이름표도 빨강으로 바꾼다. 벽만 맞닿은 이웃은 겹침이 아니다. 점·면 단위 모두 보인다(`App/UnitOverlapHoles.swift`).
- 펼친 unit이 MultiPolygon이면 빨간 이름표를 눌러 그 모양대로 구멍을 뚫는다. 통째로 안쪽이면 상대 링을 좌표 그대로 구멍으로 더하고, 걸쳐 있으면 겹친 만큼 깎아 낸다(CoreGraphics 차집합 뒤 꼭짓점·교점을 원래 좌표로 되돌림). MultiPolygon이 아니면 지정하라는 안내만 띄운다. 이름표를 누른 클릭은 점 찍기·면 고르기로 넘어가지 않는다.
- 자체점검 6항목 추가. 기존 회귀 ALL PASS, Building 27/27, Project 24/24, Routing 100/100, Drawing Loading 54/54(레포 밖 scratch 빌드). Document open(.app 번들)과 실제 화면 확인은 미확인.

## 2026-10-18 — unit 빈틈은 level 기준

- 사용자 결정: unit 빈틈은 **level 다각형에서 unit 전체를 뺀 곳**만 센다. level이 없을 때 unit에 둘러싸인 빈 곳을 빈틈으로 보던 대체 규칙을 없앴다(건물 바깥 테두리 쪽 빈 곳을 놓쳤다). level이 없으면 빈틈은 계산하지 않고 상단바에 `level 없어 빈틈 미계산`을 띄운다. 겹침은 종전대로 level과 무관하다. unit이 하나도 없으면 level 전체가 빈틈이다.
- 자체점검: 대체 규칙 항목을 level 기준 2항목으로 바꿨다. 기존 회귀 ALL PASS, Building 27/27, Project 24/24, Routing 100/100, Drawing Loading 54/54. 실제 화면 확인은 미확인.

## 2026-10-18 — unit 보조 선분·자르기·점 끼우기, level 기준 면 선택

- unit 레이어 점 단위 상단바에 도구 `그리기 / 보조 선분 / 자르기 / 점 끼우기`를 두었다(`App/UnitTools.swift`).
  - 보조 선분: 두 점을 찍어 긋는다(꼭짓점·교점에 붙고, 없으면 저장된 개체의 변·다른 보조 선분 위에 붙는다). feature가 아니라 내보내지 않고 면 단위의 모든 기준에서 면을 나누는 경계로만 쓴다. 층마다 `FeatureStore.guides`에 저장되어 실행취소·층 전환·프로젝트 파일을 함께 탄다(선택 키라 이전 파일 호환). Control+클릭으로 하나, 상단바 버튼으로 모두 지운다. 캔버스에 청록 점선으로 보인다.
  - 자르기: 점을 이어 선을 긋고 Return(또는 마지막 점 다시 누르기·상단바 버튼)으로, 선이 가로지른 unit을 조각마다 나눈다. 가장 큰 조각이 원래 unit을 잇고 나머지는 원래 속성을 그대로 가진 새 unit이다. 선이 닿지 않은 MultiPolygon의 다른 섬은 원래 unit에 남는다. 좌표는 CoreGraphics 계산 뒤 원래 꼭짓점·교점으로 되돌린다.
  - 점 끼우기: 저장된 unit의 변 위를 누르면 그 자리(변 위에 도면 점이 있으면 그 점)에 꼭짓점을 넣는다. 같은 변을 쓰는 이웃 unit에도 함께 넣는다.
- 면 단위 기준에 `level 기준`(unit 레이어 전용)을 추가했다. 경계는 level 외곽선·unit 경계·보조 선분·문 선이고, level 안에서 unit이 아직 덮지 않은 곳만 고를 수 있다. 면 추적이 섬을 구멍으로 빼지 못해 기존 '모든 레이어 기준'에서는 level 외곽선 면이 unit 전체를 덮은 채 잡혔다. 이제 안쪽에 떠 있는 unit 자리는 구멍으로 빠지고(그 자리를 눌러도 바깥 면이 잡히지 않음), 구멍 있는 면은 MultiPolygon unit으로 저장된다.
- 포스텍 도서관 2층(읽기 전용 진단): level 기준 면 4개(가장 큰 것은 복도 등 넓이 20,350·구멍 49개), 면 넓이 합 20,529 ≈ 빈틈 넓이 합 20,536, 계산 0.58초(경계가 같으면 캐시). 큰 면은 보조 선분으로 나눠 저장하는 것을 전제로 한다.
- 자체점검 17항목 추가. 기존 회귀 ALL PASS, Building 27/27, Project 24/24, Routing 100/100, Drawing Loading 54/54. 실제 화면 확인은 미확인.

- 추가: 점 단위 상단바가 unit 도구·긴 안내로 캔버스 폭을 넘어 오른쪽이 잘렸다(실제 화면 피드백). 넘치면 가로 스크롤로 바뀌는데 스크롤 막대가 숨겨져 잘린 것처럼만 보였다. 안내 문장을 둘째 줄로 내리고, `CanvasBarFit`이 스크롤할 때 스크롤 막대를 보이게 했다(모든 상단바 공통).

## 2026-10-18 — property type 레이어 투명도는 표시된 다각형 기준

- 사용자 결정: 레이어 투명도는 도면 원본 개체가 아니라 표시된 다각형 기준이다. property type 레이어(unit·fixture 등)의 슬라이더 값은 이제 도면 SVG 개체에 곱하지 않고, 그 type으로 저장된 다각형·선·점(점 단위 화면, 면 단위의 저장된 면, 다른 레이어 도형 표시)에 곱한다(`polygonOpacity(for:)`). 다른 레이어의 도형도 각자 자기 레이어 값을 따르고, 예전 방식(구성원 개체)으로 태깅한 개체 선은 주인 type 값을 따른다. 상위·하위 기본 레이어와 속성 필터 레이어는 종전대로 도면 개체 기준이다. 작성 중인 점·도면 꼭짓점·아직 고르지 않은 면·이름표는 투명도를 타지 않는다.
- 자체점검 2항목 추가. 기존 회귀 ALL PASS, Building 27/27, Project 24/24, Routing 100/100, Drawing Loading 54/54. 실제 화면 확인은 미확인.

- 추가(실제 화면 피드백): unit-114(level 기준으로 저장한 복도, 바깥 링 591점·구멍 49개 MultiPolygon)를 펼쳐도 면이 주황으로 칠해지지 않았다. 면 단위는 저장된 unit을 '같은 모양의 면'으로만 칠하는데, level 기준에서는 덮인 곳이 면에서 빠지고, 다른 기준에서는 구멍 때문에 면이 다른 모양으로 잘려 주인 없는 면(다시 고를 수 있는 면)이 됐다. ① 같은 모양이 아니어도 지금 레이어의 feature가 99% 이상 덮은 면은 그 feature의 면으로 본다(`coveringFeature`). ② 대응하는 면이 없는 저장된 feature는 면 단위에서 링을 직접 칠한다(펼치면 주황). 포스텍 도서관 2층: 현재 레이어 기준 고를 수 있는 면 14 → 4개(나머지는 이미 덮인 자리), unit-114가 면 1개를 가짐. 면 계산(경계가 바뀔 때만) 0.11 → 0.56초. 자체점검 3항목 추가, 6개 모드 통과. 실제 화면 확인은 미확인.

## 2026-10-18 — Shift+클릭으로 저장된 꼭짓점 빼기

- 저장된 도형에서 꼭짓점 하나만 빼는 방법이 없었다(Control 편집은 바꾸기·끼우기만, Delete는 작성 중 도형의 마지막 점만). 점 단위에서 작성 중인 도형이 없을 때 저장된 도형(지금 레이어)의 꼭짓점을 Shift+클릭하면 뺀다. 링이 3점 미만이 되거나, 꼬이거나, 같은 feature의 다른 다각형과 어긋나게 겹치면 빼지 않는다. 선(LineString)은 3점 이상일 때만 뺀다. 같은 점을 쓰는 이웃 도형은 건드리지 않고 알림으로 알린다. 실행취소 한 칸.
- 자체점검 5항목 추가, 6개 모드 통과. 실제 화면 확인은 미확인.

## 2026-10-18 — 고른 다각형의 점 순서(파랑), 빈틈·겹침 구분과 이름표

- 우측 패널에서 펼친 지금 레이어 feature의 꼭짓점을 파란 점으로 찍고(첫 점은 속 빈 큰 원) 순번 이름표를 단다. 링이 여럿이면 `링번호·순번`(예: 2·5)이다. 점·면 단위 모두, 화면에 보이는 점만 600개까지 단다. 저장된 도형을 Control로 고치는 중이면 작성 중 도형의 순번이 대신 보인다.
- 빈틈·겹침 표시: 빈틈은 노란 점무늬, 겹침은 빨간 빗금으로 색까지 나눴다. 조각마다 이름표를 단다 — `빈틈-01 · 넓이`, `겹침-01 unit-012×unit-031 · 넓이`(위→아래, 왼→오른 순 번호). 상단바 개수도 색을 나눴다. `UnitCoverage.Result.overlapPairs`로 겹침마다 두 unit을 기록한다.
- 자체점검 2항목 추가(점 순서 표시는 화면 그리기라 자체점검 대상이 아님), 6개 모드 통과. 실제 화면 확인은 미확인.

## 2026-10-18 — 포스텍 도서관 2층 겹침 정리·벽 structure unit, 실오라기 방지

- 사용자 결정으로 원본 프로젝트(`포스텍 도서관_261017_1651.imdfrnt`)를 레포 밖 일회성 처리로 고쳤다(앱 종료 상태, 처리 전 백업 보관). ① unit 겹침 8곳(모두 넓이 0.5 미만)을 두 unit 중 큰 쪽에서 깎았다(unit-005·011·017·022·057·063·086의 링만 바뀜, 좌표는 원래 꼭짓점·교점으로 되돌림). ② level 빈틈 안에 통째로 든 도면 면 중 평균 폭 3 미만(벽 두께 띠) 294개를 맞닿은 것끼리 묶어 category `structure` unit 176개(넓이 5,501)로 저장했다. 벽 unit이 기존 unit과 만든 넓이 0.002 이하 겹침 15곳은 벽 unit 쪽에서 깎았다. ③ 복도 등 나머지 빈틈 80곳(넓이 14,487)은 사용자 지시로 손대지 않았다. 결과: unit 274 · 겹침 0. 다시 열어 확인.
- 실오라기 원인(겹친 8쌍 실측): T자 접점에서 꼭짓점이 이웃 변에서 0.002~0.05 벗어남(7쌍), 같은 모서리를 0.01~0.02 떨어진 다른 점으로 찍음(2쌍). 방지(`App/SnapAlignment.swift`): 점을 찍을 때와 다각형을 저장할 때(점 그리기·Control 편집·면 단위 저장) 같은 type 이웃(unit은 level 포함)의 꼭짓점에서 0.1 안이면 그 꼭짓점, 아니면 변에서 0.1 안이면 변 위 투영점으로 맞춘다. 그 꼭짓점이 이웃 변 한가운데 놓이면 이웃 변에도 꼭짓점을 넣어 함께 쓰게 한다. 맞춘 결과가 꼬이면 원래 링을 쓴다. 알림에 맞춘 꼭짓점 수와 함께 고친 이웃을 덧붙인다.
- 자체점검 5항목 추가, 6개 모드 통과. 실제 화면 확인은 미확인.

## 2026-10-18 — #54 클라이언트용 지도·길찾기 데이터 묶음 Export

- [이슈 #54](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/54). 요구사항 문서(postech-library 요청 초안) E1~E7·5장을 기준으로 `도구 → 클라이언트용 묶음 내보내기… (지도+길찾기)`를 추가했다(`Export/ClientDataset.swift`). 계약 문서는 [`docs/routing/CLIENT_DATASET.md`](docs/routing/CLIENT_DATASET.md).
- 한 순간의 프로젝트 데이터로 `IMDFArchive.build`와 `RoutingExporter.collection`을 함께 돌려 `<dataset-id>/IMDFData/`(앱이 읽는 8종은 항상)·`routing-graph.geojson`·`dataset.json`을 만든다. 최종 바이트를 다시 읽어 통합 검증(노드 level_id·ordinal ↔ level.geojson, 간선 끝점, 자기 연결·길이 0, 파일 안 ID 중복, ring 닫힘·좌표 범위, 필수 venue·level)하고 SHA-256을 기록한다.
- 서가 매핑은 편집기에 없어 만들지 않고 `shelves_sha256: null`로 표시한다. 앱의 schema 1은 `shelves_sha256`이 필수라 호환되지 않으므로 **schema 2**로 붙였다(합의 필요, 앱 쪽 adapter 필요).
- 적용 안 된 입력(작성 중 도형 등) 안내, 기존 폴더는 교체 확인, 임시 폴더에서 완성 후 한 번에 교체(실패 시 기존 보존), 백그라운드 처리. 새로 발급한 feature id는 프로젝트에 되돌려 넣는다.
- 자체점검 17항목(합성 2개 층·같은 층/층간 연결·해시·재Export 바이트 동일·막는 조건·교체 보존) + 실제 C5 입력 1항목. 6개 모드 통과(Routing 117/117), 실제 C5 입력 포함 Routing 120/120. C5는 알려진 타입 간 UUID 중복(amenity·unit) 1건을 경고한다. 실제 화면 확인·postech-library 앱에서 읽기는 미확인.

## 2026-10-18 — #52 우측 패널 category 필터, category 한국어 표기

- [이슈 #52](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/52)에 작업 목록을 더해 재사용했다(같은 category UI 기능).
- category 필터(`UI/CategoryFilterBar.swift`): 우측 패널 카드 목록 위에서 이 레이어에 저장된 category(개수, null 포함)를 여러 개 고르면 그 feature만 카드 목록에 남고, 캔버스에서도 그 feature의 도형(점 단위 도형·면 단위 면·대응 면 없는 저장 도형·다른 레이어 도형·예전 방식 구성원 개체)과 이름표만 그린다. 머리글 개수는 `보이는 수 / 전체 수`. 모든 레이어에 따로 적용되고, 실행취소 대상이 아니라 `AppEnvironment.categoryFilters`에 두며 새 프로젝트·층 전환 때 비운다. 걸러진 카드가 펼쳐져 있으면 접는다. 빈틈·겹침 표시는 필터와 무관하다.
- category 한국어 표기(`Model/CategoryLabel.swift`): 드롭다운 값 전부(unit·amenity·opening·section·geofence·fixture·footprint·level·building·venue)에 `한국어(영어)`로 보인다. 저장·내보내기 값은 영어 원문 그대로다. 같은 값이 type마다 뜻이 다르면 type별로 둔다(opening `service` = 서비스 출입구). 검색 칸은 한국어로도 찾는다("화장실" → `restroom` 계열). occupant는 자유 입력이라 원문만 보인다. 번역은 화면용 이름이며 스펙 원문 정의가 아니다.
- 사용자 지시로 포스텍 도서관 2층의 Claude가 만든 `structure` unit 176개(unit-117~292)를 원본 프로젝트에서 지웠다(레포 밖 일회성 처리, 앱 종료 상태, 백업 `포스텍 도서관_261017_1651.before-structure-delete-261018.imdfrnt.bak`). 다른 데이터의 참조는 없었다. unit 번호 카운터를 남은 최대 번호(116)로 되돌렸다. 남은 것: unit 113 · opening 26 · fixture 8 · footprint 1 · level 1. 위 "겹침 정리"의 사용자 unit 7개 수정은 되돌리지 않았다.
- 사용자 지시로 같은 프로젝트의 미세한 빈틈을 이웃 unit에 흡수시켰다(레포 밖 일회성 처리, 앱 종료 상태, 백업 `포스텍 도서관_261017_1651.before-sliver-absorb-261018.imdfrnt.bak`). 계기: unit-086 주변의 얇은 틈 중 일부가 벽 자리 빈틈과 이어져 있어 나중에 벽 unit으로 함께 태깅될 수 있었다. 기준: level에서 unit 전체를 뺀 빈틈 중 **폭 0.1 미만**인 부분(앱 스냅 허용치와 같은 값, 가장 얇은 벽 띠 약 0.5보다 충분히 작다). 벽 빈틈에 붙은 얇은 조각은 각진 모서리를 보존하는 열림 연산(mitre)으로 떼어 냈다. 20곳(벽 빈틈에 이어진 것 15, 막힌 것 5, 넓이 합 2.05, 가장 큰 것 0.76)을 맞닿은 길이가 가장 긴 unit에 합쳤다 — unit-022·023·032·048·057·066·085·086·087·090·092·097·106. 링 수·방향은 그대로이고, 꼭짓점은 기존 좌표로 되돌렸다. 결과: 빈틈 넓이 10,941.57 → 10,939.52, 겹침 쌍 0 → 0, unit-086에 닿은 빈틈은 벽 자리 빈틈 하나뿐. 폭 10⁻⁹ 이하의 계산 오차 수준 4곳은 남는다(앱 최소 넓이 기준 미만). 앱에서 다시 열어 화면 확인은 미확인.
- 추가(실제 화면 피드백 "이름표를 눌러도 선택이 안 된다"): 캔버스 이름표 클릭은 펼친 unit과 겹친 빨간 이름표만 처리하고 나머지는 점 찍기·면 고르기로 넘기고 있었다. 이제 빨간 이름표가 아니면 그 feature를 고른다(우측 카드를 그것만 펼침, 다시 누르면 접음, 모든 레이어). 점 단위에서 이름표 바로 밑 꼭짓점의 끌기가 먼저 잡히던 것도, 누른 자리가 이름표면 꼭짓점 끌기를 시작하지 않게 막았다. 고른 카드가 목록 밖이면 우측 패널이 그 카드까지 스크롤한다. 기존 점검 "이름표 클릭이 아닌 unit은 종전 클릭으로 넘긴다"를 새 동작으로 바꾸고 1항목 추가.
- 추가(#38, 실제 화면 피드백 "level id에 층 관리에서 설정한 층이 들어가지 않는다"): 우측 패널 level_id 칸은 이 층에 그린 level feature의 일련번호를 고르는 칸이었고, 층 관리의 층과 연결되지 않았다. IMDF 아카이브는 level feature id를 층 UUID로 바꾸면서 빈 level_id만 채워, 일련번호를 골라 둔 feature는 level_id가 실제 level id와 어긋났다. 이제 level_id는 **지금 층(층 관리)의 UUID(소문자)로 자동**이다 — 패널은 층 이름·ordinal·UUID를 보여 주고 편집을 막는다. `GeoJSONExporter.levelID`가 있으면 슬롯 값과 상관없이 level_id와 level feature id를 그 값으로 쓴다(아카이브·type별 `.geojson` 공통). 층 관리 층이 없으면 종전대로다. 자체점검 1항목 추가.
- 추가(#31, 실제 화면 피드백 "도면 정렬에서 도면이 지도 위에 안 뜬다"): '이 층을 지도 가운데에 올리기'가 지도 범위와 상관없이 눌려, 처음 열린 전국 보기에서 누르면 도면 크기를 화면 폭의 절반으로 잡아 대한민국 중심(위도 35.86·경도 127.79)에 폭 약 7km로 올라갔다(포스텍 도서관 2층 저장값으로 확인, 1단위 = 8.4m). 다시 들어오면 그 중심을 300m로 비춰 빈 곳만 보였고, 이미 올린 층은 다시 올릴 길이 없었다. 화면 가로 폭이 3km(`AppEnvironment.maxPlacingWidthMeters`)를 넘으면 올리기를 막고 확대 안내를 띄운다. 층 카드에 '지도 가운데로 가져오기'를 두어 이미 올린 층을 지금 지도 가운데·화면 폭에 맞춰 되찾는다(회전·순서·표시·투명도 유지, 확정 해제, 실행취소 한 칸, 잠긴 층은 불가). 자체점검 3항목 추가.
- 추가(#31, 실제 화면 피드백 "도면이 정렬되면 아무 버튼도 안 눌린다 — 위성/지도 전환·돌아가기·확대축소·지도 이동 모두, 하단 바만 눌림"): 손 동작 겹(`interactionLayer`)이 도면 테두리 모양 전체를 `contentShape`로 잡았는데, 도면이 화면보다 크면(위 7km 도면) 모양이 지도 밖으로 나가고 SwiftUI는 뷰 밖이라도 모양 안이면 클릭을 받는다. 지도 겹은 화면 순서상 상단 바들 위·하단 바 아래라 창 위쪽 버튼이 전부 막혔다. 받는 자리를 지도 화면과의 교집합으로 잘랐다. 도면 위의 스크롤·핀치는 손 동작 겹이 먹어 지도까지 가지 않았으므로, `MapAlignMapController`가 로컬 이벤트 모니터로 지도가 직접 받지 않는 자리의 스크롤·핀치를 지도에 넘긴다. 도면이 화면을 덮으면 끌 자리가 없어, ⌥ 끌기·Anchor 찍기 모드 끌기·잠긴 층 끌기는 도면 위에서도 지도를 옮긴다(끌지 않고 누른 것은 종전 클릭). 화면 동작이라 자체점검 대상이 아니다 — 6개 모드 회귀 통과(document-open은 위와 같은 3항목), 실제 화면 확인 필요.
- 사용자 지시로 남은 빈틈 2곳(unit-085·unit-086에 붙은 것, 넓이 0.0034·0.0136)을 같은 방식으로 흡수했다(레포 밖 일회성 처리, 앱 종료 상태, 원본이 시험 실행 뒤 바뀌어 최신본으로 다시 계산, 백업 `포스텍 도서관_261017_1651.before-sliver-absorb2-261018.imdfrnt.bak`). 층 빈틈 넓이 0.0170 → 0, unit 겹침 쌍 0 → 0, 다시 재 보면 얇은 빈틈 0곳.
- 추가(사용자 지시 "이름표를 누르면 category·이름을 지정할 수 있게, category가 필요한 모든 레이어"): 이름표를 눌러 feature가 골라지면 그 이름표에 작은 편집 창(`UI/FeatureTagEditor.swift`)이 뜬다. category 목록이 있는 레이어는 category(검색 칸, `한국어(영어)` 표기), 이름을 쓰는 레이어는 name(en·ko)을 담고, 칸은 우측 패널과 같은 `PropertySlotRow`라 저장·되돌리기도 같다. 다시 눌러 접거나 빨간 이름표로 구멍을 뚫으면 창을 닫는다. 자체점검 1항목(레이어별 칸 구성) 추가, selftest 732·building 28·project 25·routing 118·drawing-loading 55 통과. 실제 화면 확인 필요.
- 추가(실제 화면 피드백 "확대/축소가 너무 민감하고, category 검색·unit 선택·화면 이동 등에서 버벅임이 많다"): 포스텍 도서관 2층(도면 개체 64,006개, feature 157개)으로 재 보니(디버그 빌드) 개체 표시 상태 사전을 통째로 다시 만드는 데 324 ms가 걸렸고, 이름표 hover·카드 펼침·category 필터가 바뀔 때마다 이 사전을 버렸다. 또 그리기는 프레임마다 6만 개를 모두 돌았다(그리기 전 준비만 28 ms). 고친 것: (1) hover·펼침·필터는 해당 feature의 구성원·빌린 개체만 다시 판정(`refreshRenderStates(owners:)`, 324 → 0.07 ms), (2) 개체마다 읽던 지금 층·활성 레이어·`@Published` 저장소를 사전 만들 때 한 번만 읽기(`RenderStateContext`, 통째로 다시 만들기 324 → 24 ms), (3) 확대해 일부만 볼 때 격자(`SpatialIndex.drawIndices`)로 화면 안 개체만 돌기(화면이 도면의 25%·5%일 때 28 → 10·2 ms, 절반 넘게 보이거나 범위를 모르면 종전처럼 전체), (4) 면·겹침·빈틈 캐시가 매번 링·선분 전체를 모아 비교하던 것을 `geometryRevision` 번호로 먼저 확인, (5) 검색 칸 목록 거르기를 한 번만. 확대는 휠 한 줄 10%·한 번 최대 40%·핀치 그대로였던 것을 지수 배율(휠 한 줄 4%, 트랙패드 ⌘스크롤 점당 0.3%, 핀치 0.6배)로 바꾸고 한 번에 최대 16%로 묶었다. 자체점검 3항목(부분 갱신 = 통째 갱신, 확대 민감도, 화면 안만 그리기) 추가, selftest 734·building 27·project 24·routing 117·drawing-loading 54 통과. 실제 화면 확인 필요.
- 자체점검 4항목 추가. selftest·building·project·routing·drawing-loading 통과, document-open은 CLI 바이너리 직접 실행이라 Info.plist 3항목이 실패(번들 실행 환경 차이, 이번 변경과 무관). 실제 화면 확인은 미확인.

## 2026-10-19 — #31 지도 정렬 화면을 네이버 지도로

- 사용자 지시로 지도 정렬 화면의 지도를 MapKit에서 **네이버 지도 Web Dynamic Map v3**(WKWebView)로 바꿨다(`UI/MapAlign/AlignMapView.swift`, `UI/MapAlign/NaverMapPage.swift`). 장소 검색과 기존 Anchor 화면(1:1 찍기)은 종전 MapKit 그대로다.
- 일반 지도·위성·위성+이름은 `NORMAL`·`SATELLITE`·`HYBRID`. 도면 선·테두리·손잡이·Anchor·꼭짓점은 지도 안의 `OverlayView`(SVG)로 그려 지도 타일과 함께 움직인다(MapKit 오버레이와 같은 이유로 흔들림 없음). 도면 선은 처음 한 번만 SVG 경로로 넘기고(백그라운드에서 만듦) 정렬이 바뀌면 변환 행렬만, 투명도는 투명도만 바꾼다.
- 손 동작용 화면 ↔ 위경도 변환은 지도가 움직일 때마다 받은 범위(남서·북동)와 화면 크기로 Swift가 웹 메르카토르 식으로 계산한다(`NaverMapViewport`). 도면 위 스크롤은 지도로 넘기고, 트랙패드 핀치는 쌓아 두었다가 한 단계씩 확대한다(네이버 웹 지도는 정수 단계). ⌥ 끌기 등 지도 끌기는 시작 범위 기준으로 중심을 옮긴다.
- 인증: 스크립트는 `maps.js?ncpKeyId=<Client ID>`. Client ID는 상단 바 열쇠 버튼(또는 지도가 안 뜰 때 나오는 안내 칸)에서 넣고 이 Mac의 UserDefaults(`naverMapsClientID`)에만 저장한다 — 레포·프로젝트 파일에 키를 넣지 않는다. 페이지를 `http://localhost/`로 띄우므로 네이버 클라우드 콘솔 Application의 Web 서비스 URL에 `http://localhost`를 등록해야 한다. Client ID 없음·인증 실패(`navermap_authFailure`)·불러오기 실패를 나눠 안내한다.
- MapKit 때의 확대 한계 1m는 네이버 기본 최대 확대 단계로 바뀐다(실제 화면 확인 필요).
- 자체점검 8항목 추가(범위 읽기·화면 변환 왕복·메르카토르 세로·끌기 방향·잘못된 범위·SVG 경로·페이지 구성). 페이지 JS는 node에서 문법 검사와 가짜 `naver.maps`로 겹 추가·이동·투명도·순서·제거를 돌려 오류를 하나 고쳤다(붙이자마자 draw가 불리면 멈춤). selftest 743·building 28·project 25·routing 118·drawing-loading 55 통과, document-open은 위와 같은 3항목. 실제 네이버 키로 화면 확인은 미확인.

## 2026-10-19 — category를 정한 feature의 이름표

- 사용자 지시로 캔버스 이름표 중 category가 있는 feature는 진한 초록(`ClosedPolygonAppearance.categorizedLabelFill`) 바탕으로 칠하고, 이름표 바로 위에 작은 글씨(8pt)로 category를 `한국어(영어)` 표기로 단다(흰 바탕). 강조(주황)·겹침(빨강) 이름표가 우선이고, 누르는 자리는 이름표 그대로다. 모든 레이어 공통. 화면 그리기라 자체점검 대상이 아니다 — 5개 모드 회귀 통과, 실제 화면 확인 필요.

## 2026-10-19 — 네이버 지도가 '불러오는 중'에서 멈춤

- 실제 화면 피드백: 지도 정렬 화면이 "네이버 지도를 불러오는 중…"에서 넘어가지 않았다. 앱과 같은 페이지를 화면 없는 WKWebView로 띄워 재현했다(저장된 Client ID 사용, 키는 기록하지 않음).
- 원인 ①: 스크립트 주소에 callback 파라미터를 붙이면 지도 스크립트가 실행 중 오류("Script error.", 다른 출처라 내용 가려짐)를 내고 `naver` 객체가 생기지 않아, 준비 신호가 오지 않았다. → callback 없이 동기로 불러오고 페이지 `load` 때 직접 초기화한다.
- 원인 ②: 페이지 기준 주소가 `http://localhost/`라 지도가 타일·스타일을 `http://`로 요청했고 ATS가 막아, 확대 버튼·로고만 뜨고 지도가 검게 비었다. → 기준 주소를 `https://localhost/`로 바꿨다. 재현 환경에서 위성 타일이 내려오고 인증 실패 신호 없음을 확인했다.
- 지도 JS 오류(`window.onerror`)를 앱 로그로 넘기고, 15초 안에 준비 신호가 없으면 '불러오지 못함' 안내(Client ID 다시 넣기)로 바꾼다.
- 자체점검 1항목 추가(기준 주소 https), 페이지 구성 점검을 callback 없음으로 바꿈. selftest 통과. 실제 앱 화면 확인 필요.

## 2026-10-19 — 네이버 지도 위 지도·도면 조작이 모두 막힘

- 실제 화면 피드백: 지도 정렬 화면에서 지도 이동·확대·축소와 도면 이동·크기·회전이 하나도 되지 않았다.
- 원인: 포스텍 도서관 2층은 대한민국 중심(위도 35.86·경도 127.79)에 1단위 8.4m(폭 약 7km)로 올라가 있고 잠겨 있다(10-18 항목의 그 저장값). 화면이 그 도면 위 300m를 비추므로 도면 테두리가 지도 전체를 덮고, 그 위에 얹은 SwiftUI 손 동작 겹이 모든 입력을 먼저 받았다. 그 겹이 지도로 넘기던 스크롤은 WKWebView에 직접 넣으면 무시된다(화면 없는 WKWebView로 확인: 넘긴 스크롤 뒤에도 확대 단계 그대로). 도면은 잠금 때문에 움직이지 않는 것이 맞다.
- 고친 것: SwiftUI 미리보기·손 동작 겹을 없애고 **손 동작을 지도 페이지(JS)가 받는다**. 편집 중인 층의 테두리 겹을 기준으로 테두리 안(이동)·모서리(크기)·회전 손잡이를 누른 것만 가로채 앱에 알리고(끄는 동안은 프레임마다 한 번), 앱은 종전 계산으로 정렬을 바꿔 미리보기 값으로 지도 안 겹을 다시 그린다. 잠긴 층·⌥ 끌기·Anchor 찍기 모드의 끌기와 모든 스크롤은 네이버 지도가 직접 받는다. Anchor 찍기 모드에서 끌지 않고 놓으면 그 자리를 앱에 알려 종전처럼 꼭짓점·교점을 찍는다. 핀치는 종전처럼 앱이 확대 단계로 바꿔 넘긴다. 효과 없던 스크롤 넘기기와 지도 끌기 코드는 지웠다.
- 확인: 실제 네이버 지도(저장된 Client ID)를 띄운 화면 없는 WKWebView에서 네 경우 — 편집 가능한 층 테두리 안 끌기(도면 이동만 알림, 지도 그대로)·잠긴 층 끌기(지도 이동)·Anchor 모드 클릭(클릭 알림)·Anchor 모드 끌기(지도 이동) — 모두 기대대로. 자체점검 2항목 추가, selftest 752·building 27·project 24·routing 117·drawing-loading 54 통과. 실제 앱 화면 확인 필요.
- 사용 안내: 이 층은 잠겨 있고 엉뚱한 곳(폭 7km)에 있다. 층 카드에서 잠금을 풀고, 장소 검색으로 건물 근처로 간 뒤 '지도 가운데로 가져오기'를 누르면 화면 폭에 맞춰 다시 놓인다.

## 2026-10-19 — 캔버스 이동 렉

- 실제 화면 피드백: "지도(도면) 이동 렉이 다시 심해졌다", "이름표 편집 창에서 category 검색·고르기가 오래 걸린다", "name 칸에 글자를 칠 때 커서가 매우 느리다". 포스텍 도서관 2층(도면 개체 64,006개, feature 158개) 사본을 레포 밖에서 열고, 캔버스를 화면 없이 그려(ImageRenderer, 1400×900) 프레임과 Canvas 본문 구간을 쟀다(Release, `sample`로 함수별 확인). 원본 프로젝트는 읽기만 했다.
- 원인 ① 이동: 10-18의 '화면 안만 그리기'는 확대해 도면 절반 미만이 보일 때만 듣는다. 전체 보기~2배에서는 프레임마다 6만 개를 하나씩 그렸고, 개체마다 `@Published` 저장소(`segmentation`·`canvasBackground`·`moves.offsets`)를 여러 번 읽었다(읽을 때마다 Combine을 거침). 한 프레임 132 ms(Canvas 본문 120 ms = 상위 레이어 68 + 하위 기본 레이어 48, 이름표는 3 ms). 이름표 category 글씨 추가·편집 창 닻은 원인이 아니었다(이름표 전체 3 ms, 닻은 이동 중 바뀌지 않음).
- 원인 ② 편집 창: category·name 저장(`updateProperty`)이 글자 하나마다 280~310 ms. 속성만 바뀌어도 `features` 변경으로 점 진행률을 다시 셌고(`refreshPointProgress`), 그 안의 문 자리 안 개체 찾기가 opening 26개 × 개체 6만 개를 돌며 저장소를 읽었다(sample 3,188 중 3,186). 도형 편집(꼭짓점 하나)도 291 ms였다.
- 고친 것:
  - `UI/CanvasView.swift`: 개체 루프에서 읽는 저장소 값을 프레임 시작에 한 번만 읽는다. 도면 대부분이 보이고 옮기는 개체가 없으면 같은 색·굵기 선끼리 묶은 경로(`App/CanvasBatches.swift`)를 그린다 — 묶음은 표시 상태 사전 번호(`renderStateRevision`)·`geometryRevision`·배경·상위 레이어 투명도가 바뀔 때만 다시 만든다(약 12 ms). 하위 기본 레이어도 굵기별로 묶는다. 확대해 일부만 볼 때·개체 이동 중에는 종전처럼 하나씩 그린다. 면(fill)은 묶지 않는다(방향이 반대인 면이 겹치면 구멍이 생김).
  - `Geometry/SpatialIndex.swift`: 화면이 도면 범위의 절반 넘게 덮으면 후보를 모으지 않고 바로 '전체'로 답한다(버리던 후보 모으기 5 ms × 2).
  - `Store/Stores.swift`·`App/AppEnvironment.swift`: `features`가 속성만 바뀌었으면(`FeatureStore.propertyOnlyChanges`) 도형 번호·면·겹침·진행률 계산을 건너뛰고 그 feature 구성원의 표시 상태만 다시 판정한다. 구성원이 없는 feature(점으로 그린 것)의 hover·펼침은 표시 상태 사전을 건드리지 않는다.
  - `App/PointEditing.swift`: 문 자리 안 개체를 격자로 문 근처만 보고, 저장소는 한 번만 읽는다(실제 데이터에서 격자 결과 = 전부 훑은 결과 3,502·4,128·15,872개 확인).
- 수치(Release, 전 → 후): 전체 보기 프레임 132 → 22 ms(Canvas 본문 120 → 13), 2배 130 → 21, 4배 87 → 25, 10배 20 → 16. category 저장 283 → 0.1 ms 미만, name 한 글자 275 → 0.1 ms 미만, 꼭짓점 하나 고치기 291 → 24 ms. 이름표 클릭(카드 펼침) 0.1 ms 그대로.
- name 입력 판단: 우측 패널도 같은 칸(`PropertySlotRow`)으로 글자마다 저장하고, 실행취소는 같은 칸 연속 입력을 한 칸으로 합친다. 렉의 원인은 저장 시점이 아니라 저장 한 번의 비용이었으므로, 입력 중 저장을 미루지 않고 우측 패널과 같은 동작을 유지했다.
- 사용자 지시: name을 정한 feature는 이름표 위 글씨에 name도 함께 단다(`화장실(restroom) · 남자 화장실(Men)`, name은 ko·en이 다 있으면 `한국어(영어)`, 하나만 있으면 그것). category 없이 name만 있어도 단다. 이름표 색 규칙은 그대로(category가 있을 때만 진한 초록).
- 보이는 차이: 묶어 그릴 때 같은 묶음의 반투명 선(비활성 회색 등)이 겹친 자리가 두 번 칠해지지 않아 약간 덜 진하고, 면이 모두 선보다 먼저 칠해지며, 상태 표시(태깅·강조·빌림·선택) 선이 평범한 선 위에 온다.
- 자체점검 7항목 추가(`App/CanvasLagSelfTest.swift`: 속성만 바뀌면 도형 계산 생략, 일부 판정 = 통째 판정(category 필터), name 표시, 묶음이 보이는 개체를 빠짐없이 자기 묶음에 담고 상태가 같으면 재사용, 선택이 바뀌면 다시 만듦, 절반 넘게 보이면 바로 전체, 문 자리 격자 = 전부 훑기). selftest 750·building 27·project 24·routing 117·drawing-loading 54 통과(레포 밖 scratch 빌드). 실제 화면 확인 필요(실제 창에서의 이동 체감, 팝오버 열기·검색·고르기 체감, 이름표 위 name 글씨).

## 2026-10-19 — 이름표 편집 창 name 입력 지연

- 실제 화면 피드백(78bc418 뒤): 이름표 편집 창의 name 칸에 글자를 칠 때 지연이 심하다. 이번에는 저장 함수만이 아니라 **글자 하나 → 화면 반영 전체**를 쟀다. 포스텍 도서관 2층 사본을 열고 앱 전체 화면(`RootView`, 1600×1000)과 편집 창을 화면 없는 `NSHostingView`에 올려, name 저장 뒤 SwiftUI가 다시 계산·배치를 끝낼 때까지 시간과 화면별 본문 계산 횟수·시간을 쟀다(Release, 레포 밖 계측 사본).
- 원인: 칸이 글자 하나(한글은 자모 하나)마다 feature를 저장했고, 저장할 때마다 `AppEnvironment`가 바뀌었다고 알려 **앱 전체**를 다시 그렸다. 저장 자체는 0.1 ms(78bc418 효과, 그 전 277 ms)이지만, 다시 그리기가 한 글자에 38 ms였다(78bc418 전은 430 ms). 내역은 캔버스 다시 그리기 14 ms(그중 이름표 3.4 ms), 좌측 패널 3.7 ms, 그 밖의 배치·비교 약 20 ms이고, 화면 붙이기(래스터)는 따로다. 아무것도 바꾸지 않고 다시 그리라고만 해도 37 ms가 들어, 저장 내용과 무관한 '다시 그리기 한 번'의 값이다. 묶음(`CanvasBatches`)은 다시 만들지 않았고(구성원 없는 feature라 `renderStateRevision` 그대로), 실행취소 스냅샷 0.02 ms, 저장 상태 표시(`projectSaveStatus`) 0.0 ms, 우측 패널·편집 창 본문은 각 0.02 ms 미만이었다. 팝오버 닻은 입력 중 바뀌지 않는다.
- 고친 것(`UI/DraftTextField.swift`, `UI/RightSidebar.swift`): 속성 글자칸(`PropertySlotRow`의 name en·ko·문자열·숫자·쉼표 목록 칸)이 친 글자를 **칸 안에만** 들고 있다가, 0.4초 멈추거나 Return·다른 칸으로 옮기기·창 닫기 때 한 번 저장한다. 입력 중에는 칸만 바뀌고 앱 전체가 다시 그려지지 않는다(한 단어 입력 동안 저장 = 앱 전체 다시 그리기가 글자 수만큼 → 멈출 때마다 한 번). 잠깐 멈춰 저장할 때는 칸의 글자를 건드리지 않아 한글 조합이 깨지지 않는다.
- 우측 패널과의 일치: 이름표 편집 창과 우측 패널은 같은 `PropertySlotRow`를 쓰므로 둘 다 이 방식이다. 저장은 종전과 같은 `updateProperty`(같은 칸 연속 입력을 실행취소 한 칸으로 합침)라, 한 번 입력이 실행취소 한 칸인 것도 같다. 실행취소 등으로 저장값이 바뀌면 입력 중이 아닌 칸은 바로 따라간다. 이름표 위 name 글씨는 저장될 때(멈추거나 확정할 때) 바뀐다.
- 수치(Release): 글자 하나마다 앱 전체 다시 그리기 38 ms(78bc418 전 430 ms) → 입력 중 0회, 저장할 때 한 번 38 ms. 실제 창의 글자 입력 체감은 화면 없이 잴 수 없어 확인하지 못했다.
- 자체점검 1항목 추가(글자칸 입력 중 상태: 입력 중에는 저장하지 않고 확정할 글자만 넘기며 저장되면 끝남). selftest 753·building 27·project 24·routing 117·drawing-loading 54 통과. 실제 화면 확인 필요(name·ko 입력 체감, 0.4초 뒤 이름표 글씨 반영, Return·창 닫기 때 저장, 한글 조합).

## 2026-10-19 — opening 하나 저장할 때 '점·면 계산 중' 팝업

- 실제 화면 피드백: opening 하나를 태깅(저장)할 때마다 "점·면 계산 중" 팝업이 뜨고 오래 걸린다.
- 원인: 저장된 opening의 선은 면을 닫는 선분이라 저장할 때마다 `DerivedGeometryKey`가 바뀌고, `DerivedGeometry.make`가 점·면을 처음부터 다시 계산했다. 레포 밖 계측 사본으로 구간을 쟀다(Release). 포스텍 도서관 2층(개체 64,006·보조 제외 50,564)에서 2,119 ms 중 **보조 개체까지 포함한 전체 점 추출 1,832 ms**(33만 개, 진행률 분모를 세는 데만 쓰임), 보조 제외 뒤 점 197 ms, 선분 자르기 32 ms, 면 추적(자르기 포함) 102 ms였다. C5 5층은 272 ms 중 점 175 ms. 즉 opening과 무관한 점 다시 세기가 대부분이었다. 선분 자르기 캐시(처음 제안한 B안)는 효과가 30 ms뿐이라 하지 않았다.
- 고친 것(`App/DerivedGeometry.swift`, `App/AppEnvironment.swift`, `App/LevelDrawingCache.swift`): 결과에 점을 센 입력(`PointSource`: 도면 fingerprint·선분화·보조 제외)을 담고, 마지막 결과(`lastDerivedGeometry`)를 다음 계산에 넘긴다. 도면·선분화·보조 제외가 같으면 점을 그대로 쓰고 면만 다시 찾는다. 보조 제외만 바뀌면 전체 점 수(분모)는 재사용하고 고를 수 있는 점만 새로 센다. 층 캐시의 '파싱 재사용' 경로도 같은 재사용을 쓴다.
- 수치(Release, drawing-loading 자체점검): opening 하나 추가 후 재계산 포스텍 도서관 2층 2.10 s → 0.11 s, C5 0.44 s → 0.10 s. 보조 개체 하나 제외 후 재계산은 포스텍 도서관 0.33 s(종전 경로는 약 2 s). 팝업은 1초 넘을 때만 뜨므로 opening 저장 때는 뜨지 않을 것으로 본다.
- 자체점검 2항목 추가(`App/DrawingLoadingSelfTest.swift`: opening 추가 시 재사용 결과 = 처음부터 센 결과(면 id·점 수·분모)이고 더 빠름, 보조 제외만 바뀌어도 결과 같음). drawing-loading 56(샘플)·53(포스텍 도서관)·56(C5), selftest·building 27·project 24·routing 117 통과. document-open 20/23은 변경 전과 같은 3건(번들 Info.plist 검사, `.app` 밖 바이너리라 실패)이다. 실제 화면 확인 필요(opening 저장 체감).
- 코드 변경은 `df228b7` 커밋에 함께 들어갔다(커밋 메시지에는 없음).

## 2026-10-19 — fixture 선 단위(도면 개체 골라 저장), unit category 최근 순

- 사용자 지시: fixture 레이어에 기존 점 단위·면 단위와 함께 **선 단위**를 옵션으로 둔다. 도면 개체를 클릭·드래그로 골라 fixture 하나로 저장하는 종전 개체 선택 방식이다(`LayerEditMode.object`, `IMDFFeatureType.allowsObjectSelection`은 fixture만). 선 단위에서는 선택 키(fn+shift+z) 없이도 클릭·드래그(왼→오른 감싸기, 오른→왼 걸치기)가 개체를 고르고, 상단바(`UI/ObjectToolbar.swift`)에 모드 전환·안내가 늘 보이며 고르면 종전 선택 상단바('Feature로 저장'·'기존 feature에 추가')가 그 아래 뜬다. 저장은 종전 `createFeature`(구성원 feature, 소유권·보조 제외 판정 그대로). '기존 feature에 추가' 목록에서 점으로 그린 fixture는 뺐다. 다른 모드로 돌아가면 선택을 비운다.
- 사용자 지시: unit 레이어 category 칸은 최근 고른 값이 맨 위에 최근 순으로 오고(시계 표시), 나머지는 종전 순서다(`App/RecentCategories.swift`). 기록은 이 Mac 설정(`recentUnitCategories`)에 최근 12개, 실행취소 대상이 아니다. 우측 패널과 이름표 편집 창이 같은 칸이라 둘 다 적용된다. 다른 레이어는 그대로다.
- 자체점검 11항목 추가(fixture 선 단위 6·최근 순 5). selftest 764·building 27·project 24·routing 117·drawing-loading 56 통과. 실제 화면 확인 필요.

## 2026-10-19 — 메타데이터 type은 레이어 대신 정보 입력, section에 unit 모양 기준

- 사용자 지시: 도형 없이 정보만 갖는 type(address·building·occupant·manifest, `requiredGeometry == .none` → `isMetadataOnly`)은 레이어를 만들지 않는다. 그릴 도형이 없어 레이어를 만들어도 캔버스에서 할 일이 없었다. 좌측 목록 버튼이 '정보 입력'이 되고, 누르면 입력 창(`UI/MetadataEditor.swift`)이 뜬다. 창에서 feature를 더하고(속성 모두 null로 시작, 실행취소 한 칸) 우측 패널과 같은 속성 칸(`PropertySlotRow`)으로 값을 넣으며, 휴지통으로 보낼 수 있다. manifest는 하나만 둔다. `selectPropertyType`도 이 type이면 창을 연다(opening 선행 게이트와 무관). 예전에 만든 이 type의 레이어는 창을 열 때 닫는다(feature는 그대로). 저장 위치는 종전과 같은 지금 층의 feature 목록이라 내보내기(모든 층에서 모음)는 바꾸지 않았다(`App/MetadataFeatures.swift`).
- 사용자 지시: section 레이어 면 단위에 `unit 모양 기준`(`FaceBoundaryScope.unitShapes`, section 전용)을 추가했다. 저장된 unit의 다각형마다(MultiPolygon은 섬마다) 면이 하나씩이고 unit 안쪽 링은 구멍이라, 누르면 그 unit과 똑같은 모양(구멍 포함)의 section으로 저장된다. 경계선으로 면을 다시 찾으면 이웃 unit·보조 선분에 잘려 모양이 달라지기 때문에 unit 링을 그대로 쓴다. 이미 section으로 저장한 unit 자리는 다시 고를 수 없다 — 처음에는 면 캐시가 unit 경계만 비교해 section을 저장해도 갱신되지 않던 것을 자체점검으로 잡아, 비교에 section 링을 넣었다. 기준을 고를 수 없는 레이어에서는 `현재 레이어 기준`으로 돌아간다.
- 자체점검 12항목 추가(메타데이터 7·section unit 모양 5). selftest 776·building 27·project 24·routing 117·drawing-loading 56 통과. 실제 화면 확인 필요.

## 2026-10-19 — fixture 선 단위: 똑같이 생긴 개체 묶음은 그 자리 윤곽선대로 함께 저장

- 사용자 지시: fixture는 똑같이 생긴 개체가 2개 이상이면 윤곽선에 맞춰 함께 태깅한다. 점 단위의 종전 기능(10-18)은 그린 도형을 평행이동해 저장하지만, 선 단위는 **그 자리의 도면 개체를 구성원으로** 저장해 자리마다 윤곽선이 도면을 그대로 따른다(`App/FixtureTwins.swift` `fixtureMemberTwins`).
- 자리 찾기: 고른 개체 하나하나가 같은 만큼 옮긴 자리에 쌍둥이(`twinKey`)를 가져야 한 자리다. 쌍둥이가 가장 적은 개체를 기준으로 후보를 돌고, 위치는 0.01 격자(이웃 칸 포함)로 맞춘다. 보조 개체로 뺀 개체·고른 개체 자신은 넣지 않는다.
- 'Feature로 저장'(`createFeature`)은 fixture면 아무 feature도 갖지 않은 자리마다 구성원 fixture를 함께 만든다(같은 속성, 실행취소 한 칸). 선 단위 상단바 안내에 함께 저장될 곳 수를 미리 보인다(짧은 선 하나를 고르면 수백 곳이 될 수 있다). 우측 패널 '같은 태깅으로 저장'도 선 단위 fixture면 개체로 자리를 찾아, 빈 자리는 새로 저장하고 그 자리 개체를 그대로 가진 fixture는 속성만 맞춘다(다른 feature가 가진 자리는 건너뜀).
- 자체점검 7항목 추가(묶음째 자리 찾기·자리마다 저장·저장된 자리 제외·실행취소·쌍둥이 없는 개체·보조 제외 자리·우측 패널 속성 맞춤). selftest 786·building 27·project 24·routing 117 통과. 실제 화면 확인 필요(포스텍 도서관 3층 가구로).
- 같은 작업 트리에 이번 작업과 무관한 미커밋 변경(보조 개체 클릭 시 겹친 개체 함께 고르기, `stackedTwins`)이 함께 있다.
