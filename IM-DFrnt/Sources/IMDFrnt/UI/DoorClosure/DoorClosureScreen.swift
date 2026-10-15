import SwiftUI

/// '문 임시로 닫기' 전용 창(신기능 3항).
/// Anchor 화면·보조 개체 창과 같은 이유로 시트가 아니라 전체 화면 전환이다 —
/// 도면 전체를 훑으며 문 자리마다 점을 찍는 작업이라 화면이 넓어야 한다.
struct DoorClosureScreen: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                ZStack(alignment: .top) {
                    DoorClosurePane()
                    VStack(spacing: 6) {
                        draftBar
                        stageHint
                        // 클릭이 단계에 따라 다르게 동작하므로, 지금 무엇을 고르는 중인지를
                        // 상단바 바로 아래에 항상 적는다. 안 적으면 "왜 문이 안 잡히지"가 된다.
                    }
                    .padding(.top, 12)
                    // 상단바를 항상 띄운다. 선택이 있을 때만 뜨는 메인 상단바와 다른 이유는,
                    // 이 창에서는 **무엇을 더 골라야 하는지**가 곧 안내이기 때문이다.
                    // 비어 있을 때 사라지면 사용자가 다음에 할 일을 알 곳이 없다.
                }
                ResizableSidebar(width: $env.doorSidebarWidth,
                                 range: 260...560,
                                 edge: .trailing) { sidebar }
            }
        }
    }

    // MARK: 제목 줄

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "door.left.hand.open")
            Text("문 임시로 닫기").font(.headline).fixedSize()
            Text("열린 상태로 그려진 문 자리를 두 점으로 닫아 Openings 개체를 만듭니다")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail).layoutPriority(-1)
            Spacer(minLength: 8)
            Text("임시 문 \(env.doorClosures.count)개")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
            Button("작업 화면으로 돌아가기") { env.exitDoorClosureScreen() }
                .keyboardShortcut(.escape, modifiers: [])
                .fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: 상단 바 (신기능 3-4)

    private var draftBar: some View {
        HStack(spacing: 0) {
            slot(icon: "smallcircle.filled.circle",
                 label: "점 \(env.doorDraftPoints.count)/2",
                 filled: env.doorDraftPoints.count == 2)
            // #37: 문짝·호 칸을 없앴다. 문 선의 양 끝 두 점만 찍는다.
            divider

            Button { env.saveTemporaryDoor() } label: {
                Label("임시 문 저장", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.toolbar)
            .padding(.horizontal, 10)
            .disabled(!env.canSaveTemporaryDoor)
            .help(env.temporaryDoorHint)

            if env.doorDraftPoints.count > 0 {
                divider
                Button { env.resetDoorDraft() } label: {
                    Label("찍은 점 비우기", systemImage: "xmark.circle")
                }
                .buttonStyle(.toolbar)
                .padding(.horizontal, 10)
            }
        }
        .frame(height: 38)
        .toolbarCard()
    }

    /// 지금 무엇을 찍어야 하는지 안내한다.
    private var stageHint: some View {
        Text(env.doorStageHint)
            .font(.caption)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .toolbarCapsuleCard()
    }

    /// 상태 칸. **무엇이 채워졌고 무엇이 남았는지를 칸으로 보여준다** —
    /// 버튼만 흐리게 두면 무엇이 모자란지 알 수 없어 아무거나 눌러 보게 된다.
    private func slot(icon: String, label: String, filled: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: filled ? "checkmark.circle.fill" : icon)
            Text(label).font(.caption)
        }
        .opacity(filled ? 1.0 : 0.55)
        .padding(.horizontal, 12)
    }

    private var divider: some View { ToolbarDivider() }

    // MARK: 우측 사이드바 (신기능 3-5·3-6)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("저장한 임시 문").font(.subheadline.weight(.semibold))
                        Text("아직 Openings 레이어에 반영되지 않았습니다")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    SidebarCollapseAllButton(owner: .door)
                }
            }
            .padding(12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    SidebarSection(id: .doorList, title: "임시 문",
                                   badge: "\(env.doorClosures.count)") {
                        ForEach(env.doorClosures.doors) { door in
                            doorRow(door)
                        }
                        if env.doorClosures.isEmpty {
                            Text("아직 없습니다.\n도면에서 문 선의 양 끝 두 점을 찍은 뒤 저장하세요.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(8)
                        }
                    }
                }
                .padding(8)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    env.applyTemporaryDoors()
                } label: {
                    Label("모두 Openings 레이어에 반영하기", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!env.canApplyTemporaryDoors)

                Text("반영하면 각 임시 문이 opening feature 하나가 됩니다. 좌표는 찍은 두 점입니다.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func doorRow(_ door: TemporaryDoor) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "door.left.hand.open")
                .foregroundStyle(env.canvasBackground.marker(.displayPoint))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(door.label).font(.caption)
                Text(String(format: "(%.1f, %.1f) → (%.1f, %.1f)",
                            door.start.x, door.start.y, door.end.x, door.end.y))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                env.requestDeletion(title: "\(door.label)을 삭제할까요?",
                                    message: "이 임시 문을 삭제합니다. 실행 취소로 복구할 수 있습니다.") {
                    $0.removeTemporaryDoor(door.id)
                }
            } label: { Image(systemName: "trash").foregroundStyle(.red) }
                .buttonStyle(.borderless)
                .help("이 임시 문을 지웁니다.")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
