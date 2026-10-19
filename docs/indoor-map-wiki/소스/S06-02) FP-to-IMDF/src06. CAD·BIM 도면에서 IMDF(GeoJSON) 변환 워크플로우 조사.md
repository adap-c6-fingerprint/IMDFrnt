---
summary: "Safe Software FME, Esri ArcGIS Indoors, Apple 공식 리소스 페이지, 실무 컨설팅 자료를 통해 CAD/BIM 도면을 IMDF(GeoJSON)로 변환하는 실제 단계별 워크플로우 조사"
source: "fme.safe.com, support.safe.com, community.safe.com, docs.safe.com, register.apple.com/resources/indoor, cloudpointgeo.com, luftent.com"
created: "2026-08-13 00:00"
updated: "2026-08-20 00:00"
---
# CAD·BIM 도면에서 IMDF(GeoJSON) 변환 워크플로우 조사

## 수집 기준

- 수집일: 2026-08-13
- 목적: 기존 위키 문서(`Apple Indoor Maps Program과 IMDF 개요.md` 3절)는 "CAD/BIM/GIS 파일을 업계 표준 도구로 IMDF로 변환한다"는 한 문장만 있어, 실제 변환의 전 과정(도면 → GeoJSON)을 알 수 없었음. Apple이 공식 파트너로 언급하는 Safe Software(FME)와 Esri(ArcGIS Indoors)의 실제 문서, 그리고 제3자 실무 자료를 조사해 구체적 단계를 확보.
- 주의: `support.safe.com`의 3부작 튜토리얼 원문 페이지는 WebFetch로 직접 열람 시 403(차단)이 발생해 본문을 온전히 가져오지 못했다. 대신 WebSearch가 반환한 해당 페이지의 발췌·요약을 인용했다. **원문 전체 대조는 하지 못했으므로, 발췌 인용 부분은 검색 스니펫 기반임을 표시한다.**

## 핵심 출처

- Esri, "Overview of georeferencing" (ArcGIS Pro 공식 문서): https://pro.arcgis.com/en/pro-app/latest/help/data/imagery/overview-of-georeferencing.htm
- Esri, "Add control points manually" (ArcGIS Pro 공식 문서): https://pro.arcgis.com/en/pro-app/latest/help/data/cad/adding-control-points-manually.htm
- OGC, "Footprint - Indoor Mapping Data Format (1.0.0)" (공식 스펙): https://docs.ogc.org/cs/20-094/Footprint/index.html
- FME 블로그, "Indoor mapping your venue with the new IMDF standard": https://fme.safe.com/blog/2018/10/indoor-mapping-ios-imdf/
- FME Support, "Converting CAD Datasets to IMDF: Part 1" (전처리): https://support.safe.com/hc/en-us/articles/25407420486669
- FME Support, "Converting CAD Datasets to IMDF: Part 2" (AutoCAD 수동 정리): https://support.safe.com/hc/en-us/articles/25407624382093
- FME Support, "Converting CAD Datasets to IMDF: Part 3" (Writer·지오레퍼런싱·검증): https://support.safe.com/hc/en-us/articles/25407639677965
- FME Support, "Tutorial: Creating and Validating IMDF Datasets": https://support.safe.com/hc/en-us/articles/25407643555085
- FME 문서, IMDF Reader/Writer 개요: https://docs.safe.com/fme/html/FME-Form-Documentation/FME-ReadersWriters/imdf/imdf.htm
- FME 문서, IMDF Writer 파라미터: https://docs.safe.com/fme/html/FME-Form-Documentation/FME-ReadersWriters/imdf/imdf_writer.htm
- FME 커뮤니티 포럼(Safe Software 직원 답변 포함): https://community.safe.com/transformers-9/how-to-format-autocad-so-that-it-is-ready-for-fme-conversion-into-imdf-6514
- Apple 공식, Additional Resources(Indoor Maps Program): https://register.apple.com/resources/indoor/program/additional_resources
- CloudPoint Geo, "Migrating CAD Floor Plans to GIS with ArcGIS Pro": https://www.cloudpointgeo.com/post/migrating-cad-floor-plans-to-gis-with-arcgis-pro
- Luft Enterprises, "From CAD to IMDF: A Practical Workflow": https://www.luftent.com/cad-to-imdf-article/

