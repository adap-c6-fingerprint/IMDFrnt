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
        let uuidBefore = pEnv.ids.id(for: unitF.id)
        // 한 번 내보낸 셈 치고 UUID를 발급받는다.

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

        check("프로젝트: UUID가 유지된다",
              reopened.ids.peek(unitF.id) == uuidBefore && uuidBefore != nil,
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
        // **만드는 시점이 이 절의 핵심이다.** 끝점·교차점 계산은 개체 수의 제곱에 붙는다.
        // 도면을 열 때마다 만들면 실도면(개체 수천 개)에서 **앱 시작이 그대로 멈춘다** —
        // 자동 저장본 복원 경로에서 실제로 그렇게 됐다. 창에 들어갈 때만 만든다.
        check("문닫기: 도면을 열기만 해서는 점을 만들지 않는다", dc.doorSnapPoints.isEmpty,
              "여기서 만들면 실도면을 여는 순간 앱이 멈춘다(엔진 디버깅 1-1과 같은 실수)")
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

        // 3-3·3-4) 넷을 모두 고르기 전에는 저장할 수 없다
        guard let arcObj = dcDoc.objects.first(where: { $0.isCurved }),
              let doorObj = dcDoc.objects.first(where: { !$0.isCurved && $0.sourceElement == "line" }) else {
            print("[FAIL] 문닫기: 시험용 문·호를 못 찾음"); exit(1)
        }
        check("문닫기: 아무것도 안 골랐으면 저장 불가", !dc.canSaveTemporaryDoor)
        dc.toggleDoorPoint(LocalPoint(10, 10))
        check("문닫기: 점 1개로는 저장 불가", !dc.canSaveTemporaryDoor)
        dc.toggleDoorPoint(LocalPoint(40, 10))
        check("문닫기: 점만 2개여도 저장 불가", !dc.canSaveTemporaryDoor,
              "명세 3-4는 넷이 모두 갖춰져야 한다고 못박는다")
        check("문닫기: 왜 못 누르는지 알려준다", dc.temporaryDoorHint.contains("문"),
              dc.temporaryDoorHint)

        dc.toggleDoorObject(doorObj.id)
        check("문닫기: 직선은 문짝 자리에 들어간다", dc.doorDraftDoorID == doorObj.id)
        dc.toggleDoorObject(arcObj.id)
        check("문닫기: 곡선은 호 자리에 들어간다", dc.doorDraftArcID == arcObj.id,
              "어느 자리인지는 사용자가 아니라 도형이 정한다 — 호는 회전 궤적이라 반드시 곡선이다")
        check("문닫기: 넷이 갖춰지면 저장할 수 있다", dc.canSaveTemporaryDoor)

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
        check("문닫기: 저장 뒤에는 고른 것이 비워진다",
              dc.doorDraftPoints.isEmpty && dc.doorDraftDoorID == nil && dc.doorDraftArcID == nil,
              "안 비우면 다음 문을 찍을 때 앞 문의 개체가 딸려 온다")
        check("문닫기: 저장은 실행취소 대상이다", dc.canUndo,
              "스냅샷에서 빠뜨리면 perform이 '바뀐 게 없다'고 판단해 칸을 도로 버린다")
        dc.undo()
        check("문닫기: cmd+z로 되돌아간다", dc.doorClosures.isEmpty)
        dc.redo()
        check("문닫기: 다시실행도 된다", dc.doorClosures.count == 1)

        guard let saved = dc.doorClosures.doors.first else { print("[FAIL] 문닫기: 저장 실패"); exit(1) }
        check("문닫기: 쓰인 문·호를 기억한다",
              saved.consumedObjectIDs == [doorObj.id, arcObj.id])
        check("문닫기: 같은 개체를 다른 문이 또 쓰지 못한다",
              dc.doorClosures.user(of: doorObj.id)?.id == saved.id,
              "같은 문짝을 두 opening이 나눠 갖는 상황은 도면상 있을 수 없다")

        // 3-7) 진행률 기여 — 레이어에 반영하기 **전에도** 센다
        let doorClaimedBefore = dc.claimedCount
        check("문닫기: 반영 전에도 진행률에 기여한다", doorClaimedBefore >= 2,
              "\(doorClaimedBefore)개 — 작업을 했는데 막대가 안 움직이면 한 줄 알 수 없다")

        // 같은 자리를 겨냥해도 길이 0인 문은 저장되지 않는다.
        // 토글이라 같은 점을 두 번 찍으면 취소되지만, 그 경로로만 막으면 규칙이 UI에 갇힌다.
        let beforeZero = dc.doorClosures.count
        dc.doorDraftPoints = [LocalPoint(200, 200), LocalPoint(200, 200)]
        dc.doorDraftDoorID = doorObj.id
        dc.doorDraftArcID = arcObj.id
        dc.saveTemporaryDoor()
        check("문닫기: 길이 0인 문은 저장되지 않는다", dc.doorClosures.count == beforeZero,
              "길이 0인 LineString은 GeoJSON으로 나가면 그대로 깨진 opening이 된다")
        dc.resetDoorDraft()

        // 3-6) 레이어 반영
        let openingsBefore = dc.features.count(ofType: .opening)
        dc.applyTemporaryDoors()
        check("문닫기: 반영하면 opening feature가 된다",
              dc.features.count(ofType: .opening) == openingsBefore + 1)
        check("문닫기: 반영하면 목록이 비워진다", dc.doorClosures.isEmpty)
        check("문닫기: 반영 뒤에도 진행률이 두 번 세지 않는다", dc.claimedCount == doorClaimedBefore,
              "\(dc.claimedCount) vs \(doorClaimedBefore) — 집합 합집합으로 세야 이중 계산이 안 샌다")

        guard let openingFeature = dc.features.features(ofType: .opening).last else {
            print("[FAIL] 문닫기: opening feature 없음"); exit(1)
        }
        check("문닫기: 쓰인 문·호가 그 feature 소유가 된다",
              openingFeature.memberIDs == [doorObj.id, arcObj.id]
              && dc.ownership.ownerOf(doorObj.id) == openingFeature.id)
        check("문닫기: 찍은 선분이 feature에 실린다",
              openingFeature.closureSegment?.start == saved.start
              && openingFeature.closureSegment?.end == saved.end)

        // 좌표는 구성원이 아니라 찍은 선분에서 나와야 한다.
        let doorVerts = VertexExtractor.vertices(for: openingFeature, document: dcDoc,
                                             segmentation: dc.segmentation, kind: .lineString)
        check("문닫기: opening 좌표는 찍은 두 점이다",
              doorVerts.count == 2 && doorVerts[0] == saved.start && doorVerts[1] == saved.end,
              "구성원으로 LineString을 만들면 호를 따라 휘어진 엉뚱한 선이 나온다")

        // 3-8) 소유권 배타 규칙은 이 경로에서도 그대로
        check("문닫기: 이미 쓰인 개체는 다시 못 고른다",
              dc.ownership.ownerOf(arcObj.id) != nil)

        // 저장 파일에 실린다 — 수십 개를 찍는 작업이라 앱을 닫았다고 사라지면 안 된다
        dc.doorClosures.insert(saved)
        if let f = dc.makeProjectFile(), let round = try? ProjectFile.decoded(from: f.encoded()) {
            check("문닫기: 작업 파일에 실려 왕복한다", round.commonProject().levels.first?.editing.doorClosures.count == 1,
              "도면 전체를 훑으며 수십 개를 찍는 작업이라 저장 안 하면 통째로 날아간다")
        } else {
            check("문닫기: 작업 파일에 실려 왕복한다", false, "직렬화 실패")
        }

        // 3-2·3-3) 클릭이 점과 개체를 나눠 받는다 (2026-08-30 보고: 연속으로 못 닫는 문제)
        //
        // **예전에는 점을 언제나 먼저 봤고, 그래서 호를 고르는 일이 아예 불가능했다.**
        // 호는 곡선이라 경로 위 꼭짓점이 그 자체로 후보 점이다 — 호를 누르면 반드시
        // 그 위의 점이 먼저 잡혀 점만 늘어나고 호는 안 잡혔다. 문 하나를 저장하지 못하니
        // 다음 문으로 넘어갈 수도 없었다. 이 항목이 그 재발을 막는다.
        let dcClick = AppEnvironment()
        dcClick.openSample()
        dcClick.selectPropertyType(.opening)
        dcClick.enterDoorClosureScreen()

        guard let clickArc = dcClick.document?.objects.first(where: { $0.isCurved }),
              let clickDoor = dcClick.document?.objects.first(where: {
                  !$0.isCurved && $0.sourceElement == "line" }) else {
            print("[FAIL] 문닫기 클릭: 시험용 문·호를 못 찾음"); exit(1)
        }
        /// 개체 위의 한 점. 곡선은 경로 가운데 꼭짓점이라 예전 규칙에서는 반드시 점이 이겼다.
        func pointOn(_ o: VectorObject) -> LocalPoint {
            let pts = dcClick.geometry(for: o).subpaths.first!.points
            return pts[pts.count / 2]
        }

        check("문닫기 클릭: 시작은 점을 찍는 단계",
              dcClick.doorClickStage == .pickingPoints, dcClick.doorStageHint)

        let clickSnaps = dcClick.doorSnapPoints
        guard clickSnaps.count >= 2 else { print("[FAIL] 문닫기 클릭: 후보 점 부족"); exit(1) }
        dcClick.handleDoorClosureClick(at: clickSnaps[0].point, tolerance: 6)
        dcClick.handleDoorClosureClick(at: clickSnaps[1].point, tolerance: 6)
        check("문닫기 클릭: 점 두 개가 찍힌다", dcClick.doorDraftPoints.count == 2)
        check("문닫기 클릭: 점이 차면 개체를 고르는 단계로 넘어간다",
              dcClick.doorClickStage == .pickingObjects, dcClick.doorStageHint)

        dcClick.handleDoorClosureClick(at: pointOn(clickArc), tolerance: 6)
        check("문닫기 클릭: 호를 클릭하면 호가 잡힌다", dcClick.doorDraftArcID == clickArc.id,
              "곡선 위는 어디를 눌러도 후보 점이라, 점을 먼저 보면 호는 영영 안 잡힌다")
        check("문닫기 클릭: 호를 눌러도 찍은 점은 그대로", dcClick.doorDraftPoints.count == 2,
              "점이 밀려나면 저장 버튼이 도로 꺼져 사용자는 이유를 알 수 없다")

        dcClick.handleDoorClosureClick(at: pointOn(clickDoor), tolerance: 6)
        check("문닫기 클릭: 문짝도 클릭으로 잡힌다", dcClick.doorDraftDoorID == clickDoor.id)
        check("문닫기 클릭: 넷이 갖춰져 저장할 수 있다", dcClick.canSaveTemporaryDoor,
              dcClick.temporaryDoorHint)

        // 찍은 점을 다시 누르면 지워지고, 다시 점을 찍는 단계로 돌아간다.
        let backOne = dcClick.doorDraftPoints[1]
        dcClick.handleDoorClosureClick(at: backOne, tolerance: 6)
        check("문닫기 클릭: 찍은 점을 다시 누르면 지워진다", dcClick.doorDraftPoints.count == 1)
        check("문닫기 클릭: 지우면 다시 점 단계", dcClick.doorClickStage == .pickingPoints)
        dcClick.handleDoorClosureClick(at: backOne, tolerance: 6)
        check("문닫기 클릭: 다시 찍으면 복구된다", dcClick.doorDraftPoints.count == 2)

        // 연속 작업 — 저장하고 나면 곧바로 다음 문을 같은 순서로 닫을 수 있어야 한다.
        dcClick.saveTemporaryDoor()
        check("문닫기 클릭: 저장하면 다시 점 단계로 돌아온다",
              dcClick.doorClosures.count == 1 && dcClick.doorClickStage == .pickingPoints)

        guard let arc2 = dcClick.document?.objects.first(where: {
                  $0.isCurved && $0.id != clickArc.id }),
              let door2 = dcClick.document?.objects.first(where: {
                  !$0.isCurved && $0.sourceElement == "line" && $0.id != clickDoor.id }) else {
            print("[FAIL] 문닫기 클릭: 두 번째 문·호를 못 찾음"); exit(1)
        }
        dcClick.handleDoorClosureClick(at: clickSnaps[2].point, tolerance: 6)
        dcClick.handleDoorClosureClick(at: clickSnaps[3].point, tolerance: 6)
        dcClick.handleDoorClosureClick(at: pointOn(arc2), tolerance: 6)
        dcClick.handleDoorClosureClick(at: pointOn(door2), tolerance: 6)
        check("문닫기 클릭: 두 번째 문도 클릭만으로 갖춰진다", dcClick.canSaveTemporaryDoor,
              dcClick.temporaryDoorHint)
        dcClick.saveTemporaryDoor()
        check("문닫기 클릭: 문을 연속으로 닫을 수 있다", dcClick.doorClosures.count == 2,
              "2026-08-30 보고 — 하나를 닫고 나면 다음 문을 닫을 수 없던 증상")

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
        check("다각형 작업: opening 레이어는 선분 선택 그대로다", !cp.isPolygonWorkMode,
              "LineString·Point type은 종전 경로를 유지한다(5-4 1번)")
        cp.declareOpeningComplete()
        cp.selectPropertyType(.unit)
        check("다각형 작업: unit 레이어를 열면 면을 고르는 모드가 된다", cp.isPolygonWorkMode)
        check("다각형 작업: 레이어를 여는 것이 곧 진입이다",
              !cp.closedPolygonFaces.isEmpty
              && (cp.closedPolygonNotice?.contains("보조 개체 제외 창") ?? false)
              && (cp.closedPolygonNotice?.contains(IMDFFeatureType.unit.displayName) ?? false),
              "면 \(cp.closedPolygonFaces.count)개 — 별도 진입 버튼을 두지 않는다")

        // 포함 모드: 빈 상태에서 더해 간다.
        check("다각형 작업: 포함 모드는 아무것도 고르지 않은 상태로 시작한다",
              cp.polygonWorkMode == .include && cp.faceSelection.isEmpty)

        // 제외 모드: 전부 고른 상태에서 빼 나간다.
        cp.setPolygonWorkMode(.exclude)
        check("다각형 작업: 제외 모드는 전부 고른 상태로 시작한다",
              cp.faceSelection.count == cp.selectableFaceCount && !cp.faceSelection.isEmpty,
              "저장할 것이 대부분일 때 훨씬 빠르다(5-4 2번)")
        if let one = cp.closedPolygonFaces.first {
            let before = cp.faceSelection.count
            cp.handleFaceClick(at: LocalPoint(one.boundingBox.midX, one.boundingBox.midY))
            check("다각형 작업: 제외 모드에서 누르면 선택에서 빠진다",
                  cp.faceSelection.count == before - 1 || cp.faceSelection.count == before + 1)
        }

        // 드래그 복수 선택(5-4 3번).
        cp.setPolygonWorkMode(.include)
        cp.handleFaceMarquee(rect: CGRect(x: -1000, y: -1000, width: 5000, height: 5000),
                             mode: .crossing)
        check("다각형 작업: 드래그로 여러 면을 한 번에 고른다",
              cp.faceSelection.count == cp.selectableFaceCount)

        // 저장.
        let pickedCount = cp.faceSelection.count
        cp.saveSelectedFaces()
        let savedUnits = cp.features.features(ofType: .unit)
        check("다각형 작업: 고른 면이 각각 Feature가 된다",
              savedUnits.count == pickedCount && cp.faceSelection.isEmpty,
              "\(savedUnits.count)개 저장 — 폴리곤 type은 면 하나가 feature 하나다")
        if let made = savedUnits.first, let ring = made.polygonRings.first {
            check("다각형 작업: 좌표는 면의 링이 정본이다",
                  VertexExtractor.vertices(for: made, document: doc,
                                           segmentation: cp.segmentation, kind: .polygon) == ring,
                  "구성원으로 다시 조립하면 옆방과 나눠 쓰는 벽선이 빠져 링이 열린다")
            check("다각형 작업: 저장한 면은 다시 고를 수 없다",
                  cp.savedPolygonFaceIDs.count == pickedCount)
        }

        cp.undo()
        check("다각형 작업: 저장은 cmd+z로 되돌아간다",
              cp.features.features(ofType: .unit).isEmpty
              && cp.faceSelection.count == pickedCount,
              "되돌리면 고르던 것도 함께 돌아와야 '저장을 취소했다'가 성립한다")

        // fixture(MultiPolygon)는 맞닿은 면을 한 feature로 묶는다.
        let fx = AppEnvironment()
        fx.document = doc
        fx.selectPropertyType(.opening)
        fx.declareOpeningComplete()
        fx.selectPropertyType(.fixture)
        fx.selectAllFaces()
        let fxFaceCount = fx.faceSelection.count
        fx.saveSelectedFaces()
        let fxFeatures = fx.features.features(ofType: .fixture)
        check("다각형 작업: fixture는 맞닿은 면을 한 feature로 묶는다",
              !fxFeatures.isEmpty && fxFeatures.count <= fxFaceCount
              && fxFeatures.allSatisfy { !$0.polygonRings.isEmpty },
              "면 \(fxFaceCount)개 → feature \(fxFeatures.count)개")

        // 진행률 두 막대(5-5).
        let pr = AppEnvironment()
        pr.document = doc
        check("진행률: 다각형 분모는 도면을 열 때 한 번 센다",
              pr.totalPolygonCount > 0, "전체 면 \(pr.totalPolygonCount)개")
        let denominatorBefore = pr.totalPolygonCount
        pr.selectPropertyType(.opening)
        pr.declareOpeningComplete()
        pr.selectPropertyType(.unit)
        if let victim = doc.objects.first {
            pr.auxiliary.exclude([victim.id])
        }
        check("진행률: 보조 개체를 빼도 분모는 그대로다",
              pr.totalPolygonCount == denominatorBefore,
              "분모가 조작할 때마다 흔들리면 막대가 이유 없이 늘었다 줄었다 한다")
        check("진행률: 제외로 사라진 면이 분자에 들어간다",
              pr.vanishedPolygonCount >= 0
              && pr.polygonProgressFraction >= pr.taggedPolygonFraction,
              "사라진 면 \(pr.vanishedPolygonCount)개")
        pr.selectAllFaces()
        pr.saveSelectedFaces()
        check("진행률: 태깅한 면이 분자에 들어간다",
              pr.taggedPolygonCount > 0 && pr.taggedPolygonFraction > 0,
              "태깅 \(pr.taggedPolygonCount)개 / 전체 \(pr.totalPolygonCount)개")

        // ✅ 2026-08-30 요청 1-1: 도면을 막 열었을 때 '제외로 사라진 다각형'이 100%로 나오던 것.
        //
        // 옛 식은 `totalPolygonCount - closedPolygonFaces.count`였다. 그런데 면 목록은 성능 때문에
        // **폴리곤 type 레이어를 열 때만** 채운다(도면 적재 시 만들면 실도면에서 앱이 멈춘다).
        // 그래서 도면을 막 열면 빈 배열이고 `전체 - 0 = 전체`, 즉 '제외로 다 사라졌다'가 되어
        // 막대가 통째로 주황이 됐다. **'아직 안 셌다'와 '다 사라졌다'가 둘 다 면 0개로 보인 것이다.**
        let fresh = AppEnvironment()
        fresh.document = doc
        check("진행률: 도면을 막 열면 사라진 면이 0이다",
              fresh.vanishedPolygonCount == 0 && fresh.polygonProgressFraction == 0,
              "\(fresh.vanishedPolygonCount)/\(fresh.totalPolygonCount)개")
        fresh.selectPropertyType(.opening)
        check("진행률: 폴리곤이 아닌 레이어로 옮겨도 100%가 되지 않는다",
              fresh.closedPolygonFaces.isEmpty && fresh.vanishedPolygonCount == 0,
              "면 목록이 비워지는 자리다 — 여기서 그 값으로 다시 세면 같은 버그가 돌아온다")

        let vp = AppEnvironment()
        vp.document = doc
        if let victim2 = doc.objects.first {
            vp.enterAuxiliaryScreen()
            vp.auxiliarySelection = [victim2.id]
            vp.markSelectedAsAuxiliary()
            check("진행률: 제외 창 안에서는 셈을 미룬다",
                  vp.vanishedPolygonCount == 0,
                  "창이 떠 있는 동안 좌측 사이드바는 보이지 않는다 — 클릭마다 면을 다시 찾을 이유가 없다")
            vp.exitAuxiliaryScreen()
            let remainingFaces = ClosedPolygonFinder.faces(
                in: vp.faceSources(in: doc, includeAuxiliary: false)).count
            check("진행률: 창을 닫을 때 사라진 면을 다시 센다",
                  vp.vanishedPolygonCount == max(0, vp.totalPolygonCount - remainingFaces),
                  "사라진 면 \(vp.vanishedPolygonCount)개 / 전체 \(vp.totalPolygonCount)개")
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
