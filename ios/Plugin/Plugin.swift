import Foundation
import Capacitor
import GoogleMaps
import SDWebImage

@objc(CapacitorGoogleMaps)
public class CapacitorGoogleMaps: CustomMapViewEvents {

    var GOOGLE_MAPS_KEY: String = "";

    var customMapViews = [String : CustomMapView]();

    var customMarkers = [String : CustomMarker]();

    @objc func initialize(_ call: CAPPluginCall) {

        self.GOOGLE_MAPS_KEY = call.getString("key", "")

        if self.GOOGLE_MAPS_KEY.isEmpty {
            call.reject("GOOGLE MAPS API key missing!")
            return
        }

        GMSServices.provideAPIKey(self.GOOGLE_MAPS_KEY)
        call.resolve([
            "initialized": true
        ])
    }

    @objc func createMap(_ call: CAPPluginCall) {

        DispatchQueue.main.async {
            let customMapView : CustomMapView = CustomMapView(customMapViewEvents: self);

            self.bridge?.saveCall(call)
            customMapView.savedCallbackIdForCreate = call.callbackId;
            
            let boundingRect = call.getObject("boundingRect", JSObject());
            customMapView.boundingRect.updateFromJSObject(boundingRect);
            
            let mapCameraPosition = call.getObject("cameraPosition", JSObject());
            customMapView.mapCameraPosition.updateFromJSObject(mapCameraPosition);

            let preferences = call.getObject("preferences", JSObject());
            customMapView.mapPreferences.updateFromJSObject(preferences);

            self.bridge?.viewController?.view.addSubview(customMapView.view);

            customMapView.GMapView.delegate = customMapView;

            self.customMapViews[customMapView.id] = customMapView;
        }
    }

    @objc func updateMap(_ call: CAPPluginCall) {
        let mapId: String = call.getString("mapId")!;

        DispatchQueue.main.async {
            let customMapView = self.customMapViews[mapId];

            if (customMapView != nil) {
                let preferences = call.getObject("preferences", JSObject());
                customMapView?.mapPreferences.updateFromJSObject(preferences);

                customMapView?.invalidateMap();
            } else {
                call.reject("map not found");
            }
        }

    }

    @objc func moveCamera(_ call: CAPPluginCall) {
        guard let mapId = call.getString("mapId") else {
            call.reject("map not found")
            return
        }

        DispatchQueue.main.async {
            guard let customMapView = self.customMapViews[mapId]  else {
                call.reject("map not found")
                return
            }

            let mapCameraPosition = MapCameraPosition()
            let cameraPosition = call.getObject("cameraPosition", JSObject())
            mapCameraPosition.updateFromJSObject(cameraPosition)

            let camera = GMSMutableCameraPosition.camera(withLatitude: mapCameraPosition.latitude,
                                                         longitude: mapCameraPosition.longitude,
                                                         zoom: customMapView.GMapView.camera.zoom)
            customMapView.GMapView.animate(to: camera)

            call.resolve(cameraPosition)
        }
    }

    @objc func addMarker(_ call: CAPPluginCall) {
        let mapId: String = call.getString("mapId", "")

        DispatchQueue.main.async {
            guard let customMapView = self.customMapViews[mapId] else {
                call.reject("map not found")
                return
            }
            let preferences = call.getObject("preferences", JSObject())
            let marker = CustomMarker()
            marker.updateFromJSObject(preferences: preferences)
            marker.map = customMapView.GMapView
            self.customMarkers[marker.id] = marker
            if let url = call.getObject("icon")?["url"] as? String {
                self.imageCache.image(at: url) { image in
                    marker.icon = image
                }
            }
            
            call.resolve(CustomMarker.getResultForMarker(marker))
        }
    }
    