## 1. 전체 파이프라인 개요 (FME 블로그, fme.safe.com)

원문 4단계:
1. "Read data from wherever it is – BIM, CAD, GeoJSON, ArcGIS, etc."
2. "Enrich and convert it to meet the IMDF specification. This involves some combination of **georeferencing, semantic enrichment, classification, schema mapping, and cleansing.**"
3. "Validate against the IMDF specification by sending it through the **IMDFValidator**."
4. "Write to IMDF. From there, you can submit the dataset to Apple via **Apple Maps Connect**."

## 2. FME "Converting CAD Datasets to IMDF" 3부작 (AutoCAD DWG 기준, 검색 스니펫 인용)

### Part 1 — PreProcess.fmw (전처리)

- "The first step is to align the floors for the building as well as create attributes with the correct naming convention to meet the IMDF requirements."
- Xref(외부 참조 도면)와 지오레퍼런싱을 함께 처리: "Coordinates are extracted from the master drawing and the difference between master and references are calculated and stored as attributes. These attributes will be used to offset the drawing."
- "The non-IMDF-specific attributes are then removed."
- "A FeatureMerger is used to merge both the Xref and Georeferencing workflows together based on the `_xref` attribute... The georeferencing is then applied by **rotating, scaling and offsetting** the drawing."
- 권장 사항: "It is a good idea to run the workspace with Feature Caching enabled and monitor the data as it flows through."

### Part 2 — AutoCAD에서 수동으로 데이터 준비("Preparing the Preprocessed Data using AutoCAD")

- Part 1에서 만든 `ToEdit.dwg`를 AutoCAD로 열어 레이어별로 문제를 수동으로 고친다.
- 자동 처리가 완벽하지 않은 대표 문제: "single lines and openings where single line processing and opening extraction are not perfect, especially small 'notches'."
- 중요 규칙: "Null areas in the Units layer inside the Level boundary will be considered as a **wall** in the final IMDF" — 즉 Units 레이어 안에서 도형이 채워지지 않은 빈 영역은 최종 IMDF에서 벽으로 취급된다.
- "if any are known to be structural columns, they should be moved to the **Columns layer** for that level" — 구조 기둥은 별도 Columns 레이어로 옮겨야 한다.
- 이 단계에서 georeference point(지오레퍼런스 기준점)도 수동으로 만든다.

### Part 3 — Writer·지오레퍼런싱·검증

- **Writer**: "When writing out to IMDF one single zip file is created that contains GeoJSON files for each of the separate feature types: **levels, units, openings, venue, address, building, and footprints.**"
- **Georeference**: "The georeferencing is applied with the custom transformer `ApplyGeoreferencing`, which is the same method that was done in the PreProcessing.fmw processing workspace (part 1), it is just wrapped up in a custom transformer to clean up the workspace."
- **Validate**: "Before sending the IMDF off to be published, the data should be validated to check for any errors or warnings that may exist in the data."

## 3. CAD 변환의 본질적 어려움 (Safe Software 직원 답변, community.safe.com)

원문: "CAD is likely the hardest data to properly convert to IMDF, since it allows a great deal of latitude in the presentation and topology of the features, and IMDF is pretty rigid in its requirements."

→ CAD 도면은 표현 방식·토폴로지가 자유로운 반면 IMDF는 스키마가 엄격해서, 이 둘 사이 간극을 메우는 작업(레이어 정리·속성 부여·기하 정합)이 변환 과정의 핵심 난점이라는 점이 Safe Software 측 견해로 확인된다.

## 4. Esri 경로 — ArcGIS Pro / ArcGIS Indoors (cloudpointgeo.com 블로그)

