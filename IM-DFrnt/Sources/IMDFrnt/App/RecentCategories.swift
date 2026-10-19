import Foundation

/// unit category의 최근 태깅 순서(2026-10-19 요청). unit category는 값이 수십 개라, 방금 쓴 값을 매번
/// 검색하거나 목록에서 다시 찾아야 했다. 최근 고른 값을 목록 맨 위에 최근 순으로 올린다.
///
/// 프로젝트가 아니라 이 Mac의 설정(`projectDefaults`)에 둔다 — 같은 사람이 여러 도면에서 같은 값을 이어 쓰기 때문이다.
/// 실행취소 대상이 아니다. 고른 기록일 뿐 데이터가 아니다.
@MainActor
extension AppEnvironment {
    static let recentUnitCategoriesKey = "recentUnitCategories"
    static let recentCategoryLimit = 12

    /// 최근 고른 unit category(최근 것이 앞).
    var recentUnitCategories: [String] {
        projectDefaults.stringArray(forKey: Self.recentUnitCategoriesKey) ?? []
    }

    /// category를 고른 기록을 남긴다. unit만 기록한다.
    func recordRecentCategory(_ value: String, type: IMDFFeatureType) {
        guard type == .unit, !value.isEmpty else { return }
        var list = recentUnitCategories.filter { $0 != value }
        list.insert(value, at: 0)
        projectDefaults.set(Array(list.prefix(Self.recentCategoryLimit)), forKey: Self.recentUnitCategoriesKey)
    }

    /// category 칸에 보일 순서. unit은 최근 고른 값이 앞(최근 순), 나머지는 종전 순서다. 다른 type은 그대로다.
    func categoryOptionsOrdered(for type: IMDFFeatureType) -> (options: [String], recent: Set<String>) {
        let options = PropertySchema.categoryOptions(for: type)
        guard type == .unit else { return (options, []) }
        let valid = Set(options)
        let recent = recentUnitCategories.filter { valid.contains($0) }
        // 스펙 목록에 없는 값(예전 기록)은 올리지 않는다.
        let picked = Set(recent)
        return (recent + options.filter { !picked.contains($0) }, picked)
    }
}
