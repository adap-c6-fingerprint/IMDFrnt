---
summary: CAD/BIM 도면이 좌표계 정의·지오레퍼런싱·레이어 정리·속성(카테고리·이름) 부여·변환 도구(FME/ArcGIS Indoors) 실행·검증을 거쳐 IMDF(GeoJSON)가 되는 전 과정을 Safe Software·Esri·Apple 공식 자료로 정리
source: 01-2) 소스 --------------------/S06) Indoor Map/S06-02) FP-to-IMDF/src06. CAD·BIM 도면에서 IMDF(GeoJSON) 변환 워크플로우 조사.md
related:
  - "[[IMDF]]"
  - "[[GeoJSON]]"
  - "[[지오레퍼런싱]]"
  - "[[00) Apple Indoor Maps Program과 IMDF 개요]]"
  - "[[05) 라벨에 관하여]]"
core_keywords:
  - IMDF
  - FME
  - ArcGIS Indoors
created: 2026-08-13 00:00
updated: 2026-08-20 00:00
---
# 도면에서 GeoJSON(IMDF) 추출 전 과정

## 요약

`Apple Indoor Maps Program과 IMDF 개요.md`는 "건물·부동산 소유자는 CAD/BIM/GIS 파일을 업계 표준 도구로 IMDF로 변환하는 것부터 시작한다"고만 짧게 서술한다. 이 문서는 그 "변환"이 실제로 무엇을 하는 작업인지, Apple이 공식 파트너로 명시하는 **Safe Software(FME)**와 **Esri(ArcGIS Indoors)**의 실제 문서·튜토리얼을 근거로 도면 원본에서 IMDF(GeoJSON)가 나오기까지의 전 과정을 정리한다.

핵심은, 이 변환이 "파일 형식만 바꾸는" 단순 작업이 아니라 **좌표계가 없는 도면에 실제 지구 좌표를 부여하고(지오레퍼런싱), 자유로운 CAD 표현을 IMDF의 엄격한 스키마에 맞게 재구성하는(정제·속성 부여)** 작업이라는 점이다. Safe Software 직원의 원문 표현을 빌리면: "CAD is likely the hardest data to properly convert to IMDF, since it allows a great deal of latitude in the presentation and topology of the features, and IMDF is pretty rigid in its requirements."

## 1. 전체 파이프라인 (4단계)

FME 블로그가 제시하는 큰 틀:

1. **읽기(Read)** — "Read data from wherever it is – BIM, CAD, GeoJSON, ArcGIS, etc."
2. **보강·변환(Enrich and convert)** — "involves some combination of **georeferencing, semantic enrichment, classification, schema mapping, and cleansing.**"
3. **검증(Validate)** — "sending it through the IMDFValidator."
4. **쓰기·제출(Write & Submit)** — "Write to IMDF... submit the dataset to Apple via Apple Maps Connect."

아래 2~5절은 이 4단계 중 2단계("보강·변환")를 실무 사례(FME의 AutoCAD 변환 3부작, Esri의 ArcGIS Pro 경로)로 더 세분화한 것이다.

> **별도 문서로 분리된 질문:** "다각형 형태로 표현되는 unit들이 어떻게 좌표로 옮겨지는가 — 사각형 방 하나가 좌표화될 때 도면상 어떤 점들이 좌표가 되는가(꼭짓점만인가, 문·창문까지인가), 좌표화의 기준은 무엇인가. 그리고 좌표들의 집합을 수동이 아니라 자동으로 '방'·'문'·'창문'으로 정의하려면 무엇을 기준으로 묶어야 하는가."
> → [[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]]에서 OGC IMDF 스펙·Esri·FME 공식 문서 근거와 함께 전면 정리했다.

## 2. 좌표계 정의와 지오레퍼런싱

- **질문**💡 **지오레퍼런싱이란 무엇인가?**
	- **답변:** 지오레퍼런싱(georeferencing)은 좌표계가 없는 도면(또는 지도)을 실제 지구 좌표계(위도·경도)에 정렬하는 과정이다. [[지오레퍼런싱]] 문서 기준으로 두 단계로 나뉜다. ① **도면 제작 단계**(이 절에서 다루는 내용): CAD/BIM 도면은 원래 임의의 도면 좌표로 그려지므로, FME나 ArcGIS Pro 같은 변환 도구로 좌표계를 정의하고 이동·회전·스케일 조정을 거쳐 실제 지구 좌표에 맞춘다. ② **Apple 검증 단계**: `00) Apple Indoor Maps Program과 IMDF 개요.md` 6절에 정리된 대로, 자동 검증에서 에러가 없어진 뒤 Apple 실내 팀이 이 좌표가 Apple 위성 이미지와 실제로 맞는지 **수동으로** 재확인한다. 즉 지오레퍼런싱은 한 번이 아니라, 도면 제작자 쪽과 Apple 쪽에서 각각 한 번씩 총 두 번 이뤄진다.

