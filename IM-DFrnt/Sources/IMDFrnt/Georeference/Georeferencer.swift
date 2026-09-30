import Foundation

/// Store와 변환을 잇는 얇은 파사드. `GeoPoint`를 만들 수 있는 유일한 경로다.
struct Georeferencer {
    private let transform: GeoAffineTransform?
    let pairCount: Int
    let fitError: String?

    init(pairs: [AnchorPair]) {
        pairCount = pairs.count
        do {
            transform = try GeoAffineTransform.fit(from: pairs)
            fitError = nil
        } catch let e as GeoAffineTransform.FitError {
            transform = nil
            fitError = pairs.count >= GeoAffineTransform.minimumPairs ? e.description : nil
        } catch {
            transform = nil
            fitError = error.localizedDescription
        }
    }

    var isConfigured: Bool { transform != nil }

    /// Anchor이 충분하면 nil을 절대 반환하지 않는다.
    /// 명세 7-3-6-3) "Anchor이 지정됐는데 coordinates가 안 나오는 것은 불가능"이 여기서 보장된다.
    func geoPoint(for local: LocalPoint) -> GeoPoint? {
        transform?.apply(local)
    }

    func geoPoints(for locals: [LocalPoint]) -> [GeoPoint]? {
        guard let transform else { return nil }
        return locals.map(transform.apply)
    }

    func residuals(for pairs: [AnchorPair]) -> [Double] {
        guard let transform else { return [] }
        return ResidualCalculator.residuals(of: transform, against: pairs)
    }
}
