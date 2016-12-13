//
//  InputStream+Callback.swift
//  CallbackStreams
//
//  Created by Teo Sartori on 13/12/2016.
//  Copyright © 2016 Matteo Sartori. All rights reserved.
//

import Foundation

public typealias VoidFunc = (() -> Void)

private var inputStreamKey: UInt8 = 0

extension InputStream {
    
    /// This has to be an NSObject for the associatedObject stuff to work
    class Box : NSObject {
        /// For each stream event type there is a dictionary of uuid strings to void funcs.
        var handlers = [StreamEventType : [String : VoidFunc]]()
    }
    
    
    var handlersContainer: Box {
        get {
            return associatedObject(base: self, key: &inputStreamKey) {
                return Box()
            }
        }
        set {
            associateObject(base: self, key: &inputStreamKey, value: newValue)
        }
    }
    
    /**
     To get around the fact that class extensions cannot use stored properties
     we use associated objects to store an array of handlers, one for each event
     type, in the objC runtime. This is bodgy but the recommended way if you
     want to avoid subclassing InputStream.
     **/
    
    /// Register a handler with an input stream for a given event.
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
        
        /// If the handler is nil we remove the handler with the given uuid.
        guard let handler = handler else {
            
            handlersContainer.handlers[event]?[uuid] = nil
            
            /// Deregister if we removed all handlers.
            if handlersContainer.handlers[event]?.count == 0 {
                CFReadStreamSetClient(self, registeredEvents.rawValue, nil, nil)
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
        
        CFReadStreamSetClient(self, eventFlags, { readStream, streamEvent, data -> Void in
            
            guard let eventType: StreamEventType = StreamEventType.translate(from: streamEvent) else {
                return
            }
            
            /// Bind the UnsafeMutableRawPointer to a [StreamEventType : VoidFunc].self type
            let handlersForEvent = data!.assumingMemoryBound(to: [StreamEventType : [String : VoidFunc]]!.self)
            
            /// Index the handlers with the appropriate event type and call any handlers.
            if let uuidToHandlers = handlersForEvent.pointee[eventType] {
                for (_, handler) in uuidToHandlers {
                    handler()
                }
            }
            
        }, &clientContextPtr)
        
        return uuid
    }
}

extension InputStream {
    
    open func pipe(into writeStream: OutputStream, endHandler: VoidFunc? = nil) {
        /// Connect the tarReadStream to the tarWriteStream
        let bufSize = 512
        
        self.on(event: .hasBytesAvailable) {
            
            let streamBuf: [UInt8] = Array(repeating: 0, count: bufSize)
            let buf = UnsafeMutablePointer<UInt8>(mutating: streamBuf)
            let bytesRead = self.read(buf, maxLength: bufSize)
            
            writeStream.write(payload: Array(streamBuf[0 ..< bytesRead])) {
                print("write done")
            }
        }
        
        self.on(event: .endOfStream) {
            
            writeStream.close()
            writeStream.remove(from: .main, forMode: .defaultRunLoopMode)
            
            self.close()
            self.remove(from: .main, forMode: .defaultRunLoopMode)
            
            endHandler?()
        }
        
        self.schedule(in: .main, forMode: .defaultRunLoopMode)
        writeStream.schedule(in: .main, forMode: .defaultRunLoopMode)
        
        self.open()
        writeStream.open()
    }
}
