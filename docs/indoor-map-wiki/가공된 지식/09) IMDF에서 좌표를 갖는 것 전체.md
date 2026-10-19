---
summary: IMDF .geojson 파일에서 실제 좌표가 기록되는 모든 자리를 전수 정리. 좌표는 geometry 멤버와 properties.display_point 두 곳에 나뉘어 들어가며, Feature Type 16종 중 12종이 geometry 좌표를, 9종이 display_point 좌표를 갖는다
source: 01-2) 소스 --------------------/S06) Indoor Map/S06-02) FP-to-IMDF/src12. IMDF 좌표 보유 지점 전수 조사 — geometry·display_point 이원 구조.md
related:
  - "[[IMDF]]"
  - "[[GeoJSON]]"
  - "[[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]]"
  - "[[08) IMDF Feature Type·카테고리 전체 레퍼런스]]"
  - "[[Display Point]]"
  - "[[지오레퍼런싱]]"
  - "[[06) GeoJSON 디코딩과 렌더링 과정 — MapKit·MapKit JS]]"
created: 2026-08-20 00:00
updated: 2026-08-20 00:00
core_keywords:
  - IMDF
  - Display Point
  - Feature Type
---
# IMDF에서 좌표를 갖는 것 전체

## 요약

질문은 이것이었다. **".geojson에 좌표로 표시되어야 하는 점은 결국 Unit polygon ring의 꼭짓점들과 문 양 끝 좌표뿐인가?"**

답은 **아니다**. 두 가지 이유에서 그렇다.

1. **좌표를 갖는 Feature Type이 Unit·Opening 말고도 10종 더 있다.** Venue·Footprint·Level·Section·Geofence·Fixture·Kiosk가 폴리곤을, Detail이 선형을, Amenity·Anchor가 점을 갖는다.
2. **좌표가 기록되는 자리가 `geometry` 하나가 아니다.** `properties` 객체 안의 **`display_point`**가 별도의 GeoJSON Point 좌표를 담는다. 이건 도형이 아니라 "라벨을 어디에 찍을지"를 지정하는 좌표다.

두 번째가 특히 놓치기 쉽다. 사각형 방 하나는 꼭짓점 4개가 아니라 **꼭짓점 4개 + display_point 1개 = 좌표점 5개**를 갖는다.

---

## 1. 좌표는 두 자리에 들어간다

IMDF Feature는 GeoJSON Feature이므로 `geometry` 멤버에 도형 좌표를 담는다. 그런데 OGC 스펙의 Reference 페이지는 `properties` 안에도 좌표가 들어가는 필드를 정의한다.

