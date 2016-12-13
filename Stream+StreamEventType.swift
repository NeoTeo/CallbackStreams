//
//  Stream+StreamEventType.swift
//  CallbackStreams
//
//  Created by Teo Sartori on 13/12/2016.
//  Copyright © 2016 Matteo Sartori. All rights reserved.
//

import Foundation

/// CFStreamEventType does not conform to the Hashable protocol and cannot be used
/// as an index in the Box class we're using with associatedObject.
/// With StreamEventType we get a Hashable wrapper.
public enum StreamEventType {
    
    case openCompleted
    case hasBytesAvailable
    case canAcceptBytes
    case errorOccurred
    case endOfStream
    
    static func translate(from eventType: CFStreamEventType) -> StreamEventType? {
        switch eventType {
        case CFStreamEventType.openCompleted:
            return StreamEventType.openCompleted
            
        case CFStreamEventType.hasBytesAvailable:
            return StreamEventType.hasBytesAvailable
            
        case CFStreamEventType.canAcceptBytes:
            return StreamEventType.canAcceptBytes
            
        case CFStreamEventType.errorOccurred:
            return StreamEventType.errorOccurred
            
        case CFStreamEventType.endEncountered:
            return StreamEventType.endOfStream
            
        default: // case not handled
            return nil
        }
    }
    
    static func translate(from eventType: StreamEventType) -> CFStreamEventType? {
        switch eventType {
            
        case .openCompleted:
            return CFStreamEventType.openCompleted
            
        case .hasBytesAvailable:
            return CFStreamEventType.hasBytesAvailable
            
        case .canAcceptBytes:
            return CFStreamEventType.canAcceptBytes
            
        case .errorOccurred:
            return CFStreamEventType.errorOccurred
            
        case .endOfStream:
            return CFStreamEventType.endEncountered
            
        }
    }
}
