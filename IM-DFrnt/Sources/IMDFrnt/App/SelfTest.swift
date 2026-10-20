import AppKit
import CoreLocation
import Foundation
import MapKit
import SwiftUI

/// `IM-DFrnt --selftest` 로 실행하면 GUI 없이 파싱·기하·변환·직렬화를 점검한다.
/// UI를 손으로 눌러보지 않고도 엔진이 살아 있는지 확인하기 위한 개발용 경로다.
@MainActor
enum SelfTest {

    /// SwiftUI Color의 상대 휘도. 대비 검사용이라 sRGB 근사로 충분하다.
    private static func luminance(of color: Color) -> Double {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return 0.2126 * Double(ns.redComponent)
             + 0.7152 * Double(ns.greenComponent)
             + 0.0722 * Double(ns.blueComponent)
    }

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--selftest") else { return false }
        var failures = 0

        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            let mark = condition ? "PASS" : "FAIL"
            if !condition { failures += 1 }
            print("[\(mark)] \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }

        print("== IM-DFrnt self test ==")

        // 1. SVG 파싱
        guard let data = SampleFloorplan.svg.data(using: .utf8),
              let doc = try? SVGParser.parse(data: data, sourceName: SampleFloorplan.name) else {
            print("[FAIL] SVG 파싱 — 문서를 만들지 못했습니다"); exit(1)
        }
        check("SVG 파싱", doc.objects.count == 27, "개체 \(doc.objects.count)개")
        check("viewBox 반영", doc.canvasSize == CGSize(width: 1000, height: 700),
              "\(doc.canvasSize)")

        let curved = doc.curvedObjectIDs
        check("곡선 개체 검출", curved.count == 5, "곡선 \(curved.count)개 (circle/ellipse/C/A/Q-T)")

        let kinds = Dictionary(grouping: doc.objects, by: \.sourceElement).mapValues(\.count)
        check("요소 종류", kinds["rect"] == 7 && kinds["line"] == 6 && kinds["path"] == 8
              && kinds["circle"] == 1 && kinds["ellipse"] == 1
              && kinds["polygon"] == 1 && kinds["polyline"] == 3,
              "\(kinds.sorted { $0.key < $1.key })")

        // 2. 스타일 보존 ('같은 속성 모아보기'의 근거)
        let doorKeys = Set(doc.objects.filter { $0.sourceElement == "line" }.map(\.style.attributeKey))
        check("문 6개의 스타일 키 일치", doorKeys.count == 1, "고유 키 \(doorKeys.count)개")
        let dashed = doc.objects.filter { !$0.style.dashPattern.isEmpty }
        check("점선 속성 보존", dashed.count == 6, "점선 개체 \(dashed.count)개")

        // 3. 선분화 + 검증
        var seg = SegmentationStore()
        var defectCount = 0
        for id in curved {
            guard let o = doc.object(id) else { continue }
            defectCount += seg.segmentize(id, geometry: o.geometry, tolerance: 0.6).count
        }
        check("곡선 5개 선분화", seg.segmentedObjectIDs.count == 5 && defectCount == 0,
              "결함 \(defectCount)건")
        if let anyID = curved.first, let s = seg.segmentation(for: anyID) {
            let gaps = SegmentationValidator.validate(s.segments, epsilon: 1e-4)
            check("선분 연속성·비교차", gaps.isEmpty, "결함 \(gaps.count)건, 선분 \(s.segments.count)개")
        }

        // 교차는 선분화를 막지 않는다(2026-10-18). 직선과 곡선이 X자로 가로지르는, 원본이 스스로 꼬인 path도 선분화한다.
        let eightSVG = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100">
        <path d="M 0 0 L 100 100 L 100 0 C 80 13 37 61 3 97" fill="none" stroke="#000"/>
        </svg>
        """
        if let eight = try? SVGParser.parse(data: Data(eightSVG.utf8), sourceName: "eight.svg").objects.first {
            let raw = SegmentationValidator.validate(CurveFlattener.flatten(eight.geometry, tolerance: 0.01), epsilon: 1e-4)
            var eightStore = SegmentationStore()
            let defects = eightStore.segmentize(eight.id, geometry: eight.geometry, tolerance: 0.6)
            check("선분화: 원본이 꼬인 곡선도 교차 오류 없이 선분화한다",
                  raw.contains(where: \.isCrossing) && defects.isEmpty && eightStore.isSegmented(eight.id),
                  "가장 잘게 잘라도 교차 \(raw.filter(\.isCrossing).count)건 — 도면 자체가 꼬인 것이다")
            if case .success(let s) = SegmentationStore.prepare(eight.id, geometry: eight.geometry, tolerance: 0.6) {
                let coarse = SegmentationValidator.validate(CurveFlattener.flatten(eight.geometry, tolerance: 0.6), epsilon: 1e-4)
                    .contains(where: \.isCrossing)
                check("선분화: 교차가 있을 때만 더 잘게 다시 잘라 본다", coarse ? s.tolerance < 0.6 : s.tolerance == 0.6,
                      "0.6에서 교차 \(coarse ? "있음" : "없음") → 허용 오차 \(s.tolerance)")
            }
        } else {
            check("선분화: 꼬인 곡선 검사 도면을 읽는다", false)
        }

        // unit 빈틈·겹침 — 같은 층 unit끼리 겹치거나 틈이 있으면 안 된다(IMDF).
        func covBox(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [[LocalPoint]] {
            [[LocalPoint(x0, y0), LocalPoint(x1, y0), LocalPoint(x1, y1), LocalPoint(x0, y1)]]
        }
        let covFitted = UnitCoverage.analyze(units: [covBox(0, 0, 100, 100), covBox(100, 0, 200, 100)], levels: [covBox(0, 0, 200, 100)])
        check("unit 빈틈·겹침: 변을 정확히 공유하면 둘 다 없다", covFitted.isEmpty,
              "빈틈 \(covFitted.gaps.count) · 겹침 \(covFitted.overlaps.count)")
        let covSliver = UnitCoverage.analyze(units: [covBox(0, 0, 100, 100), covBox(100.03, 0, 200, 100)], levels: [covBox(0, 0, 200, 100)])
        check("unit 빈틈·겹침: 0.03 어긋난 변 사이의 얇은 틈도 찾는다", covSliver.gaps.count == 1 && covSliver.overlaps.isEmpty,
              "빈틈 넓이 \(covSliver.gaps.first.map(UnitCoverage.area) ?? 0)")
        let covOverlapped = UnitCoverage.analyze(units: [covBox(0, 0, 100, 100), covBox(90, 0, 200, 100)], levels: [covBox(0, 0, 200, 100)])
        check("unit 빈틈·겹침: 두 unit이 겹친 곳을 찾는다",
              covOverlapped.overlaps.count == 1 && covOverlapped.gaps.isEmpty
                  && abs((covOverlapped.overlaps.first.map(UnitCoverage.area) ?? 0) - 1000) < 1)
        let covRingOfUnits = UnitCoverage.analyze(units: [covBox(0, 0, 300, 100), covBox(0, 200, 300, 300), covBox(0, 100, 100, 200), covBox(200, 100, 300, 200)], levels: [])
        check("unit 빈틈·겹침: level이 없으면 빈틈을 계산하지 않는다(level 기준)",
              covRingOfUnits.gaps.isEmpty && !covRingOfUnits.hasLevel,
              "빈틈 \(covRingOfUnits.gaps.count)개")
        let covOuterGap = UnitCoverage.analyze(units: [covBox(0, 0, 300, 100), covBox(0, 200, 300, 300), covBox(0, 100, 100, 200), covBox(200, 100, 300, 200)],
                                               levels: [covBox(0, 0, 400, 300)])
        check("unit 빈틈·겹침: level 기준이면 unit에 둘러싸인 곳과 바깥 테두리 쪽 빈 곳을 모두 찾는다",
              covOuterGap.hasLevel && covOuterGap.gaps.count == 2
              && abs(covOuterGap.gaps.map(UnitCoverage.area).reduce(0, +) - 40_000) < 1)
        let covUncovered = UnitCoverage.analyze(units: [covBox(0, 0, 100, 100), covBox(100, 0, 200, 100)], levels: [covBox(0, 0, 300, 100)])
        check("unit 빈틈·겹침: level 안에서 unit이 덮지 않은 곳을 빈틈으로 본다",
              covUncovered.gaps.count == 1 && abs((covUncovered.gaps.first.map(UnitCoverage.area) ?? 0) - 10_000) < 1)
        let covDonut = covBox(0, 0, 300, 300) + covBox(100, 100, 200, 200)
        let covFilledHole = UnitCoverage.analyze(units: [covDonut, covBox(100, 100, 200, 200)], levels: [])
        check("unit 빈틈·겹침: MultiPolygon unit의 구멍을 다른 unit이 채우면 겹침이 아니다", covFilledHole.isEmpty,
              "빈틈 \(covFilledHole.gaps.count) · 겹침 \(covFilledHole.overlaps.count)")

        // IMDF 아카이브(#38) — 두 층의 작업을 type별 파일 하나로 합친다.
        func archiveLevel(_ name: String, _ ordinal: Int, withLevelPolygon: Bool = true, anchored: Bool = true) -> ProjectLevel {
            var level = ProjectLevel(info: ProjectLevelInfo(name: name, ordinal: ordinal))
            if anchored {
                level.info.anchors.add(local: LocalPoint(0, 0), geo: GeoPoint(longitude: 129.3250, latitude: 36.0150), label: "A")
                level.info.anchors.add(local: LocalPoint(1000, 0), geo: GeoPoint(longitude: 129.3260, latitude: 36.0150), label: "B")
                level.info.anchors.add(local: LocalPoint(1000, 1000), geo: GeoPoint(longitude: 129.3260, latitude: 36.0140), label: "C")
                level.info.anchors.add(local: LocalPoint(0, 1000), geo: GeoPoint(longitude: 129.3250, latitude: 36.0140), label: "D")
            }
            func add(_ type: IMDFFeatureType, _ serial: String, _ ring: [LocalPoint]) {
                var f = FeatureGroup(featureType: type, serialNumber: serial, memberIDs: [])
                for field in PropertySchema.fields(for: type) { f.properties[field.key] = .null }
                f.polygonRings = [ring]
                level.editing.features.insert(f)
            }
            if withLevelPolygon {
                add(.level, "level-001", [LocalPoint(0, 0), LocalPoint(1000, 0), LocalPoint(1000, 1000), LocalPoint(0, 1000)])
            }
            add(.unit, "unit-001", [LocalPoint(0, 0), LocalPoint(500, 0), LocalPoint(500, 500), LocalPoint(0, 500)])
            add(.unit, "unit-002", [LocalPoint(500, 0), LocalPoint(1000, 0), LocalPoint(1000, 500), LocalPoint(500, 500)])
            return level
        }
        func archiveData(_ levels: [ProjectLevel]) -> Data {
            var file = ProjectFile.empty()
            file.buildingProject = BuildingProject(levels: levels)
            return try! file.encoded()
        }
        func json(_ data: Data?) -> [String: Any] { (data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:] }
        func features(_ data: Data?) -> [[String: Any]] { json(data)["features"] as? [[String: Any]] ?? [] }

        let floor1 = archiveLevel("1층", 0), floor2 = archiveLevel("2층", 1)
        do {
            let out = try IMDFArchive.build(projectData: archiveData([floor1, floor2]), documents: [:])
            let units = features(out.files["unit.geojson"])
            let levelsOut = features(out.files["level.geojson"])
            func levelID(_ f: [String: Any]) -> String? { (f["properties"] as? [String: Any])?["level_id"] as? String }
            check("IMDF 아카이브: 모든 층의 unit이 unit.geojson 하나에 모인다",
                  units.count == 4 && Set(units.compactMap(levelID)) == [floor1.id.uuidString.lowercased(), floor2.id.uuidString.lowercased()],
                  "unit \(units.count)개 — 층마다 파일을 나누지 않고 level_id로 층을 가린다")
            check("IMDF 아카이브: level feature의 id는 그 층의 UUID이고 ordinal·name이 채워진다",
                  levelsOut.count == 2 && levelsOut.contains { f in
                      f["id"] as? String == floor2.id.uuidString.lowercased()
                          && (f["properties"] as? [String: Any])?["ordinal"] as? Int == 1
                          && ((f["properties"] as? [String: Any])?["name"] as? [String: String])?["ko"] == "2층"
                  })
            check("IMDF 아카이브: 층마다 같은 일련번호(unit-001)도 id가 겹치지 않는다",
                  Set(units.compactMap { $0["id"] as? String }).count == 4)
            let manifest = json(out.files["manifest.json"])
            check("IMDF 아카이브: manifest.json은 version 1.0.0·created·language를 갖는다",
                  manifest["version"] as? String == "1.0.0" && (manifest["created"] as? String)?.isEmpty == false
                      && manifest["language"] as? String == "ko-KR")
            check("IMDF 아카이브: 필수 파일 address·venue는 비어도 들어가고 경고한다",
                  out.files["address.geojson"] != nil && out.files["venue.geojson"] != nil && out.warnings.count == 2)
            check("IMDF 아카이브: geometry는 위경도 Polygon이다",
                  ((units.first?["geometry"] as? [String: Any])?["type"] as? String) == "Polygon"
                      && (((units.first?["geometry"] as? [String: Any])?["coordinates"] as? [[[Double]]])?.first?.first?.first ?? 0) > 129)

            var again1 = floor1, again2 = floor2
            again1.editing.ids = out.ids[floor1.id]!; again2.editing.ids = out.ids[floor2.id]!
            let second = try IMDFArchive.build(projectData: archiveData([again1, again2]), documents: [:])
            check("IMDF 아카이브: 발급한 id를 되돌려 넣으면 다시 내보내도 같은 id다",
                  Set(features(second.files["unit.geojson"]).compactMap { $0["id"] as? String }) == Set(units.compactMap { $0["id"] as? String }))

            let zipDir = FileManager.default.temporaryDirectory.appendingPathComponent("IMDFrntArchiveTest-\(UUID())")
            try FileManager.default.createDirectory(at: zipDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: zipDir) }
            let zip = zipDir.appendingPathComponent("archive.zip")
            try IMDFArchive.writeZip(out.files, to: zip)
            let reread = try IMDFImporter.load(zip)
            check("IMDF 아카이브: ZIP을 다시 불러오면 두 층과 파일이 그대로 읽힌다",
                  reread.floors.count == 2 && reread.files["unit.geojson"] != nil && reread.files["manifest.json"] != nil,
                  "층 \(reread.floors.count)개 · 파일 \(reread.files.count)개")
        } catch {
            check("IMDF 아카이브: 두 층 프로젝트를 묶는다", false, "\(error)")
        }
        do {
            _ = try IMDFArchive.build(projectData: archiveData([floor1, archiveLevel("2층", 1, withLevelPolygon: false)]), documents: [:])
            check("IMDF 아카이브: level 다각형이 없는 층은 막는다", false)
        } catch let blocked as IMDFArchive.Blocked {
            check("IMDF 아카이브: level 다각형이 없는 층은 막는다", blocked.messages.contains { $0.hasPrefix("2층:") && $0.contains("level") })
        } catch { check("IMDF 아카이브: level 다각형이 없는 층은 막는다", false, "\(error)") }
        do {
            _ = try IMDFArchive.build(projectData: archiveData([floor1, archiveLevel("2층", 1, anchored: false)]), documents: [:])
            check("IMDF 아카이브: Anchor가 없는 층은 막는다", false)
        } catch let blocked as IMDFArchive.Blocked {
            check("IMDF 아카이브: Anchor가 없는 층은 막는다", blocked.messages.contains { $0.hasPrefix("2층:") && $0.contains("Anchor") })
        } catch { check("IMDF 아카이브: Anchor가 없는 층은 막는다", false, "\(error)") }

        // 진행률 팝업 — 시작·갱신·종료. 나중 작업이 자리를 차지하면 먼저 끝난 작업이 닫지 않는다.
        let lt = AppEnvironment()
        let first = lt.beginLongTask("첫 작업")
        lt.updateLongTask(first, fraction: 0.5, detail: "절반")
        check("진행률 팝업: 진행률과 설명을 갱신한다", lt.longTask?.fraction == 0.5 && lt.longTask?.detail == "절반")
        let second = lt.beginLongTask("둘째 작업", fraction: nil)
        lt.endLongTask(first)
        check("진행률 팝업: 끝난 작업이 다른 작업의 팝업을 닫지 않는다", lt.longTask?.id == second && lt.longTask?.fraction == nil)
        lt.endLongTask(second)
        check("진행률 팝업: 작업이 끝나면 저절로 닫힌다", lt.longTask == nil)

        // 일련번호 태그 마우스오버 — 올리면 강조(주황), 떼면 원래 색.
        let hoverID = FeatureGroupID()
        lt.hoveredFeature = hoverID
        let hoveredOn = lt.isFeatureHighlighted(hoverID)
        lt.hoveredFeature = nil
        check("태그 마우스오버: 올린 동안만 그 feature를 강조한다", hoveredOn && !lt.isFeatureHighlighted(hoverID))

        // 4. 어파인 변환 + 잔차
        let pairs = [
            AnchorPair(local: LocalPoint(60, 60), geo: GeoPoint(longitude: 129.3242, latitude: 36.0169), label: "NW"),
            AnchorPair(local: LocalPoint(940, 60), geo: GeoPoint(longitude: 129.3270, latitude: 36.0169), label: "NE"),
            AnchorPair(local: LocalPoint(940, 640), geo: GeoPoint(longitude: 129.3270, latitude: 36.0151), label: "SE"),
            AnchorPair(local: LocalPoint(60, 640), geo: GeoPoint(longitude: 129.3242, latitude: 36.0151), label: "SW"),
        ]
        let geo = Georeferencer(pairs: pairs)
        check("어파인 fit (4쌍)", geo.isConfigured, geo.fitError ?? "")
        let res = geo.residuals(for: pairs)
        check("잔차 계산", res.count == 4 && ResidualCalculator.rms(res) < 0.5,
              String(format: "RMS %.4f m", ResidualCalculator.rms(res)))

        let short = Georeferencer(pairs: Array(pairs.prefix(2)))
        check("2쌍이면 변환 거부", !short.isConfigured)

        let collinear = [
            AnchorPair(local: LocalPoint(0, 0), geo: GeoPoint(longitude: 1, latitude: 1), label: "a"),
            AnchorPair(local: LocalPoint(10, 10), geo: GeoPoint(longitude: 2, latitude: 2), label: "b"),
            AnchorPair(local: LocalPoint(20, 20), geo: GeoPoint(longitude: 3, latitude: 3), label: "c"),
        ]
        check("한 직선 위 3점 거부", !Georeferencer(pairs: collinear).isConfigured)

        // 자동 Anchor 후보: OSM의 닫힌 건물 외곽을 읽고, 도면의 순서 있는 외곽과 맞춘다.
        let osmXML = """
        <osm version="0.6">
          <node id="1" lon="127.0720000" lat="37.4957000"/>
          <node id="2" lon="127.0724000" lat="37.4957000"/>
          <node id="3" lon="127.0724000" lat="37.4955000"/>
          <node id="4" lon="127.0720000" lat="37.4955000"/>
          <way id="42"><nd ref="1"/><nd ref="2"/><nd ref="3"/><nd ref="4"/><nd ref="1"/>
            <tag k="building" v="yes"/><tag k="name" v="시험 건물"/></way>
          <way id="43"><nd ref="1"/><nd ref="2"/><nd ref="3"/><nd ref="4"/><nd ref="1"/>
            <tag k="building" v="no"/></way>
          <way id="44"><nd ref="1"/><nd ref="2"/><nd ref="3"/>
            <tag k="building" v="yes"/></way>
        </osm>
        """
        let center = GeoPoint(longitude: 127.0722, latitude: 37.4956)
        let buildings = (try? BuildingFootprintService.parse(Data(osmXML.utf8), near: center)) ?? []
        check("OSM: 닫힌 건물만 읽고 building=no 제외", buildings.count == 1
              && buildings.first?.id == "42" && buildings.first?.name == "시험 건물")
        check("OSM: 잘못된 XML 거부",
              (try? BuildingFootprintService.parse(Data("<osm><way>".utf8), near: center)) == nil)

        if let building = buildings.first {
            let metersPerLongitude = 111_000 * cos(building.center.latitude * .pi / 180)
            let localOutline = building.coordinates.map { point in
                let x = (point.longitude - building.center.longitude) * metersPerLongitude
                let y = (point.latitude - building.center.latitude) * 111_000
                return LocalPoint(300 + 5 * x, 200 - 5 * y)
            }
            let proposal = AutoAnchorMatcher.propose(localOutline: localOutline, building: building)
            check("자동 Anchor: 같은 외곽에서 4쌍 생성", proposal?.pairs.count == 4
                  && proposal?.canApply == true && (proposal?.rmsMeters ?? .infinity) < 0.1)
            let reversed = AutoAnchorMatcher.propose(localOutline: Array(localOutline.reversed()),
                                                      building: building)
            check("자동 Anchor: 도면 외곽의 반대 순서 허용", reversed?.canApply == true
                  && (reversed?.rmsMeters ?? .infinity) < 0.1)
            let unrelated = [LocalPoint(0, 0), LocalPoint(100, 0),
                             LocalPoint(100, 100), LocalPoint(0, 100)]
            let unrelatedProposal = AutoAnchorMatcher.propose(localOutline: unrelated,
                                                               building: building)
            check("자동 Anchor: 다른 외곽 형태 적용 거부",
                  unrelatedProposal?.canApply == false,
                  String(format: "오차 %.1f%% / %.1f m",
                         (unrelatedProposal?.relativeError ?? 0) * 100,
                         unrelatedProposal?.rmsMeters ?? 0))
            check("자동 Anchor: 점이 부족하면 후보 없음",
                  AutoAnchorMatcher.propose(localOutline: Array(localOutline.prefix(3)),
                                            building: building) == nil)
            if let proposal {
                let autoEnv = AppEnvironment()
                autoEnv.addAutoAnchorProposal(proposal)
                check("자동 Anchor: 4쌍을 한 작업으로 적용", autoEnv.anchors.pairs.count == 4
                      && autoEnv.georeferencer.isConfigured && autoEnv.canUndo)
                autoEnv.undo()
                check("자동 Anchor: 한 번에 실행 취소", autoEnv.anchors.pairs.isEmpty)
            }
        }

        // 5. 소유권
        var reg = OwnershipRegistry()
        let f1 = UUID(), f2 = UUID()
        let ids = Set(doc.objects.prefix(3).map(\.id))
        var ownershipOK = (try? reg.claim(ids, for: f1)) != nil
        do { try reg.claim(ids, for: f2); ownershipOK = false } catch { }
        check("전역 유일 소유권", ownershipOK, "중복 claim 거부됨")

        // 6. 좌표 추출 + GeoJSON 직렬화
        guard let room = doc.objects.first(where: { $0.sourceElement == "rect" }) else {
            print("[FAIL] rect 없음"); exit(1)
        }
        var f = FeatureGroup(featureType: .unit, serialNumber: "unit-001", memberIDs: [room.id])
        f.properties["category"] = .string("room")
        f.properties["name"] = .localized(en: "Room A", ko: "A실")
        f.displayPoint = LocalPoint(room.boundingBox.midX, room.boundingBox.midY)

        let verts = VertexExtractor.vertices(for: f, document: doc, segmentation: seg, kind: .polygon)
        check("폴리곤 꼭짓점 추출", verts.count == 4, "\(verts.count)개")

        var assigner = IDAssigner()
        let exporter = GeoJSONExporter(document: doc, segmentation: seg, georeferencer: geo)
        let fc = exporter.buildFeatureCollection(type: .unit, features: [f],
                                                 ids: &assigner, serialToUUID: [:])
        let json = (try? JSONSerialization.data(withJSONObject: fc, options: [.prettyPrinted]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        check("GeoJSON 직렬화", json.contains("\"Polygon\"") && json.contains("\"display_point\""),
              "\(json.count)바이트")

        let firstUUID = assigner.peek(f.id)
        _ = exporter.buildFeatureCollection(type: .unit, features: [f], ids: &assigner, serialToUUID: [:])
        check("재내보내기 시 id 유지", assigner.peek(f.id) == firstUUID,
              "UUID \(firstUUID?.uuidString.prefix(8) ?? "?")")
        assigner.retire(f.id)
        let reissued = assigner.id(for: f.id)
        check("폐기 UUID 재사용 금지", reissued != firstUUID)

        let floorID = UUID()
        var leveled = f
        leveled.properties["level_id"] = .string("level-001")
        // 예전 화면에서 고른 일련번호가 남아 있어도 층 UUID가 앞선다.
        var levelAssigner = IDAssigner()
        let levelExporter = GeoJSONExporter(document: doc, segmentation: seg, georeferencer: geo, levelID: floorID)
        let leveledProps = (levelExporter.buildFeatureCollection(type: .unit, features: [leveled], ids: &levelAssigner,
                                                                 serialToUUID: ["level-001": UUID()])["features"]
                            as? [[String: Any]])?.first?["properties"] as? [String: Any]
        check("level_id: 층 관리의 층 UUID(소문자)로 자동 지정된다",
              leveledProps?["level_id"] as? String == floorID.uuidString.lowercased())

        // 7. 내보내기 차단 조건
        let blocked = ExportValidator(document: doc, features: [f],
                                      anchors: AnchorStore(),
                                      georeferencer: Georeferencer(pairs: []),
                                      segmentation: seg).validate(type: .unit)
        check("Anchor 없으면 차단", blocked.contains { if case .anchorsInsufficient = $0 { return true }; return false })

        var cps = AnchorStore(); cps.pairs = pairs
        let passed = ExportValidator(document: doc, features: [f], anchors: cps,
                                     georeferencer: geo, segmentation: seg).validate(type: .unit)
        check("Anchor 갖추면 통과", passed.isEmpty, "차단 \(passed.count)건")

        // 8. 상호작용 계층 — 사용자가 화면에서 하는 순서를 그대로 재현한다.
        let env = AppEnvironment()
        check("앱: 시작 시 도면 없음", env.document == nil,
              "샘플이 자동으로 열리면 안 된다(명세 디버깅 12번)")

        env.openSample()
        check("앱: 자체점검용 샘플 적재", env.document?.objects.count == 27,
              "UI 경로는 없앴지만 이 함수는 자체점검 입력으로 남아 있어야 한다")

        // 명세 10-1: opening 선행 태깅 게이트. 사용자도 이 순서를 거치므로 시험도 같은 순서다.
        env.selectPropertyType(.unit)
        check("게이트: opening 전에는 다른 type이 안 열린다",
              env.layers.activePropertyType != .unit,
              "명세 10-1-1 — 문을 확정해야 방 폴리곤을 닫을 수 있다")

        env.selectPropertyType(.opening)
        check("게이트: opening 자신은 언제나 열린다", env.layers.activePropertyType == .opening)

        env.declareOpeningComplete()
        check("게이트: 완료 선언하면 열린다", env.openingGate.allowsOtherTypes,
              "자동 판정은 불가능하다 — 도면에 문이 몇 개인지 프로그램은 모른다")

        env.selectPropertyType(.unit)
        check("앱: unit 레이어 생성", env.layers.activePropertyType == .unit)

        env.forceSelectMode = true
        check("앱: 대체 선택 토글", env.isSelectModeActive)

        // 방 rect 하나를 클릭해 선택
        guard let roomObj = env.document?.objects.first(where: { $0.sourceElement == "rect" }) else {
            print("[FAIL] rect 없음"); exit(1)
        }
        let edge = LocalPoint(roomObj.boundingBox.minX, roomObj.boundingBox.midY)
        env.handleCanvasClick(at: edge, tolerance: 6)
        check("앱: 클릭으로 개체 선택", env.selection.selected.contains(roomObj.id),
              "선택 \(env.selection.selected.count)개")

        env.createFeature()
        check("앱: Feature로 저장", env.features.count(ofType: .unit) == 1
              && env.features.features(ofType: .unit).first?.serialNumber == "unit-001")
        check("앱: 진행률 갱신", env.ownership.claimedCount == 1, env.progressText)

        // 같은 개체를 fixture 레이어에서 다시 선택 → 소유권 충돌 경고
        env.selectPropertyType(.fixture)
        env.handleCanvasClick(at: edge, tolerance: 6)
        check("앱: 소유권 충돌 경고", env.conflict?.ownerSerial == "unit-001")
        env.conflict = nil

        // Anchor 없이 내보내기 → 차단
        env.selectPropertyType(.unit)
        env.export()
        check("앱: Anchor 없으면 내보내기 차단", !env.exportBlockers.isEmpty,
              env.exportBlockers.first?.message ?? "")
        env.exportBlockers = []

        // Anchor 지정 화면 진입 → 선택 잠금
        env.enterAnchorScreen()
        check("앱: Anchor 화면 진입 시 선택 잠금",
              env.showAnchorScreen && env.mode == .anchorPicking && !env.isSelectModeActive)

        // 도면 클릭 → 지도 클릭(위경도 입력)의 2단계 흐름
        env.pendingAnchorLocal = pairs[0].local
        env.addAnchor(longitude: pairs[0].geo.longitude, latitude: pairs[0].geo.latitude, label: "NW")
        check("앱: 도면→지도 2단계로 쌍 완성",
              env.anchors.pairs.count == 1 && env.pendingAnchorLocal == nil)

        env.pendingAnchorLocal = pairs[1].local
        env.addAnchor(longitude: pairs[1].geo.longitude, latitude: pairs[1].geo.latitude, label: "NE")
        check("앱: 2쌍이면 겹쳐보기 프리뷰 가능",
              env.overlayTransform != nil && env.overlayIsPreviewOnly)
        check("앱: 2쌍은 확정 변환 아님", !env.georeferencer.isConfigured)

        env.pendingAnchorLocal = pairs[2].local
        env.addAnchor(longitude: pairs[2].geo.longitude, latitude: pairs[2].geo.latitude, label: "SE")
        check("앱: 3쌍이면 확정 어파인", env.georeferencer.isConfigured && !env.overlayIsPreviewOnly)
        check("앱: 3쌍이면 잔차 판정 불가", !env.anchors.isOverDetermined)

        // 마커 드래그로 미세 조정
        let movedID = env.anchors.pairs[0].id
        env.updateAnchorLocal(movedID, to: LocalPoint(61, 61))
        env.updateAnchorGeo(movedID, to: GeoPoint(longitude: 129.3243, latitude: 36.0170))
        check("앱: 마커 드래그 반영",
              env.anchors.pairs[0].local == LocalPoint(61, 61)
              && env.anchors.pairs[0].geo.longitude == 129.3243)

        env.anchors.pairs.removeAll()
        env.exitAnchorScreen()
        check("앱: Anchor 화면 이탈", !env.showAnchorScreen && env.mode == .idle)

        // 9-6 선정 기준 안내. 표시 자체는 눈으로 볼 일이지만, 명세 네 줄이 문구에서
        // 빠지지 않았는지는 상수만 보고도 확인할 수 있다.
        check("Anchor 기준: 적합 4가지가 모두 있다",
              AnchorCriteria.suitable.count == 4
              && AnchorCriteria.suitable.contains { $0.text.contains("외벽 모서리") },
              "\(AnchorCriteria.suitable.count)가지")
        check("Anchor 기준: 부적합에는 이유가 반드시 붙는다",
              !AnchorCriteria.unsuitable.isEmpty
              && AnchorCriteria.unsuitable.allSatisfy { !$0.note.isEmpty },
              "부적합 \(AnchorCriteria.unsuitable.count)가지")
        check("Anchor 기준: 고층 건물은 지면 접합부",
              AnchorCriteria.tallBuildingNote.contains("접합부")
              && !AnchorCriteria.principle.isEmpty)

        // 지도 장소 검색 (2026-08-26). 네트워크가 필요한 검색 자체는 여기서 못 돌린다 —
        // 순수 계산(검색어 정규화·이동 범위 계산·실패 문구)만 검증한다.
        check("검색: 공백뿐인 검색어는 검색하지 않는다",
              PlaceSearchModel.normalized("   ") == nil
              && PlaceSearchModel.normalized(" 제2공학관 ") == "제2공학관")

        let wideResult = PlaceSearchModel.PlaceResult(
            name: "넓은 캠퍼스", subtitle: "",
            coordinate: CLLocationCoordinate2D(latitude: 36.0150, longitude: 129.3240),
            boundingRegion: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 36.0150, longitude: 129.3240),
                latitudinalMeters: 8000, longitudinalMeters: 8000))
        let wide = PlaceSearchModel.focusRegion(for: wideResult)
        check("검색: 넓은 장소도 모서리를 찍을 만큼 당겨진다",
              wide.span.latitudeDelta * 111_000 <= PlaceSearchModel.maximumMeters + 1,
              String(format: "%.0f m", wide.span.latitudeDelta * 111_000))

        let pointResult = PlaceSearchModel.PlaceResult(
            name: "점 하나", subtitle: "",
            coordinate: CLLocationCoordinate2D(latitude: 36.0150, longitude: 129.3240),
            boundingRegion: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 36.0150, longitude: 129.3240),
                latitudinalMeters: 5, longitudinalMeters: 5))
        let near = PlaceSearchModel.focusRegion(for: pointResult)
        check("검색: 점 장소도 주변이 보일 만큼 물러난다",
              near.span.latitudeDelta * 111_000 >= PlaceSearchModel.minimumMeters - 1,
              String(format: "%.0f m", near.span.latitudeDelta * 111_000))
        check("검색: 이동 중심은 고른 장소의 좌표",
              abs(near.center.latitude - 36.0150) < 1e-9
              && abs(near.center.longitude - 129.3240) < 1e-9)

        // 지도 마커 드래그 (2026-08-26). 집는 순간 튀지 않는지 · 카메라 고정 범위가 맞는지.
        let markerGeo = CLLocationCoordinate2D(latitude: 36.0150, longitude: 129.3240)
        let grabbedAt = CLLocationCoordinate2D(latitude: 36.0149, longitude: 129.3238)
        let grab = AnchorMapMath.grabOffset(cursor: grabbedAt, marker: markerGeo)
        let heldStill = AnchorMapMath.draggedCoordinate(cursor: grabbedAt, grab: grab)
        check("지도 마커: 집기만 해서는 움직이지 않는다",
              abs(heldStill.latitude - markerGeo.latitude) < 1e-12
              && abs(heldStill.longitude - markerGeo.longitude) < 1e-12,
              "집은 지점과 마커 중심의 차이를 유지한다 — 커서로 순간이동하면 넓은 축척에서 몇 km가 튄다")

        let cursorMoved = CLLocationCoordinate2D(latitude: grabbedAt.latitude + 0.0001,
                                                 longitude: grabbedAt.longitude + 0.0002)
        let dragged = AnchorMapMath.draggedCoordinate(cursor: cursorMoved, grab: grab)
        check("지도 마커: 커서가 움직인 만큼만 움직인다",
              abs((dragged.latitude - markerGeo.latitude) - 0.0001) < 1e-12
              && abs((dragged.longitude - markerGeo.longitude) - 0.0002) < 1e-12)

        let fitted = AnchorMapMath.regionFitting([
            CLLocationCoordinate2D(latitude: 36.0140, longitude: 129.3230),
            CLLocationCoordinate2D(latitude: 36.0160, longitude: 129.3250)])
        check("지도 마커: 고정 범위가 Anchor 전부를 담는다",
              fitted != nil
              && fitted!.span.latitudeDelta >= 0.0020
              && fitted!.span.longitudeDelta >= 0.0020
              && abs(fitted!.center.latitude - 36.0150) < 1e-9)

        let single = AnchorMapMath.regionFitting([markerGeo])
        check("지도 마커: 한 점뿐이어도 최소 범위를 준다",
              single != nil
              && single!.span.latitudeDelta * 111_000 >= AnchorMapMath.minimumSpanMeters - 1,
              String(format: "%.0f m", (single?.span.latitudeDelta ?? 0) * 111_000))
        check("지도 마커: Anchor가 없으면 고정하지 않는다",
              AnchorMapMath.regionFitting([]) == nil)

        check("검색: 연결 실패와 결과 없음을 구분한다",
              PlaceSearchModel.failureMessage(for:
                  NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
                  .contains("인터넷")
              && PlaceSearchModel.failureMessage(for: MKError(.placemarkNotFound))
                  .contains("결과가 없습니다"))

        // Anchor 4쌍 주입 후 좌표 표가 채워지는지
        for p in pairs { env.anchors.pairs.append(p) }
        let fid = env.features.features(ofType: .unit)[0].id
        let rows = env.vertexRows(for: fid)
        check("앱: 좌표 표 위경도 채움", rows.count == 4 && rows.allSatisfy { $0.1 != nil })

        // display point 범위 밖 거부 / 안쪽 허용
        env.beginDisplayPointPicking(fid)
        env.setDisplayPoint(LocalPoint(-500, -500), for: fid)
        check("앱: 범위 밖 display point 거부", env.features.feature(fid)?.displayPoint == nil)
        env.setDisplayPoint(LocalPoint(roomObj.boundingBox.midX, roomObj.boundingBox.midY), for: fid)
        check("앱: 범위 안 display point 허용", env.features.feature(fid)?.displayPoint != nil)

        // 곡선 모드 + 선분화 → 해제
        env.mode = .curvedOnly(showSegmentedOnly: false)
        env.segmentize(env.document?.curvedObjectIDs ?? [])
        check("앱: 곡선 전체 선분화", env.segmentedCount == 5, "\(env.segmentedCount)/\(env.curvedObjectCount)")
        env.desegmentize(env.document?.curvedObjectIDs ?? [])
        check("앱: 선분화 해제", env.segmentedCount == 0)
        env.mode = .idle

        // 휴지통 → 복원
        env.trash(fid)
        check("앱: 휴지통", env.features.count(ofType: .unit) == 0 && env.ownership.claimedCount == 0)
        env.restore(fid)
        check("앱: 복원", env.features.count(ofType: .unit) == 1 && env.ownership.claimedCount == 1)

        // property type 14종 — section·geofence 추가분 확인
        check("property type 14종", IMDFFeatureType.allCases.count == 14,
              "\(IMDFFeatureType.allCases.count)종")
        check("section geometry", IMDFFeatureType.section.requiredGeometry == .polygon)
        check("geofence geometry", IMDFFeatureType.geofence.requiredGeometry == .polygon)
        check("section 스키마", !PropertySchema.fields(for: IMDFFeatureType.section).isEmpty)
        check("geofence 스키마", PropertySchema.fields(for: IMDFFeatureType.geofence)
                .contains { $0.key == "parents" })

        // 문 빌려주기 대상(명세 10-2-4) — 닫힌 폴리곤이 필요한 type만
        let borrowers = IMDFFeatureType.allCases.filter(\.canBorrowOpenings).map(\.rawValue).sorted()
        check("빌려주기 대상", borrowers == ["fixture", "footprint", "geofence", "level",
                                          "section", "unit", "venue"],
              borrowers.joined(separator: ","))
        check("amenity는 빌리지 않음", !IMDFFeatureType.amenity.canBorrowOpenings,
              "geometry가 Point라 닫을 폴리곤이 없다")
        check("opening 자신은 제외", !IMDFFeatureType.opening.canBorrowOpenings)

        // 9. 겹침 표시 (명세 2-3의 '위치 이동'을 대체)
        // 선분 단위 판정을 먼저 못박고, 그 위에 앱 계층을 확인한다.
        let horizontal = LineSegment(start: LocalPoint(0, 0), end: LocalPoint(10, 0))
        let vertical = LineSegment(start: LocalPoint(5, -5), end: LocalPoint(5, 5))
        check("겹침: 가로지르는 교차점",
              OverlapDetector.crossing(horizontal, vertical) == LocalPoint(5, 0))

        let cornerTouch = LineSegment(start: LocalPoint(10, 0), end: LocalPoint(10, 9))
        check("겹침: 꼭짓점 접합은 교차 아님",
              OverlapDetector.crossing(horizontal, cornerTouch) == nil,
              "방 모서리끼리 맞닿은 정상 도면이 겹침으로 잡히면 안 된다")

        let tJunction = LineSegment(start: LocalPoint(4, 0), end: LocalPoint(4, 8))
        check("겹침: T자 접합은 교차로 잡음",
              OverlapDetector.crossing(horizontal, tJunction) == LocalPoint(4, 0))

        let apart = LineSegment(start: LocalPoint(0, 30), end: LocalPoint(10, 30))
        check("겹침: 떨어진 평행선은 아님",
              OverlapDetector.sharedRun(horizontal, apart, tolerance: 0.5) == nil)

        let doubled = LineSegment(start: LocalPoint(3, 0.05), end: LocalPoint(20, 0.05))
        let run = OverlapDetector.sharedRun(horizontal, doubled, tolerance: 0.5)
        check("겹침: 이중선의 공유 구간", run?.start == LocalPoint(3, 0) && run?.end == LocalPoint(10, 0),
              run.map { "\($0.start.x)~\($0.end.x)" } ?? "없음")

        check("겹침: 선택이 없으면 표시 없음",
              { env.selection.clear(); return env.overlapHighlight.isEmpty }())

        // 샘플 도면에서 실제로 겹치는 개체를 찾아 앱 계층까지 확인한다.
        if let doc = env.document {
            var found = false
            for o in doc.objects {
                env.selection.clear()
                env.selection.toggle(o.id)
                if !env.overlapHighlight.isEmpty { found = true; break }
            }
            check("겹침: 샘플 도면에서 검출", found,
                  "겹침 \(env.overlapHighlight.count)곳, 상대 \(env.overlapHighlight.partnerIDs.count)개")

            env.showOverlapHighlight = false
            check("겹침: 토글 끄면 계산도 안 함", env.overlapHighlight.isEmpty)
            env.showOverlapHighlight = true
            env.selection.clear()
        }

        // 9-1. 위치 이동 재도입 (명세 2-3, 2026-08-25 사노 요청)
        if let doc = env.document, let moveObj = doc.objects.first {
            env.selection.clear()
            env.resetPositions()
            env.selection.toggle(moveObj.id)

            check("이동: 선택 전에는 오프셋 없음", env.offset(for: moveObj.id) == .zero)

            // 9-1-1. '개체 이동' 토글이 게이트 노릇을 하는가 (2026-08-29 사노 요청)
            check("이동: 토글 기본값은 꺼짐", env.isMoveEnabled == false,
                  "실수로 도면을 흐트러뜨리는 쪽이 비용이 크다 — 켜는 것은 사용자의 선택이어야 한다")

            let blockedBase = env.beginMove()
            env.applyMove(CGSize(width: 30, height: 30), from: blockedBase)
            check("이동: 토글이 꺼져 있으면 오프셋이 생기지 않는다",
                  blockedBase.isEmpty && env.offset(for: moveObj.id) == .zero && !env.hasAnyOffset)

            // 같은 자리를 토글만 바꿔 두 번 찍는다. '꺼지면 nil'만 보면 점이 빗나가도 통과하므로,
            // 켰을 때 실제로 잡히는 자리인지 함께 못박아야 게이트를 검사한 것이 된다.
            if let probe = moveObj.geometry.allPoints.first {
                env.isMoveEnabled = true
                let hitOn = env.movableHit(at: probe, tolerance: 6)
                env.isMoveEnabled = false
                let hitOff = env.movableHit(at: probe, tolerance: 6)
                check("이동: 토글이 꺼져 있으면 드래그가 이동 후보를 못 찾는다(화면 팬으로 흐른다)",
                      hitOn == moveObj.id && hitOff == nil)
            }

            env.isMoveEnabled = true

            let base = env.beginMove()
            env.applyMove(CGSize(width: 12, height: -7), from: base)
            check("이동: 오프셋이 반영된다",
                  env.offset(for: moveObj.id) == CGSize(width: 12, height: -7))

            let moved = env.displayGeometry(for: moveObj)
            let original = env.geometry(for: moveObj)
            check("이동: 화면 지오메트리가 오프셋만큼 밀린다",
                  moved.boundingBox.minX == original.boundingBox.minX + 12
                    && moved.boundingBox.minY == original.boundingBox.minY - 7)

            // 두 번째 델타는 시작점 기준 절대값이어야 한다 — 프레임마다 더하면 드리프트가 생긴다.
            env.applyMove(CGSize(width: 20, height: 0), from: base)
            check("이동: 델타는 시작점 기준 절대값(드리프트 없음)",
                  env.offset(for: moveObj.id) == CGSize(width: 20, height: 0))

            if let doc = env.document {
                let vertices = VertexExtractor.vertices(
                    for: FeatureGroup(id: FeatureGroupID(), featureType: .unit,
                                      serialNumber: "unit-test", memberIDs: [moveObj.id]),
                    document: doc, segmentation: env.segmentation,
                    kind: .lineString, borrowed: [])
                let rawEnd = moveObj.geometry.allPoints.last
                check("이동: 좌표 추출은 원본 좌표를 쓴다(이동 무관)",
                      vertices.last == rawEnd,
                      "이동은 화면 전용이라 VertexExtractor는 영향받지 않아야 한다")
            }

            env.resetPositions(env.selection.selected)
            check("이동: '원위치'가 선택분을 되돌린다", env.offset(for: moveObj.id) == .zero)

            env.applyMove(CGSize(width: 5, height: 5), from: env.beginMove())
            check("이동: '모든 개체 원위치' 대상 판정", env.hasAnyOffset)

            // 토글을 끄는 것은 '더는 못 옮긴다'는 뜻이지 '되돌린다'는 뜻이 아니다.
            // 안내 문구가 복구를 '모든 개체 원위치'에 맡기고 있으므로, 여기서 몰래 되돌리면
            // 겹침을 보려고 벌려 둔 배치가 확인도 하기 전에 사라진다.
            let beforeToggle = env.snapshot
            env.isMoveEnabled = false
            check("이동: 토글을 꺼도 이미 옮긴 개체는 그대로 남는다", env.hasAnyOffset)
            check("이동: 토글은 실행취소 스냅샷에 들어가지 않는다", env.snapshot == beforeToggle,
                  "화면 설정이라 cmd+z가 되돌릴 '작업'이 아니다 — 겹침 표시 토글·사이드바 폭과 같은 취급")

            env.resetPositions()
            check("이동: '모든 개체 원위치'가 전부 비운다", !env.hasAnyOffset)

            env.selection.clear()
        }

        // 10. 좌표 추출 — 교차점을 꼭짓점으로 (디버깅 5번)
        // 9번과 같은 '만나는 점 vs 교차점' 기준을 좌표 쪽에서도 보는지 먼저 못박는다.
        let cross1 = LineSegment(start: LocalPoint(0, 0), end: LocalPoint(10, 10))
        let cross2 = LineSegment(start: LocalPoint(0, 10), end: LocalPoint(10, 0))
        check("좌표: X자 교차는 교차점 하나만 남음",
              VertexExtractor.polygonRing(from: [cross1, cross2]) == [LocalPoint(5, 5)],
              "교차점을 지나쳐 찍힌 끝점 4개는 작도 흔적이라 뺀다")

        // 사각형을 모서리마다 2씩 지나치게 그린 '#'자 도면 — 실제 방은 안쪽 사각형이다.
        let hash = [
            LineSegment(start: LocalPoint(-2, 0), end: LocalPoint(12, 0)),
            LineSegment(start: LocalPoint(-2, 10), end: LocalPoint(12, 10)),
            LineSegment(start: LocalPoint(0, -2), end: LocalPoint(0, 12)),
            LineSegment(start: LocalPoint(10, -2), end: LocalPoint(10, 12))
        ]
        let hashRing = VertexExtractor.polygonRing(from: hash)
        check("좌표: 지나쳐 그린 사각형은 교차점 4개",
              Set(hashRing) == Set([LocalPoint(0, 0), LocalPoint(10, 0),
                                    LocalPoint(10, 10), LocalPoint(0, 10)]),
              "\(hashRing.count)개 — 꼬리 끝점 8개 제외")

        // 끝점끼리 정확히 맞닿은 정상 사각형은 손대지 않는다.
        let tidy = [
            LineSegment(start: LocalPoint(0, 0), end: LocalPoint(10, 0)),
            LineSegment(start: LocalPoint(10, 0), end: LocalPoint(10, 10)),
            LineSegment(start: LocalPoint(10, 10), end: LocalPoint(0, 10)),
            LineSegment(start: LocalPoint(0, 10), end: LocalPoint(0, 0))
        ]
        check("좌표: 만나는 점으로 그린 사각형은 그대로",
              VertexExtractor.polygonRing(from: tidy).count == 4,
              "꼭짓점 접합은 교차가 아니므로 자를 꼬리가 없다")

        // T자 접합은 한쪽 끝점이 상대 선분 위에 얹힌 것뿐이라 자유 끝점이 살아 있어야 한다(명세 7-3-5-1).
        let tRing = VertexExtractor.polygonRing(from: [
            LineSegment(start: LocalPoint(0, 0), end: LocalPoint(10, 0)),
            LineSegment(start: LocalPoint(4, 0), end: LocalPoint(4, 8))
        ])
        check("좌표: T자 접합의 자유 끝점은 유지",
              tRing.contains(LocalPoint(4, 8)) && tRing.contains(LocalPoint(4, 0)),
              "\(tRing.count)개")

        // 문서 계층 — 지나쳐 그린 벽 4개를 한 feature로 묶어도 같은 결과가 나와야 한다.
        let wallObjects = hash.enumerated().map { i, s in
            VectorObject(id: UUID(),
                         geometry: PathGeometry(subpaths: [
                            Subpath(start: s.start, segments: [.line(to: s.end)], isClosed: false)
                         ]),
                         style: .default, sourceElement: "line", ordinal: i)
        }
        let wallDoc = DrawingDocument(objects: wallObjects,
                                      canvasSize: CGSize(width: 20, height: 20),
                                      sourceName: "overshoot")
        let wallFeature = FeatureGroup(featureType: .unit, serialNumber: "unit-901",
                                       memberIDs: Set(wallObjects.map(\.id)))
        let wallRing = VertexExtractor.vertices(for: wallFeature, document: wallDoc,
                                                segmentation: SegmentationStore(), kind: .polygon)
        check("좌표: feature 단위에서도 교차점이 꼭짓점",
              Set(wallRing) == Set([LocalPoint(0, 0), LocalPoint(10, 0),
                                    LocalPoint(10, 10), LocalPoint(0, 10)]),
              "\(wallRing.count)개")

        // 10. 보조 개체 제외 (명세 디버깅 6번)
        env.selection.clear()
        env.auxiliary.clear()
        guard let auxDoc = env.document else { print("[FAIL] 문서 없음"); exit(1) }

        // 쌍둥이 판정은 위치를 보지 않는다 — 같은 모양이 흩어져 있는 게 보조 개체의 특징이다.
        let doors = auxDoc.objects.filter { $0.sourceElement == "line" }
        let doorKeySet = Set(doors.map(\.twinKey))
        check("보조: 위치 다른 같은 모양은 같은 키",
              doors.count == 6 && doorKeySet.count < doors.count,
              "문 \(doors.count)개 → 고유 키 \(doorKeySet.count)개")

        let allKeys = Set(auxDoc.objects.map(\.twinKey))
        check("보조: 모양 다르면 다른 키", allKeys.count > 1, "고유 키 \(allKeys.count)개")
        check("보조: 그룹 목록은 많은 것부터",
              zip(env.twinGroups, env.twinGroups.dropFirst()).allSatisfy { $0.count >= $1.count },
              "그룹 \(env.twinGroups.count)개")

        // 창 진입 → 개체 하나 지정 → 쌍둥이까지 확장
        env.enterAuxiliaryScreen()
        check("보조: 전용 창 진입", env.showAuxiliaryScreen && env.selection.isEmpty)

        guard let firstDoor = doors.first else { print("[FAIL] line 없음"); exit(1) }
        env.auxiliarySelection = [firstDoor.id]
        env.markSelectedAsAuxiliary()
        check("보조: 개체 하나 지정", env.auxiliary.isExcluded(firstDoor.id) && env.excludedCount == 1)
        check("보조: 지정 후 선택 자동 해제", env.auxiliarySelection.isEmpty,
              "지정이 끝난 개체가 골라진 채 남으면 다음 개체에 딸려 온다")
        check("보조: 선택이 비면 쌍둥이 표시도 꺼진다", !env.showTwinsOnly && !env.canShowTwins)

        // ✅ 2026-08-30 요청 2-1: '함께 지정될 쌍둥이'를 색으로 구분한다.
        // 종전에는 opacity(100% vs 75%)로만 드러나 밝은 배경에서 거의 읽히지 않았다.
        env.auxiliarySelection = [firstDoor.id]
        check("쌍둥이 색: '모두 표시'가 꺼져 있으면 대상이 없다",
              !env.showTwinsOnly && env.auxiliaryTwinPendingIDs.isEmpty,
              "켜지도 않았는데 칠하면 '무엇이 딸려 오는가'가 아니라 그냥 다른 색 도면이 된다")
        env.showTwinsOnly = true
        let pendingTwins = env.auxiliaryTwinPendingIDs
        check("쌍둥이 색: 직접 고른 개체는 대상에서 빠진다",
              pendingTwins.isDisjoint(with: env.auxiliarySelection),
              "고른 것은 선택색(파랑)으로 이미 드러난다 — 겹쳐 칠하면 경계가 사라진다")
        check("쌍둥이 색: 이미 제외된 개체도 대상에서 빠진다",
              pendingTwins.isDisjoint(with: env.auxiliary.excluded),
              "버튼을 눌러도 상태가 바뀌지 않는 것은 '앞으로 빠질 것'이 아니다")
        check("쌍둥이 색: 색 대상 + 고른 것 + 이미 제외 = 실제 지정 대상 전체",
              pendingTwins
                .union(env.auxiliarySelection)
                .union(env.twins(of: env.auxiliarySelection)
                        .intersection(env.auxiliary.excluded))
                == env.twins(of: env.auxiliarySelection),
              "화면에 색으로 보이는 것과 실제로 지정되는 것이 갈라지면 안 된다")
        env.showTwinsOnly = false
        env.auxiliarySelection = []

        let twinCount = env.twins(of: [firstDoor.id]).count
        env.auxiliarySelection = [firstDoor.id]
        // 지정이 선택을 비우므로 쌍둥이 확장은 다시 골라서 시작한다
        env.markTwinsAsAuxiliary()
        check("보조: 똑같이 생긴 개체까지 지정", env.excludedCount == twinCount,
              "\(env.excludedCount)개 (쌍둥이 \(twinCount)개)")

        // 진행률: 분모는 그대로, 분자에만 더해진다
        check("보조: 분모 불변", env.totalObjectCount == auxDoc.objects.count,
              "\(env.totalObjectCount)개 — 제외해도 전체 개체 수는 줄지 않는다")
        check("보조: 제외분이 진행률에 반영",
              abs(env.progressFraction - Double(env.claimedCount + env.excludedCount)
                  / Double(env.totalObjectCount)) < 1e-9,
              String(format: "%.1f%%", env.progressFraction * 100))
        check("보조: 저장분과 제외분이 색 구간으로 분리",
              abs(env.claimedFraction + env.excludedFraction - env.progressFraction) < 1e-9)
        check("보조: 진행률 100% 초과 없음", env.progressFraction <= 1.0 + 1e-9,
              String(format: "%.4f", env.progressFraction))

        // 제외된 개체는 어느 레이어에서도 선택되지 않는다
        env.exitAuxiliaryScreen()
        check("보조: 창 이탈 시 창 전용 선택 초기화",
              !env.showAuxiliaryScreen && env.auxiliarySelection.isEmpty)

        env.selectPropertyType(.opening)
        env.forceSelectMode = true
        env.selection.clear()
        let doorEdge = LocalPoint(firstDoor.boundingBox.midX, firstDoor.boundingBox.midY)
        env.handleCanvasClick(at: doorEdge, tolerance: 6)
        check("보조: 제외 개체는 태깅 선택 불가", env.selection.isEmpty,
              "선택 \(env.selection.selected.count)개")
        check("보조: 제외 개체는 비활성 렌더", env.renderState(for: firstDoor).isDisabled)

        // 지정 해제하면 다시 선택된다 — 되돌릴 수 있어야 실수해도 안전하다
        env.auxiliary.include([firstDoor.id])
        env.handleCanvasClick(at: doorEdge, tolerance: 6)
        check("보조: 제외 풀면 다시 선택 가능", env.selection.selected.contains(firstDoor.id))

        env.selection.clear()
        env.auxiliary.clear()
        check("보조: 전체 해제", env.excludedCount == 0)

        // 11. 전체 선택 해제 확인 팝업 (명세 디버깅 7번)
        env.selection.clear()
        env.requestClearSelection(.main)
        check("해제: 선택 없으면 팝업 안 뜸", env.pendingClearSelection == nil,
              "빈 선택에 확인을 물으면 눌러야 할 버튼만 늘어난다")

        env.forceSelectMode = true
        env.selection.toggle(firstDoor.id)
        env.requestClearSelection(.main)
        check("해제: 선택 있으면 팝업", env.pendingClearSelection != nil)
        check("해제: 팝업 문구용 개수", env.selectionCount(.main) == 1)

        env.cancelClearSelection()
        check("해제: '아니오'면 선택 유지",
              env.pendingClearSelection == nil && env.selection.selected.contains(firstDoor.id))

        env.requestClearSelection(.main)
        env.confirmClearSelection()
        check("해제: '예'면 전체 해제",
              env.selection.isEmpty && env.pendingClearSelection == nil)

        // 보조 개체 창의 선택도 같은 경로를 탄다 — 메인 선택은 건드리지 않는다
        env.selection.toggle(firstDoor.id)
        env.auxiliarySelection = Set(doors.prefix(3).map(\.id))
        env.requestClearSelection(.auxiliary)
        check("해제: 보조 창 개수", env.selectionCount(.auxiliary) == 3)
        env.confirmClearSelection()
        check("해제: 보조 창만 비우고 메인 선택은 유지",
              env.auxiliarySelection.isEmpty && env.selection.selected.contains(firstDoor.id))
        env.selection.clear()

        // 12. 실행취소·다시실행 (명세 디버깅 8번)
        env.undoStack.clear()
        env.auxiliary.clear()
        env.selection.clear()
        env.selectPropertyType(.unit)
        env.undoStack.clear()
        check("취소: 초기엔 되돌릴 것 없음", !env.canUndo && !env.canRedo)

        // feature 저장 → 되돌리기 → 다시실행. 얽힌 상태가 통째로 왕복하는지 본다.
        // 앞 절에서 이미 소유권이 걸린 개체를 쓰면 저장 자체가 거부되어 시험이 성립하지 않는다.
        env.forceSelectMode = true
        guard let freeObj = env.document?.objects.first(where: {
            env.ownership.ownerOf($0.id) == nil && !env.auxiliary.isExcluded($0.id)
        }) else { print("[FAIL] 소유되지 않은 개체 없음"); exit(1) }
        env.selection.selected = [freeObj.id]
        let beforeSave = env.features.count(ofType: .unit)
        env.createFeature()
        check("취소: 저장 후 스택에 쌓임", env.canUndo, env.undoStack.undoName ?? "")
        check("취소: 저장 반영", env.features.count(ofType: .unit) == beforeSave + 1)

        env.undo()
        check("취소: feature 되돌림", env.features.count(ofType: .unit) == beforeSave)
        check("취소: 소유권도 함께 되돌림",
              !env.ownership.claimedObjectIDs.contains(freeObj.id),
              "소유 \(env.ownership.claimedCount)개 — 상태 일부만 되돌아가면 조용히 깨진다")
        check("취소: 선택도 되돌림", env.selection.selected.contains(freeObj.id),
              "저장하며 비웠던 선택이 돌아와야 이어서 작업할 수 있다")
        check("취소: 다시실행 가능", env.canRedo)

        env.redo()
        check("취소: 다시실행으로 복귀", env.features.count(ofType: .unit) == beforeSave + 1)

        // 새 작업을 하면 다시실행 가지는 버려진다
        env.undo()
        check("취소: 되돌린 뒤 다시실행 대기", env.canRedo)
        env.selection.selected = [freeObj.id]
        env.createFeature()
        check("취소: 새 작업이 다시실행 가지를 버림", !env.canRedo,
              "갈라진 미래를 남겨두면 어느 쪽으로 가는지 알 수 없다")

        // 속성 입력 합치기 — 글자마다 칸이 쌓이면 스택이 쓸모없어진다
        let editFid = env.features.features(ofType: .unit)[0].id
        let depthBeforeTyping = env.undoStack.undoEntries.count
        for text in ["A", "A실", "A실 1"] {
            env.updateProperty("name", value: .string(text), in: editFid)
        }
        check("취소: 연속 입력은 한 칸으로 합침",
              env.undoStack.undoEntries.count == depthBeforeTyping + 1,
              "\(env.undoStack.undoEntries.count - depthBeforeTyping)칸 증가")
        env.undo()
        check("취소: 합친 입력은 입력 시작 전으로 되돌림",
              env.features.feature(editFid)?.properties["name"] == PropertyValue.null)

        // 아무것도 안 바꾼 명령은 칸을 남기지 않는다
        let depthBeforeNoop = env.undoStack.undoEntries.count
        env.selection.clear()
        env.createFeature()
        check("취소: 빈 명령은 칸을 안 남김",
              env.undoStack.undoEntries.count == depthBeforeNoop,
              "빈 칸이 쌓이면 cmd+z를 눌러도 화면이 안 바뀌는 것처럼 보인다")

        // 보조 개체 제외도 되돌아간다
        env.auxiliary.clear()
        env.undoStack.clear()
        env.auxiliarySelection = [firstDoor.id]
        env.markSelectedAsAuxiliary()
        check("취소: 보조 지정 반영", env.excludedCount == 1)
        env.undo()
        check("취소: 보조 지정 되돌림", env.excludedCount == 0)

        // 그룹 해제로 폐기된 UUID도 되살아나야 스펙의 "id 유지"가 안 깨진다
        env.undoStack.clear()
        env.selection.selected = [freeObj.id]
        env.createFeature()
        let ungroupFid = env.features.features(ofType: .unit).last!.id
        let issued = env.ids.id(for: ungroupFid)
        env.ungroup(ungroupFid)
        check("취소: 해제 시 UUID 폐기", env.ids.peek(ungroupFid) == nil)
        env.undo()
        check("취소: 되돌리면 UUID도 복귀", env.ids.peek(ungroupFid) == issued,
              "폐기 대장이 안 돌아오면 실행취소 한 번에 id 유지 요건이 깨진다")

        // 상한
        check("취소: 스택 상한", UndoStack.limit == 60, "\(UndoStack.limit)칸")

        env.undoStack.clear()
        env.selection.clear()
        env.auxiliary.clear()

        // 회전 — 90° 단위 순환
        env.canvasRotation = 0
        env.rotateCanvas(1);  check("회전 +90", env.canvasRotation == 1)
        env.rotateCanvas(1);  env.rotateCanvas(1); env.rotateCanvas(1)
        check("회전 360° 복귀", env.canvasRotation == 0)
        env.rotateCanvas(-1); check("회전 -90 순환", env.canvasRotation == 3)
        env.canvasRotation = 0

        // 회전 — 층마다 따로 기억한다(2026-10-19). 한 층을 돌려도 다른 층은 그대로다.
        let savedFloor = env.routingFloorID
        let floorA = UUID(), floorB = UUID()
        env.routingFloorID = floorA; env.rotateCanvas(1)
        env.routingFloorID = floorB
        check("회전: 다른 층은 돌지 않는다", env.canvasRotation == 0, "\(env.canvasRotation)")
        env.rotateCanvas(-1)
        env.routingFloorID = floorA
        check("회전: 층으로 돌아오면 그 층 회전이 남아 있다", env.canvasRotation == 1, "\(env.canvasRotation)")
        env.routingFloorID = floorB
        check("회전: 층마다 따로 돈다", env.canvasRotation == 3, "\(env.canvasRotation)")
        env.canvasRotationByLevel = [:]
        env.routingFloorID = savedFloor

        // 배경 대비 — 밝은/어두운 배경 어느 쪽에서도 캔버스 요소가 묻히지 않아야 한다.
        for bg in CanvasBackground.allCases {
            let name = bg == .light ? "밝은 배경" : "어두운 배경"

            // 극단 색(검정·흰색)과 회색이 모두 배경과 구분되는지
            let samples: [(String, RGBAColor)] = [
                ("검정 선", RGBAColor(r: 0, g: 0, b: 0, a: 1)),
                ("흰색 선", RGBAColor(r: 1, g: 1, b: 1, a: 1)),
                ("연회색 선", RGBAColor(r: 0.9, g: 0.9, b: 0.9, a: 1)),
                ("진회색 선", RGBAColor(r: 0.15, g: 0.15, b: 0.15, a: 1))
            ]
            for (label, c) in samples {
                let lum = luminance(of: bg.resolve(c))
                check("\(name): \(label) 대비", abs(lum - bg.luminance) >= 0.25,
                      String(format: "휘도차 %.2f", abs(lum - bg.luminance)))
            }

            // 배경에 얹는 나머지 요소들
            let elements: [(String, Color)] = [
                ("기본 선", bg.defaultStroke),
                ("비활성 개체", bg.disabledStroke),
                ("선택 강조", bg.selection),
                ("Anchor 마커", bg.marker(.normal)),
                ("이상치 마커", bg.marker(.outlier)),
                ("대기 마커", bg.marker(.pending)),
                ("display point", bg.marker(.displayPoint))
            ]
            for (label, color) in elements {
                let lum = luminance(of: color)
                check("\(name): \(label) 대비", abs(lum - bg.luminance) >= 0.2,
                      String(format: "휘도차 %.2f", abs(lum - bg.luminance)))
            }

            // 겹침 윤곽은 사용자가 색을 고정(#FF00D9)해서 반전 규칙을 태울 수 없다.
            // 어두운 배경에서는 휘도차가 다른 요소만큼 안 나오므로, 대신 채도로 구분된다는 것을 확인한다.
            let ov = NSColor(bg.overlapOutline).usingColorSpace(.sRGB) ?? .black
            check("\(name): 겹침 윤곽 색 고정",
                  abs(Double(ov.redComponent) - 1) < 0.01 && Double(ov.greenComponent) < 0.01
                  && abs(Double(ov.blueComponent) - 0.851) < 0.01, "#FF00D9")
            check("\(name): 겹침 윤곽 채도", Double(ov.saturationComponent) >= 0.9,
                  String(format: "채도 %.2f — 무채색 도면 선과 색상으로 구분된다",
                         Double(ov.saturationComponent)))

            // 고스트는 명세상 20% opacity라, 합성 후에도 구분되는지 따로 본다.
            let ghost = luminance(of: bg.ghostStroke) * 0.2 + bg.luminance * 0.8
            check("\(name): 고스트 레이어 대비", abs(ghost - bg.luminance) >= 0.09,
                  String(format: "합성 휘도차 %.3f", abs(ghost - bg.luminance)))
        }

        // 27. 곡선 창에서는 소유권이 선택을 막지 않는다 (명세 3-3-3)
        let cEnv = AppEnvironment()
        cEnv.openSample()
        cEnv.declareOpeningComplete()
        cEnv.selectPropertyType(.unit)
        guard let cDoc = cEnv.document,
              let curvedObj = cDoc.objects.first(where: { $0.isCurved }) else {
            print("[FAIL] 곡선 개체 없음"); exit(1)
        }

        // 곡선 개체를 feature로 저장해 소유권을 걸어 둔다.
        cEnv.selection.selected = [curvedObj.id]
        cEnv.createFeature()
        check("곡선창: 저장돼 소유권이 걸린 상태",
              cEnv.ownership.ownerOf(curvedObj.id) != nil)

        // 일반 모드에서는 소유권 때문에 다시 고를 수 없다.
        cEnv.selection.clear()
        cEnv.forceSelectMode = true
        guard let curvedCenter = curvedObj.geometry.subpaths.first?.start else {
            print("[FAIL] 곡선 개체에 점이 없음"); exit(1)
        }
        // **경계 상자의 중심이 아니라 선 위의 점**을 쓴다. 원·타원은 중심이 선에서 가장 먼 자리라
        // 히트테스트가 잡지 못한다 — 시험이 실패하면 구현이 아니라 이 좌표를 먼저 의심해야 한다.
        cEnv.handleCanvasClick(at: curvedCenter, tolerance: 6)
        let pickedNormally = cEnv.selection.selected.contains(curvedObj.id)

        // 곡선 창에서는 고를 수 있어야 한다 — 선분화 해제가 막히면 안 된다.
        cEnv.setMode(.curvedOnly(showSegmentedOnly: false))
        cEnv.handleCanvasClick(at: curvedCenter, tolerance: 6)
        check("곡선창: 소유권이 걸려도 고를 수 있다",
              cEnv.selection.selected.contains(curvedObj.id),
              "일반 모드에서는 \(pickedNormally ? "고를 수 있었다" : "막혔다") — 이 창은 선분화 대상 지정이지 태깅이 아니다")

        // 고른 상태에서 선분화·해제가 된다.
        cEnv.segmentizeSelection()
        check("곡선창: 저장된 개체도 선분화된다",
              cEnv.segmentation.isSegmented(curvedObj.id))
        cEnv.desegmentize([curvedObj.id])
        check("곡선창: 선분화 해제도 된다(명세 3-3-3)",
              !cEnv.segmentation.isSegmented(curvedObj.id))

        // 창을 나가면 선택이 비워진다 — 소유권을 무시하고 고른 것을 들고 나가면 안 된다.
        cEnv.selection.selected = [curvedObj.id]
        cEnv.setMode(.idle)
        check("곡선창: 나가면 선택이 비워진다", cEnv.selection.isEmpty,
              "남의 개체를 고른 채 'Feature로 저장'을 누를 수 있게 된다")

        // 26. geometry 불일치 판정이 정상 도면을 막지 않는가
        // 이전에는 '닫힌 subpath가 하나도 없으면 경고'였고, 그 경고가 내보내기 차단으로 이어졌다.
        // 벽 선분으로 그린 방은 닫힌 subpath가 없으므로 정상 작업이 통째로 막혔다.
        let lines = doc.objects.filter { $0.sourceElement == "line" }
        var lineOnlyUnit = FeatureGroup(featureType: .unit, serialNumber: "unit-901",
                                        memberIDs: Set(lines.prefix(4).map(\.id)))
        check("불일치: 선분으로 그린 방을 막지 않는다",
              GeometryClassifier.mismatchWarning(lineOnlyUnit, document: doc) == nil,
              "닫힌 subpath가 없어도 링은 닫힐 수 있다")

        check("불일치: LineString에 닫힌 도형은 여전히 잡는다",
              GeometryClassifier.mismatchWarning(
                  FeatureGroup(featureType: .opening, serialNumber: "opening-901",
                               memberIDs: [room.id]),
                  document: doc) != nil,
              "geometry 종류가 실제로 어긋나는 경우다")

        lineOnlyUnit.memberIDs = []
        check("불일치: 빈 feature는 판정하지 않는다",
              GeometryClassifier.mismatchWarning(lineOnlyUnit, document: doc) == nil)

        // 열린 링은 차단이 아니라 경고로 남는다(명세 7-4의 차단 조건에 링 열림은 없다).
        let ringWarnEnv = AppEnvironment()
        ringWarnEnv.openSample()
        ringWarnEnv.declareOpeningComplete()
        ringWarnEnv.selectPropertyType(.unit)
        if let wLine = ringWarnEnv.document?.objects.first(where: { $0.sourceElement == "line" }) {
            ringWarnEnv.selection.selected = [wLine.id]
            ringWarnEnv.createFeature()
            let openList = ringWarnEnv.openRingFeatures(type: .unit)
            check("불일치: 열린 링은 목록으로 알린다", !openList.isEmpty,
                  "선분 하나로는 링이 닫히지 않는다")
            check("불일치: 다른 type은 섞이지 않는다",
                  ringWarnEnv.openRingFeatures(type: .opening).isEmpty,
                  "내보내기는 한 type씩 하므로 무관한 경고가 섞이면 안 된다")

            let blockers2 = ExportValidator(document: ringWarnEnv.document!,
                                            features: ringWarnEnv.features.features,
                                            anchors: ringWarnEnv.anchors,
                                            georeferencer: ringWarnEnv.georeferencer,
                                            segmentation: ringWarnEnv.segmentation,
                                            borrow: ringWarnEnv.borrow).validate(type: .unit)
            check("불일치: 링이 열려도 geometry 사유로 차단하지 않는다",
                  !blockers2.contains { if case .geometryMismatch = $0 { return true }; return false },
                  "차단 사유는 Anchor·좌표 미확보뿐이다")
        }

        // 25. 빌려온 개체의 화면 표시 (명세 10-2-2)
        let vizEnv = AppEnvironment()
        vizEnv.openSample()
        vizEnv.selectPropertyType(.opening)
        guard let vzDoc = vizEnv.document,
              let vzDoor = vzDoc.objects.first(where: { $0.sourceElement == "line" }),
              let vzRect = vzDoc.objects.first(where: { $0.sourceElement == "rect" }) else {
            print("[FAIL] 표시 시험용 개체 없음"); exit(1)
        }
        vizEnv.selection.selected = [vzDoor.id]
        vizEnv.createFeature()
        vizEnv.declareOpeningComplete()
        vizEnv.selectPropertyType(.unit)

        check("표시: 고르기 전에는 빌린 것이 아니다",
              !vizEnv.renderState(for: vzDoor).isBorrowed)

        vizEnv.selection.selected = [vzRect.id, vzDoor.id]
        check("표시: 고른 순간부터 빌린 것으로 보인다",
              vizEnv.renderState(for: vzDoor).isBorrowed,
              "저장하면 빌리게 될 상태라 미리 구분해 보여준다")
        check("표시: 내 개체는 빌린 것이 아니다",
              !vizEnv.renderState(for: vzRect).isBorrowed)

        vizEnv.createFeature()
        check("표시: 저장 뒤에도 빌린 것으로 보인다",
              vizEnv.renderState(for: vzDoor).isBorrowed,
              "저장 직후 그 feature가 펼쳐지므로 계속 구분된다")

        // 다른 feature를 펼치면 그 feature 기준으로 바뀐다.
        vizEnv.expandedFeature = nil
        vizEnv.selection.clear()
        check("표시: 관계없는 화면에서는 표시하지 않는다",
              !vizEnv.renderState(for: vzDoor).isBorrowed,
              "빌림은 특정 feature와의 관계지 개체의 속성이 아니다")

        // 24. 빌려온 opening이 좌표에 반영되는가 (명세 10-3-1, 10-5-2)
        // 이것이 없으면 문을 빌려도 열린 폴리곤 좌표가 그대로 파일로 나가, 빌려주기가 무의미해진다.
        let vDoc = doc
        var vFeature = FeatureGroup(featureType: .unit, serialNumber: "unit-900",
                                    memberIDs: [])
        // ㄷ자로 벽 3면만 있는 방 — 한쪽이 문 자리로 뚫려 있다.
        let wallIDs = Set(vDoc.objects.filter { $0.sourceElement == "line" }.prefix(2).map(\.id))
        vFeature.memberIDs = wallIDs
        let borrowedDoor = vDoc.objects.first { $0.sourceElement == "line" && !wallIDs.contains($0.id) }

        if let bd = borrowedDoor {
            let without = VertexExtractor.vertices(for: vFeature, document: vDoc,
                                                   segmentation: seg, kind: .polygon)
            let with = VertexExtractor.vertices(for: vFeature, document: vDoc,
                                                segmentation: seg, kind: .polygon,
                                                borrowed: [bd.id])
            check("좌표: 빌려온 문이 링에 들어간다", with.count > without.count,
                  "빌리기 전 \(without.count)개 → 빌린 뒤 \(with.count)개")

            // LineString·Point에는 남의 문을 넣지 않는다.
            let line = VertexExtractor.vertices(for: vFeature, document: vDoc,
                                                segmentation: seg, kind: .lineString,
                                                borrowed: [bd.id])
            let lineNo = VertexExtractor.vertices(for: vFeature, document: vDoc,
                                                  segmentation: seg, kind: .lineString)
            check("좌표: LineString에는 안 넣는다", line == lineNo,
                  "선이 엉뚱한 데로 뻗는다")
            check("좌표: 폴리곤 계열만 빌린다",
                  GeoJSONGeometryKind.polygon.usesBorrowedOpenings
                  && GeoJSONGeometryKind.multiPolygon.usesBorrowedOpenings
                  && !GeoJSONGeometryKind.lineString.usesBorrowedOpenings
                  && !GeoJSONGeometryKind.point.usesBorrowedOpenings)
        }

        // 내보내기 계층까지 이어지는가 — 화면 좌표 표와 파일이 같아야 한다.
        let xEnv = AppEnvironment()
        xEnv.openSample()
        xEnv.selectPropertyType(.opening)
        guard let xDoc = xEnv.document,
              let xDoor = xDoc.objects.first(where: { $0.sourceElement == "line" }),
              let xRect = xDoc.objects.first(where: { $0.sourceElement == "rect" }) else {
            print("[FAIL] 내보내기 시험용 개체 없음"); exit(1)
        }
        xEnv.selection.selected = [xDoor.id]
        xEnv.createFeature()
        xEnv.declareOpeningComplete()
        xEnv.selectPropertyType(.unit)
        xEnv.selection.selected = [xRect.id, xDoor.id]
        xEnv.createFeature()
        xEnv.anchors.pairs = pairs

        if let xUnit = xEnv.features.features(ofType: .unit).first {
            let rows = xEnv.vertexRows(for: xUnit.id)
            var assigner2 = IDAssigner()
            let exporter2 = GeoJSONExporter(document: xDoc, segmentation: xEnv.segmentation,
                                            georeferencer: xEnv.georeferencer,
                                            borrow: xEnv.borrow)
            let fc = exporter2.buildFeatureCollection(type: .unit,
                                                      features: xEnv.features.features,
                                                      ids: &assigner2, serialToUUID: [:])
            let feats = (fc["features"] as? [[String: Any]]) ?? []
            let coordCount = feats.compactMap { f -> Int? in
                guard let g = f["geometry"] as? [String: Any],
                      let c = g["coordinates"] as? [[[Double]]] else { return nil }
                return c.first?.count
            }.first
            check("좌표: 화면 표와 파일이 같은 수", coordCount != nil && coordCount! >= rows.count,
                  "표 \(rows.count)개 / 파일 \(coordCount.map(String.init) ?? "없음")개 (링은 첫 점이 끝에 반복된다)")
        }

        // 23. opening 반납 (명세 10-2-3)
        // 그룹 해제와 다른 기능이다 — 해제는 feature를 없애고, 반납은 문만 돌려준다.
        let rEnv = AppEnvironment()
        rEnv.openSample()
        rEnv.selectPropertyType(.opening)
        guard let rDoc = rEnv.document,
              let rDoor = rDoc.objects.first(where: { $0.sourceElement == "line" }),
              let rRect = rDoc.objects.first(where: { $0.sourceElement == "rect" }) else {
            print("[FAIL] 반납 시험용 개체 없음"); exit(1)
        }
        rEnv.selection.selected = [rDoor.id]
        rEnv.createFeature()
        let openingF = rEnv.features.features(ofType: .opening).first
        rEnv.declareOpeningComplete()
        rEnv.selectPropertyType(.unit)
        rEnv.selection.selected = [rRect.id, rDoor.id]
        rEnv.createFeature()
        guard let rUnit = rEnv.features.features(ofType: .unit).first else {
            print("[FAIL] unit 없음"); exit(1)
        }
        check("반납: 빌린 상태", rEnv.borrow.objects(borrowedBy: rUnit.id) == [rDoor.id])

        rEnv.returnBorrowedOpenings(from: rUnit.id)
        check("반납: 문을 돌려준다", rEnv.borrow.objects(borrowedBy: rUnit.id).isEmpty)
        check("반납: feature는 살아남는다",
              rEnv.features.feature(rUnit.id) != nil
              && rEnv.ownership.ownerOf(rRect.id) == rUnit.id,
              "그룹 해제와 달리 방은 그대로 둔다")
        check("반납: opening feature도 그대로",
              rEnv.features.feature(openingF?.id ?? UUID()) != nil,
              "빌려준 쪽은 애초에 소유를 넘긴 적이 없다")

        rEnv.undo()
        check("반납: 되돌리면 다시 빌린 상태",
              rEnv.borrow.objects(borrowedBy: rUnit.id) == [rDoor.id])

        // 22. 프로젝트 파일 왕복 (명세 7-3-2, 9-7)
        // 이 시험이 지키는 것은 IMDF 스펙의 "id는 배송 간 유지" 요건이다.
        let pEnv = AppEnvironment()
        pEnv.openSample()
        pEnv.selectPropertyType(.opening)
        guard let pDoc = pEnv.document,
              let pDoor = pDoc.objects.first(where: { $0.sourceElement == "line" }),
              let pRect = pDoc.objects.first(where: { $0.sourceElement == "rect" }) else {
            print("[FAIL] 프로젝트 시험용 개체 없음"); exit(1)
        }
        pEnv.selection.selected = [pDoor.id]
        pEnv.createFeature()
        pEnv.declareOpeningComplete()
        pEnv.selectPropertyType(.unit)
        pEnv.selection.selected = [pRect.id, pDoor.id]
        pEnv.createFeature()
        pEnv.anchors.pairs = pairs
        pEnv.auxiliary.exclude([pDoc.objects[3].id])

        guard let unitF = pEnv.features.features(ofType: .unit).first else {
            print("[FAIL] unit 없음"); exit(1)
        }
        // 한 번 내보낸 셈 치고 UUID를 발급받고, 대장에 실제 기록됐는지 확인한다.
        let issuedUUID = pEnv.ids.id(for: unitF.id)
        guard let uuidBefore = pEnv.ids.peek(unitF.id), uuidBefore == issuedUUID else {
            print("[FAIL] 프로젝트: 발급 UUID가 대장에 없음"); exit(1)
        }

        let saved = ProjectFile(sourceName: pDoc.sourceName, svg: SampleFloorplan.svg,
                                features: pEnv.features, ownership: pEnv.ownership,
                                segmentation: pEnv.segmentation, auxiliary: pEnv.auxiliary,
                                anchors: pEnv.anchors, serials: pEnv.serials, ids: pEnv.ids,
                                openingGate: pEnv.openingGate, borrow: pEnv.borrow)
        guard let blob = try? saved.encoded(),
              let reopened = try? ProjectFile.decoded(from: blob) else {
            print("[FAIL] 프로젝트 파일 직렬화 실패"); exit(1)
        }

        check("프로젝트: feature가 그대로", reopened.features == pEnv.features,
              "\(reopened.features.features.count)개")
        check("프로젝트: 소유권이 그대로", reopened.ownership == pEnv.ownership)
        check("프로젝트: Anchor가 그대로", reopened.anchors == pEnv.anchors,
              "명세 9-7 — 도면 좌표와 위경도를 함께 갖는 유일한 데이터")
        check("프로젝트: 보조 개체 제외가 그대로", reopened.auxiliary == pEnv.auxiliary)
        check("프로젝트: 대여 장부가 그대로", reopened.borrow == pEnv.borrow,
              "안 담기면 다시 열었을 때 폴리곤이 열린 채로 뜬다")
        check("프로젝트: opening 게이트가 그대로", reopened.openingGate == pEnv.openingGate)
        check("프로젝트: 일련번호 대장이 그대로", reopened.serials == pEnv.serials,
              "안 담기면 다시 열고 저장할 때 unit-001부터 다시 매겨져 번호가 겹친다")

        guard let uuidAfter = reopened.ids.peek(unitF.id) else {
            print("[FAIL] 프로젝트: 재열기 후 UUID 기록이 없음"); exit(1)
        }
        check("프로젝트: UUID가 유지된다",
              uuidAfter == uuidBefore,
              "IMDF 스펙 MUST — 다시 내보내도 같은 id여야 한다")

        var retiredIDs = pEnv.ids
        retiredIDs.retire(unitF.id)
        let withRetired = ProjectFile(sourceName: "x", svg: "y", features: pEnv.features,
                                      ownership: pEnv.ownership, segmentation: pEnv.segmentation,
                                      auxiliary: pEnv.auxiliary, anchors: pEnv.anchors,
                                      serials: pEnv.serials, ids: retiredIDs,
                                      openingGate: pEnv.openingGate, borrow: pEnv.borrow)
        if let d = try? withRetired.encoded(), let r = try? ProjectFile.decoded(from: d) {
            check("프로젝트: 폐기 UUID 대장도 유지된다", r.ids == retiredIDs,
                  "IMDF 스펙 MUST NOT — 버린 id를 다른 feature가 물려받으면 안 된다")
        }

        check("프로젝트: SVG 원본을 함께 담는다", reopened.svg == SampleFloorplan.svg,
              "경로만 참조하면 도면이 옮겨졌을 때 작업 전체가 열리지 않는다")
        check("프로젝트: 버전이 기록된다", reopened.version == ProjectFile.currentVersion)

        var future = saved
        future.version = ProjectFile.currentVersion + 1
        if let d = try? future.encoded() {
            check("프로젝트: 앞선 버전은 거부한다",
                  (try? ProjectFile.decoded(from: d)) == nil,
                  "모르는 필드를 버린 채 저장하면 작업이 소리 없이 사라진다")
        }

        // 21. 하위 기본 레이어는 작업 대상이 아니다 (명세 2-3)
        let ghostEnv2 = AppEnvironment()
        ghostEnv2.openSample()
        guard let ghostL = ghostEnv2.layers.layers.first(where: {
            if case .baseGhost = $0.kind { return true }; return false
        }), let topL = ghostEnv2.layers.layers.first(where: {
            if case .baseTop = $0.kind { return true }; return false
        }) else { print("[FAIL] 기본 레이어 없음"); exit(1) }

        let beforeActive = ghostEnv2.layers.activeLayerID
        check("고스트: 활성으로 만들 수 없다",
              ghostEnv2.layers.activate(ghostL.id) == false
              && ghostEnv2.layers.activeLayerID == beforeActive,
              "활성이 되면 그 위에서 개체를 선택·저장할 수 있게 된다")
        check("고스트: 상위 기본 레이어는 열린다",
              ghostEnv2.layers.activate(topL.id) && ghostEnv2.layers.activeLayerID == topL.id)
        check("고스트: 액션 불가 표시", !ghostL.allowsObjectActions && topL.allowsObjectActions)
        check("고스트: 숨길 수 있다", ghostL.isHidable,
              "명세 2-3 뒤집음(2026-08-25 뷰 디버깅 15번) — 닫기(isClosable)만 계속 막는다")
        check("고스트: 닫을 수는 없다", !ghostL.isClosable)
        check("고스트: 50% 불투명도", abs(ghostL.baseOpacity - 0.5) < 1e-9,
              "명세 2-3의 수치는 EditorLayer 한 곳에만 둔다 (2026-08-25 사노 요청으로 20%→50%)")

        // 20. 링 닫힘 검증 (명세 10-4)
        // 정확히 맞물린 사각형 — 닫힌다.
        let closedRect = [
            LineSegment(start: LocalPoint(0, 0), end: LocalPoint(100, 0)),
            LineSegment(start: LocalPoint(100, 0), end: LocalPoint(100, 100)),
            LineSegment(start: LocalPoint(100, 100), end: LocalPoint(0, 100)),
            LineSegment(start: LocalPoint(0, 100), end: LocalPoint(0, 0)),
        ]
        check("링: 맞물린 사각형은 닫힌다",
              RingClosureValidator.validate(segments: closedRect, tolerance: 0.5).isClosed)

        // 한 변을 떼어내 문 자리를 만든다 — 열린다.
        var openRect = closedRect
        openRect.removeLast()
        let openResult = RingClosureValidator.validate(segments: openRect, tolerance: 0.5)
        check("링: 변이 빠지면 열린다", !openResult.isClosed,
              "벌어진 곳 \(openResult.gaps.count)곳")
        check("링: 벌어진 자리를 좌표로 짚는다",
              openResult.gaps.contains { $0.point.distance(to: LocalPoint(0, 0)) < 0.001 }
              && openResult.gaps.contains { $0.point.distance(to: LocalPoint(0, 100)) < 0.001 },
              "그 자리를 캔버스에 표시해야 하므로 위치가 정확해야 한다")

        // 문을 끼워 넣으면 다시 닫힌다 — 빌려주기의 목적 그 자체.
        let withDoor = openRect + [LineSegment(start: LocalPoint(0, 100), end: LocalPoint(0, 0))]
        check("링: 문을 빌려 끼우면 닫힌다",
              RingClosureValidator.validate(segments: withDoor, tolerance: 0.5).isClosed)

        // 미세하게 벌어진 CAD 도면 — 허용 오차 안이면 붙은 것으로 본다(Door Close Buffer).
        var sloppy = closedRect
        sloppy[3] = LineSegment(start: LocalPoint(0, 100), end: LocalPoint(0.3, 0.3))
        check("링: 오차 안의 틈은 붙은 것으로 본다",
              RingClosureValidator.validate(segments: sloppy, tolerance: 0.5).isClosed,
              "눈으로 붙어 보이는 CAD 도면을 매번 실패로 처리하면 쓸 수 없다")
        check("링: 오차를 넘는 틈은 잡는다",
              !RingClosureValidator.validate(segments: sloppy, tolerance: 0.1).isClosed,
              "같은 도면도 기준을 좁히면 걸린다")

        check("링: 변이 3개 미만이면 폴리곤이 아니다",
              !RingClosureValidator.validate(segments: Array(closedRect.prefix(2)),
                                             tolerance: 0.5).isClosed)

        // 같은 자리에서 두 번 잡힌 틈은 한 곳으로 줄인다.
        check("링: 같은 자리 틈은 하나로 센다",
              openResult.gaps.count == 2,
              "끝점 두 개가 각각 잡히므로 줄이지 않으면 네 곳으로 보인다")

        // 앱 계층 — 빌려온 opening을 넣고 판정하는가.
        let ringEnv = AppEnvironment()
        ringEnv.openSample()
        ringEnv.declareOpeningComplete()
        ringEnv.selectPropertyType(.amenity)
        if let amenityObj = ringEnv.document?.objects.first {
            ringEnv.selection.selected = [amenityObj.id]
            ringEnv.createFeature()
            if let af = ringEnv.features.features(ofType: .amenity).first {
                check("링: 폴리곤이 아닌 type은 판정하지 않는다",
                      ringEnv.ringClosure(of: af) == nil,
                      "amenity는 점 하나라 닫을 링이 없다")
            }
        }

        // 19. 문 빌려주기 (명세 10-2·10-3)
        let bEnv = AppEnvironment()
        bEnv.openSample()
        guard let bDoc = bEnv.document,
              let door = bDoc.objects.first(where: { $0.sourceElement == "line" }),
              let wall = bDoc.objects.first(where: { $0.sourceElement == "rect" }) else {
            print("[FAIL] 빌려주기 시험용 개체 없음"); exit(1)
        }

        // 문을 opening으로 먼저 저장한다.
        bEnv.selectPropertyType(.opening)
        bEnv.selection.selected = [door.id]
        bEnv.createFeature()
        guard let openingFeature = bEnv.features.features(ofType: .opening).first else {
            print("[FAIL] opening feature 생성 실패"); exit(1)
        }
        check("빌려주기: 문이 opening 소유", bEnv.ownership.ownerOf(door.id) == openingFeature.id)

        bEnv.declareOpeningComplete()
        bEnv.selectPropertyType(.unit)
        check("빌려주기: unit은 빌릴 수 있다", bEnv.canBorrow(door.id),
              "geometry가 Polygon인 type만 빌린다(명세 10-2-4)")

        bEnv.selectPropertyType(.amenity)
        check("빌려주기: amenity는 못 빌린다", !bEnv.canBorrow(door.id),
              "Point라 닫을 폴리곤이 없다")

        bEnv.selectPropertyType(.unit)
        bEnv.selection.selected = [wall.id, door.id]
        let claimedBefore = bEnv.claimedCount
        bEnv.createFeature()
        guard let unitFeature = bEnv.features.features(ofType: .unit).first else {
            print("[FAIL] unit feature 생성 실패"); exit(1)
        }
        check("빌려주기: 대여로 기록된다",
              bEnv.borrow.objects(borrowedBy: unitFeature.id) == [door.id])
        check("빌려주기: 구성원에는 안 들어간다", !unitFeature.memberIDs.contains(door.id),
              "명세 10-5-2 — 파일에 '이 unit이 저 opening을 빌렸다'를 적을 필드가 없다")
        check("빌려주기: 소유권은 opening에 남는다",
              bEnv.ownership.ownerOf(door.id) == openingFeature.id,
              "명세 10-3-2 — 소유권은 이동하지 않는다")
        check("빌려주기: 진행률에 중복 계산 안 됨",
              bEnv.claimedCount == claimedBefore + 1,
              "늘어난 것은 벽 1개뿐 — 문은 opening 몫으로 이미 세었다(명세 10-3-3)")
        check("빌려주기: 빌린 쪽을 되짚을 수 있다",
              bEnv.borrow.borrowers(of: door.id) == [unitFeature.id],
              "휴지통 경고(명세 10-4-4)가 이 목록을 쓴다")

        // 하나의 문을 둘 이상이 빌린다 — 방 A·B 사이 문(명세 10-2-5)
        if let wall2 = bDoc.objects.first(where: {
            $0.sourceElement == "rect" && $0.id != wall.id && bEnv.ownership.ownerOf($0.id) == nil
        }) {
            bEnv.selection.selected = [wall2.id, door.id]
            bEnv.createFeature()
            check("빌려주기: 여러 feature가 같은 문을 빌린다",
                  bEnv.borrow.borrowers(of: door.id).count == 2,
                  "대여는 소유와 달리 배타적이지 않다")
        }

        // 되돌리기와 반납
        let borrowersBeforeUndo = bEnv.borrow.borrowers(of: door.id).count
        bEnv.undo()
        check("빌려주기: 대여도 되돌아간다",
              bEnv.borrow.borrowers(of: door.id).count == borrowersBeforeUndo - 1,
              "안 돌아오면 실행취소 뒤 폴리곤이 열린 채 남는다")

        bEnv.ungroup(unitFeature.id)
        check("빌려주기: 빌린 쪽이 사라지면 반납된다",
              !bEnv.borrow.borrowers(of: door.id).contains(unitFeature.id),
              "없는 feature가 붙잡고 있으면 경고가 유령 일련번호를 띄운다")
        check("빌려주기: 반납해도 opening은 남는다",
              bEnv.ownership.ownerOf(door.id) == openingFeature.id,
              "명세 10-3-3 — unit을 지워도 opening feature는 남는다")

        // opening만 골라 저장하는 것은 막는다.
        bEnv.selectPropertyType(.unit)
        bEnv.selection.selected = [door.id]
        let countBefore = bEnv.features.features(ofType: .unit).count
        bEnv.createFeature()
        check("빌려주기: 빌린 것만으로는 저장 불가",
              bEnv.features.features(ofType: .unit).count == countBefore,
              "아무것도 소유하지 않는 빈 feature가 생긴다")

        // 게이트 되돌리기 (명세 10-1-4)
        bEnv.reopenOpeningTagging()
        check("게이트: 다시 열면 잠긴다", !bEnv.openingGate.allowsOtherTypes)
        check("게이트: 다시 열어도 기존 feature는 남는다",
              !bEnv.features.features(ofType: .opening).isEmpty,
              "명세 10-1-4 — 빠뜨린 문을 추가하러 돌아가는 것이지 되돌리는 것이 아니다")

        // 18. 속성 필터 레이어 (명세 2항)
        // 자료구조(`extraObjectIDs`·`addObjects`)는 있었지만 렌더링과 UI가 그것을 전혀 보지 않아
        // 레이어가 목록에 이름만 생기던 것을 이었다.
        let filterEnv = AppEnvironment()
        filterEnv.openSample()
        guard let fDoc = filterEnv.document,
              let sampleDoor = fDoc.objects.first(where: { $0.sourceElement == "line" }),
              let offStyle = fDoc.objects.first(where: {
                  $0.style.attributeKey != sampleDoor.style.attributeKey
              }) else { print("[FAIL] 속성 필터 시험용 개체 없음"); exit(1) }

        let doorKey = sampleDoor.style.attributeKey
        let matching = fDoc.objects.filter { $0.style.attributeKey == doorKey }
        check("필터 레이어: 기본 상태에서는 전부 보인다",
              fDoc.objects.allSatisfy { filterEnv.renderState(for: $0).isVisible })

        filterEnv.layers.addAttributeFilterLayer(key: doorKey, label: "문")
        check("필터 레이어: 같은 속성만 보인다",
              fDoc.objects.allSatisfy {
                  filterEnv.renderState(for: $0).isVisible == ($0.style.attributeKey == doorKey)
              },
              "\(matching.count)개만 남아야 한다")
        check("필터 레이어: 속성 다른 개체는 숨는다",
              !filterEnv.renderState(for: offStyle).isVisible)

        // 명세 2항 "거기에 내가 선택한 다른 벡터들도 추가 가능"
        filterEnv.selection.selected = [offStyle.id]
        filterEnv.addSelectionToActiveFilterLayer()
        check("필터 레이어: 선택 개체 직접 추가",
              filterEnv.renderState(for: offStyle).isVisible,
              "속성이 달라도 사용자가 넣었으면 보인다")
        check("필터 레이어: 추가는 필터 조건을 바꾸지 않는다",
              filterEnv.renderState(for: sampleDoor).isVisible
              && fDoc.objects.filter { filterEnv.renderState(for: $0).isVisible }.count
                 == matching.count + 1,
              "원래 걸리던 개체 + 추가한 1개")

        filterEnv.undo()
        check("필터 레이어: 개체 추가도 되돌아간다",
              !filterEnv.renderState(for: offStyle).isVisible)

        // 숨기기 — 이전에는 상태만 바뀌고 화면이 그대로였다.
        guard let activeID = filterEnv.layers.activeLayerID else { print("[FAIL] 활성 레이어 없음"); exit(1) }
        filterEnv.layers.setHidden(true, for: activeID)
        check("필터 레이어: 숨기면 개체가 사라진다",
              fDoc.objects.allSatisfy { !filterEnv.renderState(for: $0).isVisible })
        filterEnv.layers.setHidden(false, for: activeID)
        check("필터 레이어: 숨김 해제하면 돌아온다",
              filterEnv.renderState(for: sampleDoor).isVisible)

        // 레이어를 닫으면 기본 레이어로 돌아가 전부 다시 보인다.
        filterEnv.layers.close(activeID)
        check("필터 레이어: 닫으면 전부 다시 보인다",
              fDoc.objects.allSatisfy { filterEnv.renderState(for: $0).isVisible })

        // 하위 기본 레이어(고스트)는 숨길 수 있다(2026-08-25 뷰 디버깅 15번, 명세 2-3 뒤집음).
        // 닫는 것(레이어 자체를 없애는 것)은 여전히 불가능하다 — 그건 별개 규칙(`isClosable`).
        let ghostEnv = AppEnvironment()
        ghostEnv.openSample()
        if let ghost = ghostEnv.layers.layers.first(where: {
            if case .baseGhost = $0.kind { return true }; return false
        }) {
            ghostEnv.layers.setHidden(true, for: ghost.id)
            check("필터 레이어: 하위 기본 레이어를 숨길 수 있다",
                  ghostEnv.layers.layers.first { $0.id == ghost.id }?.isHidden == true,
                  "명세 2-3 뒤집음(2026-08-25) — 눈 모양 클릭으로 숨김")
            ghostEnv.layers.setHidden(false, for: ghost.id)
            check("필터 레이어: 다시 펼 수 있다",
                  ghostEnv.layers.layers.first { $0.id == ghost.id }?.isHidden == false)
            check("필터 레이어: 하위 기본 레이어는 여전히 닫을 수 없다", !ghost.isClosable)
        }

        // 17. category 열거형 — OGC IMDF 1.0.0 Categories 원문 대조 (2026-08-25)
        // 스펙에 없는 값이 드롭다운에 있으면 그대로 파일에 실려 나간다. 개수와 표본을 못박는다.
        // 개수는 src11의 절 제목("약 65" 등 근사치)이 아니라 **원문 값 목록을 직접 센 수**다.
        // 근사치를 기대값으로 쓰면 정확히 옮겨 적어도 실패한다.
        let catCounts: [(IMDFFeatureType, Int, String)] = [
            (.unit, 63, "UNIT"), (.amenity, 172, "AMENITY"), (.opening, 7, "OPENING"),
            (.section, 71, "SECTION"), (.geofence, 8, "GEOFENCE"), (.fixture, 15, "FIXTURE"),
            (.footprint, 3, "FOOTPRINT"), (.level, 9, "LEVEL"), (.building, 5, "BUILDING"),
            (.venue, 22, "VENUE"),
        ]
        for (type, expected, name) in catCounts {
            let opts = PropertySchema.categoryOptions(for: type)
            check("category: \(name) 전량", opts.count == expected,
                  "\(opts.count)개 (스펙 \(expected)종)")
            check("category: \(name) 중복 없음", Set(opts).count == opts.count)
            check("category: \(name) 정렬", opts == opts.sorted(),
                  "원문이 알파벳순이라 순서가 어긋나면 옮겨 적다 빠뜨린 것이다")
        }

        // 대조 전에 실제로 틀려 있던 값들. 다시 들어오면 여기서 잡힌다.
        check("category: SECTION에 unspecified 없음",
              !PropertySchema.categoryOptions(for: .section).contains("unspecified"))
        check("category: GEOFENCE에 unspecified 없음",
              !PropertySchema.categoryOptions(for: .geofence).contains("unspecified"))
        check("category: FIXTURE에 shelving·planter·column 없음",
              PropertySchema.categoryOptions(for: .fixture)
                  .allSatisfy { !["shelving", "planter", "column"].contains($0) },
              "column은 UNIT-CATEGORY 값이고 나머지 둘은 스펙에 없다")
        check("category: LEVEL은 복수형",
              PropertySchema.categoryOptions(for: .level).contains("arrivals")
              && !PropertySchema.categoryOptions(for: .level).contains("arrival"),
              "arrival/departure 단수형은 스펙에 없다")
        check("category: VENUE에 hospital 없음",
              !PropertySchema.categoryOptions(for: .venue).contains("hospital")
              && PropertySchema.categoryOptions(for: .venue).contains("healthcarefacility"),
              "의료시설은 healthcarefacility다")
        check("category: OCCUPANT은 자유 입력",
              PropertySchema.categoryOptions(for: .occupant).isEmpty,
              "스펙 열거값 전량 미확보 — 드롭다운으로 막으면 나머지 업종을 입력할 수 없다")

        // 16. 사이드바 리사이즈 계산 (명세 디버깅 1·13번)
        // 드래그 조작 자체는 헤드리스로 재현할 수 없으므로 방향과 한계값만 못박는다.
        let leftRange: ClosedRange<CGFloat> = 200...460
        check("리사이즈: 왼쪽은 오른쪽으로 끌면 넓어진다",
              SidebarResizeMath.width(base: 268, translation: 40, edge: .leading, range: leftRange) == 308)
        check("리사이즈: 왼쪽은 왼쪽으로 끌면 좁아진다",
              SidebarResizeMath.width(base: 268, translation: -40, edge: .leading, range: leftRange) == 228)

        let rightRange: ClosedRange<CGFloat> = 260...620
        check("리사이즈: 오른쪽은 방향이 반대",
              SidebarResizeMath.width(base: 360, translation: -40, edge: .trailing, range: rightRange) == 400,
              "핸들이 왼편에 있어 같은 드래그가 반대 결과를 낸다")
        check("리사이즈: 상한 고정",
              SidebarResizeMath.width(base: 440, translation: 999, edge: .leading, range: leftRange) == 460)
        check("리사이즈: 하한 고정",
              SidebarResizeMath.width(base: 210, translation: -999, edge: .leading, range: leftRange) == 200)

        // 기본값이 범위 밖이면 창을 열자마자 폭이 튄다.
        let widthEnv = AppEnvironment()
        check("리사이즈: 기본 폭이 범위 안",
              leftRange.contains(widthEnv.leftSidebarWidth)
              && rightRange.contains(widthEnv.rightSidebarWidth)
              && (260...560).contains(widthEnv.auxiliarySidebarWidth),
              "왼쪽 \(widthEnv.leftSidebarWidth) / 오른쪽 \(widthEnv.rightSidebarWidth) / 보조창 \(widthEnv.auxiliarySidebarWidth)")

        // 폭은 실행취소 대상이 아니다 — cmd+z가 사이드바 크기를 되돌리면 작업 이력이 묻힌다.
        widthEnv.openSample()
        widthEnv.declareOpeningComplete()
        widthEnv.leftSidebarWidth = 300
        widthEnv.selectPropertyType(.unit)
        widthEnv.leftSidebarWidth = 420
        widthEnv.undo()
        check("리사이즈: 폭은 실행취소 대상이 아니다", widthEnv.leftSidebarWidth == 420,
              "\(widthEnv.leftSidebarWidth) — 스냅샷에 폭이 들어가면 cmd+z가 창 크기를 되돌린다")

        // 15. '똑같이 생긴 개체 모두 표시' — 복수 선택 지원 (엔진 디버깅 1-2번)
        //
        // **뷰 디버깅 11번의 판단을 뒤집은 자리다.** 예전 시험은 "선택 2개면 비활성"을 못박고 있었다.
        // 지금은 반대로 "선택 2개여도 동작하고, 화면이 몇 그룹의 합집합인지 밝힌다"를 못박는다.
        // 여기서 조건을 되돌리려는 다음 세션이 있다면 이 주석을 먼저 볼 것.
        env.enterAuxiliaryScreen()
        env.auxiliary.clear()
        guard doors.count >= 2 else { print("[FAIL] 쌍둥이 시험용 개체 부족"); exit(1) }

        env.auxiliarySelection = []
        check("쌍둥이 표시: 선택 0개면 비활성", !env.canShowTwins)

        env.auxiliarySelection = [doors[0].id]
        check("쌍둥이 표시: 선택 1개면 활성", env.canShowTwins)

        env.showTwinsOnly = true
        let twinSample = env.twins(of: [doors[0].id])
        guard let outsider = auxDoc.objects.first(where: { !twinSample.contains($0.id) }) else {
            print("[FAIL] 쌍둥이 아닌 개체 없음"); exit(1)
        }
        check("쌍둥이 표시: 켜면 쌍둥이만 100%",
              abs(env.auxiliaryOpacity(for: doors[0]) - 1.0) < 1e-9
              && abs(env.auxiliaryOpacity(for: outsider) - 0.75) < 1e-9,
              "쌍둥이 1.0 / 나머지 0.75")

        check("쌍둥이 표시: 선택 1개면 1그룹", env.selectedTwinGroupCount == 1,
              "\(env.selectedTwinGroupCount)그룹")

        // 서로 다른 그룹에 속한 개체를 하나씩 골라 '섞인 선택'을 만든다.
        // 같은 그룹에서 둘을 고르면 그룹 수가 1이라 이 항목이 아무것도 검증하지 못한다.
        guard let otherDoor = doors.first(where: { !twinSample.contains($0.id) }) else {
            print("[FAIL] 다른 쌍둥이 그룹의 개체 없음"); exit(1)
        }
        let mixed: Set<VectorObjectID> = [doors[0].id, otherDoor.id]
        env.auxiliarySelection = mixed
        check("쌍둥이 표시: 선택 2개여도 활성 (1-2번, 11번 판단 뒤집기)", env.canShowTwins,
              "선택 \(env.auxiliarySelection.count)개")
        check("쌍둥이 표시: 선택이 늘어도 효과가 유지된다", env.showTwinsOnly,
              "예전에는 여기서 자동으로 꺼졌다")
        check("쌍둥이 표시: 섞인 선택은 그룹 수가 2", env.selectedTwinGroupCount == 2,
              "\(env.selectedTwinGroupCount)그룹")

        // 합집합이 맞는지 — 두 그룹의 구성원이 모두 100%로 떠야 한다.
        let mixedTwins = env.twins(of: mixed)
        check("쌍둥이 표시: 여러 그룹은 합집합",
              mixedTwins == twinSample.union(env.twins(of: [otherDoor.id]))
              && mixedTwins.count > twinSample.count,
              "\(mixedTwins.count)개")
        check("쌍둥이 표시: 합집합 전부 100%",
              mixedTwins.allSatisfy { id in
                  guard let o = auxDoc.objects.first(where: { $0.id == id }) else { return false }
                  return abs(env.auxiliaryOpacity(for: o) - 1.0) < 1e-9
              })

        // 이 완화의 전제 조건 — 합집합이라는 사실을 라벨이 말해야 한다.
        // 안 말하면 "100%로 보이는 것"의 기준이 사라진다는 11번의 우려가 그대로 남는다.
        check("쌍둥이 라벨: 여러 그룹이면 그룹 수를 함께 보여준다",
              TwinToggleText.label(isOn: true, groupCount: 3, objectCount: 24)
                  == "쌍둥이 3그룹 · 24개 표시 중")
        check("쌍둥이 라벨: 한 그룹이면 그룹 수를 빼고 개수만",
              TwinToggleText.label(isOn: true, groupCount: 1, objectCount: 6)
                  == "쌍둥이 6개 표시 중")
        check("쌍둥이 라벨: 꺼져 있으면 켜라는 말",
              TwinToggleText.label(isOn: false, groupCount: 3, objectCount: 24)
                  == "똑같이 생긴 개체 모두 표시")
        check("쌍둥이 도움말: 선택 0개일 때만 '하나 이상'을 요구",
              TwinToggleText.help(selectionCount: 0, groupCount: 0).contains("하나 이상")
              && !TwinToggleText.help(selectionCount: 2, groupCount: 2).contains("하나만"),
              "예전 도움말의 '하나만 선택했을 때' 문구가 남아 있으면 안 된다")

        // 선택이 **비면** 여전히 꺼야 한다. 끌 버튼이 사라지는 함정은 그대로 남아 있다.
        env.auxiliarySelection = []
        check("쌍둥이 표시: 선택이 비면 효과가 꺼진다", !env.showTwinsOnly && !env.canShowTwins)
        check("쌍둥이 표시: 꺼지면 배율 원복",
              abs(env.auxiliaryOpacity(for: outsider) - 1.0) < 1e-9)

        // 지정 버튼도 같은 조건을 따른다 — 보이는 것과 지정되는 것이 갈라지면 안 된다.
        let beforeMark = env.excludedCount
        env.markTwinsAsAuxiliary()
        check("쌍둥이 지정: 선택 0개면 아무것도 안 한다", env.excludedCount == beforeMark,
              "\(env.excludedCount)개")

        env.auxiliarySelection = mixed
        env.markTwinsAsAuxiliary()
        check("쌍둥이 지정: 섞인 선택이면 두 그룹 모두 지정", env.excludedCount == mixedTwins.count,
              "\(env.excludedCount)개 (합집합 \(mixedTwins.count)개)")
        // 1-4번: 여기가 이번 항목의 실제 내용이다. 예전에는 이 함수가 선택을 남겼다.
        check("쌍둥이 지정: 지정 후 선택 자동 해제 (1-4번)", env.auxiliarySelection.isEmpty,
              "그룹 전체가 골라진 채 남으면 다음 선택에 수십 개가 딸려 온다")
        check("쌍둥이 지정: 선택이 비어 표시 효과도 함께 꺼진다", !env.showTwinsOnly)

        // '지정 풀기'는 반대다 — 푼 개체를 이어서 보는 흐름이라 선택이 남아야 한다.
        env.auxiliarySelection = mixed
        env.unmarkSelectedAsAuxiliary()
        check("지정 풀기: 선택을 비우지 않는다", env.auxiliarySelection == mixed,
              "종착점인 '지정'만 비운다 — 푼 개체는 이어서 다시 봐야 한다")

        // 16. 우측 사이드바 목록 분리 (엔진 디버깅 1-3번)
        env.auxiliary.clear()
        let groupTab = env.auxiliarySidebarGroups(.twinGroups)
        let soloTab = env.auxiliarySidebarGroups(.soloObjects)
        check("사이드바 분리: 그룹 탭은 2개 이상만", groupTab.allSatisfy { $0.count > 1 },
              "\(groupTab.count)그룹")
        check("사이드바 분리: 개별 탭은 1개짜리만", soloTab.allSatisfy { $0.count == 1 },
              "\(soloTab.count)개")
        check("사이드바 분리: 두 탭이 안 겹친다",
              Set(groupTab.map(\.key)).isDisjoint(with: Set(soloTab.map(\.key))))
        check("사이드바 분리: 합치면 전체 그룹",
              groupTab.count + soloTab.count == env.twinGroups.count,
              "\(groupTab.count) + \(soloTab.count) / \(env.twinGroups.count)")
        // 이 항목이 없으면 "개별 개체가 어딘가엔 보인다"가 보장되지 않는다 —
        // 예전 사이드바에서 크기 1짜리가 통째로 걸러져 안 보이던 게 이번 건의 원인이다.
        check("사이드바 분리: 모든 개체가 어느 한 탭에는 뜬다",
              Set(groupTab.flatMap(\.memberIDs)).union(soloTab.flatMap(\.memberIDs))
                  == Set(auxDoc.objects.map(\.id)),
              "개체 \(auxDoc.objects.count)개")
        if let solo = soloTab.first {
            // 크기 1짜리 그룹의 키는 그 개체 하나만 가리킨다 — 개별 개체용 강조 상태를
            // 따로 두지 않고 `focusedTwinKey`를 그대로 쓸 수 있는 근거다.
            env.focusedTwinKey = solo.key
            check("사이드바 분리: 개별 개체도 focusedTwinKey로 단독 강조",
                  env.auxiliaryHighlightedIDs == Set(solo.memberIDs)
                  && env.auxiliaryHighlightedIDs?.count == 1,
                  "\(env.auxiliaryHighlightedIDs?.count ?? -1)개")
            env.focusedTwinKey = nil
        }

        env.exitAuxiliaryScreen()
        env.auxiliary.clear()

        // 14. 상단바 버튼 가시성 (명세 디버깅 10번)
        // "활성인데 비활성처럼 보인다"가 문제였으므로, 두 상태가 수치로 갈라지는지를 못박는다.
        let onOpacity = ToolbarButtonAppearance.opacity(isEnabled: true)
        let offOpacity = ToolbarButtonAppearance.opacity(isEnabled: false)
        check("상단바: 활성 버튼은 불투명", abs(onOpacity - 1.0) < 0.001,
              String(format: "%.2f — 누를 수 있는 버튼이 흐려지면 비활성으로 오해한다", onOpacity))
        check("상단바: 활성·비활성 구분", onOpacity - offOpacity >= 0.5,
              String(format: "차이 %.2f", onOpacity - offOpacity))
        check("상단바: 비활성은 흐림", offOpacity <= 0.4,
              String(format: "%.2f", offOpacity))

        let idle = ToolbarButtonAppearance.background(isEnabled: true, isHovering: false, isPressed: false)
        let hover = ToolbarButtonAppearance.background(isEnabled: true, isHovering: true, isPressed: false)
        let pressed = ToolbarButtonAppearance.background(isEnabled: true, isHovering: true, isPressed: true)
        check("상단바: hover 배경이 평상시보다 진함", hover > idle,
              String(format: "%.2f > %.2f", hover, idle))
        check("상단바: 누른 상태가 hover보다 진함", pressed > hover,
              String(format: "%.2f > %.2f", pressed, hover))
        check("상단바: 비활성은 hover 배경 없음",
              ToolbarButtonAppearance.background(isEnabled: false, isHovering: true, isPressed: false) == idle,
              "눌릴 것처럼 보이면 안 된다")

        // 상단바 색은 시스템 외관이 아니라 **캔버스 배경**을 따라야 한다.
        // 전에는 `.regularMaterial` + `.primary`였는데, 머터리얼이 반투명이라
        // 시스템 다크 + 캔버스 밝게에서 흰 글씨가 흰 카드에 묻혔다. 그 조합을 수치로 막는다.
        for bg in CanvasBackground.allCases {
            let name = bg == .light ? "밝은 배경" : "어두운 배경"
            let fill = luminance(of: bg.toolbarFill)
            let fore = luminance(of: bg.toolbarForeground)
            let stroke = luminance(of: bg.toolbarStroke)

            check("\(name): 상단바 글자·바탕 대비", abs(fore - fill) >= 0.5,
                  String(format: "휘도차 %.2f — 이 값이 무너지면 버튼이 카드에 묻힌다", abs(fore - fill)))
            check("\(name): 상단바 카드가 도면과 구분", abs(fill - bg.luminance) >= 0.04,
                  String(format: "휘도차 %.2f", abs(fill - bg.luminance)))
            check("\(name): 상단바 테두리 대비", abs(stroke - fill) >= 0.15,
                  String(format: "휘도차 %.2f — 휘도차가 작은 카드를 테두리가 대신 세운다", abs(stroke - fill)))
            check("\(name): 상단바 글자가 배경 반대쪽",
                  (bg == .light && fore < 0.35) || (bg == .dark && fore > 0.65),
                  String(format: "글자 휘도 %.2f, 배경 %.2f", fore, bg.luminance))
        }
        // 배경을 바꾸면 글자색도 같이 뒤집혀야 한다. 한쪽만 따라오면 이번 문제가 재발한다.
        check("상단바: 배경 전환 시 글자색도 반전",
              luminance(of: CanvasBackground.light.toolbarForeground)
                < luminance(of: CanvasBackground.dark.toolbarForeground),
              "밝은 배경은 어두운 글자, 어두운 배경은 밝은 글자")
        check("상단바: 아이콘 버튼은 평상시에도 바탕이 있다",
              ToolbarButtonAppearance.background(isEnabled: true, isHovering: false,
                                                 isPressed: false, bordered: true)
                > ToolbarButtonAppearance.background(isEnabled: true, isHovering: false,
                                                     isPressed: false),
              "글자 없는 버튼은 눌릴 곳이 안 보인다")

        // 15. 드래그 사각형 선택 (명세 디버깅 9번)
        env.selection.clear()
        env.auxiliary.clear()
        env.setMode(.idle)
        env.forceSelectMode = true
        // fn+shift+z를 GUI 없이 흉내낸다. 이 스위치가 없으면 아래 선택이 전부 막힌다.

        let allRect = CGRect(x: -50, y: -50,
                             width: doc.canvasSize.width + 100, height: doc.canvasSize.height + 100)
        let everything = HitTester.objects(in: allRect, mode: .enclose,
                                           candidates: doc.objects, cached: HitTester.directGeometry(SegmentationStore()))
        check("드래그 선택: 전체를 감싸면 전부 잡힌다", everything.count == doc.objects.count,
              "\(everything.count)/\(doc.objects.count)개")

        let emptyRect = CGRect(x: -400, y: -400, width: 10, height: 10)
        check("드래그 선택: 빈 곳은 아무것도 안 잡는다",
              HitTester.objects(in: emptyRect, mode: .crossing,
                                candidates: doc.objects, cached: HitTester.directGeometry(SegmentationStore())).isEmpty)

        // 감싸기 vs 스치기 — 개체의 변 하나에만 걸치는 작은 사각형으로 둘을 갈라 본다.
        guard let probe = doc.objects.first(where: { $0.sourceElement == "rect" }) else {
            print("[FAIL] 드래그 선택: 시험용 개체 없음"); exit(1)
        }
        let onEdge = CGRect(x: probe.boundingBox.minX - 4, y: probe.boundingBox.midY - 4,
                            width: 8, height: 8)
        check("드래그 선택: 감싸기는 걸친 개체를 안 고른다",
              HitTester.objects(in: onEdge, mode: .enclose,
                                candidates: [probe], cached: HitTester.directGeometry(SegmentationStore())).isEmpty,
              "좌→우 드래그는 사각형 안에 통째로 들어온 것만 고른다")
        check("드래그 선택: 스치기는 걸친 개체를 고른다",
              HitTester.objects(in: onEdge, mode: .crossing,
                                candidates: [probe], cached: HitTester.directGeometry(SegmentationStore())) == [probe.id],
              "우→좌 드래그는 닿기만 해도 고른다 — 화면 밖까지 뻗은 벽선을 고르는 유일한 길이다")

        // 속이 빈 개체의 **안쪽만** 훑은 것은 아무것도 안 스친 것이다.
        // 채워진 개체는 반대다 — 눈에는 그 개체를 긁은 것으로 보이므로 잡아 준다.
        let hollow = doc.objects.first { $0.style.fill == nil && $0.sourceElement == "rect" }
        let filled = doc.objects.first { $0.style.fill != nil }
        if let hollow {
            let inside = hollow.boundingBox.insetBy(dx: hollow.boundingBox.width * 0.3,
                                                    dy: hollow.boundingBox.height * 0.3)
            check("드래그 선택: 빈 개체 안쪽만 훑으면 안 잡힌다",
                  HitTester.objects(in: inside, mode: .crossing,
                                    candidates: [hollow], cached: HitTester.directGeometry(SegmentationStore())).isEmpty,
                  "선이 하나도 안 닿았으면 스친 것이 아니다")
        }
        if let filled {
            let inside = filled.boundingBox.insetBy(dx: filled.boundingBox.width * 0.3,
                                                    dy: filled.boundingBox.height * 0.3)
            check("드래그 선택: 채워진 개체 안쪽은 잡힌다",
                  HitTester.objects(in: inside, mode: .crossing,
                                    candidates: [filled], cached: HitTester.directGeometry(SegmentationStore())) == [filled.id],
                  "면을 긁었으면 사용자 눈에는 그 개체를 고른 것이다")
        }

        let full = HitTester.objects(in: probe.boundingBox.insetBy(dx: -5, dy: -5), mode: .enclose,
                                     candidates: [probe], cached: HitTester.directGeometry(SegmentationStore()))
        check("드래그 선택: 통째로 감싸면 감싸기로도 잡힌다", full == [probe.id])

        // 선분 대 사각형 판정 — 관통하는 선은 끝점이 둘 다 밖에 있어도 닿은 것이다.
        let box = CGRect(x: 0, y: 0, width: 10, height: 10)
        check("드래그 선택: 관통하는 선분 판정",
              HitTester.segment(LineSegment(start: LocalPoint(-5, 5), end: LocalPoint(15, 5)),
                                intersects: box))
        check("드래그 선택: 사각형 밖 선분은 안 잡힘",
              !HitTester.segment(LineSegment(start: LocalPoint(20, 20), end: LocalPoint(30, 30)),
                                 intersects: box))
        check("드래그 선택: 끝점이 안에 있으면 잡힘",
              HitTester.segment(LineSegment(start: LocalPoint(5, 5), end: LocalPoint(50, 50)),
                                intersects: box))
        check("드래그 선택: 클릭·드래그 경계", MarqueeRect.dragThreshold >= 3,
              "\(MarqueeRect.dragThreshold)pt — 손떨림이 사각형 선택으로 새면 클릭이 사라진다")

        // 방향으로 방식이 갈리는지
        check("드래그 선택: 좌→우는 감싸기",
              MarqueeRect(start: CGPoint(x: 0, y: 0), current: CGPoint(x: 100, y: 60)).isCrossing == false)
        check("드래그 선택: 우→좌는 스치기",
              MarqueeRect(start: CGPoint(x: 100, y: 0), current: CGPoint(x: 0, y: 60)).isCrossing)

        // 실제 선택 경로 — 클릭과 같은 이유로 막히는 개체는 조용히 빠져야 한다.
        env.selection.clear()
        env.selectPropertyType(.unit)
        env.handleMarqueeSelection(rect: allRect, mode: .enclose)
        let bulk = env.selection.selected.count
        check("드래그 선택: 캔버스에서 여러 개가 한 번에 들어온다", bulk > 1, "\(bulk)개")

        let before = env.selection.selected.count
        env.handleMarqueeSelection(rect: allRect, mode: .enclose)
        check("드래그 선택: 다시 훑어도 이미 고른 것이 풀리지 않는다",
              env.selection.selected.count == before,
              "토글이 아니라 더하기다 — 수십 개가 한꺼번에 뒤집히면 결과를 예측할 수 없다")

        // ✅ 2026-08-30 요청 1-2: 상단바 '드래그: 해제' 모드에서는 같은 드래그가 빼기가 된다.
        env.marqueeSubtracts = true
        env.handleMarqueeSelection(rect: allRect, mode: .enclose)
        check("드래그 해제: 빼기 모드에서 같은 사각형을 훑으면 선택이 빈다",
              env.selection.selected.isEmpty,
              "\(before)개 → \(env.selection.selected.count)개")
        check("드래그 해제: 선택이 비면 모드도 함께 꺼진다",
              !env.marqueeSubtracts,
              "상단바가 사라지는데 모드만 켜져 있으면 끌 버튼이 없는 상태가 된다")

        env.marqueeSubtracts = true
        env.enterAuxiliaryScreen()
        check("드래그 해제: 모드는 화면을 넘어가지 않는다", !env.marqueeSubtracts,
              "다른 화면에서 켜 둔 모드가 따라오면 첫 드래그의 결과를 예측할 수 없다")
        env.exitAuxiliaryScreen()

        env.selection.clear()
        env.auxiliary.exclude([firstDoor.id])
        check("드래그 선택: 보조 개체는 조용히 빠진다",
              env.marqueeAdmission(firstDoor.id, in: doc) == .auxiliary)
        env.auxiliary.clear()

        // 보조 개체 제외 창 — 여기는 수식키 없이 그냥 드래그가 사각형 선택이다.
        env.auxiliarySelection = []
        env.handleAuxiliaryMarquee(rect: allRect, mode: .enclose)
        check("드래그 선택: 보조 개체 창에서도 여러 개가 잡힌다",
              env.auxiliarySelection.count == doc.objects.count,
              "\(env.auxiliarySelection.count)/\(doc.objects.count)개 — 이 창은 소유권을 보지 않는다")

        // ✅ 2026-08-30 요청 1-2: 이 창도 같은 규칙이다. ⌥드래그가 이미 화면 이동이라
        // 수식키로 빼기를 표현할 자리가 없어, 상단바 토글 하나로 두 화면을 같은 규칙으로 맞춘다.
        env.marqueeSubtracts = true
        env.handleAuxiliaryMarquee(rect: allRect, mode: .enclose)
        check("드래그 해제: 보조 개체 창에서도 빼기가 된다",
              env.auxiliarySelection.isEmpty && !env.marqueeSubtracts,
              "\(env.auxiliarySelection.count)개 남음")

        env.auxiliarySelection = []
        env.forceSelectMode = false
        env.selection.clear()

        // 16. 쌍둥이 인덱스 — '똑같이 생긴 개체 모두 보기'가 멈추던 건 (엔진 디버깅 1-1번)
        //
        // `twinKey`는 개체의 모든 점을 문자열로 이어 붙이는 무거운 계산이다. 예전에는 캔버스가
        // 개체마다 `auxiliaryOpacity`를 부르고 그 안에서 도면 전체의 키를 새로 만들어,
        // 매 프레임 O(N² × 점 개수)가 돌았다. 개체가 수천 개인 실도면에서 커서가 안 돌아온 이유다.
        check("쌍둥이 인덱스: 도면 적재 시 만들어진다",
              env.twinKeyByObject.count == auxDoc.objects.count && !env.twinGroups.isEmpty,
              "키 \(env.twinKeyByObject.count)개 / 그룹 \(env.twinGroups.count)개")

        let indexedKeys = Set(env.twinKeyByObject.values)
        check("쌍둥이 인덱스: 그룹 수와 고유 키 수가 같다",
              env.twinGroups.count == indexedKeys.count,
              "그룹 \(env.twinGroups.count) / 키 \(indexedKeys.count)")
        check("쌍둥이 인덱스: 캐시한 키가 직접 계산한 값과 같다",
              auxDoc.objects.allSatisfy { env.twinKeyByObject[$0.id] == $0.twinKey },
              "캐시가 어긋나면 화면과 지정 대상이 갈라진다")

        check("쌍둥이 배율: 강조가 꺼져 있으면 전부 100%",
              abs(AuxiliaryOpacity.value(for: doors[0].id, highlighted: nil) - 1.0) < 1e-9,
              "흐릴 대상이 없을 때 전부 흐리면 기준이 되는 100%가 사라진다")
        check("쌍둥이 배율: 명세의 75%",
              abs(AuxiliaryOpacity.dimmed - 0.75) < 1e-9,
              "\(AuxiliaryOpacity.dimmed)")

        // 같은 자리에 겹친 개체 — 클릭으로 지정한 것이 작업 화면에서 안 지워지던 건(2026-10-19).
        // 클릭은 맨 위 하나만 잡아, 밑에 겹친 같은 선이 남았다. 드래그는 겹친 것을 다 담아 결과가 갈렸다.
        // 실도면처럼 면(fill만)과 테두리(stroke만)가 같은 모양의 별개 path로 겹친 경우도 넣는다.
        let fillOnly = VectorStyle(stroke: nil, fill: RGBAColor(r: 0.73, g: 0.73, b: 0.73, a: 1),
                                   strokeWidth: 1, dashPattern: [])
        func stackRect(_ x: Double, _ i: Int, style: VectorStyle) -> VectorObject {
            VectorObject(id: UUID(),
                         geometry: PathGeometry(subpaths: [Subpath(
                             start: LocalPoint(x, 0),
                             segments: [.line(to: LocalPoint(x + 8, 0)),
                                        .line(to: LocalPoint(x + 8, 8)),
                                        .line(to: LocalPoint(x, 8))],
                             isClosed: true)]),
                         style: style, sourceElement: "path", ordinal: i)
        }
        let stacked = [stackRect(0, 0, style: doors[0].style), stackRect(0, 1, style: doors[0].style),
                       stackRect(0, 2, style: fillOnly), stackRect(40, 3, style: doors[0].style)]
        let stackEnv = AppEnvironment()
        stackEnv.document = DrawingDocument(objects: stacked, canvasSize: CGSize(width: 100, height: 20),
                                            sourceName: "겹침시험")
        stackEnv.showAuxiliaryScreen = true
        stackEnv.handleAuxiliaryClick(stacked[2].id)
        check("보조 클릭: 같은 자리에 겹친 똑같은 개체를 함께 고른다",
              stackEnv.auxiliarySelection == Set(stacked[0...2].map(\.id)),
              "\(stackEnv.auxiliarySelection.count)개 선택 (기대 3, 다른 자리 쌍둥이는 제외)")
        stackEnv.markSelectedAsAuxiliary()
        check("보조 클릭: 지정하면 겹친 것이 모두 제외된다",
              stackEnv.excludedCount == 3 && !stackEnv.auxiliary.isExcluded(stacked[3].id),
              "제외 \(stackEnv.excludedCount)개")
        stackEnv.handleAuxiliaryClick(stacked[0].id)
        stackEnv.handleAuxiliaryClick(stacked[0].id)
        check("보조 클릭: 다시 클릭하면 겹친 것이 함께 풀린다",
              stackEnv.auxiliarySelection.isEmpty, "\(stackEnv.auxiliarySelection.count)개 남음")

        // 큰 도면으로 한 프레임을 흉내 내 시간을 잰다.
        // 고치기 전이라면 이 블록 하나가 수십 초 걸린다 — 상한을 넉넉히 둬도 확실히 걸린다.
        var heavy: [VectorObject] = []
        for i in 0..<600 {
            let x = Double(i % 30) * 12, y = Double(i / 30) * 12
            heavy.append(VectorObject(
                id: UUID(),
                geometry: PathGeometry(subpaths: [Subpath(
                    start: LocalPoint(x, y),
                    segments: [.line(to: LocalPoint(x + 8, y)),
                               .line(to: LocalPoint(x + 8, y + 8)),
                               .line(to: LocalPoint(x, y + 8))],
                    isClosed: true)]),
                style: doors[0].style,
                sourceElement: "rect",
                ordinal: i))
        }
        let heavyEnv = AppEnvironment()
        heavyEnv.document = DrawingDocument(objects: heavy,
                                            canvasSize: CGSize(width: 400, height: 300),
                                            sourceName: "성능시험")
        heavyEnv.showAuxiliaryScreen = true
        heavyEnv.auxiliarySelection = [heavy[0].id]
        heavyEnv.showTwinsOnly = true
        check("쌍둥이 인덱스: 큰 도면도 한 번만 훑는다",
              heavyEnv.twinKeyByObject.count == heavy.count, "\(heavyEnv.twinKeyByObject.count)개")

        let started = Date()
        for _ in 0..<30 {
            // 캔버스가 한 프레임에 하는 일 그대로 — 강조 집합은 루프 **바깥**에서 한 번만 받는다.
            let highlighted = heavyEnv.auxiliaryHighlightedIDs
            var lit = 0
            for o in heavy where AuxiliaryOpacity.value(for: o.id, highlighted: highlighted) > 0.9 {
                lit += 1
            }
            if lit == 0 { break }
        }
        let elapsed = Date().timeIntervalSince(started)
        check("쌍둥이 표시: 600개 도면 30프레임이 1초 안에 끝난다", elapsed < 1.0,
              String(format: "%.3f초 — 고치기 전에는 프레임마다 도면 전체의 키를 새로 만들어 수십 초가 걸렸다", elapsed))

        // 17. 저장·작업 공유 (신기능 1항)
        //
        // 이 절의 시험은 전부 **디스크를 거치지 않는다.** 합치기는 잘못되면 남의 작업이
        // 소리 없이 사라지거나 내 작업을 덮는 종류라, 헤드리스로 확인할 수 있어야 한다.

        // 17-1. 개체 id가 도면에서 결정적으로 나오는가 — 작업 공유 전체가 여기 얹혀 있다
        guard let reparsed = try? SVGParser.parse(data: data, sourceName: SampleFloorplan.name) else {
            print("[FAIL] 공유: 도면 재파싱 실패"); exit(1)
        }
        check("공유: 같은 SVG를 두 번 읽으면 개체 id가 같다",
              reparsed.objects.map(\.id) == doc.objects.map(\.id),
              "id가 매번 달라지면 B가 태깅한 결과를 A에 붙일 방법이 없다")
        check("공유: 도면 지문도 같다", reparsed.fingerprint == doc.fingerprint)
        check("공유: 개체 id가 서로 겹치지 않는다",
              Set(doc.objects.map(\.id)).count == doc.objects.count,
              "좌표가 같은 도형이 겹쳐 있어도 ordinal이 둘을 가른다")

        let shuffled = DrawingDocument(objects: Array(doc.objects.dropLast()),
                                       canvasSize: doc.canvasSize, sourceName: doc.sourceName)
        check("공유: 도면이 달라지면 지문도 달라진다", shuffled.fingerprint != doc.fingerprint,
              "배정한 뒤 원본 도면을 바꿔 열면 개체가 어긋난다 — 그 경우를 걸러내는 자물쇠다")

        // 17-2. 저장 형식
        check("저장: 확장자는 .imdfrnt", ProjectFile.fileExtension == "imdfrnt",
              ProjectFile.fileExtension)
        check("저장: 버전 1과 확장자가 같으므로 version 필드가 유일한 판별 수단",
              ProjectFile.currentVersion == 5,
              "확장자를 되돌려서 파일 이름만으로는 옛 파일을 구분할 수 없다")
        check("저장: 자동 저장 주기 30초",
              abs(AppEnvironment.autosaveInterval - 30) < 1e-9,
              "\(AppEnvironment.autosaveInterval)초")

        var legacy = ProjectFile(sourceName: "old.svg", svg: SampleFloorplan.svg,
                                 features: FeatureStore(), ownership: OwnershipRegistry(),
                                 segmentation: SegmentationStore(), auxiliary: AuxiliaryStore(),
                                 anchors: AnchorStore(), serials: SerialNumberAllocator(),
                                 ids: IDAssigner(), openingGate: OpeningGateStore(),
                                 borrow: BorrowRegistry())
        legacy.version = 1
        var legacyRejected = false
        if let d = try? legacy.encoded() {
            do { _ = try ProjectFile.decoded(from: d) } catch { legacyRejected = true }
        }
        check("저장: 옛 형식(버전 1)은 거절한다", legacyRejected,
              "억지로 열면 태깅이 가리키는 개체가 도면에 하나도 없는 상태가 된다 — 조용한 데이터 손실")

        // 17-3. A가 몫을 나눠주고, B가 태깅하고, A가 다시 합치는 한 바퀴
        let alice = AppEnvironment()
        alice.openSample()
        guard let aliceDoc = alice.document else { print("[FAIL] 공유: 도면 적재 실패"); exit(1) }

        let half = Set(aliceDoc.objects.prefix(10).map(\.id))
        let assignment = Assignment(id: UUID(), projectID: alice.projectID,
                                    drawingFingerprint: aliceDoc.fingerprint,
                                    assignee: "김도면", objectIDs: half,
                                    bounds: Assignment.bounds(of: half, in: aliceDoc),
                                    createdAt: Date())
        check("공유: 담당 구역은 담당 개체를 모두 감싼다",
              half.allSatisfy { assignment.bounds.insetBy(dx: -1, dy: -1)
                  .contains(aliceDoc.object($0)!.boundingBox) })

        // B 쪽: 배정본을 열면 담당 밖은 고를 수 없다
        let bob = AppEnvironment()
        bob.openSample()
        bob.projectID = alice.projectID
        bob.assignment = assignment
        guard let bobDoc = bob.document else { print("[FAIL] 공유: B 도면 적재 실패"); exit(1) }
        guard let mine = half.first,
              let notMine = bobDoc.objects.first(where: { !half.contains($0.id) })?.id else {
            print("[FAIL] 공유: 담당 안/밖 개체를 못 찾음"); exit(1)
        }
        check("공유: 담당 개체는 고를 수 있다", bob.isWithinAssignment(mine))
        check("공유: 담당 밖 개체는 못 고른다", !bob.isWithinAssignment(notMine))
        check("공유: 드래그 선택도 담당 밖을 거른다",
              bob.marqueeAdmission(notMine, in: bobDoc) == .outsideAssignment,
              "클릭만 막고 드래그를 열어 두면 규칙이 경로마다 갈린다")
        check("공유: 담당 밖 개체는 화면에서도 비활성",
              bob.renderState(for: bobDoc.object(notMine)!).isDisabled,
              "고를 수 없는데 고를 수 있어 보이면 계속 눌러 보게 된다")

        // B가 담당 몫을 태깅. 명세 10-1 게이트를 사람과 같은 순서로 지난다 —
        // 이 절차를 건너뛰면 unit 레이어가 안 열려 시험이 "공유가 깨졌다"고 잘못 말한다.
        bob.selectPropertyType(.opening)
        bob.declareOpeningComplete()
        bob.selectPropertyType(.unit)
        bob.selection.selected = Set(half.prefix(3))
        bob.createFeature()
        guard let bobFeature = bob.features.features.first else {
            print("[FAIL] 공유: B가 feature를 못 만듦"); exit(1)
        }
        let bobIssuedID = bob.ids.id(for: bobFeature.id)

        guard var handback = bob.makeProjectFile() else {
            print("[FAIL] 공유: B의 저장 파일 생성 실패"); exit(1)
        }
        handback.assignment = assignment

        // A가 합친다
        alice.selectPropertyType(.opening)
        alice.declareOpeningComplete()
        alice.selectPropertyType(.unit)
        var report = MergeReport()
        alice.merge(file: handback, named: "김도면.imdfrnt", into: aliceDoc, report: &report)
        check("합치기: B의 feature가 들어온다", report.acceptedFeatures == 1,
              "\(report.acceptedFeatures)개")
        check("합치기: 소유권도 함께 넘어온다",
              bobFeature.memberIDs.allSatisfy { alice.ownership.ownerOf($0) == bobFeature.id })
        check("합치기: 발급된 UUID를 그대로 물려받는다",
              alice.ids.peek(bobFeature.id) == bobIssuedID,
              "여기서 새로 뽑으면 IMDF 스펙의 'id 유지' 요건이 담당자 몫에서만 깨진다")
        check("합치기: 일련번호를 예약해 중복 발급을 막는다",
              alice.serials.next(for: .unit) != bobFeature.serialNumber,
              "예약을 안 하면 다음 저장에서 번호가 겹친다")

        // 같은 파일을 또 합쳐도 두 번 들어오지 않는다
        var again = MergeReport()
        alice.merge(file: handback, named: "김도면.imdfrnt", into: aliceDoc, report: &again)
        check("합치기: 같은 파일을 두 번 합쳐도 늘지 않는다", again.acceptedFeatures == 0,
              "\(again.acceptedFeatures)개")

        // 17-4. 막아야 하는 것들
        var wrongProject = handback
        wrongProject.assignment?.projectID = UUID()
        var r2 = MergeReport()
        alice.merge(file: wrongProject, named: "남의것.imdfrnt", into: aliceDoc, report: &r2)
        check("합치기: 다른 작업에서 온 파일은 거절", r2.rejectedFiles.count == 1,
              "합치면 남의 태깅이 내 도면에 섞인다")

        var wrongDrawing = handback
        wrongDrawing.assignment?.drawingFingerprint = "다른도면"
        var r3 = MergeReport()
        alice.merge(file: wrongDrawing, named: "도면바뀜.imdfrnt", into: aliceDoc, report: &r3)
        check("합치기: 도면이 달라진 파일은 거절", r3.rejectedFiles.count == 1,
              "projectID가 같아도 도면을 바꿔 열면 개체 id가 통째로 달라진다")

        var notAssignment = handback
        notAssignment.assignment = nil
        var r4 = MergeReport()
        alice.merge(file: notAssignment, named: "일반작업.imdfrnt", into: aliceDoc, report: &r4)
        check("합치기: 배정본이 아닌 파일은 거절", r4.rejectedFiles.count == 1)

        // 담당 밖을 태깅해 온 경우 — 받으면 다른 사람 몫과 충돌한다
        let rogue = AppEnvironment()
        rogue.openSample()
        rogue.projectID = alice.projectID
        rogue.selectPropertyType(.opening)
        rogue.declareOpeningComplete()
        rogue.selectPropertyType(.unit)
        rogue.selection.selected = [notMine]
        rogue.createFeature()
        if var rogueFile = rogue.makeProjectFile() {
            rogueFile.assignment = assignment
            var r5 = MergeReport()
            alice.merge(file: rogueFile, named: "범위밖.imdfrnt", into: aliceDoc, report: &r5)
            check("합치기: 담당 밖을 태깅해 온 feature는 건너뛴다",
                  r5.outOfScopeFeatures.count == 1 && r5.acceptedFeatures == 0,
                  "받아들이면 다른 사람 몫과 충돌한다")
        }
        check("합치기: 결과를 반드시 사람에게 보여준다", !report.message.isEmpty,
              "조용히 건너뛰면 내보내기 단계에서야 드러난다")

        // 18. 확대·축소 (2026-08-25, "확대가 더 크게" 요청)
        //
        // 세 작업 화면의 상한이 제각각(메인 8배 / 보조 20배 / Anchor 20배)이었고,
        // 정작 태깅을 하는 주 화면이 가장 덜 확대됐다. 규칙을 한 곳으로 모았으므로
        // 여기서 못박아 두면 한 화면만 다시 갈라지는 일을 막을 수 있다.
        check("확대: 상한이 종전 메인 화면보다 크다", CanvasZoom.maxScale > 8,
              "\(CanvasZoom.maxScale)배 — 벽 두께·문틈처럼 몇 단위짜리 간격을 보려면 8배로는 어림없다")
        check("확대: 상한에서 멈춘다",
              CanvasZoom.clamp(CanvasZoom.maxScale * 10) == CanvasZoom.maxScale)
        check("확대: 하한에서 멈춘다",
              CanvasZoom.clamp(CanvasZoom.minScale / 10) == CanvasZoom.minScale)
        check("확대: 범위 안은 그대로", CanvasZoom.clamp(2.5) == 2.5)

        // 여기가 이번 변경의 실질이다. 상한만 올리면 선이 같이 굵어져
        // "더 크게 볼 수는 있는데 아무것도 안 보이는" 상태가 된다.
        let rawWidth: CGFloat = 1.0
        for s in [CGFloat(0.5), 1, 2, 4] {
            check("확대: \(s)배까지는 선 두께가 종전과 같다",
                  abs(CanvasZoom.strokeWidth(rawWidth, at: s) - rawWidth) < 1e-9,
                  "지금까지 보던 화면이 바뀌면 안 된다")
        }

        func onScreen(_ s: CGFloat) -> CGFloat { CanvasZoom.strokeWidth(rawWidth, at: s) * s }
        check("확대: 성장 한계 위에서는 화면상 두께가 고정된다",
              abs(onScreen(200) - onScreen(CanvasZoom.strokeGrowthCap)) < 1e-9,
              String(format: "200배 %.2fpt = %.0f배 %.2fpt",
                     onScreen(200), CanvasZoom.strokeGrowthCap, onScreen(CanvasZoom.strokeGrowthCap)))
        check("확대: 200배에서 선이 도면을 덮지 않는다", onScreen(200) <= 8,
              String(format: "화면상 %.2fpt — 보정 전에는 %.0fpt였다", onScreen(200), rawWidth * 200))
        check("확대: 굵은 선도 같은 규칙을 탄다",
              abs(CanvasZoom.strokeWidth(3, at: 100) * 100
                  - CanvasZoom.strokeWidth(3, at: CanvasZoom.strokeGrowthCap) * CanvasZoom.strokeGrowthCap) < 1e-9)

        // 화면에 얹은 표시(선택 테두리·점선 간격)는 배율과 무관하게 크기가 같아야 한다.
        check("확대: 화면 고정 요소는 배율과 무관하게 같은 크기",
              abs(CanvasZoom.screenLength(3, at: 200) * 200 - 3) < 1e-9
              && abs(CanvasZoom.screenLength(3, at: 0.5) * 0.5 - 3) < 1e-9,
              "보정 안 하면 200배에서 선택 테두리가 개체에서 화면 밖까지 멀어진다")

        check("확대: 배율 표시가 칸을 넘지 않는다",
              CanvasZoom.label(200) == "200×" && CanvasZoom.label(10) == "10×",
              "\(CanvasZoom.label(200)) — 20000%로 쓰면 자릿수가 넘친다")
        check("확대: 낮은 배율은 백분율 그대로",
              CanvasZoom.label(1) == "100%" && CanvasZoom.label(0.5) == "50%",
              "\(CanvasZoom.label(1)) / \(CanvasZoom.label(0.5))")

        // 19. 문 임시로 닫기 (신기능 3항)
        //
        // 열린 상태로 그려진 문에는 **닫는 데 쓸 선분이 아예 없다.** 문짝과 회전 궤적만 있어서
        // 기존 opening 빌려주기(`BorrowRegistry`)로는 링을 닫을 수 없다. 그래서 사용자가
        // 두 점을 직접 찍어 없는 선분을 만든다 — 그 선분이 곧 opening의 LineString이다.
        let dc = AppEnvironment()
        dc.openSample()
        guard let dcDoc = dc.document else { print("[FAIL] 문닫기: 도면 적재 실패"); exit(1) }

        check("문닫기: Openings 레이어가 아니면 못 들어간다", !dc.canEnterDoorClosure,
              "다른 type에서 열어 주면 사용자가 만든 opening이 엉뚱한 레이어에 쌓인다")
        dc.selectPropertyType(.opening)
        check("문닫기: Openings 레이어에서는 들어갈 수 있다", dc.canEnterDoorClosure)

        // 3-2) 끝점과 교차점
        //
        // **만드는 시점이 이 절의 핵심이었다.** 예전에는 끝점·교차점을 메인 스레드에서 만들어,
        // 도면을 열 때 만들면 실도면에서 앱 시작이 멈췄다. 그래서 창에 들어갈 때만 만들었다.
        // #21(2026-10-15): 점 단위 편집이 모든 레이어의 기본이 되어 도면을 열 때 함께 만든다.
        // 대신 **앱에서는 백그라운드에서** 만든다(`DerivedGeometry`). 자체점검은 그 자리에서 계산한다.
        check("문닫기: 도면을 열면 고를 수 있는 점이 이미 준비된다(#21)",
              !dc.snapPoints.isEmpty && dc.doorSnapPoints.count == dc.snapPoints.count,
              "점 \(dc.snapPoints.count)개 — 앱에서는 백그라운드에서 계산한다")
        dc.enterDoorClosureScreen()
        let snaps = dc.doorSnapPoints
        check("문닫기: 창에 들어가면 점이 만들어진다", !snaps.isEmpty, "\(snaps.count)개")
        check("문닫기: 꼭짓점도 후보에 들어간다",
              snaps.contains { $0.kind == .vertex },
              "꼭짓점 \(snaps.filter { $0.kind == .vertex }.count)개 — 닫힌 사각형 모서리는 '끝점'이 아니라 꼭짓점이다")
        check("문닫기: 닫힌 사각형의 모서리가 잡힌다",
              dcDoc.objects.filter { $0.sourceElement == "rect" }.allSatisfy { r in
                  snaps.contains { abs($0.point.x - r.boundingBox.minX) < 0.06
                                && abs($0.point.y - r.boundingBox.minY) < 0.06 }
              },
              "방 폴리곤은 닫힌 경로라 종전에는 후보가 하나도 없었다")
        check("문닫기: 샘플 도면에서 끝점이 잡힌다",
              snaps.contains { $0.kind == .endpoint },
              "끝점 \(snaps.filter { $0.kind == .endpoint }.count)개")
        // 샘플 도면에는 **서로 가로지르는 개체가 없다.** 방은 떨어진 사각형이고 문은 벽에 닿기만 한다
        // (닿는 것과 가로지르는 것은 다르다 — 뷰 디버깅 4번에서 꼭짓점 접합을 겹침에서 뺀 것과 같은 기준).
        // 그래서 교차점 추출은 실제로 가로지르는 도형을 만들어 확인한다.
        let crossDoc = DrawingDocument(objects: [
            VectorObject(id: StableObjectID.make(ordinal: 1, element: "line", styleKey: "k",
                                                 geometry: PathGeometry(subpaths: [Subpath(
                                                    start: LocalPoint(0, 10),
                                                    segments: [.line(to: LocalPoint(20, 10))],
                                                    isClosed: false)])),
                         geometry: PathGeometry(subpaths: [Subpath(start: LocalPoint(0, 10),
                                                                   segments: [.line(to: LocalPoint(20, 10))],
                                                                   isClosed: false)]),
                         style: doors[0].style, sourceElement: "line", ordinal: 1),
            VectorObject(id: StableObjectID.make(ordinal: 2, element: "line", styleKey: "k",
                                                 geometry: PathGeometry(subpaths: [Subpath(
                                                    start: LocalPoint(10, 0),
                                                    segments: [.line(to: LocalPoint(10, 20))],
                                                    isClosed: false)])),
                         geometry: PathGeometry(subpaths: [Subpath(start: LocalPoint(10, 0),
                                                                   segments: [.line(to: LocalPoint(10, 20))],
                                                                   isClosed: false)]),
                         style: doors[0].style, sourceElement: "line", ordinal: 2)
        ], canvasSize: CGSize(width: 20, height: 20), sourceName: "십자")
        let crossSnaps = SnapPointExtractor.points(in: crossDoc.objects, segmentation: SegmentationStore())
        check("문닫기: 가로지르는 자리에서 교차점이 잡힌다",
              crossSnaps.contains { $0.kind == .crossing
                  && abs($0.point.x - 10) < 0.01 && abs($0.point.y - 10) < 0.01 },
              "교차점 \(crossSnaps.filter { $0.kind == .crossing }.count)개")
        check("문닫기: 교차점은 두 개체를 주인으로 갖는다",
              crossSnaps.first { $0.kind == .crossing }?.owners.count == 2)

        // 같은 자리에 여러 종류가 성립하면 뜻이 좁은 쪽이 이긴다: 끝점 > 교차점 > 꼭짓점.
        check("문닫기: 십자 도형의 끝점은 꼭짓점에 덮이지 않는다",
              crossSnaps.contains { $0.kind == .endpoint
                  && abs($0.point.x - 0) < 0.01 && abs($0.point.y - 10) < 0.01 },
              "벽이 끝난 자리가 '그냥 꺾인 점'으로 보이면 겨냥할 것을 못 고른다")
        let vertexOnly = SnapPointExtractor.points(
            in: [dcDoc.objects.first { $0.sourceElement == "rect" }!],
            segmentation: SegmentationStore())
        check("문닫기: 닫힌 경로만 있으면 전부 꼭짓점이다",
              !vertexOnly.isEmpty && vertexOnly.allSatisfy { $0.kind == .vertex },
              "\(vertexOnly.count)개")
        check("문닫기: 같은 자리 점이 겹쳐 있지 않다",
              Set(snaps.map { "\(Int(($0.point.x / SnapPointExtractor.mergeTolerance).rounded())),\(Int(($0.point.y / SnapPointExtractor.mergeTolerance).rounded()))" }).count == snaps.count,
              "벽선 두 개가 한 점에서 끝나면 후보가 두 번 잡힌다")
        check("문닫기: 결과 순서가 재현된다",
              SnapPointExtractor.points(in: dcDoc.objects, segmentation: dc.segmentation).map(\.id) == snaps.map(\.id),
              "딕셔너리 순서를 그대로 내보내면 실행할 때마다 목록이 달라진다")

        if let target = snaps.first {
            check("문닫기: 허용 반경 안이면 잡힌다",
                  SnapPointExtractor.nearest(to: target.point, among: snaps, within: 1)?.id == target.id)
            let far = LocalPoint(target.point.x + 500, target.point.y + 500)
            check("문닫기: 허용 반경 밖이면 아무것도 안 준다",
                  SnapPointExtractor.nearest(to: far, among: snaps, within: 1) == nil,
                  "억지로 가장 가까운 점을 주면 의도하지 않은 자리에 선분이 걸린다")
        }

        // 개체가 많은 도면에서도 창이 열려야 한다. 경계 상자로 먼저 걸러내지 않으면
        // 모든 개체 쌍 × 모든 선분 쌍을 돌게 되어 여기서 멈춘다.
        var manyObjects: [VectorObject] = []
        for i in 0..<600 {
            let x = Double(i % 30) * 40, y = Double(i / 30) * 40
            let g = PathGeometry(subpaths: [Subpath(
                start: LocalPoint(x, y),
                segments: [.line(to: LocalPoint(x + 30, y)),
                           .line(to: LocalPoint(x + 30, y + 30)),
                           .line(to: LocalPoint(x, y + 30))],
                isClosed: false)])
            manyObjects.append(VectorObject(
                id: StableObjectID.make(ordinal: i, element: "polyline",
                                        styleKey: doors[0].style.attributeKey, geometry: g),
                geometry: g, style: doors[0].style, sourceElement: "polyline", ordinal: i))
        }
        let snapStart = Date()
        let manySnaps = SnapPointExtractor.points(in: manyObjects, segmentation: SegmentationStore())
        let snapElapsed = Date().timeIntervalSince(snapStart)
        check("문닫기: 개체 600개 도면에서도 창이 열린다", snapElapsed < 3.0,
              String(format: "%.2f초 · 후보 %d개 — 경계 상자로 먼저 거르지 않으면 여기서 멈춘다",
                     snapElapsed, manySnaps.count))

        // 3-1) 제외된 보조 개체는 20%
        check("문닫기: 제외된 보조 개체는 20%",
              abs(DoorClosureAppearance.excludedOpacity - 0.2) < 1e-9,
              "\(DoorClosureAppearance.excludedOpacity)")
        check("문닫기: 하위 기본 레이어 수치를 빌려 쓰지 않는다",
              DoorClosureAppearance.excludedOpacity != 0.5,
              "그쪽은 사노 요청으로 50%가 됐다 — 우연히 같았던 수치를 묶으면 한쪽이 조용히 끌려간다")

        // 3-3·3-4) #37(2026-10-15): 문짝·호를 고르지 않는다. 문 선의 양 끝 두 점만 찍는다.
        // C5 도면은 호가 점선(짧은 선분 여러 개)이라 곡선 하나로 고를 수 없었다(1차 사용성 검증 #35).
        guard let arcObj = dcDoc.objects.first(where: { $0.isCurved }),
              let doorObj = dcDoc.objects.first(where: { !$0.isCurved && $0.sourceElement == "line" }) else {
            print("[FAIL] 문닫기: 예전 방식 시험용 문·호를 못 찾음"); exit(1)
        }
        check("문닫기: 아무것도 안 찍었으면 저장 불가", !dc.canSaveTemporaryDoor)
        dc.toggleDoorPoint(LocalPoint(10, 10))
        check("문닫기: 점 1개로는 저장 불가", !dc.canSaveTemporaryDoor)
        check("문닫기: 왜 못 누르는지 알려준다", dc.temporaryDoorHint.contains("1개"), dc.temporaryDoorHint)
        dc.toggleDoorPoint(LocalPoint(40, 10))
        check("#37 문닫기: 점 2개면 문짝·호 없이 저장할 수 있다", dc.canSaveTemporaryDoor,
              "호와 문짝을 고르는 단계를 없앴다")

        // 점은 두 개까지만. 세 번째는 가장 오래된 것을 밀어낸다.
        dc.toggleDoorPoint(LocalPoint(70, 10))
        check("문닫기: 점은 두 개까지만", dc.doorDraftPoints.count == 2,
              "\(dc.doorDraftPoints.count)개")
        check("문닫기: 가장 오래된 점이 밀려난다",
              dc.doorDraftPoints.first?.x == 40,
              "매번 지우고 다시 찍게 하면 손이 두 배로 든다")
        dc.toggleDoorPoint(dc.doorDraftPoints[0])
        check("문닫기: 같은 점을 다시 찍으면 취소된다", dc.doorDraftPoints.count == 1)
        dc.toggleDoorPoint(LocalPoint(40, 10))

        // 3-5) 저장
        dc.undoStack.clear()
        dc.saveTemporaryDoor()
        check("문닫기: 저장하면 목록에 쌓인다", dc.doorClosures.count == 1)
        check("문닫기: 저장 뒤에는 찍은 점이 비워진다", dc.doorDraftPoints.isEmpty)
        check("문닫기: 저장은 실행취소 대상이다", dc.canUndo,
              "스냅샷에서 빠뜨리면 perform이 '바뀐 게 없다'고 판단해 칸을 도로 버린다")
        dc.undo()
        check("문닫기: cmd+z로 되돌아간다", dc.doorClosures.isEmpty)
        dc.redo()
        check("문닫기: 다시실행도 된다", dc.doorClosures.count == 1)

        guard let saved = dc.doorClosures.doors.first else { print("[FAIL] 문닫기: 저장 실패"); exit(1) }
        check("#37 문닫기: 새 임시 문은 도면 개체를 쓰지 않는다",
              saved.doorObjectID == nil && saved.arcObjectID == nil && saved.consumedObjectIDs.isEmpty)

        // 같은 자리를 겨냥해도 길이 0인 문은 저장되지 않는다.
        // 토글이라 같은 점을 두 번 찍으면 취소되지만, 그 경로로만 막으면 규칙이 UI에 갇힌다.
        let beforeZero = dc.doorClosures.count
        dc.doorDraftPoints = [LocalPoint(200, 200), LocalPoint(200, 200)]
        dc.saveTemporaryDoor()
        check("문닫기: 길이 0인 문은 저장되지 않는다", dc.doorClosures.count == beforeZero,
              "길이 0인 LineString은 GeoJSON으로 나가면 그대로 깨진 opening이 된다")
        dc.resetDoorDraft()

        // 3-6) 레이어 반영
        let doorClaimedBefore = dc.claimedCount
        let openingsBefore = dc.features.count(ofType: .opening)
        dc.applyTemporaryDoors()
        check("문닫기: 반영하면 opening feature가 된다",
              dc.features.count(ofType: .opening) == openingsBefore + 1)
        check("문닫기: 반영하면 목록이 비워진다", dc.doorClosures.isEmpty)

        guard let openingFeature = dc.features.features(ofType: .opening).last else {
            print("[FAIL] 문닫기: opening feature 없음"); exit(1)
        }
        check("#37 문닫기: 반영된 opening은 개체를 소유하지 않는다",
              openingFeature.memberIDs.isEmpty && dc.claimedCount == doorClaimedBefore)
        check("문닫기: 찍은 선분이 feature에 실린다",
              openingFeature.closureSegment?.start == saved.start
              && openingFeature.closureSegment?.end == saved.end)
        let doorVerts = VertexExtractor.vertices(for: openingFeature, document: dcDoc,
                                             segmentation: dc.segmentation, kind: .lineString)
        check("문닫기: opening 좌표는 찍은 두 점이다",
              doorVerts.count == 2 && doorVerts[0] == saved.start && doorVerts[1] == saved.end)

        // 예전 방식(문짝·호를 고른) 임시 문은 변환하지 않고 그대로 쓴다(#37 결정 4).
        let legacyDoor = TemporaryDoor(id: UUID(), start: LocalPoint(300, 300), end: LocalPoint(330, 300),
                                       doorObjectID: doorObj.id, arcObjectID: arcObj.id, createdAt: Date())
        dc.doorClosures.insert(legacyDoor)
        check("#37 예전 임시 문: 쓰인 문·호를 기억한다",
              legacyDoor.consumedObjectIDs == [doorObj.id, arcObj.id]
              && dc.doorClosures.user(of: doorObj.id)?.id == legacyDoor.id)
        check("#37 예전 임시 문: 반영 전에도 진행률에 기여한다", dc.claimedCount >= doorClaimedBefore + 2)
        if let data = try? JSONEncoder().encode(legacyDoor),
           let round = try? JSONDecoder().decode(TemporaryDoor.self, from: data) {
            check("#37 예전 임시 문: 문짝·호 id가 왕복 보존된다", round == legacyDoor)
        } else {
            check("#37 예전 임시 문: 문짝·호 id가 왕복 보존된다", false, "직렬화 실패")
        }
        if let data = try? JSONEncoder().encode(saved),
           let json = String(data: data, encoding: .utf8) {
            check("#37 새 임시 문: 문짝·호 키 없이 저장·해독된다",
                  !json.contains("doorObjectID") && (try? JSONDecoder().decode(TemporaryDoor.self, from: data)) == saved)
        }
        dc.applyTemporaryDoors()
        if let legacyOpening = dc.features.features(ofType: .opening).first(where: {
            $0.closureSegment?.start == legacyDoor.start }) {
            check("#37 예전 임시 문: 반영하면 문·호가 그 feature 소유가 된다",
                  legacyOpening.memberIDs == [doorObj.id, arcObj.id]
                  && dc.ownership.ownerOf(doorObj.id) == legacyOpening.id)
        } else {
            check("#37 예전 임시 문: 반영하면 문·호가 그 feature 소유가 된다", false)
        }

        // 저장 파일에 실린다 — 수십 개를 찍는 작업이라 앱을 닫았다고 사라지면 안 된다
        dc.doorClosures.insert(saved)
        if let f = dc.makeProjectFile(), let round = try? ProjectFile.decoded(from: f.encoded()) {
            check("문닫기: 작업 파일에 실려 왕복한다", round.commonProject().levels.first?.editing.doorClosures.count == 1,
              "도면 전체를 훑으며 수십 개를 찍는 작업이라 저장 안 하면 통째로 날아간다")
        } else {
            check("문닫기: 작업 파일에 실려 왕복한다", false, "직렬화 실패")
        }

        // 3-2) 클릭은 점만 찍는다(#37). 예전에는 점 2개 뒤 클릭이 개체(문짝·호)를 골랐다.
        let dcClick = AppEnvironment()
        dcClick.openSample()
        dcClick.selectPropertyType(.opening)
        dcClick.enterDoorClosureScreen()
        let clickSnaps = dcClick.doorSnapPoints
        guard clickSnaps.count >= 4 else { print("[FAIL] 문닫기 클릭: 후보 점 부족"); exit(1) }

        check("#37 문닫기 클릭: 안내는 두 점 찍기다", dcClick.doorStageHint.contains("2개"), dcClick.doorStageHint)
        dcClick.handleDoorClosureClick(at: LocalPoint(-100_000, -100_000), tolerance: 6)
        check("문닫기 클릭: 후보 점이 아닌 자리는 찍히지 않는다", dcClick.doorDraftPoints.isEmpty)
        dcClick.handleDoorClosureClick(at: clickSnaps[0].point, tolerance: 6)
        dcClick.handleDoorClosureClick(at: clickSnaps[1].point, tolerance: 6)
        check("문닫기 클릭: 점 두 개가 찍힌다", dcClick.doorDraftPoints.count == 2)
        check("#37 문닫기 클릭: 두 점이면 바로 저장할 수 있다", dcClick.canSaveTemporaryDoor,
              dcClick.temporaryDoorHint)

        let backOne = dcClick.doorDraftPoints[1]
        dcClick.handleDoorClosureClick(at: backOne, tolerance: 6)
        check("문닫기 클릭: 찍은 점을 다시 누르면 지워진다", dcClick.doorDraftPoints.count == 1)
        dcClick.handleDoorClosureClick(at: backOne, tolerance: 6)
        check("문닫기 클릭: 다시 찍으면 복구된다", dcClick.doorDraftPoints.count == 2)

        // 연속 작업 — 저장하고 나면 곧바로 다음 문을 닫을 수 있어야 한다.
        dcClick.saveTemporaryDoor()
        dcClick.handleDoorClosureClick(at: clickSnaps[2].point, tolerance: 6)
        dcClick.handleDoorClosureClick(at: clickSnaps[3].point, tolerance: 6)
        dcClick.saveTemporaryDoor()
        check("문닫기 클릭: 문을 연속으로 닫을 수 있다", dcClick.doorClosures.count == 2,
              "점 4번 클릭 + 저장 2번으로 문 두 개 — 문짝·호를 고르는 클릭이 없다")
        dcClick.applyTemporaryDoors()
        let clickOpenings = dcClick.features.features(ofType: .opening)
        check("#37 문닫기 클릭: 모두 반영하면 opening 두 개가 두 점 LineString이 된다",
              clickOpenings.count == 2 && clickOpenings.allSatisfy {
                  VertexExtractor.vertices(for: $0, document: dcClick.document!, segmentation: dcClick.segmentation,
                                           kind: .lineString).count == 2 })

        // 20. 사이드바 '모두 접기' (2026-08-25 요청)
        let sb = AppEnvironment()
        sb.openSample()

        check("모두 접기: 처음에는 아무것도 안 접혀 있다", sb.collapsedSections.isEmpty)
        check("모두 접기: 모든 사이드바에 항목이 있다",
              SidebarSectionID.Owner.allCases.allSatisfy { !SidebarSectionID.all(in: $0).isEmpty },
              "요청이 '모든 사이드바에 해당해야 함'이라 하나라도 비면 그 화면에는 버튼이 죽은 채로 뜬다")
        check("모두 접기: 항목 키가 겹치지 않는다",
              Set(SidebarSectionID.allCases.map(\.rawValue)).count == SidebarSectionID.allCases.count,
              "키가 겹치면 한 항목을 접을 때 다른 사이드바의 항목이 같이 접힌다")

        // 한 사이드바를 접어도 다른 사이드바는 그대로여야 한다.
        sb.collapseAllSections(in: .left)
        check("모두 접기: 좌측이 전부 접힌다", sb.areAllSectionsCollapsed(in: .left))
        check("모두 접기: 다른 사이드바는 건드리지 않는다",
              !sb.areAllSectionsCollapsed(in: .auxiliary)
              && SidebarSectionID.all(in: .auxiliary).allSatisfy { !sb.isSectionCollapsed($0) },
              "한 버튼이 다른 창의 항목까지 접으면 그 창에 갔을 때 접힌 이유를 알 수 없다")

        sb.expandAllSections(in: .left)
        check("모두 펼치기: 좌측이 전부 펴진다",
              SidebarSectionID.all(in: .left).allSatisfy { !sb.isSectionCollapsed($0) },
              "접기만 있고 펴기가 없으면 되돌릴 방법이 항목을 하나씩 누르는 것뿐이다")

        sb.toggleSection(.leftProgress)
        check("모두 접기: 항목 하나만 접을 수도 있다", sb.isSectionCollapsed(.leftProgress))
        check("모두 접기: 하나라도 펴져 있으면 '모두 펼치기'로 안 바뀐다",
              !sb.areAllSectionsCollapsed(in: .left),
              "아직 접을 것이 남았는데 버튼이 반대로 바뀌면 한 번 더 눌러야 한다")
        sb.toggleSection(.leftProgress)
        check("모두 접기: 다시 누르면 펴진다", !sb.isSectionCollapsed(.leftProgress))

        // 우측은 펼쳐 놓은 feature 카드까지 함께 접힌다.
        sb.selectPropertyType(.opening)
        sb.declareOpeningComplete()
        sb.selectPropertyType(.unit)
        if let anyObj = sb.document?.objects.first {
            sb.selection.selected = [anyObj.id]
            sb.createFeature()
        }
        // feature 3개를 만들어 카드별 토글을 시험한다.
        for obj in (sb.document?.objects.prefix(4) ?? []).dropFirst() {
            sb.selection.selected = [obj.id]
            sb.createFeature()
        }
        let cards = sb.features.features(ofType: .unit).map(\.id)
        check("카드 토글: 시험용 카드가 여러 개 있다", cards.count >= 3, "\(cards.count)개")

        sb.collapseAllFeatures()
        sb.toggleFeatureExpansion(cards[0])
        sb.toggleFeatureExpansion(cards[1])
        check("카드 토글: 여러 개를 동시에 펼 수 있다",
              sb.isFeatureExpanded(cards[0]) && sb.isFeatureExpanded(cards[1])
              && !sb.isFeatureExpanded(cards[2]),
              "카드마다 독립된 토글이라야 상위 트리 없이도 원하는 것만 볼 수 있다")

        sb.toggleFeatureExpansion(cards[0])
        check("카드 토글: 하나를 접어도 다른 카드는 그대로다",
              !sb.isFeatureExpanded(cards[0]) && sb.isFeatureExpanded(cards[1]))
        check("카드 토글: 접은 카드가 초점이었으면 남은 카드로 옮긴다",
              sb.focusedFeature == cards[1],
              "초점을 비우면 다른 카드가 펼쳐져 있는데도 상단바의 대상별 동작이 사라진다")

        check("모두 접기: 카드가 펼쳐져 있으면 아직 다 접힌 게 아니다",
              sb.hasExpandedFeature && !sb.areAllSectionsCollapsed(in: .right))
        sb.collapseAllSections(in: .right)
        check("모두 접기: 우측은 카드의 개별 토글을 한꺼번에 접는다",
              !sb.hasExpandedFeature && sb.areAllSectionsCollapsed(in: .right),
              "우측에서 자리를 가장 많이 차지하는 것이 펼쳐 놓은 카드다")
        sb.expandAllSections(in: .right)
        check("모두 펼치기: 우측은 카드의 개별 토글을 한꺼번에 편다",
              cards.allSatisfy { sb.isFeatureExpanded($0) } && sb.focusedFeature != nil,
              "카드를 여러 개 펼 수 있게 된 뒤로 '모두 펼치기'가 뜻을 갖는다")

        check("카드 토글: 카드 전부를 감싸는 상위 트리는 없다",
              !SidebarSectionID.all(in: .right).contains { $0.rawValue == "rightFeatures" },
              "상위 토글 하나로 통째로 접히면 카드별 토글이 뜻을 잃는다")

        sb.collapseAllFeatures()

        // 접힌 상태는 '지금 화면을 어떻게 보고 있는가'이지 작업 결과가 아니다.
        sb.collapseAllSections(in: .left)
        let foldedSnapshot = sb.snapshot
        sb.expandAllSections(in: .left)
        check("모두 접기: 실행취소 대상이 아니다", sb.snapshot == foldedSnapshot,
              "cmd+z 한 번에 항목이 접혔다 펴지면 되돌린 것이 무엇인지 알 수 없다")
        if let f = sb.makeProjectFile(), let round = try? ProjectFile.decoded(from: f.encoded()) {
            check("모두 접기: 작업 파일에 저장되지 않는다",
                  !"\(round)".contains("collapsedSections"),
                  "남의 파일을 열 때 남의 화면 상태가 따라오면 방해만 된다")
        }

        // MARK: 레이어별 투명도 (2026-08-27 요청)

        let op = AppEnvironment()
        op.document = doc
        op.layers.bootstrap()
        let ghostLayer = op.layers.layers.first { if case .baseGhost = $0.kind { return true }; return false }!
        let topLayer = op.layers.layers.first { if case .baseTop = $0.kind { return true }; return false }!
        check("레이어 투명도: 기본값은 레이어마다 다르다",
              ghostLayer.opacity == 0.5 && topLayer.opacity == 1.0,
              "하위 기본 레이어 50%는 명세 2-3이 정한 수치다")
        check("레이어 투명도: 처음에는 사용자가 만진 값이 없다",
              !ghostLayer.hasCustomOpacity && !topLayer.hasCustomOpacity)

        op.layers.setOpacity(0.4, for: topLayer.id)
        let dimmedTop = op.layers.layers.first { $0.id == topLayer.id }!
        check("레이어 투명도: 조절한 값이 반영된다",
              dimmedTop.opacity == 0.4 && dimmedTop.hasCustomOpacity)
        check("레이어 투명도: 기본값은 그대로 남는다", dimmedTop.baseOpacity == 1.0,
              "되돌릴 기준을 잃지 않으려면 기본값과 사용자 값을 따로 둬야 한다")

        let sampleObject = doc.objects[0]
        check("레이어 투명도: 활성 레이어 값이 화면에 곱해진다",
              abs(op.renderState(for: sampleObject).opacity - 0.4) < 1e-9,
              "실제 그리기 투명도 \(op.renderState(for: sampleObject).opacity)")

        op.layers.setOpacity(nil, for: topLayer.id)
        check("레이어 투명도: 기본값으로 되돌린다",
              op.layers.layers.first { $0.id == topLayer.id }!.opacity == 1.0
              && abs(op.renderState(for: sampleObject).opacity - 1.0) < 1e-9)

        op.layers.setOpacity(0.0, for: ghostLayer.id)
        check("레이어 투명도: 0%로는 내려가지 않는다",
              op.layers.layers.first { $0.id == ghostLayer.id }!.opacity >= EditorLayer.minimumOpacity,
              "0%는 레이어가 사라진 것과 같은데, 그건 '숨기기'가 할 일이다 — 투명도 0은 화면에서 이유를 알 수 없다")
        op.layers.setOpacity(5.0, for: ghostLayer.id)
        check("레이어 투명도: 100%를 넘지 않는다",
              op.layers.layers.first { $0.id == ghostLayer.id }!.opacity == 1.0)

        // 고스트는 따로 그려지므로 활성 레이어 값에 끌려가지 않는다.
        op.layers.setOpacity(nil, for: ghostLayer.id)
        op.layers.setOpacity(0.3, for: topLayer.id)
        check("레이어 투명도: 하위 기본 레이어는 활성 레이어와 따로 논다",
              op.layers.layers.first { $0.id == ghostLayer.id }!.opacity == 0.5,
              "원위치 대조용이라 작업 레이어를 옅게 했다고 함께 옅어지면 대조가 안 된다")

        // property type 레이어의 투명도는 도면 개체가 아니라 표시된 다각형에 건다(2026-10-18 요청).
        let pop = AppEnvironment()
        pop.document = doc
        pop.declareOpeningComplete()
        pop.selectPropertyType(.unit)
        if let unitLayer = pop.layers.layers.first(where: { $0.kind == .propertyType(.unit) }) {
            pop.layers.setOpacity(0.3, for: unitLayer.id)
            let free = doc.objects.first { pop.ownership.ownerOf($0.id) == nil }!
            check("레이어 투명도: property type 레이어 값은 도면 원본 개체에 곱하지 않는다",
                  abs(pop.renderState(for: free).opacity - 1.0) < 1e-9,
                  "개체 투명도 \(pop.renderState(for: free).opacity)")
            check("레이어 투명도: property type 레이어 값은 그 type의 다각형 투명도가 된다",
                  abs(pop.polygonOpacity(for: .unit) - 0.3) < 1e-9 && pop.polygonOpacity(for: .fixture) == 1)
        } else {
            check("레이어 투명도: unit 레이어가 만들어진다", false)
        }

        // MARK: 곡선 개체 창 (명세 3-3, 2026-08-27 전용 창으로 전환)

        let cv = AppEnvironment()
        cv.document = doc
        check("곡선창: 곡선이 있으면 열 수 있다", cv.canEnterCurvedScreen,
              "곡선 \(cv.curvedObjectCount)개")
        cv.enterCurvedScreen()
        check("곡선창: 창이 열리고 표시 규칙이 켜진다",
              cv.showCurvedScreen && cv.isCurvedOnlyMode,
              "모드로만 두었을 때는 옅기 25% 차이뿐이라 '눌러도 변화 없음'으로 읽혔다")

        if let curvedObject = doc.objects.first(where: { $0.isCurved }),
           let straightObject = doc.objects.first(where: { !$0.isCurved }) {
            let curvedPoint = LocalPoint(curvedObject.boundingBox.midX,
                                         curvedObject.boundingBox.midY)
            cv.handleCurvedScreenClick(at: curvedPoint, tolerance: 400)
            check("곡선창: 곡선 개체를 고를 수 있다", !cv.selection.isEmpty)
            check("곡선창: 직선은 고를 수 없다",
                  !cv.selection.selected.contains(straightObject.id),
                  "직선까지 고르면 '선택 선분화'가 아무 일도 안 하는 경우가 생긴다(명세 3-3-2)")
        }

        cv.selection.clear()
        cv.handleCurvedScreenMarquee(rect: CGRect(x: -5000, y: -5000, width: 20000, height: 20000),
                                     mode: .crossing)
        check("곡선창: 드래그로 곡선만 한꺼번에 잡는다",
              cv.selection.selected.count == cv.curvedObjectCount,
              "\(cv.selection.selected.count)/\(cv.curvedObjectCount)개")

        cv.segmentizeSelection()
        check("곡선창: 고른 곡선이 선분화된다", cv.segmentedCount == cv.curvedObjectCount,
              "\(cv.segmentedCount)개")
        cv.setCurvedShowsSegmentedOnly(true)
        check("곡선창: '선분화된 것만 보기' 토글", cv.curvedShowsSegmentedOnly)
        cv.desegmentize(cv.selection.selected)
        check("곡선창: 선분화 해제도 된다", cv.segmentedCount == 0)

        check("곡선창: 곡선과 선분화된 곡선이 다른 색이다",
              CurvedAppearance.curvedAndSegmentedAreDistinct,
              "옅기 차이만으로는 무엇이 선분화됐는지 알 수 없다")

        cv.exitCurvedScreen()
        check("곡선창: 나가면 모드와 선택이 정리된다",
              !cv.showCurvedScreen && !cv.isCurvedOnlyMode && cv.selection.isEmpty,
              "선택을 남기면 메인 화면에서 곡선이 골라진 채로 시작해 잘못 태깅된다")

        let noCurve = AppEnvironment()
        noCurve.document = DrawingDocument(
            objects: doc.objects.filter { !$0.isCurved },
            canvasSize: doc.canvasSize, sourceName: "직선만")
        check("곡선창: 곡선이 없으면 열리지 않는다", !noCurve.canEnterCurvedScreen,
              "버튼을 눌러도 아무 일이 없으면 고장으로 읽힌다 — 비활성으로 두고 이유를 밝힌다")

        // MARK: 닫힌 다각형 보기 (신기능 5항, 2026-08-26)

        func faceEdge(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double,
                 _ id: VectorObjectID? = nil) -> ClosedPolygonFinder.SourceSegment {
            .init(segment: LineSegment(start: LocalPoint(ax, ay), end: LocalPoint(bx, by)),
                  objectID: id)
        }

        // 사각형 하나 — 가장 단순한 닫힌 면.
        let square = [faceEdge(0, 0, 100, 0), faceEdge(100, 0, 100, 100),
                      faceEdge(100, 100, 0, 100), faceEdge(0, 100, 0, 0)]
        let squareFaces = ClosedPolygonFinder.faces(in: square)
        check("닫힌 다각형: 사각형 하나를 면 하나로 찾는다",
              squareFaces.count == 1 && abs(squareFaces[0].area - 10_000) < 1,
              "면 \(squareFaces.count)개, 넓이 \(squareFaces.first.map { Int($0.area) } ?? 0)")
        check("닫힌 다각형: 바깥 면은 결과에 없다", squareFaces.count == 1,
              "같은 걸음 규칙으로 돌면 바깥 면은 넓이 부호가 뒤집힌다 — 그 부호로 걸러낸다")

        // 한 변이 끊긴 사각형 — 닫히지 않았으므로 면이 없어야 한다.
        let open = [faceEdge(0, 0, 100, 0), faceEdge(100, 0, 100, 100), faceEdge(100, 100, 0, 100)]
        check("닫힌 다각형: 한 변이 끊기면 면이 아니다",
              ClosedPolygonFinder.faces(in: open).isEmpty,
              "저장한 뒤에야 링이 열린 걸 알던 문제를 뒤집는 것이 이 기능의 목적이다")

        // 가운데 벽을 나눠 쓰는 방 둘 — 실제 도면의 기본 형태다.
        let twoRooms = square + [faceEdge(50, 0, 50, 100)]
        let roomFaces = ClosedPolygonFinder.faces(in: twoRooms)
        check("닫힌 다각형: 벽을 나눠 쓰는 방 둘을 따로 찾는다",
              roomFaces.count == 2 && roomFaces.allSatisfy { abs($0.area - 5_000) < 1 },
              "면 \(roomFaces.count)개 — 최소 순환을 따라가므로 바깥 사각형이 아니라 방 둘이 나온다")

        // 가로지르는 선은 교차점에서 잘려야 면이 성립한다.
        let crossed = [faceEdge(0, 50, 100, 50)] + square
        check("닫힌 다각형: 가로지르는 선은 교차점에서 잘린다",
              ClosedPolygonFinder.faces(in: crossed).count == 2,
              "자르지 않으면 두 면이 한 덩어리로 남아 방을 따로 고를 수 없다")

        // 실오라기 면 걸러내기.
        let sliver = [faceEdge(0, 0, 100, 0), faceEdge(100, 0, 100, 0.01),
                      faceEdge(100, 0.01, 0, 0.01), faceEdge(0, 0.01, 0, 0)]
        check("닫힌 다각형: 실오라기 면은 버린다",
              ClosedPolygonFinder.faces(in: sliver).isEmpty,
              "벽 두께 사이의 자투리까지 보여주면 고를 것이 수백 개로 불어난다")

        // 임시 문으로 닫힌 면은 그 사실을 표시한다.
        let doorClosedFace = [faceEdge(0, 0, 100, 0, doors[0].id), faceEdge(100, 0, 100, 100, doors[0].id),
                        faceEdge(100, 100, 0, 100, doors[0].id), faceEdge(0, 100, 0, 0, nil)]
        let doorFace = ClosedPolygonFinder.faces(in: doorClosedFace)
        check("닫힌 다각형: 임시 문으로 닫힌 면을 표시한다",
              doorFace.count == 1 && doorFace[0].usesTemporaryDoor
              && doorFace[0].memberIDs == [doors[0].id],
              "도면에 없는 선으로 닫힌 면이라는 것은 알고 고르는 편이 낫다")

        check("닫힌 다각형: 면 안쪽 점만 그 면에 속한다",
              squareFaces[0].contains(LocalPoint(50, 50))
              && !squareFaces[0].contains(LocalPoint(150, 50)))

        check("닫힌 다각형: 면·선·점이 서로 다른 색이다",
              ClosedPolygonAppearance.facesLinesPointsAreDistinct,
              "신기능 5-2: 면/선/점은 서로 다른 색으로 표시한다")

        // 면 묶기(5-4 2번) — 선분을 나눠 쓰는 면은 한 덩어리다.
        let sharedWall = square + [faceEdge(50, 0, 50, 100)]
        let sharedFaces = ClosedPolygonFinder.faces(in: sharedWall)
        check("면 묶기: 벽을 나눠 쓰는 두 면은 한 덩어리로 묶인다",
              ClosedPolygonFinder.connectedGroups(of: sharedFaces).count == 1,
              "fixture는 MultiPolygon이라 맞닿은 면이 한 feature다")

        let farApart = square + [faceEdge(300, 300, 400, 300), faceEdge(400, 300, 400, 400),
                              faceEdge(400, 400, 300, 400), faceEdge(300, 400, 300, 300)]
        let apartFaces = ClosedPolygonFinder.faces(in: farApart)
        check("면 묶기: 떨어진 면은 따로 묶인다",
              ClosedPolygonFinder.connectedGroups(of: apartFaces).count == 2)

        // 앱 경로 — 폴리곤 type 레이어에서의 작업(5-4 전환).
        let cp = AppEnvironment()
        cp.document = doc
        cp.selectPropertyType(.opening)
        check("다각형 작업: opening 레이어는 점 단위 편집이다", !cp.isPolygonWorkMode && cp.isPointWorkMode,
              "#21: 선분 단위 작업은 없앴다. LineString은 두 점을 찍는다")
        cp.declareOpeningComplete()
        cp.selectPropertyType(.unit)
        check("다각형 작업: unit 레이어도 기본은 점 단위다", cp.isPointWorkMode && !cp.isPolygonWorkMode,
              "#21: 모든 레이어의 기본은 점 단위 편집이다")
        // 면 단위는 도면 개체가 아니라 **저장된 개체의 경계로 막힌 면**만 고른다(2026-10-18).
        // 멀리 떨어진 자리에 unit 두 개(벽을 나눠 씀)와 opening 선 네 개(사각형)를 점으로 그려 둔다.
        let fo = 3_000_000.0
        func fp(_ x: Double, _ y: Double) -> LocalPoint { LocalPoint(fo + x, fo + y) }
        let ftol = 0.01
        func drawRing(_ env: AppEnvironment, _ pts: [LocalPoint]) {
            for p in pts { env.handlePointClick(at: p, tolerance: ftol, freePoint: true) }
            env.handlePointClick(at: pts[0], tolerance: ftol, freePoint: true)
        }
        func drawDoorSquare(_ env: AppEnvironment) {
            env.selectPropertyType(.opening)
            let c = [fp(300, 0), fp(400, 0), fp(400, 100), fp(300, 100)]
            for i in 0..<4 {
                env.handlePointClick(at: c[i], tolerance: ftol, freePoint: true)
                env.handlePointClick(at: c[(i + 1) % 4], tolerance: ftol, freePoint: true)
            }
        }
        drawRing(cp, [fp(0, 0), fp(100, 0), fp(100, 100), fp(0, 100)])
        drawRing(cp, [fp(100, 0), fp(200, 0), fp(200, 100), fp(100, 100)])
        drawDoorSquare(cp)
        cp.selectPropertyType(.unit)
        check("면 단위 준비: unit 두 개와 opening 선 네 개를 저장한다",
              cp.features.features(ofType: .unit).count == 2 && cp.features.features(ofType: .opening).count == 4)

        cp.setLayerEditMode(.face)
        check("다각형 작업: 면 단위로 바꾸면 면을 고르는 모드가 되고 안내가 뜬다",
              cp.isPolygonWorkMode
              && (cp.closedPolygonNotice?.contains("보조 개체 제외 창") ?? false)
              && (cp.closedPolygonNotice?.contains(IMDFFeatureType.unit.displayName) ?? false))
        check("면 단위: 현재 레이어 기준이 기본이고, 저장된 unit 경계로 막힌 면만 잡는다",
              cp.faceBoundaryScope == .currentLayer && cp.faceModeFaces.count == 2 && cp.selectableFaceCount == 0,
              "면 \(cp.faceModeFaces.count)개 — 이미 같은 모양으로 저장된 unit 둘은 다시 고를 수 없다. 도면 개체 면은 쓰지 않는다")
        cp.setFaceBoundaryScope(.allLayers)
        check("면 단위: 모든 레이어 기준이면 opening 선으로 막힌 면도 잡힌다",
              cp.faceModeFaces.count == 3 && cp.selectableFaceCount == 1)

        // 포함 모드: 빈 상태에서 더해 간다.
        check("다각형 작업: 포함 모드는 아무것도 고르지 않은 상태로 시작한다",
              cp.polygonWorkMode == .include && cp.faceSelection.isEmpty)

        // 제외 모드: 전부 고른 상태에서 빼 나간다.
        cp.setPolygonWorkMode(.exclude)
        check("다각형 작업: 제외 모드는 전부 고른 상태로 시작한다",
              cp.faceSelection.count == cp.selectableFaceCount && !cp.faceSelection.isEmpty,
              "저장할 것이 대부분일 때 훨씬 빠르다(5-4 2번)")
        cp.handleFaceClick(at: fp(350, 50))
        check("다각형 작업: 제외 모드에서 누르면 선택에서 빠진다", cp.faceSelection.isEmpty)
        cp.handleFaceClick(at: fp(50, 50))
        check("면 단위: 이미 저장된 면은 눌러도 고르지 않는다", cp.faceSelection.isEmpty)

        // 드래그 복수 선택(5-4 3번).
        cp.setPolygonWorkMode(.include)
        cp.handleFaceMarquee(rect: CGRect(x: fo - 1000, y: fo - 1000, width: 5000, height: 5000),
                             mode: .crossing)
        check("다각형 작업: 드래그로 여러 면을 한 번에 고른다",
              cp.faceSelection.count == cp.selectableFaceCount && cp.faceSelection.count == 1)

        // 저장.
        let unitsBefore = cp.features.features(ofType: .unit).count
        cp.saveSelectedFaces()
        let madeFromFace = cp.features.features(ofType: .unit).first { $0.polygonRings.first.map { ring in ring.contains(fp(300, 0)) } ?? false }
        check("다각형 작업: 고른 면이 Feature가 된다",
              cp.features.features(ofType: .unit).count == unitsBefore + 1 && cp.faceSelection.isEmpty && madeFromFace != nil)
        if let made = madeFromFace, let ring = made.polygonRings.first {
            check("다각형 작업: 좌표는 면의 링이 정본이다",
                  VertexExtractor.vertices(for: made, document: doc,
                                           segmentation: cp.segmentation, kind: .polygon) == ring)
            check("면 단위: 저장된 개체로 만든 면은 점으로 그린 도형처럼 꼭짓점 편집이 된다",
                  made.isPointDrawn && made.polygonFaceIDs.isEmpty)
            check("다각형 작업: 저장한 면은 다시 고를 수 없다", cp.selectableFaceCount == 0)
        }

        cp.undo()
        check("다각형 작업: 저장은 cmd+z로 되돌아간다",
              cp.features.features(ofType: .unit).count == unitsBefore && cp.faceSelection.count == 1,
              "되돌리면 고르던 것도 함께 돌아와야 '저장을 취소했다'가 성립한다")

        // fixture(MultiPolygon)는 맞닿은 면을 한 feature로 묶는다.
        let fx = AppEnvironment()
        fx.document = doc
        fx.selectPropertyType(.opening)
        fx.declareOpeningComplete()
        fx.selectPropertyType(.unit)
        drawRing(fx, [fp(0, 0), fp(100, 0), fp(100, 100), fp(0, 100)])
        drawRing(fx, [fp(100, 0), fp(200, 0), fp(200, 100), fp(100, 100)])
        drawDoorSquare(fx)
        fx.selectPropertyType(.fixture)
        fx.setLayerEditMode(.face)
        fx.setFaceBoundaryScope(.allLayers)
        fx.selectAllFaces()
        let fxFaceCount = fx.faceSelection.count
        fx.saveSelectedFaces()
        let fxFeatures = fx.features.features(ofType: .fixture)
        check("다각형 작업: fixture는 맞닿은 면을 한 feature로 묶는다",
              fxFaceCount == 3 && fxFeatures.count == 2
              && fxFeatures.contains { $0.polygonRings.count == 2 } && fxFeatures.contains { $0.polygonRings.count == 1 },
              "면 \(fxFaceCount)개 → feature \(fxFeatures.count)개")

        // 진행률 — 점 기준(#21). 다각형 막대(5-5-2)를 점 기준으로 바꿨다.
        let pr = AppEnvironment()
        pr.document = doc
        check("진행률: 점 분모는 도면을 열 때 센다",
              pr.totalPointCount > 0 && pr.totalPointCount == pr.snapPoints.count,
              "전체 점 \(pr.totalPointCount)개")
        check("진행률: 도면을 막 열면 처리된 점이 0이다",
              pr.taggedPointCount == 0 && pr.excludedPointCount == 0 && pr.pointProgressFraction == 0)
        let denominatorBefore = pr.totalPointCount
        pr.selectPropertyType(.opening)
        pr.declareOpeningComplete()
        pr.selectPropertyType(.unit)
        if let victim = doc.objects.first {
            pr.auxiliary.exclude([victim.id])
        }
        check("진행률: 보조 개체를 빼도 분모는 그대로다",
              pr.totalPointCount == denominatorBefore,
              "분모가 조작할 때마다 흔들리면 막대가 이유 없이 늘었다 줄었다 한다")
        check("진행률: 제외로 사라진 점이 분자에 들어간다",
              pr.excludedPointCount > 0 && pr.pointProgressFraction >= pr.taggedPointFraction,
              "제외된 점 \(pr.excludedPointCount)개")
        let prPool = pr.snapPoints.map(\.point)
        if let a = prPool.min(by: { $0.x < $1.x }), let b = prPool.max(by: { $0.x < $1.x }),
           let c = prPool.min(by: { $0.y < $1.y }), let d = prPool.max(by: { $0.y < $1.y }) {
            let quad = VertexExtractor.sortAroundCentroid(VertexExtractor.dedup([a, b, c, d], epsilon: 1))
            for p in quad { pr.handlePointClick(at: p, tolerance: 0.01, freePoint: false) }
            pr.handlePointClick(at: quad[0], tolerance: 0.01, freePoint: false)
        }
        pr.selectPropertyType(.fixture)
        pr.setLayerEditMode(.face)
        pr.setFaceBoundaryScope(.allLayers)
        pr.selectAllFaces()
        pr.saveSelectedFaces()
        let prFixture = pr.features.features(ofType: .fixture).first
        check("진행률: 면 단위로 저장해도 점 기준으로 센다",
              prFixture != nil && pr.taggedPointCount > 0 && pr.taggedPointFraction > 0
              && (prFixture?.polygonRings.first ?? []).allSatisfy { pr.snapPointIndex.index(at: $0) != nil },
              "태깅된 점 \(pr.taggedPointCount)개 / 전체 \(pr.totalPointCount)개 — 면의 꼭짓점이 도면 점 그대로다")

        let vp = AppEnvironment()
        vp.document = doc
        if let victim2 = doc.objects.first {
            let keyBefore = vp.derivedKey
            vp.enterAuxiliaryScreen()
            vp.auxiliarySelection = [victim2.id]
            vp.markSelectedAsAuxiliary()
            check("진행률: 제외 창 안에서는 셈을 미룬다",
                  vp.derivedKey == keyBefore && vp.excludedPointCount == 0,
                  "창이 떠 있는 동안 좌측 사이드바는 보이지 않는다 — 클릭마다 다시 셀 이유가 없다")
            vp.exitAuxiliaryScreen()
            let expected = try? DerivedGeometry.make(document: doc, key: vp.currentDerivedKey)
            check("진행률: 창을 닫을 때 제외된 점을 다시 센다",
                  vp.excludedPointCount == max(0, vp.totalPointCount - (expected?.snapPoints.count ?? -1))
                  && vp.excludedPointCount > 0,
                  "제외된 점 \(vp.excludedPointCount)개 / 전체 \(vp.totalPointCount)개")
        }

        // 큰 도면에서도 창이 열려야 한다. 자르기가 선분 수의 제곱에 붙어서,
        // 경계 상자로 걸러내지 않으면 여기서 멈춘다(`04) 엔진 디버깅.md` 1-1과 같은 자리).
        var gridWalls: [ClosedPolygonFinder.SourceSegment] = []
        for i in 0..<25 {
            let x = Double(i) * 40
            gridWalls.append(faceEdge(x, 0, x, 960))
        }
        for j in 0..<25 {
            let y = Double(j) * 40
            gridWalls.append(faceEdge(0, y, 960, y))
        }
        let gridStart = Date()
        let gridFaces = ClosedPolygonFinder.faces(in: gridWalls)
        let gridElapsed = Date().timeIntervalSince(gridStart)
        check("닫힌 다각형: 격자 도면(선 50개·면 576개)에서도 창이 열린다",
              gridElapsed < 3.0 && gridFaces.count == 576,
              String(format: "%.2f초, 면 %d개", gridElapsed, gridFaces.count))

        // MARK: #21 — 격자 자르기와 점 단위 편집 (2026-10-15)

        // 격자 자르기는 모든 쌍 비교와 **같은 결과**를 내야 한다. 비교 상대만 줄였을 뿐이다.
        var lcg: UInt64 = 0x2026_1015
        func rnd(_ range: Double) -> Double {
            lcg = lcg &* 6364136223846793005 &+ 1442695040888963407
            return Double(lcg >> 11) / Double(1 << 53) * range
        }
        var randomWalls: [ClosedPolygonFinder.SourceSegment] = []
        for _ in 0..<400 {
            let x = rnd(1000), y = rnd(1000)
            randomWalls.append(faceEdge(x, y, x + rnd(200) - 100, y + rnd(200) - 100))
        }
        randomWalls += gridWalls
        func pieceKey(_ s: ClosedPolygonFinder.SourceSegment) -> String {
            String(format: "%.9f,%.9f,%.9f,%.9f", s.segment.start.x, s.segment.start.y, s.segment.end.x, s.segment.end.y)
        }
        let byGrid = ClosedPolygonFinder.split(randomWalls).map(pieceKey)
        let byPairs = ClosedPolygonFinder.splitByAllPairs(randomWalls).map(pieceKey)
        check("#21 격자 자르기: 모든 쌍 비교와 조각이 같다", byGrid == byPairs,
              "조각 \(byGrid.count)개 / \(byPairs.count)개 — C5 실도면에서도 136,352개로 같았다")

        // 꼭짓점·교점도 격자로 비교 상대를 좁힌다. 모든 쌍 비교와 **점 목록이 같아야** 한다.
        let snapGrid = SnapPointExtractor.points(in: doc.objects, segmentation: SegmentationStore())
        let snapPairs = SnapPointExtractor.pointsByAllPairs(in: doc.objects, segmentation: SegmentationStore())
        check("#21 격자 교점: 샘플 도면에서 모든 쌍 비교와 같다", snapGrid == snapPairs,
              "점 \(snapGrid.count)개 / \(snapPairs.count)개")
        let curveSVG = """
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
        <path d="M 0 0 C 0 100 100 100 100 0" fill="none" stroke="#000"/>
        <line x1="-10" y1="50" x2="110" y2="50" stroke="#000"/>
        <line x1="50" y1="-10" x2="50" y2="120" stroke="#000"/>
        </svg>
        """
        if let curveDoc = try? SVGParser.parse(data: Data(curveSVG.utf8), sourceName: "curve.svg") {
            let cg = SnapPointExtractor.points(in: curveDoc.objects, segmentation: SegmentationStore())
            let cp = SnapPointExtractor.pointsByAllPairs(in: curveDoc.objects, segmentation: SegmentationStore())
            let onCurve = cg.filter { $0.kind == .crossing && abs($0.point.y - 50) < 0.5 && $0.point.x < 45 }
            check("#21 격자 교점: 곡선이 기준점 상자 밖으로 나간 자리의 교차도 찾는다",
                  cg == cp && !onCurve.isEmpty,
                  "점 \(cg.count)개 — 곡선 위 교차 \(onCurve.count)개. 개체 상자는 기준점만 담아 예전에는 놓쳤다")
        } else {
            check("#21 격자 교점: 곡선 검사 도면을 읽는다", false)
        }

        // 점 단위 편집 — unit(폴리곤).
        let pe = AppEnvironment()
        pe.document = doc
        pe.selectPropertyType(.opening)
        pe.declareOpeningComplete()
        pe.selectPropertyType(.unit)
        let tol = 0.01
        let pool = pe.snapPoints.map(\.point)
        if let a = pool.min(by: { $0.x < $1.x }), let b = pool.max(by: { $0.x < $1.x }),
           let c = pool.min(by: { $0.y < $1.y }), let d = pool.max(by: { $0.y < $1.y }) {
            let quad = VertexExtractor.sortAroundCentroid(VertexExtractor.dedup([a, b, c, d], epsilon: 1))
            for p in quad.dropLast() { pe.handlePointClick(at: p, tolerance: tol, freePoint: false) }
            check("#21 점 편집: 꼭짓점·교점을 순서대로 찍는다",
                  pe.pointDraft.points.count == quad.count - 1 && pe.features.features(ofType: .unit).isEmpty,
                  "미완성 도형은 feature가 되지 않는다")
            pe.undo()
            check("#21 점 편집: 점 추가는 cmd+z로 되돌아간다", pe.pointDraft.points.count == quad.count - 2)
            pe.redo()
            pe.handlePointClick(at: quad.last!, tolerance: tol, freePoint: false)
            pe.handlePointClick(at: quad[0], tolerance: tol, freePoint: false)
            let units = pe.features.features(ofType: .unit)
            check("#21 점 편집: 시작점을 다시 누르면 닫히고 저장된다",
                  units.count == 1 && pe.pointDraft.isEmpty && units[0].polygonRings.first?.count == quad.count)
            if let u = units.first {
                check("#21 점 편집: DraftShape는 원본 개체와 독립이다",
                      u.memberIDs.isEmpty && u.isPointDrawn && pe.ownership.claimedCount == 0)
                check("#21 점 편집: 좌표는 찍은 점이 정본이다",
                      VertexExtractor.vertices(for: u, document: doc, segmentation: pe.segmentation, kind: .polygon)
                          == u.polygonRings[0])
                check("#21 점 편집: 점으로 닫은 도형은 링 열림 경고가 없다", pe.ringClosure(of: u) == nil)
                check("#21 진행률: 점으로 그린 도형의 꼭짓점이 태깅된 점이 된다",
                      pe.taggedPointCount == quad.count, "\(pe.taggedPointCount)개")

                // 꼭짓점 이동·고정.
                pe.isVertexMoveEnabled = false
                pe.beginVertexDrag(.feature(u.id, ring: 0, index: 0), at: quad[0])
                check("#21 꼭짓점: 고정 모드에서는 끌 수 없다", pe.vertexDrag == nil)
                pe.isVertexMoveEnabled = true
                check("#21 꼭짓점: 이동 모드에서 저장된 꼭짓점을 잡는다",
                      pe.vertexHit(at: quad[0], tolerance: tol) == .feature(u.id, ring: 0, index: 0))
                let moved = LocalPoint(quad[0].x - 0.5, quad[0].y)
                pe.beginVertexDrag(.feature(u.id, ring: 0, index: 0), at: quad[0])
                pe.updateVertexDrag(to: moved, tolerance: 0.0001, freePoint: true)
                pe.endVertexDrag()
                check("#21 꼭짓점: 끌어 놓으면 좌표가 바뀐다",
                      pe.features.feature(u.id)?.polygonRings[0][0] == moved)
                pe.undo()
                check("#21 꼭짓점: 이동은 cmd+z로 되돌아간다",
                      pe.features.feature(u.id)?.polygonRings[0][0] == quad[0])
                pe.isVertexMoveEnabled = false
            }
        }

        // 꼭짓점을 옮겨 도형이 꼬이면 반영하지 않는다. 도면과 겹치지 않는 먼 자리에 새 점(⌥)으로 정사각형을 그린다.
        let far = 1_000_000.0
        let drawnSquare = [(0.0, 0.0), (100.0, 0.0), (100.0, 100.0), (0.0, 100.0)].map { LocalPoint(far + $0.0, far + $0.1) }
        for p in drawnSquare { pe.handlePointClick(at: p, tolerance: tol, freePoint: true) }
        pe.handlePointClick(at: drawnSquare[0], tolerance: tol, freePoint: true)
        if let sq = pe.features.features(ofType: .unit).first(where: { $0.polygonRings.first == drawnSquare }) {
            pe.isVertexMoveEnabled = true
            pe.beginVertexDrag(.feature(sq.id, ring: 0, index: 0), at: drawnSquare[0])
            pe.updateVertexDrag(to: LocalPoint(far + 150, far + 50), tolerance: tol, freePoint: true)
            pe.endVertexDrag()
            check("#21 꼭짓점: 옮겨서 도형이 꼬이면 반영하지 않는다",
                  pe.features.feature(sq.id)?.polygonRings.first == drawnSquare)
            pe.isVertexMoveEnabled = false
        } else {
            check("#21 꼭짓점: 검사용 정사각형을 새 점으로 그린다", false)
        }

        // 자기 교차(나비넥타이) 도형은 확정하지 않는다.
        for (x, y) in [(0.0, 0.0), (100.0, 100.0), (100.0, 0.0), (0.0, 100.0)] {
            pe.handlePointClick(at: LocalPoint(far + x, far + y), tolerance: tol, freePoint: true)
        }
        let unitCountBefore = pe.features.features(ofType: .unit).count
        pe.closePointDraft()
        check("#21 점 편집: 자기 교차 도형은 확정하지 않는다",
              pe.features.features(ofType: .unit).count == unitCountBefore && pe.pointDraft.points.count == 4,
              "변끼리 X자로 가로지르면 경고만 띄우고 작성 중 상태를 유지한다")
        check("#21 점 편집: 꼭짓점·교점이 아닌 자리는 ⌥ 없이 찍히지 않는다", { () -> Bool in
            let before = pe.pointDraft.points.count
            pe.handlePointClick(at: LocalPoint(far + 500, far + 500), tolerance: tol, freePoint: false)
            return pe.pointDraft.points.count == before
        }())
        let keys = PointKeyMonitor(env: pe)
        check("#21 키보드: Delete는 마지막 점을 지운다",
              keys.handle(keyCode: 51) && pe.pointDraft.points.count == 3)
        check("#21 키보드: 글자 입력 중에는 Delete를 가로채지 않는다",
              !keys.handle(keyCode: 51, textIsEditing: true) && pe.pointDraft.points.count == 3)
        check("#21 키보드: ESC는 작성 중인 도형을 취소한다",
              keys.handle(keyCode: 53) && pe.pointDraft.isEmpty)
        pe.undo()
        check("#21 점 편집: ESC 취소도 cmd+z로 되살아난다", pe.pointDraft.points.count == 3)

        // 개체 편집(엔진 디버깅 5번) — Control 클릭으로 빠진 순번 자리에 새 점을 끼운다.
        pe.cancelPointDraft()
        func at(_ x: Double, _ y: Double) -> LocalPoint { LocalPoint(far + 2000 + x, far + y) }
        let hex = [at(0, 0), at(100, 0), at(200, 0), at(200, 100), at(100, 100), at(0, 100)]
        for p in hex { pe.handlePointClick(at: p, tolerance: tol, freePoint: true) }
        func ctrl(_ p: LocalPoint) { pe.handlePointClick(at: p, tolerance: tol, freePoint: true, editing: true) }
        func releaseControl() { keys.handleFlags(.control); keys.handleFlags([]) }
        // 실제 입력처럼 Control을 눌렀다 뗀다. 떼는 순간에만 편집이 끝난다.
        ctrl(hex[3])
        check("개체 편집: Control로 4번 점을 누르면 4·5·6번이 흐려진다",
              pe.pointDraft.edit != nil && (3...5).allSatisfy(pe.pointDraft.isDimmed) && !pe.pointDraft.isDimmed(2))
        let a = at(250, 50)
        ctrl(a)
        ctrl(hex[4])
        check("개체 편집: 4번을 빼고 a를 찍은 뒤 5번을 누르면 a가 새 4번이 된다",
              pe.pointDraft.points == [hex[0], hex[1], hex[2], a, hex[4], hex[5]] &&
              pe.pointDraft.edit == nil && pe.pointDraft.breaks.isEmpty)
        let b = at(150, 150)
        ctrl(a); ctrl(a); ctrl(b); ctrl(hex[4])
        check("개체 편집: 4번을 두 번 누르고 b, 5번을 누르면 4번과 5번 사이에 끼운다",
              pe.pointDraft.points == [hex[0], hex[1], hex[2], a, b, hex[4], hex[5]] && pe.pointDraft.edit == nil)
        pe.undo()
        check("개체 편집: 끼우기는 cmd+z로 되돌아간다",
              pe.pointDraft.points == [hex[0], hex[1], hex[2], a, b, hex[4], hex[5]] && pe.pointDraft.edit?.insertedCount == 1)
        pe.redo()
        let c = at(50, 150)
        ctrl(hex[5]); ctrl(c)
        releaseControl()
        let unitsBeforeBroken = pe.features.features(ofType: .unit).count
        pe.handlePointClick(at: hex[0], tolerance: tol, freePoint: true)
        check("개체 편집: 잇지 않고 Control을 떼면 선분이 끊기고 폴리곤으로 닫히지 않는다",
              pe.pointDraft.edit == nil && pe.pointDraft.breaks == [6] &&
              pe.features.features(ofType: .unit).count == unitsBeforeBroken)
        ctrl(hex[5]); ctrl(hex[5])
        check("개체 편집: 끊긴 뒤쪽 점을 Control로 두 번 누르면 다시 이어진다",
              pe.pointDraft.breaks.isEmpty && pe.pointDraft.edit == nil &&
              pe.pointDraft.points == [hex[0], hex[1], hex[2], a, b, hex[4], c, hex[5]])
        ctrl(hex[1])
        releaseControl()
        check("개체 편집: 아무것도 바꾸지 않고 Control을 떼면 그대로 둔다",
              pe.pointDraft.edit == nil && pe.pointDraft.breaks.isEmpty && pe.pointDraft.points.count == 8)
        pe.handlePointClick(at: hex[0], tolerance: tol, freePoint: true)
        check("개체 편집: 고친 순서대로 꼬임 없이 닫혀 저장된다",
              pe.features.features(ofType: .unit).count == unitsBeforeBroken + 1 && pe.pointDraft.isEmpty &&
              pe.features.features(ofType: .unit).contains { $0.polygonRings.first == [hex[0], hex[1], hex[2], a, b, hex[4], c, hex[5]] })

        // 저장된 도형도 같은 방식으로 고친다.
        let editedRing = [hex[0], hex[1], hex[2], a, b, hex[4], c, hex[5]]
        if let saved = pe.features.features(ofType: .unit).first(where: { $0.polygonRings.first == editedRing }) {
            ctrl(b)
            check("개체 편집: 저장된 도형 꼭짓점을 Control로 누르면 그 링을 꺼내 5번부터 흐린다",
                  pe.pointDraft.source == PointDraftSource(featureID: saved.id, ring: 0) &&
                  pe.pointDraft.points == editedRing && (4...7).allSatisfy(pe.pointDraft.isDimmed))
            let d = at(150, 170)
            ctrl(d); ctrl(hex[4])
            releaseControl()
            check("개체 편집: 저장된 도형은 이어진 채 Control을 떼면 링이 바뀐다",
                  pe.features.feature(saved.id)?.polygonRings.first == [hex[0], hex[1], hex[2], a, d, hex[4], c, hex[5]] &&
                  pe.pointDraft.isEmpty && pe.features.features(ofType: .unit).count == unitsBeforeBroken + 1,
                  "링 \(pe.features.feature(saved.id)?.polygonRings.first?.count ?? -1)점 · 작성 중 \(pe.pointDraft.points.count)점 · \(pe.banner?.text ?? "")")
            pe.undo()
            check("개체 편집: 저장된 도형 고치기는 cmd+z로 되돌아간다",
                  pe.features.feature(saved.id)?.polygonRings.first == editedRing)
            pe.cancelPointDraft()
            ctrl(hex[1]); ctrl(at(100, -50))
            _ = keys.handle(keyCode: 53)
            check("개체 편집: 저장된 도형 편집을 ESC로 취소하면 원래 도형이 그대로다",
                  pe.pointDraft.isEmpty && pe.features.feature(saved.id)?.polygonRings.first == editedRing)
            ctrl(hex[1])
            releaseControl()
            check("개체 편집: 저장된 도형을 바꾼 것 없이 떼면 그냥 닫힌다",
                  pe.pointDraft.isEmpty && pe.features.feature(saved.id)?.polygonRings.first == editedRing)
        } else {
            check("개체 편집: 고친 도형을 찾는다", false)
        }

        // MultiPolygon 지정 — 감싸면 기존이 구멍, 안쪽이면 새 것이 구멍.
        pe.cancelPointDraft()
        func mp(_ x: Double, _ y: Double) -> LocalPoint { LocalPoint(far + 5000 + x, far + y) }
        func mpSquare(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [LocalPoint] {
            [mp(x0, y0), mp(x1, y0), mp(x1, y1), mp(x0, y1)]
        }
        func drawSquare(_ pts: [LocalPoint]) {
            for p in pts { pe.handlePointClick(at: p, tolerance: tol, freePoint: true) }
            pe.handlePointClick(at: pts[0], tolerance: tol, freePoint: true)
        }
        let mpRoom = mpSquare(0, 0, 100, 100)
        drawSquare(mpRoom)
        if let unit = pe.features.features(ofType: .unit).first(where: { $0.polygonRings == [mpRoom] }) {
            check("MultiPolygon: 저장한 unit 다각형을 지정할 수 있다", pe.canDesignateMultiPolygon(unit) && !unit.isMultiPolygon)
            pe.designateMultiPolygon(unit.id)
            let beforeDesignatedDraw = pe.features.features(ofType: .unit).count
            drawSquare(mpSquare(-300, 0, -200, 100))
            check("MultiPolygon: 지정만 하고 '다각형 추가'를 안 누르면 새 다각형은 새 feature가 된다",
                  pe.multiPolygonTargetID == nil && pe.features.feature(unit.id)!.polygonRings.count == 1
                      && pe.features.features(ofType: .unit).count == beforeDesignatedDraw + 1)
            pe.startMultiPolygonAdding(unit.id)
            drawSquare(mpSquare(-50, -50, 150, 150))
            var u = pe.features.feature(unit.id)!
            check("MultiPolygon: 기존 다각형을 감싸면 기존 다각형이 구멍이 된다",
                  u.isMultiPolygon && u.polygonRings.count == 2 && pe.multiPolygonSummary(u) == (1, 1) &&
                  pe.features.features(ofType: .unit).count == unitsBeforeBroken + 3)
            drawSquare(mpSquare(300, 0, 400, 100))
            drawSquare(mpSquare(325, 25, 375, 75))
            u = pe.features.feature(unit.id)!
            check("MultiPolygon: 떨어진 다각형은 다각형으로, 기존 다각형 안쪽은 구멍으로 더해진다",
                  u.polygonRings.count == 4 && pe.multiPolygonSummary(u) == (2, 2))
            let structure = RingNesting.polygons(u.polygonRings)
            check("MultiPolygon: 내보낼 때 바깥 다각형마다 바로 안쪽 구멍이 붙는다",
                  structure.count == 2 && structure.allSatisfy { $0.holes.count == 1 } &&
                  structure.contains { $0.outer == 1 && $0.holes == [0] } && structure.contains { $0.outer == 2 && $0.holes == [3] })
            pe.undo()
            check("MultiPolygon: 다각형 추가는 cmd+z로 되돌아간다", pe.features.feature(unit.id)!.polygonRings.count == 3)
            pe.redo()
            drawSquare(mpSquare(350, 50, 450, 150))
            check("MultiPolygon: 기존 다각형과 어긋나게 겹치면 받지 않는다",
                  pe.features.feature(unit.id)!.polygonRings.count == 4 && !pe.pointDraft.isEmpty)
            pe.cancelPointDraft()
            pe.releaseMultiPolygon(unit.id)
            check("MultiPolygon: 다각형이 여럿이면 Polygon으로 되돌리지 않는다", pe.features.feature(unit.id)!.multiPolygon == true)
            pe.finishMultiPolygonAdding()
            let before = pe.features.features(ofType: .unit).count
            drawSquare(mpSquare(600, 0, 700, 100))
            check("MultiPolygon: 추가를 끝내면 새 다각형은 새 feature가 된다",
                  pe.features.features(ofType: .unit).count == before + 1 && pe.features.feature(unit.id)!.polygonRings.count == 4)
            check("MultiPolygon: 점 단위 type이 아니면 지정할 수 없다",
                  !pe.canDesignateMultiPolygon(FeatureGroup(featureType: .opening, serialNumber: "o", memberIDs: [])))
        } else {
            check("MultiPolygon: 검사용 unit을 그린다", false)
        }

        // 이미 개체로 저장된 점도 다시 골라 새 개체를 만든다. 옆 unit과 같은 꼭짓점을 써야 틈·겹침이 없다.
        pe.cancelPointDraft()
        pe.finishMultiPolygonAdding()
        let left = mpSquare(1000, 0, 1100, 100)
        drawSquare(left)
        // ⌥로 만든 점이라 도면의 꼭짓점·교점 목록에는 없다.
        let nearCorner = LocalPoint(left[1].x + tol * 0.5, left[1].y + tol * 0.5)
        pe.handlePointClick(at: nearCorner, tolerance: tol, freePoint: false)
        check("저장된 점 재선택: 저장된 개체의 꼭짓점은 ⌥ 없이도 그 좌표 그대로 찍힌다",
              pe.pointDraft.points == [left[1]], "도면 점이 아닌 꼭짓점이라 예전에는 '꼭짓점·교점이 아닌 자리'로 막혔다")
        let unitCountBeforeRight = pe.features.features(ofType: .unit).count
        pe.handlePointClick(at: mpSquare(1200, 0, 1200, 0)[0], tolerance: tol, freePoint: true)
        pe.handlePointClick(at: mpSquare(1200, 100, 1200, 100)[0], tolerance: tol, freePoint: true)
        pe.handlePointClick(at: left[2], tolerance: tol, freePoint: false)
        pe.handlePointClick(at: left[1], tolerance: tol, freePoint: false)
        let right = pe.features.features(ofType: .unit).first { $0.polygonRings.first?.contains(left[2]) == true && $0.polygonRings.first?.count == 4 && $0.polygonRings.first != left }
        check("저장된 점 재선택: 옆 unit의 두 꼭짓점을 공유하는 새 unit이 저장된다",
              pe.features.features(ofType: .unit).count == unitCountBeforeRight + 1 &&
              right?.polygonRings.first?.contains(left[1]) == true &&
              right.map { RingNesting.relation($0.polygonRings[0], to: left) == .disjoint } == true,
              "공유한 변에서 맞닿기만 하고 겹치지 않는다")

        // opening — 두 점 선분(#37).
        let ow = AppEnvironment()
        ow.document = doc
        ow.selectPropertyType(.opening)
        if ow.snapPoints.count >= 2 {
            let keyBefore = ow.currentDerivedKey
            let p0 = ow.snapPoints[0].point
            let p1 = ow.snapPoints.max(by: { $0.point.distance(to: p0) < $1.point.distance(to: p0) })!.point
            ow.handlePointClick(at: p0, tolerance: tol, freePoint: false)
            check("#21 opening: 첫 점만으로는 저장하지 않는다",
                  ow.features.features(ofType: .opening).isEmpty && ow.pointDraft.points.count == 1)
            ow.handlePointClick(at: p1, tolerance: tol, freePoint: false)
            let opening = ow.features.features(ofType: .opening).first
            check("#21 opening: 두 점을 찍으면 바로 선으로 저장된다",
                  opening?.drawnVertices == [p0, p1] && ow.pointDraft.isEmpty && opening?.memberIDs.isEmpty == true)
            if let opening {
                check("#21 opening: 좌표는 찍은 두 점이다",
                      VertexExtractor.vertices(for: opening, document: doc, segmentation: ow.segmentation,
                                               kind: .lineString) == [p0, p1])
                check("opening 저장은 점·면을 다시 계산하지 않는다",
                      ow.currentDerivedKey == keyBefore && !ow.isComputingDerivedGeometry,
                      "엔진 디버깅 7번: 열쇠에 opening 선이 있으면 저장마다 도면 전체를 다시 계산한다")
            }
        }

        // amenity — 점 하나.
        ow.declareOpeningComplete()
        ow.selectPropertyType(.amenity)
        if let p = ow.snapPoints.first?.point {
            ow.handlePointClick(at: p, tolerance: tol, freePoint: false)
            let amenity = ow.features.features(ofType: .amenity).first
            check("#21 amenity: 점 하나를 찍으면 바로 저장된다", amenity?.drawnVertices == [p])
            if let amenity {
                check("#21 amenity: Point 좌표는 찍은 점이다",
                      VertexExtractor.vertices(for: amenity, document: doc, segmentation: ow.segmentation,
                                               kind: .point) == [p])
                check("amenity: 찍자마자 그 feature를 고르고 category·name 창을 요청한다",
                      ow.focusedFeature == amenity.id && ow.tagEditorRequest == amenity.id)
            }
        }

        // footprint는 면 단위 대상이 아니다.
        ow.selectPropertyType(.footprint)
        ow.setLayerEditMode(.face)
        check("#21 footprint: 면 단위 선택을 쓸 수 없다",
              !IMDFFeatureType.footprint.allowsFaceSelection && ow.layerEditMode == .point
              && !ow.isPolygonWorkMode && ow.isPointWorkMode)
        check("#21 면 단위: polygon·multipolygon type만 허용한다",
              IMDFFeatureType.unit.allowsFaceSelection && IMDFFeatureType.fixture.allowsFaceSelection
              && !IMDFFeatureType.opening.allowsFaceSelection && !IMDFFeatureType.amenity.allowsFaceSelection)

        // 저장 형식 — 점 좌표는 선택적 필드라 이전 파일도 읽힌다.
        if let saved = ow.features.features(ofType: .amenity).first,
           let data = try? JSONEncoder().encode(saved),
           var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let round = try? JSONDecoder().decode(FeatureGroup.self, from: data)
            check("#21 저장: 점으로 그린 좌표가 왕복 보존된다", round?.drawnVertices == saved.drawnVertices)
            json.removeValue(forKey: "drawnVertices")
            let legacy = (try? JSONSerialization.data(withJSONObject: json))
                .flatMap { try? JSONDecoder().decode(FeatureGroup.self, from: $0) }
            check("#21 저장: 이 필드가 없는 이전 파일도 읽힌다", legacy != nil && legacy?.drawnVertices == nil)
        }

        // MARK: fixture — 똑같이 생긴 개체에 같은 태깅 (2026-10-18 요청)

        // 같은 모양의 가구 셋(쌍둥이)과 크기가 다른 하나. 하나를 점으로 그리면 나머지 둘 자리에도 같은 fixture를 둔다.
        func fixtureRect(_ x: Double, _ y: Double, _ w: Double, _ ord: Int) -> VectorObject {
            VectorObject(id: UUID(),
                         geometry: PathGeometry(subpaths: [Subpath(
                            start: LocalPoint(x, y),
                            segments: [.line(to: LocalPoint(x + w, y)), .line(to: LocalPoint(x + w, y + 6)),
                                       .line(to: LocalPoint(x, y + 6))],
                            isClosed: true)]),
                         style: .default, sourceElement: "rect", ordinal: ord)
        }
        let tw = AppEnvironment()
        tw.document = DrawingDocument(objects: [fixtureRect(0, 0, 10, 0), fixtureRect(50, 0, 10, 1),
                                                fixtureRect(0, 40, 10, 2), fixtureRect(50, 40, 12, 3)],
                                      canvasSize: CGSize(width: 100, height: 100), sourceName: "fixture 쌍둥이")
        tw.declareOpeningComplete()
        tw.selectPropertyType(.fixture)
        let corners = [LocalPoint(0, 0), LocalPoint(10, 0), LocalPoint(10, 6), LocalPoint(0, 6)]
        func drawFixture() {
            for p in corners { tw.handlePointClick(at: p, tolerance: 0.01, freePoint: false) }
            tw.handlePointClick(at: corners[0], tolerance: 0.01, freePoint: false)
        }
        tw.handlePointClick(at: corners[0], tolerance: 0.01, freePoint: false)
        check("fixture 쌍둥이: 점 하나만 찍어도 똑같이 생긴 자리를 보여 준다",
              tw.draftFixtureTwins.count == 2, "\(tw.draftFixtureTwins.count)곳 — 크기가 다른 개체는 빠진다")
        tw.cancelPointDraft()

        tw.savesFixtureTwins = true
        drawFixture()
        let together = tw.features.features(ofType: .fixture)
        let movedStarts = Set(together.compactMap { $0.polygonRings.first?.first })
        check("fixture 쌍둥이: 닫을 때 함께 저장하면 자리마다 개별 Polygon fixture가 생긴다",
              together.count == 3 && together.allSatisfy { $0.polygonRings.count == 1 }
              && movedStarts == [LocalPoint(0, 0), LocalPoint(50, 0), LocalPoint(0, 40)],
              "fixture \(together.count)개")
        tw.undo()
        check("fixture 쌍둥이: 실행취소 한 번에 함께 저장한 것이 모두 사라진다",
              tw.features.features(ofType: .fixture).isEmpty)

        tw.savesFixtureTwins = false
        drawFixture()
        check("fixture 쌍둥이: 함께 저장을 끄면 그린 것 하나만 저장된다", tw.features.features(ofType: .fixture).count == 1)
        if let base = tw.features.features(ofType: .fixture).first {
            check("fixture 쌍둥이: 저장한 카드에서도 똑같이 생긴 자리를 찾는다", tw.fixtureTwinPlacements(of: base).count == 2)
            tw.updateProperty("category", value: .string("toilet"), in: base.id)
            tw.applyTaggingToFixtureTwins(base.id)
            let tagged = tw.features.features(ofType: .fixture)
            check("fixture 쌍둥이: 같은 태깅으로 저장하면 속성까지 같은 fixture가 자리마다 생긴다",
                  tagged.count == 3 && tagged.allSatisfy { $0.value("category") == .string("toilet") })
            tw.updateProperty("category", value: .string("sink"), in: base.id)
            tw.applyTaggingToFixtureTwins(base.id)
            let retagged = tw.features.features(ofType: .fixture)
            check("fixture 쌍둥이: 다시 누르면 새로 만들지 않고 이미 저장된 자리의 속성만 맞춘다",
                  retagged.count == 3 && retagged.allSatisfy { $0.value("category") == .string("sink") })
        }

        // 개체 하나(점 두 개)만 맞는 자리는 쌍둥이가 아니다(2026-10-19). 책상 모서리에 의자 선이 붙은 묶음을
        // 그대로 옮긴 자리(아래 80)만 받고, 책상만 같고 의자가 딴 데 붙은 자리(아래 40)는 빼야 한다.
        func chairLine(_ x: Double, _ y: Double, _ ord: Int) -> VectorObject {
            VectorObject(id: UUID(),
                         geometry: PathGeometry(subpaths: [Subpath(start: LocalPoint(x, y),
                                                                   segments: [.line(to: LocalPoint(x + 2, y - 3))],
                                                                   isClosed: false)]),
                         style: .default, sourceElement: "line", ordinal: ord)
        }
        let fxPair = AppEnvironment()
        fxPair.document = DrawingDocument(objects: [fixtureRect(0, 0, 10, 0), chairLine(10, 0, 1),
                                                fixtureRect(0, 40, 10, 2), chairLine(10, 46, 3),
                                                fixtureRect(0, 80, 10, 4), chairLine(10, 80, 5)],
                                      canvasSize: CGSize(width: 100, height: 100), sourceName: "fixture 묶음 비교")
        let deskEdge = fxPair.fixtureTwinPlacements(for: [LocalPoint(0, 0), LocalPoint(10, 0)])
        check("fixture 쌍둥이: 점을 만든 개체가 모두 같은 만큼 옮겨진 자리만 쌍둥이다",
              deskEdge.map { LocalPoint($0.dx, $0.dy) } == [LocalPoint(0, 80)],
              deskEdge.map { "(\($0.dx), \($0.dy))" }.joined(separator: " ") + " — 의자 선이 다른 데 붙은 (0, 40)은 빠져야 한다")

        // MARK: unit — 펼친 unit과 겹치는 unit 빨강, 이름표로 구멍 뚫기 (2026-10-18 요청)

        let uo = AppEnvironment()
        uo.document = tw.document
        uo.declareOpeningComplete()
        uo.selectPropertyType(.unit)
        func unitSquare(_ serial: String, _ x: Double, _ y: Double, _ w: Double) -> FeatureGroup {
            var f = FeatureGroup(featureType: .unit, serialNumber: serial, memberIDs: [])
            f.polygonRings = [[LocalPoint(x, y), LocalPoint(x + w, y), LocalPoint(x + w, y + w), LocalPoint(x, y + w)]]
            return f
        }
        let hall = unitSquare("unit-901", 0, 0, 100)
        let inner = unitSquare("unit-902", 20, 20, 20)
        let straddle = unitSquare("unit-903", 90, 40, 30)
        let neighbor = unitSquare("unit-904", 100, 0, 30)
        for f in [hall, inner, straddle, neighbor] { uo.features.insert(f) }
        uo.expandedFeature = hall.id
        check("unit 겹침: 펼친 unit과 넓이 있게 겹치는 unit만 빨강 대상이다",
              uo.unitsOverlappingExpanded == [inner.id, straddle.id],
              "벽만 맞닿은 unit-904는 겹친 것이 아니다")
        check("unit 겹침: MultiPolygon이 아니면 이름표를 눌러도 구멍을 뚫지 않는다",
              uo.handleFeatureTagClick(inner.id) && uo.features.feature(hall.id)?.polygonRings.count == 1)
        uo.designateMultiPolygon(hall.id)
        _ = uo.handleFeatureTagClick(inner.id)
        let holed = uo.features.feature(hall.id)
        check("unit 겹침: 통째로 안쪽인 unit 이름표를 누르면 그 모양 그대로 구멍이 된다",
              holed?.polygonRings.count == 2 && holed?.polygonRings.last == inner.polygonRings[0]
              && holed.map { uo.multiPolygonSummary($0).holes } == 1)
        _ = uo.handleFeatureTagClick(straddle.id)
        let cut = uo.features.feature(hall.id)
        check("unit 겹침: 걸친 unit 이름표를 누르면 겹친 만큼 깎여 더는 겹치지 않는다",
              cut.map { AppEnvironment.overlapArea($0.polygonRings, straddle.polygonRings) < UnitCoverage.minimumArea } == true
              && cut.map { abs(UnitCoverage.area(UnitCoverage.path($0.polygonRings)) - (10_000 - 400 - 300)) < 1e-9 } == true
              && uo.unitsOverlappingExpanded.isEmpty,
              "넓이 \(cut.map { UnitCoverage.area(UnitCoverage.path($0.polygonRings)) } ?? -1)")
        let expandedBeforeTag = uo.expandedFeature
        check("unit 겹침: 겹치지 않은 unit의 이름표는 구멍을 뚫지 않고 그 unit을 고른다",
              uo.handleFeatureTagClick(neighbor.id) && uo.expandedFeature == neighbor.id
              && uo.features.feature(neighbor.id)?.polygonRings == neighbor.polygonRings)
        uo.expandedFeature = expandedBeforeTag
        // 2026-10-18 요청으로 바뀐 동작이다. 예전에는 클릭을 점 찍기로 넘겼다.
        uo.undo(); uo.undo()
        check("unit 겹침: 실행취소로 구멍 뚫기를 하나씩 되돌린다",
              uo.features.feature(hall.id)?.polygonRings == hall.polygonRings)

        // MARK: unit — level 기준 면, 보조 선분·자르기·점 끼우기 (2026-10-18 요청)

        func rectRing(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [LocalPoint] {
            [LocalPoint(x0, y0), LocalPoint(x1, y0), LocalPoint(x1, y1), LocalPoint(x0, y1)]
        }
        func levelEnv(level: [LocalPoint], units: [[LocalPoint]]) -> AppEnvironment {
            let e = AppEnvironment()
            e.document = tw.document
            e.declareOpeningComplete()
            for (i, ring) in ([level] + units).enumerated() {
                var f = FeatureGroup(featureType: i == 0 ? .level : .unit,
                                     serialNumber: i == 0 ? "level-001" : String(format: "unit-%03d", 900 + i), memberIDs: [])
                f.polygonRings = [ring]
                e.features.insert(f)
            }
            e.selectPropertyType(.unit)
            e.setLayerEditMode(.face)
            e.setFaceBoundaryScope(.level)
            return e
        }
        let lv = levelEnv(level: rectRing(0, 0, 300, 100), units: [rectRing(0, 0, 100, 100), rectRing(200, 0, 300, 100)])
        check("level 기준: unit 레이어에서만 고를 수 있는 기준이다",
              FaceBoundaryScope.options(for: .unit).contains(.level) && !FaceBoundaryScope.options(for: .fixture).contains(.level))
        check("level 기준: level 안에서 unit이 덮지 않은 곳만 면으로 잡힌다",
              lv.faceModeFaces.count == 1 && abs((lv.faceModeFaces.first?.area ?? 0) - 10_000) < 1e-6,
              "면 \(lv.faceModeFaces.count)개")
        lv.handleFaceClick(at: LocalPoint(150, 50))
        lv.saveSelectedFaces()
        check("level 기준: 고른 빈틈을 저장하면 unit이 level을 빈틈없이 덮는다",
              lv.features.features(ofType: .unit).count == 3 && lv.unitCoverage.gaps.isEmpty
              && lv.unitCoverage.overlaps.isEmpty && lv.faceModeFaces.isEmpty)

        let island = levelEnv(level: rectRing(0, 0, 300, 300), units: [rectRing(100, 100, 200, 200)])
        let ring = island.faceModeFaces.first
        check("level 기준: 안쪽에 떠 있는 unit은 면의 구멍으로 빠진다",
              island.faceModeFaces.count == 1 && ring.map { island.faceHoles($0).count } == 1
              && abs((ring?.area ?? 0) - 80_000) < 1e-6)
        island.handleFaceClick(at: LocalPoint(150, 150))
        check("level 기준: 구멍(이미 덮인 unit) 자리를 눌러도 바깥 면이 잡히지 않는다", island.faceSelection.isEmpty)
        island.handleFaceClick(at: LocalPoint(50, 50))
        island.saveSelectedFaces()
        let donut = island.features.features(ofType: .unit).first { $0.polygonRings.count == 2 }
        check("level 기준: 구멍 있는 면은 구멍 있는 MultiPolygon unit으로 저장된다",
              donut?.multiPolygon == true && island.unitCoverage.isEmpty)

        let split = levelEnv(level: rectRing(0, 0, 300, 100), units: [rectRing(0, 0, 100, 100)])
        split.setLayerEditMode(.point)
        split.unitPointTool = .guide
        split.handlePointClick(at: LocalPoint(200, 0), tolerance: 0.01, freePoint: false)
        split.handlePointClick(at: LocalPoint(200, 100), tolerance: 0.01, freePoint: false)
        check("보조 선분: 두 점(변 위에도 붙음)을 찍으면 선분이 생긴다",
              split.features.guides == [LineSegment(start: LocalPoint(200, 0), end: LocalPoint(200, 100))])
        split.setLayerEditMode(.face)
        check("보조 선분: level 기준 면을 둘로 나눈다", split.faceModeFaces.count == 2, "면 \(split.faceModeFaces.count)개")
        split.setFaceBoundaryScope(.currentLayer)
        split.setLayerEditMode(.point)
        split.unitPointTool = .guide
        split.handlePointClick(at: LocalPoint(200, 50), tolerance: 0.01, freePoint: false, editing: true)
        check("보조 선분: Control+클릭으로 지운다", split.features.guides.isEmpty)
        split.undo()
        check("보조 선분: 실행취소로 되살아난다", split.features.guides.count == 1)
        if let data = try? JSONEncoder().encode(split.features),
           var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let round = try? JSONDecoder().decode(FeatureStore.self, from: data)
            json.removeValue(forKey: "guides")
            let legacy = (try? JSONSerialization.data(withJSONObject: json)).flatMap { try? JSONDecoder().decode(FeatureStore.self, from: $0) }
            check("보조 선분: 저장 왕복이 되고 이 키가 없는 이전 파일도 읽힌다",
                  round?.guides.count == 1 && legacy != nil && legacy?.guides.isEmpty == true)
        }

        let cutEnv = levelEnv(level: rectRing(0, 0, 300, 100), units: [rectRing(0, 0, 100, 100)])
        cutEnv.setLayerEditMode(.point)
        if let u = cutEnv.features.features(ofType: .unit).first {
            cutEnv.updateProperty("category", value: .string("room"), in: u.id)
            cutEnv.updateProperty("name", value: .localized(en: "Reading Room", ko: "열람실"), in: u.id)
        }
        cutEnv.unitPointTool = .cut
        cutEnv.handlePointClick(at: LocalPoint(40, -20), tolerance: 0.01, freePoint: false)
        cutEnv.handlePointClick(at: LocalPoint(40, 120), tolerance: 0.01, freePoint: false)
        cutEnv.closePointDraft()
        let pieces = cutEnv.features.features(ofType: .unit)
        let areas = pieces.map { UnitCoverage.area(UnitCoverage.path($0.polygonRings)) }.sorted()
        check("자르기: 선이 가로지른 unit이 둘로 나뉘고 조각마다 원래 속성(category·name)을 가진다",
              pieces.count == 2 && abs(areas[0] - 4000) < 1e-9 && abs(areas[1] - 6000) < 1e-9
              && pieces.allSatisfy { $0.value("category") == .string("room") }
              && pieces.allSatisfy { $0.value("name") == .localized(en: "Reading Room", ko: "열람실") }
              && pieces.allSatisfy { $0.polygonRings.flatMap { $0 }.allSatisfy { p in [0, 40, 100].contains(p.x) && [0, 100].contains(p.y) } },
              "넓이 \(areas)")
        cutEnv.unitPointTool = .cut
        cutEnv.handlePointClick(at: LocalPoint(150, -20), tolerance: 0.01, freePoint: false)
        cutEnv.handlePointClick(at: LocalPoint(150, 120), tolerance: 0.01, freePoint: false)
        cutEnv.closePointDraft()
        check("자르기: unit을 가로지르지 않는 선은 아무것도 바꾸지 않는다", cutEnv.features.features(ofType: .unit).count == 2)

        // section — unit 모양 기준 (2026-10-19 요청)
        let secEnv = levelEnv(level: rectRing(0, 0, 300, 100), units: [rectRing(0, 0, 100, 100), rectRing(100, 0, 200, 100)])
        let secHoled = secEnv.features.features(ofType: .unit).first { $0.polygonRings[0].contains(LocalPoint(0, 0)) }
        if let secHoled { secEnv.features.update(secHoled.id) { $0.polygonRings.append(rectRing(40, 40, 60, 60)) } }
        secEnv.selectPropertyType(.section)
        secEnv.setLayerEditMode(.face)
        secEnv.setFaceBoundaryScope(.unitShapes)
        check("section unit 모양: section 레이어에만 이 기준이 있다",
              FaceBoundaryScope.options(for: .section).contains(.unitShapes)
                  && !FaceBoundaryScope.options(for: .unit).contains(.unitShapes)
                  && secEnv.effectiveFaceBoundaryScope == .unitShapes)
        check("section unit 모양: 저장된 unit마다 면이 하나씩", secEnv.faceModeFaces.count == 2, "\(secEnv.faceModeFaces.count)개")
        secEnv.handleFaceClick(at: LocalPoint(50, 50))
        check("section unit 모양: unit의 구멍 자리를 눌러도 면이 잡히지 않는다", secEnv.faceSelection.isEmpty)
        secEnv.handleFaceClick(at: LocalPoint(10, 10))
        secEnv.saveSelectedFaces()
        let secSaved = secEnv.features.features(ofType: .section).first
        func ringSets(_ rings: [[LocalPoint]]) -> Set<Set<LocalPoint>> { Set(rings.map { Set($0) }) }
        check("section unit 모양: 고른 unit과 같은 모양(구멍 포함)의 section으로 저장된다",
              secSaved.map { ringSets($0.polygonRings) } == secHoled.map { ringSets($0.polygonRings + [rectRing(40, 40, 60, 60)]) },
              secSaved.map { "링 \($0.polygonRings.count)개" } ?? "저장 안 됨")
        check("section unit 모양: 이미 section으로 저장한 unit 자리는 다시 고를 수 없다",
              secEnv.faceModeFaces.contains { secEnv.faceOwner($0) != nil })
        cutEnv.cancelPointDraft()

        let ins = levelEnv(level: rectRing(0, 0, 200, 100), units: [rectRing(0, 0, 100, 100), rectRing(100, 0, 200, 100)])
        ins.setLayerEditMode(.point)
        ins.unitPointTool = .insertVertex
        ins.handlePointClick(at: LocalPoint(100, 30), tolerance: 0.01, freePoint: false)
        let insUnits = ins.features.features(ofType: .unit)
        check("점 끼우기: 변 위를 누르면 그 자리에 꼭짓점이 들어가고, 같은 변을 쓰는 이웃 unit에도 들어간다",
              insUnits.count == 2 && insUnits.allSatisfy { $0.polygonRings[0].count == 5 && $0.polygonRings[0].contains(LocalPoint(100, 30)) }
              && insUnits.allSatisfy { !PolygonValidity.selfIntersects($0.polygonRings[0]) })

        // 구멍이 바깥 테두리에 닿은 MultiPolygon unit(level 기준으로 저장한 복도처럼)은 면 추적에서 다른 모양으로 잡힌다.
        let notched = levelEnv(level: rectRing(0, 0, 300, 300), units: [])
        var corridor = FeatureGroup(featureType: .unit, serialNumber: "unit-950", memberIDs: [])
        corridor.polygonRings = [rectRing(0, 0, 300, 300), rectRing(100, 0, 200, 100)]
        corridor.multiPolygon = true
        notched.features.insert(corridor)
        notched.setFaceBoundaryScope(.currentLayer)
        let notchFace = notched.faceModeFaces.first { abs($0.area - 80_000) < 1e-6 }
        check("면 단위: 같은 모양이 아니어도 저장된 unit이 거의 다 덮은 면은 그 unit의 것이다",
              notchFace.map { notched.faceOwner($0) } == corridor.id && notched.selectableFaceCount == 1,
              "면 \(notched.faceModeFaces.map { Int($0.area) }) · 고를 수 있음 \(notched.selectableFaceCount)")
        notched.expandedFeature = corridor.id
        check("면 단위: 그 unit을 펼치면 그 면이 강조 대상이다",
              notchFace.flatMap { notched.faceOwner($0) }.map { notched.isFeatureHighlighted($0) } == true)
        notched.setFaceBoundaryScope(.level)
        check("level 기준: 구멍 자리(아직 안 덮인 곳)만 면으로 남는다",
              notched.faceModeFaces.count == 1 && abs((notched.faceModeFaces.first?.area ?? 0) - 10_000) < 1e-6)

        // Shift+클릭으로 저장된 꼭짓점 빼기 (2026-10-18 요청)
        let rm = levelEnv(level: rectRing(0, 0, 300, 100), units: [
            [LocalPoint(0, 0), LocalPoint(50, 0), LocalPoint(100, 0), LocalPoint(100, 100), LocalPoint(0, 100)],
            [LocalPoint(100, 0), LocalPoint(200, 0), LocalPoint(200, 100), LocalPoint(100, 100)],
            [LocalPoint(250, 10), LocalPoint(290, 10), LocalPoint(270, 50)]])
        rm.setLayerEditMode(.point)
        let rmUnits = rm.features.features(ofType: .unit)
        rm.handlePointClick(at: LocalPoint(50, 0), tolerance: 0.01, freePoint: false, removing: true)
        check("꼭짓점 빼기: Shift+클릭한 저장된 꼭짓점이 빠진다",
              rm.features.feature(rmUnits[0].id)?.polygonRings[0].count == 4
              && rm.features.feature(rmUnits[0].id)?.polygonRings[0].contains(LocalPoint(50, 0)) == false)
        rm.handlePointClick(at: LocalPoint(100, 0), tolerance: 0.01, freePoint: false, removing: true)
        check("꼭짓점 빼기: 같은 점을 쓰는 이웃은 그대로 두고 알린다",
              rm.features.feature(rmUnits[1].id)?.polygonRings[0].count == 4
              && (rm.banner?.text.contains("unit-902도 이 점을 씁니다") ?? false),
              rm.banner?.text ?? "")
        rm.handlePointClick(at: LocalPoint(270, 50), tolerance: 0.01, freePoint: false, removing: true)
        check("꼭짓점 빼기: 3점 미만이 되면 빼지 않는다",
              rm.features.feature(rmUnits[2].id)?.polygonRings[0].count == 3 && rm.banner?.isError == true)
        check("꼭짓점 빼기: 작성 중인 점이 생기지 않는다", rm.pointDraft.isEmpty)
        rm.undo(); rm.undo()
        check("꼭짓점 빼기: 실행취소로 되살아난다",
              rm.features.feature(rmUnits[0].id)?.polygonRings[0] == rmUnits[0].polygonRings[0])

        // 빈틈·겹침 이름표 — 겹침에는 서로 겹친 두 unit을 단다 (2026-10-18 요청)
        let cov = levelEnv(level: rectRing(0, 0, 300, 100), units: [rectRing(0, 0, 120, 100), rectRing(100, 0, 200, 100)])
        let covLabels = cov.unitCoverageLabels.map(\.text)
        check("빈틈·겹침 이름표: 빈틈과 겹침을 나눠 번호·넓이를 달고, 겹침에는 두 unit을 단다",
              covLabels == ["빈틈-01 · 10000.0", "겹침-01 unit-901×unit-902 · 2000.00"], "\(covLabels)")
        check("빈틈·겹침 이름표: 빈틈과 겹침은 다른 색이다", UnitCoverage.gapColor != UnitCoverage.overlapColor)

        // 실오라기 방지 — 이웃 꼭짓점·변에 맞추기 (2026-10-18 요청)
        let sl = levelEnv(level: rectRing(0, 0, 300, 100), units: [rectRing(0, 0, 100, 100)])
        sl.setLayerEditMode(.point)
        sl.handlePointClick(at: LocalPoint(100.04, 20), tolerance: 0.01, freePoint: true)
        check("실오라기 방지: 이웃 변에서 0.1 안에 찍은 점은 그 변 위로 붙는다",
              sl.pointDraft.points.last == LocalPoint(100, 20), "\(sl.pointDraft.points)")
        sl.cancelPointDraft()
        sl.handlePointClick(at: LocalPoint(100.015, 0.012), tolerance: 0.01, freePoint: true)
        check("실오라기 방지: 이웃 꼭짓점에서 0.1 안에 찍은 점은 그 꼭짓점이 된다",
              sl.pointDraft.points.last == LocalPoint(100, 0))
        sl.cancelPointDraft()
        // T자 접점: 이웃 변 한가운데 닿는 두 점으로 unit을 그린다.
        for p in [LocalPoint(100.03, 20), LocalPoint(200, 20), LocalPoint(200, 80), LocalPoint(100.02, 80)] {
            sl.handlePointClick(at: p, tolerance: 0.01, freePoint: true)
        }
        sl.handlePointClick(at: LocalPoint(100, 20), tolerance: 0.01, freePoint: true)
        let slLeft = sl.features.features(ofType: .unit).first { $0.serialNumber == "unit-901" }
        check("실오라기 방지: T자 접점의 꼭짓점은 이웃 unit의 변에도 함께 들어간다",
              slLeft.map { $0.polygonRings[0].contains(LocalPoint(100, 20)) && $0.polygonRings[0].contains(LocalPoint(100, 80)) } == true)
        check("실오라기 방지: 그렇게 그린 이웃끼리는 겹침이 없다",
              sl.features.features(ofType: .unit).count == 2 && sl.unitCoverage.overlaps.isEmpty
              && abs(sl.unitCoverage.gaps.map { abs(UnitCoverage.area($0)) }.reduce(0, +) - (30_000 - 10_000 - 6_000)) < 1e-3,
              "unit \(sl.features.features(ofType: .unit).map { "\($0.serialNumber) \($0.polygonRings)" }) 겹침 \(sl.unitCoverage.overlaps.count) 빈틈 \(sl.unitCoverage.gaps.map { abs(UnitCoverage.area($0)) })")
        let raw = [[LocalPoint(100.05, 30), LocalPoint(150, 30), LocalPoint(150, 60), LocalPoint(100.05, 60)]]
        let fixed = sl.alignRings(raw, type: .unit, excluding: nil)
        check("실오라기 방지: 저장 직전에도 링을 이웃에 맞춘다(면 단위 저장 등)",
              fixed.moved == 2 && fixed.rings[0][0] == LocalPoint(100, 30))

        // MARK: fixture 선 단위 — 도면 개체를 골라 fixture 하나로 (2026-10-19 요청)

        let ox = AppEnvironment()
        ox.openSample()
        ox.selectPropertyType(.opening)
        ox.declareOpeningComplete()
        // opening 완료를 선언해야 다른 type 레이어가 열린다(명세 10-1-1).
        ox.selectPropertyType(.unit)
        ox.setLayerEditMode(.object)
        check("fixture 선 단위: fixture가 아닌 레이어는 선 단위로 바뀌지 않는다",
              ox.layerEditMode == .point && !LayerEditMode.object.isAvailable(for: .unit))
        ox.selectPropertyType(.fixture)
        ox.setLayerEditMode(.object)
        check("fixture 선 단위: 켜면 점 단위가 아니고 키 없이도 개체를 고른다",
              ox.isObjectWorkMode && !ox.isPointWorkMode && !ox.isPolygonWorkMode && ox.isSelectModeActive
                  && !ox.forceSelectMode && !ox.selectModifierDown)
        let fixtureObjs = (ox.document?.objects ?? []).filter { $0.sourceElement == "rect" }.prefix(2)
        if fixtureObjs.count == 2, let first = fixtureObjs.first, let second = fixtureObjs.last {
            ox.handleCanvasClick(at: LocalPoint(first.boundingBox.minX, first.boundingBox.midY), tolerance: 6)
            ox.handleMarqueeSelection(rect: second.boundingBox.insetBy(dx: -1, dy: -1), mode: .enclose)
            check("fixture 선 단위: 클릭과 드래그로 개체를 고른다",
                  ox.selection.selected.isSuperset(of: [first.id, second.id]), "선택 \(ox.selection.selected.count)개")
            let picked = ox.selection.selected
            ox.createFeature()
            let saved = ox.features.features(ofType: .fixture)
            check("fixture 선 단위: 고른 개체가 fixture 하나의 구성원으로 저장된다",
                  saved.count == 1 && saved.first?.memberIDs == picked && ox.selection.isEmpty,
                  saved.first.map { "\($0.serialNumber) · 개체 \($0.memberIDs.count)개" } ?? "없음")
            if let f = saved.first, let doc = ox.document {
                var ids = IDAssigner()
                let fc = GeoJSONExporter(document: doc, segmentation: ox.segmentation, georeferencer: geo)
                    .buildFeatureCollection(type: .fixture, features: [f], ids: &ids, serialToUUID: [:])
                let json = (try? JSONSerialization.data(withJSONObject: fc)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                check("fixture 선 단위: 구성원 fixture가 도형으로 내보내진다",
                      json.contains("\"MultiPolygon\"") || json.contains("\"Polygon\""), "\(json.count)바이트")
            }
            ox.handleCanvasClick(at: LocalPoint(first.boundingBox.minX, first.boundingBox.midY), tolerance: 6)
            ox.setLayerEditMode(.point)
            check("fixture 선 단위: 점 단위로 돌아가면 선택을 비우고 점 단위가 된다",
                  ox.selection.isEmpty && ox.isPointWorkMode && !ox.isSelectModeActive)
        } else {
            check("fixture 선 단위: 예제 도면에 rect 2개", false)
        }

        // MARK: fixture 선 단위 — 똑같이 생긴 개체 묶음은 그 자리 윤곽선대로 함께 저장 (2026-10-19 요청)

        let chairs = (0..<3).map { i -> String in
            let x = 20 + i * 40
            return "<rect x=\"\(x)\" y=\"20\" width=\"16\" height=\"12\" fill=\"none\" stroke=\"#000\"/>"
                + "<line x1=\"\(x)\" y1=\"36\" x2=\"\(x + 16)\" y2=\"36\" stroke=\"#000\"/>"
        }.joined()
        let mt = AppEnvironment()
        mt.load(data: Data("""
            <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100">\(chairs)\
            <rect x="20" y="60" width="50" height="20" fill="none" stroke="#000"/></svg>
            """.utf8), name: "의자시험")
        // 의자(사각형+선) 3자리와 탁자 하나. 같은 의자 묶음은 위치만 다르다.
        mt.selectPropertyType(.opening)
        mt.declareOpeningComplete()
        mt.selectPropertyType(.fixture)
        mt.setLayerEditMode(.object)
        mt.handleMarqueeSelection(rect: CGRect(x: 18, y: 18, width: 20, height: 20), mode: .enclose)
        let firstChair = mt.selection.selected
        let chairTwins = mt.freeFixtureMemberTwins(of: firstChair)
        check("fixture 함께 저장: 고른 묶음과 똑같이 생긴 자리를 묶음째 찾는다",
              firstChair.count == 2 && chairTwins.count == 2 && chairTwins.allSatisfy { $0.memberIDs.count == 2 }
                  && chairTwins.map(\.dx) == [40, 80],
              "선택 \(firstChair.count)개 · 자리 \(chairTwins.map { "\($0.dx),\($0.memberIDs.count)개" })")
        mt.createFeature()
        let chairFixtures = mt.features.features(ofType: .fixture)
        let allMembers = chairFixtures.reduce(into: Set<VectorObjectID>()) { $0.formUnion($1.memberIDs) }
        check("fixture 함께 저장: 저장하면 자리마다 그 자리 도면 개체를 가진 fixture가 생긴다",
              chairFixtures.count == 3 && chairFixtures.allSatisfy { $0.memberIDs.count == 2 && $0.polygonRings.isEmpty }
                  && allMembers.count == 6 && allMembers.isSuperset(of: firstChair),
              "fixture \(chairFixtures.map { "\($0.serialNumber) 개체 \($0.memberIDs.count)" })")
        check("fixture 함께 저장: 이미 저장된 자리는 다시 찾지 않는다",
              mt.freeFixtureMemberTwins(of: firstChair).isEmpty)
        mt.undo()
        check("fixture 함께 저장: 실행취소 한 번에 함께 저장한 것까지 모두 돌아간다",
              mt.features.features(ofType: .fixture).isEmpty && mt.ownership.claimedCount == 0,
              "남은 fixture \(mt.features.features(ofType: .fixture).count)개")
        mt.handleMarqueeSelection(rect: CGRect(x: 18, y: 58, width: 54, height: 24), mode: .enclose)
        check("fixture 함께 저장: 똑같이 생긴 것이 없는 개체는 하나만 저장한다",
              mt.freeFixtureMemberTwins(of: mt.selection.selected).isEmpty, "선택 \(mt.selection.selected.count)개")
        mt.selection.clear()
        mt.handleMarqueeSelection(rect: CGRect(x: 18, y: 18, width: 20, height: 20), mode: .enclose)
        mt.auxiliary.exclude(Set(chairTwins[1].memberIDs))
        check("fixture 함께 저장: 보조 개체로 뺀 자리는 넣지 않는다",
              mt.freeFixtureMemberTwins(of: mt.selection.selected).map(\.dx) == [40])
        mt.auxiliary.include(Set(chairTwins[1].memberIDs))
        mt.createFeature()
        if let saved = mt.features.features(ofType: .fixture).first(where: { $0.memberIDs == firstChair }) {
            mt.updateProperty("category", value: .string("furniture"), in: saved.id)
            mt.applyTaggingToFixtureTwins(saved.id)
            check("fixture 함께 저장: 우측 패널 '같은 태깅으로 저장'이 선 단위 fixture의 자리 속성을 맞춘다",
                  mt.features.features(ofType: .fixture).count == 3
                      && mt.features.features(ofType: .fixture).allSatisfy { $0.properties["category"] == .string("furniture") })
        } else {
            check("fixture 함께 저장: 다시 저장한 첫 의자를 찾는다", false)
        }

        // MARK: 메타데이터 type은 레이어 대신 정보 입력 (2026-10-19 요청)

        let md = AppEnvironment()
        md.openSample()
        let layersBefore = md.layers.layers.count
        md.selectPropertyType(.building)
        check("메타데이터: building을 고르면 레이어를 만들지 않고 정보 입력 창을 연다",
              md.layers.layers.count == layersBefore && md.layers.layer(for: .building) == nil
                  && md.metadataEditorType == .building)
        check("메타데이터: 도형 없는 type만 해당한다",
              IMDFFeatureType.allCases.filter(\.isMetadataOnly) == [.address, .building, .manifest, .occupant])
        let bid = md.addMetadataFeature(.building)
        let mdSaved = bid.flatMap { md.features.feature($0) }
        check("메타데이터: 추가하면 속성이 모두 null인 feature가 지금 층에 생긴다",
              mdSaved?.featureType == .building && mdSaved?.memberIDs.isEmpty == true && mdSaved?.polygonRings.isEmpty == true
                  && PropertySchema.fields(for: .building).allSatisfy { mdSaved?.properties[$0.key] == .null })
        if let bid { md.updateProperty("name", value: .localized(en: "Library", ko: "도서관"), in: bid) }
        check("메타데이터: 우측 패널과 같은 방식으로 속성을 넣는다",
              bid.flatMap { md.features.feature($0)?.value("name") } == .localized(en: "Library", ko: "도서관"))
        md.undo(); md.undo()
        check("메타데이터: 추가·입력은 실행취소로 되돌아간다", md.features.features(ofType: .building).isEmpty)
        _ = md.addMetadataFeature(.manifest)
        check("메타데이터: manifest는 하나만 둔다",
              md.addMetadataFeature(.manifest) == nil && md.features.features(ofType: .manifest).count == 1)
        md.layers.addPropertyTypeLayer(.occupant)
        md.openMetadataEditor(.occupant)
        check("메타데이터: 예전에 만든 이 type의 레이어는 창을 열 때 닫는다", md.layers.layer(for: .occupant) == nil)

        // MARK: unit category 최근 순 (2026-10-19 요청)

        let recentSuite = "com.imdfrnt.selftest.recent.\(UUID().uuidString)"
        let recentDefaults = UserDefaults(suiteName: recentSuite)!
        let rc = AppEnvironment(projectDefaults: recentDefaults)
        let unitOptions = PropertySchema.categoryOptions(for: .unit)
        check("unit category 최근 순: 기록이 없으면 종전 순서",
              rc.categoryOptionsOrdered(for: .unit).options == unitOptions)
        if unitOptions.count >= 3 {
            let a = unitOptions[unitOptions.count - 1], b = unitOptions[unitOptions.count - 2]
            rc.recordRecentCategory(a, type: .unit)
            rc.recordRecentCategory(b, type: .unit)
            rc.recordRecentCategory(a, type: .unit)
            let ordered = rc.categoryOptionsOrdered(for: .unit)
            check("unit category 최근 순: 최근 고른 값이 맨 위에 최근 순으로, 나머지는 종전 순서",
                  Array(ordered.options.prefix(2)) == [a, b] && ordered.options.count == unitOptions.count
                      && Array(ordered.options.dropFirst(2)) == unitOptions.filter { $0 != a && $0 != b }
                      && ordered.recent == [a, b])
            rc.recordRecentCategory("not-a-category", type: .unit)
            check("unit category 최근 순: 스펙 목록에 없는 기록은 올리지 않는다",
                  !rc.categoryOptionsOrdered(for: .unit).options.contains("not-a-category"))
        }
        rc.recordRecentCategory(PropertySchema.categoryOptions(for: .fixture).last ?? "", type: .fixture)
        check("unit category 최근 순: unit이 아닌 레이어는 순서를 바꾸지 않는다",
              rc.categoryOptionsOrdered(for: .fixture).options == PropertySchema.categoryOptions(for: .fixture)
                  && rc.categoryOptionsOrdered(for: .fixture).recent.isEmpty)
        for i in 0..<20 { rc.recordRecentCategory(unitOptions[i % unitOptions.count], type: .unit) }
        check("unit category 최근 순: 기록은 최근 \(AppEnvironment.recentCategoryLimit)개까지",
              rc.recentUnitCategories.count <= AppEnvironment.recentCategoryLimit)
        UserDefaults().removePersistentDomain(forName: recentSuite)

        // MARK: #31 — 지도 정렬과 (가)·(나) Anchor (신기능 11항, 2026-10-15)

        let align = MapAlignment(center: GeoPoint(longitude: 129.3245, latitude: 36.0141),
                                 canvasCenter: LocalPoint(500, 400), metersPerUnit: 0.05,
                                 rotationDegrees: 37)
        let probes = [LocalPoint(0, 0), LocalPoint(1000, 0), LocalPoint(250, 777), LocalPoint(500, 400)]
        check("#31 정렬: 도면 → 위경도 → 도면 왕복이 맞다",
              probes.allSatisfy { p in align.localPoint(for: align.geoPoint(for: p)).map { $0.distance(to: p) < 1e-6 } ?? false })
        check("#31 정렬: 어파인 계수가 정렬 변환과 같다",
              probes.allSatisfy { p in
                  let g1 = align.geoPoint(for: p), g2 = align.affine.apply(p)
                  return abs(g1.longitude - g2.longitude) < 1e-9 && abs(g1.latitude - g2.latitude) < 1e-9 })
        // 1e-9도 ≈ 0.1mm. 1단위 차분으로 계수를 만들어 위경도 129° 근처에서 1e-12도 수준의 반올림 오차가 난다.
        let tenUnits = ResidualCalculator.metersBetween(align.geoPoint(for: LocalPoint(0, 0)),
                                                        align.geoPoint(for: LocalPoint(100, 0)))
        check("#31 정렬: 크기(m/단위)가 실제 거리로 나온다", abs(tenUnits - 5) < 0.05,
              String(format: "100단위 × 0.05m = %.3fm", tenUnits))
        let north = align.geoPoint(for: LocalPoint(500, 0)).latitude > align.center.latitude
        check("#31 정렬: 회전 0이면 도면 위쪽이 북쪽이다", { () -> Bool in
            var a = align; a.rotationDegrees = 0
            return a.geoPoint(for: LocalPoint(500, 0)).latitude > a.center.latitude
                && abs(a.geoPoint(for: LocalPoint(500, 0)).longitude - a.center.longitude) < 1e-12
        }() && north)
        let clampCanvas = CGSize(width: 2000, height: 1500)
        check("#31 정렬: 크기는 도면 긴 변 1m 아래로 줄지 않는다",
              abs(MapAlignment.clampedMetersPerUnit(0, canvasSize: clampCanvas) * 2000 - 1) < 1e-9)
        // 줄이다 한 점으로 뭉치면 손잡이가 겹쳐 다시 잡을 수 없다.
        let worldWide = MapAlignment.initial(center: GeoPoint(longitude: 127, latitude: 37.5),
                                             visibleWidthMeters: 360 * MapAlignment.metersPerDegreeLatitude,
                                             canvasSize: clampCanvas)
        check("#31 정렬: 세계 지도 배율에서 올려도 도면 모서리 위도가 유효하다",
              abs(worldWide.geoPoint(for: LocalPoint(0, 0)).latitude) < 90
                  && abs(worldWide.metersPerUnit * 2000 - 10_000) < 1e-6,
              String(format: "긴 변 %.0fm", worldWide.metersPerUnit * 2000))

        // 네이버 지도(2026-10-19): 화면 좌표 변환은 지도가 알려 준 범위로 Swift가 계산한다.
        let viewport = NaverMapViewport(message: ["sw": [129.32, 36.01], "ne": [129.33, 36.02], "w": 800.0, "h": 600.0])
        check("#31 네이버 지도: 지도가 보낸 범위를 읽는다", viewport != nil)
        if let v = viewport {
            let ne = v.screenPoint(v.northEast), sw = v.screenPoint(v.southWest)
            check("#31 네이버 지도: 북동은 오른쪽 위, 남서는 왼쪽 아래다",
                  abs(ne.x - 800) < 1e-6 && abs(ne.y) < 1e-6 && abs(sw.x) < 1e-6 && abs(sw.y - 600) < 1e-6)
            let probe = GeoPoint(longitude: 129.3237, latitude: 36.0131)
            let back = v.coordinate(v.screenPoint(probe))
            check("#31 네이버 지도: 위경도 → 화면 → 위경도 왕복이 맞다",
                  abs(back.longitude - probe.longitude) < 1e-10 && abs(back.latitude - probe.latitude) < 1e-10)
            let mid = v.screenPoint(GeoPoint(longitude: 129.325, latitude: 36.015))
            check("#31 네이버 지도: 세로는 메르카토르라 위도 가운데가 화면 가운데보다 조금 아래다",
                  abs(mid.x - 400) < 1e-6 && mid.y > 300 && mid.y < 300.1, String(format: "y = %.4f", mid.y))
            let panned = v.coordinate(CGPoint(x: 400 - 80, y: 300))
            // `pan(from:by:)`의 식: 오른쪽으로 80pt 끌면 새 중심은 시작 범위에서 왼쪽 80pt 자리다.
            check("#31 네이버 지도: 오른쪽으로 끌면 지도 중심이 서쪽으로 간다", panned.longitude < v.center.longitude)
        }
        check("#31 네이버 지도: 잘못된 범위는 읽지 않는다",
              NaverMapViewport(message: ["sw": [129.33, 36.01], "ne": [129.32, 36.02], "w": 800.0, "h": 600.0]) == nil
                  && NaverMapViewport(message: ["sw": [129.32, 36.01], "ne": [129.33, 36.02], "w": 0.0, "h": 600.0]) == nil)
        var svgProbe = Path()
        svgProbe.move(to: CGPoint(x: 0, y: 0)); svgProbe.addLine(to: CGPoint(x: 10.5, y: 0))
        svgProbe.addLine(to: CGPoint(x: 10.5, y: 3.14159)); svgProbe.closeSubpath()
        check("#31 네이버 지도: 도면 경로를 SVG d로 바꾼다(소수 셋째 자리)",
              NaverMapPage.svgPathData(svgProbe) == "M0 0L10.5 0L10.5 3.142Z", NaverMapPage.svgPathData(svgProbe))
        let page = NaverMapPage.html(clientID: "ab c&d", mapKind: .hybrid)
        check("#31 네이버 지도: 페이지가 Client ID(인코딩)·지도 종류·인증 실패 콜백을 담는다",
              page.contains("maps.js?ncpKeyId=ab%20c%26d\"") && !page.contains("&callback=")
                  && page.contains("MapTypeId['HYBRID']") && page.contains("navermap_authFailure")
                  && !page.contains("__CLIENT_ID__") && !page.contains("__MAP_TYPE__"))
        check("#31 네이버 지도: 페이지 기준 주소가 https다(http면 ATS가 타일을 막아 지도가 검게 빈다)",
              NaverMapPage.baseURL.scheme == "https")
        let pointer = MapPointerEvent(message: ["phase": "changed", "kind": "rotate", "x0": 10.0, "y0": 20.0, "x": 30.0, "y": 40.0])
        check("#31 네이버 지도: 지도 페이지가 보낸 손 동작을 읽는다",
              pointer == MapPointerEvent(phase: .changed, kind: .rotate, start: CGPoint(x: 10, y: 20), location: CGPoint(x: 30, y: 40))
                  && MapPointerEvent(message: ["phase": "drag", "kind": "move", "x0": 0.0, "y0": 0.0, "x": 0.0, "y": 0.0]) == nil)
        check("#31 네이버 지도: 손 동작은 지도 페이지가 테두리 겹 기준으로 가로챈다(지도를 덮는 앱 겹 없음)",
              page.contains("IMDF.setInteraction") && page.contains("IMDF.hitKind")
                  && AlignOverlay.layerID(levelID: UUID(), kind: .decoration).hasSuffix("-decoration")
                  && (MapInteraction.none.payload["id"] is NSNull))

        let ma = AppEnvironment()
        ma.openSample()
        if let levelID = ma.routingFloorID, let maDoc = ma.document {
            check("#31 정렬: 도면이 있는 층이 정렬 대상이다", ma.mapAlignLevels.count == 1 && ma.mapAlignment(of: levelID) == nil)
            ma.undoStack.clear()
            ma.placeOnMapIfNeeded(levelID, canvasSize: maDoc.canvasSize,
                                  mapCenter: GeoPoint(longitude: 129.3245, latitude: 36.0141), visibleWidthMeters: 200)
            let placed = ma.mapAlignment(of: levelID)
            check("#31 정렬: 지도 가운데에 올리면 도면 폭이 보이는 폭의 절반이다",
                  placed.map { abs($0.metersPerUnit * Double(max(maDoc.canvasSize.width, maDoc.canvasSize.height)) - 100) < 1e-6 } ?? false)
            ma.undo()
            check("#31 정렬: 올리기는 cmd+z로 되돌아간다", ma.mapAlignment(of: levelID) == nil)
            ma.redo()

            // (가) 정렬된 도면의 꼭짓점·교점을 Anchor 쌍으로.
            let pts = ma.snapPoints.map(\.point)
            if let a = pts.min(by: { $0.x < $1.x }), let b = pts.max(by: { $0.x < $1.x }),
               let c = pts.max(by: { $0.y < $1.y }) {
                let made = [a, b, c].compactMap { ma.addAlignmentAnchor(at: $0) }
                check("#31 (가): 정렬된 도면의 점이 Anchor 쌍이 된다",
                      made.count == 3 && ma.anchors.pairs.allSatisfy { $0.fromAlignment == true })
                check("#31 (가): 같은 점은 두 번 찍히지 않는다", ma.addAlignmentAnchor(at: a) == nil && ma.anchors.pairs.count == 3)
                check("#31 (가): 3쌍이면 지오레퍼런싱이 설정되고 잔차는 0이다",
                      ma.georeferencer.isConfigured && (ma.residuals.max() ?? 1) < 1e-3,
                      String(format: "최대 잔차 %.6fm", ma.residuals.max() ?? -1))

                // 손으로 짝지은 쌍은 정렬을 고쳐도 그대로다.
                let manualGeo = GeoPoint(longitude: 129.0, latitude: 36.0)
                ma.anchors.add(local: LocalPoint(1, 1), geo: manualGeo, label: "수동")
                ma.updateMapAlignment(levelID, name: "도면 회전") { $0.rotationDegrees = 30 }
                let rotated = ma.mapAlignment(of: levelID)!
                check("#31 (가): 정렬을 고치면 정렬로 만든 쌍의 위경도가 따라온다",
                      ma.anchors.pairs.filter { $0.fromAlignment == true }.allSatisfy {
                          let g = rotated.geoPoint(for: $0.local)
                          return abs(g.longitude - $0.geo.longitude) < 1e-12 && abs(g.latitude - $0.geo.latitude) < 1e-12 })
                check("#31 (가): 손으로 짝지은 쌍은 건드리지 않는다",
                      ma.anchors.pairs.first { $0.label == "수동" }?.geo == manualGeo)
                if let manual = ma.anchors.pairs.first(where: { $0.label == "수동" }) { ma.anchors.remove(manual.id) }

                // (나) (가)로 저장한 점 중에서 IMDF anchor feature로.
                let first = ma.anchors.pairs[0]
                ma.toggleIMDFAnchor(first.id)
                let anchorFeature = ma.features.features(ofType: .anchor).first
                check("#31 (나): (가) 점을 anchor feature로 지정한다",
                      anchorFeature?.drawnVertices == [first.local] && ma.imdfAnchorFeature(for: first) != nil)
                if let anchorFeature {
                    let v = VertexExtractor.vertices(for: anchorFeature, document: maDoc,
                                                     segmentation: ma.segmentation, kind: .point)
                    let g = ma.georeferencer.geoPoint(for: v.first ?? LocalPoint(0, 0))
                    check("#31 (나): anchor.geojson Point 좌표가 (가) 점의 위경도다",
                          v == [first.local] && g.map { abs($0.longitude - first.geo.longitude) < 1e-9
                                                       && abs($0.latitude - first.geo.latitude) < 1e-9 } ?? false)
                }
                ma.toggleIMDFAnchor(first.id)
                check("#31 (나): 다시 누르면 지정이 풀린다(휴지통)",
                      ma.features.features(ofType: .anchor).isEmpty && ma.imdfAnchorFeature(for: first) == nil)
                ma.toggleIMDFAnchor(first.id)
                ma.removeAlignmentAnchor(first.id)
                check("#31 (나): (가) 점을 지우면 그 점의 anchor feature도 휴지통으로 간다",
                      ma.features.features(ofType: .anchor).isEmpty && !ma.anchors.pairs.contains { $0.id == first.id })
                ma.undo()
                check("#31 (나): 지우기를 되돌리면 둘 다 돌아온다",
                      ma.features.features(ofType: .anchor).count == 1 && ma.anchors.pairs.contains { $0.id == first.id })

                // anchor 레이어(메인 화면)에서 찍어 둔 점을 두 화면에서 그대로 불러온다.
                if let d = pts.first(where: { ma.anchorPair(at: $0) == nil && ma.anchorLayerPoint(near: $0) == nil }) {
                    let serial = ma.serials.next(for: .anchor)
                    var layerFeature = FeatureGroup(featureType: .anchor, serialNumber: serial, memberIDs: [])
                    layerFeature.drawnVertices = [d]
                    ma.perform("anchor 레이어 점 찍기") { ma.features.insert(layerFeature) }
                    check("#31 anchor 레이어: 쌍이 아닌 점도 화면에 보일 목록에 있다",
                          ma.anchorLayerPoints.contains { $0.feature.id == layerFeature.id && $0.point == d })
                    let before = ma.anchors.pairs.count
                    let imported = ma.importAnchorLayerPoints()
                    let aligned = ma.mapAlignment(of: levelID)!
                    check("#31 anchor 레이어: 지도 정렬에서 그 자리 그대로 Anchor 쌍으로 불러온다",
                          imported.count == 1 && imported[0].local == d && imported[0].label == serial
                          && imported[0].fromAlignment == true && imported[0].geo == aligned.geoPoint(for: d)
                          && ma.anchors.pairs.count == before + 1)
                    check("#31 anchor 레이어: 불러온 쌍은 그 점의 anchor feature와 이어진다",
                          ma.imdfAnchorFeature(for: imported[0])?.id == layerFeature.id)
                    check("#31 anchor 레이어: 이미 불러온 점은 다시 불러오지 않는다",
                          ma.importAnchorLayerPoints().isEmpty && ma.anchors.pairs.count == before + 1)
                    ma.undo()
                    check("#31 anchor 레이어: 불러오기는 cmd+z로 되돌아간다",
                          ma.anchors.pairs.count == before && ma.anchorPair(at: d) == nil)
                    ma.pendingAnchorLocal = d
                    ma.addAnchor(longitude: 129.3, latitude: 36.0, label: "")
                    check("#31 anchor 레이어: Anchor 지정 화면에서 그 점으로 만든 쌍은 일련번호를 라벨로 쓴다",
                          ma.anchorPair(at: d)?.label == serial)
                }
            }

            // 강조 표시: 우측 사이드바에서 고른 카드·눈으로 띄운 feature는 다른 색으로 그린다.
            if let victim = maDoc.objects.first(where: { ma.ownership.ownerOf($0.id) == nil }) {
                var grouped = FeatureGroup(featureType: .unit, serialNumber: "unit-강조", memberIDs: [victim.id])
                grouped.drawnVertices = nil
                ma.features.insert(grouped)
                try? ma.ownership.claim([victim.id], for: grouped.id)
                ma.collapseAllFeatures(); ma.layers.isolatedFeature = nil
                ma.invalidateRenderStates()
                check("강조: 고르지 않은 feature는 강조하지 않는다",
                      !ma.isFeatureHighlighted(grouped.id) && ma.renderState(for: victim).isHighlighted == false)
                ma.expandFeature(grouped.id)
                check("강조: 우측 사이드바에서 펼친 카드의 개체는 강조색으로 그린다",
                      ma.isFeatureHighlighted(grouped.id) && ma.renderState(for: victim).isHighlighted)
                ma.collapseAllFeatures()
                ma.layers.isolatedFeature = grouped.id
                check("강조: '이 feature만 보기'로 띄운 개체도 강조색으로 그린다",
                      ma.renderState(for: victim).isHighlighted)
                ma.layers.isolatedFeature = nil
                check("강조색은 저장·면·선·점 색과 모두 다르다",
                      Set([ClosedPolygonAppearance.highlightFill, ClosedPolygonAppearance.savedFill,
                           ClosedPolygonAppearance.faceFill, ClosedPolygonAppearance.edgeStroke,
                           ClosedPolygonAppearance.vertexFill].map(\.description)).count == 5)
                check("태깅 색은 회색이 아니고 다른 레이어 면·비활성 개체·선택·제외 색과 다르다",
                      CanvasBackground.allCases.allSatisfy { bg in
                          Set([ClosedPolygonAppearance.savedFill, ClosedPolygonAppearance.otherLayerFill,
                               bg.disabledStroke, bg.selection, bg.excludedStroke].map(\.description)).count == 5
                      })
                // 진행률 '저장': 점으로 그린 feature가 덮은 개체도 센다.
                if let target = maDoc.objects.first(where: { o in
                    ma.ownership.ownerOf(o.id) == nil && !ma.auxiliary.isExcluded(o.id)
                        && ma.snapPoints.contains { $0.kind != .crossing && $0.owners == [o.id] }
                        && !ma.pointCoveredObjectIDs.contains(o.id) }) {
                    let ring = ma.snapPoints.filter { $0.kind != .crossing && $0.owners.contains(target.id) }.map(\.point)
                    let beforeSaved = ma.claimedCount
                    var drawn = FeatureGroup(featureType: .fixture, serialNumber: "fixture-진행률", memberIDs: [])
                    drawn.drawnVertices = ring
                    ma.features.insert(drawn)
                    check("진행률: 점으로 그린 feature가 꼭짓점을 모두 찍은 개체는 '저장'으로 센다",
                          ma.pointCoveredObjectIDs.contains(target.id) && ma.claimedCount > beforeSaved,
                          "저장 \(beforeSaved) → \(ma.claimedCount)")
                    ma.features.remove(drawn.id)
                }
                if let door = maDoc.objects.first(where: { o in
                    let b = ma.renderCache.entry(for: o, segmentation: ma.segmentation).box
                    return ma.ownership.ownerOf(o.id) == nil && !ma.auxiliary.isExcluded(o.id)
                        && b.width > 1 && b.height <= b.width && !ma.pointCoveredObjectIDs.contains(o.id) }) {
                    let b = ma.renderCache.entry(for: door, segmentation: ma.segmentation).box
                    var opening = FeatureGroup(featureType: .opening, serialNumber: "opening-진행률", memberIDs: [])
                    opening.drawnVertices = [LocalPoint(Double(b.minX), Double(b.midY)), LocalPoint(Double(b.maxX), Double(b.midY))]
                    ma.features.insert(opening)
                    check("진행률: opening 선(두 점)의 문 자리 안에 든 개체(문짝·호)는 '저장'으로 센다",
                          ma.pointCoveredObjectIDs.contains(door.id))
                    ma.features.remove(opening.id)
                    check("진행률: opening을 지우면 그 문 자리 개체는 다시 '저장'에서 빠진다",
                          !ma.pointCoveredObjectIDs.contains(door.id))
                }

                // 제외된 보조 개체의 진하기 조절.
                let savedOpacity = ma.excludedAuxiliaryOpacity
                if let aux = maDoc.objects.first(where: { ma.ownership.ownerOf($0.id) == nil && !ma.auxiliary.isExcluded($0.id) }) {
                    ma.auxiliary.exclude([aux.id])
                    ma.excludedAuxiliaryOpacity = 1
                    let base = ma.renderState(for: aux).opacity
                    // 제외된 개체는 비활성 배율(0.85)도 함께 받는다. 슬라이더 효과만 보려고 100%일 때와 비교한다.
                    ma.excludedAuxiliaryOpacity = 0.2
                    let dimmed = ma.renderState(for: aux).opacity
                    ma.excludedAuxiliaryOpacity = 0
                    let hidden = ma.renderState(for: aux).opacity
                    check("보조 개체 진하기: 슬라이더 값만큼 제외된 개체가 옅어지고 0이면 안 보인다",
                          abs(dimmed - base * 0.2) < 1e-9 && hidden == 0,
                          String(format: "%.2f → %.2f → %.2f", base, dimmed, hidden))
                    ma.auxiliary.include([aux.id])
                }
                ma.excludedAuxiliaryOpacity = savedOpacity

                let pickOptions = ["restroom.male", "room", "unit-003", "unit-013", "walkway"]
                check("검색 선택: 공백·점을 무시하고 찾는다",
                      SearchablePicker.filter(pickOptions, query: "rest room") == ["restroom.male"])
                check("검색 선택: 번호 앞 0을 몰라도 찾는다",
                      SearchablePicker.filter(pickOptions, query: "unit 3") == ["unit-003"]
                      && SearchablePicker.filter(pickOptions, query: "unit-00") == ["unit-003"])
                check("검색 선택: 대소문자를 무시하고, 앞에서 맞는 항목을 먼저 보인다",
                      SearchablePicker.filter(pickOptions, query: "ROOM") == ["room", "restroom.male"])
                check("검색 선택: 검색어가 없으면 전부 보인다",
                      SearchablePicker.filter(pickOptions, query: "  ") == pickOptions)
                // 이 Mac에 기억되는 값이라 점검이 사용자 설정을 바꿔 놓지 않게 되돌린다.

                let unlabeled = IMDFFeatureType.allCases.flatMap { t in
                    PropertySchema.categoryOptions(for: t).filter { CategoryLabel.korean($0, type: t) == nil }
                        .map { "\(t.rawValue).\($0)" }
                }
                check("category 한국어: 모든 레이어의 category 값에 한국어 표기가 있다",
                      unlabeled.isEmpty, unlabeled.prefix(5).joined(separator: ", "))
                check("category 한국어: `한국어(영어)`로 보이고 type마다 다른 뜻을 구분한다",
                      CategoryLabel.display("classroom", type: .unit) == "강의실(classroom)"
                      && CategoryLabel.display("service", type: .opening) == "서비스 출입구(service)"
                      && CategoryLabel.display("service", type: .amenity) == "서비스(service)"
                      && CategoryLabel.display("cafe", type: .occupant) == "cafe")
                check("category 한국어: 한국어로 검색해도 영어 값이 걸린다",
                      SearchablePicker.filter(pickOptions, query: "화장실",
                                              label: { CategoryLabel.display($0, type: .unit) }) == ["restroom.male"])

                if let f = ma.features.features.first(where: { !$0.isInTrash }) {
                    let savedFilters = ma.categoryFilters
                    let own = AppEnvironment.categoryValue(of: f)
                    ma.categoryFilters[f.featureType] = ["__없는 category__"]
                    let hidden = !ma.passesCategoryFilter(f)
                    let memberHidden = f.memberIDs.first.flatMap { maDoc.object($0) }
                        .map { !ma.renderState(for: $0).isVisible } ?? true
                    ma.categoryFilters[f.featureType] = [own]
                    let shown = ma.passesCategoryFilter(f)
                    ma.categoryFilters[f.featureType] = nil
                    let cleared = ma.passesCategoryFilter(f)
                    check("category 필터: 고른 category의 feature만 남고, 해제하면 전부 돌아온다",
                          hidden && memberHidden && shown && cleared,
                          "\(f.serialNumber) category=\(own.isEmpty ? "null" : own)")
                    ma.categoryFilters = savedFilters

                    let savedExpanded = ma.expandedFeature
                    ma.collapseAllFeatures()
                    let picked = ma.handleFeatureTagClick(f.id)
                    let selected = ma.expandedFeature == f.id && ma.isFeatureExpanded(f.id)
                    let again = ma.handleFeatureTagClick(f.id)
                    check("이름표 클릭: 이름표를 누르면 그 feature를 고르고, 다시 누르면 접는다",
                          picked && selected && again && !ma.isFeatureExpanded(f.id), f.serialNumber)
                    ma.expandedFeature = savedExpanded

                    let tagFields = IMDFFeatureType.allCases.allSatisfy { t in
                        let keys = FeatureTagEditor.fields(for: t).map(\.key)
                        let wantsCategory = !PropertySchema.categoryOptions(for: t).isEmpty
                        let wantsName = PropertySchema.fields(for: t).contains { $0.key == "name" && $0.type == .localizedName }
                        return keys.contains("category") == wantsCategory && keys.contains("name") == wantsName
                    }
                    check("이름표 편집 창: category가 있는 레이어는 category를, 이름을 쓰는 레이어는 name을 편집한다",
                          tagFields && FeatureTagEditor.fields(for: .unit).map(\.key).sorted() == ["category", "name"])

                    func statesText() -> [String] {
                        maDoc.objects.map { String(describing: ma.renderState(for: $0)) }
                    }
                    var g = FeatureGroup(featureType: f.featureType, serialNumber: "\(f.featureType.rawValue)-부분갱신", memberIDs: [])
                    if let free = maDoc.objects.first(where: { ma.ownership.ownerOf($0.id) == nil }) {
                        g.memberIDs = [free.id]
                        ma.features.insert(g)
                        try? ma.ownership.claim([free.id], for: g.id)
                    }
                    // 구성원 개체가 있는 feature여야 부분 갱신이 실제로 개체를 다시 판정한다.
                    _ = ma.renderStates()
                    ma.hoveredFeature = g.id
                    ma.expandedFeature = g.id
                    let litPartial = g.memberIDs.first.flatMap { maDoc.object($0) }.map { ma.renderState(for: $0).isHighlighted } ?? false
                    ma.categoryFilters[g.featureType] = ["__없는 category__"]
                    let partial = statesText()
                    let memberHiddenPartial = g.memberIDs.first.flatMap { maDoc.object($0) }.map { !ma.renderState(for: $0).isVisible } ?? false
                    ma.invalidateRenderStates()
                    let full = statesText()
                    check("표시 상태 부분 갱신: 이름표 hover·펼침·category 필터를 바꾼 뒤 일부만 다시 판정한 결과가 통째로 다시 만든 것과 같다",
                          partial == full && litPartial && memberHiddenPartial && !g.memberIDs.isEmpty, "구성원 \(g.memberIDs.count)")
                    ma.categoryFilters = savedFilters
                    if !g.memberIDs.isEmpty { ma.ownership.release(g.memberIDs); ma.features.remove(g.id) }
                    ma.hoveredFeature = nil
                    ma.expandedFeature = savedExpanded
                }

                let zoomIn = ZoomEventMonitor.wheelFactor(3, precise: false)
                let zoomOut = ZoomEventMonitor.wheelFactor(-3, precise: false)
                check("확대 민감도: 휠을 같은 만큼 밀고 당기면 제자리이고, 한 번에 16% 넘게 변하지 않는다",
                      abs(zoomIn * zoomOut - 1) < 1e-9 && zoomIn < 1.2
                      && ZoomEventMonitor.wheelFactor(500, precise: false) <= exp(ZoomEventMonitor.maxStep) + 1e-9
                      && ZoomEventMonitor.pinchFactor(1) <= exp(ZoomEventMonitor.maxStep) + 1e-9,
                      String(format: "휠 3줄 %.3f배", zoomIn))
                let grid = SpatialIndex(objects: maDoc.objects, canvasSize: maDoc.canvasSize)
                let corner = CGRect(x: 0, y: 0, width: maDoc.canvasSize.width * 0.1, height: maDoc.canvasSize.height * 0.1)
                let picked = grid.drawIndices(in: corner, moved: [], count: maDoc.objects.count)
                let expected = maDoc.objects.indices.filter { maDoc.objects[$0].boundingBox.intersects(corner) }
                check("화면 안만 그리기: 격자로 고른 개체가 화면에 걸친 개체를 모두 담고 도면 순서를 지킨다. 범위를 모르면 전체를 그린다",
                      (picked.map { p in Set(expected).isSubset(of: Set(p)) && p == p.sorted() } ?? true)
                      && grid.drawIndices(in: .infinite, moved: [], count: maDoc.objects.count) == nil
                      && grid.drawIndices(in: corner, moved: [], count: maDoc.objects.count + 1) == nil,
                      "화면 안 \(expected.count) / 고름 \(picked?.count ?? -1) / 전체 \(maDoc.objects.count)")
                CanvasLagSelfTest.run(ma, maDoc, check)
                // 캔버스 이동 렉·이름표 편집 창 렉(2026-10-19) 점검은 따로 둔다.

                let taggedOwnType = ma.renderState(for: victim)
                check("태깅 색: 다른 레이어가 가져간 개체는 태깅 색으로 칠하지 않는다",
                      ma.layers.activePropertyType == .unit ? taggedOwnType.isTaggedHere : !taggedOwnType.isTaggedHere)
            }

            // 보조 개체로 제외한 개체는 지도에 그리지 않는다.
            if let level = ma.mapAlignLevels.first, let victim = maDoc.objects.first {
                let before = ma.mapAlignDrawing(for: level)?.objectCount ?? -1
                ma.auxiliary.exclude([victim.id])
                let after = ma.mapAlignDrawing(for: level)?.objectCount ?? -1
                check("#31 정렬: 보조 개체로 제외한 개체는 지도에 그리지 않는다",
                      before == maDoc.objects.count && after == before - 1, "\(before) → \(after)")
            }

            // 저장 왕복과 이전 파일 호환.
            if let file = ma.makeProjectFile(), let round = try? ProjectFile.decoded(from: file.encoded()) {
                let info = round.commonProject().levels.first?.info
                check("#31 저장: 정렬값과 정렬 Anchor 표시가 왕복 보존된다",
                      info?.mapAlignment == ma.mapAlignment(of: levelID)
                      && info?.anchors.pairs.contains { $0.fromAlignment == true } == true)
            } else {
                check("#31 저장: 정렬값과 정렬 Anchor 표시가 왕복 보존된다", false, "직렬화 실패")
            }
            if let level = ma.buildingProject.levels.first,
               let data = try? JSONEncoder().encode(level.info),
               var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                json.removeValue(forKey: "mapAlignment")
                let legacy = (try? JSONSerialization.data(withJSONObject: json))
                    .flatMap { try? JSONDecoder().decode(ProjectLevelInfo.self, from: $0) }
                check("#31 저장: 정렬값이 없는 이전 파일도 읽힌다", legacy != nil && legacy?.mapAlignment == nil)
            }
        }

        // 층 쌓기: 2층은 아래층 자리에서 시작하고, 쌓는 순서를 바꿀 수 있다.
        let st = AppEnvironment()
        let floors = (0..<2).map { ProjectLevel(info: ProjectLevelInfo(name: "\($0 + 1)층", ordinal: $0,
                                                                       sourceName: "s.svg", svg: SampleFloorplan.svg)) }
        st.buildingProject = BuildingProject(levels: floors)
        st.placeOnMapIfNeeded(floors[0].id, canvasSize: CGSize(width: 800, height: 600),
                              mapCenter: GeoPoint(longitude: 127, latitude: 37), visibleWidthMeters: 160)
        st.updateMapAlignment(floors[0].id, name: "test") { $0.rotationDegrees = 12; $0.isConfirmed = true }
        st.placeOnMapIfNeeded(floors[1].id, canvasSize: CGSize(width: 800, height: 600),
                              mapCenter: GeoPoint(longitude: 0, latitude: 0), visibleWidthMeters: 999)
        let lower = st.mapAlignment(of: floors[0].id), upper = st.mapAlignment(of: floors[1].id)
        check("#31 층 쌓기: 2층은 아래층 정렬 자리에서 시작한다",
              upper?.center == lower?.center && upper?.metersPerUnit == lower?.metersPerUnit
              && upper?.rotationDegrees == lower?.rotationDegrees)
        check("#31 층 쌓기: 새로 올린 층이 맨 위다", st.mapAlignStack.map(\.id) == [floors[0].id, floors[1].id])
        st.moveOnMapStack(floors[1].id, .back)
        check("#31 층 쌓기: 맨 뒤로 보내기", st.mapAlignStack.map(\.id) == [floors[1].id, floors[0].id])
        st.moveOnMapStack(floors[1].id, .forward)
        check("#31 층 쌓기: 앞으로 보내기", st.mapAlignStack.map(\.id) == [floors[0].id, floors[1].id])
        st.undo()
        check("#31 층 쌓기: 순서 바꾸기도 cmd+z로 되돌아간다", st.mapAlignStack.map(\.id) == [floors[1].id, floors[0].id])
        check("#31 진행: 정렬 완료한 층을 센다", st.mapAlignProgress.done == 1 && st.mapAlignProgress.total == 2)

        let pohang = GeoPoint(longitude: 129.3256, latitude: 36.0137)
        st.bringToMapCenter(floors[0].id, canvasSize: CGSize(width: 800, height: 600),
                            mapCenter: pohang, visibleWidthMeters: 400)
        let brought = st.mapAlignment(of: floors[0].id)
        check("#31 지도 가운데로 가져오기: 지금 지도 가운데·화면 폭에 맞추고 회전은 그대로, 확정은 풀린다",
              brought?.center == pohang && abs((brought?.metersPerUnit ?? 0) * 800 - 200) < 1e-9
              && brought?.rotationDegrees == 12 && brought?.isConfirmed == false)
        st.undo()
        let restored = st.mapAlignment(of: floors[0].id)
        check("#31 지도 가운데로 가져오기: cmd+z로 되돌아간다",
              restored?.center == lower?.center && restored?.metersPerUnit == lower?.metersPerUnit
              && restored?.isConfirmed == true)
        // 쌓는 순서는 위 점검에서 바뀌었으므로 자리·크기·확정만 비교한다.
        check("#31 지도에 올리기: 전국 보기처럼 너무 넓은 화면에서는 막는 기준이 건물 범위다",
              AppEnvironment.maxPlacingWidthMeters <= 5_000)

        // MARK: 성능 최적화 (07) 성능 최적화 제안.md, 2026-08-26)
        //
        // 캐시는 "다시 계산해야 하는데 안 하는 것"이 가장 찾기 어려운 버그다.
        // 그래서 **캐시가 준 값과 직접 계산한 값이 같은지**를 여기서 검사한다.

        let perf = AppEnvironment()
        perf.document = doc

        check("성능: 표시 상태 사전이 직접 계산과 일치",
              doc.objects.allSatisfy { perf.renderStates()[$0.id]?.isVisible
                  == perf.renderState(for: $0).isVisible })

        let beforeSelect = perf.renderStates()[doc.objects[0].id]?.isSelected ?? true
        perf.selection.selected = [doc.objects[0].id]
        let afterSelect = perf.renderStates()[doc.objects[0].id]?.isSelected ?? false
        check("성능: 선택이 바뀌면 사전이 즉시 갱신된다", beforeSelect == false && afterSelect,
              "무효화를 빠뜨리면 화면이 갱신되지 않는다 — didSet 깔때기가 살아 있는지 본다")

        let cachedEntry = perf.renderCache.entry(for: doc.objects[0], segmentation: perf.segmentation)
        check("성능: 파생 데이터가 직접 계산과 일치",
              cachedEntry.segments.count == doc.objects[0].geometry.lineSegments().count
              && cachedEntry.box == doc.objects[0].geometry.boundingBox)

        if let curvedID = curved.first, let curvedObj = doc.object(curvedID) {
            _ = perf.renderCache.entry(for: curvedObj, segmentation: perf.segmentation)
            perf.segmentation.segmentize(curvedID, geometry: curvedObj.geometry, tolerance: 0.6)
            let after = perf.renderCache.entry(for: curvedObj, segmentation: perf.segmentation)
            check("성능: 선분화하면 그 개체의 캐시만 다시 만들어진다",
                  after.segments.count
                  == perf.segmentation.effectiveGeometry(for: curvedID,
                                                         fallback: curvedObj.geometry).lineSegments().count,
                  "선분화한 개체의 화면이 그대로면 이 검사가 먼저 잡는다")
        }

        perf.showOverlapHighlight = true
        perf.selection.selected = Set(doc.objects.prefix(3).map(\.id))
        let cachedOverlap = perf.overlapHighlight
        let directOverlap = OverlapDetector.detect(
            selected: perf.selection.selected,
            among: perf.selectableObjects(in: doc),
            cached: OverlapDetector.directGeometry(perf.segmentation),
            tolerance: perf.overlapTolerance)
        check("성능: 저장해 둔 겹침이 직접 계산과 일치",
              cachedOverlap.count == directOverlap.count,
              "캐시 \(cachedOverlap.count)곳 / 직접 \(directOverlap.count)곳")
        perf.selection.clear()
        check("성능: 선택이 비면 겹침도 비워진다", perf.overlapHighlight.isEmpty)

        // 격자로 좁힌 후보가 전수 검사와 같은 답을 주는지 — 좁히다가 빠뜨리면
        // "클릭해도 안 잡히는 개체"가 생기는데, 화면에서는 원인을 알기 어렵다.
        var narrowingMatches = true
        for o in doc.objects.prefix(12) {
            let p = LocalPoint(o.boundingBox.midX, o.boundingBox.minY)
            let tol = 6.0
            let probe = CGRect(x: p.x - tol, y: p.y - tol, width: tol * 2, height: tol * 2)
            let all = HitTester.hitTest(p, candidates: perf.selectableObjects(in: doc),
                                        cached: OverlapDetector.directGeometry(perf.segmentation),
                                        tolerance: tol)
            let narrowed = HitTester.hitTest(p, candidates: perf.selectableObjects(in: doc, near: probe),
                                             cached: perf.renderCache.geometryProvider(perf.segmentation),
                                             tolerance: tol)
            if all != narrowed { narrowingMatches = false; break }
        }
        check("성능: 격자로 좁힌 클릭 판정이 전수 검사와 같다", narrowingMatches)

        check("성능: 옮긴 개체는 격자 밖이어도 후보에 남는다",
              perf.spatialIndex.candidates(in: CGRect(x: -9999, y: -9999, width: 1, height: 1),
                                           moved: [doc.objects[0].id])?.contains(doc.objects[0].id) == true,
              "이동은 화면 전용이라 격자와 어긋난다 — 빠뜨리면 옮긴 개체가 클릭되지 않는다")

        check("성능: 속성 색인이 도면 전체 비교와 같은 답을 준다",
              perf.objectsMatchingAttribute(doc.objects[0].style.attributeKey).count
              == doc.objects.filter { $0.style.attributeKey == doc.objects[0].style.attributeKey }.count)

        // 이동량이 환경 전체가 아니라 별도 객체에 있는지(제안 4).
        perf.selection.selected = [doc.objects[0].id]
        perf.isMoveEnabled = true
        // '개체 이동' 토글이 이동의 게이트라, 켜지 않으면 아래 이동이 아예 일어나지 않는다.
        let base = perf.beginMove()
        perf.applyMove(CGSize(width: 30, height: 20), from: base)
        check("성능: 이동량은 별도 객체가 들고 있다",
              perf.moves.offset(for: doc.objects[0].id) == CGSize(width: 30, height: 20)
              && perf.transientOffsets.count == 1 && perf.moves.isMoving)
        check("성능: 좌표 추출은 이동을 보지 않는다",
              perf.geometry(for: doc.objects[0]).boundingBox == doc.objects[0].geometry.boundingBox,
              "명세 2-3 — 이동은 화면 전용이고 산출물에 영향을 주지 않는다")
        perf.endMove()
        check("성능: 드래그가 끝나면 이동 상태가 풀린다", !perf.moves.isMoving)
        perf.resetPositions()
        check("성능: 원위치", !perf.hasAnyOffset)

        // 개체 2,000개 도면에서의 프레임 비용. 이 수치가 이번 최적화의 목적 자체다.
        var bigObjects: [VectorObject] = []
        for i in 0..<2000 {
            let x = Double(i % 50) * 40, y = Double(i / 50) * 40
            let g = PathGeometry(subpaths: [Subpath(
                start: LocalPoint(x, y),
                segments: [.line(to: LocalPoint(x + 34, y)),
                           .cubic(c1: LocalPoint(x + 42, y + 12), c2: LocalPoint(x + 42, y + 24),
                                  to: LocalPoint(x + 34, y + 34)),
                           .line(to: LocalPoint(x, y + 34))],
                isClosed: true)])
            // 실도면에는 곡선(문 호·모깎기)이 섞여 있고, 곡선은 쓸 때마다 잘게 쪼개진다.
            // 직선만으로 재면 이 최적화가 겨냥한 비용이 시험에 나타나지 않는다.
            bigObjects.append(VectorObject(
                id: StableObjectID.make(ordinal: i, element: "polygon",
                                        styleKey: doors[0].style.attributeKey, geometry: g),
                geometry: g, style: doors[0].style, sourceElement: "polygon", ordinal: i))
        }
        let bigDoc = DrawingDocument(objects: bigObjects,
                                     canvasSize: CGSize(width: 2000, height: 1600),
                                     sourceName: "big")
        let big = AppEnvironment()
        big.document = bigDoc

        let firstStart = Date()
        _ = big.renderStates()
        let firstMs = Date().timeIntervalSince(firstStart) * 1000
        let secondStart = Date()
        for _ in 0..<60 { _ = big.renderStates() }
        let cachedMs = Date().timeIntervalSince(secondStart) / 60 * 1000
        check("성능: 개체 2,000개 표시 상태 — 캐시된 프레임은 사실상 공짜", cachedMs < 0.5,
              String(format: "최초 %.1f ms, 이후 %.4f ms/프레임", firstMs, cachedMs))

        let pathStart = Date()
        for o in bigObjects { _ = big.renderCache.entry(for: o, segmentation: big.segmentation) }
        let pathFirst = Date().timeIntervalSince(pathStart) * 1000
        let pathAgain = Date()
        for _ in 0..<10 {
            for o in bigObjects { _ = big.renderCache.entry(for: o, segmentation: big.segmentation) }
        }
        let pathCached = Date().timeIntervalSince(pathAgain) / 10 * 1000
        check("성능: 개체 2,000개 Path·선분 — 두 번째 프레임부터 다시 만들지 않는다",
              pathCached <= pathFirst && pathCached < 2.0,
              // 비율로 재면 시험이 흔들린다 — 도면이 단순하면 최초 계산도 1ms 남짓이라
              // "4배 빨라야 한다" 같은 기준은 측정 잡음에 걸린다. **한 프레임 예산 안인가**로 본다.
              String(format: "최초 %.1f ms, 이후 %.1f ms/프레임", pathFirst, pathCached))

        big.selection.selected = [bigObjects[1000].id]
        let overlapStart = Date()
        big.refreshOverlap()
        let overlapMs = Date().timeIntervalSince(overlapStart) * 1000
        check("성능: 겹침 계산은 선택 주변만 본다", overlapMs < 60,
              String(format: "%.1f ms — 드래그 중에는 이 계산이 아예 돌지 않는다", overlapMs))

        // 드래그 다중 선택의 비용(2026-08-26 버그). 개체마다 selection을 고치면 그때마다
        // 겹침 검사가 다시 돌아 선택 개수의 제곱으로 불어난다 — 커서가 멎은 것처럼 느려졌다.
        big.selection.clear()
        big.layers.bootstrap()
        let marqueeStart = Date()
        big.forceSelectMode = true
        big.handleMarqueeSelection(rect: CGRect(x: 0, y: 0, width: 3000, height: 3000),
                                   mode: .enclose)
        let marqueeMs = Date().timeIntervalSince(marqueeStart) * 1000
        check("성능: 개체 2,000개를 한 번에 드래그 선택", marqueeMs < 1500,
              String(format: "%.0f ms, %d개 선택 — 선택은 한 번에 대입해야 한다",
                     marqueeMs, big.selection.selected.count))
        big.selection.clear()
        big.forceSelectMode = false

        // 제안 7 판단 근거 — 실행취소 스냅샷 비용 측정.
        // 무겁지 않으면 손대지 않는다(cmd+z가 먹지 않는 종류의 버그를 감수할 이유가 없다).
        let snapEnv = AppEnvironment()
        snapEnv.document = doc
        for i in 0..<300 {
            snapEnv.features.insert(FeatureGroup(featureType: .unit,
                                                 serialNumber: String(format: "unit-%03d", i),
                                                 memberIDs: [doc.objects[i % doc.objects.count].id]))
        }
        let snapshotStart = Date()
        for _ in 0..<200 { snapEnv.perform("측정") { snapEnv.expandedFeature = nil } }
        let perCall = Date().timeIntervalSince(snapshotStart) / 200 * 1000
        check("성능: feature 300개에서 실행취소 스냅샷 1회 비용", perCall < 8.0,
              String(format: "%.2f ms/회 — 8ms(한 프레임)를 넘으면 제안 7을 적용한다", perCall))

        print("== \(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)") ==")
        exit(failures == 0 ? 0 : 1)
    }
}
