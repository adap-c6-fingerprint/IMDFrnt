import AppKit
import CoreGraphics
import SwiftUI

/// 이미지 레이어의 조정 상태와 조작 중 미리보기(신기능 15항, #84).
///
/// `MoveSession`과 같은 이유로 `AppEnvironment`에 `@Published`가 아닌 `let`으로 둔다.
/// 끄는 동안 바뀌는 값을 환경에 두면 1픽셀마다 좌·우 사이드바가 통째로 다시 그려진다.
/// 이 객체는 캔버스와 이미지 줄만 구독하고, 결과는 손을 뗄 때 한 번만 프로젝트에 넣는다.
@MainActor
final class ImageOverlaySession: ObservableObject {
    /// 이동·크기·회전을 조정 중인 이미지의 type. `nil`이면 이미지는 클릭을 받지 않는다.
    @Published var adjusting: IMDFFeatureType?
    /// 조작 중인 값. 손을 떼면 비운다. 키는 type 이름이다.
    @Published private(set) var preview: [String: LevelImageOverlay] = [:]

    private var decoded: [UUID: CGImage] = [:]

    func setPreview(_ overlay: LevelImageOverlay, for type: IMDFFeatureType) { preview[type.rawValue] = overlay }
    func clearPreview(for type: IMDFFeatureType) { preview.removeValue(forKey: type.rawValue) }
    func clearAll() { adjusting = nil; preview = [:] }

    /// 그릴 이미지. 바이트는 처음 한 번만 풀고 그 뒤로는 캐시를 쓴다.
    func image(for data: ImageOverlayData) -> CGImage? {
        if let image = decoded[data.id] { return image }
        guard let image = ImageOverlayImport.decode(data) else { return nil }
        remember(image, for: data)
        return image
    }

    func remember(_ image: CGImage, for data: ImageOverlayData) {
        if decoded.count >= 12 { decoded.removeAll() }
        // 층·type을 오가며 쌓이는 것만 막는다. 큰 사진 한 장이 수십 MB라 상한 없이 두면 메모리가 는다.
        decoded[data.id] = image
    }
}

@MainActor
extension AppEnvironment {
    func imageOverlay(for type: IMDFFeatureType) -> LevelImageOverlay? {
        activeLevel?.imageOverlays?[type.rawValue]
    }

    /// 지금 층에서 그릴 이미지. 그 type 레이어가 열려 있고 숨겨지지 않았을 때만 보인다.
    var visibleImageOverlays: [(type: IMDFFeatureType, overlay: LevelImageOverlay)] {
        guard let overlays = activeLevel?.imageOverlays, !overlays.isEmpty else { return [] }
        return IMDFFeatureType.allCases.compactMap { type in
            guard let overlay = overlays[type.rawValue], overlay.presentation.isVisible,
                  let layer = layers.layer(for: type), !layer.isHidden else { return nil }
            return (type, overlay)
        }
    }