> "A Display Point represents a curated, Point-based representation of a non-puntal Feature."
> - "Display Points are members of a Feature's `"property"` object"
> - "Display Points **MUST** be captured as GeoJSON Point objects"
> - "Display Points **MUST** be **within** the geometry of the Feature that possesses it"
> - "Display Points **SHOULD** be positioned in a location where map label 'collision' is least expected"
> — [OGC IMDF 1.0.0, Reference](https://docs.ogc.org/cs/20-094/Reference/index.html)

**non-puntal**은 "점이 아닌"이라는 뜻이다. 폴리곤이나 선처럼 넓이·길이를 가진 피처를 지도 위에서 점 하나로 대표해야 할 때(라벨을 찍거나 아이콘을 놓을 때) 그 위치를 지정하는 것이 display_point다.

세 번째 규칙이 실무상 중요하다. **display_point는 그 피처의 geometry 안에 있어야 한다.** L자 모양 방처럼 오목한 도형에서 단순 중심점(centroid)을 계산하면 도형 바깥으로 나갈 수 있는데, 그러면 규정 위반이다. 네 번째 규칙("라벨 충돌이 가장 적을 위치")은 자동 계산이 아니라 **사람의 판단(curated)**이 개입한다는 뜻이다.

```json
{
  "type": "Feature",
  // GeoJSON의 최상위 단위. "도형 하나 + 그에 붙는 정보"를 한 덩어리로 묶은 것이 Feature다.
  // Feature는 항상 geometry와 properties 두 멤버로 나뉜다 — 이 분리가 GeoJSON 표준(RFC 7946) 자체의 규칙이다.

  "feature_type": "unit",
  // IMDF가 GeoJSON에 추가한 필드. 이 Feature가 16종 중 무엇인지를 말한다.

  "geometry": {
  // ── 좌표 자리 ① : "이 사물이 어디에 어떤 모양으로 있는가" ──
  // 공간 그 자체를 기술하는 자리다. 여기 들어가는 것은 오직 도형뿐이며,
  // 타입(Polygon/LineString/Point)과 좌표 배열 외의 다른 정보는 넣을 수 없다.
  // 지도 렌더러가 실제로 "그리는" 대상이 이 부분이다.

    "type": "Polygon",
    // 도형의 종류. IMDF는 Feature Type별로 이 값을 강제한다(Unit은 POLYGONAL 필수).

    "coordinates": [[ [x1,y1], [x2,y2], [x3,y3], [x4,y4], [x1,y1] ]]
    // 방의 네 꼭짓점. 마지막에 첫 점을 반복해 링을 닫는다.
  },

  "properties": {
  // ── "이 사물이 무엇이고 어떤 성질을 갖는가" ──
  // 도형에 붙는 부가 정보를 담는 자유 형식 JSON 객체다.
  // GeoJSON 표준은 이 안의 구조를 규정하지 않는다 — 무엇을 넣을지는 각 포맷이 정하며,
  // IMDF가 정한 것이 category·name·level_id·display_point 같은 필드다.

    "category": "conferenceroom",
    // 분류. 좌표가 아니라 열거값 문자열이다.

    "name": { "ko": "회의실 A" },
    // 이름. 언어 태그를 key로 하는 LABELS 타입.

    "display_point": { "type": "Point", "coordinates": [xd, yd] },
    // ── 좌표 자리 ② : properties 안에 있지만 엄연한 좌표다 ──
    // 여기가 예외 지점이다. properties는 원래 "성질"을 담는 자리인데,
    // display_point만은 그 안에서 GeoJSON Point 객체를 통째로 담는다.
    // 도형이 아니라 "이 방의 이름표를 어느 지점에 찍을 것인가"를 지정하는 좌표라서
    // geometry(도형)가 아닌 properties(그 도형에 대한 정보) 쪽에 놓인 것이다.

    "level_id": "..."
    // 다른 Feature를 가리키는 참조. 좌표가 아니라 UUID 문자열이다.
  }
}
```

**정리하면 이렇다.**

|             | `geometry`                       | `properties`                     |
| ----------- | -------------------------------- | -------------------------------- |
| 무엇을 담는가     | 사물의 **위치와 모양**                   | 사물의 **성질과 정보**                   |
| 구조를 누가 정하는가 | GeoJSON 표준(RFC 7946)이 타입 5종으로 고정 | 표준은 규정하지 않음 — IMDF가 필드를 정의       |
| 값의 형태       | 좌표 배열뿐                           | 문자열·숫자·불리언·객체 등 자유               |
| 렌더러의 취급     | 화면에 **그리는** 대상                   | 그릴 때 참조하는 **부가 정보**(색·라벨·아이콘 결정) |
| 좌표가 들어가는가   | **항상**                           | **display_point에 한해서만**          |
|             |                                  |                                  |

`geometry`가 "이 도형이 지도의 어디에 놓이는가"라면, `properties`는 "그 도형이 무엇인가"다. 문제는 **`display_point`가 이 구분을 가로지른다**는 점이다. 값의 형태로 보면 좌표이지만, 역할로 보면 "이 방의 이름표 위치"라는 방에 대한 정보이므로 `properties`에 놓였다.

이 때문에 GeoJSON을 다루는 일반적인 도구가 IMDF에서 실수하기 쉽다. **"좌표는 geometry에만 있다"고 가정하고 만든 파서·변환기는 display_point를 놓친다.** [[06) GeoJSON 디코딩과 렌더링 과정 — MapKit·MapKit JS]]에서 정리한 대로 MapKit의 `MKGeoJSONFeature`가 `properties`를 해석되지 않은 `Data`로 넘겨주는 것도 같은 맥락이다 — 표준은 properties 안을 들여다보지 않으므로, 그 안의 display_point를 좌표로 쓰려면 **개발자가 직접 2차 디코딩**을 해야 한다.

---

## 2. geometry 값 타입 5종

스펙 Reference 페이지가 정의하는 geometry 값 타입은 다음과 같다.

| 값 타입 | 원문 정의 | 실제 의미 |
| --- | --- | --- |
| `POINT` | "GeoJSON `Point` geometry" | 점 1개 |
| `LINE-STRING` | "GeoJSON `LineString` geometry" | 선분 하나 |
| `LINEAL` | "`LINE-STRING` or `MULTI-LINE-STRING`" | 선분 하나 **또는 여러 개 묶음** |
| `POLYGONAL` | "`POLYGON` or `MULTI-POLYGON` geometry" | 폴리곤 하나 **또는 여러 개 묶음** |
| `GEOMETRY` | "GeoJSON `Geometry` object" | 아무 도형 |

