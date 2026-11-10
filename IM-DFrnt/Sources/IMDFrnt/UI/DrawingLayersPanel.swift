import SwiftUI

struct DrawingLayersPanel: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let level = env.activeLevel {
                Text("\(level.info.name) 도면 레이어").font(.headline)
                if level.info.imdfCoordinates == nil {
                    DrawingLayerVisibilityControls(title: "기본 도면", kind: "svg", value: env.primarySVGPresentation)
                    Button("이 층 도면 불러오기…") { env.importRoutingDrawing() }
                } else {
                    Text("IMDF 도형").font(.callout.weight(.medium))
                }
                ReferenceDrawingLayerControls()
                Text("전역 Footprint의 표시·편집은 메인 화면의 footprint 레이어에서 관리합니다.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("먼저 층을 추가하세요.").foregroundStyle(.secondary)
            }
        }
        .disabled(env.isProjectBusy)
    }

}

struct DrawingLayerVisibilityControls: View {
    @EnvironmentObject var env: AppEnvironment
    let title: String
    let kind: String
    let value: DrawingLayerPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: Binding(get: { value.isVisible }, set: { env.updateDrawingLayer(kind, visible: $0) }))
            HStack {
                Text("불투명도").font(.caption)
                Slider(value: Binding(get: { value.opacity }, set: { env.updateDrawingLayer(kind, opacity: $0) }), in: 0...1)
                    .accessibilityLabel("\(title) 불투명도")
                Text("\(Int(value.opacity * 100))%").font(.caption.monospacedDigit()).frame(width: 38)
            }.disabled(!value.isVisible)
        }
    }
}
