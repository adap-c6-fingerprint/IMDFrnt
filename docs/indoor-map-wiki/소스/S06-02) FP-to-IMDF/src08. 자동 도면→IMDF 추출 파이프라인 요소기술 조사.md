---
summary: "도면(CAD/래스터)에서 좌표 추출·지오레퍼런싱·유닛 타입 자동 인식을 자동화하는 프로그램을 설계하기 위해, DWG→DXF 변환, DXF 파싱, 래스터 평면도 인식 연구, 자동 지오레퍼런싱 기법을 조사"
source: "ezdxf.mozman.at, opendesign.com, arxiv.org(CubiCasa5K/Raster-to-Vector 논문), researchgate.net, mdpi.com"
created: "2026-08-13 01:00"
updated: "2026-08-13 01:00"
---
# 자동 도면→IMDF 추출 파이프라인 요소기술 조사

## 수집 기준

- 수집일: 2026-08-13
- 목적: 사용자가 "도면에서 자동으로 좌표를 찍고 → 지오레퍼런싱하고 → 유닛/섹션 type property를 자동 인식·카테고라이징하는" 프로그램을 직접 만들려 함. 기존 소스(src06, src07)는 FME·ArcGIS Indoors 같은 **기성 상용 도구**의 사용법을 다뤘을 뿐, "그 도구 없이 직접 자동화 프로그램을 짤 때 쓸 수 있는 요소 기술"은 다루지 않아 별도 조사.
- 범위: CAD(DWG/DXF) 파싱 도구, 래스터(스캔·PDF) 평면도 인식 연구, 자동 지오레퍼런싱(건물 풋프린트 정합) 기법. 특정 제품 사용법이 아니라 **일반 기술 요소**를 조사 대상으로 한다.

## 1. CAD 경로 — DWG/DXF 파싱

### 1.1 DWG → DXF 변환 (ODA File Converter)

- Open Design Alliance(ODA)가 무료로 배포하는 도구. Windows/Linux/macOS 지원, GUI와 CLI(명령행) 모두 제공.
- CLI는 원본 폴더, 대상 폴더, 입력 필터, 출력 버전/타입, 재귀 처리 여부, audit(감사/복구) 여부를 인자로 받는다.
- 출처: https://www.opendesign.com/guestfiles/oda_file_converter , https://en.wikipedia.org/wiki/Open_Design_Alliance

### 1.2 DXF 파싱 (ezdxf, Python)

- ezdxf는 DXF 문서를 만들고 읽고 수정하고 쓰는 순수 Python 라이브러리로, DXF R12~R2018까지 버전 호환. 오픈소스 커뮤니티가 유지관리하며 DXF 처리의 사실상 표준 도구로 서술된다.
- ASCII/Binary DXF 모두 읽기·쓰기 지원. 레이어(layer) 테이블 접근·생성을 지원해, "레이어별로 엔티티를 골라내는" 방식(FME 튜토리얼이 쓰는 방식과 동일한 개념)을 코드로 직접 구현할 수 있다.
- ezdxf 자체에 **ODA File Converter를 자동으로 호출해 DWG를 DXF로 바꿔주는 애드온**(`odafc`)이 있다 — 즉 "DWG 입력 → ezdxf가 내부적으로 ODA 변환기 실행 → DXF로 읽기"를 한 파이프라인 안에서 연결할 수 있다.
- 요구사항: Python 3.10+, 의존 라이브러리로 pyparsing/numpy/fontTools 등.
- 출처: https://ezdxf.mozman.at/ , https://ezdxf.readthedocs.io/en/stable/introduction.html , https://ezdxf.readthedocs.io/en/stable/addons/odafc.html

## 2. 래스터 경로 — 평면도 이미지에서 벡터·의미 정보 추출 (학술 연구)

이 영역은 상용 제품이 아니라 컴퓨터 비전/딥러닝 연구 분야("floor plan recognition/parsing")로 존재한다. 대표적으로 확인된 것은 다음 두 가지다.

### 2.1 CubiCasa5K (데이터셋 + 멀티태스크 모델)