**`POLYGONAL`이 MultiPolygon을 포함한다는 점이 중요하다.** Unit·Level·Section 등이 모두 `POLYGONAL`로 규정되어 있으므로, **하나의 Unit이 물리적으로 떨어진 여러 폴리곤으로 구성될 수 있다.** 자동 변환 도구를 만든다면 "Unit 하나 = 링 하나"로 가정해서는 안 된다.

마찬가지로 Detail은 `LINEAL`이라 MultiLineString이 가능하지만, **Opening은 `LINE-STRING`(단수)로 규정되어 MultiLineString이 불가하다.** 문 하나는 반드시 연속된 선분 하나여야 한다.

---

## 3. Feature Type 16종 — 좌표 보유 전수표

|     | Feature Type     | 의미                                                                                                            | geometry         | display_point |
| --- | ---------------- | ------------------------------------------------------------------------------------------------------------- | ---------------- | ------------- |
|     | **Venue**        | 시설 전체의 최상위 단위 — 이 IMDF가 다루는 부지 하나                                                                             | POLYGONAL        | ✅ **필수**      |
|     | **Level**        | 건물의 한 층 — 그 층에 속한 모든 피처의 기준면                                                                                  | POLYGONAL        | ✅ (null 허용)   |
| ㅇ   | **Unit**         | 층 안의 개별 공간 — 경계는 벽 같은 barrier뿐 아니라 물리적 경계나 임대 면적 같은 법적 구획으로도 정해진다                                             | POLYGONAL        | ✅ (null 허용)   |
|     | **Section**      | 테마(theme)의 범위 — 경계는 문턱이거나 불분명할 수 있다. 푸드코트·보안구역처럼 Unit 위에 겹쳐 덮이는 주제 구역                                         | POLYGONAL        | ✅ (null 허용)   |
|     | **Geofence**     | 지오펜스의 범위 — 카테고리는 concourse·paidarea·platform·presecurity·postsecurity·terminal·underconstruction 등 운영·통제 구역 ※ | POLYGONAL        | ✅ (null 허용)   |
| ㅇ   | **Fixture**      | 이동 가능하거나 반영구적인 물리적 자산 — 매대·수하물 벨트 등. Unit이 아니라 Level에 직접 소속된다                                                 | POLYGONAL        | ✅ (null 허용)   |
|     | **Kiosk**        | 제품·서비스를 판매·제공하는 가구(furniture)의 물리적 범위 — 그 안에서 영업하는 사업체는 기술하지 않는다                                              | POLYGONAL        | ✅ (null 허용)   |
|     | **Footprint**    | 하나 이상의 Building이 지표면에 차지하는 대략적 외곽 형태                                                                          | POLYGONAL        | ❌             |
|     | **Opening**      | Unit 경계에 뚫린 통행 지점 — 문·출입구                                                                                     | LINE-STRING      | ✅ (null 허용)   |
|     | **Detail**       | 실재하는 물리적 객체를 선형으로 표현한 것 — 지도상 인식은 주변 맥락에 크게 의존한다                                                              | LINEAL           | ❌             |
| ㅇ   | **Amenity**      | 보행자 편의를 위한 시설의 물리적 존재와 대략적 지점 — 화장실·전화기·수유실 등                                                                 | POINT            | ❌             |
|     | **Anchor**       | 주소·점유자를 실제 위치에 못 박는 기준점                                                                                       | POINT            | ❌             |
|     | **Building**     | 부지 안의 건물 한 동 — 형태는 Footprint가 대신 가짐                                                                           | **null 필수**      | ✅ (null 허용)   |
|     | **Occupant**     | 공간을 쓰는 주체 — 입점 브랜드·상호 정보                                                                                      | **null 필수**      | ❌             |
|     | **Address**      | 우편 주소 정보 그 자체                                                                                                 | **null 필수**      | ❌             |
|     | **Relationship** | 피처끼리의 연결 관계 — 경로·인접성 표현                                                                                       | null 또는 GEOMETRY | ❌             |

> ※ **Geofence만 정의 원문이 "A Geofence models the extent of a geofence."라는 동어반복이다.** OGC 개별 페이지를 재조회해도 목적·용도를 설명하는 문장이 없어(2026-08-20 재확인), 위 서술은 `GEOFENCE-CATEGORY` 열거값 8종에서 역추론한 것이다. 나머지 15종은 스펙 정의 원문 기반이다.

### 눈여겨볼 조합 세 가지

**① Building — 도형 없이 좌표만 갖는다**

