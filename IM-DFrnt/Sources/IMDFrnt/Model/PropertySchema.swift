import Foundation

enum FieldType: Hashable {
    case string
    case integer
    case boolean
    case localizedName
    // Common languages have quick fields; JSON editing retains all BCP 47 language tags.
    case stringArray
    case reference(IMDFFeatureType)
    case point
    case alwaysNull
    case json
}

struct PropertyField: Identifiable, Hashable {
    let key: String
    let type: FieldType
    var isEditable: Bool = true
    var isNonStandard: Bool = false
    // 공식 IMDF 1.0.0 스펙에 없는 프로젝트 확장 필드
    var note: String = ""

    var id: String { key }
}

enum PropertyValue: Hashable, Codable {
    case null
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case localized(en: String, ko: String)
    case stringArray([String])
    case json(ProjectJSON)

    var isNull: Bool { if case .null = self { return true }; return false }

    var displayText: String {
        switch self {
        case .null: return "null"
        case .string(let s): return s
        case .integer(let i): return String(i)
        case .boolean(let b): return b ? "true" : "false"
        case .localized(let en, let ko):
            return [en.isEmpty ? nil : "en: \(en)", ko.isEmpty ? nil : "ko: \(ko)"]
                .compactMap { $0 }.joined(separator: " / ")
        case .stringArray(let a): return a.joined(separator: ", ")
        case .json(let value): return value.text
        }
    }

    var jsonValue: Any {
        switch self {
        case .null: return NSNull()
        case .string(let s): return s
        case .integer(let i): return i
        case .boolean(let b): return b
        case .localized(let en, let ko):
            var d: [String: String] = [:]
            if !en.isEmpty { d["en"] = en }
            if !ko.isEmpty { d["ko"] = ko }
            return d.isEmpty ? NSNull() : d
        case .stringArray(let a): return a
        case .json(let value): return value.anyValue
        }
    }
}

/// `01) geojson 파일별 properties 구조.md`의 표를 그대로 옮긴 스키마.
/// 표를 고치면 이 파일도 함께 고쳐야 한다.
enum PropertySchema {

