
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
//  Created by Yuji on 6/2/16.
//  Copyright © 2016 yuuji. All rights reserved.
//

import Foundation
import spartanX_include

import func CKit.pointer
import func CKit.mutablePointer
#if os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
    public let UNIX_PATH_MAX = 104
#elseif os(FreeBSD) || os(Linux)
    public let UNIX_PATH_MAX = 108
#endif

public enum SXSocketAddress {
    case inet(sockaddr_in)
    case inet6(sockaddr_in6)
    case dl(sockaddr_dl)
    case unix(sockaddr_un)
    
    public var address: String {
        
        var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
        switch self {
        case var .inet(`in`):
            inet_ntop(AF_INET, pointer(of: &`in`.sin_addr) , &buffer, socklen_t(MemoryLayout<sockaddr_in>.size))
        case var .inet6(in6):
            inet_ntop(AF_INET6, pointer(of: &in6.sin6_addr) , &buffer, socklen_t(MemoryLayout<sockaddr_in6>.size))
        case var .unix(un):
            strncpy(&buffer, pointer(of: &un.sun_path).cast(to: Int8.self), Int(PATH_MAX))
        case var .dl(d):
            let s = link_ntoa(&d);
            strncpy(&buffer, s, Int(strlen(s)));
            
        default: return ""
        }
        
        return String(cString: buffer)
    }
    
    public enum Error: Swift.Error {
        case nonImplementedDomain
    }
}

public extension SXSocketAddress {
    
    
    /// port number of the address (if available) in network byte order
    public var port: in_port_t? {
        switch self {
        case let .inet(addr):
            return addr.sin_port
        case let .inet6(addr):
            return addr.sin6_port
        default:
            return nil
        }
    }
    
    public var socklen: socklen_t {
        get {
            switch self {
            case .inet6(_):
                return socklen_t(MemoryLayout<sockaddr_in6>.size)
            case .inet(_):
                return socklen_t(MemoryLayout<sockaddr_in>.size)
            case .unix(_):
                return socklen_t(MemoryLayout<sockaddr_un>.size)
            case .dl(_):
                return socklen_t(MemoryLayout<sockaddr_dl>.size)
            }
        }
    }
    
    public func sockdomain() -> SocketDomains? {
        switch self {
        case .dl:
            return .link
        case .inet:
            return .inet
        case .inet6:
            return .inet6
        case .unix:
            return .unix
//        case UInt32(MemoryLayout<sockaddr_in>.size):
//            return .inet
//        case UInt32(MemoryLayout<sockaddr_in6>.size):
//            return .inet6
//        case UInt32(MemoryLayout<sockaddr_un>.size):
//            return .unix
        default: return nil
        }
    }
}

extension sockaddr {
    
    var sxaddr: SXSocketAddress? {
        return try? SXSocketAddress(self, socklen: socklen_t(self.sa_len))
    }
    
    var inetaddr: sockaddr_in? {
        if sa_family != UInt8(AF_INET) {
            return nil
        }
        
        guard let associated = try? SXSocketAddress(self, socklen: socklen_t(MemoryLayout<sockaddr_in>.size)) else {
            return nil
        }
        
        switch associated {
        case let .inet(addr):
            return addr
        default:
            return nil // should not happen
        }
    }
    
    var inet6addr: sockaddr_in6? {
        if sa_family != UInt8(AF_INET6) {
            return nil
        }
        
        guard let associated = try? SXSocketAddress(self, socklen: socklen_t(MemoryLayout<sockaddr_in6>.size)) else {
            return nil
        }
        
        switch associated {
        case let .inet6(addr):
            return addr
        default:
            return nil // should not happen
        }
    }
}

