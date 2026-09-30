import SwiftUI

/// 명세 8항의 개체 선택 상단바. 선택이 있을 때만 캔버스 위에 뜨는 플로팅 캡슐.
struct SelectionToolbar: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var moves: MoveSession
    // '원위치' 버튼이 이동 직후에 나타나야 하므로 이동량을 직접 구독한다(제안 4).

    var body: some View {
        HStack(spacing: 0) {
            Text("\(env.selection.selected.count)개 선택")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)

            divider

            Menu {
                let type = env.layers.activePropertyType
                let list = type.map { env.features.features(ofType: $0) } ?? []
                if list.isEmpty {
                    Text("추가할 feature가 없습니다")
                } else {
                    ForEach(list) { f in
                        Button("\(f.serialNumber) · 개체 \(f.memberIDs.count)개") {
                            env.addToExistingFeature(f.id)
                        }
                    }
                }
            } label: {
                Label("기존 feature에 추가", systemImage: "rectangle.stack.badge.plus")
                    .toolbarMenuLabel(isEnabled: env.layers.activePropertyType != nil)
                // Menu는 ButtonStyle을 받지 않아 라벨 쪽에서 직접 색을 맞춘다.
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 10)
            .disabled(env.layers.activePropertyType == nil)

            divider

            Button {
                env.createFeature()
            } label: {
                Label("Feature로 저장", systemImage: "square.3.layers.3d.down.right")
            }
            .buttonStyle(.toolbar)
            .padding(.horizontal, 10)
            .disabled(env.selection.selected.count < 1 || env.layers.activePropertyType == nil)
            .help("2개 이상 선택하면 그룹화되어 하나의 feature가 됩니다")

            if env.layers.activePropertyType?.hasDisplayPoint == true {
                divider
                Button {
                    if let fid = env.expandedFeature { env.beginDisplayPointPicking(fid) }
                    else { env.notify("우측에서 feature를 펼친 뒤 display point를 찍으세요.", isError: true) }
                } label: {
                    Label("display point", systemImage: "smallcircle.filled.circle")
                }
                .buttonStyle(.toolbar)
                .padding(.horizontal, 10)
            }

            if env.selectionHasCurve || env.selectionAllSegmented {
                divider
                Button {
                    if env.selectionAllSegmented { env.desegmentize(env.selection.selected) }
                    else { env.segmentizeSelection() }
                } label: {
                    Label(env.selectionAllSegmented ? "선분화 해제" : "선분화",
                          systemImage: "scribble.variable")
                }
                .buttonStyle(.toolbar)
                .padding(.horizontal, 10)
            }

            divider

            Button {
                env.showOverlapHighlight.toggle()
            } label: {
                Label(overlapLabel,
                      systemImage: env.showOverlapHighlight
                        ? "square.on.square.dashed" : "square.on.square")
            }
            .buttonStyle(.toolbar)
            .padding(.horizontal, 10)
            .help("선택한 개체가 다른 벡터와 겹치는 곳을 분홍색 윤곽으로 표시합니다")

            divider

            // '개체 이동' 토글(명세 2-3, 2026-08-29 사노 요청). 겹침 표시 토글과 같은 생김새로 둔다 —
            // 둘 다 '겹친 곳을 확인한다'는 한 가지 목적의 짝이라 나란히 있는 편이 읽힌다.
            Button {
                env.isMoveEnabled.toggle()
            } label: {
                Label("개체 이동",
                      systemImage: env.isMoveEnabled
                        ? "hand.draw.fill" : "hand.draw")
            }
            .buttonStyle(.toolbar)
            .padding(.horizontal, 10)
            .help("켜면 선택한 개체를 끌어서 옮길 수 있습니다. 꺼져 있으면 드래그가 화면 이동입니다.")

            // '모든 개체 원위치'. `도구` 메뉴에도 같은 명령이 있고, 여기가 둘째 입구다 —
            // 이동을 켤 때 뜨는 안내가 "상단 바의 «모든 개체 원위치»"를 가리키므로,
            // 그 문구를 읽은 사람이 상단바에서 실제로 찾을 수 있어야 한다.
            // 그래서 표시 조건에 `isMoveEnabled`를 더한다: 되돌릴 것이 아직 없어도(이동을 막
            // 켰을 때가 그렇다) 보이기는 해야 문구와 화면이 어긋나지 않는다. 대신 되돌릴 것이
            // 없으면 `도구` 메뉴 항목과 똑같이 흐리게 둔다.
            if env.isMoveEnabled || env.hasAnyOffset {
                divider
                Button {
                    env.resetPositions()
                } label: {
                    Label("모든 개체 원위치", systemImage: "arrow.uturn.backward.square")
                }
                .buttonStyle(.toolbar)
                .padding(.horizontal, 10)
                .disabled(!env.hasAnyOffset)
                .help("선택과 상관없이, 옮겨 둔 모든 개체를 도면 원래 위치로 되돌립니다")
            }

            // '원위치'(명세 2-3, 2026-08-25 사노 요청으로 이동 재도입). 지금 선택분만 되돌린다 —
            // '모든 개체 원위치'(`도구` 메뉴)와 역할을 나눠, 다른 곳에서 옮겨 둔 것까지 실수로
            // 되돌리지 않게 한다.
            if env.selectionHasOffset {
                divider
                Button {
                    env.resetPositions(env.selection.selected)
                } label: {
                    Label("원위치", systemImage: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.toolbar)
                .padding(.horizontal, 10)
                .help("선택한 개체를 도면 원래 위치로 되돌립니다")
            }

            // 명세 8-2) 그룹화의 짝. 지금 펼쳐 놓은 feature를 대상으로 한다 —
            // 이미 저장된 개체는 선택할 수 없으므로 '선택으로 대상을 지정'하는 경로가 성립하지 않는다.
            if let fid = env.expandedFeature, let f = env.features.feature(fid) {
                divider
                Button {
                    env.ungroup(fid)
                } label: {
                    Label("\(f.serialNumber) 그룹 해제", systemImage: "rectangle.on.rectangle.slash")
                }
                .buttonStyle(.toolbar)
                .padding(.horizontal, 10)
                .help("이 feature를 해제해 개체를 다시 고를 수 있게 합니다")

                // 명세 10-2-3: 빌려온 opening은 그룹 해제 대상이 아니라 **반납** 대상이다.
                if !env.borrow.objects(borrowedBy: fid).isEmpty {
                    divider
                    Button {
                        env.returnBorrowedOpenings(from: fid)
                    } label: {
                        Label("opening \(env.borrow.objects(borrowedBy: fid).count)개 반납",
                              systemImage: "arrow.uturn.left")
                    }
                    .buttonStyle(.toolbar)
                    .padding(.horizontal, 10)
                    .help("그룹은 그대로 두고 빌려온 문만 돌려줍니다. 이 폴리곤은 다시 열립니다.")
                }
            }

            divider

            // ✅ 2026-08-30 신설 — 드래그 사각형의 방향 토글(요청 1-2).
            // 라벨이 상태를 그대로 말한다. 흐린 아이콘 하나로는 지금 드래그가 무엇을 하는지
            // 알 수 없고, 그 상태에서 드래그하면 선택이 늘 것을 기대했다가 줄어든다.
            Button {
                env.marqueeSubtracts.toggle()
            } label: {
                Label(env.marqueeSubtracts ? "드래그: 해제" : "드래그: 선택",
                      systemImage: env.marqueeSubtracts
                        ? "minus.rectangle" : "plus.rectangle")
            }
            .buttonStyle(.toolbar)
            .padding(.horizontal, 10)
            .help("켜면 드래그한 사각형에 걸린 개체가 선택에서 빠집니다. 꺼져 있으면 선택에 더해집니다. 클릭은 모드와 상관없이 뒤집기입니다.")

            divider

            // 명세 디버깅 7번: 선택이 하나 이상일 때만, 상단바 가장 오른쪽에 둔다.
            Button {
                env.requestClearSelection(.main)
            } label: {
                Label("전체 선택 해제", systemImage: "xmark.circle")
            }
            .buttonStyle(.toolbar)
            .padding(.horizontal, 10)
            .disabled(env.selection.isEmpty)
        }
        .frame(height: 38)
        .toolbarCard()
    }

    /// 켜져 있을 때는 몇 곳이 겹쳤는지까지 보여준다 — 0곳이면 "겹침 없음"이 곧 결론이다.
    private var overlapLabel: String {
        guard env.showOverlapHighlight else { return "겹침 표시" }
        let n = env.overlapHighlight.count
        return n == 0 ? "겹침 없음" : "겹침 \(n)곳"
    }

    private var divider: some View { ToolbarDivider() }
}
