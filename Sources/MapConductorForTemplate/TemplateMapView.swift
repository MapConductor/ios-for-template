import Foundation
import MapConductorCore
import SwiftUI
import UIKit

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
            TemplateMapSurface(state: state, content: content, coordinator: coordinator)
        }
    }
}

/// 地図のビュー。実際のドライバーでは中身を SDK の `MapView` に置き換える。
///
/// **中身は `updateUIView` で毎回流すこと。**SwiftUI は body を評価するたびに
/// `updateUIView` を呼ぶので、同じ id の新しい state への差し替え・数が同じままの
/// 差し替え・マーカー以外だけの変更も、ここで漏れなくコレクタへ届く。
/// 「何かが変わったときだけ流す」形（`onChange(of: content.markers.count)` など）に
/// しないこと。数しか見ないと、上の 3 つを黙って取りこぼす。
///
/// 毎回流しても重くならないのは、差分を取る側が入口で帰すから。
/// コレクタは state のインスタンスで比べ、マーカーは ``MarkerListIdentity`` が
/// 同じ一覧の再送を弾く（カメラが動くたびに 14.4 万本を流しても 1ms 未満）。
/// ここで `@Published` の値を読んで「変わったか」を自前で判定しないこと
/// （全件ぶん読むと、それだけで body の評価ごとに重くなる）。
private struct TemplateMapSurface: UIViewRepresentable {
    let state: TemplateViewState
    let content: MapViewContent
    let coordinator: TemplateMapCoordinator

    func makeCoordinator() -> TemplateMapCoordinator { coordinator }

    func makeUIView(context: Context) -> UIView {
        // 雛形の地図は描画面を持たない。実際のドライバーは SDK のビューを返す。
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        context.coordinator.attach(state: state, content: content)
        return view
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.update(content: content)
    }

    static func dismantleUIView(_: UIView, coordinator: TemplateMapCoordinator) {
        coordinator.detach()
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
    /// body の評価ごと（`updateUIView`）に呼ばれる。
    func update(content: MapViewContent) {
        overlayScope.circleCollector.sync(content.circles.map(\.state))
        overlayScope.polylineCollector.sync(content.polylines.map(\.state))
        overlayScope.polygonCollector.sync(content.polygons.map(\.state))
        overlayScope.groundImageCollector.sync(content.groundImages.map(\.state))
        overlayScope.rasterLayerCollector.sync(content.rasterLayers.map(\.state))
        // 同じ一覧の再送は門番が入口で帰す（body の評価ごとに呼ばれても軽い）。
        controller?.markerController.syncMarkers(content.markers)
    }

    func detach() {
        controller?.destroy()
        state?.setController(nil)
        state?.setMapViewHolder(nil)
        controller = nil
        map = nil
    }
}
