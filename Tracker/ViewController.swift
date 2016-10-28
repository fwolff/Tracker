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

class ViewController: UIViewController, MKMapViewDelegate, TrackerDelegate {

    private let log = Logger.self
    
    private var locationManager: Tracker!
    private var trackFile: TrackFile!
    private var dateFormatter: DateFormatter!
    private var coordinates: [CLLocationCoordinate2D] = []
    
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    @IBAction func start(_ sender: UIButton) {
        if sender.title(for: .normal) == "Start" {
            activityIndicator.startAnimating()
            sender.setTitle("Stop", for: .normal)
            locationManager.start()
        }
        else {
            activityIndicator.stopAnimating()
            sender.setTitle("Start", for: .normal)
            locationManager.stop()
            
            let locations = trackFile.read()
            log.info("saved locations count: ?", locations.count)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        locationManager = Tracker()
        locationManager.delegate = self
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        
        mapView.delegate = self

        var fileUrl = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        fileUrl.appendPathComponent("coordinates.dat")
        trackFile = TrackFile(path: fileUrl.path)
        trackFile.delete()
    }
    
    func trackerDidStart(_ tracker: Tracker) {
        for overlay in mapView.overlays {
            mapView.remove(overlay)
        }
        
        coordinates = []
        let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
        mapView.add(polyline, level: .aboveRoads)
    }
    func tracker(_ tracker: Tracker, didUpdateLocations locations: [CLLocation]) {
        //log.info("locations: ?", locations)
        
        trackFile.append(locations: locations)
        
        if UIApplication.foregrounded() {
            activityIndicator.stopAnimating()
            
            for overlay in mapView.overlays {
                mapView.remove(overlay)
            }
            
            coordinates.append(contentsOf: locations.map({ (location) in return location.coordinate }))
            let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
            mapView.add(polyline, level: .aboveRoads)

            var region = MKCoordinateRegionForMapRect(polyline.boundingMapRect)
            region.span.latitudeDelta *= 1.1
            region.span.longitudeDelta *= 1.1
            mapView.setRegion(region, animated: true)
        }
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let polylineRenderer = MKPolylineRenderer(overlay: overlay)
        polylineRenderer.lineCap = .round
        polylineRenderer.lineJoin = .round
        polylineRenderer.strokeColor = UIColor.blue
        polylineRenderer.lineWidth = 4
        return polylineRenderer
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
}

