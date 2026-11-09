import Combine
import CoreGraphics
import Foundation
@_spi(MapConductorDriver) import MapConductorCore

// ============================================================================
// D. レンダラ 6 種 × onAdd / onChange / onRemove / onPostProcess（実装点 25）
// ============================================================================
//
// **ここがドライバーの本体。**「MapConductor の状態」→「SDK のオブジェクト」の
// 翻訳だけを書く。差分計算・購読・順序・重複排除はすべてコアが済ませてある。
//
// 各レンダラは 3 つの関数だけ実装すればよい:
//   createXxx(state:)                 … 状態から SDK オブジェクトを作る
//   updateXxxProperties(_:current:prev:) … 変わったところだけ SDK へ反映する
//   removeXxx(entity:)                … SDK から外す
//
// **当たり判定は書かない。**コアの Manager が持っている（測地線ポリゴンの巻き数
// 判定、穴の除外、球面距離、線分への近接）。書くと二重になってずれる。

// MARK: - 円

@MainActor
final class TemplateCircleRenderer: AbstractCircleOverlayRenderer<TemplateShape> {
    private weak var map: TemplateMap?

    init(map: TemplateMap?) {
        self.map = map
        super.init()
    }

    override func createCircle(state: CircleState) async -> TemplateShape? {
        // 実際の SDK ではここで SDK の円を作る。
        // 円の輪郭が要る SDK は、コアの `circleToRing` を使うこと（測地線・
        // ±180 分割・リングの閉じ方まで面倒を見てくれる）。
        map?.add(id: state.id, kind: .circle, points: [GeoPoint.from(position: state.center)])
    }

    override func updateCircleProperties(
        circle: TemplateShape,
        current: CircleEntity<TemplateShape>,
        prev: CircleEntity<TemplateShape>
    ) async -> TemplateShape? {
        // `current.fingerPrint` と `prev.fingerPrint` を比べて、変わったところだけ触る。
        // 中心や半径が変わったなら作り直しでよい。
        if current.fingerPrint.center != prev.fingerPrint.center {
            circle.points = [GeoPoint.from(position: current.state.center)]
        }
        return circle
    }

    override func removeCircle(entity: CircleEntity<TemplateShape>) async {
        map?.remove(id: entity.state.id)
    }

    func unbind() { map = nil }
}

