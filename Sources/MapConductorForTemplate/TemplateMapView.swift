import Foundation
import MapConductorCore
import SwiftUI

// ============================================================================
// G. State サブクラス（実装点 3）
// ============================================================================

/// 実装点 G。**残るのは 3 つだけ。**
///
///  - `mapDesignType`（プロバイダ固有の型）
///  - プロバイダ型のホルダー
///  - `getMapViewHolder()` の絞り込み
///
/// カメラの保持・`moveCameraTo` の 2 種・`fitBounds`・`attachController`・
/// `uiSettings`・`id` はコアの ``MapViewState`` が持つ。
///
/// `getMapViewHolder()` の絞り込みは**消さないこと**。消すとアプリ側の
/// `state.getMapViewHolder()?.map` が静的型を失う（ソース非互換）。
/// 1 行に縮めるのは可、消すのは不可。
public final class TemplateViewState: MapViewState<TemplateMapDesignType> {
    @Published private var _mapDesignType: TemplateMapDesignType

    public private(set) var mapViewHolder: TemplateViewHolder?

    override public var mapDesignType: TemplateMapDesignType {
        get { _mapDesignType }
        set { _mapDesignType = newValue }
    }

    public init(
        id: String = UUID().uuidString,
        mapDesignType: TemplateMapDesignType = TemplateMapDesign.standard,
        cameraPosition: MapCameraPosition = .Default,
        uiSettings: MapUISettings = MapUISettings()
    ) {
        self._mapDesignType = mapDesignType
        super.init(id: id, initialCameraPosition: cameraPosition, uiSettings: uiSettings)
    }

    override public func getMapViewHolder() -> AnyMapViewHolder? {
        mapViewHolder.map { AnyMapViewHolder($0) }
    }

    func setMapViewHolder(_ holder: TemplateViewHolder?) { mapViewHolder = holder }

    func setController(_ controller: (any MapViewControllerProtocol)?) { attachController(controller) }

    func updateCameraPosition(_ cameraPosition: MapCameraPosition) { setCameraPositionInternal(cameraPosition) }
}

// ============================================================================
// SwiftUI の入口
// ============================================================================

/// アプリ開発者が書くのはこれ。実際のドライバーでは中身を
/// `UIViewRepresentable { SDK の MapView }` に置き換える。
///
/// ```swift
/// TemplateMapView(state: state) {
///     Marker(position: point)
///     Polygon(state: polygonState)
/// }
/// ```
public struct TemplateMapView: View {
    @ObservedObject private var state: TemplateViewState
    private let style: MapViewStyle?
    private let onStyleDiagnostics: (([String]) -> Void)?
    private let content: MapViewContent

    @StateObject private var coordinator = TemplateMapCoordinator()

    public init(
        state: TemplateViewState,
        /// 実装点。**全プロバイダが同じ名前で受けること。** 何が起きるかは
        /// このバックエンドが宣言した能力で決まる: ``VectorStyleSupportKey``
        /// も ``VectorStyleMutationSupportKey`` も宣言していなければ、
        /// スタイルはラスタータイルとして届く。
        style: MapViewStyle? = nil,
        onStyleDiagnostics: (([String]) -> Void)? = nil,
        @MapViewContentBuilder content: () -> MapViewContent
    ) {
        self.state = state
        self.style = style
        self.onStyleDiagnostics = onStyleDiagnostics
        self.content = content()
    }

    public var body: some View {
        // 実際のドライバーはここが `UIViewRepresentable`。
        ZStack {
            // スタイルを追随させるためだけの空ビュー。実際のドライバーは
            // `UIViewRepresentable` の `updateUIView` で
            // `coordinator.applyStyle(...)` を呼べばよく、これは要らない。
            MapViewStyleApplier(
                host: coordinator.styleHost(for: state),
                style: style,
                onDiagnostics: onStyleDiagnostics
            )
            .frame(width: 0, height: 0)
            Color.clear
                .onAppear { coordinator.attach(state: state, content: content) }
                .onDisappear { coordinator.detach() }
                // 実際のドライバーでは UIViewRepresentable の updateUIView がここにあたる。
                .onChange(of: content.markers.count) { _ in coordinator.update(content: content) }
        }
    }
}

/// 地図の寿命を持つ。UIViewRepresentable の `Coordinator` にあたる。
@MainActor
final class TemplateMapCoordinator: ObservableObject {
    /// 地図がスタイルへ差し出すもの。実装点 — `MapViewCoordinatorBase` を
    /// 継承するドライバーは `styleHost` を継承で得るので、これは要らない。
    ///
    /// `attach` を待たずに作る: SwiftUI は空ビューの `updateUIView` を
    /// `onAppear` より先に回すことがあり、そこで掴んだレジストリが空だと
    /// スタイルは何も見つけられない。
    private var hosts: [ObjectIdentifier: MapViewStyleHost] = [:]

    func styleHost(for state: TemplateViewState) -> MapViewStyleHost {
        let key = ObjectIdentifier(state)
        if let existing = hosts[key] { return existing }
        let host = MapViewStyleHost(serviceRegistry: state.serviceRegistry)
        hosts[key] = host
        return host
    }

    private var map: TemplateMap?
    private var controller: TemplateMapViewController?
    private let overlayScope = MapOverlayScope()
    private weak var state: TemplateViewState?

    func attach(state: TemplateViewState, content: MapViewContent) {
        let map = TemplateMap()
        let controller = TemplateMapViewController(map: map)
        self.map = map
        self.controller = controller
        self.state = state

        state.setMapViewHolder(TemplateViewHolder(map: map))
        state.setController(controller)

        // 状態を集めるのはコレクタ。コントローラは購読も差分も持たない。
        bindOverlayCollector(overlayScope.circleCollector, to: controller.circleController)
        bindOverlayCollector(overlayScope.polylineCollector, to: controller.polylineController)
        bindOverlayCollector(overlayScope.polygonCollector, to: controller.polygonController)
        bindOverlayCollector(overlayScope.groundImageCollector, to: controller.groundImageController)
        bindOverlayCollector(overlayScope.rasterLayerCollector, to: controller.rasterLayerController)

        controller.declareCapabilities(into: state.serviceRegistry)

        // SDK のカメラ変更 → state へ push。アプリは state を読む（pull させない）。
        controller.setCameraMoveEndListener { [weak state] position in
            state?.updateCameraPosition(position)
        }

        update(content: content)
        controller.notifyMapInitialized()
    }

    /// アプリが宣言したオーバーレイをコレクタへ流す。**差分はコレクタが取る。**
    /// ここで自前の差分ループを書かないこと（移行前はそれが 1 プロバイダに 6 本あった）。
    func update(content: MapViewContent) {
        overlayScope.circleCollector.sync(content.circles.map(\.state))
        overlayScope.polylineCollector.sync(content.polylines.map(\.state))
        overlayScope.polygonCollector.sync(content.polygons.map(\.state))
        overlayScope.groundImageCollector.sync(content.groundImages.map(\.state))
        overlayScope.rasterLayerCollector.sync(content.rasterLayers.map(\.state))
        guard let controller else { return }
        Task { await controller.markerController.add(data: content.markers.map(\.state)) }
    }

    func detach() {
        controller?.destroy()
        state?.setController(nil)
        state?.setMapViewHolder(nil)
        controller = nil
        map = nil
    }
}