원본 CAD 도면은 대개 공간 참조(좌표계)가 없는 임의의 도면 좌표로 그려진다. 이를 실제 지구 좌표로 옮기는 작업이 가장 먼저 필요하다.

- **Esri/ArcGIS Pro 경로**: "Define Projection" 도구로 적절한 투영(대개 지역 State Plane)을 정의한 뒤, "Georeference 도구"로 이동(move)·회전(rotate)·스케일(scale) 조정을 거쳐 도면을 올바른 지리적 위치에 정렬한다.
- **FME 경로**: PreProcess 단계에서 "마스터 도면(master drawing)에서 좌표를 추출하고, 마스터와 참조 도면 간 차이를 계산해 속성으로 저장"한 뒤, 이 값으로 도면을 오프셋한다. 지오레퍼런싱 자체는 "rotating, scaling and offsetting"으로 적용되며, Part 3에서는 이를 `ApplyGeoreferencing`이라는 커스텀 트랜스포머로 재사용한다.

이 단계에서 나오는 좌표가 바로 [[지오레퍼런싱]] 문서가 다루는 "IMDF의 기본 요소인 건물 지면 풋프린트와 GeoCoordinates"의 출발점이다. 다만 여기서 이뤄지는 건 변환 도구 단의 지오레퍼런싱이고, `Apple Indoor Maps Program과 IMDF 개요.md` 6절이 설명하는 "Apple 실내 팀의 수동 지오레퍼런싱 확인"은 그 이후 Apple 쪽 검증 단계에서 별도로 이뤄진다.

- **질문**💡 **지오레퍼런싱을 하는 점들은 최종적으로 어떤 점인가? Polygon의 꼭짓점인가?**
	- **답변:** 부분적으로만 맞다. Esri 공식 문서("Overview of georeferencing", "Add control points manually" — ArcGIS Pro)에 따르면, 지오레퍼런싱 작업 자체에서 사람이 직접 지정·조정하는 점은 폴리곤 꼭짓점이 아니라 **컨트롤 포인트**(control point)다. 도면(from point)과 실제 좌표 참조 데이터(to point, 위성 이미지 등) 양쪽에서 정확히 식별 가능한 지점(건물 모서리 등 랜드마크)을 사람이 수동으로 짝지어 만드는 소수의 기준점 쌍이며, 위 FME Part 2에서 말하는 "georeference point"와 같은 개념이다. Esri는 "코너 근처 최소 1개 + 내부 여러 개"로 이 점들을 분산 배치할 것을 권장한다.
	- 이 컨트롤 포인트들은 최종 IMDF 파일에 그대로 남는 데이터가 아니라, 회전·스케일·이동(rotate/scale/offset) 변환식을 도출하기 위한 계산용 입력값이다. 계산된 변환식은 도면 전체(모든 레이어·모든 피처)에 일괄 적용된다.
	- 따라서 실제로 지구 좌표를 최종적으로 갖게 되는 점은 폴리곤 꼭짓점만이 아니라 **IMDF 최종 산출물의 모든 geometry의 vertex 전체**다. OGC 공식 IMDF 스펙("Footprint - Indoor Mapping Data Format 1.0.0")이 보여주듯 Footprint·Level·Unit·Section·Delimited Area 같은 Polygon/MultiPolygon 타입은 그 꼭짓점 전부가, Opening 같은 LineString 타입은 양 끝점이, Anchor·Kiosk·Occupant·Icon 같은 Point 타입은 그 단일 좌표점이 지오레퍼런싱된 좌표를 갖는다. 자세한 근거와 원문은 [[src06. CAD·BIM 도면에서 IMDF(GeoJSON) 변환 워크플로우 조사]] 7절 참고.

