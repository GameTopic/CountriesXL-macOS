import Foundation
import Combine
import CoreLocation
@preconcurrency import MapKit

// LocationService provides an observable, main-actor isolated API for current location and a
// human-readable placemark description. It uses the modern MapKit reverse geocoding API
// (MKReverseGeocodingRequest) available on macOS 26+ and iOS 26+.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    // Published state
    @Published var location: CLLocation?
    @Published var placemarkDescription: String = ""

    private let locationManager = CLLocationManager()

    private override init() {
        super.init()
        configureLocationManager()
        requestAuthorizationIfNeeded()
    }

    private func configureLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        // Do not start location updates until authorized
    }

    private func requestAuthorizationIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        case .restricted, .denied:
            stop()
        @unknown default:
            stop()
        }
    }

    private func startIfAuthorized() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }

    private func updatePlacemarkDescription(from location: CLLocation) {
        // Use modern MapKit reverse geocoding API only
        if let request = MKReverseGeocodingRequest(location: location) {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let items = try await request.mapItems
                    if let item = items.first {
                        let displayName = item.name ?? ""
                        self.placemarkDescription = displayName.isEmpty
                            ? String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
                            : displayName
                    } else {
                        self.placemarkDescription = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
                    }
                } catch {
                    self.placemarkDescription = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
                }
            }
        } else {
            self.placemarkDescription = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
        }
    }

    // Public controls for the settings UI
    func requestAuthorizationAndStart() {
        locationManager.requestWhenInUseAuthorization()
        // start will be handled in delegate callback
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        self.location = nil
        self.placemarkDescription = ""
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let lastLocation = locations.last else { return }
        Task { @MainActor in
            self.location = lastLocation
            self.updatePlacemarkDescription(from: lastLocation)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.startIfAuthorized()
            case .notDetermined:
                break
            default:
                self.stop()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.stop()
        }
    }
}