    func importImageOverlay(for type: IMDFFeatureType) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageOverlayImport.allowedTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "\(type.displayName) 레이어에 얹을 이미지 (JPG·PNG·HEIC)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importImageOverlay(at: url, for: type) }
    }

    func importImageOverlay(at url: URL, for type: IMDFFeatureType) async {
        guard let levelID = routingFloorID else { return }
        do {
            let prepared = try await Task.detached(priority: .userInitiated) { try ImageOverlayImport.prepare(url: url) }.value
            guard routingFloorID == levelID else { return }
            setImageOverlay(prepared, for: type)
        } catch {
            notify(error.localizedDescription, isError: true)
        }
    }

    /// 이미지를 type 레이어에 얹는다. 이미 있으면 바꾸되, 맞춰 둔 위치·크기·회전·투명도는 이어 받는다.
    func setImageOverlay(_ prepared: ImageOverlayImport.Prepared, for type: IMDFFeatureType) {
        guard let i = buildingProject.levels.firstIndex(where: { $0.id == routingFloorID }) else { return }
        imageOverlays.remember(prepared.image, for: prepared.data)
        var overlay = LevelImageOverlay(image: prepared.data, sourceName: prepared.sourceName,
                                        pixelWidth: Double(prepared.image.width), pixelHeight: Double(prepared.image.height),
                                        centerX: 0, centerY: 0, scale: 1)
        if let old = buildingProject.levels[i].imageOverlays?[type.rawValue] {
            overlay.center = old.center
            overlay.rotation = old.rotation
            overlay.presentation = old.presentation
            overlay.setScale(old.scale * max(old.pixelWidth, old.pixelHeight) / max(overlay.pixelWidth, overlay.pixelHeight))
            // 같은 현장을 다시 찍은 사진으로 바꾸는 경우가 많다. 긴 변의 도면 길이를 지켜 맞춘 자리를 잃지 않게 한다.
        } else {
            overlay.fit(in: document?.canvasSize ?? CGSize(width: 1000, height: 800))
        }
        perform("\(type.displayName) 이미지 레이어 추가") {
            buildingProject.levels[i].imageOverlays = (buildingProject.levels[i].imageOverlays ?? [:])
                .merging([type.rawValue: overlay]) { $1 }
        }
        imageOverlays.adjusting = type
        // 처음 얹은 이미지는 거의 늘 자리를 맞춰야 하므로 조정 모드로 바로 들어간다.
        notify("\(prepared.sourceName)을 \(buildingProject.levels[i].info.name) \(type.displayName) 레이어에 얹었습니다. 끌어서 옮기고, ⇧로 크기·⌥로 회전을 맞추세요.")
    }

    /// 프로젝트에 넣는 변경. 끌기·슬라이더는 손을 뗄 때 한 번만 부르므로 실행취소 한 칸 = 조작 한 번이다.
    func updateImageOverlay(_ type: IMDFFeatureType, _ change: (inout LevelImageOverlay) -> Void) {
        guard let i = buildingProject.levels.firstIndex(where: { $0.id == routingFloorID }),
              var overlay = buildingProject.levels[i].imageOverlays?[type.rawValue] else { return }
        change(&overlay)
        perform("\(type.displayName) 이미지 레이어 조정") {
            buildingProject.levels[i].imageOverlays?[type.rawValue] = overlay
        }
        imageOverlays.clearPreview(for: type)
    }

    func requestImageOverlayDeletion(_ type: IMDFFeatureType) {
        guard let id = routingFloorID, let overlay = imageOverlay(for: type) else { return }
        requestDeletion(title: "이미지 레이어를 삭제할까요?",
                        message: "\(overlay.sourceName)을 \(type.displayName) 레이어에서 제거합니다. 그 위에서 그린 feature는 유지됩니다.") { env in
            env.perform("\(type.displayName) 이미지 레이어 삭제") {
                guard let i = env.buildingProject.levels.firstIndex(where: { $0.id == id }) else { return }
                env.buildingProject.levels[i].imageOverlays?.removeValue(forKey: type.rawValue)
                if env.buildingProject.levels[i].imageOverlays?.isEmpty == true { env.buildingProject.levels[i].imageOverlays = nil }
                // 비면 칸을 없앤다. 이미지를 한 번도 안 쓴 프로젝트와 저장 결과가 같아야 한다.
            }
            if env.imageOverlays.adjusting == type { env.imageOverlays.adjusting = nil }
        }
    }
}

@MainActor
extension ImageOverlaySession {
    /// 화면에 보이는 값. 조작 중이면 미리보기, 아니면 저장된 값이다.
    func current(_ type: IMDFFeatureType, in env: AppEnvironment) -> LevelImageOverlay? {
        preview[type.rawValue] ?? env.imageOverlay(for: type)
    }

    /// 슬라이더를 움직이는 동안의 변경. 미리보기만 바꿔 캔버스와 이 줄만 다시 그린다.
    func edit(_ type: IMDFFeatureType, in env: AppEnvironment, _ change: (inout LevelImageOverlay) -> Void) {
        guard var overlay = current(type, in: env) else { return }
        change(&overlay)
        setPreview(overlay, for: type)
    }

    /// 손을 뗐을 때 미리보기를 프로젝트에 넣는다.
    func commit(_ type: IMDFFeatureType, in env: AppEnvironment) {
        guard let overlay = preview[type.rawValue] else { return }
        env.updateImageOverlay(type) { $0 = overlay }
    }
}
