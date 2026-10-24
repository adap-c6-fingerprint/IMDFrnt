import Foundation

/// Apple IMDF 1.0.0 preflight for the actual archive bytes, shared by ZIP and client dataset exports.
/// https://register.apple.com/resources/imdf/reference/reference
/// Draft project saving is deliberately not gated by these delivery requirements.
enum IMDFValidation {
    struct Report {
        var errors: [String] = []
        var warnings: [String] = []
    }

    struct Record {
        let file: String
        let value: ProjectJSON
        let type: IMDFFeatureType?
        let id: String
        var properties: ProjectJSON { value["properties"] ?? .object([:]) }
        var label: String { "\(file) · \(id.isEmpty ? "ID 없음" : String(id.prefix(8)))" }
    }

    static let required: [IMDFFeatureType: [String]] = [
        .address: ["address", "locality", "country"], .venue: ["category", "name", "display_point", "address_id"],
        .building: ["category"], .footprint: ["category", "building_ids"],
        .level: ["category", "outdoor", "ordinal", "name", "short_name"],
        .unit: ["category", "level_id"], .fixture: ["category", "level_id"],
        .opening: ["category", "level_id"], .section: ["category", "level_id"],
        .detail: ["level_id"], .kiosk: ["level_id"], .geofence: ["category"],
        .amenity: ["category", "unit_ids"], .anchor: ["unit_id"], .occupant: ["category", "name", "anchor_id"],
        .relationship: ["category", "direction"]
    ]

    static func check(files: [String: Data]) -> Report {
        var result = Report()
        var json: [String: ProjectJSON] = [:]
        for (name, data) in files {
            if name.contains("/") || name.contains("\\") || name == "." || name == ".." {
                result.errors.append("파일명 \(name): IMDF 파일은 ZIP 최상위의 안전한 파일명이어야 합니다.")
            }
            do { json[name] = try ProjectJSON.parse(data) }
            catch { if name.hasSuffix(".json") || name.hasSuffix(".geojson") { result.errors.append("\(name): JSON을 읽을 수 없습니다.") } }
        }
        let manifest = json["manifest.json"]
        if manifest == nil || manifest?.isObject != true { result.errors.append("manifest.json: JSON 객체가 필요합니다.") }
        if manifest?["version"]?.string != "1.0.0" { result.errors.append("manifest.json · version: 1.0.0이어야 합니다.") }
        let language = manifest?["language"]?.string ?? ""
        if !validLanguageTag(language) { result.errors.append("manifest.json · language: 유효한 BCP 47 기본 언어 태그가 필요합니다.") }
        let created = manifest?["created"]?.string ?? ""
        if ISO8601DateFormatter().date(from: created) == nil { result.errors.append("manifest.json · created: UTC 오프셋이 있는 ISO 8601 생성 시각이 필요합니다.") }
        if let extensions = manifest?["extensions"], extensions != .null,
           extensions.isArray == false || extensions.array.contains(where: { $0.string?.isEmpty != false }) {
            result.errors.append("manifest.json · extensions: 확장 식별자 문자열 배열 또는 null이어야 합니다.")
        }

        var records: [Record] = []
        var byID: [String: Record] = [:]
        for name in json.keys.sorted() where name.hasSuffix(".geojson") {
            guard let collection = json[name], collection["type"]?.string == "FeatureCollection",
                  collection["features"]?.isArray == true else {
                result.errors.append("\(name): features 배열이 있는 FeatureCollection이어야 합니다."); continue
            }
            let expected = String(name.dropLast(".geojson".count))
            for value in collection["features"]!.array {
                let id = value["id"]?.string?.lowercased() ?? ""
                let typeString = value["feature_type"]?.string ?? ""
                let record = Record(file: name, value: value, type: IMDFFeatureType(rawValue: typeString), id: id)
                records.append(record)
                if value["type"]?.string != "Feature" { result.errors.append("\(record.label): type은 Feature여야 합니다.") }
                if !validID(id) { result.errors.append("\(record.label): id는 UUID v4여야 합니다.") }
                if byID[id] != nil { result.errors.append("\(record.label): Feature UUID가 다른 레코드와 중복됩니다.") }
                else if !id.isEmpty { byID[id] = record }
                if typeString != expected || typeString == "manifest" {
                    result.errors.append("\(record.label): feature_type은 파일 타입 \(expected)와 같아야 합니다.")
                }
                if record.type == nil && (manifest?["extensions"]?.array.isEmpty ?? true) {
                    result.errors.append("\(record.label): 비표준 Feature 타입은 manifest.extensions에 선언된 확장이 필요합니다.")
                }
                if value["properties"]?.isObject != true { result.errors.append("\(record.label): properties JSON 객체가 필요합니다.") }
            }
        }
        if records.filter({ $0.type == .address }).isEmpty { result.errors.append("address.geojson: Address가 최소 1개 필요합니다. 상단 address에서 공통 주소를 추가하세요.") }
        if records.filter({ $0.type == .venue }).count != 1 { result.errors.append("venue.geojson: Venue는 아카이브 전체에 정확히 1개여야 합니다.") }

        for record in records {
            checkProperties(record, language: language, byID: byID, result: &result)
        }
        checkParentCycles(records, result: &result)
        IMDFSpatialValidation.check(records, byID: byID, result: &result)
        result.errors = Array(NSOrderedSet(array: result.errors)) as? [String] ?? result.errors
        result.warnings = Array(NSOrderedSet(array: result.warnings)) as? [String] ?? result.warnings
        return result
    }

