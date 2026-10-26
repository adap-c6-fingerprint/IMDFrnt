import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 신기능 15항(#84) — 이미지 레이어: 변환 계산, 가져오기(축소·방향·형식), 층·type별 저장, 실행취소, 저장 왕복.
@MainActor
enum ImageOverlaySelfTest {
    static func runIfRequested() async {
        guard CommandLine.arguments.contains("--image-overlay-selftest") else { return }
        var total = 0, failures = 0
        func check(_ name: String, _ valid: Bool) {
            total += 1; if !valid { failures += 1 }
            print("[\(valid ? "PASS" : "FAIL")] \(name)")
        }
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6 }

        // 변환: 이미지 중심이 center에, 회전·배율은 그 둘레로.
        var o = LevelImageOverlay(image: ImageOverlayData(bytes: Data()), sourceName: "t", pixelWidth: 200, pixelHeight: 100,
                                  centerX: 500, centerY: 400, scale: 2)
        check("이미지 중심 → center", near(CGPoint(x: 100, y: 50).applying(o.transform), CGPoint(x: 500, y: 400)))
        check("배율: 오른쪽 위 모서리", near(CGPoint(x: 200, y: 0).applying(o.transform), CGPoint(x: 700, y: 300)))
        o.setRotation(90)
        check("90° 회전: 오른쪽 위 모서리", near(CGPoint(x: 200, y: 0).applying(o.transform), CGPoint(x: 600, y: 600)))
        o.setRotation(270)
        check("회전은 -180~180으로 접힘", o.rotation == -90)
        o.setScale(0)
        check("배율 하한", o.scale == LevelImageOverlay.scaleRange.lowerBound)
        o.fit(in: CGSize(width: 1000, height: 800))
        check("도면에 맞추기: 90%·중앙·회전 0", abs(o.scale - 4.5) < 1e-9 && o.center == LocalPoint(500, 400) && o.rotation == 0)
        let sameID = ImageOverlayData(id: o.image.id, bytes: Data([1, 2, 3]))
        check("바이트는 비교하지 않고 ID로 같음 판정", sameID == o.image && ImageOverlayData(bytes: Data()) != o.image)

        // 가져오기
        func encoded(_ width: Int, _ height: Int, alpha: Bool, type: UTType, orientation: Int? = nil) -> Data? {
            let space = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue) else { return nil }
            ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: alpha ? 0.5 : 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            guard let image = ctx.makeImage() else { return nil }
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
            var props: [CFString: Any] = [:]
            if let orientation { props[kCGImagePropertyOrientation] = orientation }
            CGImageDestinationAddImage(dest, image, props as CFDictionary)
            return CGImageDestinationFinalize(dest) ? out as Data : nil
        }
        do {
            let big = try ImageOverlayImport.prepare(data: encoded(5000, 100, alpha: false, type: .jpeg)!, sourceName: "big.jpg")
            check("긴 변 4096px로 축소, 비율 유지", big.image.width == 4096 && abs(big.image.height - 82) <= 1)
            check("불투명 이미지는 JPEG로 저장", big.data.bytes.starts(with: [0xFF, 0xD8]))
            let rotated = try ImageOverlayImport.prepare(data: encoded(300, 200, alpha: false, type: .jpeg, orientation: 6)!, sourceName: "phone.jpg")
            check("EXIF 회전(6) 반영 → 세로 사진", rotated.image.width == 200 && rotated.image.height == 300)
            let png = try ImageOverlayImport.prepare(data: encoded(64, 32, alpha: true, type: .png)!, sourceName: "a.png")
            check("투명 PNG는 PNG로 저장", png.data.bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]))
            check("저장 바이트 다시 풀기", ImageOverlayImport.decode(png.data).map { $0.width == 64 && $0.height == 32 } == true)
            if let heic = encoded(120, 80, alpha: false, type: .heic) {
                let h = try ImageOverlayImport.prepare(data: heic, sourceName: "room.heic")
                check("HEIC 가져오기", h.image.width == 120 && h.image.height == 80 && h.data.bytes.starts(with: [0xFF, 0xD8]))
            } else {
                print("[SKIP] 이 Mac에서 HEIC 인코더를 쓸 수 없어 HEIC 시험 파일을 만들지 못함")
            }
            check("읽을 수 없는 파일은 오류", (try? ImageOverlayImport.prepare(data: Data("x".utf8), sourceName: "x.png")) == nil)

            // 층·type별 저장, 실행취소, 저장 왕복
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IMDFrntImageOverlay-\(UUID())")
            let suite = "IMDFrntImageOverlay.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { try? FileManager.default.removeItem(at: folder); defaults.removePersistentDomain(forName: suite) }
            let env = AppEnvironment(autosaveFolder: folder, projectDefaults: defaults)
            try env.createNewProject()
            env.openSample()
            env.declareOpeningComplete()
            // 사용자와 같은 순서다. opening을 먼저 확정해야 다른 type 레이어가 열린다.
            env.selectPropertyType(.fixture)
            let level1 = env.routingFloorID!
            env.setImageOverlay(png, for: .fixture)
            let placed = env.imageOverlay(for: .fixture)
            check("fixture 레이어에 이미지 추가, 도면에 맞춰 놓임", placed != nil &&
                  placed!.center == LocalPoint(env.document!.canvasSize.width / 2, env.document!.canvasSize.height / 2))
            check("추가 직후 조정 모드", env.imageOverlays.adjusting == .fixture)
            check("열린 레이어의 이미지만 그림", env.visibleImageOverlays.map(\.type) == [.fixture] && env.imageOverlay(for: .unit) == nil)
            env.layers.setHidden(true, for: env.layers.layer(for: .fixture)!.id)
            check("레이어를 숨기면 이미지도 숨김", env.visibleImageOverlays.isEmpty)
            env.layers.setHidden(false, for: env.layers.layer(for: .fixture)!.id)

            env.updateImageOverlay(.fixture) { $0.center = LocalPoint(10, 20); $0.presentation.opacity = 0.3 }
            env.updateImageOverlay(.fixture) { $0.setRotation(30) }
            check("조정 값 저장", env.imageOverlay(for: .fixture).map { $0.center == LocalPoint(10, 20) && $0.rotation == 30 && $0.presentation.opacity == 0.3 } == true)
            env.undo()
            check("실행취소 한 번 = 조작 한 번", env.imageOverlay(for: .fixture).map { $0.rotation == 0 && $0.center == LocalPoint(10, 20) } == true)
            env.redo()
            env.imageOverlays.setPreview(env.imageOverlay(for: .fixture)!, for: .fixture)
            env.imageOverlays.commit(.fixture, in: env)
            check("바뀐 것 없는 확정은 실행취소 칸을 남기지 않음", env.undoMenuTitle.contains("조정") && env.imageOverlays.preview.isEmpty)

            let draftBefore = env.pointDraft.points.count
            env.selectPropertyType(.unit)
            env.handlePointClick(at: LocalPoint(50, 50), tolerance: 6, freePoint: true, editing: false, removing: false)
            check("이미지가 있어도 점 찍기 그대로", env.pointDraft.points.count == draftBefore + 1)
            env.selectPropertyType(.fixture)

            let level2 = env.addProjectLevel()
            env.selectProjectLevel(level2)
            check("다른 층에는 보이지 않음, 층을 바꾸면 조정 모드 해제",
                  env.imageOverlay(for: .fixture) == nil && env.imageOverlays.adjusting == nil)
            env.selectProjectLevel(level1)

            let file = try ProjectFile.decoded(from: env.makeProjectFile()!.encoded())
            let reopened = AppEnvironment(autosaveFolder: folder, projectDefaults: defaults)
            try reopened.adopt(file, from: nil)
            reopened.selectProjectLevel(level1)
            let back = reopened.buildingProject.levels.first { $0.id == level1 }?.imageOverlays?["fixture"]
            check("저장·다시 열기 후 이미지·위치·회전·투명도 유지", back == env.imageOverlay(for: .fixture) &&
                  back?.image.bytes == png.data.bytes && back?.rotation == 30 && back?.presentation.opacity == 0.3)

            env.requestImageOverlayDeletion(.fixture)
            env.confirmDeletion(env.pendingDeletion!.id)
            check("삭제하면 칸도 비움", env.activeLevel?.imageOverlays == nil)
            env.undo()
            check("삭제 실행취소", env.imageOverlay(for: .fixture) != nil)
        } catch {
            check("이미지 레이어 통합 검사", false); print(error)
        }
        print("== Image Overlay: \(total - failures)/\(total) PASS ==")
        exit(failures == 0 ? 0 : 1)
    }
}
