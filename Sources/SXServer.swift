
//  Copyright (c) 2016, Yuji
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
//  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//  The views and conclusions contained in the software and documentation are those
//  of the authors and should not be interpreted as representing official policies,
//  either expressed or implied, of the FreeBSD Project.
//
//  Created by yuuji on 6/2/16.
//  Copyright © 2016 yuuji. All rights reserved.
//

import Foundation

public protocol SXServer : SXRuntimeObject, SXRuntimeController {
    var maxGuest: Int { get set }
    var socket: SXLocalSocket { get set }
   
    var port: in_port_t { get set }
    var bufsize: Int { get set }
    var backlog: Int { get set }
    
    #if swift(>=3)
    func start(listenQueue: (() -> SXThreadingProxy), operateQueue: (() -> SXThreadingProxy))
    #else
    func start(listenQueue: (() -> dispatch_queue_t), operateQueue: (() -> dispatch_queue_t))
    #endif
}


public class SXStreamServer: SXServer, SXRuntimeDataDelegate {
    public var maxGuest: Int
    public var socket: SXLocalSocket
   
    public var owner: AnyObject? = nil
    public var status: SXStatus
    public var port: in_port_t
    public var bufsize: Int
    public var backlog: Int

    public var delegate: SXStreamServerDelegate?

    public var didReceiveData: (_ object: SXQueue, _ data: Data) -> Bool
    public var didReceiveError: ((_ object: SXRuntimeObject, _ err: Error) -> ())?
    
    public var recvFlag: Int32 = 0
    public var sendFlag: Int32 = 0
    
    public func statusDidChange(status: SXStatus) {
        guard let delegate = self.delegate else {return}
        delegate.didChangeStatus?(self, status)
    }
    
    public func close() {
        self.delegate?.didKill?(self)
        self.socket.close()
    }
    
    public init(port: in_port_t, domain: SXSocketDomains, protocol: Int32 = 0, maxGuest: Int, backlog: Int, bufsize: Int = 16384, dataDelegate: SXRuntimeDataDelegate) throws {
        self.status = .idle
        self.socket = try SXLocalSocket(port: port, domain: domain, type: .stream, protocol: `protocol`, bufsize: bufsize)
        try self.socket.bind()
        self.port = port
        self.backlog = backlog
        self.maxGuest = maxGuest
        self.bufsize = bufsize
        self.didReceiveData = dataDelegate.didReceiveData
        self.didReceiveError = dataDelegate.didReceiveError
    }
    
    public convenience init(port: in_port_t, domain: SXSocketDomains, protocol: Int32 = 0, maxGuest: Int, backlog: Int, bufsize: Int = 16384, handler: @escaping (_ object: SXQueue, _ data: Data) -> Bool) throws {
        try self.init(port: port, domain: domain, protocol: `protocol`, maxGuest: maxGuest, backlog: backlog, bufsize: bufsize, handler: handler, errHandler: nil)
    }
    
    public init(port: in_port_t, domain: SXSocketDomains, protocol: Int32 = 0, maxGuest: Int, backlog: Int, bufsize: Int = 16384, handler: @escaping (_ object: SXQueue, _ data: Data) -> Bool, errHandler: ((_ object: SXRuntimeObject, _ err: Error) -> ())? = nil) throws {
        self.status = .idle
        self.socket = try SXLocalSocket(port: port, domain: domain, type: .stream, protocol: `protocol`, bufsize: bufsize)
        try self.socket.bind()
        self.port = port
        self.backlog = backlog
        self.maxGuest = maxGuest
        self.bufsize = bufsize
        self.didReceiveData = handler
    }
    
    public func start() {
        self.start(listenQueue: {
            #if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
            return GrandCentralDispatchQueue(DispatchQueue.global())
            #elseif os(Linux) || os(FreeBSD)
            return SXThreadPool.default
            #endif
            }, operateQueue: {
            #if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
                return GrandCentralDispatchQueue(DispatchQueue.global())
            #elseif os(Linux) || os(FreeBSD)
                return SXThreadPool.default
            #endif
            }
        )
    }
    
    public func start(listenQueue listeningQueue: (() -> SXThreadingProxy), operateQueue operatingQueue: (()->SXThreadingProxy)) {
        
        var listenQueue = listeningQueue()
        listenQueue.execute {

            self.status = .running
            var count = 0
            do {
                while self.status != .shouldTerminate {
                    
                    try self.socket.listen(backlog: self.backlog)
                    
                    if self.status == .shouldTerminate {
                        break
                    } else if self.status == .suspended {
                        continue
                    }
                    
                    do {
                        
                        let socket = try self.socket.accept(bufsize: self.bufsize)
                        if count >= self.maxGuest {
                            count += 1
                            continue
                        }
                        
                        if let handler = self.delegate?.shouldConnect?(self, socket) {
                            if !handler {
                                socket.close()
                                continue
                            }
                        }
                        
                        var queue: SXStreamQueue = SXStreamQueue(server: self, socket: socket)
                        
                        if self.delegate != nil {
                            transfer(lhs: &queue.delegate!, rhs: &self.delegate!)
                        }
                        
                        var operateQueue = operatingQueue()
                        operateQueue.execute {
                            queue.start(completion: {
                                queue.close()
                                queue.delegate?.didDisconnect?(queue, queue.socket)
                                count -= 1
                            })
                        }
                        
                    } catch {
                        self.didReceiveError?(self, error)
                        continue
                    }
                }
                
                self.status = .idle
                self.close()
                self.delegate?.didKill?(self)
            } catch {
                self.didReceiveError?(self, error)
            }
        }
    }
}
