//
//  Gpx.swift
//  Tracker
//
//  Created by Franck Wolff on 10/26/16.
//  Copyright © 2016 4riders. All rights reserved.
//

import UIKit
import CoreLocation

class TrackFile {
    
    private static let recordSize = 4 * MemoryLayout<Double>.size
    
    private let path: String
    
    public init(path: String) {
        self.path = path
    }
    
    public func delete() {
        if FileManager.default.fileExists(atPath: path){
            try! FileManager.default.removeItem(atPath: path)
        }
    }
    
    public func append(locations: [CLLocation]) {
        if !FileManager.default.fileExists(atPath: path) && !FileManager.default.createFile(atPath: path, contents: nil, attributes: nil) {
            return
        }

        guard let file = FileHandle(forWritingAtPath: path) else {
            return
        }
        file.seekToEndOfFile()
        
        var data = Data(capacity: locations.count * TrackFile.recordSize)
        for location in locations {
            var value: Double = location.coordinate.latitude
            data.append(UnsafeBufferPointer(start: &value, count: 1))
            
            value = location.coordinate.longitude
            data.append(UnsafeBufferPointer(start: &value, count: 1))
            
            value = location.horizontalAccuracy
            data.append(UnsafeBufferPointer(start: &value, count: 1))
            
            value = location.timestamp.timeIntervalSince1970
            data.append(UnsafeBufferPointer(start: &value, count: 1))
        }
        
        file.write(data)
        file.closeFile()
        
//        if let attributes = try? manager.attributesOfItem(atPath: path) {
//            print((attributes as NSDictionary).fileSize())
//        }
    }
    
    public func read() -> [CLLocation] {
        
        let maxRecordsByRead = 128
        
        guard let file = FileHandle(forReadingAtPath: path) else {
            return []
        }

        var locations: [CLLocation] = []
        
        while true {
            let data = file.readData(ofLength: maxRecordsByRead * TrackFile.recordSize)
            let recordsCount: Int = (data.count / TrackFile.recordSize)
            
            var index = 0
            for _ in 0..<recordsCount {
                var latitude: Double = 0.0, longitude: Double = 0.0, horizontalAccuracy: Double = 0.0, timestamp: Double = 0.0
                
                _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &latitude, count: 1), from: index..<(index + MemoryLayout<Double>.size))
                index += MemoryLayout<Double>.size
                _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &longitude, count: 1), from: index..<(index + MemoryLayout<Double>.size))
                index += MemoryLayout<Double>.size
                _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &horizontalAccuracy, count: 1), from: index..<(index + MemoryLayout<Double>.size))
                index += MemoryLayout<Double>.size
                _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &timestamp, count: 1), from: index..<(index + MemoryLayout<Double>.size))
                index += MemoryLayout<Double>.size
                
                locations.append(CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    altitude: -1,
                    horizontalAccuracy: horizontalAccuracy,
                    verticalAccuracy: -1,
                    timestamp: Date(timeIntervalSince1970: timestamp)
                ))
            }
            
            if recordsCount < maxRecordsByRead {
                break
            }
        }

        return locations
    }
}
