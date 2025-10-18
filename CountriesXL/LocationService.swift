import Foundation
import Combine
import CoreLocation
import MapKit

@available(macOS 26.0, *)
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()
    
    @Published var location: CLLocation?
    @Published var placemarkDescription: String = ""
    
    private let locationManager = CLLocationManager()
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        locationManager.requestWhenInUseAuthorization()
        checkAuthorizationAndStart()
    }
    
    private func checkAuthorizationAndStart() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            locationManager.stopUpdatingLocation()
            location = nil
            placemarkDescription = ""
        }
    }
    
    private func updatePlacemarkDescription(from location: CLLocation) {
        Task {
            // Use MapKit's reverse geocoding request instead of deprecated CLGeocoder
            guard let request = MKReverseGeocodingRequest(location: location) else {
                await MainActor.run {
                    self.placemarkDescription = String(
                        format: "%.4f, %.4f",
                        location.coordinate.latitude,
                        location.coordinate.longitude
                    )
                }
                return
            }

            do {
                let items = try await request.mapItems
                if let item = items.first {
                    let displayName = item.name ?? ""

                    await MainActor.run {
                        if !displayName.isEmpty {
                            self.placemarkDescription = displayName
                        } else {
                            self.placemarkDescription = String(
                                format: "%.4f, %.4f",
                                location.coordinate.latitude,
                                location.coordinate.longitude
                            )
                        }
                    }
                } else {
                    await MainActor.run {
                        self.placemarkDescription = String(
                            format: "%.4f, %.4f",
                            location.coordinate.latitude,
                            location.coordinate.longitude
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.placemarkDescription = String(
                        format: "%.4f, %.4f",
                        location.coordinate.latitude,
                        location.coordinate.longitude
                    )
                }
            }
        }
    }
    
    // Public controls for the settings UI
    func requestAuthorizationAndStart() {
        locationManager.requestWhenInUseAuthorization()
        checkAuthorizationAndStart()
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        DispatchQueue.main.async {
            self.location = nil
            self.placemarkDescription = ""
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let lastLocation = locations.last else { return }
        DispatchQueue.main.async {
            self.location = lastLocation
            self.updatePlacemarkDescription(from: lastLocation)
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkAuthorizationAndStart()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.location = nil
            self.placemarkDescription = ""
        }
    }
}