    static func fields(for type: IMDFFeatureType) -> [PropertyField] {
        var list: [PropertyField]
        switch type {
        case .address:
            list = [
                .init(key: "address", type: .string),
                .init(key: "unit", type: .string),
                .init(key: "locality", type: .string),
                .init(key: "province", type: .string),
                .init(key: "country", type: .string),
                .init(key: "postal_code", type: .string),
                .init(key: "postal_code_ext", type: .string),
                .init(key: "postal_code_vanity", type: .string),
            ]
        case .amenity:
            list = [
                .init(key: "category", type: .string),
                .init(key: "accessibility", type: .stringArray),
                .init(key: "name", type: .localizedName),
                .init(key: "alt_name", type: .localizedName),
                .init(key: "hours", type: .string),
                .init(key: "phone", type: .string),
                .init(key: "website", type: .string),
                .init(key: "unit_ids", type: .stringArray),
                .init(key: "address_id", type: .reference(.address)),
                .init(key: "correlation_id", type: .string),
                .init(key: "display_point", type: .point, isEditable: false, isNonStandard: true,
                      note: "공식 스펙에 없음 (36블록 중 9개에만 존재)"),
                .init(key: "level_id", type: .reference(.level), isNonStandard: true,
                      note: "공식 스펙에 없음 (36블록 중 9개에만 존재)"),
            ]
        case .anchor:
            list = [
                .init(key: "address_id", type: .reference(.address)),
                .init(key: "unit_id", type: .reference(.unit)),
            ]
        case .building:
            list = [
                .init(key: "name", type: .localizedName),
                .init(key: "alt_name", type: .localizedName),
                .init(key: "category", type: .string),
                .init(key: "restriction", type: .string),
                .init(key: "display_point", type: .point, isEditable: false),
                .init(key: "address_id", type: .reference(.address)),
            ]
        case .detail:
            list = [.init(key: "level_id", type: .reference(.level))]
        case .kiosk:
            list = [.init(key: "name", type: .localizedName),
                    .init(key: "alt_name", type: .localizedName),
                    .init(key: "anchor_id", type: .reference(.anchor)),
                    .init(key: "level_id", type: .reference(.level)),
                    .init(key: "display_point", type: .point, isEditable: false)]
        case .relationship:
            list = [.init(key: "category", type: .string), .init(key: "direction", type: .string),
                    .init(key: "origin", type: .json), .init(key: "destination", type: .json),
                    .init(key: "intermediary", type: .json), .init(key: "hours", type: .string)]
        case .fixture:
            list = [
                .init(key: "category", type: .string),
                .init(key: "name", type: .localizedName),
                .init(key: "alt_name", type: .localizedName),
                .init(key: "anchor_id", type: .reference(.anchor)),
                .init(key: "display_point", type: .point, isEditable: false),
                .init(key: "level_id", type: .reference(.level)),
            ]
        case .footprint:
            list = [
                .init(key: "category", type: .string),
                .init(key: "name", type: .localizedName),
                .init(key: "building_ids", type: .stringArray),
            ]
        case .level:
            list = [
                .init(key: "category", type: .string),
                .init(key: "restriction", type: .string),
                .init(key: "outdoor", type: .boolean),
                .init(key: "ordinal", type: .integer),
                .init(key: "name", type: .localizedName),
                .init(key: "short_name", type: .localizedName),
                .init(key: "display_point", type: .point, isEditable: false),
                .init(key: "address_id", type: .reference(.address)),
                .init(key: "building_ids", type: .stringArray),
            ]
        case .manifest:
            list = [
                .init(key: "version", type: .string, isEditable: false),
                .init(key: "created", type: .string, isEditable: false),
                .init(key: "generated_by", type: .string),
                .init(key: "language", type: .string),
                .init(key: "extensions", type: .stringArray),
            ]
        case .occupant:
            list = [
                .init(key: "category", type: .string),
                .init(key: "name", type: .localizedName),
                .init(key: "unit_id", type: .reference(.unit), isNonStandard: true,
                      note: "공식 스펙에 없음 — 스펙상 위치는 anchor_id로만 결정"),
                .init(key: "level_id", type: .reference(.level), isNonStandard: true,
                      note: "공식 스펙에 없음 — occupant는 위치가 없는 feature이고 층은 anchor_id로 정해진다"),
                .init(key: "correlation_id", type: .string),
                .init(key: "anchor_id", type: .reference(.anchor)),
                .init(key: "hours", type: .string),
                .init(key: "phone", type: .string),
                .init(key: "validity", type: .json),
                .init(key: "website", type: .string),
            ]
        case .opening:
            list = [
                .init(key: "category", type: .string),
                .init(key: "access_control", type: .stringArray),
                .init(key: "door", type: .json),
                .init(key: "name", type: .localizedName),
                .init(key: "alt_name", type: .localizedName),
                .init(key: "level_id", type: .reference(.level)),
                .init(key: "display_point", type: .point, isEditable: false),
                .init(key: "accessibility", type: .stringArray),
            ]
        case .unit:
            list = [
                .init(key: "category", type: .string),
                .init(key: "name", type: .localizedName),
                .init(key: "alt_name", type: .localizedName),
                .init(key: "level_id", type: .reference(.level)),
                .init(key: "restriction", type: .string),
                .init(key: "display_point", type: .point, isEditable: false),
                .init(key: "accessibility", type: .stringArray),
            ]
        case .section:
            // Apple Section Property Keys, including addressing, correlation and parent references.
            list = [
                .init(key: "category", type: .string),
                .init(key: "name", type: .localizedName),
                .init(key: "alt_name", type: .localizedName),
                .init(key: "restriction", type: .string),
                .init(key: "accessibility", type: .stringArray),
                .init(key: "level_id", type: .reference(.level)),
                .init(key: "display_point", type: .point, isEditable: false),
                .init(key: "address_id", type: .reference(.address)),
                .init(key: "correlation_id", type: .string),
                .init(key: "parents", type: .stringArray),
            ]
        case .geofence:
            // src11 3.8 — geometry POLYGONAL 필수. category가 유일한 필수 property.
            // 계층은 parent_id가 아니라 parents(GEOFENCE-ID 배열)로 표현한다.
            list = [
                .init(key: "category", type: .string),
                .init(key: "restriction", type: .string),
                .init(key: "name", type: .localizedName),
                .init(key: "alt_name", type: .localizedName),
                .init(key: "correlation_id", type: .string),
                .init(key: "display_point", type: .point, isEditable: false),
                .init(key: "building_ids", type: .stringArray),
                .init(key: "level_ids", type: .stringArray),
                .init(key: "parents", type: .stringArray,
                      note: "GEOFENCE-ID 배열 — 계층은 parent_id가 아니라 이 배열로 표현"),
            ]
        case .venue:
            list = [
                .init(key: "category", type: .string),
                .init(key: "restriction", type: .string),
                .init(key: "name", type: .localizedName),
                .init(key: "alt_name", type: .localizedName),
                .init(key: "address_id", type: .reference(.address)),
                .init(key: "hours", type: .string),
                .init(key: "phone", type: .string),
                .init(key: "website", type: .string),
                .init(key: "display_point", type: .point, isEditable: false),
                .init(key: "building_ids", type: .stringArray, isNonStandard: true,
                      note: "공식 스펙에 없음"),
            ]
        }
        // id 슬롯은 항상 맨 앞에 놓되 입력 불가(명세 7-3-2). 값은 내보내기 때 UUID v4로 발급된다.
        return [PropertyField(key: "id", type: .string, isEditable: false,
                              note: "내보내기 시 UUID v4 자동 생성")] + list
    }