Building은 geometry가 `null` 필수인데 display_point는 가질 수 있다. 건물의 모양은 Footprint가 갖고, 건물 이름을 찍을 위치는 Building이 갖는 구조다.

> **확인 필요:** DISPLAY-POINT 규정은 "그 피처의 geometry 안에 있어야 한다"고 하는데, Building의 geometry는 null이다. 이 둘이 어떻게 양립하는지 스펙에 설명이 없다.

**② Amenity·Anchor — geometry가 이미 점이라 display_point가 없다**

DISPLAY-POINT 정의가 "non-puntal Feature"(점이 아닌 피처)의 점 표현이라고 명시하므로 일관적이다. 이미 점인 것에 대표점을 또 둘 이유가 없다.

> **Amenity는 Unit당 1개가 아니다.** 스펙은 "**Multiple Amenities MAY be within a single Unit**"이라고 명시한다. 그리고 Amenity는 `level_id`가 아니라 **`unit_ids`(UNIT-ID 배열, 필수)**로 Unit에 연결되므로, 하나의 Amenity가 여러 Unit에 걸칠 수도 있다. 즉 **Amenity ↔ Unit은 다대다(N:M) 관계**다. 화장실 한 칸(Unit)에 `restroom`·`babychanging`·`handsanitizerstation` Amenity가 함께 놓이거나, 여러 Unit에 걸친 넓은 대합실 하나에 `seating` Amenity가 걸리는 식이다. 좌표 관점에서는 **Unit 하나에 Amenity Point가 0개일 수도, 여러 개일 수도 있다.**

**③ Footprint·Detail — 도형이 있는데 display_point가 없다**

Footprint는 건물 이름 라벨을 Building이 대신 갖기 때문이고, Detail은 애초에 properties가 `level_id` 하나뿐이라 이름도 카테고리도 없다. 라벨을 찍을 대상이 없으니 대표점도 필요 없다.

---

## 4. Feature Type별 좌표 개수

| geometry 타입 | Feature Type | 좌표 개수 |
| --- | --- | --- |
| POLYGONAL | Venue, Footprint, Level, Unit, Section, Geofence, Fixture, Kiosk (8종) | 링당 꼭짓점 N개 + 시작점 반복 1 |
| LINE-STRING | Opening (1종) | 보통 2개 |
| LINEAL | Detail (1종) | 가변 |
| POINT | Amenity, Anchor (2종) | 1개 |
| null 필수 | Building, Occupant, Address (3종) | 0개 (Building은 display_point만) |
| null 또는 GEOMETRY | Relationship (1종) | 0개 또는 가변 |

**좌표를 갖는 Feature Type은 12종**이고, Relationship이 선택적으로 13번째가 된다.

---

## 5. 위치를 남에게 위임하는 세 피처

geometry가 `null` 필수인 세 Feature Type은 좌표를 스스로 갖지 않고 다른 피처를 참조한다.

| Feature | 위치를 어디서 얻는가 |
| --- | --- |
| **Building** | 모양은 **Footprint**(`building_ids`로 역참조), 라벨 위치는 자기 `display_point` |
| **Occupant** | `anchor_id` → **Anchor**의 Point 좌표 |
| **Address** | 좌표 없음. Anchor·Venue·Level 등이 `address_id`로 참조 |

**Anchor의 역할이 특히 설계적으로 흥미롭다.**

