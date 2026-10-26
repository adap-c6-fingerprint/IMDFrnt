import Foundation

extension ProjectLevel {
    /// IMDF에 명시한 Level ordinal을 우선한다. 비어 있을 때만 층 관리 값을 사용한다.
    /// 기준층 검색과 내보내기가 이 우선순위를 공유하고, 기존 사용자 값을 덮어쓰지 않는다.
    func ordinalForExport(_ property: ProjectJSON?) -> ProjectJSON {
        guard let property, property != .null else { return .number(Decimal(info.ordinal)) }
        return property
    }

    func exportsLevelOrdinal(_ ordinal: Int) -> Bool {
        let local = editing.features.features(ofType: .level).map { $0.value("ordinal").projectJSON }
        let imported = (geoJSON["level.geojson"] ?? []).map { $0["properties"]?["ordinal"] ?? .null }
        // 외곽이 없는 층도 찾아서 UI에서 '외곽을 먼저 그리세요'라고 안내한다.
        if local.isEmpty && imported.isEmpty { return info.ordinal == ordinal }
        let expected = ProjectJSON.number(Decimal(ordinal))
        // 가져온 GeoJSON은 원본 속성을 그대로 내보내므로 누락된 ordinal을 추측하지 않는다.
        return local.contains { ordinalForExport($0) == expected } || imported.contains(expected)
    }
}
