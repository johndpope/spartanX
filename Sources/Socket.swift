
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
//  Created by Yuji on 9/24/16.
//  Copyright © 2016 yuuji. All rights reserved.
//

import struct Foundation.Data
import CKit

public protocol Socket : FileDescriptorRepresentable {
    var sockfd: Int32 { get }
    var domain: SocketDomains { get set }
    var type: SocketTypes { get set }
    var `protocol`: Int32 { get set }
    func getfd() -> Int32
}

public protocol ServerSocket : Socket, Addressable {
    func accept() throws -> ClientSocket
}

public protocol ClientSocket : Socket, Readable, Writable {
    /* storing address */
    var address: SXSocketAddress? { get set }
}

public protocol OutgoingSocket : Socket, Addressable, Readable, Writable {
    
}

extension Socket {

    public func getfd() -> Int32 {
        return self.sockfd
    }
    
    public var fileDescriptor: Int32 {
        return self.sockfd
    }
    
    public func setBlockingMode(block: Bool) {
        let sockflags = fcntl(self.sockfd, F_GETFL, 0)
        _ = fcntl(self.sockfd, F_SETFL, block ? sockflags ^ O_NONBLOCK : sockflags | O_NONBLOCK)
    }
    
    public func setTimeoutInterval(_ time: timeval) {
        var time = time
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
    }
    
    public var isBlocking: Bool {
        return ((fcntl(self.sockfd, F_GETFL, 0) & O_NONBLOCK) == 0)
    }
}

extension Readable where Self : Socket {
    
    
    /// Receive from a blocking socket
    ///
    /// - Parameters:
    ///   - size: how many bytes to receive
    ///   - r_flags: flag for recv() syscall
    /// - Returns: the data, nil if no data available from the socket
    /// - Throws: When error occurs from system calls, the same error will throw
    func recv_block(size: Int, r_flags: Int32 = 0) throws -> Data? {
        
        var buffer = [UInt8](repeating: 0, count: size)
        var len = 0
        
        len = recv(self.sockfd, &buffer, size, r_flags)
        
        if len == 0 {
            return nil
        }
        
        if len == -1 {
            throw SocketError.recv(String.errno)
        }
        
        return Data(bytes: buffer, count: len)
    }
    
    
    /// Receive from a non-blocking socket
    ///
    /// - Parameters:
    ///   - size: how many bytes to receive
    ///   - r_flags: flag for recv() syscall
    /// - Returns: the data, nil if no data is available from the socket
    /// - Throws: When error occurs from system calls, the same error will throw
    func recv_nonblock(size: Int, r_flags: Int32 = 0) throws -> Data? {
        
        // our buffer to store data
        var buffer = [UInt8](repeating: 0, count: size)
        
        // to store how many bytes the current cycle receved
        var len = 0
        
        // the total number of bytes
        var total = 0
        
        recv_loop: while true {
            
            // a small buffer to save the current amount of bytes to receive
            var smallbuffer = [UInt8](repeating: 0, count: size)
            
            len = recv(sockfd, &smallbuffer, size, r_flags)
            
            // if no data in the socket
            if len == 0 {
                return nil
            }
            
            let dataAvailable = len > 0
            
            // if there are some bytes available from the scoket
            if dataAvailable {
                // read it to the buffer
                buffer.append(contentsOf: smallbuffer)
                // count the number of bytes read
                total += len
            } else {
                
                // it can be no more data available, or error occurs
                switch errno {
                    
                // no more bytes available, break the loop
                case EAGAIN, EWOULDBLOCK:
                    break recv_loop
                    
                // some error occurs when calling the system call, throw the error
                default:
                    throw SocketError.recv(String.errno)
                }
            }
        }
        
        return Data(bytes: buffer, count: total)
    }
}

extension Writable where Self : Socket {
    
    public func write(data: Data, flags: Int32 = 0) throws {
        if send(self.sockfd, data.bytes, data.length, flags) == -1 {
            throw SocketError.send(String.errno)
        }
    }
    
    public func write(file fd: Int32, header: Data) throws {
        #if os(FreeBSD) || os(OSX) || os(iOS) || os(tvOS) || os(watchOS)
        var header = header
        var hdvec = header.withUnsafeMutableBytes {
            return iovec(iov_base: $0, iov_len: header.length)
        }

        var _sf_hdtr = sf_hdtr(headers: &hdvec, hdr_cnt: 1, trailers: nil, trl_cnt: 0)
            
        if sendfile(fd, self.sockfd, 0, nil, &_sf_hdtr, 0) == -1 {
            print(String.errno)
            throw SocketError.sendfile(String.errno)
        }
            
        #else
        var yes: Int32 = 1
        setsockopt(sockfd, SOL_SOCKET, TCP_CORK, &yes, socklen_t(MemoryLayout<Int32>.size))
        yes = 0
        try self.write(data: header)
        sendfile(sockfd, fd, nil, try! FileStatus(fd: fd).size)
        setsockopt(sockfd, SOL_SOCKET, TCP_CORK, &yes, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }
    
    public func write(to sockfd: Int32, file fd: Int32, header: Data) throws {
        #if os(FreeBSD) || os(OSX) || os(iOS) || os(tvOS) || os(watchOS)
            var header = header
            var hdvec = header.withUnsafeMutableBytes {
                return iovec(iov_base: $0, iov_len: header.length)
            }
            
            var _sf_hdtr = sf_hdtr(headers: &hdvec, hdr_cnt: 1, trailers: nil, trl_cnt: 0)
            
            if sendfile(fd, sockfd, 0, nil, &_sf_hdtr, 0) == -1 {
                print(String.errno)
                throw SocketError.sendfile(String.errno)
            }
            
        #else
            var yes: Int32 = 1
            setsockopt(sockfd, SOL_SOCKET, TCP_CORK, &yes, socklen_t(MemoryLayout<Int32>.size))
            yes = 0
            try self.write(data: header)
            sendfile(sockfd, fd, nil, try! FileStatus(fd: fd).size)
            setsockopt(sockfd, SOL_SOCKET, TCP_CORK, &yes, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }
}

extension KqueueManagable where Self : Socket {
    public var ident: Int32 {
        return sockfd
    }
}