1. **좌표계 정의**: 원본 CAD는 공간 참조가 없는 경우가 많아 "Define Projection" 도구로 "적절한 투영(일반적으로 지역 State Plane)"을 정의한다.
2. **지오레퍼런싱**: "Georeference 도구"로 "이동(move)·회전(rotate)·스케일(scale) 조정" 기능을 이용해 CAD 레이어를 올바른 지리적 위치에 정렬한다.
3. **ArcGIS Indoors 확장으로 GIS 데이터셋 생성**:
   - CAD 파일: Excel 템플릿을 채운 뒤 지오프로세싱 도구 **"Import Floorplans To Indoors Geodatabase"** 실행.
   - BIM 파일: 지오프로세싱 도구 **"Import BIM to Indoors Dataset"** 실행.
4. 전 과정에서 "깨끗한 CAD와 BIM 데이터 레이어"의 중요성이 강조된다.

→ 이번 조사에서는 ArcGIS Indoors Geodatabase → IMDF 최종 변환 단계(Esri 자체 export 기능인지, 별도로 FME를 다시 거치는지)의 정확한 절차까지는 확인하지 못했다(확인 필요). 검색 결과 스니펫에는 "ArcGIS Indoors 데이터를 FME로 IMDF로 변환한다"는 문구(Converting ArcGIS Indoors Data to IMDF – FME Support Center)도 있어, Esri 경로도 최종적으로 FME를 한 번 더 거치는 조합이 실무에서 쓰이는 것으로 보인다(확인 필요, 원문 대조 못 함).

## 5. 실무 컨설팅 관점의 8단계 요약 (Luft Enterprises, luftent.com)

1. 사용 목적 정의: "intended output, target platforms, portfolio scale, source systems, and maintenance expectations."
2. 도면 자산 목록화: DWG, PDF, Revit 내보내기, 건물 목록, 공간 ID, 점유 데이터 수집.
3. CAD 기하 정리: "normalizing layers, removing obsolete linework, resolving duplicate geometry."
4. 속성 모델 구축: "feature names, categories, addresses, display points, level references"를 IWMS·CAFM 시스템과 맞춘다.
5. 지오레퍼런싱: "places the indoor map in real-world coordinates."
6. IMDF 패키지 생성: `manifest.json`과 `.geojson` 파일들을 zip으로 구성.
7. 데이터 검증: 구조적·의미론적 유효성 확인.
8. 지속적 유지관리: 건물 변화에 따른 업데이트 프로세스 정의.

## 6. Apple 공식 도구 (Additional Resources 페이지)

- **IMDF Sandbox**: "Once you have created or updated an IMDF you can easily view it using IMDF Sandbox." — 검증·뷰어·경미한 편집.
- **Apple Indoor Survey App**: 실내 측위 활성화·테스트용 iOS 앱.
- **MapKit / MapKit JS**: "the simplest way to display your indoor map in your apps or websites is to use MapKit or MapKit JS."
- **Safe Software**: 공식 파트너로 명시(연락처 partners@safe.com), "IMDF 변환 도구 및 검증자가 포함된 데이터 변환 플랫폼을 제공."
- 그 외 제3자 플랫폼 목록은 FAQ 페이지를 참조하라고만 안내되어 있고, 이번 조사에서 그 목록 자체는 확보하지 못했다(확인 필요).

## 7. 후속 조사 (2026-08-20) — 지오레퍼런싱이 실제로 다루는 "점"은 무엇인가

- 수집일: 2026-08-20
- 목적: 위 2절·4절이 "이동·회전·스케일 조정으로 도면을 정렬한다"고만 서술해, 그 조정을 위해 실제로 지정하는 점이 무엇인지(최종 IMDF의 폴리곤 꼭짓점 자체인지, 별도의 기준점인지)가 불명확했음. Esri 공식 문서(ArcGIS Pro Georeferencing)와 OGC 공식 IMDF 스펙(Footprint)을 직접 조회해 확인.

**Esri 공식 문서, "Overview of georeferencing" (ArcGIS Pro):**
- "The process of geo­referencing involves identifying a series of **ground control points**... where control points are locations that can be accurately identified on the raster dataset and in real-world coordinates."
- "The connection between one control point on the raster dataset (the **from point**) and the corresponding control point on the aligned target data (the **to point**) is a **control point pair**."

