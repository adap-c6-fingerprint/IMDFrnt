---
summary: "FP-to-IMDF 반자동화 앱 명세의 두 미해결 항목을 공식 문서로 확정. (1) IMDF Feature의 id는 RFC 4122 version 4 UUID여야 한다는 OGC 스펙 원문, (2) 지오레퍼런싱 변환 종류별 최소 컨트롤 포인트 개수(Esri 공식 문서), (3) IMDF의 Anchor는 지오레퍼런싱 기준점이 아니라 별개의 Feature Type이라는 용어 구분"
source: "docs.ogc.org/cs/20-094 (OGC IMDF 1.0.0) Reference·Anchor 페이지, desktop.arcgis.com (ArcMap Georeferencing 문서), pro.arcgis.com (ArcGIS Pro Overview of georeferencing)"
created: "2026-08-24 00:00"
updated: "2026-08-24 00:00"
---
# 지오레퍼런싱 기준점 최소 개수·Feature id UUID 요건 조사

## 수집 기준

- 수집일: 2026-08-24
- 목적: `02) Projects/06) Challenge 6/02) FP-to-IMDF 자동화/03) FTI 아키텍쳐.md` 0.1절에 남긴 미해결 항목 두 개를 확정하기 위한 조사.
  1. "IMDF Feature의 `id`는 UUID"라는 것이 추정인지 공식 명시인지.
  2. 명세가 "Anchor"라 부르는 지오레퍼런싱 기준점이 **몇 개 필요하고 왜 그런지**.
- 방법: OGC IMDF 1.0.0 Reference 페이지와 Anchor 페이지, Esri ArcGIS 공식 지오레퍼런싱 문서를 직접 조회해 원문 인용.

## 핵심 출처

- OGC IMDF 1.0.0 Reference: https://docs.ogc.org/cs/20-094/Reference/index.html
- OGC IMDF 1.0.0 Anchor: https://docs.ogc.org/cs/20-094/Anchor/index.html
- Esri, "Fundamentals for georeferencing a raster dataset" (ArcMap): https://desktop.arcgis.com/en/arcmap/latest/manage-data/raster-and-images/fundamentals-for-georeferencing-a-raster-dataset.htm
- Esri, "Overview of georeferencing" (ArcGIS Pro): https://pro.arcgis.com/en/pro-app/latest/help/data/imagery/overview-of-georeferencing.htm (2026-08-24 조회 시 doc.esri.com으로 301 리다이렉트, 리다이렉트 대상은 본문 취득 실패 — ArcMap 문서로 대체 확인)
- RFC 4122 §4.4: https://tools.ietf.org/html/rfc4122#page-14

---

## 1. Feature `id` — RFC 4122 version 4 UUID로 **명시되어 있음**

OGC IMDF 1.0.0 Reference 페이지 원문:

> "A Feature object **MUST** contain the GeoJSON `"id"` member with a `FEATURE-ID` value"

`FEATURE-ID`의 정의는 세 가지 요건을 강제한다.

> 1. "Feature IDs **MUST** be a globally unique, [RFC 4122](https://tools.ietf.org/html/rfc4122#page-14) compliant version 4 UUID"
> 2. "Feature IDs **MUST** be retained to identify the target feature during the lifetime of its existence across distinct deliveries"
> 3. "Feature IDs **MUST NOT** be re-assigned to another Feature of any type within the target dataset or any other"

같은 페이지의 `UUID` 데이터 타입 정의:

> "[RFC 4122, section 4.4](https://tools.ietf.org/html/rfc4122#page-14) compliant version 4 UUID"

**판정:** "IMDF의 id는 UUID"는 추정이 아니라 **공식 스펙에 MUST로 명시된 사실**이다. 버전까지 못 박혀 있다 — RFC 4122 §4.4는 **난수 기반 version 4** UUID를 정의하는 절이다(시각 기반 v1, 이름 기반 v3/v5가 아니다).

**추가로 확정된 두 가지 제약 (기존 조사에 없던 내용):**

- **id는 배포 간에 유지되어야 한다(요건 2).** 같은 방을 다시 내보낼 때마다 새 UUID를 발급하면 스펙 위반이다. 즉 도구는 발급한 UUID를 프로젝트 파일에 **영속 저장**해야 하며, 매 내보내기마다 새로 만들어서는 안 된다.
- **id는 어떤 Feature에도 재사용되어서는 안 된다(요건 3).** 삭제된 Feature의 UUID를 다른 Feature가 물려받는 동작을 만들면 안 된다.

---

## 2. IMDF의 `Anchor`는 지오레퍼런싱 기준점이 **아니다**

OGC IMDF 1.0.0 Anchor 페이지 원문:

> "An Anchor represents the curated Point used as the preferred display location of a specific Address OR non-addressable device, service, equipment or physical environment."

- geometry: "Anchor objects must have a `"geometry"` member with a `POINT` value"
- properties: `address_id` (`null` 또는 `ADDRESS-ID`), `unit_id` (`UNIT-ID` — "Unique identifier of the Unit the Anchor possesses a spatial relationship with")

**판정:** IMDF의 Anchor는 **최종 산출물에 실제로 저장되는 Feature Type 16종 중 하나**이며, 그 역할은 "주소나 입주자(Occupant)의 대표 표시 지점"이다. `src12` 5절이 정리한 대로, geometry가 `null`이어야 하는 Occupant의 좌표를 대신 갖는 점이다.

