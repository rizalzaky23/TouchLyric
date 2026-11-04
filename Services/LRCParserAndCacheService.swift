import Foundation

final class LRCParserAndCacheService {
    private let cacheFolder: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheFolder = caches.appendingPathComponent("TouchLyricLRC", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true, attributes: nil)
    }

    func lyricLines(for track: SpotifyTrack) async throws -> [LyricLine] {
        if let cached = try? loadFromCache(trackID: track.id) {
            return cached
        }
        let fetched = try await fetchFromLRCLib(track: track)
        try saveToCache(trackID: track.id, lines: fetched)
        return fetched
    }

    private func cacheURL(for trackID: String) -> URL {
        let safe = trackID.replacingOccurrences(of: ":", with: "_")
        return cacheFolder.appendingPathComponent("\(safe).lrc")
    }

    private func loadFromCache(trackID: String) throws -> [LyricLine] {
        let url = cacheURL(for: trackID)
        let data = try Data(contentsOf: url)
        let raw = String(decoding: data, as: UTF8.self)
        return parseLRC(raw)
    }

    private func saveToCache(trackID: String, lines: [LyricLine]) throws {
        let url = cacheURL(for: trackID)
        let lrc = lines.map { line in
            let min = Int(line.time / 60)
            let sec = line.time.truncatingRemainder(dividingBy: 60)
            return String(format: "[%02d:%05.2f] %@", min, sec, line.text)
        }.joined(separator: "\n")
        try lrc.write(to: url, atomically: true, encoding: .utf8)
    }

    private func fetchFromLRCLib(track: SpotifyTrack) async throws -> [LyricLine] {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "duration", value: String(Int(track.duration)))
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard let lrc = json["syncedLyrics"] as? String else {
            throw NSError(domain: "LRC", code: 1, userInfo: [NSLocalizedDescriptionKey: "No lyrics"])
        }
        return parseLRC(lrc)
    }

    private func parseLRC(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let regex = try! NSRegularExpression(pattern: #"\[(\d{2}):(\d{2}\.\d{2})\]\s*(.*)"#, options: [])
        raw.enumerateLines { line, _ in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, options: [], range: range),
               let minR = Range(match.range(at: 1), in: line),
               let secR = Range(match.range(at: 2), in: line),
               let txtR = Range(match.range(at: 3), in: line) {
                let min = Double(line[minR]) ?? 0
                let sec = Double(line[secR]) ?? 0
                let time = min * 60 + sec
                let txt = String(line[txtR])
                lines.append(LyricLine(time: time, text: txt))
            }
        }
        return lines.sorted()
    }
}
