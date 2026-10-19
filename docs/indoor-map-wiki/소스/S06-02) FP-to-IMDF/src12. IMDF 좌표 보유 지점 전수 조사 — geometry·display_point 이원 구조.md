---
summary: "IMDF .geojson 파일에서 실제 좌표가 기록되는 모든 자리를 전수 조사. Feature Type 16종의 geometry 타입(POLYGONAL/LINEAL/POINT/null)과, geometry와 별개로 properties 안에 좌표를 담는 display_point(DISPLAY-POINT) 필드의 보유 여부를 OGC IMDF 1.0.0 개별 페이지에서 확인"
source: "docs.ogc.org/cs/20-094 (OGC IMDF 1.0.0) — Reference 및 Feature Type 16개 개별 페이지"
created: "2026-08-20 00:00"
updated: "2026-08-20 00:00"
---
# IMDF 좌표 보유 지점 전수 조사 — geometry·display_point 이원 구조

## 수집 기준

- 수집일: 2026-08-20
- 목적: `src10`은 "방=Unit Polygon 꼭짓점, 문=Opening LineString 양 끝점"을 확인했고, `src11`은 Feature Type 16종의 geometry 타입을 정리했다. 사용자가 "그럼 결국 .geojson에 좌표로 표시되는 점은 Unit polygon ring 꼭짓점과 문 양끝 좌표뿐인가"를 물음에 따라, **좌표가 기록되는 모든 자리**를 빠짐없이 확인.
- 방법: OGC IMDF 1.0.0의 Reference 페이지(geometry 값 타입 정의, DISPLAY-POINT 정의)와 Feature Type 16개 개별 페이지의 properties 표를 각각 조회해 `geometry` 타입과 `display_point` 보유 여부를 전수 대조.

## 핵심 출처

- Reference(geometry 값 타입·DISPLAY-POINT 정의): https://docs.ogc.org/cs/20-094/Reference/index.html
- Feature Type 개별 페이지 16종: `https://docs.ogc.org/cs/20-094/{...}/index.html`

## 1. 핵심 발견 — 좌표는 두 자리에 기록된다

`src10`·`src11`까지의 조사는 암묵적으로 "좌표 = `geometry` 멤버"로 전제했다. 그러나 Reference 페이지의 DISPLAY-POINT 정의가 이를 뒤집는다.

> "A Display Point represents a curated, Point-based representation of a non-puntal Feature."
> - "Display Points are members of a Feature's `"property"` object"
> - "Display Points **MUST** be captured as GeoJSON Point objects"
> - "Display Points **MUST** be within the geometry of the Feature that possesses it"
> - "Display Points **SHOULD** be positioned in a location where map label 'collision' is least expected"

→ **`display_point`은 `properties` 객체 안에 있으면서 GeoJSON Point 좌표를 담는다.** 즉 IMDF Feature 하나가 좌표를 갖는 자리는 `geometry`와 `properties.display_point` **두 곳**이다. 이 사실은 `src04` 3절에서 DISPLAY-POINT 정의를 인용했으나 "좌표 보유 지점"이라는 관점으로는 정리되지 않았던 부분이다.

## 2. Reference — geometry 값 타입 정의 (원문)

| 값 타입 | 원문 정의 |
| --- | --- |
| `GEOMETRY` | "GeoJSON `Geometry` object" |
| `POINT` | "GeoJSON `Point` geometry" |
| `LINE-STRING` | "GeoJSON `LineString` geometry" |
| `LINEAL` | "`LINE-STRING` or `MULTI-LINE-STRING`" |
| `POLYGONAL` | "`POLYGON` or `MULTI-POLYGON` geometry" |

→ **`POLYGONAL`은 MultiPolygon을 포함한다.** 즉 Unit·Level·Section 등도 여러 개의 분리된 링을 가질 수 있다. `src11`에서 Footprint만 "Polygon/MultiPolygon"으로 기록했으나, 실제로는 `POLYGONAL`로 규정된 모든 타입이 동일하다.
→ **`LINEAL`도 MultiLineString을 포함한다.** Detail이 `LINEAL`이므로 Detail은 여러 선분 묶음을 하나의 Feature로 담을 수 있다. 반면 Opening은 `LINE-STRING`(단수)으로 규정되어 MultiLineString이 불가하다.

