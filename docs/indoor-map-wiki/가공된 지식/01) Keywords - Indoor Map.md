### 지침
1. /Users/sionlee/Desktop/LLM Wiki/전자두뇌/01) Wiki/01-2) 소스 --------------------/S06) Indoor Map/S06-01) Indoor Map Overall/WWDC19 - Introducing the Indoor Maps Program.md를 바탕으로, 원문에 등장하는 키워드 (원어 그대로) 를 리스트업하세요.
2. 키워드는 20개 리스트업합니다. 10개는 기술 용어, 10개는 기술 용어의 서술어입니다. ex) "인스턴스를 반환하다" 라는 문장에서, '인스턴스'는 기술 용어고, '반환하다'는 기술 용어의 서술어입니다.
3. 해당 키워드가 등장하는 원문의 문장을 키워드별로 그대로 긁어 와서 리스트업하세요.
4. 키워드의 한국어 정의, 원문 문장의 한국어 번역을 함께 기재하세요.
5. 표 형태로 정리하세요. 키워드, 뜻 | 예문, 예문 뜻 순서로 정리합니다.
6. 대상 독자는 영어 실력이 초보자 수준인 iOS 개발자입니다.

---

# Keywords — WWDC19 Introducing the Indoor Maps Program

출처: `01-2) 소스 --------------------/S06) Indoor Map/S06-01) Indoor Map Overall/WWDC19 - Introducing the Indoor Maps Program.md`

## 기술 용어 10개

| 키워드                               | 뜻                                    | 예문 (원문 그대로)                                                                                                                                      | 예문 뜻                                                                               |
| --------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| Indoor Mapping Data Format (IMDF) | 실내 지도 데이터 포맷. Apple이 정한 실내 공간 표현 규격  | "At the core of the program is the **Indoor Mapping Data Format**, or **IMDF**."                                                                 | "이 프로그램의 핵심에는 Indoor Mapping Data Format, 즉 IMDF가 있습니다."                           |
| GeoJSON                           | 지리 정보를 담는 JSON 기반 텍스트 파일 포맷          | "An IMDF is an archive made up of multiple **GeoJSON** files and the multiple files we discussed."                                               | "IMDF는 여러 개의 GeoJSON 파일과 앞서 이야기한 여러 파일로 이루어진 아카이브입니다."                             |
| indoor positioning                | 실내 측위. 건물 안에서 사용자의 위치를 알아내는 기술       | "The next step is to enable Apple **indoor positioning**."                                                                                       | "다음 단계는 Apple 실내 측위를 활성화하는 것입니다."                                                  |
| fingerprint                       | 핑거프린트. 특정 위치에서 잡히는 Wi-Fi 신호의 고유한 패턴  | "inside each box, there will be a unique texture pattern of ripples or what we call the **fingerprint**."                                        | "각 칸 안에는 물결의 고유한 질감 패턴, 즉 우리가 핑거프린트라 부르는 것이 생깁니다."                                 |
| georeferencing                    | 지오레퍼런싱. 지도를 실제 지구 좌표에 맞춰 정렬하는 것      | "**Georeferencing** of the building is the solution."                                                                                            | "건물의 지오레퍼런싱이 그 해결책입니다."                                                            |
| MapKit                            | iOS·웹에서 지도를 표시하는 Apple 프레임워크         | "**MapKit** and **MapKit** JS support decoding and rendering of GeoJSON files."                                                                  | "MapKit과 MapKit JS는 GeoJSON 파일의 디코딩과 렌더링을 지원합니다."                                  |
| access point                      | 액세스 포인트(AP). Wi-Fi 신호를 내보내는 무선 공유기   | "The ripples caused by the raindrop are much like the signal coming from an **access point**."                                                   | "빗방울이 만드는 물결은 액세스 포인트에서 나오는 신호와 매우 비슷합니다."                                         |
| IMDF Sandbox                      | 브라우저에서 IMDF를 보고 검증하고 편집하는 도구         | "The **IMDF Sandbox** is a browser-based tool for visualizing IMDF, searching the IMDF file, observing the validations and making simple edits." | "IMDF Sandbox는 IMDF를 시각화하고, IMDF 파일을 검색하고, 검증 결과를 관찰하고, 간단한 편집을 하는 브라우저 기반 도구입니다." |
| unit                              | 유닛. 실내 지도에서 방·통로·엘리베이터 등 공간을 차지하는 요소 | "The level is entirely covered by some form of what we call a **unit**, for example, a room, a walkway, an elevator or an escalator."            | "한 층은 우리가 유닛이라 부르는 어떤 형태로 완전히 덮입니다. 예를 들어 방, 통로, 엘리베이터, 에스컬레이터 같은 것입니다."           |
| UUID                              | 전 세계에서 겹치지 않는 고유 식별자                 | "there's a unique **UUID** provided to the specific feature type of level."                                                                      | "level이라는 특정 피처 타입에 고유한 UUID가 부여되어 있습니다."                                          |

