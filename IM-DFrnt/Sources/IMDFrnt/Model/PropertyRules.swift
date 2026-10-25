import Foundation

/// 정보 type(address·building·occupant·manifest) 칸별 입력 가이드와 점검(2026-10-20, #31).
///
/// 근거: OGC IMDF 1.0(docs.ogc.org/cs/20-094, Apple 제출 원문)의 각 Feature·Reference 페이지와
/// Apple `IMDF.zip`의 `imdf-validations-1.0.3.csv`. Apple 검증에서 **Violation**이면 `.violation`,
/// **Warning**이면 `.warning`으로 둔다. 내보내기는 violation이 있으면 막고 warning은 알리기만 한다.
struct FieldProblem: Equatable {
    enum Severity { case violation, warning }
    let severity: Severity
    /// 어떻게 고치면 되는지까지 쓴다. 칸 아래 빨간(주황) 글씨로 그대로 보인다.
    let message: String
}

enum PropertyRules {

    /// 칸 아래에 늘 보이는 입력 가이드. 없으면 nil.
    static func guide(_ type: IMDFFeatureType, _ key: String) -> String? {
        switch (type, key) {
        case (.address, "address"): "필수. 호수를 뺀 도로명 주소. 예: 경북 포항시 남구 청암로 77. 도로명 주소가 없으면 건물·venue 이름"
        case (.address, "unit"): "선택. 호수 하나만. 예: 101호. 건물 주소에는 비워 둡니다(매장 등 호수 붙은 주소에만)"
        case (.address, "locality"): "필수. 시·군·구. 예: 포항시"
        case (.address, "province"): "ISO 3166-2 코드. 한국은 시·도를 목록에서 고릅니다. 예: KR-47(경상북도)"
        case (.address, "country"): "필수. ISO 3166 두 글자 국가 코드. 예: KR"
        case (.address, "postal_code"): "권장. 우편번호. 예: 37673"
        case (.address, "postal_code_ext"), (.address, "postal_code_vanity"): "한국 주소에는 쓰지 않습니다"
        case (_, "name") where [.building, .occupant].contains(type):
            type == .occupant ? "필수. 상호(브랜드명). Manifest 기본 언어의 이름을 포함하세요" : "선택. 공식 건물 이름. 입력하면 Manifest 기본 언어를 포함하세요"
        case (.building, "alt_name"): "선택. 흔히 부르는 다른 이름. 쓰려면 name도 있어야 합니다"
        case (.building, "category"): "필수. 주차 건물은 parking, 그 밖은 대개 unspecified"
        case (.building, "restriction"): "선택. 일반인 출입이 안 되는 건물이면 employeesonly 또는 restricted"
        case (.building, "display_point"): "건물 이름을 찍을 자리. 이 건물의 footprint 안이어야 합니다"
        case (.building, "address_id"): "권장. 비우면 venue 주소를 따릅니다. 호수 붙은 주소는 고르지 않습니다"
        case (.occupant, "category"): "필수. 업종을 목록에서 고릅니다. 예: cafe, restaurant"
        case (.occupant, "anchor_id"): "필수. 이 매장이 놓일 anchor. anchor가 unit·층·주소를 정합니다"
        case (.occupant, "hours"): "권장. OSM opening_hours 형식. 예: Mo-Fr 09:00-18:00; Sa 10:00-14:00"
        case (.occupant, "phone"): "권장. +국가번호로 시작, 공백·하이픈 없이. 예: +82542792114 (팩스 번호 금지)"
        case (.occupant, "website"): "권장. http:// 또는 https://로 시작하는 주소"
        case (.occupant, "unit_id"), (.occupant, "level_id"): "공식 스펙에 없는 칸입니다. 위치는 anchor_id로 정합니다"
        case (.manifest, "version"): "1.0.0으로 고정됩니다(지원되는 유일한 버전)"
        case (.manifest, "created"): "내보낼 때 그 시각으로 자동 기록됩니다"
        case (.manifest, "generated_by"): "선택. 만든 프로그램. 비우면 IM-DFrnt"
        case (.manifest, "language"): "필수. LABELS와 같은 기본 언어 태그. 새 프로젝트 기본값 ko. 예: ko, en-US"
        case (.manifest, "extensions"): "IMDF 확장을 쓰지 않으면 null입니다"
        default: nil
        }
    }

