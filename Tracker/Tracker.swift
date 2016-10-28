//
//  LocationManager.swift
//  Tracker
//
//  Created by Franck Wolff on 10/21/16.
//  Copyright © 2016 4riders. All rights reserved.
//

import UIKit
import CoreLocation

extension CLLocation {
    
    func isValid(_ maximumHorizontalAccuracy: CLLocationAccuracy) -> Bool {
        return (
            horizontalAccuracy <= maximumHorizontalAccuracy &&
            horizontalAccuracy >= 0 &&
            CLLocationCoordinate2DIsValid(coordinate)
        )
    }
    
    func isLaterThan(_ location: CLLocation?) -> Bool {
        return location == nil || timestamp > location!.timestamp
    }
    
    func isSignificant(from location: CLLocation?, minTimeInterval: TimeInterval, minDistance: CLLocationDistance) -> Bool {
        return (
            location == nil ||
            horizontalAccuracy < location!.horizontalAccuracy ||
            timestamp.timeIntervalSince(location!.timestamp) >= minTimeInterval ||
            distance(from: location!) >= minDistance
        )
    }
}

protocol TrackerDelegate: class  {
    
    func trackerDidStart(_ tracker: Tracker)
    func trackerDidPause(_ tracker: Tracker)
    func trackerDidResume(_ tracker: Tracker)
    func trackerDidStop(_ tracker: Tracker)
    
    func tracker(_ tracker: Tracker, authorizationRefusedWithStatus status: CLAuthorizationStatus)
    func tracker(_ tracker: Tracker, didFailWithError error: Error)
    func tracker(_ tracker: Tracker, didUpdateLocations locations: [CLLocation])
}

extension TrackerDelegate {

    func trackerDidStart(_ tracker: Tracker) {}
    func trackerDidPause(_ tracker: Tracker) {}
    func trackerDidResume(_ tracker: Tracker) {}
    func trackerDidStop(_ tracker: Tracker) {}
    
    func tracker(_ tracker: Tracker, authorizationRefusedWithStatus status: CLAuthorizationStatus) {}
    func tracker(_ tracker: Tracker, didFailWithError error: Error) {}
    func tracker(_ tracker: Tracker, didUpdateLocations locations: [CLLocation]) {}
}

class Tracker: NSObject, CLLocationManagerDelegate {
    
    private let log = Logger.self
    
//    public static let LocationManagerError = NSNotification.Name("Tracker.Error")
//    public static let LocationManagerAuthorizationRefused = NSNotification.Name("Tracker.AuthorizationRefused")
//    public static let LocationManagerDidStart = NSNotification.Name("Tracker.DidStart")
//    public static let LocationManagerDidStop = NSNotification.Name("Tracker.DidStop")
//    public static let LocationManagerDidUpdateLocations = NSNotification.Name("Tracker.DidUpdateLocations")
    
    private var locationManager: CLLocationManager? = nil
    
    private(set) var lastLocation: CLLocation? = nil
    private(set) var started: Bool = false
    private(set) var deferred: Bool = false
    
    var delegate: TrackerDelegate? = nil
    var maximumHorizontalAccuracy = 50.0
    