/// コントローラは**この 3 つ**だけ書く。差分も購読も持たない
/// （`bindOverlayCollector` が `add(data:)` / `update(state:)` を流してくる）。
@MainActor
final class TemplateCircleController: CircleController<TemplateShape, TemplateCircleRenderer> {
    init(map: TemplateMap?) {
        super.init(circleManager: CircleManager<TemplateShape>(), renderer: TemplateCircleRenderer(map: map))
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

// MARK: - ポリライン

@MainActor
final class TemplatePolylineRenderer: AbstractPolylineOverlayRenderer<TemplateShape> {
    private weak var map: TemplateMap?

    init(map: TemplateMap?) {
        self.map = map
        super.init()
    }

    override func createPolyline(state: PolylineState) async -> TemplateShape? {
        map?.add(id: state.id, kind: .polyline, points: state.points.map { GeoPoint.from(position: $0) })
    }

    override func updatePolylineProperties(
        polyline: TemplateShape,
        current: PolylineEntity<TemplateShape>,
        prev _: PolylineEntity<TemplateShape>
    ) async -> TemplateShape? {
        polyline.points = current.state.points.map { GeoPoint.from(position: $0) }
        return polyline
    }

    override func removePolyline(entity: PolylineEntity<TemplateShape>) async {
        map?.remove(id: entity.state.id)
    }

    func unbind() { map = nil }
}

@MainActor
final class TemplatePolylineController: PolylineController<TemplateShape, TemplatePolylineRenderer> {
    init(map: TemplateMap?) {
        super.init(polylineManager: PolylineManager<TemplateShape>(), renderer: TemplatePolylineRenderer(map: map))
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

// MARK: - ポリゴン

@MainActor
final class TemplatePolygonRenderer: AbstractPolygonOverlayRenderer<TemplateShape> {
    private weak var map: TemplateMap?

    init(map: TemplateMap?) {
        self.map = map
        super.init()
    }

    override func createPolygon(state: PolygonState) async -> TemplateShape? {
        // 穴（`state.holes`）を持てない SDK は、
        //  - 穴を無視する            → capability を `degraded` で宣言する
        //  - 外周を分割して穴を避ける → capability を `approximated` で宣言する
        // どちらでもよいが、**黙って無視しない**こと。
        map?.add(id: state.id, kind: .polygon, points: state.points.map { GeoPoint.from(position: $0) })
    }

    override func updatePolygonProperties(
        polygon: TemplateShape,
        current: PolygonEntity<TemplateShape>,
        prev _: PolygonEntity<TemplateShape>
    ) async -> TemplateShape? {
        polygon.points = current.state.points.map { GeoPoint.from(position: $0) }
        return polygon
    }

    override func removePolygon(entity: PolygonEntity<TemplateShape>) async {
        map?.remove(id: entity.state.id)
    }

    func unbind() { map = nil }
}

@MainActor
final class TemplatePolygonController: PolygonController<TemplateShape, TemplatePolygonRenderer> {
    init(map: TemplateMap?) {
        super.init(polygonManager: PolygonManager<TemplateShape>(), renderer: TemplatePolygonRenderer(map: map))
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

// MARK: - 地上画像

@MainActor
final class TemplateGroundImageRenderer: AbstractGroundImageOverlayRenderer<TemplateShape> {
    private weak var map: TemplateMap?

    init(map: TemplateMap?) {
        self.map = map
        super.init()
    }

    override func createGroundImage(state: GroundImageState) async -> TemplateShape? {
        map?.add(
            id: state.id,
            kind: .groundImage,
            points: [state.bounds.southWest, state.bounds.northEast].compactMap { $0 }
        )
    }

    override func updateGroundImageProperties(
        groundImage: TemplateShape,
        current _: GroundImageEntity<TemplateShape>,
        prev _: GroundImageEntity<TemplateShape>
    ) async -> TemplateShape? {
        groundImage
    }

    override func removeGroundImage(entity: GroundImageEntity<TemplateShape>) async {
        map?.remove(id: entity.state.id)
    }

    func unbind() { map = nil }
}

@MainActor
final class TemplateGroundImageController: GroundImageController<TemplateShape, TemplateGroundImageRenderer> {
    init(map: TemplateMap?) {
        super.init(
            groundImageManager: GroundImageManager<TemplateShape>(),
            renderer: TemplateGroundImageRenderer(map: map)
        )
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

// MARK: - ラスターレイヤ

@MainActor
final class TemplateRasterLayerRenderer: AbstractRasterLayerOverlayRenderer<TemplateShape> {
    private weak var map: TemplateMap?

    init(map: TemplateMap?) {
        self.map = map
        super.init()
    }

    override func createLayer(state: RasterLayerState) async -> TemplateShape? {
        // ここを実装すると heatmap / geojson-layer / タイル方式マーカーが
        // まとめて動くようになる（どれもラスタータイルの重ね合わせで実装されている）。
        map?.add(id: state.id, kind: .rasterLayer, points: [])
    }

    override func updateLayerProperties(
        layer: TemplateShape,
        current _: RasterLayerEntity<TemplateShape>,
        prev _: RasterLayerEntity<TemplateShape>
    ) async -> TemplateShape? {
        layer
    }

    override func removeLayer(entity: RasterLayerEntity<TemplateShape>) async {
        map?.remove(id: entity.state.id)
    }

    func unbind() { map = nil }
}

@MainActor
final class TemplateRasterLayerController: RasterLayerController<TemplateShape, TemplateRasterLayerRenderer> {
    init(map: TemplateMap?) {
        super.init(
            rasterLayerManager: RasterLayerManager<TemplateShape>(),
            renderer: TemplateRasterLayerRenderer(map: map)
        )
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

// MARK: - マーカー

@MainActor
final class TemplateMarkerRenderer: MarkerOverlayRendererProtocol {
    typealias ActualMarker = TemplateShape

    var animateStartListener: OnMarkerEventHandler?
    var animateEndListener: OnMarkerEventHandler?

    private weak var map: TemplateMap?

    init(map: TemplateMap?) { self.map = map }

    /// `bitmapIcon` は**コアが用意した最終的なアイコン**。既定アイコンの合成も
    /// ラベル描画も済んでいる。SDK のアノテーションに載せるだけでよい。
    func onAdd(data: [MarkerOverlayAddParams]) async -> [TemplateShape?] {
        data.map { params in
            map?.add(id: params.state.id, kind: .marker, points: [GeoPoint.from(position: params.state.position)])
        }
    }

    func onChange(data: [MarkerOverlayChangeParams<TemplateShape>]) async -> [TemplateShape?] {
        data.map { params in
            let marker = params.current.marker
            marker?.points = [GeoPoint.from(position: params.current.state.position)]
            return marker
        }
    }

    func onRemove(data: [MarkerEntity<TemplateShape>]) async {
        data.forEach { map?.remove(id: $0.state.id) }
    }

    /// アニメーションを持たない SDK は空のままでよい。
    /// ただし `animateStartListener` / `animateEndListener` を呼ばないなら、
    /// `markerAnimation` capability を `unsupported` で宣言すること。
    func onAnimate(entity _: MarkerEntity<TemplateShape>) async {}

    func onPostProcess() async {}

    func unbind() { map = nil }
}

/// マーカーの当たり判定・ドラッグ・アニメの保持はすべてコアの
/// ``AbstractMarkerController`` と ``DefaultMarkerEventController`` が持つ。
@MainActor
final class TemplateMarkerController: AbstractMarkerController<TemplateShape, TemplateMarkerRenderer> {
    private weak var map: TemplateMap?

    /// 同じ一覧の再送を入口で見抜く門番。**消さないこと。**
    private var syncIdentity = MarkerListIdentity()
    /// いま地図に載せている state と、その購読。
    private var statesById: [String: MarkerState] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]

    init(map: TemplateMap?) {
        self.map = map
        super.init(markerManager: MarkerManager<TemplateShape>(), renderer: TemplateMarkerRenderer(map: map))
    }

    /// アプリが宣言したマーカーの一覧を地図へ流す。body の評価ごとに呼ばれる。
    ///
    /// SwiftUI はカメラが動くたびに body を評価し直し、そのたびに**全マーカー**がここへ来る。
    /// 同じ一覧（同じ state のインスタンスが同じ順）なら ``MarkerListIdentity`` が入口で帰す。
    /// これを外すと 14.4 万本でピンチが凍る（詳細は型のコメント）。
    ///
    /// 比べるのは参照だけで、`@Published` は読まない。位置などの in-place の変更は
    /// 下の購読が届ける。同じ id の**新しい state** が来たら、古い state の購読を外して
    /// 新しい state を購読し直す。
    ///
    /// - Returns: 一覧を処理したら true（テスト用）。
    @discardableResult
    func syncMarkers(_ markers: [Marker]) -> Bool {
        guard syncIdentity.shouldProcess(markers) else { return false }

        var next: [String: MarkerState] = [:]
        for marker in markers { next[marker.id] = marker.state }
        for (id, previous) in statesById where next[id] !== previous {
            subscriptions.removeValue(forKey: id)?.cancel()
        }
        statesById = next
        for state in next.values where subscriptions[state.id] == nil {
            subscribe(state)
        }

        // 差分（追加・変更・削除）はコアの `add(data:)` が取る。
        let states = markers.map(\.state)
        Task { await self.add(data: states) }
        return true
    }

    private func subscribe(_ state: MarkerState) {
        subscriptions[state.id] = state.asFlow()
            .dropFirst() // 購読した瞬間の値は要らない
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak state] _ in
                guard let self, let state, self.statesById[state.id] === state else { return }
                Task { await self.update(state: state) }
            }
    }

    func unbind() {
        subscriptions.values.forEach { $0.cancel() }
        subscriptions.removeAll()
        statesById.removeAll()
        renderer.unbind()
        map = nil
        destroy()
    }
}
