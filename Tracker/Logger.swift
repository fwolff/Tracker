//
//  Logger.swift
//  Tracker
//
//  Created by Franck Wolff on 10/25/16.
//  Copyright © 2016 4riders. All rights reserved.
//

import UIKit

class Logger {
    
    public enum Level: Int, CustomStringConvertible {
        case error = 0
        case info = 1
        case debug = 2

        public var description: String {
            switch self {
            case .error: return "ERROR"
            case .info: return "INFO"
            case .debug: return "DEBUG"
            }
        }
    }

    public static var level: Level = .info
    
    public static func error(_ format: String = "", _ arguments: Any..., file: String = #file, line: Int = #line, function: String = #function) {
        log(.error, format: format, arguments: arguments, file: file, line: line, function: function)
    }
    
    public static func info(_ format: String = "", _ arguments: Any..., file: String = #file, line: Int = #line, function: String = #function) {
        log(.info, format: format, arguments: arguments, file: file, line: line, function: function)
    }
    
    public static func debug(_ format: String = "", _ arguments: Any..., file: String = #file, line: Int = #line, function: String = #function) {
        log(.debug, format: format, arguments: arguments, file: file, line: line, function: function)
    }
    
    private static func log(_ level: Level, format: String, arguments: [Any], file: String, line: Int, function: String) {
        if level.rawValue <= Logger.level.rawValue {
            let message = self.format(format, arguments: arguments)
            if message.isEmpty {
                NSLog("[\(level.description)] - \(stripFileName(file)).\(function)@\(line)")
            }
            else {
                NSLog("[\(level.description)] - \(stripFileName(file)).\(function)@\(line): \(message)")
            }
        }
    }
    
    private static func stripFileName(_ name: String) -> String {
        guard let start = name.range(of: "/", options: .backwards)?.upperBound else {
            return name
        }
        guard let end = name.range(of: ".", options: .backwards)?.lowerBound else {
            return name
        }
        if start > end {
            return name
        }
        return name.substring(with: Range(uncheckedBounds: (lower: start, upper: end)))
    }

    private static func format(_ pattern: String, arguments: [Any]) -> String {
        var formatted = ""
        var iArg = 0
        var escape = false
        
        for c in pattern.characters {
            if escape {
                formatted.append(c)
                escape = false
                continue
            }
            switch c {
            case "\\":
                escape = true
            case "?":
                if iArg < arguments.count {
                    formatted.append("\(arguments[iArg])")
                    iArg += 1
                    break
                }
                fallthrough
            default:
                formatted.append(c)
            }
        }
        
        if iArg < arguments.count {
            if iArg > 0 {
                formatted.append(" ... ")
            }
            
            var first = true
            while iArg < arguments.count {
                if first {
                    first = false
                }
                else {
                    formatted.append(", ")
                }
                formatted.append("\(arguments[iArg])")
                iArg += 1
            }
        }
        
        return formatted
    }
}

