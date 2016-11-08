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
    
    func isLaterThan(_ location: CLLocation?, _ startedTimestamp: Date?) -> Bool {
        if let location = location {
            return timestamp > location.timestamp
        }
        return startedTimestamp == nil || timestamp >= startedTimestamp!
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
    
    func tracker(_ tracker: Tracker, authorizationRefusedWithStatus status: CLAuthorizationStatus) {
        Logger.self.error("status=?", status)
    }
    
    func tracker(_ tracker: Tracker, didFailWithError error: Error) {
        Logger.self.error("error=?", error)
    }
    
    func tracker(_ tracker: Tracker, didUpdateLocations locations: [CLLocation]) {}
}

class Tracker: NSObject, CLLocationManagerDelegate {
    
    private let log = Logger.self
    
    public enum State {
        case stopped
        case started
        case deferring
        case monitoringRegion
        case pausedOnLowBattery
        case pausedOnAuthorizationRefused
    }

    private lazy var locationManager: CLLocationManager = {
        [unowned self] in
        var locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestAlwaysAuthorization()
        return locationManager
    }()
    
    private let regionId: String
    
    private(set) var state: State = .stopped
    private(set) var lastLocation: CLLocation? = nil
    private(set) var stationaryLocation: CLLocation? = nil
    private var startedTimestamp: Date? = nil
    
    var delegate: TrackerDelegate? = nil
    
    var minimumBatteryLevel: Float = 0.2 // 20%

    var minimumHorizontalAccuracy: Double = 50.0 // 50 meters
    var maximumWaitForFirstLocation: TimeInterval = 5 * 60.0 // 5 minutes
    var maximumWaitForNextLocation: TimeInterval = 5 * 60.0 // 5 minutes
    var minimumSignificantTimeInterval: TimeInterval = 30.0 // 30 seconds
    var minimumSignificantDistance:CLLocationDistance = 10.0 // 10 meters
    
    var maximumDeferringDistance:CLLocationDistance = CLLocationDistanceMax // infinite meters
    var maximumDeferringTimeout:TimeInterval = 30.0 // 30 seconds
    
    var minimumStationaryDistance:CLLocationDistance = 20.0 // 20 meters
    var minimumStationaryTimeInterval: TimeInterval = 5 * 60.0 // 5 minutes
    var monitoringRegionRadius: Double = 50.0 // 50.0 meters
    
    public override init() {
        log.info()
        
        regionId = (Bundle.main.infoDictionary!["CFBundleName"] as! String) + "_trackerRestartOnExitRegion"
        
        super.init()

        UIDevice.current.isBatteryMonitoringEnabled = true

        addObserver(NSNotification.Name.UIApplicationWillTerminate, using: applicationWillTerminate)
        addObserver(NSNotification.Name.UIApplicationWillEnterForeground, using: applicationWillEnterForeground)
        addObserver(NSNotification.Name.UIDeviceBatteryLevelDidChange, using: deviceBatteryLevelDidChange)
    }
    
    deinit {
        log.info()

        removeObserver(NSNotification.Name.UIApplicationWillTerminate)
        removeObserver(NSNotification.Name.UIApplicationWillEnterForeground)
        removeObserver(NSNotification.Name.UIDeviceBatteryLevelDidChange)
    }
    
    public func start() {
        DispatchQueue.main.async {
            self._start()
        }
    }
    
    private func _start() {
        log.info()
        
        switch state {
        case .started, .pausedOnLowBattery:
            return
        case .deferring:
            locationManager.disallowDeferredLocationUpdates()
            state = .started
            return
        case .monitoringRegion:
            stopMonitoringRegion()
        case .stopped, .pausedOnAuthorizationRefused:
            break
        }
        
        lastLocation = nil
        stationaryLocation = nil
        
        if !CLLocationManager.locationServicesEnabled() {
            state = .pausedOnAuthorizationRefused
            delegate { $0.tracker(self, authorizationRefusedWithStatus: .denied) }
            return
        }
        
        let status = CLLocationManager.authorizationStatus()
        
        if status == .denied || status == .restricted || status == .authorizedWhenInUse {
            state = .pausedOnAuthorizationRefused
            delegate { $0.tracker(self, authorizationRefusedWithStatus: status) }
            return
        }
        
        startedTimestamp = Date()
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
        state = .started
        
        delegate { $0.trackerDidStart(self) }
    }
    
    public func stop() {
        log.info()

        switch state {
        case .stopped, .pausedOnAuthorizationRefused, .pausedOnLowBattery:
            return
        case .monitoringRegion:
            stopMonitoringRegion()
        case .deferring:
            locationManager.disallowDeferredLocationUpdates()
            fallthrough
        case .started:
            locationManager.stopUpdatingLocation()
        }

        lastLocation = nil
        stationaryLocation = nil
        startedTimestamp = nil
        
        state = .stopped
        
        delegate { $0.trackerDidStop(self) }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        log.info()
        
        stop()
    }
    
    public func applicationWillEnterForeground(_ notification: Notification) {
        log.info()
        
        start()
    }
    
    private func pauseOnLowBattery() {
        log.info()
        
        stop()
        state = .pausedOnLowBattery
    }
    
    private func resumeOnLowBattery() {
        log.info()
        
        state = .stopped
        start()
    }
    
