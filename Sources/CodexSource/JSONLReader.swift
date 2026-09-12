import Foundation

struct JSONLCursor: Codable {
    var offset: UInt64 = 0
    var line: Int = 0
}

struct JSONLProgress {
    let cursor: JSONLCursor
    let partialTail: Bool
}

struct JSONLReader {
    let maximumLineBytes = 16 * 1_024 * 1_024

    func read(_ source: RolloutFile, from initial: JSONLCursor,
              consume: (Data?, Int) throws -> Void) throws -> JSONLProgress {
        try source.handle.seek(toOffset: initial.offset)
        var cursor = initial
        var position = initial.offset
        var pending = Data()
        var oversized = false
        while position < source.version.size {
            let chunk = try source.read(upToCount: Int(min(source.version.size - position, 64 * 1_024)))
            var start = chunk.startIndex
            for end in chunk.indices where chunk[end] == 10 {
                if !oversized { pending.append(chunk[start..<end]) }
                cursor.line += 1
                cursor.offset = position + UInt64(chunk.distance(from: chunk.startIndex, to: end)) + 1
                try consume(oversized || pending.count > maximumLineBytes ? nil : pending, cursor.line)
                pending.removeAll(keepingCapacity: true)
                oversized = false
                start = chunk.index(after: end)
            }
            if !oversized {
                pending.append(chunk[start...])
                if pending.count > maximumLineBytes {
                    oversized = true
                    pending.removeAll(keepingCapacity: true)
                }
            }
            position += UInt64(chunk.count)
        }
        return JSONLProgress(cursor: cursor, partialTail: oversized || !pending.isEmpty)
    }
}