- 논문: "CubiCasa5K: A Dataset and an Improved Multi-Task Model for Floorplan Image Analysis" (Kalervo, Ylioinas 외, 2019, arXiv:1904.01920, Springer 게재).
- 데이터셋 구성: 원래 CAD로 제작된 뒤 래스터화된 핀란드 부동산 매물 평면도 이미지 약 15,000장 중, 선명도·완전성(단층 전체 레이아웃)·주요 요소(벽·방·문·창) 가시성 기준으로 5,000장을 선별.
- 주석(annotation) 범위: **80개 이상의 평면도 객체 카테고리** — 방(주방·침실·욕실·거실·복도 등), 아이콘(창문·문·싱크대·가전·변기·벽난로 등), 구조 요소(벽·난간·수납·굴뚝·계단 등).
- 주석 절차: 벽 폴리곤을 먼저 그리고, 그 벽 경계를 이용해 방을 분할하고, 마지막으로 아이콘/개구부를 배치하는 순서로 진행됨.
- 통계: 평면도당 방 8~12개, 벽 세그먼트 20~30개, 아이콘 15~30개가 피크 구간. 침실이 전체 방 폴리곤의 약 16%로 가장 흔한 방 타입.
- **주의(확인 필요로 명시):** 이 데이터셋의 방 타입 태그 체계는 **주거용**(침실·욕실·주방 등)이며, IMDF의 `UNIT-CATEGORY`(room, auditorium, classroom, office, storage 등 상업·공공시설 위주 어휘)와 직접 대응하지 않는다. 그대로 쓰려면 별도의 매핑 테이블 또는 상업시설 데이터로의 재학습(fine-tuning)이 필요하다.
- 출처: https://ar5iv.labs.arxiv.org/html/1904.01920 , https://www.emergentmind.com/topics/cubicasa5k-dataset

### 2.2 Raster-to-Vector: Revisiting Floorplan Transformation (ICCV 2017)

- 저자: Chen Liu, Jiajun Wu, Pushmeet Kohli, Yasutaka Furukawa. ICCV 2017 발표.
- 접근법: 신경망이 먼저 래스터 이미지를 "접합점(junction)" — 벽 모서리, 문 끝점 같은 저수준 기하·의미 정보 — 집합으로 변환하고, 그 다음 정수계획법(integer programming)으로 이 접합점들을 벽선·문선·아이콘 박스 같은 단순 도형으로 묶어 위상·기하 일관성을 보장하는 벡터 평면도를 만든다.
- 이후 연구(예: Deep Floor Plan Recognition, MuraNet 등)들이 이 방식을 계승·개선한 것으로 검색 결과에 함께 나타난다(개별 대조는 이번 조사에서 하지 않음, 확인 필요).
- 출처: https://openaccess.thecvf.com/content_ICCV_2017/papers/Liu_Raster-To-Vector_Revisiting_Floorplan_ICCV_2017_paper.pdf , https://art-programmer.github.io/floorplan-transformation.html

## 3. 자동 지오레퍼런싱 — 건물 풋프린트 형태 정합

- Iterative Closest Point(ICP) 알고리즘은 두 점군(point set) 사이의 대응점을 반복적으로 찾아 정합하는 고전적 기법이다. 다만 학술 자료는 **"건물 풋프린트처럼 인접 폴리곤이 조밀하고 서로 모양·크기가 비슷한 도심 밀집 지역에서는 ICP가 잘못된 대응(오매칭)을 만들 수 있다"**고 명시적으로 경고한다.
- 대안으로 제시되는 것은, 두 폴리곤을 이동·회전 보정한 뒤 경계 사이 평균 거리로 유사도를 재는 "형태 유사도(shape similarity)" 측정 방식이다.
- Affine(어파인) 변환은 지도 접합(map conflation)에 널리 쓰이며, 국소적 왜곡까지 없애지는 못해도 좌표계 변환에서 생기는 전반적 정렬 오차를 1차로 줄이는 데 우선 적용되는 것으로 서술된다.
- → 즉 "CAD 외곽선을 OSM 건물 풋프린트와 자동으로 형태 정합시켜 지오레퍼런싱한다"는 아이디어 자체는 지도 정합(map conflation) 분야에 관련 기법(ICP, 형태 유사도, affine 정합)이 존재하지만, **이 특정 조합(CAD 도면 ↔ OSM 건물 풋프린트, IMDF 목적)을 그대로 서술한 논문이나 사례는 이번 조사에서 발견하지 못했다.** 이는 기존 지도-정합 기법을 이 문제에 응용해볼 수 있다는 설계 아이디어이지, 검증된 기존 방법론이 아니다.
- 출처: 지도/OSM 풋프린트 정합 관련 검색 결과 종합(researchgate.net, mdpi.com 등 복수 논문의 검색 스니펫 기반 — 개별 원문 전체는 대조하지 않음).

## 미해결 질문

- CubiCasa5K 학습된 모델의 실제 공개 여부·라이선스(연구용/상업용 재사용 가능 범위) — 이번 조사에서 확인하지 못함.
- Raster-to-Vector 이후 계승 연구(Deep Floor Plan Recognition, MuraNet 등)의 코드/모델 공개 여부.
- ICP/형태 유사도 정합을 "CAD 도면 ↔ OSM 풋프린트, 자동 지오레퍼런싱" 목적에 실제로 적용한 선행 사례 유무 — 발견하지 못함, 이 문서의 3절 제안은 검증되지 않은 설계 아이디어임을 명시.
- ezdxf의 `odafc` 애드온이 실제로 요구하는 ODA File Converter 라이선스 조건(상업적 재배포 시 제약 여부).