- **질문**💡 **풋프린트는 무엇인가?**
	- **답변:** Footprint는 IMDF 16개 Feature Type 중 하나로, 건물의 대략적인 물리적 범위(지면 형태)를 나타낸다. OGC IMDF 1.0.0 스펙 원문: "A Footprint models the approximate physical extent of one or more referenced Buildings." geometry는 Polygon(또는 MultiPolygon)이고, properties는 `category`(값: `"aerial"`/`"ground"`/`"subterranean"` — 지상·공중·지하 중 어디인지), `name`(LABELS, 선택), `building_ids`(연관된 Building의 식별자 배열, 1개 이상 필수)로 구성된다. 즉 Footprint는 "이 건물이 지구 표면 어디에, 어떤 모양으로 놓여 있는가"를 나타내는 가장 바깥쪽 도형이며, 2절의 지오레퍼런싱이 실제로 정렬하는 대상이 바로 이 Footprint(와 그 위에 쌓이는 Level·Unit 등)다.

## 3. CAD 기하 정리 — 레이어별 수동 편집

FME 튜토리얼 Part 2("Preparing the Preprocessed Data using AutoCAD")는 자동 전처리 이후에도 반드시 사람이 AutoCAD에서 레이어별로 직접 손봐야 하는 부분을 명시한다.

- 자동 처리가 완벽하지 않은 지점: "single lines and openings where single line processing and opening extraction are not perfect, especially small 'notches'."
- **"Null areas in the Units layer inside the Level boundary will be considered as a wall in the final IMDF."** — Units 레이어 안에서 도형으로 채워지지 않은 빈 영역은 최종 IMDF에서 벽으로 취급된다.
- "구조 기둥으로 판단되는 것은 해당 층의 **Columns 레이어**로 옮겨야 한다."

**`라벨에 관하여.md`와의 교차 확인:** 그 문서 GQ3(b)는 IMDF 스펙 자체에 "Wall(벽)"이라는 독립 Feature Type이 없고, "Unit 경계 = 벽"이라고 스펙이 명시적으로 등치시키는 문장도 없어 확인 필요로 남겨두었다. 이번 조사로, 실제 제작 도구(FME) 단에서는 **"Units 레이어의 빈 영역이 곧 최종 IMDF의 벽"이라는 규칙을 실무적으로 쓰고 있음**이 확인된다. 즉 스펙 문서가 이를 명문화하지는 않지만, 변환 도구/실무 관행 차원에서는 "Unit이 채우지 않은 자리 = 벽"이라는 원칙이 실제로 적용된다.

## 4. 속성(semantic enrichment·schema mapping) — 카테고리·이름·주소 부여

CAD 도면의 선·폴리곤에는 원래 "이게 무슨 카테고리의 방인지, 이름이 무엇인지" 같은 의미 정보가 없거나 CAD 자체 방식(레이어명, 블록명 등)으로만 담겨 있다. 이를 IMDF 스키마의 실제 필드로 옮기는 작업이 필요하다.

- Luft Enterprises의 표현: "feature names, categories, addresses, display points, level references"를 IWMS·CAFM 같은 시설관리 시스템의 데이터와 맞춰(schema mapping) 구축한다.
- FME Part 1은 이 단계에서 "IMDF 요구사항에 맞는 명명 규칙을 따르는 속성을 생성한다(create attributes with the correct naming convention to meet the IMDF requirements)"고 서술한다.

여기서 생성되는 속성들이 정확히 `라벨에 관하여.md`, `src04`에서 확인한 IMDF 필드들이다 — `category`(UNIT-CATEGORY 등), `name`/`alt_name`([[LABELS]] 타입), `display_point`([[Display Point]] 타입), `level_id` 등. 즉 이 문서의 4절과 `라벨에 관하여.md`는 "그 필드가 최종 파일에서 어떤 모양인가"(라벨에 관하여)와 "그 필드가 도면 제작 단계에서 어떻게 채워지는가"(이 문서)로 같은 대상을 다른 단계에서 다룬다.

## 5. 변환 도구 실행 — FME Writer / ArcGIS Indoors

### 5.1 FME 경로

- **Writer**: "하나의 zip 파일에 Feature Type별 GeoJSON 파일들 — levels, units, openings, venue, address, building, footprints — 을 담아 출력한다."
- FME는 400개 이상의 포맷(CAD, BIM, GIS, Excel 등)을 입력으로 지원한다고 서술된다.
- 같은 워크플로우를 재사용해 이후 도면이 바뀔 때 IMDF를 다시 생성·재제출하는 것도 자동화할 수 있다.