    public func deviceBatteryLevelDidChange(_ notification: Notification) {
        log.info("Batery level: ?", UIDevice.current.batteryLevel)
        
        if UIDevice.current.batteryLevel <= minimumBatteryLevel {
            pauseOnLowBattery()
        }
        else if state == .pausedOnLowBattery {
            resumeOnLowBattery()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        log.info("?", status.rawValue)
        
        switch status {
            case .authorizedAlways:
                if state == .pausedOnAuthorizationRefused {
                    start()
                }
            
            case .denied, .restricted, .authorizedWhenInUse:
                stop()
                state = .pausedOnAuthorizationRefused
                delegate { $0.tracker(self, authorizationRefusedWithStatus: status) }
            
            case .notDetermined:
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
        
        stop()

        if let clError = error as? CLError {
            if clError.code == CLError.denied || clError.code == CLError.regionMonitoringDenied {
                state = .pausedOnAuthorizationRefused
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFinishDeferredUpdatesWithError error: Error?) {
        if error == nil {
            log.info()
        }
        else {
            log.error("?", error)
        }

        if state == .deferring {
            state = .started

            if let clError = error as? CLError {
                if clError.code == CLError.deferredFailed {
                    log.info("################# RESTART ON DEFERRED FAILED #################")
                    
                    stop()
                    start()
                }
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        log.info("?", locations)
        
        if lastLocation == nil && locations.last!.timestamp.timeIntervalSince(startedTimestamp!) > maximumWaitForFirstLocation {
            let error = NSError(domain: CLError._nsErrorDomain, code: CLError.locationUnknown.rawValue, userInfo: nil)
            delegate { $0.tracker(self, didFailWithError: error) }
            
            stop()
            return
        }
        
        if locations.count > 1 {
            log.info("################# DEFERRED: ? #################", locations.count)
        }
        
        var shouldStartMonitoringRegion = false
        
        var locations = locations.filter({ $0.isValid(minimumHorizontalAccuracy) && $0.isLaterThan(lastLocation, startedTimestamp)})
        if locations.isEmpty {
            if lastLocation != nil && Date().timeIntervalSince(lastLocation!.timestamp) > maximumWaitForNextLocation {
                stationaryLocation = lastLocation!
                shouldStartMonitoringRegion = true
            }
        }
        else {
            locations.sort(by: { $0.timestamp < $1.timestamp })
            
            var significantLocations: [CLLocation] = []
            
            if stationaryLocation == nil {
                stationaryLocation = locations.first!
            }

            if lastLocation == nil {
                lastLocation = locations.first!
                significantLocations.append(lastLocation!)
            }
            
            var moved = false
            for location in locations {
                if location.isSignificant(from: lastLocation!, minTimeInterval: minimumSignificantTimeInterval, minDistance: minimumSignificantDistance) {
                    lastLocation = location
                    significantLocations.append(lastLocation!)
                }
                if !moved && location.distance(from: stationaryLocation!) >= minimumStationaryDistance {
                    moved = true
                }
            }
            
            if moved {
                stationaryLocation = locations.last!
            }
            else {
                let interval = locations.last!.timestamp.timeIntervalSince(stationaryLocation!.timestamp)
//                log.info("interval: ?", interval)
                if interval >= minimumStationaryTimeInterval {
                    stationaryLocation = locations.last!
                    shouldStartMonitoringRegion = true
                }
            }
            
            if !significantLocations.isEmpty {
                log.info("significantLocations: ?", significantLocations)
                
                delegate { $0.tracker(self, didUpdateLocations: significantLocations) }
            }
        }
        
        if isLowOnBattery() {
            pauseOnLowBattery()
        }
        else if shouldStartMonitoringRegion {
            startMonitoringRegion(stationaryLocation!)
        }
        else if UIApplication.backgrounded() {
            startDeferring()
        }
        else {
            stopDeferring()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        log.info("################### DID EXIT REGION: ? ###################", region)
        
        if region.identifier == regionId {
            DispatchQueue.global().async {
                self.start()
            }
        }
    }
    
    public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        log.info()
    }
    
    public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        log.info()
    }
    
    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        log.info()
    }
    
    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        log.error("?", error)
    }
    private func startDeferring() {
        if state == .started && CLLocationManager.deferredLocationUpdatesAvailable() && lastLocation != nil && lastLocation!.timestamp.timeIntervalSince(startedTimestamp!) >= 15.0 {
            log.info()
            
            locationManager.allowDeferredLocationUpdates(untilTraveled: maximumDeferringDistance, timeout: maximumDeferringTimeout)
            state = .deferring
        }
    }
    
    private func stopDeferring() {
        if state == .deferring {
            log.info()
            
            locationManager.disallowDeferredLocationUpdates()
            state = .started
        }
    }
    
    private func startMonitoringRegion(_ center: CLLocation) {
        stop()

        log.info("################### MONITOR REGION: ? ###################", center)
        
        let region = CLCircularRegion(center: center.coordinate, radius: monitoringRegionRadius, identifier: regionId)
        region.notifyOnExit = true
        region.notifyOnEntry = false
        locationManager.startMonitoring(for: region)
        
        state = .monitoringRegion
    }
    
    private func stopMonitoringRegion() {
        log.info()

        for region in locationManager.monitoredRegions {
            if region.identifier == regionId {
                log.info("Region found: ?", region)
                locationManager.stopMonitoring(for: region)
                break
            }
        }
    }
    
    private func delegate(_ block: @escaping (TrackerDelegate) -> Void) {
        if let delegate = self.delegate {
            DispatchQueue.main.async {
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
    
    private func isLowOnBattery() -> Bool {
        return (
            UIDevice.current.isBatteryMonitoringEnabled &&
            UIDevice.current.batteryState != .charging &&
            UIDevice.current.batteryLevel <= minimumBatteryLevel
        )
    }
}