    /// category 자유입력 대신 드롭다운으로 제한한다. 오타 하나로 IMDF 스펙에 없는 값이 파일에 실린다.
    ///
    /// **값은 OGC IMDF 1.0.0 Categories 페이지 원문을 그대로 옮긴 것이다**(2026-08-25 전량 대조).
    /// 근거: `01) Wiki/01-2) 소스 .../S06-01) Indoor Map Overall/
    /// src11. IMDF 공식 스펙 — Feature Type 16종·카테고리 열거형 전수 조사.md` 2절.
    /// 대조 전에는 5종(section·geofence·fixture·level·venue)에 스펙에 없는 값이 섞여 있었다.
    static func categoryOptions(for type: IMDFFeatureType) -> [String] {
        switch type {
        case .unit:
            // src11 2절 UNIT-CATEGORY 65종
        // `brick`·`concrete`·`drywall`·`glass`·`wood`는 용도가 아니라 **재질**이다.
        // 벽 같은 구조체를 Unit으로 표현할 때 쓰는 값으로 보이지만 스펙에 용법 설명이 없다(확인 필요).
            return [
                    "auditorium", "brick", "classroom", "column", "concrete", "conferenceroom", "drywall",
                    "elevator", "escalator", "fieldofplay", "firstaid", "fitnessroom", "foodservice",
                    "footbridge", "glass", "huddleroom", "kitchen", "laboratory", "library", "lobby",
                    "lounge", "mailroom", "mothersroom", "movietheater", "movingwalkway", "nonpublic",
                    "office", "opentobelow", "parking", "phoneroom", "platform", "privatelounge", "ramp",
                    "recreation", "restroom", "restroom.family", "restroom.female",
                    "restroom.female.wheelchair", "restroom.male", "restroom.male.wheelchair",
                    "restroom.transgender", "restroom.transgender.wheelchair", "restroom.unisex",
                    "restroom.unisex.wheelchair", "restroom.wheelchair", "road", "room", "serverroom",
                    "shower", "smokingarea", "stairs", "steps", "storage", "structure", "terrace", "theater",
                    "unenclosedarea", "unspecified", "vegetation", "waitingroom", "walkway",
                    "walkway.island", "wood",
            ]
        case .amenity:
            // src11 2절 AMENITY-CATEGORY 160종
            return [
                    "amphitheater", "animalreliefarea", "arrivalgate", "atm", "babychanging",
                    "baggagecarousel", "baggagecarousel.intl", "baggagecarts", "baggageclaim",
                    "baggageclaim.oversize", "baggagerecheck", "baggagestorage", "boardinggate",
                    "boardinggate.aircraft", "boardinggate.bus", "boardinggate.ferry", "boardinggate.train",
                    "bus", "bus.muni", "bus.national", "businesscenter", "cabin", "caregiver", "carrental",
                    "cashier", "changemachine", "checkin", "checkin.desk", "checkin.desk.oversizebaggage",
                    "checkin.desk.transfer", "checkin.selfservice", "childplayarea", "coinlocker",
                    "copymachine", "defibrillator", "drinkingfountain", "eatingdrinking", "elevator",
                    "emergencyshelter", "entry", "escalator", "exhibit", "faregate", "faregate.oversized",
                    "fieldofplay", "fieldofplay.americanfootball", "fieldofplay.baseball",
                    "fieldofplay.basketball", "fieldofplay.fieldhockey", "fieldofplay.icehockey",
                    "fieldofplay.rugby", "fieldofplay.soccer", "fieldofplay.softball", "fieldofplay.tennis",
                    "fieldofplay.trackfield", "fieldofplay.volleyball", "firealarmpullstation",
                    "fireextinguisher", "firstaid", "fittingroom", "foodservice", "gatearea",
                    "groundtransportation", "guestservices", "handsanitizerstation", "healthscreening",
                    "hoteling", "immigration", "information", "information.bid", "information.carrental",
                    "information.hotel", "information.mufid", "information.mufid.arrivals",
                    "information.mufid.departures", "information.transit", "landmark", "library", "limo",
                    "lostandfound", "mailbox", "meditation", "meetingpoint", "mobilityrescue", "mothersroom",
                    "movingwalkway", "paidarea", "parkandride", "parking", "parking.bicycle",
                    "parking.compact", "parking.ev", "parking.longterm", "parking.motorcycle",
                    "parking.shortterm", "parking.waitingarea", "payphone", "pedestriancrossing",
                    "peoplemover", "phone", "phone.emergency", "photobooth", "platform", "police",
                    "powerchargingstation", "prayerroom", "prayerroom.buddhism", "prayerroom.christianity",
                    "prayerroom.hinduism", "prayerroom.islam", "prayerroom.islam.female",
                    "prayerroom.islam.male", "prayerroom.judaism", "prayerroom.shintoism", "prayerroom.sikh",
                    "prayerroom.taoic", "privatelounge", "productreturn", "rail.muni", "rail.national",
                    "ramp", "reception.desk", "recreation", "restroom", "restroom.family", "restroom.female",
                    "restroom.female.wheelchair", "restroom.male", "restroom.male.wheelchair",
                    "restroom.transgender", "restroom.transgender.wheelchair", "restroom.unisex",
                    "restroom.unisex.wheelchair", "restroom.wheelchair", "rideshare", "seat", "seating",
                    "security", "security.checkpoint", "security.inspection", "service", "shower", "shuttle",
                    "sleepbox", "smokingarea", "stairs", "storage", "strollerrental", "studentadmissions",
                    "studentservices", "swimmingpool", "swimmingpool.children", "swimmingpool.family",
                    "taxi", "ticketing", "ticketing.airline", "ticketing.bus", "ticketing.bus.muni",
                    "ticketing.bus.national", "ticketing.rail", "ticketing.rail.muni",
                    "ticketing.rail.national", "ticketing.shuttle", "traintrack", "transit", "unspecified",
                    "valet", "vendingmachine", "vendingmachine.trainticket", "wheelchairassist", "wifi",
                    "yoga",
            ]
        case .opening:
            // src11 2절 OPENING-CATEGORY 7종
            return [
                    "automobile", "bicycle", "emergencyexit", "pedestrian", "pedestrian.principal",
                    "pedestrian.transit", "service",
            ]
        case .section:
            // src11 2절 SECTION-CATEGORY 70종
        // `unspecified`가 **없다.** 이전 코드가 넣어 뒀던 것은 스펙에 없는 값이었다.
            return [
                    "arcade", "baggageclaim", "baggageclaim.intl", "carrental", "carrental.dropoff",
                    "checkin", "concessions", "cubicle", "dutyfree", "eatingdrinking", "entertainmentarea",
                    "entertainmentarea.game", "entertainmentarea.music", "entertainmentarea.performance",
                    "entertainmentarea.sport", "exhibit", "exhibition", "gambling", "gambling.baccarat",
                    "gambling.bingo", "gambling.blackjack", "gambling.craps", "gambling.keno",
                    "gambling.mahjong", "gambling.medalgame", "gambling.minibaccarat",
                    "gambling.offtrackbetting", "gambling.pachinko", "gambling.paigow", "gambling.poker",
                    "gambling.poker.letitride", "gambling.poker.paigow", "gambling.poker.threecard",
                    "gambling.poker.video", "gambling.roulette", "gambling.rummy", "gambling.sicbo",
                    "gambling.slotmachine", "gambling.slotmachine.highlimit", "gatearea", "gatearea.holding",
                    "immigration", "immigration.schengen", "information", "paidarea", "parkandride",
                    "parking", "parking.bicycle", "parking.compact", "parking.ev", "parking.longterm",
                    "parking.motorcycle", "parking.shortterm", "parking.waitingarea", "platform",
                    "postsecurity", "presecurity", "private", "recomposearea", "recreation", "rental",
                    "retail", "retaildepartment", "road", "seating", "seatingrow", "security", "servicearea",
                    "ticketing", "vegetation", "walkway",
            ]
        case .geofence:
            // src11 2절 GEOFENCE-CATEGORY 8종
        // 여기에도 `unspecified`가 없다. 이전 코드의 ["unspecified"]는 스펙에 없는 값이었다.
            return [
                    "concourse", "geofence", "paidarea", "platform", "postsecurity", "presecurity",
                    "terminal", "underconstruction",
            ]
        case .fixture:
            // src11 2절 FIXTURE-CATEGORY 15종
        // 이전 코드의 `shelving`·`planter`는 스펙에 없고, `column`은 UNIT-CATEGORY 값이다.
        // `wall`이 여기 있다 — Wall이라는 독립 Feature Type은 없지만 Fixture category로는 표현된다.
            return [
                    "baggagecarousel", "boardinggate.desk", "checkin.desk", "checkin.kiosk", "desk",
                    "equipment", "furniture", "immigration.desk", "inspection.desk", "obstruction",
                    "securityequipment", "stage", "vegetation", "wall", "water",
            ]
        case .footprint:
            // src11 2절 FOOTPRINT-CATEGORY 3종
            return [
                    "aerial", "ground", "subterranean",
            ]
        case .level:
            // src11 2절 LEVEL-CATEGORY 9종
        // 이전 코드의 `arrival`·`departure`는 단수형이라 스펙에 없는 값이었다(스펙은 복수형).
            return [
                    "arrivals", "arrivals.domestic", "arrivals.intl", "departures", "departures.domestic",
                    "departures.intl", "parking", "transit", "unspecified",
            ]
        case .building:
            // src11 2절 BUILDING-CATEGORY 5종
            return [
                    "parking", "transit", "transit.bus", "transit.train", "unspecified",
            ]
        case .venue:
            // src11 2절 VENUE-CATEGORY 22종
        // 이전 코드의 `hospital`은 스펙에 없다. 의료시설은 `healthcarefacility`다.
            return [
                    "airport", "airport.intl", "aquarium", "businesscampus", "casino", "communitycenter",
                    "conventioncenter", "governmentfacility", "healthcarefacility", "hotel", "museum",
                    "parkingfacility", "resort", "retailstore", "shoppingcenter", "stadium", "stripmall",
                    "theater", "themepark", "trainstation", "transitstation", "university",
            ]
        case .occupant:
            return OccupantCategories.all
        case .relationship:
            return ["elevator", "escalator", "movingwalkway", "ramp", "stairs", "traversal", "traversal.path"]
            // 스펙 페이지로는 전량을 얻지 못해 자유 입력이었다. Apple 배포 범주 파일로 채웠다(2026-10-20).
        default:
            return []
        }
    }
}
