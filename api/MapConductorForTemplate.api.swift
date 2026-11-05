import CoreGraphics
import Foundation
import MapConductorCore
import Swift
import SwiftUI
import UIKit
import _Concurrency
import _StringProcessing
import _SwiftConcurrencyShims
@_hasMissingDesignatedInitializers final public class TemplateShape {
  final public let id: Swift::String
  final public let kind: MapConductorCore::OverlayKind
  final public var points: [MapConductorCore::GeoPoint]
  @objc deinit
}
final public class TemplateMap {
  final public var center: MapConductorCore::GeoPoint
  final public var zoom: Swift::Double
  final public var bearingDegrees: Swift::Double
  final public var tiltDegrees: Swift::Double
  final public var sizePx: CoreFoundation::CGSize
  final public var isScrollEnabled: Swift::Bool
  final public var shapes: [Swift::String : MapConductorForTemplate::TemplateShape] {
    get
  }
  final public var onCameraChanged: (() -> Swift::Void)?
  final public var onTap: ((CoreFoundation::CGPoint) -> Swift::Void)?
  final public var onLongPress: ((CoreFoundation::CGPoint) -> Swift::Void)?
  public init()
  @discardableResult
  final public func add(id: Swift::String, kind: MapConductorCore::OverlayKind, points: [MapConductorCore::GeoPoint]) -> MapConductorForTemplate::TemplateShape
  final public func remove(id: Swift::String)
  final public func removeAll()
  final public func screenPoint(for position: any MapConductorCore::GeoPointProtocol) -> CoreFoundation::CGPoint?
  final public func geoPoint(at point: CoreFoundation::CGPoint) -> MapConductorCore::GeoPoint?
  @objc deinit
}
@_hasMissingDesignatedInitializers final public class TemplateViewHolder : MapConductorCore::MapViewHolderProtocol {
  final public let mapView: MapConductorForTemplate::TemplateMap
  final public let map: MapConductorForTemplate::TemplateMap
  final public func toScreenOffset(position: any MapConductorCore::GeoPointProtocol) -> CoreFoundation::CGPoint?
  final public func fromScreenOffsetSync(offset: CoreFoundation::CGPoint) -> MapConductorCore::GeoPoint?
  final public func viewportSizePx() -> CoreFoundation::CGSize?
  public typealias ActualMap = MapConductorForTemplate::TemplateMap
  public typealias ActualMapView = MapConductorForTemplate::TemplateMap
  @objc deinit
}
public struct TemplateMapDesignType : Swift::Equatable, Swift::Sendable {
  public let id: Swift::String
  public init(id: Swift::String)
  public static func == (a: MapConductorForTemplate::TemplateMapDesignType, b: MapConductorForTemplate::TemplateMapDesignType) -> Swift::Bool
}
public enum TemplateMapDesign {
  public static let standard: MapConductorForTemplate::TemplateMapDesignType
  public static let satellite: MapConductorForTemplate::TemplateMapDesignType
}
final public class TemplateViewState : MapConductorCore::MapViewState<MapConductorForTemplate::TemplateMapDesignType> {
  final public var mapViewHolder: MapConductorForTemplate::TemplateViewHolder? {
    get
  }
  override final public var mapDesignType: MapConductorForTemplate::TemplateMapDesignType {
    get
    set
  }
  public init(id: Swift::String = UUID().uuidString, mapDesignType: MapConductorForTemplate::TemplateMapDesignType = TemplateMapDesign.standard, cameraPosition: MapConductorCore::MapCameraPosition = .Default, uiSettings: MapConductorCore::MapUISettings = MapUISettings())
  override final public func getMapViewHolder() -> MapConductorCore::AnyMapViewHolder?
  @objc deinit
}
@_Concurrency::MainActor @preconcurrency public struct TemplateMapView : SwiftUICore::View {
  @_Concurrency::MainActor @preconcurrency public init(state: MapConductorForTemplate::TemplateViewState, style: (any MapConductorCore::MapViewStyle)? = nil, onStyleDiagnostics: (([Swift::String]) -> Swift::Void)? = nil, @MapConductorCore::MapViewContentBuilder content: () -> MapConductorCore::MapViewContent)
  @_Concurrency::MainActor @preconcurrency public var body: some SwiftUICore::View {
    get
  }
  public typealias Body = @_opaqueReturnTypeOf("$s23MapConductorForTemplate0dA4ViewV4bodyQrvp", 0) __
}
@_Concurrency::MainActor final public class TemplateMapViewController : MapConductorCore::MapViewControllerProtocol {
  @_Concurrency::MainActor final public let holder: MapConductorCore::AnyMapViewHolder
  @_Concurrency::MainActor final public let coroutine: MapConductorCore::CoroutineScope
  @_Concurrency::MainActor final public let overlayControllers: MapConductorCore::OverlayControllerRegistry
  @_Concurrency::MainActor public init(map: MapConductorForTemplate::TemplateMap)
  @_Concurrency::MainActor final public func moveCamera(position: MapConductorCore::MapCameraPosition)
  @_Concurrency::MainActor final public func animateCamera(position: MapConductorCore::MapCameraPosition, duration _: MapConductorCore::Long)
  @_Concurrency::MainActor final public func fitBounds(bounds: MapConductorCore::GeoRectBounds, padding _: Swift::Int)
  @_Concurrency::MainActor final public func clearOverlays() async
  @_Concurrency::MainActor final public func destroy()
  @_Concurrency::MainActor final public func applyUISettings(_ settings: MapConductorCore::MapUISettings)
  @_Concurrency::MainActor final public func setCameraMoveStartListener(listener: MapConductorCore::OnCameraMoveHandler?)
  @_Concurrency::MainActor final public func setCameraMoveListener(listener: MapConductorCore::OnCameraMoveHandler?)
  @_Concurrency::MainActor final public func setCameraMoveEndListener(listener: MapConductorCore::OnCameraMoveHandler?)
  @_Concurrency::MainActor final public func setMapClickListener(listener: MapConductorCore::OnMapEventHandler?)
  @_Concurrency::MainActor final public func setMapLongClickListener(listener: MapConductorCore::OnMapEventHandler?)
  @_Concurrency::MainActor final public func setMapInitializedListener(listener: MapConductorCore::OnMapInitializedHandler?)
  @objc deinit
}
extension MapConductorForTemplate::TemplateMapView : Swift::Sendable {}
extension MapConductorForTemplate::TemplateMapViewController : Swift::Sendable {}
