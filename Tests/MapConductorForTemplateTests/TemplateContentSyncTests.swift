import MapConductorCore
import SwiftUI
import UIKit
import XCTest
@testable import MapConductorForTemplate

/// 地図へ届くのは「数」の変化だけではないこと。
///
/// SwiftUI の `TemplateMapView` は、body が評価されるたびに中身をコレクタへ流す
/// （実際のドライバーの `updateUIView` と同じ）。以前はマーカーの**数**が変わった
/// ときしか流しておらず、次の 3 つを取りこぼしていた:
///
///  - 同じ id の**新しい state** への差し替え
///  - 数が同じままの差し替え（別の id に入れ替え）
///  - マーカー以外（ポリゴン等）だけの変更
///
/// 雛形として写されると、この穴が新しいプロバイダへそのまま広がる。
@MainActor
final class TemplateContentSyncTests: XCTestCase {
    /// ホストのビューが読む中身。アプリの `@State` にあたる。
    private final class Model: ObservableObject {
        @Published var polygon: PolygonState
        @Published var marker: MarkerState

        init(polygon: PolygonState, marker: MarkerState) {
            self.polygon = polygon
            self.marker = marker
        }
    }

    private struct Host: View {
        let state: TemplateViewState
        @ObservedObject var model: Model

        var body: some View {
            TemplateMapView(state: state) {
                Polygon(state: model.polygon)
                Marker(state: model.marker)
            }
        }
    }

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func pt(_ lat: Double, _ lng: Double) -> GeoPoint { GeoPoint(latitude: lat, longitude: lng, altitude: 0) }

    private func box(_ s: Double, _ w: Double, _ n: Double, _ e: Double) -> [GeoPoint] {
        [pt(s, w), pt(s, e), pt(n, e), pt(n, w)]
    }

    /// 画面に載せて、`TemplateMap` を返す。
    private func show(_ model: Model) async throws -> TemplateMap {
        let state = TemplateViewState()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = UIHostingController(rootView: Host(state: state, model: model))
        window.makeKeyAndVisible()
        self.window = window
        try await settle()
        return try XCTUnwrap(state.mapViewHolder?.map, "the map never attached")
    }

    /// SwiftUI の更新とマーカーの非同期の追加を待つ。
    private func settle() async throws {
        for _ in 0..<10 {
            window?.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    private func points(_ map: TemplateMap, _ id: String) -> [GeoPoint] {
        map.shapes[id]?.points ?? []
    }

    func testANewStateWithTheSameIdReachesTheMap() async throws {
        let model = Model(
            polygon: PolygonState(points: box(35.0, 139.0, 35.1, 139.1), id: "PG"),
            marker: MarkerState(position: pt(35.0, 139.0), id: "MK")
        )
        let map = try await show(model)
        XCTAssertEqual(points(map, "PG"), box(35.0, 139.0, 35.1, 139.1))
        XCTAssertEqual(points(map, "MK"), [pt(35.0, 139.0)])

        model.polygon = PolygonState(points: box(36.0, 140.0, 36.1, 140.1), id: "PG")
        model.marker = MarkerState(position: pt(36.0, 140.0), id: "MK")
        try await settle()

        XCTAssertEqual(points(map, "PG"), box(36.0, 140.0, 36.1, 140.1), "polygon")
        XCTAssertEqual(points(map, "MK"), [pt(36.0, 140.0)], "marker")
    }

    func testSwappingInADifferentIdAtTheSameCountReachesTheMap() async throws {
        let model = Model(
            polygon: PolygonState(points: box(35.0, 139.0, 35.1, 139.1), id: "PG-A"),
            marker: MarkerState(position: pt(35.0, 139.0), id: "MK-A")
        )
        let map = try await show(model)

        model.polygon = PolygonState(points: box(36.0, 140.0, 36.1, 140.1), id: "PG-B")
        model.marker = MarkerState(position: pt(36.0, 140.0), id: "MK-B")
        try await settle()

        XCTAssertNil(map.shapes["PG-A"], "old polygon still on the map")
        XCTAssertNil(map.shapes["MK-A"], "old marker still on the map")
        XCTAssertEqual(points(map, "PG-B"), box(36.0, 140.0, 36.1, 140.1))
        XCTAssertEqual(points(map, "MK-B"), [pt(36.0, 140.0)])
    }

    func testAChangeToOnlyTheNonMarkerOverlaysReachesTheMap() async throws {
        let marker = MarkerState(position: pt(35.0, 139.0), id: "MK")
        let model = Model(polygon: PolygonState(points: box(35.0, 139.0, 35.1, 139.1), id: "PG-A"), marker: marker)
        let map = try await show(model)

        model.polygon = PolygonState(points: box(36.0, 140.0, 36.1, 140.1), id: "PG-B")
        try await settle()

        XCTAssertNil(map.shapes["PG-A"])
        XCTAssertEqual(points(map, "PG-B"), box(36.0, 140.0, 36.1, 140.1))
    }

    /// in-place の変更は各 state の購読が届ける（中身を流し直さなくても）。
    func testMovingAMarkerInPlaceReachesTheMap() async throws {
        let marker = MarkerState(position: pt(35.0, 139.0), id: "MK")
        let model = Model(polygon: PolygonState(points: box(35.0, 139.0, 35.1, 139.1), id: "PG"), marker: marker)
        let map = try await show(model)

        marker.position = pt(36.0, 140.0)
        try await settle()

        XCTAssertEqual(points(map, "MK"), [pt(36.0, 140.0)])
    }

    /// 同じ一覧の再送では、マーカーの差分を取り直さない（門番 ``MarkerListIdentity``）。
    /// 14.4 万本でピンチが凍った件の再発防止。
    func testResendingTheSameMarkersSkipsTheDiff() async throws {
        let controller = TemplateMapViewController(map: TemplateMap())
        let markers = (0..<3).map { Marker(state: MarkerState(position: pt(35.0 + Double($0), 139.0), id: "M\($0)")) }

        XCTAssertTrue(controller.markerController.syncMarkers(markers))
        XCTAssertFalse(controller.markerController.syncMarkers(markers), "same list resent")
        XCTAssertFalse(
            controller.markerController.syncMarkers(markers.map { Marker(state: $0.state) }),
            "same states in rebuilt Marker values"
        )
        XCTAssertTrue(
            controller.markerController.syncMarkers([markers[0], markers[1], Marker(state: MarkerState(position: pt(0, 0), id: "M2"))]),
            "a new state under the same id"
        )
    }
}
