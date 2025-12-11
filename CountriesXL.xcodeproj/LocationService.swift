//
//  LocationService.swift
//
//  Requires Info.plist key:
//  NSLocationWhenInUseUsageDescription
//

import Foundation
import CoreLocation
import Combine

final class LocationService: NSObject, ObservableObject {
    
    private let kLastPlacemarkKey = "LocationService.lastPlacemark"
    private let kLastLatitudeKey = "LocationService.lastLatitude"
    private let kLastLongitudeKey = "LocationService.lastLongitude"
    
    static let shared = LocationService()
    
    private let locationManager: CLLocationManager
    private let geocoder: CLGeocoder
    
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var location: CLLocation?
    @Published var placemarkDescription: String = ""
    @Published var lastError: String?
    
    private override init() {
        locationManager = CLLocationManager()
        geocoder = CLGeocoder()
        authorizationStatus = locationManager.authorizationStatus
        
        super.init()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 1000
        
        if let cached = UserDefaults.standard.string(forKey: kLastPlacemarkKey) {
            self.placemarkDescription = cached
        }
        let lat = UserDefaults.standard.double(forKey: kLastLatitudeKey)
        let lon = UserDefaults.standard.double(forKey: kLastLongitudeKey)
        if lat != 0 || lon != 0 {
            self.location = CLLocation(latitude: lat, longitude: lon)
        }
    }
    
    func requestAuthorizationAndStart() {
        if UserDefaults.standard.bool(forKey: "LocationEnabled") == false {
            return
        }
        
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdatingLocation()
        case .denied:
            updateLastError("Location access denied.")
        case .restricted:
            updateLastError("Location access restricted.")
        @unknown default:
            updateLastError("Unknown authorization status.")
        }
    }
    
    private func startUpdatingLocation() {
        DispatchQueue.main.async {
            self.lastError = nil
        }
        locationManager.startUpdatingLocation()
    }
    
    func stop() {
        locationManager.stopUpdatingLocation()
    }
    
    private func updateLastError(_ error: String?) {
        DispatchQueue.main.async {
            self.lastError = error
        }
    }
    
    private func updateAuthorizationStatus(_ status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
    }
    
    private func updateLocation(_ location: CLLocation?) {
        DispatchQueue.main.async {
            self.location = location
        }
    }
    
    private func updatePlacemarkDescription(_ description: String) {
        DispatchQueue.main.async {
            self.placemarkDescription = description
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        updateAuthorizationStatus(status)
        
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdatingLocation()
        case .denied:
            updateLastError("Location access denied.")
        case .restricted:
            updateLastError("Location access restricted.")
        case .notDetermined:
            break
        @unknown default:
            updateLastError("Unknown authorization status.")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let firstLocation = locations.first else { return }
        
        updateLocation(firstLocation)
        UserDefaults.standard.set(firstLocation.coordinate.latitude, forKey: kLastLatitudeKey)
        UserDefaults.standard.set(firstLocation.coordinate.longitude, forKey: kLastLongitudeKey)
        
        locationManager.stopUpdatingLocation()
        
        geocoder.reverseGeocodeLocation(firstLocation) { [weak self] placemarks, error in
            guard let self = self else { return }
            
            if let error = error {
                self.updateLastError("Reverse geocoding error: \(error.localizedDescription)")
                return
            }
            
            guard let placemark = placemarks?.first else {
                self.updatePlacemarkDescription("")
                UserDefaults.standard.set("", forKey: self.kLastPlacemarkKey)
                return
            }
            
            let city = placemark.locality ?? ""
            let region = placemark.administrativeArea ?? ""
            let country = placemark.country ?? ""
            
            let components = [city, region, country].filter { !$0.isEmpty }
            let description = components.joined(separator: ", ")
            
            self.updatePlacemarkDescription(description)
            UserDefaults.standard.set(self.placemarkDescription, forKey: self.kLastPlacemarkKey)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        updateLastError("Location update failed: \(error.localizedDescription)")
    }
}
