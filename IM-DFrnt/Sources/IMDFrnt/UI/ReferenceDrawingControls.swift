import SwiftUI

struct ReferenceDrawingLayerControls: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reference = env.activeLevel?.referenceDrawing {
                DrawingLayerVisibilityControls(title: "참고 도면", kind: "reference", value: reference.presentation)
                Text(reference.sourceName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Button(env.isAligningReferenceDrawing ? "참고 도면 정렬 완료" : "화면에서 참고 도면 정렬") {
                    env.isAligningReferenceDrawing.toggle()
                }
                .accessibilityLabel(env.isAligningReferenceDrawing ? "참고 도면 정렬 완료" : "화면에서 참고 도면 정렬")
                .disabled(!reference.presentation.isVisible || reference.presentation.opacity == 0)
                Button("참고 도면 교체…") { env.importReferenceDrawing() }
                Button(role: .destructive) { env.requestReferenceDrawingDeletion() } label: {
                    Text("참고 도면 삭제").foregroundStyle(.red)
                }
            } else {
                Button("참고 도면 불러오기…") { env.importReferenceDrawing() }
            }
        }
        .controlSize(.small)
        .disabled(env.isProjectBusy || env.activeLevel == nil)
    }
}

struct ReferenceDrawingAlignmentControls: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var moveStep = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("참고 도면 정렬").font(.headline)
                Spacer()
                Button("완료") { env.isAligningReferenceDrawing = false }
            }
            Text("화면에서 드래그하면 참고 도면만 이동합니다.")
                .font(.caption).foregroundStyle(.secondary)
            movementControls
            field("가로 위치", key: \.x, step: moveStep)
            field("세로 위치", key: \.y, step: moveStep)
            field("회전 (°)", key: \.rotation, step: 0.1)
            Slider(value: binding(\.rotation), in: -360...360)
                .accessibilityLabel("참고 도면 회전")
            field("배율 (1 = 원래 크기)", key: \.scale, step: 0.01)
            HStack {
                Button("축소 −") { resize(by: 1 / 1.01) }
                Button("확대 +") { resize(by: 1.01) }
                Spacer()
                Button("정렬 초기화") { env.updateReferenceDrawingAlignment(ReferenceDrawingAlignment()) }
            }
            Text("도면 좌표 기준 · 기본 도면과 IMDF 작업은 바뀌지 않습니다.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .padding(12).frame(width: 320)
        .toolbarCard(cornerRadius: 8)
        .buttonStyle(.toolbar)
        .environment(\.colorScheme, env.canvasBackground == .light ? .light : .dark)
        .disabled(env.isProjectBusy)
    }

    private var movementControls: some View {
        HStack {
            Button { move(x: -moveStep, y: 0) } label: { Image(systemName: "arrow.left") }.help("참고 도면 왼쪽 이동")
            VStack(spacing: 4) {
                Button { move(x: 0, y: -moveStep) } label: { Image(systemName: "arrow.up") }.help("참고 도면 위로 이동")
                Button { move(x: 0, y: moveStep) } label: { Image(systemName: "arrow.down") }.help("참고 도면 아래로 이동")
            }
            Button { move(x: moveStep, y: 0) } label: { Image(systemName: "arrow.right") }.help("참고 도면 오른쪽 이동")
            Spacer()
            Stepper("이동 간격 \(moveStep, specifier: "%.1f")", value: $moveStep, in: 0.1...100, step: 0.1)
        }
    }

    private func binding(_ key: WritableKeyPath<ReferenceDrawingAlignment, Double>) -> Binding<Double> {
        Binding(get: { env.referenceDrawingAlignment[keyPath: key] }, set: { value in
            var alignment = env.referenceDrawingAlignment
            alignment[keyPath: key] = value
            env.updateReferenceDrawingAlignment(alignment, coalescingKey: "reference-field:\(env.routingFloorID?.uuidString ?? ""):\(key)")
        })
    }

    private func field(_ title: String, key: WritableKeyPath<ReferenceDrawingAlignment, Double>, step: Double) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            TextField(title, value: binding(key), format: .number.precision(.fractionLength(0...3)))
                .frame(width: 90).accessibilityLabel("참고 도면 \(title)")
            Stepper(title, onIncrement: { binding(key).wrappedValue += step },
                    onDecrement: { binding(key).wrappedValue -= step }).labelsHidden()
        }
    }

    private func move(x: Double, y: Double) {
        var alignment = env.referenceDrawingAlignment
        alignment.x += x; alignment.y += y
        env.updateReferenceDrawingAlignment(alignment)
    }

    private func resize(by factor: Double) {
        var alignment = env.referenceDrawingAlignment
        alignment.scale *= factor
        env.updateReferenceDrawingAlignment(alignment)
    }
}