## 3. Feature Type 16종 — geometry 타입과 display_point 보유 여부 (개별 페이지 원문 확인)

| Feature Type | geometry 규정 원문 | display_point |
| --- | --- | --- |
| Venue | "MUST have a `"geometry"` member with a polygonal value" | **있음(필수)** |
| Level | "Level objects **MUST** have a `"geometry"` member with a `POLYGONAL` value" | 있음 (null 허용) |
| Unit | "Unit objects **MUST** have a `"geometry"` member with a `POLYGONAL` value" | 있음 (null 허용) |
| Section | "Section objects **MUST** have a `"geometry"` member with a `POLYGONAL` value" | 있음 (null 허용) |
| Geofence | "MUST have a 'geometry' member with a POLYGONAL value" | 있음 (null 허용) |
| Fixture | "Fixture objects MUST have a `"geometry"` member with a `POLYGONAL` value" | 있음 (null 허용) |
| Kiosk | "Kiosk objects **MUST** have a `"geometry"` member with a `POLYGONAL` value" | 있음 (null 허용) |
| Footprint | "Footprint objects **MUST** have a `"geometry"` member with a `POLYGONAL` value" | **없음** |
| Opening | "Opening objects **MUST** have a `"geometry"` member with a `LINE-STRING` value" | 있음 (null 허용) |
| Detail | "Detail objects must have a `"geometry"` member with a LINEAL value" | **없음** |
| Amenity | "Amenity objects **MUST** have a `'geometry'` member with a `POINT` value" | **없음** |
| Anchor | "Anchor objects must have a `"geometry"` member with a `POINT` value" | **없음** |
| Building | "Building objects must have a `"geometry"` member with a `null` value" | 있음 (null 허용) |
| Occupant | "Occupant objects must have a `"geometry"` member with a `null` value" | 없음 |
| Address | "Address objects must have geometry set to `null` value" | 없음 |
| Relationship | "Relationship objects **MAY** have a `"geometry"` member with a `null` or `GEOMETRY` value" | 없음 |

**주의할 조합 3가지**

1. **Building** — geometry는 `null` 필수인데 `display_point`는 가질 수 있다. 즉 **도형 없이 좌표만 갖는 Feature**가 성립한다. 다만 DISPLAY-POINT 규정 "MUST be within the geometry of the Feature that possesses it"과 충돌 소지가 있다(geometry가 null인데 그 안에 있어야 한다?). **확인 필요.**
2. **Amenity / Anchor** — geometry가 이미 Point이므로 `display_point`가 없다. DISPLAY-POINT 정의가 "non-puntal Feature"(점이 아닌 피처)의 점 표현이라고 명시하므로 일관적이다.
3. **Footprint / Detail** — 폴리곤·선형이면서도 display_point가 없다. Footprint는 Building이 display_point를 대신 갖고, Detail은 properties가 `level_id` 하나뿐이다.

## 4. 각 Feature Type의 좌표 개수 특성

| geometry 타입 | 해당 Feature Type | 좌표 개수 |
| --- | --- | --- |
| POLYGONAL (Polygon/MultiPolygon) | Venue, Footprint, Level, Unit, Section, Geofence, Fixture, Kiosk (8종) | 링당 꼭짓점 N개 + 시작점 반복 1개 |
| LINE-STRING | Opening (1종) | 보통 2개 (양 끝점) |
| LINEAL (LineString/MultiLineString) | Detail (1종) | 가변 |
| POINT | Amenity, Anchor (2종) | 1개 |
| null 필수 | Building, Occupant, Address (3종) | 0개 (단 Building은 display_point 가능) |
| null 또는 GEOMETRY | Relationship (1종) | 0개 또는 가변 |

→ 합계 16종. **좌표를 갖는 Feature Type은 12종**(POLYGONAL 8 + LINE-STRING 1 + LINEAL 1 + POINT 2)이고, Relationship은 선택적으로 갖는다.

## 5. Anchor의 위상 — Occupant의 좌표를 대신 갖는 점

> "An Anchor represents the curated Point used as the preferred display location of a specific Address OR non-addressable device, service, equipment or physical environment."