    private static func checkProperties(_ record: Record, language: String, byID: [String: Record], result: inout Report) {
        guard let type = record.type else { return }
        let properties = record.properties
        if record.value["imdfrnt_local_display_point"] != nil {
            result.warnings.append("\(record.label): 이전 로컬 display_point는 GPS 없이 변환할 수 없어 원본을 프로젝트에 보관했습니다. 공통 정보의 display_point GPS를 확인하세요.")
        }
        func fail(_ key: String, _ message: String) { result.errors.append("\(record.label) · \(key): \(message)") }
        for key in required[type] ?? [] where properties[key] == nil || properties[key] == .null {
            fail(key, "필수 값을 입력하세요.")
        }
        for field in PropertySchema.fields(for: type) where field.key != "id" && !field.isNonStandard {
            guard let value = properties[field.key], value != .null else { continue }
            switch field.type {
            case .string:
                if let text = value.string {
                    if text.isEmpty || text != text.trimmingCharacters(in: .whitespacesAndNewlines) { fail(field.key, "빈 값 또는 앞뒤 공백은 허용하지 않습니다.") }
                } else { fail(field.key, "문자열이어야 합니다.") }
            case .integer:
                if value.integer == nil { fail(field.key, "정수여야 합니다.") }
            case .boolean:
                if value.boolean == nil { fail(field.key, "true 또는 false여야 합니다.") }
            case .localizedName:
                guard value.isObject, !value.object.isEmpty else { fail(field.key, "언어 태그별 이름 객체가 필요합니다."); continue }
                if !value.object.keys.contains(where: { $0.lowercased() == language.lowercased() }) {
                    fail(field.key, "Manifest 기본 언어 \(language)의 이름을 포함하세요.")
                }
                var tags = Set<String>()
                for (tag, text) in value.object {
                    if !validLanguageTag(tag) || !tags.insert(tag.lowercased()).inserted { fail(field.key, "유효하고 중복 없는 언어 태그가 필요합니다: \(tag)") }
                    guard let s = text.string, !s.isEmpty, s == s.trimmingCharacters(in: .whitespacesAndNewlines) else {
                        fail(field.key, "\(tag) 이름은 비어 있지 않은 문자열이어야 합니다."); continue
                    }
                }
            case .reference(let target): reference(value, target: target.rawValue, record: record, key: field.key, byID: byID, result: &result)
            case .stringArray:
                guard value.isArray, value.array.allSatisfy({ $0.string != nil }) else { fail(field.key, "문자열 배열이어야 합니다."); continue }
                let strings = value.array.compactMap(\.string)
                if Set(strings.map { $0.lowercased() }).count != strings.count { fail(field.key, "중복 값을 제거하세요.") }
                if (required[type] ?? []).contains(field.key) && strings.isEmpty { fail(field.key, "최소 하나의 참조가 필요합니다.") }
                let target: String? = switch field.key {
                case "building_ids": "building"
                case "level_ids": "level"
                case "unit_ids": "unit"
                case "parents": type.rawValue
                default: nil
                }
                if let target { for item in value.array { reference(item, target: target, record: record, key: field.key, byID: byID, result: &result) } }
            case .point: break // Parsed and spatially checked with the geometry below.
            case .json: checkNested(value, key: field.key, record: record, byID: byID, result: &result)
            case .alwaysNull: break
            }
        }
        if let category = properties["category"]?.string {
            let choices = PropertySchema.categoryOptions(for: type)
            if !choices.isEmpty && !choices.contains(category) { fail("category", "공식 \(type.rawValue) category 값이 아닙니다: \(category)") }
        }
        if let restriction = properties["restriction"], restriction != .null,
           !["employeesonly", "restricted"].contains(restriction.string ?? "") { fail("restriction", "employeesonly 또는 restricted만 허용됩니다.") }
        for key in ["accessibility", "access_control"] {
            let allowed = key == "accessibility"
                ? ["assisted.listening", "braille", "hearing", "hearingloop", "signlanginterpreter", "tactilepaving", "tdd", "trs", "volume", "wheelchair"]
                : ["badgereader", "fingerprintreader", "guard", "keyaccess", "outofservice", "passwordaccess", "retinascanner", "voicerecognition"]
            for item in properties[key]?.array ?? [] where !allowed.contains(item.string ?? "") { fail(key, "공식 허용값이 아닙니다: \(item.text)") }
        }
        if let correlation = properties["correlation_id"], correlation != .null, !validID(correlation.string ?? "") { fail("correlation_id", "UUID v4여야 합니다.") }
        if type == .level, properties["outdoor"]?.boolean == false,
           (properties["building_ids"]?.array.isEmpty ?? true) { fail("building_ids", "실내 Level은 Building을 참조해야 합니다.") }
        if type == .address {
            var feature = FeatureGroup(featureType: .address, serialNumber: record.id, memberIDs: [])
            feature.properties = properties.object.mapValues(PropertyValue.from)
            for key in ["country", "province"] {
                if let problem = PropertyRules.problem(.address, key, in: feature), problem.severity == .violation { fail(key, problem.message) }
            }
        }
        if type == .relationship {
            if !["directed", "undirected"].contains(properties["direction"]?.string ?? "") { fail("direction", "directed 또는 undirected여야 합니다.") }
            if (properties["origin"] == nil || properties["origin"] == .null)
                && (properties["destination"] == nil || properties["destination"] == .null) { fail("origin/destination", "최소 한쪽 Feature 참조가 필요합니다.") }
        }
        for key in ["phone", "website"] {
            guard let text = properties[key]?.string else { continue }
            if key == "phone", text.range(of: #"^\+[1-9][0-9]{1,14}(;ext=[0-9]+)?$"#, options: .regularExpression) == nil { fail(key, "+국가번호로 시작하는 E.164 전화번호가 필요합니다.") }
            if key == "website", URL(string: text).map({ ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host?.isEmpty == false }) != true { fail(key, "http:// 또는 https:// 웹 주소가 필요합니다.") }
        }
        if let hours = properties["hours"]?.string, !PropertyRules.isOpeningHours(hours) {
            result.warnings.append("\(record.label) · hours: 복합 OSM opening_hours 표현은 Apple Sandbox에서 확인하세요.")
        }
    }

    private static func checkNested(_ value: ProjectJSON, key: String, record: Record, byID: [String: Record], result: inout Report) {
        func fail(_ text: String) { result.errors.append("\(record.label) · \(key): \(text)") }
        if ["origin", "destination", "intermediary"].contains(key) {
            let values = key == "intermediary" ? value.array : [value]
            if key == "intermediary" && !value.isArray { fail("Feature 참조 배열이어야 합니다.") }
            for item in values {
                guard item.isObject, let target = item["feature_type"]?.string else { fail("id와 feature_type이 있는 참조 객체가 필요합니다."); continue }
                reference(item["id"] ?? .null, target: target, record: record, key: key, byID: byID, result: &result)
            }
        } else if key == "door" {
            guard value.isObject else { fail("Door JSON 객체여야 합니다."); return }
            let types = ["movablepartition", "open", "revolving", "shutter", "sliding", "swinging", "turnstile", "turnstile.fullheight", "turnstile.waistheight"]
            if let type = value["type"], type != .null, !types.contains(type.string ?? "") { fail("허용되지 않은 door.type입니다.") }
            if let material = value["material"], material != .null, !["wood", "glass", "metal", "gate"].contains(material.string ?? "") { fail("허용되지 않은 door.material입니다.") }
            if let automatic = value["automatic"], automatic != .null, automatic.boolean == nil { fail("door.automatic은 true/false/null이어야 합니다.") }
        } else if key == "validity" {
            guard value.isObject else { fail("Temporality JSON 객체여야 합니다."); return }
            for name in ["start", "end", "modified"] {
                if let date = value[name], date != .null, date.string.flatMap({ ISO8601DateFormatter().date(from: $0) }) == nil,
                   date.string?.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil { fail("validity.\(name)에 ISO 8601 날짜/시각을 넣으세요.") }
            }
        }
    }

    private static func reference(_ value: ProjectJSON, target: String, record: Record, key: String, byID: [String: Record], result: inout Report) {
        let id = value.string?.lowercased() ?? ""
        if !validID(id) || byID[id]?.value["feature_type"]?.string != target {
            result.errors.append("\(record.label) · \(key): 실제 \(target) Feature의 UUID를 선택하세요 (\(value.text)).")
        }
        if key == "parents" && id == record.id { result.errors.append("\(record.label) · parents: 자기 자신을 부모로 지정할 수 없습니다.") }
    }

    private static func checkParentCycles(_ records: [Record], result: inout Report) {
        let parents = Dictionary(records.filter { $0.type == .section || $0.type == .geofence }.map {
            ($0.id, $0.properties["parents"]?.array.compactMap { $0.string?.lowercased() } ?? [])
        }, uniquingKeysWith: { a, _ in a })
        var done = Set<String>(), visiting = Set<String>()
        func visit(_ id: String) {
            if visiting.contains(id) { result.errors.append("\(id) · parents: 부모 관계에 순환이 있습니다."); return }
            guard !done.contains(id) else { return }
            visiting.insert(id)
            for parent in parents[id] ?? [] { visit(parent) }
            visiting.remove(id); done.insert(id)
        }
        for id in parents.keys { visit(id) }
    }

    static func validID(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil
    }

    private static let languageCodes = Set(Locale.LanguageCode.isoLanguageCodes.map { $0.identifier.lowercased() })

    static func validLanguageTag(_ value: String) -> Bool {
        let tag = value.lowercased()
        let grandfathered = ["art-lojban", "cel-gaulish", "en-gb-oed", "i-ami", "i-bnn", "i-default", "i-enochian", "i-hak", "i-klingon", "i-lux", "i-mingo", "i-navajo", "i-pwn", "i-tao", "i-tay", "i-tsu", "no-bok", "no-nyn", "sgn-be-fr", "sgn-be-nl", "sgn-ch-de", "zh-guoyu", "zh-hakka", "zh-min", "zh-min-nan", "zh-xiang"]
        if grandfathered.contains(tag) { return true }
        let pattern = #"^(?:[A-Za-z]{2,3}(?:-[A-Za-z]{3}){0,3}|[A-Za-z]{4}|[A-Za-z]{5,8})(?:-[A-Za-z]{4})?(?:-[A-Za-z]{2}|-[0-9]{3})?(?:-(?:[A-Za-z0-9]{5,8}|[0-9][A-Za-z0-9]{3}))*(?:-[0-9A-WY-Za-wy-z](?:-[A-Za-z0-9]{2,8})+)*(?:-x(?:-[A-Za-z0-9]{1,8})+)?$|^x(?:-[A-Za-z0-9]{1,8})+$"#
        guard value.range(of: pattern, options: .regularExpression) != nil, let base = tag.split(separator: "-").first.map(String.init) else { return false }
        if base == "x" || (base.count == 3 && base >= "qaa" && base <= "qtz") { return true }
        return languageCodes.contains(base)
    }
}

extension ProjectJSON {
    var isObject: Bool { if case .object = self { return true }; return false }
    var isArray: Bool { if case .array = self { return true }; return false }
    var double: Double? { if case .number(let n) = self { return NSDecimalNumber(decimal: n).doubleValue }; return nil }
    var integer: Int? { if case .number = self { return Int(text) }; return nil }
    var boolean: Bool? { if case .bool(let b) = self { return b }; return nil }
}
