import Foundation

func unpack7to8RLE(_ src: [UInt8], maxBytes: Int) throws -> ([UInt8], Int) {
    var dst = [UInt8]()
    var s = 0
    let end = min(src.count, maxBytes)
    
    while s < end {
        guard s < src.count else { break }
        let first = src[s]
        s += 1
        
        if first < 64 {
            var size = 0
            var off = 0
            if first < 4 { size = 2; off = 0 }
            else if first < 12 { size = 3; off = 4 }
            else if first < 28 { size = 4; off = 12 }
            else if first < 60 { size = 5; off = 28 }
            else { throw NSError(domain: "Unpack", code: 1) }
            
            guard s + size <= src.count else { throw NSError(domain: "Unpack", code: 2) }
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
            let marker = first - 64
            let high = (marker & 1) != 0
            var runLen = Int(marker >> 1)
            if runLen == 31 {
                guard s < src.count else { throw NSError(domain: "Unpack", code: 3) }
                runLen = 31 + Int(src[s])
                s += 1
            }
            guard s < src.count else { throw NSError(domain: "Unpack", code: 4) }
            var byte = src[s] & 0x7F
            if high {
                byte |= 0x80
            }
            s += 1
            dst.append(contentsOf: repeatElement(byte, count: runLen))
        }
    }
    return (dst, s)
}

func applyDeltaRLE(_ delta: [UInt8], to buffer: inout [UInt8]) throws {
    var s = 0
    while s + 2 <= delta.count {
        let offset = Int(delta[s]) | (Int(delta[s + 1]) << 7)
        s += 2
        
        guard offset >= 0 && offset < buffer.count else {
            continue
        }
        
        let remaining = Array(delta[s...])
        let (unpacked, used): ([UInt8], Int)
        do {
            (unpacked, used) = try unpack7to8RLE(remaining, maxBytes: min(remaining.count, buffer.count - offset))
        } catch {
            break
        }
        
        guard offset + unpacked.count <= buffer.count else {
            continue
        }
        
        for i in 0..<unpacked.count {
            buffer[offset + i] = unpacked[i]
        }
        
        s += used
    }
}
