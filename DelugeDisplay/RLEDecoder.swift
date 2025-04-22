import Foundation

func unpack7to8RLE(_ src: [UInt8], maxBytes: Int) throws -> ([UInt8], Int) {
    var dst = [UInt8]()
    var s = 0
    let end = min(src.count, maxBytes)
    dst.reserveCapacity(end * 2) // Pre-allocate space for efficiency
    
    while s < end {
        guard s < src.count else { break }
        let first = src[s]
        s += 1
        
        if first < 64 {
            // Dense packet
            var size = 0
            var off = 0
            if first < 4 { size = 2; off = 0 }
            else if first < 12 { size = 3; off = 4 }
            else if first < 28 { size = 4; off = 12 }
            else if first < 60 { size = 5; off = 28 }
            else { continue } // Skip invalid marker
            
            if s + size > src.count { break }
            
            let highBits = first - UInt8(off)
            for j in 0..<size {
                var byte = src[s + j] & 0x7F
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
                if s >= src.count { break }
                runLen = 31 + Int(src[s])
                s += 1
            }
            
            if s >= src.count { break }
            var byte = src[s] & 0x7F
            if high {
                byte |= 0x80
            }
            s += 1
            
            // Limit maximum run length for safety
            runLen = min(runLen, 256)
            dst.append(contentsOf: repeatElement(byte, count: runLen))
        }
    }
    
    return (dst, s)
}

func applyDeltaRLE(_ delta: [UInt8], to buffer: inout [UInt8]) throws {
    let frameSize = 128 * 6 // Fixed frame size for Deluge display
    var s = 0
    
    while s + 2 <= delta.count {
        let offset = Int(delta[s]) | (Int(delta[s + 1]) << 7)
        s += 2
        
        // Validate offset
        guard offset < frameSize else { continue }
        
        let remaining = Array(delta[s...])
        guard !remaining.isEmpty else { break }
        
        do {
            let (unpacked, used) = try unpack7to8RLE(remaining, maxBytes: frameSize - offset)
            guard !unpacked.isEmpty else { continue }
            
            // Ensure we don't write past buffer bounds
            let updateLength = min(unpacked.count, frameSize - offset)
            buffer.replaceSubrange(offset..<(offset + updateLength), with: unpacked.prefix(updateLength))
            
            s += used
        } catch {
            // Skip to next potential update on error
            s += 1
            continue
        }
    }
}
