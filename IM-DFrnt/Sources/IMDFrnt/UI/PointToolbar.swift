import SwiftUI

/// 점 단위 편집의 상단바(#21).
///
/// **선택이 없어도 항상 뜬다.** 이 모드에서는 *무엇을 더 찍어야 하는지*가 곧 안내다
/// (문 닫기 창 3-4·다각형 상단바와 같은 이유).
struct PointToolbar: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            controls
            HStack(spacing: 6) {
                Text(env.pointStageHint)
                    .font(.caption)
                    .fixedSize()
                if env.isComputingDerivedGeometry {
                    ProgressView().controlSize(.mini)
                    Text("꼭짓점·교점 계산 중").font(.caption2).foregroundStyle(.secondary)
                }
            }
            // 안내는 둘째 줄에 둔다. 도구가 늘어 한 줄에 다 놓으면 캔버스 폭을 넘어 오른쪽 버튼이 잘렸다.
        }
        .buttonStyle(.toolbarIcon)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .toolbarCard(cornerRadius: 10)
        .help("꼭짓점·교점 근처를 누르면 그 점에 붙습니다. 새 점은 ⌥(Option)을 누른 채 클릭합니다. 저장된 도형의 꼭짓점은 Shift+클릭으로 뺍니다.")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            LayerEditModePicker()
            if env.layers.activePropertyType == .unit {
                UnitToolPicker()
            }

            Text("점 \(env.pointDraft.points.count)개")
                .font(.caption.monospacedDigit())
                .foregroundStyle(env.pointDraft.isEmpty ? .secondary : .primary)

            if env.unitToolInUse == .cut {
                Button {
                    env.cutUnitsAlongDraft()
                } label: {
                    Label("자르기", systemImage: "scissors")
                }
                .disabled(env.pointDraft.points.count < 2)
                .help("선이 가로지른 unit을 나눕니다. (Return)")
            } else if env.unitToolInUse == .guide {
                Text("보조 선분 \(env.features.guides.count)개").font(.caption.monospacedDigit()).fixedSize()
                Button {
                    env.perform("보조 선분 모두 지우기") { env.features.removeAllGuides() }
                } label: {
                    Label("보조 선분 모두 지우기", systemImage: "trash")
                }
                .disabled(env.features.guides.isEmpty)
                .help("이 층의 보조 선분을 모두 지웁니다. 실행취소로 되살릴 수 있습니다.")
            } else if env.activeGeometryKind.isAreal, env.unitToolInUse == nil {
                Button {
                    env.closePointDraft()
                } label: {
                    Label("닫고 저장", systemImage: "checkmark.seal")
                }
                .disabled(env.pointDraft.points.count < 3)
                .help("시작점을 다시 누르는 것과 같습니다. (Return)")
            }
            Button {
                env.removeLastDraftPoint()
            } label: {
                Label("마지막 점 지우기", systemImage: "delete.left")
            }
            .disabled(env.pointDraft.isEmpty)
            .help("마지막에 찍은 점을 지웁니다. (Delete)")
            Button {
                env.escapePointDraft()
            } label: {
                Label("취소", systemImage: "xmark.circle")
            }
            .disabled(env.pointDraft.isEmpty)
            .help("작성 중인 도형을 버립니다. 실행취소로 되살릴 수 있습니다. (esc)")

            if env.layers.activePropertyType == .fixture {
                ToolbarDivider().frame(height: 16)
                FixtureTwinControls()
            }

            ToolbarDivider().frame(height: 16)

            Toggle(isOn: $env.isVertexMoveEnabled) {
                Text(env.isVertexMoveEnabled ? "꼭짓점 이동" : "꼭짓점 고정").font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("켜면 찍은 점과 저장한 도형의 꼭짓점을 끌어 옮길 수 있습니다. 끄면 고정되고 드래그는 화면 이동입니다.")
            UnitCoverageToggle()
        }
    }
}

/// fixture 점 단위의 쌍둥이 표시·함께 저장(2026-10-18 요청).
struct FixtureTwinControls: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let count = env.draftFixtureTwins.count
        Text(env.pointDraft.isEmpty ? "똑같이 생긴 개체: 점을 찍으면 표시" : "똑같이 생긴 개체 \(count)개")
            .font(.caption.monospacedDigit())
            .foregroundStyle(count > 0 ? env.canvasBackground.twinStroke : .secondary)
            .fixedSize()
        Toggle(isOn: $env.savesFixtureTwins) {
            Text("닫을 때 함께 저장").font(.caption)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .help("켜면 도형을 닫을 때 보라색으로 표시된 똑같이 생긴 자리마다 같은 태깅의 fixture를 개별 Polygon으로 함께 저장합니다.")
    }
}

/// unit 점 단위의 도구 고르기(2026-10-18 요청).
struct UnitToolPicker: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        Picker("", selection: $env.unitPointTool) {
            ForEach(UnitPointTool.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help(env.unitPointTool.help)
        ToolbarDivider().frame(height: 16)
    }
}

/// 점 단위 / 면 단위 전환. 면 단위는 polygon·multipolygon type(footprint 제외)에서만 보인다.
struct LayerEditModePicker: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        if env.layers.activePropertyType?.allowsFaceSelection ?? false {
            Picker("", selection: Binding(
                get: { env.layerEditMode },
                set: { env.setLayerEditMode($0) }
            )) {
                ForEach(LayerEditMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("점 단위: 꼭짓점·교점을 찍어 도형을 그립니다. 면 단위: 도면에서 이미 닫힌 면을 고릅니다.")
            ToolbarDivider().frame(height: 16)
        }
    }
}
