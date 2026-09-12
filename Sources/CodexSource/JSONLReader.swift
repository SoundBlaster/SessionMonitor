import Foundation

struct JSONLReader {
    let maximumLineBytes = 16 * 1_024 * 1_024

    func read(_ url: URL, consume: (Data?, Int) throws -> Void) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var pending = Data()
        var line = 0
        var oversized = false
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            var start = chunk.startIndex
            for end in chunk.indices where chunk[end] == 10 {
                if !oversized { pending.append(chunk[start..<end]) }
                line += 1
                try consume(oversized || pending.count > maximumLineBytes ? nil : pending, line)
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
        }
        return oversized || !pending.isEmpty
    }
}
