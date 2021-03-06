
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
//  Created by yuuji on 7/8/16.
//  Copyright © 2016 yuuji. All rights reserved.
//

// this protocol provides an inteface to use ANY 
// threading library as long as they confirms to this protocol
public protocol SXThreadingProxy {
    mutating func execute(block: @escaping () -> Void)
}

#if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
    public var SXThreadingProxyDefault = GrandCentralDispatchQueue(DispatchQueue.global())
#else
    public var SXThreadingProxyDefault = SXThreadPool.default
#endif



//==============================//
//  built-in threading library  //
//==============================//

// just a threading library we use
import XThreads

// the built-in threading library
public typealias SXThread = XThread
public typealias SXThreadPool = XThreadPool


extension SXThreadPool : SXThreadingProxy {
    public func execute(block: @escaping () -> Void) {
        self.exec(block: block)
    }
    public static var `default` = SXThreadPool(threads: 4)
}

extension SXThread : SXThreadingProxy {
    public func execute(block: @escaping () -> Void) {
        self.exec(block: block)
    }
}



#if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
//==============================//
//  GCD as threading library    //
//==============================//
    
import Dispatch
    
public struct GrandCentralDispatchQueue : SXThreadingProxy {
    
    public var queue: DispatchQueue
    
    public init(_ queue: DispatchQueue) {
        self.queue = queue
    }
    
    public func execute(block: @escaping () -> Void) {
        queue.async(execute: block)
    }
}
#endif

