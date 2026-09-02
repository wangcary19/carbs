// carbs — persistence: append-only daily JSONL, totals folding, CSV export data

import Foundation

struct CarbRecord: Codable {
    var ts: Date
    var source: String // "device" | "model"
    var kwh: Double?
    var tokens: Double?
    var g: Double // grams CO2e
    var detail: String?
}

struct Totals {
    var todayDevice = 0.0
    var todayModel = 0.0
    var week = 0.0
    var month = 0.0
}

/// Append-only JSONL per day under ~/.carbs/data/. Totals fold the last 30 files on read.
final class Store {
    private let dataDir: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(dataDir: URL) {
        self.dataDir = dataDir
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    private func fileURL(for day: Date) -> URL {
        dataDir.appendingPathComponent(Self.dayFmt.string(from: day) + ".jsonl")
    }

    func append(_ r: CarbRecord) {
        guard let line = try? encoder.encode(r) else { return }
        let url = fileURL(for: r.ts)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        h.seekToEndOfFile()
        h.write(line)
        h.write(Data([0x0a]))
    }

    func totals(now: Date = Date()) -> Totals {
        var t = Totals()
        let cal = Calendar.current
        let todayStr = Self.dayFmt.string(from: now)
        for i in 0..<30 {
            guard let day = cal.date(byAdding: .day, value: -i, to: now),
                  let data = try? Data(contentsOf: fileURL(for: day)) else { continue }
            for line in data.split(separator: 0x0a) where !line.isEmpty {
                guard let r = try? decoder.decode(CarbRecord.self, from: Data(line)) else { continue }
                t.month += r.g
                if i < 7 { t.week += r.g }
                if Self.dayFmt.string(from: r.ts) == todayStr {
                    if r.source == "model" { t.todayModel += r.g } else { t.todayDevice += r.g }
                }
            }
        }
        return t
    }

    /// Per-day device/model grams, oldest → newest. Used by CSV export.
    func dailyTotals() -> [(day: String, device: Double, model: Double)] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dataDir.path)
        else { return [] }
        var out: [(day: String, device: Double, model: Double)] = []
        for f in files where f.hasSuffix(".jsonl") {
            let day = String(f.dropLast(".jsonl".count))
            var dev = 0.0, mod = 0.0
            if let data = try? Data(contentsOf: dataDir.appendingPathComponent(f)) {
                for line in data.split(separator: 0x0a) where !line.isEmpty {
                    guard let r = try? decoder.decode(CarbRecord.self, from: Data(line)) else { continue }
                    if r.source == "model" { mod += r.g } else { dev += r.g }
                }
            }
            out.append((day, dev, mod))
        }
        return out.sorted { $0.day < $1.day }
    }

    /// Archives current data aside and starts fresh.
    func reset() {
        let suffix = UUID().uuidString.prefix(6)
        let archive = dataDir.deletingLastPathComponent()
            .appendingPathComponent("archive-\(Self.dayFmt.string(from: Date()))-\(suffix)")
        try? FileManager.default.moveItem(at: dataDir, to: archive)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    }
}