    @objc func addMarkers(_ call: CAPPluginCall) {
        let mapId: String = call.getString("mapId", "")
        
        DispatchQueue.main.async {
            guard let customMapView = self.customMapViews[mapId] else {
                call.reject("map not found")
                return
            }
            
            let markers = List<JSValue>(elements: call.getArray("markers", []))
            self.addMarker(node: markers.first, mapView: customMapView)
            
            call.resolve()
        }
    }

    @objc func removeMarker(_ call: CAPPluginCall) {
        let markerId: String = call.getString("markerId", "");

        DispatchQueue.main.async {
            let customMarker = self.customMarkers[markerId];

            if (customMarker != nil) {
                customMarker?.map = nil;
                self.customMarkers[markerId] = nil;
                call.resolve();
            } else {
                call.reject("marker not found");
            }
        }
    }

    @objc func didTapInfoWindow(_ call: CAPPluginCall) {
        setCallbackIdForEvent(call: call, eventName: CustomMapView.EVENT_DID_TAP_INFO_WINDOW);
    }

    @objc func didCloseInfoWindow(_ call: CAPPluginCall) {
        setCallbackIdForEvent(call: call, eventName: CustomMapView.EVENT_DID_CLOSE_INFO_WINDOW);
    }

    @objc func didTapMap(_ call: CAPPluginCall) {
        setCallbackIdForEvent(call: call, eventName: CustomMapView.EVENT_DID_TAP_MAP);
    }

    @objc func didLongPressMap(_ call: CAPPluginCall) {
        setCallbackIdForEvent(call: call, eventName: CustomMapView.EVENT_DID_LONG_PRESS_MAP);
    }

    @objc func didTapMarker(_ call: CAPPluginCall) {
        setCallbackIdForEvent(call: call, eventName: CustomMapView.EVENT_DID_TAP_MARKER);
    }

    @objc func didTapMyLocationButton(_ call: CAPPluginCall) {
        setCallbackIdForEvent(call: call, eventName: CustomMapView.EVENT_DID_TAP_MY_LOCATION_BUTTON);
    }

    @objc func didTapMyLocationDot(_ call: CAPPluginCall) {
        setCallbackIdForEvent(call: call, eventName: CustomMapView.EVENT_DID_TAP_MY_LOCATION_DOT);
    }

    func setCallbackIdForEvent(call: CAPPluginCall, eventName: String) {
        call.keepAlive = true;
        let callbackId = call.callbackId;
        guard let mapId = call.getString("mapId") else { return };

        let customMapView: CustomMapView = customMapViews[mapId]!;

        let preventDefault: Bool = call.getBool("preventDefault", false);
        customMapView.setCallbackIdForEvent(callbackId: callbackId, eventName: eventName, preventDefault: preventDefault);
    }

    override func lastResultForCallbackId(callbackId: String, result: PluginCallResultData) {
        let call = bridge?.savedCall(withID: callbackId);
        call?.resolve(result);
        bridge?.releaseCall(call!);
    }

    override func resultForCallbackId(callbackId: String, result: PluginCallResultData?) {
        let call = bridge?.savedCall(withID: callbackId);
        if (result != nil) {
            call?.resolve(result!);
        } else {
            call?.resolve();
        }
    }

}

private extension CapacitorGoogleMaps {
    func addMarker(node: Node<JSValue>?,
                   mapView: CustomMapView) {
        guard let node = node else { return }
        let markerObject = node.value as? JSObject ?? JSObject();
        let preferences = markerObject["preferences"] as? JSObject ?? JSObject();
        
        let marker = CustomMarker()
        marker.updateFromJSObject(preferences: preferences)
        marker.map = mapView.GMapView
        self.customMarkers[marker.id] = marker
        if let url = (markerObject["icon"] as? JSObject)?["url"] as? String {
            imageCache.image(at: url) { [weak self] image in
                marker.icon = image
                self?.addMarker(node: node.next, mapView: mapView)
            }
        }
    }
}

extension CapacitorGoogleMaps: ImageCachable {
    var imageCache: ImageURLLoadable {
        SDWebImageCache.shared
    }
}
