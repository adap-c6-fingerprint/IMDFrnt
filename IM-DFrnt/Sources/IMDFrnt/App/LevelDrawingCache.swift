import Foundation
import SwiftUI

/// A value snapshot of the expensive inputs, independent of the editor actor.
struct LevelDrawingInput: Equatable, Sendable {
    let levelID: UUID
    let svg: String
    let sourceName: String
    var segmentation = SegmentationStore()
    var excluded: Set<VectorObjectID> = []
    var doors: [TemporaryDoor] = []

    init(_ level: ProjectLevel) {
        levelID = level.id; svg = level.info.svg; sourceName = level.info.sourceName
        segmentation = level.editing.segmentation
        excluded = level.editing.auxiliary.excluded
        doors = level.editing.doorClosures.doors
    }

    init(levelID: UUID, svg: String, sourceName: String) {
        self.levelID = levelID; self.svg = svg; self.sourceName = sourceName
    }
}

struct PreparedLevelDrawing: Sendable {
    let input: LevelDrawingInput
    let document: DrawingDocument?
    let renderEntries: [VectorObjectID: ObjectRenderCache]
    let attributeIndex: [String: [VectorObjectID]]
    let spatialIndex: SpatialIndex
    let twinKeys: [VectorObjectID: String]
    let twinGroups: [PreparedTwinGroup]
    let totalPolygonCount: Int
    let vanishedPolygonCount: Int
    let preparationSeconds: Double

    struct PreparedTwinGroup: Sendable {
        let key: String
        let memberIDs: [VectorObjectID]
        let sample: VectorObject
    }

    /// The same pipeline serves file validation and background UI loading.
    static func make(_ input: LevelDrawingInput) throws -> Self {
        let start = ContinuousClock.now
        try Task.checkCancellation()
        let doc = try input.svg.isEmpty ? nil : SVGParser.parse(data: Data(input.svg.utf8), sourceName: input.sourceName)
        let objects = doc?.objects ?? []
        var entries: [VectorObjectID: ObjectRenderCache] = [:]
        var attributes: [String: [VectorObjectID]] = [:]
        var keys: [VectorObjectID: String] = [:]
        var buckets: [String: [VectorObject]] = [:]
        var sources: [ClosedPolygonFinder.SourceSegment] = []
        var remaining: [ClosedPolygonFinder.SourceSegment] = []
        for object in objects {
            try Task.checkCancellation()
            let geometry = input.segmentation.effectiveGeometry(for: object.id, fallback: object.geometry)
            let segments = geometry.lineSegments()
            entries[object.id] = ObjectRenderCache(path: geometry.swiftUIPath, segments: segments, box: geometry.boundingBox)
            attributes[object.style.attributeKey, default: []].append(object.id)
            let key = object.twinKey
            keys[object.id] = key; buckets[key, default: []].append(object)
            let pieces = segments.map { ClosedPolygonFinder.SourceSegment(segment: $0, objectID: object.id) }
            sources.append(contentsOf: pieces)
            if !input.excluded.contains(object.id) { remaining.append(contentsOf: pieces) }
        }
        let doors = input.doors.map { ClosedPolygonFinder.SourceSegment(segment: LineSegment(start: $0.start, end: $0.end), objectID: nil) }
        sources.append(contentsOf: doors); remaining.append(contentsOf: doors)
        try Task.checkCancellation()
        let total = ClosedPolygonFinder.faces(in: sources).count
        try Task.checkCancellation()
        let vanished = input.excluded.isEmpty ? 0 : max(0, total - ClosedPolygonFinder.faces(in: remaining).count)
        try Task.checkCancellation()
        let groups = buckets.compactMap { key, objects -> PreparedTwinGroup? in
            guard let sample = objects.first else { return nil }
            return PreparedTwinGroup(key: key, memberIDs: objects.map(\.id), sample: sample)
        }.sorted { $0.memberIDs.count != $1.memberIDs.count ? $0.memberIDs.count > $1.memberIDs.count : $0.sample.ordinal < $1.sample.ordinal }
        let duration = start.duration(to: .now).components
        return Self(input: input, document: doc, renderEntries: entries, attributeIndex: attributes,
            spatialIndex: SpatialIndex(objects: objects, canvasSize: doc?.canvasSize ?? .zero),
            twinKeys: keys, twinGroups: groups, totalPolygonCount: total, vanishedPolygonCount: vanished,
            preparationSeconds: Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
    }
}

/// Bounded per-project LRU; completed and in-flight values are never global.
@MainActor
final class LevelDrawingCache {
    private struct Pending {
        let token: UUID
        let generation: UUID
        let input: LevelDrawingInput
        let task: Task<PreparedLevelDrawing, Error>
    }
    private var entries: [UUID: PreparedLevelDrawing] = [:]
    private var order: [UUID] = []
    private var pending: [UUID: Pending] = [:]
    private var pendingOrder: [UUID] = []
    private var generation = UUID()
    let capacity: Int
    let maximumCost = 128 * 1024 * 1024
    private(set) var preparationCount = 0
    private(set) var hitCount = 0
    var count: Int { entries.count }

