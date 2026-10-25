import Foundation

enum IMDFLabels {
    /// Keep all labels; add the exact default tag from a generic label of the same language if needed.
    static func properties(_ properties: ProjectJSON, type: IMDFFeatureType, language: String) -> ProjectJSON {
        var result = properties
        let base = language.split(separator: "-").first.map(String.init) ?? language
        for field in PropertySchema.fields(for: type) where field.type == .localizedName {
            guard var labels = result[field.key], labels.isObject,
                  !labels.object.keys.contains(where: { $0.lowercased() == language.lowercased() }),
                  let generic = labels.object.first(where: { $0.key.lowercased() == base.lowercased() })?.value,
                  generic.string?.isEmpty == false else { continue }
            labels[language] = generic
            result[field.key] = labels
        }
        return result
    }
}