반면 도면을 실제 위경도에 정렬하기 위해 사람이 찍는 점은 **컨트롤 포인트(control point)**이고, `src06` 7절이 확인했듯 **최종 IMDF 파일에 남지 않는 계산용 입력값**이다. 두 개념은 이름이 비슷할 뿐 완전히 별개다.

→ FP-to-IMDF 앱 명세가 지오레퍼런싱 기준점을 "Anchor"라고 부르는 것은 **IMDF 공식 용어와 충돌**한다. 같은 명세의 좌측 사이드바 property type 목록에도 `anchor`가 이미 들어 있어(= Anchor Feature 생성 메뉴), 같은 화면에서 한 단어가 두 뜻으로 쓰이게 된다.

---

## 3. 지오레퍼런싱 컨트롤 포인트 — 변환 종류별 최소 개수

Esri "Fundamentals for georeferencing a raster dataset" 원문에서 확인한 최소 링크(컨트롤 포인트 쌍) 개수:

| 변환 종류 | 최소 링크 수 | 원문 |
|---|---|---|
| Zero-order shift (평행이동만) | 1 | "one for a zero-order shift" |
| First-order (affine, 어파인) | 3 | "three for a first-order affine" |
| Projective (투영) | 4 | "A minimum of four links are required" |
| Second-order polynomial | 6 | "six for a second order" |
| Third-order polynomial | 10 | "10 for a third order" |
| Spline | 10 | "Spline requires a minimum of 10 control points" |
| Adjust | 3 | "Adjust requires a minimum of three control points" |

1차(어파인) 변환의 능력에 대한 원문:

> A first-order transformation can "shift, scale, and rotate a raster dataset."
> "straight lines on the raster dataset [are] mapped as straight lines in the warped raster dataset"

오차 지표 정의 원문:

> **Residual error**: "the difference between where the from point ended up as opposed to the actual location that was specified—the to point position."
> **RMS error**: "taking the root mean square sum of all the residuals" — 이 값은 "how consistent the transformation is between the different control points (links)"를 나타낸다.

컨트롤 포인트 쌍의 정의(`src06` 7절에서 이미 확보한 원문 재수록):

> "The connection between one control point on the raster dataset (the **from point**) and the corresponding control point on the aligned target data (the **to point**) is a **control point pair**."

배치 권고:

> "spread the links over the entire raster dataset rather than concentrating them in one area... having at least one link near each corner... and a few throughout the interior."

---

## 4. 최소 개수의 수학적 근거 (자체 정리 — 공식 문서 인용 아님)

Esri 문서는 개수만 제시하고 이유는 설명하지 않으므로, 이유는 아래와 같이 자체 정리한다. **이 절은 원문 인용이 아니라 표준 선형대수에 근거한 유도이므로, 위키 문서에서도 출처를 그렇게 표기할 것.**

컨트롤 포인트 쌍 하나는 "x가 맞아야 한다", "y가 맞아야 한다" 두 개의 방정식을 준다. 따라서 필요한 최소 쌍 개수는 `ceil(미지수 개수 / 2)`다.

| 변환 | 미지수(자유도) | 필요한 방정식 | 최소 쌍 |
|---|---|---|---|
| 평행이동만 | 2 (dx, dy) | 2 | 1 |
| 상사(similarity) — 회전+등방 축척+평행이동 | 4 (a, b, dx, dy) | 4 | 2 |
| 어파인(affine) — 상사 + 비등방 축척 + 전단(skew) | 6 (a,b,c,d,dx,dy) | 6 | 3 |
| 투영(projective) | 8 | 8 | 4 |
| 2차 다항식 | 12 | 12 | 6 |
| 3차 다항식 | 20 | 20 | 10 |

- 상사 변환은 Esri 표에 별도 항목이 없지만(Esri는 1차를 어파인으로 통칭), 자유도 4이므로 **2쌍**이면 유일하게 결정된다.
- 최소 개수는 "유일해가 존재하는 하한"일 뿐이다. 정확히 최소 개수만 쓰면 방정식 수 = 미지수 수라 **잔차가 항상 0**이 되어, 사람이 점을 잘못 찍었는지 알 방법이 없다. 한 쌍이라도 더 있어야 최소자승 해와 함께 잔차·RMS가 나오고, 그 값으로 오지정을 검출할 수 있다. Esri 문서의 "코너마다 하나 + 내부에 몇 개" 권고가 이 이유와 맞물린다.

---

## 미해결 질문

- Apple Indoor Maps Program이 IMDF 제출물의 지오레퍼런싱 정확도에 요구하는 **정량 기준**(허용 오차 m 단위)이 공식 문서에 있는지 — 미확인.
- ArcGIS Pro(최신) 문서의 동일 내용은 2026-08-24 조회 시 doc.esri.com 리다이렉트 후 본문 취득에 실패했다. 위 개수는 ArcMap 문서 기준이며, ArcGIS Pro 최신판에서 값이 바뀌었는지 재확인 필요.
- SVG 도면처럼 **축척이 이미 균일하고 직교성이 보장된** 입력에서는 어파인(3쌍)까지 갈 필요 없이 상사 변환(2쌍)이면 충분한가 — 실무 검증 자료 미확보.
