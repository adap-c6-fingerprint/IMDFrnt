import Foundation

/// category 값의 한국어 표기. 화면에는 `한국어(영어)`로 보이고, 저장·내보내기 값은 영어 원문 그대로다(#52).
///
/// 대상은 `PropertySchema.categoryOptions(for:)`의 모든 값이다. 같은 영어 값이 type마다 뜻이 다르면
/// `overrides`에 type별로 따로 둔다 — opening의 `service`는 "서비스 출입구", amenity의 `service`는 "서비스"다.
/// 번역은 IMDF 원문 정의를 옮긴 것이 아니라 화면에서 알아보기 위한 이름이다.
enum CategoryLabel {
    /// 한국어 이름. 모르는 값(occupant 자유 입력 등)이면 nil이다.
    static func korean(_ value: String, type: IMDFFeatureType) -> String? {
        overrides[type]?[value] ?? names[value]
    }

    /// `한국어(영어)`. 한국어가 없으면 영어 원문만 돌려준다.
    static func display(_ value: String, type: IMDFFeatureType) -> String {
        guard let ko = korean(value, type: type) else { return value }
        return "\(ko)(\(value))"
    }

    private static let overrides: [IMDFFeatureType: [String: String]] = [
        .unit: ["storage": "창고", "firstaid": "응급처치실", "parking": "주차 공간"],
        .amenity: ["storage": "보관함"],
        .opening: ["service": "서비스 출입구"],
        .level: ["parking": "주차층", "transit": "대중교통층"],
        .building: ["parking": "주차 건물", "transit": "대중교통 건물"],
    ]