**Esri 공식 문서, "Add control points manually" (ArcGIS Pro):**
- "On the Georeferencing tab, in the Adjust group, click **Add Control Points**... snap to and click the source CAD feature to create the **from point**... snap to and click the destination to create the **to point**. This creates a **link**."
- Best practice: "spread the links over the entire raster dataset rather than concentrating them in one area... having at least one link near each corner... and a few throughout the interior."

**OGC 공식 스펙, "Footprint - Indoor Mapping Data Format (1.0.0)":**
- Footprint의 `geometry`는 Polygon(또는 MultiPolygon)이며, `coordinates`는 경도·위도 좌표쌍의 중첩 배열로 구성된다. 예: `"coordinates": [[[100.0, 0.0], [101.0, 0.0], [101.0, 1.0], [100.0, 1.0], [100.0, 0.0]]]`.

**종합 판단:**
- "지오레퍼런싱"이라는 작업 자체가 지정·조정하는 점은 IMDF의 **폴리곤 꼭짓점이 아니라, 원본 도면과 실제 좌표계(위성 이미지 등 참조 데이터) 양쪽에서 사람이 수동으로 짝지은 소수의 "컨트롤 포인트"(from point/to point 쌍, 위 FME Part 2의 "georeference point"와 동일 개념)**다. 이 점들은 건물 모서리처럼 도면과 실제 세계 양쪽에서 정확히 식별 가능한 랜드마크이며, 최종 IMDF 파일에 그대로 남는 데이터가 아니라 회전·스케일·이동 변환식을 계산하기 위한 입력값이다.
- 이렇게 계산된 변환식이 도면 전체(모든 레이어·모든 피처)에 일괄 적용된다("rotating, scaling and offsetting the drawing" — FME 원문, 위 2절). 그 결과 실제로 지구 좌표를 최종적으로 갖게 되는 점은 **IMDF 최종 산출물의 모든 geometry의 vertex 전체**다 — Footprint·Level·Unit·Section·Delimited Area 같은 Polygon/MultiPolygon 타입은 그 꼭짓점 전부, Opening 같은 LineString 타입은 양 끝점, Anchor·Kiosk·Occupant·Icon 같은 Point 타입은 그 단일 좌표점.
- 즉 질문 "georeferencing 하는 점 = polygon 꼭짓점인가"에 대한 답은 **부분적으로만 맞다**: (1) 변환식을 만들기 위해 사람이 직접 다루는 점은 폴리곤 꼭짓점이 아니라 별도의 컨트롤 포인트이고, (2) 그 변환이 적용된 결과로 최종 좌표를 갖게 되는 대상은 폴리곤 꼭짓점뿐 아니라 라인스트링 끝점·포인트 피처까지 포함한 IMDF의 모든 geometry vertex다.

## 후속 조사 (2026-08-13, src07)

아래 미해결 질문 중 "ArcGIS Indoors Geodatabase → IMDF export 절차"는 `src07. FME·ArcGIS Indoors 툴 자체 조사.md`에서 해소됨: Esri 자체 기능이 아니라 ArcGIS Pro의 Data Interoperability Extension(FME 엔진 내장)으로 "ArcGIS Indoors Model to IMDF" FME 워크벤치를 실행하는 방식이며, 사전 작업으로 "Generate Unit Openings" 도구가 필요하다.

## 미해결 질문

- `support.safe.com`의 3부작 튜토리얼 원문 전체(코드/트랜스포머 스크린샷 포함)는 403 차단으로 대조하지 못함 — 검색 스니펫 인용에 그침.
- ~~ArcGIS Indoors Geodatabase에서 최종 IMDF(.geojson zip)로 export하는 정확한 절차~~ — src07에서 해결.
- register.apple.com FAQ 페이지의 제3자 IMDF 플랫폼 전체 목록 — 미확보.
- FME IMDF Writer가 요구하는 정확한 필수 파라미터(manifest 필드 등) — 이번 조사에서는 "Default Language", "Coordinate System", "Coordinate Precision"만 확인, 전체 파라미터 목록 미확보.