## 기술 용어의 서술어

| 키워드 | 뜻 | 예문 (원문 그대로) | 예문 뜻 |
| --- | --- | --- | --- |
| represented as | ~로 표현되다 | "This is Apple specification for modeling indoor spaces and is **represented as** a set of GeoJSON files." | "이것은 실내 공간을 모델링하기 위한 Apple의 규격이며, 여러 GeoJSON 파일의 묶음으로 표현됩니다." |
| enable | 활성화하다, 가능하게 하다 | "IMDF is the basis for the map used to display in your app and website and to **enable** indoor positioning." | "IMDF는 여러분의 앱과 웹사이트에 표시할 지도의 기반이며, 실내 측위를 활성화하는 기반이기도 합니다." |
| converting | 변환하다 | "Building and property owners start by **converting** their CAD, BIM or GIS files to IMDF using industry standard tools." | "건물·부동산 소유자는 업계 표준 도구로 자신의 CAD, BIM, GIS 파일을 IMDF로 변환하는 것부터 시작합니다." |
| validated | 검증되다 | "when an IMDF is uploaded into the organization's account, it is electronically **validated** and a report is provided with a detailed analysis." | "IMDF가 조직 계정에 업로드되면, 전자적으로 검증되고 상세 분석이 담긴 리포트가 제공됩니다." |
| overlap | 겹치다 | "In IMDF, units should never **overlap**." | "IMDF에서 유닛은 절대로 서로 겹쳐서는 안 됩니다." |
| derives | 도출하다, 이끌어내다 | "the device passively looks at the fingerprint, does an on-device pattern match, **derives** the coordinates and plots the location dots." | "기기는 핑거프린트를 수동적으로 관찰하고, 온디바이스 패턴 매칭을 수행하고, 좌표를 도출한 뒤 위치 점을 찍습니다." |
| rendering | 렌더링하다, 화면에 그려내다 | "This is **rendering** the IMDF data to show you how it looks." | "이것은 IMDF 데이터를 렌더링해서 그것이 어떻게 보이는지 보여주는 것입니다." |
| covered | 덮이다 | "The level is then entirely **covered** in units, which are associated with openings, such as doorways." | "그다음 그 층은 유닛으로 완전히 덮이며, 이 유닛들은 출입구 같은 오프닝과 연결됩니다." |
| activate | 활성화하다, 작동시키다 | "Any participant in the Indoor Maps Program can **activate** indoor positioning for their building and use the IMDF maps in their apps and websites." | "Indoor Maps Program 참여자는 누구나 자신의 건물에 실내 측위를 활성화하고 앱·웹사이트에서 IMDF 지도를 사용할 수 있습니다." |
| tagged | 태그가 붙다, 정보가 표시되다 | "Using indoor maps and indoor positioning, the equipment report can be **tagged** with an accurate latitude, longitude and floor level." | "실내 지도와 실내 측위를 이용하면, 장비 리포트에 정확한 위도, 경도, 층 정보를 태그로 붙일 수 있습니다." |
| aligned | 정렬되다, 맞춰지다 | "To ensure accurate indoor positioning, the IMDF must have walkable areas for survey and be **aligned** with the Apple satellite imagery." | "정확한 실내 측위를 위해서는 IMDF에 서베이 가능한 이동 영역이 있어야 하고, Apple 위성 이미지와 정렬되어야 합니다." |
| triggered | 촉발되다, 유발되다 | "you'll also see a link to all the validation errors and warnings **triggered** by this data set." | "이 데이터셋에서 촉발된 모든 검증 에러와 경고로 이어지는 링크도 볼 수 있습니다." |
| calibrated | 보정되다, 캘리브레이션되다 | "This is how the positioning algorithm is **calibrated** to your location." | "이렇게 해서 측위 알고리즘이 여러분의 위치에 맞게 보정됩니다." |
| fingerprinted | 핑거프린팅되다, 신호 패턴으로 기록되다 | "When the floor is entirely colored in, the area is **fingerprinted** and the data is ready for upload." | "바닥이 전부 색칠되면, 그 영역은 핑거프린팅되어 데이터가 업로드할 준비가 됩니다." |
| digitized | 디지털화되다, 전자 파일로 변환되다 | "You can see the orange area outside the level looks to be some sort of drawing error that was picked up when the file was **digitized**." | "레벨 바깥의 주황색 영역은 파일이 디지털화될 때 생긴 일종의 그리기 오류로 보입니다." |
| assigned | 할당되다, 배정되다 | "Amenities and their associated data are **assigned** to the units, and finally, anchors are used for positioning references and unit addresses with additional data blocks." | "편의시설과 관련 데이터는 유닛에 할당되고, 마지막으로 앵커는 측위 기준점과 유닛 주소를 위한 추가 데이터 블록에 사용됩니다." |
