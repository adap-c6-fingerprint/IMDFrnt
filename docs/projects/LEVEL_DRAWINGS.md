# 층별 도면과 비동기 로딩

관련 이슈: [#20](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/20), 서브 이슈 [#26](https://github.com/adap-c6-fingerprint/IMDFrnt/issues/26).
브랜치: `feat/#20-level-drawing-management`, 병합된 develop 기준.

## 사용

- 층 이름·짧은 이름을 도면 준비보다 먼저 상단 탭바에 표시한다. 우측 상단 층 선택과 관리·노드 화면의 층 셀도 같은 선택을 사용한다.
- 캐시가 없는 층은 로딩 표시를 보여준다. 다른 탭을 계속 선택할 수 있으며 마지막으로 선택한 층만 적용된다.
- SVG·PNG·JPG는 현재 층에 내장한다. 일반 SVG 작업의 교체는 기존 태깅·좌표 기준점 초기화를 확인하며 노드를 유지한다.
- IMDF 층에서는 가져온 SVG·이미지를 독립된 참고 레이어로 추가한다. 원본 IMDF geometry·투영·도형·핀 좌표를 바꾸지 않는다.
- 상단 **도면 레이어** 또는 **건물·층 관리 → 도면 레이어**에서 SVG와 건물 Footprint의 표시·숨김·불투명도를 바꾼다.
- 참고 도면은 종횡비를 유지하여 도면 영역에 맞춰 표시한다. 이 배치는 지리좌표 정합을 확정하지 않는다. Footprint는 IMDF 투영 또는 설정한 좌표 기준점의 역변환으로 표시한다.
- 참고 도면 삭제는 빨간 버튼·확인 알림·취소·Undo를 지원한다.

## 저장과 캐시

v5 `.imdfrnt`의 각 Level에 선택적 `referenceDrawing`(SVG 원문·파일명·표시 설정)과 `svgPresentation`을 추가했다. `footprintPresentation`은 건물 전역 설정이다. 필드가 없는 이전 v5 파일은 기본 설정을 사용하고 v2~v4 이전 경로도 유지한다.

저장된 SVG 원문과 GeoJSON이 원본이다. 캐시는 프로젝트 파일·Undo·수정 여부에서 제외한다. SVG 파싱 결과, Path·선분·경계 상자, 속성·공간·쌍둥이 색인과 다각형 진행률을 보관한다. 최대 6개 층과 약 128 MiB의 추정 비용으로 LRU 축출한다. 단일 활성 도면이 한도를 넘으면 그 도면 한 개는 유지한다. 도면 준비 작업은 최대 2개이고 인접 층은 순서대로 미리 준비한다.

파일 읽기·이미지 디코딩·SVG 파싱·파생 계산은 백그라운드 Task에서 수행하고 Sendable 값으로 전달한다. 메인 액터는 선택과 준비된 결과를 적용한다. 프로젝트·요청 ID와 입력 내용이 일치해야 반영하며, 교체·삭제·Undo·재열기에서 오래된 결과를 적용하지 않는다. 로딩 중 이전 층의 도면과 색인은 비운다. Swift 6 언어 모드를 사용한다.

## 검증

```sh
cd IM-DFrnt
./build-app.sh /Users/dd/Applications/IM-DFrntIssue20.app
./run-self-tests.sh /Users/dd/Applications/IM-DFrntIssue20.app --imdf-test-input /path/to/IMDFData --drawing-test-project /path/to/test.imdfrnt
```

`--drawing-loading-selftest`는 기본 샘플, `--drawing-test-svg`, `--drawing-test-project` 또는 `--imdf-test-input`을 지원한다. 원본 입력은 읽기 전용으로 사용한다. 메타데이터 우선 표시, 메인 액터 응답, 마지막 선택, 캐시 재사용·제한·동시 요청 공유, 층별 미저장 노드, 교체·삭제·Undo, 참고 레이어 분리·저장, 비동기 열기 취소·손상 입력을 검사한다.

2026-10-14 Release에서 `5F, 6F Floor map_Light.svg`(개체 3,442개)의 기존 전환 로직은 매번 5.29~5.34초를 사용했다. 실제 두 층 테스트 프로젝트를 비동기로 열면 최초 준비는 약 5.4초이고 그동안 메인 액터의 10ms 간격 확인 작업이 400회 이상 실행됐다. 캐시된 층 재전환 로직은 약 0.4~0.5ms이며 재파싱·파생 계산이 증가하지 않았다. 선택 명령부터 도면 모델 적용까지의 시간이며 화면 첫 프레임까지 측정한 값은 아니다.

Release 빌드·번들 서명과 6개 CLI 검사를 통과했다. UI 도구는 `Sky Computer Use native pipe startup failed`로 연결되지 않았고 WindowServer에서도 테스트 창을 조회하지 못했다. 실제 버튼 입력·화면 렌더링은 수동 확인 항목으로 남긴다. 검증 로그 경로와 최신 결과는 [진행 기록](../../PROGRESS.md)에 기록한다.

## 수동 확인

1. 테스트 프로젝트의 두 층을 탭과 우측 Picker로 반복 전환해 무지개 대기 커서가 다시 나타나는지 확인한다.
2. 첫 도면 로딩 중 탭의 층 이름이 보이고 다른 층을 선택할 수 있는지 확인한다.
3. 빠르게 여러 층을 선택해 마지막 탭·도면·노드가 일치하는지 확인한다.
4. IMDF 층에 참고 SVG를 넣고 SVG/Footprint를 각각 숨기거나 불투명도를 바꾼다. IMDF 도형과 핀 위치가 유지되는지 확인한다.
5. 참고 도면 삭제 알림의 취소·확정·Undo와 저장·재열기 후 레이어 설정 복원을 확인한다.