    private static let names: [String: String] = [
        "traversal": "통행 관계", "traversal.path": "통행 경로",
        // unit
        "auditorium": "강당", "brick": "벽돌", "classroom": "강의실", "column": "기둥",
        "concrete": "콘크리트", "conferenceroom": "회의실", "drywall": "석고보드", "elevator": "엘리베이터",
        "escalator": "에스컬레이터", "fieldofplay": "경기 구역", "firstaid": "응급처치",
        "fitnessroom": "체력단련실", "foodservice": "식음 서비스", "footbridge": "보행 육교", "glass": "유리",
        "huddleroom": "소회의실", "kitchen": "주방", "laboratory": "실험실", "library": "도서관",
        "lobby": "로비", "lounge": "라운지", "mailroom": "우편실", "mothersroom": "수유실",
        "movietheater": "영화관", "movingwalkway": "무빙워크", "nonpublic": "비공개 구역",
        "office": "사무실", "opentobelow": "아래층 트임", "parking": "주차장", "phoneroom": "통화실",
        "platform": "승강장", "privatelounge": "전용 라운지", "ramp": "경사로", "recreation": "레크리에이션",
        "restroom": "화장실", "restroom.family": "가족 화장실", "restroom.female": "여자 화장실",
        "restroom.female.wheelchair": "여자 장애인 화장실", "restroom.male": "남자 화장실",
        "restroom.male.wheelchair": "남자 장애인 화장실", "restroom.transgender": "트랜스젠더 화장실",
        "restroom.transgender.wheelchair": "트랜스젠더 장애인 화장실", "restroom.unisex": "남녀공용 화장실",
        "restroom.unisex.wheelchair": "남녀공용 장애인 화장실", "restroom.wheelchair": "장애인 화장실",
        "road": "도로", "room": "방", "serverroom": "서버실", "shower": "샤워실", "smokingarea": "흡연 구역",
        "stairs": "계단", "steps": "단차 계단", "storage": "창고·보관", "structure": "구조체",
        "terrace": "테라스", "theater": "극장", "unenclosedarea": "개방 구역", "unspecified": "미분류",
        "vegetation": "식재", "waitingroom": "대기실", "walkway": "통로", "walkway.island": "통로 섬",
        "wood": "목재",

        // amenity
        "amphitheater": "원형 극장", "animalreliefarea": "반려동물 배변 구역", "arrivalgate": "도착 게이트",
        "atm": "현금인출기", "babychanging": "기저귀 교환대", "baggagecarousel": "수하물 컨베이어",
        "baggagecarousel.intl": "국제선 수하물 컨베이어", "baggagecarts": "수하물 카트",
        "baggageclaim": "수하물 찾는 곳", "baggageclaim.oversize": "대형 수하물 찾는 곳",
        "baggagerecheck": "수하물 재위탁", "baggagestorage": "수하물 보관소", "boardinggate": "탑승 게이트",
        "boardinggate.aircraft": "항공기 탑승 게이트", "boardinggate.bus": "버스 탑승 게이트",
        "boardinggate.ferry": "페리 탑승 게이트", "boardinggate.train": "열차 탑승 게이트", "bus": "버스",
        "bus.muni": "시내버스", "bus.national": "시외버스", "businesscenter": "비즈니스 센터", "cabin": "객실",
        "caregiver": "보호자 지원", "carrental": "렌터카", "cashier": "계산대", "changemachine": "동전 교환기",
        "checkin": "체크인", "checkin.desk": "체크인 카운터",
        "checkin.desk.oversizebaggage": "대형 수하물 체크인 카운터", "checkin.desk.transfer": "환승 체크인 카운터",
        "checkin.selfservice": "셀프 체크인", "childplayarea": "어린이 놀이 공간", "coinlocker": "코인 로커",
        "copymachine": "복사기", "defibrillator": "자동심장충격기", "drinkingfountain": "음수대",
        "eatingdrinking": "식음 공간", "emergencyshelter": "비상 대피소", "entry": "입구", "exhibit": "전시물",
        "faregate": "개찰구", "faregate.oversized": "대형 개찰구",
        "fieldofplay.americanfootball": "미식축구장", "fieldofplay.baseball": "야구장",
        "fieldofplay.basketball": "농구장", "fieldofplay.fieldhockey": "필드하키장",
        "fieldofplay.icehockey": "아이스하키장", "fieldofplay.rugby": "럭비장", "fieldofplay.soccer": "축구장",
        "fieldofplay.softball": "소프트볼장", "fieldofplay.tennis": "테니스장",
        "fieldofplay.trackfield": "육상 트랙", "fieldofplay.volleyball": "배구장",
        "firealarmpullstation": "화재 경보 발신기", "fireextinguisher": "소화기", "fittingroom": "탈의실",
        "gatearea": "게이트 구역", "groundtransportation": "지상 교통", "guestservices": "고객 서비스",
        "handsanitizerstation": "손 소독제", "healthscreening": "건강 검사", "hoteling": "공유 좌석",
        "immigration": "출입국 심사", "information": "안내", "information.bid": "상권 안내",
        "information.carrental": "렌터카 안내", "information.hotel": "호텔 안내",
        "information.mufid": "운항 정보 안내판", "information.mufid.arrivals": "도착 운항 정보 안내판",
        "information.mufid.departures": "출발 운항 정보 안내판", "information.transit": "대중교통 안내",
        "landmark": "랜드마크", "limo": "리무진", "lostandfound": "분실물 센터", "mailbox": "우체통",
        "meditation": "명상 공간", "meetingpoint": "만남의 장소", "mobilityrescue": "이동 보조 구조",
        "paidarea": "유료 구역", "parkandride": "환승 주차장", "parking.bicycle": "자전거 주차",
        "parking.compact": "경차 주차", "parking.ev": "전기차 주차", "parking.longterm": "장기 주차",
        "parking.motorcycle": "오토바이 주차", "parking.shortterm": "단기 주차",
        "parking.waitingarea": "주차 대기 구역", "payphone": "공중전화", "pedestriancrossing": "횡단보도",
        "peoplemover": "피플무버", "phone": "전화", "phone.emergency": "비상 전화", "photobooth": "즉석 사진 부스",
        "police": "경찰", "powerchargingstation": "충전소", "prayerroom": "기도실",
        "prayerroom.buddhism": "불교 기도실", "prayerroom.christianity": "기독교 기도실",
        "prayerroom.hinduism": "힌두교 기도실", "prayerroom.islam": "이슬람교 기도실",
        "prayerroom.islam.female": "이슬람교 여성 기도실", "prayerroom.islam.male": "이슬람교 남성 기도실",
        "prayerroom.judaism": "유대교 기도실", "prayerroom.shintoism": "신도 기도실",
        "prayerroom.sikh": "시크교 기도실", "prayerroom.taoic": "도교 기도실", "productreturn": "반품 접수",
        "rail.muni": "도시철도", "rail.national": "간선철도", "reception.desk": "안내 데스크",
        "rideshare": "승차 공유", "seat": "좌석", "seating": "좌석 구역", "security": "보안",
        "security.checkpoint": "보안 검색대", "security.inspection": "보안 검사", "service": "서비스",
        "shuttle": "셔틀", "sleepbox": "수면 캡슐", "strollerrental": "유모차 대여",
        "studentadmissions": "입학 안내", "studentservices": "학생 지원", "swimmingpool": "수영장",
        "swimmingpool.children": "어린이 수영장", "swimmingpool.family": "가족 수영장", "taxi": "택시",
        "ticketing": "매표소", "ticketing.airline": "항공권 발권", "ticketing.bus": "버스 매표소",
        "ticketing.bus.muni": "시내버스 매표소", "ticketing.bus.national": "시외버스 매표소",
        "ticketing.rail": "철도 매표소", "ticketing.rail.muni": "도시철도 매표소",
        "ticketing.rail.national": "간선철도 매표소", "ticketing.shuttle": "셔틀 매표소", "traintrack": "선로",
        "transit": "대중교통", "valet": "발레파킹", "vendingmachine": "자판기",
        "vendingmachine.trainticket": "승차권 자판기", "wheelchairassist": "휠체어 지원", "wifi": "와이파이",
        "yoga": "요가",

        // opening
        "automobile": "차량 출입구", "bicycle": "자전거 출입구", "emergencyexit": "비상구",
        "pedestrian": "보행자 출입구", "pedestrian.principal": "주 출입구", "pedestrian.transit": "대중교통 연결 출입구",

        // section
        "arcade": "아케이드", "baggageclaim.intl": "국제선 수하물 찾는 곳", "carrental.dropoff": "렌터카 반납",
        "concessions": "매점", "cubicle": "칸막이 업무 공간", "dutyfree": "면세점",
        "entertainmentarea": "오락 구역", "entertainmentarea.game": "게임 구역",
        "entertainmentarea.music": "음악 구역", "entertainmentarea.performance": "공연 구역",
        "entertainmentarea.sport": "스포츠 구역", "exhibition": "전시장", "gambling": "도박 구역",
        "gambling.baccarat": "바카라", "gambling.bingo": "빙고", "gambling.blackjack": "블랙잭",
        "gambling.craps": "크랩스", "gambling.keno": "키노", "gambling.mahjong": "마작",
        "gambling.medalgame": "메달 게임", "gambling.minibaccarat": "미니 바카라",
        "gambling.offtrackbetting": "장외 발매소", "gambling.pachinko": "파친코", "gambling.paigow": "파이가우",
        "gambling.poker": "포커", "gambling.poker.letitride": "렛잇라이드 포커",
        "gambling.poker.paigow": "파이가우 포커", "gambling.poker.threecard": "스리카드 포커",
        "gambling.poker.video": "비디오 포커", "gambling.roulette": "룰렛", "gambling.rummy": "러미",
        "gambling.sicbo": "식보", "gambling.slotmachine": "슬롯머신",
        "gambling.slotmachine.highlimit": "고액 슬롯머신", "gatearea.holding": "탑승 대기 구역",
        "immigration.schengen": "솅겐 출입국 심사", "postsecurity": "보안 검색 후 구역",
        "presecurity": "보안 검색 전 구역", "private": "사적 구역", "recomposearea": "검색 후 정리 구역",
        "rental": "대여", "retail": "매장", "retaildepartment": "매장 코너", "seatingrow": "좌석 열",
        "servicearea": "서비스 구역",

        // geofence
        "concourse": "중앙 홀", "geofence": "지오펜스", "terminal": "터미널", "underconstruction": "공사 중",

        // fixture
        "boardinggate.desk": "탑승 게이트 데스크", "checkin.kiosk": "체크인 키오스크", "desk": "책상",
        "equipment": "장비", "furniture": "가구", "immigration.desk": "출입국 심사 데스크",
        "inspection.desk": "검사 데스크", "obstruction": "장애물", "securityequipment": "보안 장비",
        "stage": "무대", "wall": "벽", "water": "수경 시설",

        // footprint
        "aerial": "상공 투영", "ground": "지면", "subterranean": "지하",

        // level
        "arrivals": "도착층", "arrivals.domestic": "국내선 도착층", "arrivals.intl": "국제선 도착층",
        "departures": "출발층", "departures.domestic": "국내선 출발층", "departures.intl": "국제선 출발층",

        // building
        "transit.bus": "버스 터미널", "transit.train": "기차역",

        // venue
        "airport": "공항", "airport.intl": "국제공항", "aquarium": "수족관", "businesscampus": "업무 단지",
        "casino": "카지노", "communitycenter": "주민 센터", "conventioncenter": "컨벤션 센터",
        "governmentfacility": "공공기관", "healthcarefacility": "의료 시설", "hotel": "호텔",
        "museum": "박물관", "parkingfacility": "주차 시설", "resort": "리조트", "retailstore": "소매점",
        "shoppingcenter": "쇼핑센터", "stadium": "스타디움", "stripmall": "상가 단지",
        "themepark": "테마파크", "trainstation": "기차역", "transitstation": "환승역", "university": "대학교",
    ]
}
