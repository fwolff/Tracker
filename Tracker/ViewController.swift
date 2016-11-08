//
//  ViewController.swift
//  Tracker
//
//  Created by Franck Wolff on 10/21/16.
//  Copyright © 2016 4riders. All rights reserved.
//

import UIKit
import CoreLocation
import MapKit

class ViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate, TrackerDelegate {

    private let log = Logger.self
    
    private var locationManager: Tracker!
    private var trackFile: TrackFile!
    private var coordinates: [CLLocationCoordinate2D] = []
    
    @IBOutlet weak var startStopButton: UIButton!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    @IBAction func start(_ sender: UIButton) {
        if sender.title(for: .normal) == "Start" {
            activityIndicator.startAnimating()
            sender.setTitle("Stop", for: .normal)
            
            trackFile.delete()
            coordinates = []
            showCoordinates()
            
            locationManager.start()
        }
        else {
            activityIndicator.stopAnimating()
            sender.setTitle("Start", for: .normal)
            
            locationManager.stop()
            
            let locations = trackFile.read()
            coordinates = locations.map({ (location) in return location.coordinate })
            showCoordinates()
        }
    }
    
//    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
//        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
//        
//        log.info()
//    }
    
//    required init?(coder aDecoder: NSCoder) {
//        super.init(coder: aDecoder)
//        
//        log.info()
//        
////        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIApplicationWillEnterForeground, object: nil, queue: nil, using: applicationWillEnterForeground)
////        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIApplicationWillTerminate, object: nil, queue: nil, using: applicationWillTerminate)
//    }
    
//    public func applicationWillEnterForeground(_ notification: Notification) {
//        log.info()
//        
//        showCoordinates()
//    }
//    
//    public func stopLocationManager() {
//        log.info()
//        
//        for region in manager.monitoredRegions {
//            if region.identifier == "fuck" {
//                manager.stopMonitoring(for: region)
//                break
//            }
//        }
//        
//        manager.stopUpdatingLocation()
//        manager.stopMonitoringSignificantLocationChanges()
//    }
//
//    public func applicationWillTerminate(_ notification: Notification) {
//        log.info()
//        
//        for region in manager.monitoredRegions {
//            if region.identifier == "fuck" {
//                manager.stopMonitoring(for: region)
//                break
//            }
//        }
//    }
//    
//    var manager: CLLocationManager!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        log.info()

        locationManager = Tracker()
        locationManager.delegate = self
        
        mapView.delegate = self

        var fileUrl = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        fileUrl.appendPathComponent("coordinates.dat")
        
        trackFile = TrackFile(path: fileUrl.path)
        let locations = trackFile.read()
        coordinates = locations.map({ (location) in return location.coordinate })
        showCoordinates()
    }
    
//    var taskIdentifier = UIBackgroundTaskInvalid
//
//    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
//        log.info()
//        
//        if region.identifier == "fuck" {
//            manager.stopMonitoring(for: region)
//            
//            if taskIdentifier != UIBackgroundTaskInvalid {
//                UIApplication.shared.endBackgroundTask(taskIdentifier)
//                taskIdentifier = UIBackgroundTaskInvalid
//            }
//            
//            if UIApplication.foregrounded() {
//                self.log.info("requestLocation (foreground)")
//                manager.requestLocation()
//            }
//            else {
//                taskIdentifier = UIApplication.shared.beginBackgroundTask {
//                    if self.taskIdentifier != UIBackgroundTaskInvalid {
//                        UIApplication.shared.endBackgroundTask(self.taskIdentifier)
//                        self.taskIdentifier = UIBackgroundTaskInvalid
//                    }
//                }
//
//                DispatchQueue.global().async {
//                    self.log.info("requestLocation (background)")
//                    manager.requestLocation()
//                }
//            }
//        }
//    }
//    
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        log.info("?", locations)
//        
//        coordinates.append(contentsOf: locations.map({ (location) in return location.coordinate }))
//        if UIApplication.foregrounded() {
//            activityIndicator.stopAnimating()
//            showCoordinates()
//        }
//        
//        let region = CLCircularRegion(center: locations.last!.coordinate, radius: 100, identifier: "fuck")
//        region.notifyOnExit = true
//        region.notifyOnEntry = false
//        manager.startMonitoring(for: region)
//        
//        if taskIdentifier != UIBackgroundTaskInvalid {
//            UIApplication.shared.endBackgroundTask(taskIdentifier)
//            taskIdentifier = UIBackgroundTaskInvalid
//        }
//    }
//    
//    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
//        log.error("?", error)
//    }
//    
//    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
//        log.error("?", error)
//    }

    func tracker(_ tracker: Tracker, didUpdateLocations locations: [CLLocation]) {
        trackFile.append(locations: locations)
        coordinates.append(contentsOf: locations.map({ (location) in return location.coordinate }))
        
        if UIApplication.foregrounded() {
            activityIndicator.stopAnimating()
            showCoordinates()
        }
    }
    
    func tracker(_ tracker: Tracker, didFailWithError error: Error) {
        log.error("?", error)
        
        activityIndicator.stopAnimating()
        startStopButton.setTitle("Start", for: .normal)
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let polylineRenderer = MKPolylineRenderer(overlay: overlay)
        polylineRenderer.lineCap = .round
        polylineRenderer.lineJoin = .round
        polylineRenderer.strokeColor = UIColor.blue
        polylineRenderer.lineWidth = 4
        return polylineRenderer
    }
    
    func showCoordinates() {
        for overlay in mapView.overlays {
            mapView.remove(overlay)
        }
        
        if !coordinates.isEmpty {
            let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
            mapView.add(polyline, level: .aboveRoads)
            
            var region = MKCoordinateRegionForMapRect(polyline.boundingMapRect)
            region.span.latitudeDelta *= 1.1
            region.span.longitudeDelta *= 1.1
            mapView.setRegion(region, animated: true)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
}