    /// 이 칸이 조건을 만족하지 않으면 무엇이 틀렸고 어떻게 고치는지 돌려준다.
    static func problem(_ type: IMDFFeatureType, _ key: String, in f: FeatureGroup) -> FieldProblem? {
        let value = f.value(key)
        let text: String? = { if case .string(let s) = value { return s }; return nil }()
        func violation(_ m: String) -> FieldProblem { FieldProblem(severity: .violation, message: m) }
        func warning(_ m: String) -> FieldProblem { FieldProblem(severity: .warning, message: m) }
        if let text, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return violation("공백만 있습니다. 값을 넣거나 칸을 완전히 비우세요.")
        }
        switch (type, key) {
        case (.address, "address"):
            return text == nil ? violation("비어 있습니다. 도로명 주소를 넣으세요.") : nil
        case (.address, "locality"):
            return text == nil ? violation("비어 있습니다. 시·군·구를 넣으세요. 예: 포항시") : nil
        case (.address, "country"):
            guard let text else { return violation("비어 있습니다. 국가 코드를 고르세요. 예: KR") }
            return isoCountries.contains(text) ? nil : violation("‘\(text)’는 ISO 3166 국가 코드가 아닙니다. 목록에서 고르세요(대한민국은 KR).")
        case (.address, "province"):
            let country: String? = { if case .string(let s) = f.value("country") { return s }; return nil }()
            guard let text else {
                return country.map { subdivisions[$0] != nil } == true
                    ? violation("이 나라는 ISO가 시·도 코드를 정해 두어 반드시 넣어야 합니다. 목록에서 고르세요.") : nil
            }
            if let country, let list = subdivisions[country] {
                return list.contains { $0.code == text } ? nil
                    : violation("‘\(text)’는 \(country)의 ISO 3166-2 코드가 아닙니다. 목록에서 고르세요. 예: KR-47(경상북도)")
            }
            if text.range(of: #"^[A-Z]{2}-[A-Z0-9]{1,3}$"#, options: .regularExpression) == nil {
                return violation("ISO 3166-2 코드 형식(국가코드-지역코드)이 아닙니다. 예: KR-47")
            }
            if let country, !text.hasPrefix(country + "-") {
                return violation("country(\(country))와 다른 나라의 코드입니다. \(country)-로 시작해야 합니다.")
            }
            return nil
        case (.address, "postal_code"):
            return text == nil ? warning("우편번호가 없으면 Apple 검증이 경고합니다.") : nil
        case (.building, "category"), (.occupant, "category"):
            guard let text else { return violation("비어 있습니다. 목록에서 고르세요.") }
            return PropertySchema.categoryOptions(for: type).contains(text) ? nil
                : violation("‘\(text)’는 \(type.rawValue) category에 없는 값입니다. 목록에서 고르세요.")
        case (.building, "restriction"):
            guard let text else { return nil }
            return restrictionOptions.contains(text) ? nil : violation("employeesonly 또는 restricted만 쓸 수 있습니다.")
        case (.building, "name"), (.occupant, "name"):
            if !value.projectJSON.object.isEmpty { return nil }
            return type == .occupant ? violation("비어 있습니다. 기본 언어의 상호를 넣으세요.")
                : warning("건물 이름이 없으면 Apple 검증이 경고합니다.")
        case (.building, "alt_name"):
            guard !value.isNull else { return nil }
            return f.value("name").isNull ? warning("alt_name만 있고 name이 없습니다. name을 먼저 넣으세요.") : nil
        case (.building, "address_id"):
            return value.isNull ? warning("주소를 고르지 않으면 Apple 검증이 경고합니다(venue 주소를 따릅니다).") : nil
        case (.occupant, "anchor_id"):
            return value.isNull ? violation("비어 있습니다. 이 매장이 놓일 anchor를 고르세요.") : nil
        case (.occupant, "hours"):
            guard let text else { return warning("영업시간이 없으면 Apple 검증이 경고합니다.") }
            return isOpeningHours(text) ? nil
                : warning("복합 OSM opening_hours 표현은 Apple Sandbox에서 확인하세요. 예: Mo-Fr 09:00-18:00; Sa off")
        case (.occupant, "phone"):
            guard let text else { return warning("전화번호가 없으면 Apple 검증이 경고합니다.") }
            return text.range(of: #"^\+[1-9][0-9]{6,14}(;ext=[0-9]+)?$"#, options: .regularExpression) != nil ? nil
                : violation("E.164 형식이 아닙니다. 0을 떼고 +82를 붙이세요. 예: 054-279-2114 → +82542792114")
        case (.occupant, "website"):
            guard let text else { return warning("웹사이트가 없으면 Apple 검증이 경고합니다.") }
            guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else {
                return violation("http:// 또는 https://로 시작하는 주소여야 합니다. 예: https://example.com")
            }
            return nil
        case (.manifest, "language"):
            guard let text else { return nil }
            return IMDFValidation.validLanguageTag(text) ? nil
                : violation("언어 태그 형식이 아닙니다. 언어 소문자-지역 대문자로 쓰세요. 예: ko-KR")
        default:
            return nil
        }
    }