    init(capacity: Int = 6) { self.capacity = max(1, capacity) }

    func cached(_ input: LevelDrawingInput) -> PreparedLevelDrawing? {
        guard let value = entries[input.levelID], value.input == input else { return nil }
        hitCount += 1
        touch(input.levelID)
        return value
    }

    func insert(_ value: PreparedLevelDrawing) {
        entries[value.input.levelID] = value
        touch(value.input.levelID)
        while order.count > capacity { entries.removeValue(forKey: order.removeFirst()) }
        while entries.count > 1, entries.values.reduce(0, { $0 + cost($1) }) > maximumCost {
            entries.removeValue(forKey: order.removeFirst())
        }
    }

    private func cost(_ value: PreparedLevelDrawing) -> Int {
        value.input.svg.utf8.count + value.renderEntries.count * 512
            + value.renderEntries.values.reduce(0) { $0 + $1.segments.count * 96 }
            + (value.document?.rasterImages.reduce(0) { $0 + $1.image.width * $1.image.height * 4 } ?? 0)
    }

    private func touch(_ id: UUID) {
        order.removeAll { $0 == id }; order.append(id)
    }

    func load(_ input: LevelDrawingInput) async throws -> PreparedLevelDrawing {
        if let value = cached(input) { return value }
        let work: Pending
        if let existing = pending[input.levelID], existing.input == input {
            work = existing
        } else {
            pending[input.levelID]?.task.cancel()
            pendingOrder.removeAll { $0 == input.levelID }
            while pendingOrder.count >= 2 {
                pending.removeValue(forKey: pendingOrder.removeFirst())?.task.cancel()
            }
            preparationCount += 1
            work = Pending(token: UUID(), generation: generation, input: input, task: Task.detached(priority: .userInitiated) {
                try PreparedLevelDrawing.make(input)
            })
            pending[input.levelID] = work
            pendingOrder.append(input.levelID)
        }
        do {
            let value = try await work.task.value
            guard generation == work.generation else { throw CancellationError() }
            if pending[input.levelID]?.token != work.token {
                guard entries[input.levelID]?.input == input else { throw CancellationError() }
                return value
            }
            pending.removeValue(forKey: input.levelID)
            pendingOrder.removeAll { $0 == input.levelID }
            insert(value)
            return value
        } catch {
            if pending[input.levelID]?.token == work.token {
                pending.removeValue(forKey: input.levelID); pendingOrder.removeAll { $0 == input.levelID }
            }
            throw error
        }
    }

    func invalidate(_ id: UUID) {
        pending.removeValue(forKey: id)?.task.cancel()
        pendingOrder.removeAll { $0 == id }
        entries.removeValue(forKey: id); order.removeAll { $0 == id }
    }

    func reset() {
        generation = UUID()
        for work in pending.values { work.task.cancel() }
        pending = [:]; pendingOrder = []; entries = [:]; order = []
    }
}
