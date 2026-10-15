import SwiftUI

struct DrawingLayersPanel: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let level = env.activeLevel {
                Text("\(level.info.name) 도면 레이어").font(.headline)
                if level.info.imdfCoordinates == nil {
                    controls("SVG 도면", kind: "svg", value: env.primarySVGPresentation)
                    Button("이 층 도면 불러오기…") { env.importRoutingDrawing() }
                } else {
                    Text("IMDF 도형").font(.callout.weight(.medium))
                    if let reference = level.referenceDrawing {
                        controls("참고 SVG", kind: "reference", value: reference.presentation)
                        Text(reference.sourceName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Button(role: .destructive) { env.requestReferenceDrawingDeletion() } label: { Text("참고 도면 삭제").foregroundStyle(.red) }
                    }
                    Button("참고 도면 불러오기…") { env.importRoutingDrawing() }
                    Text("참고 도면은 도면 영역에 맞춰 표시됩니다.").font(.caption2).foregroundStyle(.secondary)
                }
                Divider()
                controls("건물 Footprint", kind: "footprint", value: env.footprintPresentation)
                if !level.info.hasGeographicCoordinates {
                    Text("좌표 기준점을 설정하면 건물 외곽이 표시됩니다.").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("먼저 층을 추가하세요.").foregroundStyle(.secondary)
            }
        }
        .disabled(env.isProjectBusy)
    }

    private func controls(_ title: String, kind: String, value: DrawingLayerPresentation) -> some View {
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