    /// 정보 type 한 feature의 모든 문제. 내보내기 점검이 쓴다.
    static func problems(in f: FeatureGroup) -> [(key: String, problem: FieldProblem)] {
        PropertySchema.fields(for: f.featureType).compactMap { field in
            problem(f.featureType, field.key, in: f).map { (field.key, $0) }
        }
    }

    // MARK: 고를 수 있는 값

    /// 자유 입력 대신 목록에서 고르는 칸. (값, 보이는 이름). nil이면 글자칸이다.
    static func choices(_ type: IMDFFeatureType, _ key: String, in f: FeatureGroup) -> [(value: String, label: String)]? {
        switch (type, key) {
        case (.address, "country"):
            let ko = Locale(identifier: "ko_KR")
            return isoCountries.sorted().map { ($0, "\($0) \(ko.localizedString(forRegionCode: $0) ?? "")") }
        case (.address, "province"):
            guard case .string(let country) = f.value("country"), let list = subdivisions[country] else { return nil }
            return list.map { ($0.code, "\($0.code) \($0.name)") }
            // 목록을 아는 나라(지금은 한국)만 고르게 하고, 나머지는 형식만 점검하는 글자칸으로 둔다.
        case (.building, "restriction"):
            return restrictionOptions.map { ($0, $0) }
        default:
            return nil
        }
    }

    static let restrictionOptions = ["employeesonly", "restricted"]

    /// ISO 3166-1 alpha-2. 시스템이 아는 지역 코드 가운데 두 글자 영문만 쓴다(숫자 코드는 대륙 등 묶음이다).
    static let isoCountries: Set<String> = Set(Locale.Region.isoRegions.map(\.identifier)
        .filter { $0.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil })

    /// ISO 3166-2 하위 구역. 한국 17개(2023-11 개정 기준, 코드는 2000년 이후 그대로).
    static let subdivisions: [String: [(code: String, name: String)]] = [
        "KR": [
            ("KR-11", "서울특별시"), ("KR-26", "부산광역시"), ("KR-27", "대구광역시"), ("KR-28", "인천광역시"),
            ("KR-29", "광주광역시"), ("KR-30", "대전광역시"), ("KR-31", "울산광역시"), ("KR-50", "세종특별자치시"),
            ("KR-41", "경기도"), ("KR-42", "강원특별자치도"), ("KR-43", "충청북도"), ("KR-44", "충청남도"),
            ("KR-45", "전북특별자치도"), ("KR-46", "전라남도"), ("KR-47", "경상북도"), ("KR-48", "경상남도"),
            ("KR-49", "제주특별자치도"),
        ],
    ]

    /// OSM opening_hours의 흔한 형태만 받는다. 전체 문법(공휴일 규칙·월 범위 등)은 검사하지 않는다.
    static func isOpeningHours(_ text: String) -> Bool {
        let day = "(Mo|Tu|We|Th|Fr|Sa|Su|PH|SH)"
        let days = "\(day)(-\(day))?(,\(day)(-\(day))?)*"
        let time = "([01][0-9]|2[0-4]):[0-5][0-9]-([01][0-9]|2[0-4]|[0-9]{2}):[0-5][0-9]"
        let rule = "^(24/7|(\(days) )?(\(time)(,\(time))*|off|closed))$"
        let parts = text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        return !parts.isEmpty && parts.allSatisfy { $0.range(of: rule, options: .regularExpression) != nil }
    }
}
