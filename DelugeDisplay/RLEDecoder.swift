import Foundation

func unpack7to8RLE(_ src: [UInt8], maxBytes: Int) throws -> ([UInt8], Int) {
    var dst = [UInt8]()
    var s = 0
    let end = min(src.count, maxBytes)
    dst.reserveCapacity(end * 2)
    
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
            else { continue }
            
            // Validate size bounds
            if s + size > src.count {
                print("Dense packet truncated")
                break
            }
            
            // Validate destination capacity
            if dst.count + size > maxBytes {
                print("Dense packet would exceed maxBytes")
                break
            }
            
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
            
            // Validate run length
            runLen = min(runLen, 256)
            
            // Validate destination capacity
            if dst.count + runLen > maxBytes {
                print("RLE packet would exceed maxBytes")
                runLen = maxBytes - dst.count
            }
            
            if runLen > 0 {
                dst.append(contentsOf: repeatElement(byte, count: runLen))
            }
        }
    }
    
    return (dst, s)
}

func applyDeltaRLE(_ delta: [UInt8], to buffer: inout [UInt8]) throws {
    let frameSize = buffer.count
    var s = 0
    
    while s + 2 <= delta.count {
        // Extract 14-bit offset value (7 bits from each byte)
        let lowByte = delta[s] & 0x7F
        let highByte = delta[s + 1] & 0x7F
        let offset = Int(lowByte) | (Int(highByte) << 7)
        s += 2
        
        // Strict offset validation
        if offset >= frameSize {
            print("Invalid delta offset: \(offset), max: \(frameSize)")
            // Skip this update but continue processing
            // Find next potential valid marker
            while s < delta.count && (delta[s] & 0x80) == 0 {
                s += 1
            }
            continue
        }
        
        let remaining = Array(delta[s...])
        if remaining.isEmpty { break }
        
        do {
            let (unpacked, used) = try unpack7to8RLE(remaining, maxBytes: min(128, frameSize - offset))
            if !unpacked.isEmpty {
                // Double check bounds before applying
                let updateLength = min(unpacked.count, frameSize - offset)
                buffer.replaceSubrange(offset..<(offset + updateLength), with: unpacked.prefix(updateLength))
            }
            s += used
        } catch {
            // Skip to next potential update on error
            print("Delta decode error at offset \(offset)")
            s += 1
            continue
        }
    }
}