- geometry: POINT 필수
- properties: `address_id`(null 허용), `unit_id`(UNIT-ID)
- 용도 원문 요지: 편집 도구의 스냅 동작 지원, ID·주소 매칭으로 주소 대상 엔티티의 점 위치 도출, 그리고 **"decoupling static Address locations from frequently updated content like Occupant records"** — 자주 바뀌는 Occupant 레코드로부터 고정된 주소 위치를 분리.

→ Occupant는 geometry가 `null` 필수이므로 **입주 업체의 좌표는 Occupant가 아니라 Anchor가 갖는다.** Kiosk·Fixture·Amenity도 `anchor_id`로 Anchor를 참조한다.

## 6. Amenity의 unit_ids

- geometry: POINT 필수 (multipoint 불가)
- properties: `category`, `accessibility`, `name`, `alt_name`, `hours`, `phone`, `website`, `unit_ids`, `address_id`, `correlation_id`
- `unit_ids`: "JSON array of `UNIT-ID`" — "Unique identifier of the Unit(s) the Amenity is associated with". properties 표에 null 옵션이 없어 **필수**이며, 복수 식별자를 담을 수 있다.
- **카디널리티 규정 원문:** "**Multiple Amenities MAY be within a single Unit**"

→ Amenity는 `level_id`가 아니라 `unit_ids`(복수 배열)로 Unit에 연결되며, **Unit당 1개가 아니라 다대다(N:M) 관계**다. 한 Unit 안에 여러 Amenity가 있을 수 있고(위 규정), 하나의 Amenity가 여러 Unit에 연결될 수도 있다(`unit_ids` 배열).

공식 예시 JSON:
```json
{
  "id": "11111111-1111-1111-1111-111111111111",
  "type": "Feature",
  "feature_type": "amenity",
  "geometry": { "type": "Point", "coordinates": [1.0, 2.0] },
  "properties": {
    "category": "phone",
    "accessibility": ["tdd", "trs"],
    "name": null, "alt_name": null, "phone": null, "website": null, "hours": null,
    "unit_ids": ["22222222-2222-2222-2222-222222222222"],
    "address_id": null, "correlation_id": null
  }
}
```

## 7. 종합 — .geojson에 좌표로 남는 것 전체

사용자 질문("Unit polygon ring 꼭짓점과 문 양끝 좌표뿐인가")에 대한 답: **아니다.** 좌표가 기록되는 자리는 다음과 같다.

**A. `geometry` 멤버 (12종 + Relationship 선택)**
1. Venue Polygon 링 꼭짓점
2. Footprint Polygon/MultiPolygon 링 꼭짓점
3. Level Polygon 링 꼭짓점
4. Unit Polygon 링 꼭짓점
5. Section Polygon 링 꼭짓점
6. Geofence Polygon 링 꼭짓점
7. Fixture Polygon 링 꼭짓점
8. Kiosk Polygon 링 꼭짓점
9. Opening LineString 양 끝점
10. Detail LineString/MultiLineString 정점
11. Amenity Point 1점
12. Anchor Point 1점
13. (Relationship이 curated path를 담는 경우 그 정점)

**B. `properties.display_point` (8종)**
Venue(필수), Level, Unit, Section, Geofence, Fixture, Kiosk, Opening, Building — 각 1점씩.
※ Building은 geometry가 null이면서 display_point만 갖는 특수 사례.

→ 즉 하나의 Unit Feature는 **폴리곤 꼭짓점 N개 + display_point 1개**를 갖는다. 사각형 방이면 좌표점이 4개가 아니라 **5개**(꼭짓점 4 + display_point 1)이며, GeoJSON 링 표기상 첫 점이 반복되므로 배열에 나타나는 좌표쌍은 6개다.

## 미해결 질문

- Building은 geometry가 `null` 필수인데 `display_point`를 가질 수 있다. DISPLAY-POINT의 "MUST be within the geometry of the Feature that possesses it" 규정과 어떻게 양립하는가 — 스펙에 설명 없음.
- `display_point`가 `null`일 때 렌더러(MapKit 등)는 라벨 위치를 어떻게 정하는가(폴리곤 중심점 자동 계산?) — 스펙 범위 밖, MapKit 문서 확인 필요.
- Relationship이 geometry를 갖는 "curated path"의 실제 사용 사례와 geometry 타입(LineString?) — 미확인.
- Venue의 display_point가 필수인 이유(다른 폴리곤 피처는 모두 null 허용) — 스펙에 근거 문장 미확인.
