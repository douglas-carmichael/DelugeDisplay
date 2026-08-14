import Foundation
import OSLog

private let logger = Logger(subsystem: "com.delugedisplay", category: "RLEDecoder")

enum RLEError: Error {
    case truncatedData
}

func unpack7to8RLE(_ data: [UInt8], maxBytes: Int) throws -> ([UInt8], Int) {
    var dst = [UInt8]()
    var s = 0
    dst.reserveCapacity(maxBytes)

    // maxBytes bounds the *output*. The input scan must run to the end of the
    // packed payload: incompressible content packs larger than it unpacks (a
    // dense packet spends 6 bytes per 5 encoded), so an input scan clamped at
    // maxBytes silently truncates exactly the frames that pack worst.
    while s < data.count {
        if dst.count >= maxBytes { break }
        let first = data[s]
        s += 1
        
        if first < 64 {
            // Dense packet
            var size = 0
            var off = 0
            if first < 4 { size = 2; off = 0 }
            else if first < 12 { size = 3; off = 4 }
            else if first < 28 { size = 4; off = 12 }
            else if first < 60 { size = 5; off = 28 }
            else { continue }
            
            if s + size > data.count {
                #if DEBUG
                logger.error("Dense packet truncated")
                #endif
                throw RLEError.truncatedData
            }
            
            if dst.count + size > maxBytes {
                #if DEBUG
                logger.error("Dense packet would exceed maxBytes")
                #endif
                break
            }
            
            let highBits = first - UInt8(off)
            for j in 0..<size {
                var byte = data[s + j] & 0x7F
                if (highBits & (1 << j)) != 0 {
                    byte |= 0x80
                }
                dst.append(byte)
            }
            s += size
            
        } else {
            // RLE packet
            let marker = first - 64
            let high = (marker & 1) != 0
            var runLen = Int(marker >> 1)
            
            if runLen == 31 {
                if s >= data.count { break }
                runLen = 31 + Int(data[s])
                s += 1
            }
            
            if s >= data.count { break }
            var byte = data[s] & 0x7F
            if high {
                byte |= 0x80
            }
            s += 1
            
            runLen = min(runLen, maxBytes - dst.count)
            if runLen > 0 {
                dst.append(contentsOf: repeatElement(byte, count: runLen))
            }
        }
    }
    
    return (dst, s)
}