extension sockaddr_in {
    init(port: in_port_t, addr: in_addr = in_addr(s_addr: 0)) {
        #if os(Linux)
            self = sockaddr_in(sin_family: sa_family_t(AF_INET),
                               sin_port: port,
                               sin_addr: in_addr(s_addr: 0),
                               sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        #else
            self = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
                               sin_family: sa_family_t(AF_INET),
                               sin_port: port,
                               sin_addr: in_addr(s_addr:0),
                               sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        #endif
    }
}

extension sockaddr_in6 {
    init(port: in_port_t, addr: in6_addr = in6addr_any) {
        #if os(Linux)
            self = sockaddr_in6(sin6_family: sa_family_t(AF_INET6),
                                sin6_port: port,
                                sin6_flowinfo: 0,
                                sin6_addr: addr,
                                sin6_scope_id: 0)
        #else
            self = sockaddr_in6(sin6_len: UInt8(MemoryLayout<sockaddr_in6>.size),
                                sin6_family: sa_family_t(AF_INET6),
                                sin6_port: port,
                                sin6_flowinfo: 0,
                                sin6_addr: addr,
                                sin6_scope_id: 0)
        #endif
    }
}

public extension SXSocketAddress {
    
    public init(_ addr_: sockaddr, socklen: socklen_t) throws {
        var addr = addr_
        
        switch Int32(addr.sa_family) {
        case AF_INET:
            self = .inet(mutablePointer(of: &addr).cast(to: sockaddr_in.self).pointee)
        case AF_INET6:
            self = .inet6(mutablePointer(of: &addr).cast(to: sockaddr_in6.self).pointee)
        case AF_UNIX:
            self = .unix(mutablePointer(of: &addr).cast(to: sockaddr_un.self).pointee)
        case AF_LINK:
            self = .dl(mutablePointer(of: &addr).cast(to: sockaddr_dl.self).pointee)
        default:
            throw Error.nonImplementedDomain
        }
    }
    
    public init(_ addr: UnsafePointer<sockaddr>) throws {
        switch Int32(addr.pointee.sa_family) {
        case AF_INET:
            self = .inet(addr.cast(to: sockaddr_in.self).pointee)
        case AF_INET6:
            self = .inet6(addr.cast(to: sockaddr_in6.self).pointee)
        case AF_UNIX:
            self = .unix(addr.cast(to: sockaddr_un.self).pointee)
        case AF_LINK:
            self = .dl(addr.cast(to: sockaddr_dl.self).pointee)
        default:
            throw Error.nonImplementedDomain
        }
    }
    
    public init(withDomain domain: SocketDomains, port: in_port_t) throws {
        switch domain {
        case .inet:
            self = SXSocketAddress.inet(sockaddr_in(port: port.bigEndian))
        case .inet6:
            self = SXSocketAddress.inet6(sockaddr_in6(port: port.bigEndian))
        default:
            throw Error.nonImplementedDomain
        }
    }
    
    public init?(address: String, withDomain domain: SocketDomains, port: in_port_t = 0) {
        switch domain {
            
        case .inet:
            var sockaddr = sockaddr_in(port: port.bigEndian)
            inet_pton(AF_INET,
                      address.cString(using: .ascii),
                      UnsafeMutableRawPointer(mutablePointer(of: &sockaddr.sin_addr)))
            
            self = .inet(sockaddr)
            
        case .inet6:
            var sockaddr = sockaddr_in6(port: port.bigEndian)
            inet_pton(AF_INET6,
                      address.cString(using: .ascii),
                      UnsafeMutableRawPointer(mutablePointer(of: &sockaddr.sin6_addr)))
            
            self = .inet6(sockaddr)
            
        case .unix:
            var sockaddr = sockaddr_un()
            sockaddr.sun_family = sa_family_t(AF_UNIX)
            #if !os(Linux)
                sockaddr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            #endif
            let cstr = address.cString(using: .utf8)!
            strncpy(mutablePointer(of: &(sockaddr.sun_path)).cast(to: Int8.self), cstr, UNIX_PATH_MAX)
            
            self = .unix(sockaddr)
            
        case .link:
            
            #if !os(Linux)
            var sockaddr = sockaddr_dl()
            sockaddr.sdl_family = UInt8(AF_LINK)
            sockaddr.sdl_len = UInt8(MemoryLayout<sockaddr_dl>.size)
            link_addr(address.cString(using: .ascii), &sockaddr)
            self = .dl(sockaddr)
            #else
            fallthrough
            #endif
            
        default:
            return nil
        }
    }
}