> "An Anchor represents the curated Point used as the preferred display location of a specific Address OR non-addressable device, service, equipment or physical environment."
> — [OGC IMDF 1.0.0, Anchor](https://docs.ogc.org/cs/20-094/Anchor/index.html)

스펙이 밝히는 Anchor의 용도 중 하나가 **"decoupling static Address locations from frequently updated content like Occupant records"** — 자주 바뀌는 입주 업체 레코드로부터 고정된 주소 위치를 분리하는 것이다.

쇼핑몰에서 한 자리의 매장이 바뀌는 상황을 생각하면 이 설계가 이해된다. 좌표를 Occupant가 직접 갖고 있으면 업체가 바뀔 때마다 좌표를 다시 입력해야 한다. Anchor가 좌표를 갖고 Occupant는 `anchor_id`만 참조하면, **업체 교체는 Occupant 레코드만 갈아끼우면 끝난다.** Kiosk·Fixture·Amenity도 같은 이유로 `anchor_id`를 갖는다.

---

## 6. 그래서 사각형 방 하나는 좌표를 몇 개 갖는가

[[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]]에서 다룬 사각형 방 예시를 다시 세어 보면 이렇다.

**방 자체 (Unit Feature 1개)**
- 폴리곤 링 꼭짓점 **4개** (배열 표기상으로는 첫 점이 반복되어 좌표쌍 5개)
- display_point **1개**
- → 실질 좌표점 **5개**

**그 방에 딸린 것들**
- 문이 하나 있다면 Opening Feature 1개 → LineString 양 끝점 **2개** + display_point **1개** = **3개**
- 방 안에 책상이 있고 Fixture로 모델링한다면 → 폴리곤 꼭짓점 N개 + display_point 1개
- 방에 업체가 입주해 있다면 Occupant는 좌표 0개, 대신 Anchor **1개**
- 편의시설이 있다면 Amenity Point — **개수 제한 없음.** Unit당 1개가 아니라 0개일 수도, 여러 개일 수도 있다("Multiple Amenities MAY be within a single Unit")

**그 방을 담는 상위 구조 (방마다 반복되지는 않음)**
- Level 폴리곤 + display_point
- Footprint 폴리곤
- Venue 폴리곤 + display_point(필수)
- Building은 좌표 0개(display_point만)

즉 "Unit 꼭짓점과 문 양 끝점"은 **좌표의 일부**이지 전부가 아니다.

---

## 7. 자동 변환 도구 설계에 주는 함의

[[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]]이 도면에서 좌표를 뽑는 방법을 다뤘다면, 이 문서는 **뽑은 좌표를 어디에 채워 넣어야 하는지**의 목록이다.

- **display_point를 빠뜨리기 쉽다.** 폴리곤만 만들고 끝내면 라벨 위치가 비게 된다. 9종(Venue·Level·Unit·Section·Geofence·Fixture·Kiosk·Opening·Building)에 대해 채워야 하며, **Venue는 필수**라 비워둘 수 없다.
- **display_point 자동 계산은 단순 centroid로는 부족하다.** "MUST be within the geometry" 규정 때문에 L자·U자 형태 방에서 중심점이 도형 밖으로 나가면 검증에 걸린다. 폴리곤 내부를 보장하는 점(예: point-on-surface 계열 연산)을 써야 한다.
- **MultiPolygon을 전제해야 한다.** `POLYGONAL` 타입 8종은 모두 MultiPolygon이 가능하다. "Unit = 링 하나"로 가정한 자료구조는 나중에 깨진다.
- **Opening만은 단일 LineString이다.** MultiLineString을 만들면 스펙 위반이다.
- **좌표 0개인 Feature도 출력해야 한다.** Building·Occupant·Address는 geometry가 `null`이지만 IMDF 아카이브에 반드시 들어간다. 도형이 없다고 건너뛰면 안 된다.
- **지오레퍼런싱 변환식은 두 자리 모두에 적용해야 한다.** [[지오레퍼런싱]]에서 정리한 회전·스케일·이동 변환을 `geometry`에만 적용하고 `display_point`를 빠뜨리면, 도형은 제자리인데 라벨만 엉뚱한 곳에 찍힌다.

---

## 관련 링크

- [[07) 도면의 방·문·창이 IMDF 좌표가 되는 기준]] — 도면에서 이 좌표들을 어떤 기준으로 뽑아내는가
- [[08) IMDF Feature Type·카테고리 전체 레퍼런스]] — 각 Feature Type의 category·속성 전체
- [[Display Point]] — display_point 데이터 타입 자체
- [[지오레퍼런싱]] — 이 좌표 전체에 지구 좌표를 부여하는 단계
- [[GeoJSON]] — geometry와 properties가 나뉘는 파일 구조
- [[06) GeoJSON 디코딩과 렌더링 과정 — MapKit·MapKit JS]] — properties가 파서에서 불투명하게 넘어와 2차 디코딩이 필요한 이유
- [[05) 라벨에 관하여]] — display_point가 라벨 표시에서 하는 역할

## 미해결 질문

- Building은 geometry가 `null`인데 display_point를 가질 수 있다. "display_point는 그 피처의 geometry 안에 있어야 한다"는 규정과 어떻게 양립하는가 — 스펙에 설명 없음.
- `display_point`가 `null`일 때 MapKit 등 렌더러는 라벨 위치를 어떻게 정하는가(폴리곤 중심 자동 계산?) — 스펙 범위 밖, MapKit 문서 확인 필요.
- Venue만 display_point가 필수인 이유 — 근거 문장 미확인.
- Relationship이 geometry를 갖는 "curated path"의 실제 사용 사례와 그 geometry 타입 — 미확인.
- IMDFValidator가 "display_point가 geometry 안에 있는가"를 실제로 검사하는가 — Validations 페이지 미조사.
