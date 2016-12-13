//
//  OutputStream+Callback.swift
//  CallbackStreams
//
//  Created by Teo Sartori on 13/12/2016.
//  Copyright © 2016 Matteo Sartori. All rights reserved.
//

import Foundation

private var outputStreamKey: UInt8 = 0

extension OutputStream {
    
    // MARK: Consider wrapping in a queue and sync calls to make thread safe
    /// write(payload: completionHandler:)
    /// Writes all the bytes in the given payload and executes the completionHandler
    /// on success.
    /// - Parameters:
    ///   - payload: the bytes to write on the outputstream
    ///   - completionHandler: the block to execute on completing the write of all bytes.
    open func write(payload: [UInt8], completionHandler: @escaping VoidFunc) {
        var data = payload
        
        while data.count > 0 {
            
            guard self.hasSpaceAvailable else {
                
                let handlerId = UUID().uuidString
                /// No space in write stream! Register for notification when there's space available again.
                self.on(event: .canAcceptBytes, handlerUuid: handlerId) {
                    /// Now there's space, immedately unregister.
                    self.on(event: .canAcceptBytes, handlerUuid: handlerId, handler: nil)
                    
                    /// And start writing again.
                    self.write(payload: data, completionHandler: completionHandler)
                }
                return
            }
            
            /// write as much as we can
            let written = self.write(data, maxLength: data.count)
            if written > 0 {
                data = Array(data[written ..< data.count])
            }
        }
        
        completionHandler()
    }
    
    /// This has to be an NSObject for the associatedObject stuff to work
    class Box : NSObject {
        var handlers = [StreamEventType : [String : VoidFunc]]()
    }
    
    
    var handlersContainer: Box {
        get {
            return associatedObject(base: self, key: &outputStreamKey) {
                return Box()
            }
        }
        set {
            associateObject(base: self, key: &outputStreamKey, value: newValue)
        }
    }
    
    /// Register a handler with an output stream for a given event.
    ///
    /// - Parameters:
    ///   - event: The event that will trigger the handler
    ///   - handlerUuid: The uuid string of a handler we wish to deregister.
    ///   - handler: The handler block that should be called when the event triggers.
    /// - Returns: A uuid string to uniquely identify the handler. Use to deregister the handler.
    
    @discardableResult open func on(event: StreamEventType, handlerUuid: String? = nil, handler: VoidFunc?) -> String? {
        
        guard let registeredEvents = StreamEventType.translate(from: event) else {
            print("Error! no such event type.")
            return nil
        }
        
        /// If we don't pass in a uuid we create a fresh one.
        let uuid = handlerUuid ?? UUID().uuidString
        
        /// If the handler is nil we deregister the client.
        guard let handler = handler else {
            handlersContainer.handlers[event]?[uuid] = nil
            
            /// Deregister if we removed all handlers.
            if handlersContainer.handlers[event]?.count == 0 {
                CFWriteStreamSetClient(self, registeredEvents.rawValue, nil, nil)
            }
            return nil
        }
        
        if handlersContainer.handlers[event] == nil {
            handlersContainer.handlers[event] = [uuid : handler]
        } else {
            handlersContainer.handlers[event]![uuid] = handler
        }
        
        /// make a bitfield from the events
        var eventFlags: CFOptionFlags = 0
        
        for f in handlersContainer.handlers {
            guard let event = StreamEventType.translate(from: f.key) else { continue }
            eventFlags = eventFlags | event.rawValue
        }
        
        /// Get the address of the handlers' dictionary
        let gCtx = withUnsafeMutablePointer(to: &handlersContainer.handlers) { return $0 }
        
        var clientContextPtr = CFStreamClientContext(version: 0,
                                                     info: gCtx,
                                                     retain: nil,
                                                     release: nil,
                                                     copyDescription: nil)
        
        CFWriteStreamSetClient(self, eventFlags, { readStream, streamEvent, data -> Void in
            
            guard let eventType: StreamEventType = StreamEventType.translate(from: streamEvent) else {
                return
            }
            
            /// Bind the UnsafeMutableRawPointer to a [StreamEventType : VoidFunc].self type
            let handlersForEvent = data!.assumingMemoryBound(to: [StreamEventType : [String : VoidFunc]]!.self)
            
            /// Index the handlers with the appropriate event type.
            if let uuidToHandlers = handlersForEvent.pointee[eventType] {
                for (_, handler) in uuidToHandlers {
                    //print("calling handler for uuid \(uuid)")
                    handler()
                }
            }
        }, &clientContextPtr)
        
        return uuid
    }
}
