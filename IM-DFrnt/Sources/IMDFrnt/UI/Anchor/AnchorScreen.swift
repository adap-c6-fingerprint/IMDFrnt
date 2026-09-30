import CoreLocation
import MapKit
import SwiftUI

/// 명세 9항의 Anchor 지정 전용 화면. 시트가 아니라 전체 화면 전환이다.
/// 왼쪽 도면 · 오른쪽 지도 좌우 분할이며, 이 화면에 있는 동안
/// 개체 선택·이동·그룹화는 잠긴다.
struct AnchorScreen: View {
    @EnvironmentObject var env: AppEnvironment

    @State private var showOverlay = true
    @State private var mapPickMode = true
    @State private var camera: MapCameraPosition = .automatic
    @State private var lonText = ""
    @State private var latText = ""
    @State private var labelText = ""
    @State private var draggingAnchor: AnchorID?
    @StateObject private var placeSearch = PlaceSearchModel()
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var grabOffset: CLLocationCoordinate2D?
    @State private var didPinCamera = false
    @State private var showCriteria = false
    // 명세 9-6 선정 기준 팝오버의 열림 상태. 기본은 닫힘이다 — 아래 `criteriaButton` 주석 참고.
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                AnchorDrawingPane(draggingAnchor: $draggingAnchor)
                    .frame(minWidth: 380)
                mapPane
                    .frame(minWidth: 380)
            }
            Divider()
            bottomPanel
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: 상단 툴바

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button {
                env.exitAnchorScreen()
            } label: {
                Label("돌아가기", systemImage: "chevron.left")
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Anchor 지정").font(.headline).fixedSize()
                Text("도면 좌표를 실제 위경도에 맞추는 변환식을 만듭니다")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .layoutPriority(-1)
            // 창을 좁히면 이 설명이 먼저 줄어야 한다 — 오른쪽 버튼·상태가 잘리면 안 된다.

            Spacer(minLength: 8)

            statusChip

            Toggle(isOn: $showOverlay) {
                Label("도면 겹쳐보기", systemImage: "square.on.square")
            }
            .toggleStyle(.button)
            .disabled(env.anchors.pairs.count < 2)
            .help("Anchor 2쌍부터 도면을 지도 위에 반투명하게 겹쳐 정합을 확인할 수 있습니다")
        }
        .padding(12)
    }

    private var statusChip: some View {
        let n = env.anchors.pairs.count
        let need = AnchorStore.minimumPairs
        return HStack(spacing: 8) {
            Image(systemName: n >= need ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(n >= need ? .green : .orange)
            Text("\(n) / \(need)쌍").font(.callout.monospacedDigit())
            Divider().frame(height: 14)
            if n < need {
                Text("최소 \(need)쌍 필요").font(.caption).foregroundStyle(.secondary)
            } else if env.anchors.isOverDetermined {
                Text(String(format: "RMS %.2f m", env.rms)).font(.caption.monospacedDigit())
            } else {
                Text("판정 불가 (Anchor \(AnchorStore.recommendedPairs)쌍 이상 필요)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.quaternary.opacity(0.4), in: Capsule())
    }

    // MARK: 지도

    private var mapPane: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $mapPickMode) {
                    Text("Anchor 찍기").tag(true)
                    Text("지도 이동").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                // 폭을 210으로 못 박으면 지도 칸이 좁아질 때 옆 요소를 밀어낸다.
                // `fixedSize`는 글자 길이에 맞는 폭을 쓰되 늘어나지도 않는다 — 원래 의도한 바다.

                Spacer()

                if env.pendingAnchorLocal != nil {
                    Label("지도에서 같은 지점을 클릭하세요", systemImage: "arrow.right.circle.fill")
                        .font(.caption).foregroundStyle(.blue)
                } else {
                    Text("먼저 왼쪽 도면에서 한 점을 클릭하세요")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.top, 8)

            searchBar
                .padding(.horizontal, 8).padding(.vertical, 6)

            MapReader { proxy in
                Map(position: $camera) {
                    ForEach(Array(env.anchors.pairs.enumerated()), id: \.element.id) { i, pair in
                        Annotation(pair.label, coordinate: pair.geo.clCoordinate, anchor: .center) {
                            AnchorMapMarker(index: i + 1,
                                            isOutlier: env.outlierIndices.contains(i))
                        }
                    }

                    if showOverlay, let t = env.overlayTransform, let doc = env.document {
                        ForEach(overlayLines(doc: doc, transform: t), id: \.0) { item in
                            MapPolyline(coordinates: item.1)
                                .stroke(Color.orange.opacity(env.overlayIsPreviewOnly ? 0.5 : 0.8),
                                        lineWidth: 1.5)
                        }
                    }
                }
                .mapStyle(.imagery(elevation: .flat))
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                }
                .onAppear { pinCameraIfNeeded() }
                .onChange(of: env.anchors.pairs.count) { _ in pinCameraIfNeeded() }
                // 지금 보고 있는 범위를 검색 편향값으로 쓴다(`PlaceSearchModel.search(around:)`).
                // 같은 이름의 장소가 여럿일 때 화면 근처를 먼저 돌려준다.
                .overlay {
                    if mapPickMode {
                        Color.white.opacity(0.001)
                            .contentShape(Rectangle())
                            .gesture(mapGesture(proxy: proxy))
                    }
                }
                .overlay(alignment: .top) {
                    if placeSearch.isShowingResults { searchResultList }
                }
                // 결과 목록은 Anchor 찍기용 투명 겹침보다 **뒤에** 얹는다.
                // 앞에 두면 목록이 그 겹침에 가려져 클릭이 지도 클릭으로 새 나간다.
            }
        }
    }

    // MARK: 장소 검색 (2026-08-26 요청)

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)

            TextField("장소 검색 (예: 포항공과대학교 제2공학관)", text: $placeSearch.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { placeSearch.search(around: visibleRegion) }
                .onChange(of: placeSearch.query) { _ in
                    if PlaceSearchModel.normalized(placeSearch.query) == nil { placeSearch.clear() }
                }
                // 검색어를 지우면 남아 있던 결과 목록도 함께 닫는다.
                // 목록만 남으면 지금 검색어와 목록이 어긋나 무엇을 보고 있는지 알 수 없다.

            if placeSearch.isSearching {
                ProgressView().controlSize(.small)
            } else if !placeSearch.query.isEmpty {
                Button {
                    placeSearch.query = ""
                    placeSearch.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("검색어 지우기")
            }

            Button("검색") { placeSearch.search(around: visibleRegion) }
                .controlSize(.small)
                .disabled(PlaceSearchModel.normalized(placeSearch.query) == nil)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
        .help("이름으로 지도를 옮깁니다. Anchor 쌍은 지금처럼 지도를 직접 클릭해서 만듭니다.")
    }

    private var searchResultList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = placeSearch.message {
                Text(message)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(placeSearch.results) { result in
                Button {
                    camera = .region(PlaceSearchModel.focusRegion(for: result))
                    didPinCamera = true
                    placeSearch.dismissResults()
                    searchFocused = false
                    // 검색은 지도를 옮기기만 한다. Anchor 쌍은 사용자의 클릭으로만 만들어진다 —
                    // MapKit이 주는 점은 건물 대표점이라 도면의 특정 모서리와 대응하지 않는다.
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.name).font(.callout)
                        Text(result.subtitle)
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                if result.id != placeSearch.results.last?.id { Divider() }
            }
        }
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .shadow(radius: 6, y: 2)
        .padding(8)
    }

    private func mapGesture(proxy: MapProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let coord = proxy.convert(value.location, from: .local) else { return }
                if draggingAnchor == nil {
                    // 마커 근처에서 시작했으면 그 마커를 끌고, 아니면 새 쌍을 만든다.
                    if let start = proxy.convert(value.startLocation, from: .local),
                       let near = nearestAnchor(to: start, proxy: proxy, within: 22),
                       let pair = env.anchors.pairs.first(where: { $0.id == near }) {
                        draggingAnchor = near
                        grabOffset = AnchorMapMath.grabOffset(cursor: start,
                                                              marker: pair.geo.clCoordinate)
                        pinCamera()
                    }
                    // 집은 지점과 마커 중심의 차이를 기억한다(`AnchorMapMath.grabOffset`).
                    // 커서 좌표를 그대로 대입하면 집는 순간 마커가 커서 자리로 순간이동하는데,
                    // 넓게 축소한 지도에서는 그 거리가 몇 km라 "조금 움직였는데 크게 튀는" 것으로 보인다.
                    // 카메라도 이때 못 박는다 — `.automatic`이면 마커가 움직일 때마다 지도가
                    // 스스로 화면을 다시 잡아, 커서 아래 좌표가 매 프레임 달라진다.
                }
                if let id = draggingAnchor, let grab = grabOffset {
                    let moved = AnchorMapMath.draggedCoordinate(cursor: coord, grab: grab)
                    env.updateAnchorGeo(id, to: GeoPoint(longitude: moved.longitude,
                                                         latitude: moved.latitude))
                }
            }
            .onEnded { value in
                defer { draggingAnchor = nil; grabOffset = nil }
                let moved = abs(value.translation.width) + abs(value.translation.height)
                guard draggingAnchor == nil, moved < 5 else { return }
                guard let coord = proxy.convert(value.location, from: .local) else { return }
                guard env.pendingAnchorLocal != nil else {
                    env.notify("먼저 왼쪽 도면에서 대응하는 점을 클릭하세요.", isError: true)
                    return
                }
                env.addAnchor(longitude: coord.longitude, latitude: coord.latitude, label: labelText)
                labelText = ""
                if env.anchors.pairs.count == 1 { focusCamera() }
            }
    }

    private func nearestAnchor(to coord: CLLocationCoordinate2D, proxy: MapProxy,
                               within points: CGFloat) -> AnchorID? {
        guard let origin = proxy.convert(coord, to: .local) else { return nil }
        var best: (AnchorID, CGFloat)?
        for p in env.anchors.pairs {
            guard let sp = proxy.convert(p.geo.clCoordinate, to: .local) else { continue }
            let d = hypot(sp.x - origin.x, sp.y - origin.y)
            if d <= points, d < (best?.1 ?? .greatestFiniteMagnitude) { best = (p.id, d) }
        }
        return best?.0
    }

    /// 도면 개체를 지도 좌표계 폴리라인으로 바꾼다. 과도한 렌더링을 막기 위해 개수를 제한한다.
    private func overlayLines(doc: DrawingDocument,
                              transform: GeoAffineTransform) -> [(Int, [CLLocationCoordinate2D])] {
        var out: [(Int, [CLLocationCoordinate2D])] = []
        for (i, o) in doc.objects.enumerated() {
            guard out.count < 200 else { break }
            for sp in o.geometry.subpaths {
                var coords = PathGeometry(subpaths: [sp]).lineSegments(tolerance: 1.5)
                    .map { transform.apply($0.start).clCoordinate }
                if let last = PathGeometry(subpaths: [sp]).lineSegments(tolerance: 1.5).last {
                    coords.append(transform.apply(last.end).clCoordinate)
                }
                if coords.count >= 2 { out.append((out.count * 1000 + i, coords)) }
            }
        }
        return out
    }

    /// 지도 화면을 지금 있는 Anchor에 맞춰 한 번 못 박는다.
    /// **`.automatic`으로 남겨 두지 않는 것이 목적이다** — 자동 화면 맞춤은 마커를 끄는 동안
    /// 지도를 계속 다시 잡아, 커서 아래 좌표가 매 프레임 달라지게 만든다.
    private func pinCameraIfNeeded() {
        guard !didPinCamera else { return }
        pinCamera()
    }

    private func pinCamera() {
        if let region = visibleRegion {
            camera = .region(region)
            didPinCamera = true
            return
        }
        guard let region = AnchorMapMath.regionFitting(env.anchors.pairs.map(\.geo.clCoordinate))
        else { return }
        // Anchor가 하나도 없으면 못 박을 기준이 없다. 그대로 두면 첫 쌍이 생길 때
        // `focusCamera()`가 잡아 준다.
        camera = .region(region)
        didPinCamera = true
    }

    private func focusCamera() {
        guard let first = env.anchors.pairs.first else { return }
        camera = .region(MKCoordinateRegion(center: first.geo.clCoordinate,
                                            latitudinalMeters: 400, longitudinalMeters: 400))
        didPinCamera = true
    }

    // MARK: 하단 — 직접 입력과 목록

    /// 명세 9-5-5의 배치 안내. Esri 공식 권고("spread the links over the entire raster
    /// dataset... at least one link near each corner... and a few throughout the interior.")를
    /// 옮긴 것이다. **Anchor 개수만 채우고 한쪽에 몰아 찍으면 그 근처만 잘 맞고 반대편이 크게 어긋난다** —
    /// 잔차는 찍은 점에서만 재므로 몰아 찍으면 오히려 잔차가 작게 나와 잘못된 안심을 준다.
    private var placementHint: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lightbulb")
                .foregroundStyle(.secondary)
            Text("Anchor를 한쪽에 몰아 찍지 말고 도면의 각 모서리 근처에 하나씩, 내부에도 몇 개를 두세요. 건물 외벽 모서리처럼 위성 이미지에서도 특정할 수 있는 지점이 좋습니다.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 명세 9-6의 선정 기준을 여는 버튼. **팝오버를 쓴 이유**는 `bottomPanel`이
    /// `.frame(height:)`로 높이가 못 박혀 있기 때문이다 — `DisclosureGroup`으로 펼치면
    /// 늘어난 만큼이 고정 높이 안에서 잘리거나 Anchor 쌍 표를 밀어낸다.
    /// 팝오버는 패널 위에 떠서 열리므로 도면·지도·표의 자리를 전혀 빼앗지 않는다.
    private var criteriaButton: some View {
        Button {
            showCriteria = true
        } label: {
            Label("선정 기준", systemImage: "checklist")
                .font(.caption)
        }
        .controlSize(.small)
        .fixedSize()
        // 안내 문장이 길어 창을 좁히면 이 버튼이 먼저 찌그러진다. 줄어들 몫은 왼쪽 문장이다.
        .help("어떤 지점을 Anchor로 찍어야 하는지 — 적합·부적합 예시를 봅니다")
        .popover(isPresented: $showCriteria, arrowEdge: .top) {
            criteriaPopover
        }
    }

    /// 명세 9-6 본문. 9-5-5의 `placementHint`가 **어디에 흩어 찍을지**를 말한다면
    /// 여기는 **무엇을 찍을지**를 말한다 — 성격이 다르므로 한 문단에 섞지 않고 갈라 두었다.
    /// 부적합 항목은 이유를 반드시 함께 보인다. 이유 없이 금지 목록만 주면
    /// 목록에 없는 지점(예: 화단 경계석)을 만났을 때 스스로 판단할 근거가 없다.
    private var criteriaPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anchor 선정 기준").font(.headline)

            Text(AnchorCriteria.principle)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            criteriaList(title: "적합", items: AnchorCriteria.suitable,
                         symbol: "checkmark.circle.fill", tint: .green)
            criteriaList(title: "부적합", items: AnchorCriteria.unsuitable,
                         symbol: "slash.circle.fill", tint: .red)
            // 색만으로 적합·부적합을 가르지 않는다. 아이콘 모양과 "적합"·"부적합" 라벨을
            // 함께 두어야 색을 구별하기 어려운 눈에도 같은 정보가 전달된다.

            Divider()

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "building.2")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("고층 건물").font(.caption.weight(.semibold))
                    Text(AnchorCriteria.tallBuildingNote)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(width: 330)
        // 팝오버는 스스로 늘어날 폭이 없어 글이 한 줄로 뻗는다. 폭을 정해 줘야
        // 위 `fixedSize(horizontal: false, vertical: true)`가 줄바꿈으로 작동한다.
    }

    private func criteriaList(title: String, items: [AnchorCriteria.Item],
                              symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            ForEach(items) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.text).font(.caption)
                        if !item.note.isEmpty {
                            Text(item.note)
                                .font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                placementHint
                Spacer(minLength: 4)
                criteriaButton
            }
            HStack(spacing: 8) {
                Text("위경도 직접 입력").font(.caption.weight(.semibold)).fixedSize()
                TextField("경도 (lon)", text: $lonText)
                    .frame(minWidth: 80, idealWidth: 120, maxWidth: 140)
                TextField("위도 (lat)", text: $latText)
                    .frame(minWidth: 80, idealWidth: 120, maxWidth: 140)
                TextField("라벨 (예: 건물 남서 모서리)", text: $labelText)
                    .frame(minWidth: 110, idealWidth: 200, maxWidth: 260)
                // 폭을 못 박으면 창을 좁힐 때 줄 전체가 넘쳐 버튼이 밖으로 밀린다(뷰 디버깅 16번).
                // 범위로 두면 넓을 때는 종전과 같고, 좁아지면 입력칸이 먼저 양보한다.
                Button("쌍 추가") {
                    guard let lo = Double(lonText), let la = Double(latText) else {
                        env.notify("경도·위도를 숫자로 입력하세요.", isError: true); return
                    }
                    env.addAnchor(longitude: lo, latitude: la, label: labelText)
                    lonText = ""; latText = ""; labelText = ""
                    if env.anchors.pairs.count == 1 { focusCamera() }
                }
                .disabled(env.pendingAnchorLocal == nil || lonText.isEmpty || latText.isEmpty)

                Spacer()
                // 남은 폭을 이 `Spacer`가 먹어야 줄이 왼쪽에 붙는다. 없애면 늘어날 뷰가 하나도
                // 없어 `HStack`이 줄 전체를 가운데로 몰아, 아래 안내 문구와 시작점이 어긋난다.
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)

            Text("MapKit 위성 이미지 해상도가 부족한 건물에서는 이 직접 입력 경로가 주 경로입니다. 측량 성과가 있으면 그 값을 그대로 넣으세요.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            HStack {
                Spacer()
                SidebarCollapseAllButton(owner: .anchor)
            }
            SidebarSection(id: .anchorPairs, title: "Anchor 쌍",
                           badge: "\(env.anchors.pairs.count)") { anchorTable }
            // 이 화면의 '세부 항목'은 쌍 표다. 접으면 지도와 도면이 그만큼 넓어진다 —
            // 쌍을 다 넣고 나면 표보다 지도를 봐야 하는 시간이 길다.
        }
        .padding(12)
        .frame(height: env.isSectionCollapsed(.anchorPairs) ? 150 : 260)
        // 접었는데 패널 높이가 그대로면 빈 칸만 남는다. 접기의 목적이 자리를 내주는 것이므로
        // 패널 자체가 줄어야 한다.
    }

    private var anchorTable: some View {
        // 폭 고정(170/110/190/90) 대신 `Grid`로 바꿨다(뷰 디버깅 16번).
        //
        // **머리글과 값이 어긋나던 진짜 이유는 둘이 서로 다른 컨테이너에 있었다는 것이다.**
        // 머리글은 `HStack`, 값은 `ScrollView` 안의 다른 `HStack`이라, 폭을 똑같이 못 박아도
        // 행에만 붙은 가로 여백(6pt)과 끝의 삭제 버튼 때문에 세로줄이 밀렸다.
        // 창을 좁히면 고정 폭 합계(560pt)가 넘쳐 밀림이 더 커졌다.
        //
        // `Grid`는 **모든 행이 같은 열 폭을 공유**하므로 이런 어긋남이 구조적으로 생기지 않는다.
        // 머리글도 같은 `Grid` 안에 넣었다 — 스크롤과 함께 움직이는 대신 절대 어긋나지 않는다.
        // Anchor는 보통 3~8쌍이라 스크롤될 일 자체가 드물다.
        ScrollView {
            let res = env.residuals
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                GridRow {
                    Text("라벨")
                    Text("도면 좌표")
                    Text("위경도")
                    Text("잔차")
                    Color.clear.frame(width: 16, height: 1)
                    // 삭제 버튼 자리. 머리글에도 같은 칸을 둬야 열 수가 맞는다.
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)

                ForEach(Array(env.anchors.pairs.enumerated()), id: \.element.id) { i, pair in
                    GridRow {
                        TextField("", text: Binding(
                            get: { pair.label },
                            set: { env.renameAnchor(pair.id, to: $0) }
                        ))
                        .textFieldStyle(.plain)
                        .frame(minWidth: 110, idealWidth: 170)

                        Text(String(format: "%.1f, %.1f", pair.local.x, pair.local.y))
                            .fixedSize()
                        Text(String(format: "%.6f, %.6f", pair.geo.longitude, pair.geo.latitude))
                            .fixedSize()
                        Group {
                            if !env.anchors.isOverDetermined {
                                Text("판정 불가").foregroundStyle(.tertiary)
                            } else if i < res.count {
                                Text(String(format: "%.2f m", res[i]))
                                    .foregroundStyle(env.outlierIndices.contains(i) ? .red : .primary)
                            }
                        }
                        .fixedSize()
                        // 숫자 칸은 줄바꿈되면 행 높이가 달라져 가로줄이 어긋난다.
                        // 좁아지면 줄이는 것은 라벨 칸 몫이다(위 `minWidth`).

                        Button { env.anchors.remove(pair.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).controlSize(.mini)
                    }
                    .font(.caption.monospacedDigit())
                    .background(env.outlierIndices.contains(i) ? Color.red.opacity(0.1) : .clear,
                                in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if env.anchors.pairs.isEmpty {
                Text("아직 Anchor가 없습니다. 왼쪽 도면에서 한 점을 클릭한 뒤 지도에서 같은 지점을 클릭하세요.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                // 창을 좁히면 이 안내가 한 줄에 안 들어간다. `fixedSize`가 없으면
                // 줄바꿈 대신 뒤가 잘려 문장이 끊긴 채로 보인다.
            }
        }
    }

}

/// 명세 9-6 "Anchor 선정 기준"의 문구를 한곳에 모은 것.
/// 뷰 안에 문자열을 흩어 두지 않고 상수로 뽑은 이유는 자체점검(`--selftest`)에서
/// **부적합 항목에 이유가 빠지지 않았는지**를 기계적으로 확인하기 위해서다.
enum AnchorCriteria {

    struct Item: Identifiable, Equatable {
        let text: String
        /// 그 지점을 권하거나 말리는 근거. 적합 항목에서는 비어 있을 수 있다.
        let note: String
        var id: String { text }
    }

    static let principle = "도면과 실제 지도(위성 이미지) 양쪽에서 똑같이 특정할 수 있는 지점이어야 합니다."

    static let suitable: [Item] = [
        Item(text: "건물 외벽 모서리", note: "가장 정확합니다. 우선 이것부터 찾으세요."),
        Item(text: "주 출입구 중심", note: ""),
        Item(text: "외부 돌출 구조물의 모서리", note: ""),
        Item(text: "도면에 그려진 외부 포장·보도의 교차점", note: ""),
    ]

    static let unsuitable: [Item] = [
        Item(text: "방 한가운데, 가구, 실내 벽 교차점",
             note: "위성 이미지에서 찍을 수 없습니다."),
        Item(text: "나무·차량 옆",
             note: "시점에 따라 위치가 바뀝니다."),
    ]

    static let tallBuildingNote = "위성 촬영 각도 때문에 옥상이 옆으로 밀려 보입니다. 옥상 모서리가 아니라 건물이 지면과 만나는 접합부를 찍으세요."
}

extension GeoPoint {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