    public static func authorizationStatusToString(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways:
            return "authorizedAlways"
        case .authorizedWhenInUse:
            return "authorizedWhenInUse"
        case .denied:
            return "denied"
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        }
    }
    
    public override init() {
        log.info()
        
        super.init()
    }
    
    public func start() {
        log.info()
        
        if locationManager == nil || !started {
            if locationManager == nil {
                create()
                return
            }
            
            addObserver(NSNotification.Name.UIApplicationWillTerminate, using: applicationWillTerminate)
            addObserver(NSNotification.Name.UIApplicationWillEnterForeground, using: applicationWillEnterForeground)
            
            lastLocation = nil
            locationManager!.startUpdatingLocation()
            started = true

            delegate { $0.trackerDidStart(self) }
        }
    }
    
    public func stop() {
        log.info()
        
        if locationManager != nil {
            removeObserver(NSNotification.Name.UIApplicationWillTerminate)
            removeObserver(NSNotification.Name.UIApplicationWillEnterForeground)

            locationManager!.stopUpdatingLocation()
            locationManager = nil
            lastLocation = nil
            started = false
            
            delegate { $0.trackerDidStop(self) }
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        log.info()
        stop()
    }
    
    public func applicationWillEnterForeground(_ notification: Notification) {
        log.info()
        stopDeferring()
    }
    
    private func create() {
        log.info()

        if locationManager == nil {
            started = false
            
            if !CLLocationManager.locationServicesEnabled() {
                delegate { $0.tracker(self, authorizationRefusedWithStatus: .denied) }
                return
            }
            
            let status = CLLocationManager.authorizationStatus()
            
            if status == .denied || status == .restricted || status == .authorizedWhenInUse {
                delegate { $0.tracker(self, authorizationRefusedWithStatus: status) }
                return
            }
            
            locationManager = CLLocationManager()
            locationManager!.delegate = self
            locationManager!.activityType = .fitness
            locationManager!.pausesLocationUpdatesAutomatically = true
            locationManager!.allowsBackgroundLocationUpdates = true
            locationManager!.desiredAccuracy = kCLLocationAccuracyBest
            locationManager!.distanceFilter = kCLDistanceFilterNone
            locationManager!.requestAlwaysAuthorization()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        log.info("?", status.rawValue)
        
        switch status {
            case .authorizedAlways:
                start()
            
            case .denied, .restricted:
                delegate { $0.tracker(self, authorizationRefusedWithStatus: status) }
                stop()
            
            case .notDetermined, .authorizedWhenInUse:
                break
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log.error("?", error)
        
        if let clError = error as? CLError {
            if clError.code == CLError.locationUnknown {
                return
            }
        }
        delegate { $0.tracker(self, didFailWithError: error) }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        log.error("?", error)
        
        deferred = false
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        if locations.count > 1 {
            log.info("################# DEFERRED: ? #################", locations.count)
        }
        
        var locations = locations.filter({ $0.isValid(maximumHorizontalAccuracy) && $0.isLaterThan(lastLocation)})
        if !locations.isEmpty {
            
            var significantLocations: [CLLocation] = []
            if locations.count == 1 {
                if locations.first!.isSignificant(from: lastLocation, minTimeInterval: 30, minDistance: 10) {
                    significantLocations = locations
                }
            }
            else {
                locations.sort(by: { $0.timestamp.compare($1.timestamp) == .orderedAscending })
                
                var previousLocation: CLLocation
                var locationsCollection: [CLLocation]
                
                if let lastLocation = lastLocation {
                    previousLocation = lastLocation
                    locationsCollection = locations
                }
                else {
                    previousLocation = locations.first!
                    significantLocations.append(previousLocation)
                    locationsCollection = Array(locations.dropFirst())
                }
                
                for location in locationsCollection {
                    if location.isSignificant(from: previousLocation, minTimeInterval: 30, minDistance: 10) {
                        previousLocation = location
                        significantLocations.append(previousLocation)
                    }
                }
            }
            
            if !significantLocations.isEmpty {
                log.info("? - ?", lastLocation, significantLocations)
                delegate { $0.tracker(self, didUpdateLocations: significantLocations) }
                lastLocation = significantLocations.last!
            }
        }
        
        if UIApplication.backgrounded() {
            startDeferring()
        }
        else {
            stopDeferring()
        }
    }
    
    public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        log.info()

        delegate { $0.trackerDidPause(self) }
    }
    
    public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        log.info()
        
        delegate { $0.trackerDidResume(self) }
    }
    
    private func startDeferring() {
        if !deferred && CLLocationManager.deferredLocationUpdatesAvailable() {
            log.info()
            locationManager!.allowDeferredLocationUpdates(untilTraveled: CLLocationDistanceMax, timeout: 30)
            deferred = true
        }
    }
    
    private func stopDeferring() {
        if deferred {
            log.info()
            locationManager!.disallowDeferredLocationUpdates()
            deferred = false
        }
    }
    
    private func delegate(_ block: @escaping (TrackerDelegate) -> Void) {
        if let delegate = self.delegate {
            DispatchQueue.main.async() {
                block(delegate)
            }
        }
    }
    
    private func addObserver(_ name: NSNotification.Name?, using block: @escaping (Notification) -> Swift.Void) {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil, using: block)
        
    }
    
    private func removeObserver(_ name: NSNotification.Name? = nil) {
        NotificationCenter.default.removeObserver(self, name: name, object: nil)
        
    }
}