### 5.2 Esri 경로

- ArcGIS Indoors 확장에서, CAD 파일은 Excel 템플릿을 채운 뒤 지오프로세싱 도구 **"Import Floorplans To Indoors Geodatabase"**를, BIM 파일은 **"Import BIM to Indoors Dataset"**을 실행해 ArcGIS Indoors Geodatabase로 만든다.
- **후속 확인(2026-08-13):** 이 Geodatabase → 최종 IMDF export는 Esri 자체 기능이 아니라 **FME를 재사용한다.** "Generate Unit Openings" 도구로 IMDF가 요구하는 LineString Opening을 먼저 만든 뒤, ArcGIS Pro의 Data Interoperability Extension(FME 엔진 내장)으로 "ArcGIS Indoors Model to IMDF" 워크벤치(FME Hub 배포)를 실행한다. 즉 5.1·5.2 두 경로 모두 최종적으로는 FME가 IMDF를 출력한다는 점이 같다. 자세한 내용은 [[04) ArcGIS Indoors]] 참고.

## 6. 검증과 제출

- FME 쪽: "Before sending the IMDF off to be published, the data should be validated to check for any errors or warnings" — **IMDFValidator**로 검증한 뒤 **Apple Maps Connect**를 통해 Apple에 제출한다.
- 검증 이후 절차(전자 검증 리포트, [[IMDF Sandbox]]를 통한 시각적 확인, Apple 실내 팀의 수동 지오레퍼런싱 확인)는 `Apple Indoor Maps Program과 IMDF 개요.md` 6절에 이미 정리되어 있다 — 이 문서는 "그 검증 리포트를 받기 전, 도면에서 그 IMDF 파일 자체가 어떻게 만들어지는가"를 다룬다는 점에서 서로 이어지는 앞 단계다.

## 전체 흐름 요약

```
CAD/BIM 원본 도면 (좌표계 없음, 자유로운 표현)
  ↓ 좌표계 정의 + 지오레퍼런싱(rotate/scale/offset)
  ↓ 레이어·기하 정리 (Units 빈 영역=벽, 기둥→Columns 레이어 등 수동 편집)
  ↓ 속성 부여 (category, name/alt_name, display_point, level_id 등 IMDF 필드로 schema mapping)
  ↓ 변환 도구 실행 (FME Writer 또는 ArcGIS Indoors → IMDF)
  ↓ IMDFValidator로 자체 검증
  ↓ Apple Maps Connect로 제출
  ↓ (이후 Apple Indoor Maps Program과 IMDF 개요.md 6절: 전자 검증·Sandbox·수동 지오레퍼런싱 확인 단계로 이어짐)
```

## 관련 링크

- [[IMDF]] — 이 파이프라인의 최종 산출물 규격
- [[GeoJSON]] — IMDF Writer가 출력하는 파일 포맷
- [[지오레퍼런싱]] — 2절에서 다루는 좌표 정렬 작업의 개념 문서
- [[00) Apple Indoor Maps Program과 IMDF 개요]] — 이 문서 이후 단계(검증·측위 활성화·앱 표시)를 다룸
- [[05) 라벨에 관하여]] — 4절에서 부여하는 속성 필드들의 최종 데이터 구조

## 관련 링크(추가)

- [[03) FME]] — FME 자체(회사·제품)를 다룬 심화 문서
- [[04) ArcGIS Indoors]] — ArcGIS Indoors 자체(제품·라이선스·IMDF export 절차)를 다룬 심화 문서
- [[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]] — 이 문서 2~4절(지오레퍼런싱·기하 정리·속성 부여)에서 다루는 좌표·피처가 실제로 어느 선에서 어떤 기준으로 만들어지는지를 파고든 심화 문서

## 미해결 질문

- `support.safe.com` 3부작 튜토리얼 원문 전체(트랜스포머 스크린샷 등)는 403 차단으로 검색 스니펫 인용에 그침 — 직접 원문 대조 필요.
- ~~ArcGIS Indoors Geodatabase → 최종 IMDF export의 정확한 절차.~~ [[04) ArcGIS Indoors]]에서 해결(FME Data Interoperability Extension 재사용 확인).
- FME IMDF Writer의 전체 필수 파라미터 목록(manifest 필드 등) — 일부만 확인됨.
- register.apple.com FAQ의 제3자 IMDF 제작 플랫폼 전체 목록 — 미확보.
