import SwiftUI

/// feature type 줄 아래의 이미지 레이어 줄(신기능 15항, #84). 추가·표시·투명도·조정·바꾸기·삭제.
struct ImageOverlayRow: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var overlays: ImageOverlaySession
    let type: IMDFFeatureType

    var body: some View {
        if let overlay = overlays.current(type, in: env) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        env.updateImageOverlay(type) { $0.presentation.isVisible.toggle() }
                    } label: {
                        Image(systemName: overlay.presentation.isVisible ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help(overlay.presentation.isVisible ? "이미지 숨기기" : "이미지 보이기")
                    Image(systemName: "photo").font(.caption).foregroundStyle(.secondary)
                    Text(overlay.sourceName)
                        .font(.caption).lineLimit(1).truncationMode(.middle)
                        .help(overlay.sourceName)
                    Spacer(minLength: 4)
                    Button {
                        overlays.adjusting = isAdjusting ? nil : type
                    } label: {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .foregroundStyle(isAdjusting ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!overlay.presentation.isVisible)
                    .help(isAdjusting ? "조정 끝내기" : "이미지 이동·크기·회전 조정")
                    Button { env.importImageOverlay(for: type) } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.borderless)
                        .help("다른 이미지로 바꾸기 (맞춘 위치·크기·회전은 유지)")
                    Button { env.requestImageOverlayDeletion(type) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).controlSize(.mini)
                        .help("이미지 레이어 삭제")
                }
                ImageOverlayOpacitySlider(type: type, overlay: overlay)
                    .disabled(!overlay.presentation.isVisible)
                    .opacity(overlay.presentation.isVisible ? 1 : 0.4)
            }
            .padding(6)
            .background(isAdjusting ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 5))
        } else {
            Button { env.importImageOverlay(for: type) } label: {
                Label("이미지 레이어 추가…", systemImage: "photo.badge.plus").font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(env.document == nil || env.activeLevel == nil)
            .help("이 층의 \(type.displayName) 레이어 위에 현장 사진·실내지도(JPG·PNG·HEIC)를 얹습니다.")
        }
    }

    private var isAdjusting: Bool { overlays.adjusting == type }
}

/// 투명도 슬라이더. 움직이는 동안은 미리보기만 바꾸고, 손을 떼면 한 번 저장한다.
struct ImageOverlayOpacitySlider: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var overlays: ImageOverlaySession
    let type: IMDFFeatureType
    let overlay: LevelImageOverlay

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.lefthalf.filled").font(.caption2).foregroundStyle(.secondary)
            Slider(value: Binding(get: { overlay.presentation.opacity },
                                  set: { v in overlays.edit(type, in: env) { $0.presentation.opacity = v } }),
                   in: EditorLayer.minimumOpacity...1.0) { editing in
                if !editing { overlays.commit(type, in: env) }
            }
            .controlSize(.mini)
            .accessibilityLabel("이미지 불투명도")
            Text("\(Int((overlay.presentation.opacity * 100).rounded()))%")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

/// 이미지 조정 모드의 캔버스 상단바. 끌기로 대강 맞추고 여기서 수치로 다듬는다.
struct ImageOverlayToolbar: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var overlays: ImageOverlaySession
    let type: IMDFFeatureType

    var body: some View {
        if let overlay = overlays.current(type, in: env) {
            let fit = overlay.fitScale(in: env.document?.canvasSize ?? .zero)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Label("\(type.displayName) 이미지 조정", systemImage: "photo").font(.callout.weight(.semibold))
                    Text("끌기: 이동 · ⇧ 끌기: 크기 · ⌥ 끌기: 회전")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    Button("도면에 맞추기") {
                        env.updateImageOverlay(type) { $0.fit(in: env.document?.canvasSize ?? .zero) }
                    }
                    .controlSize(.small)
                    Button("완료") { overlays.adjusting = nil }
                        .controlSize(.small)
                }
                HStack(spacing: 14) {
                    labeled("크기", "\(Int((overlay.scale / fit * 100).rounded()))%") {
                        Slider(value: Binding(get: { log2(overlay.scale / fit) },
                                              set: { v in overlays.edit(type, in: env) { $0.setScale(fit * pow(2, v)) } }),
                               in: -4...4) { if !$0 { overlays.commit(type, in: env) } }
                    }
                    labeled("회전", "\(String(format: "%.1f", overlay.rotation))°") {
                        HStack(spacing: 4) {
                            Button { env.updateImageOverlay(type) { $0.setRotation($0.rotation - 90) } } label: { Image(systemName: "rotate.left") }
                                .buttonStyle(.borderless).help("왼쪽으로 90°")
                            Slider(value: Binding(get: { overlay.rotation },
                                                  set: { v in overlays.edit(type, in: env) { $0.setRotation(v) } }),
                                   in: -180...180) { if !$0 { overlays.commit(type, in: env) } }
                            Button { env.updateImageOverlay(type) { $0.setRotation($0.rotation + 90) } } label: { Image(systemName: "rotate.right") }
                                .buttonStyle(.borderless).help("오른쪽으로 90°")
                        }
                    }
                    ImageOverlayOpacitySlider(type: type, overlay: overlay).frame(width: 150)
                }
                .controlSize(.mini)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: 720)
            .toolbarCard(cornerRadius: 10)
        }
    }

    private func labeled<Content: View>(_ title: String, _ value: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption)
            content()
            Text(value).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
        }
    }
}
