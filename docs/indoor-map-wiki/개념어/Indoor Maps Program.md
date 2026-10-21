---
summary: 대형 공공·사설 공간 소유 조직이 실내 지도 제작·실내 측위 활성화·앱 표시를 할 수 있게 하는 Apple 프로그램
source: "[[Apple Indoor Maps Program과 IMDF 개요]], WWDC19 Session 245, register.apple.com/indoor"
related:
  - "[[IMDF]]"
  - "[[Apple 실내 측위]]"
  - "[[IMDF Sandbox]]"
created: 2026-08-05 16:40
updated: 2026-08-05 16:40
core_keywords:
  - Indoor Maps Program
---
# Indoor Maps Program

## 요약

Indoor Maps Program은 공항·쇼핑몰·병원·대학·대형 오피스처럼 넓은 공공·사설 공간을 가진 조직이 표준 실내 지도(IMDF)를 만들고, 실내 측위를 활성화하며, 자체 앱·웹사이트에 실내 지도를 표시할 수 있게 하는 Apple 프로그램이다. 트래픽이 많은 공항·쇼핑몰은 공개 실내 지도를 Apple Maps에 포함시킬 수도 있다.

## 핵심 내용

- **등록:** `register.apple.com/indoor` → Get Started. Apple Business Register가 사업자 정보를 심층 검증한다. 가입자 이메일은 조직 도메인과 연결, 담당자는 직원 또는 등록 대리인이어야 한다.
- **팀 관리:** 관리자가 멤버를 초대하고 **5가지 역할**과 venue별/조직 전체 접근 권한을 부여한다. IMDF 제작·서베이를 venue 단위로 외주할 수 있다.
- **SI 주의:** 시스템 통합업체는 고객 건물을 대신 claim하지 말고 고객 조직에 **초대받아** 참여한다.
- **장소 claim:** 자기 소유 부동산만 claim 가능. 사설 장소는 Apple Maps 노출 불가, 공항 등은 노출 허가 요청을 받는다.
- **자격(large 기준):** 프로그램 참여와 실내 측위 활성화는 대형 부동산 소유자용. 예시 기준은 50㎡ 이상(확인 필요, 오기 가능), 연 500만 명 방문, 또는 오피스 건물 전체.
- 단순 IMDF 표시는 누구나 MapKit/MapKit JS로 가능하지만, 실내 측위 활성화는 이 프로그램 참여가 필요하다.

## 관련 링크

- [[IMDF]] — 프로그램의 핵심 데이터 포맷
- [[Apple 실내 측위]] — 프로그램으로 활성화하는 측위 기능
- [[IMDF Sandbox]] — 업로드 전 IMDF 검증 도구

## 미해결 질문

- 5가지 역할의 구체적 권한 범위는 무엇인가.
- 프로그램 자격 기준 수치(면적·방문자 수)의 현재 정확한 값은 무엇인가.
