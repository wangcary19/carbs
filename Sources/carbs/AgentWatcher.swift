// carbs — agent discovery + incremental transcript tailing (pi / claude / codex / local)

import Foundation

/// Discovers local agent installs and tails their session transcripts for token usage.
/// Poll-based (10s) with persisted byte offsets — a rescan never double-counts.
/// Parsers are per-agent and fail safe: unrecognized lines are skipped, never fatal.
final class AgentWatcher {
    struct Spec {
        let name: String
        let rootPath: String
        let parser: Parser
        let displayOnly: Bool // local models: energy already in the device watt stream
        enum Parser { case pi, claude, codex, manual, unsupported }
    }

    private let store: Store
    private let config: AppConfig
    private let offsetsURL: URL
    private let manualUsageURL: URL
    private var offsets: [String: UInt64] = [:]
    private let iso = ISO8601DateFormatter()

    private(set) var discovered: [String] = []

    private let specs: [Spec] = [
        Spec(name: "pi", rootPath: "~/.pi/agent/sessions", parser: .pi, displayOnly: false),
        Spec(name: "claude", rootPath: "~/.claude/projects", parser: .claude, displayOnly: false),
        Spec(name: "codex", rootPath: "~/.codex/sessions", parser: .codex, displayOnly: false),
        Spec(name: "ollama", rootPath: "~/.ollama/models", parser: .unsupported, displayOnly: true),
        Spec(name: "lmstudio", rootPath: "~/.lmstudio", parser: .unsupported, displayOnly: true),
    ]

    init(store: Store, config: AppConfig, offsetsURL: URL, manualUsageURL: URL) {
        self.store = store
        self.config = config
        self.offsetsURL = offsetsURL
        self.manualUsageURL = manualUsageURL
        if let data = try? Data(contentsOf: offsetsURL),
           let o = try? JSONDecoder().decode([String: UInt64].self, from: data) {
            offsets = o
        }
    }

    func poll() {
        var found: [String] = []
        for spec in specs {
            let root = NSString(string: spec.rootPath).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: root) else { continue }
            if spec.displayOnly {
                found.append("\(spec.name) (local)")
                continue
            }
            guard spec.parser != .unsupported else { continue }
            found.append(spec.name)
            scan(root: root, spec: spec)
        }
        discovered = found

        // Optional manual feed: ~/.carbs/usage.jsonl (nothing depends on it)
        if FileManager.default.fileExists(atPath: manualUsageURL.path) {
            consumeFile(path: manualUsageURL.path, agent: "manual", parser: .manual)
        }
        saveOffsets()
    }

    private func scan(root: String, spec: Spec) {
        guard let en = FileManager.default.enumerator(atPath: root) else { return }
        for case let rel as String in en where rel.hasSuffix(".jsonl") {
            consumeFile(path: (root as NSString).appendingPathComponent(rel),
                        agent: spec.name, parser: spec.parser)
        }
    }

    private func consumeFile(path: String, agent: String, parser: Spec.Parser) {
        guard let h = FileHandle(forReadingAtPath: path) else { return }
        defer { try? h.close() }
        let size = h.seekToEndOfFile()

        let start: UInt64
        if let known = offsets[path] {
            start = known > size ? 0 : known // truncated/rotated → re-read from scratch
        } else {
            offsets[path] = size // first sight: skip pre-install history
            return
        }
        guard size > start else { return }

        h.seek(toFileOffset: start)
        let data = h.readDataToEndOfFile()
        var lines = data.split(separator: 0x0a, omittingEmptySubsequences: false)
        var endOffset = size
        if data.last != 0x0a, let last = lines.last { // partial line → next poll
            endOffset = size - UInt64(last.count)
            lines.removeLast()
        }
        for line in lines where !line.isEmpty {
            parseLine(Data(line), agent: agent, parser: parser)
        }
        offsets[path] = endOffset
    }

    private func parseLine(_ data: Data, agent: String, parser: Spec.Parser) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let u = extractUsage(obj, agent: agent, parser: parser),
              u.tokens > 0 else { return }
        let wh = u.tokens / 1_000_000.0 * config.factorWhPer1MTokens(for: u.model)
        let g = wh * config.dcIntensity / 1000.0
        store.append(CarbRecord(ts: u.ts, source: "model", tokens: u.tokens, g: g,
                                detail: "\(agent)/\(u.model)"))
    }

    struct Usage { let tokens: Double; let model: String; let ts: Date }

    /// Routes one transcript line to the per-agent extractor. nil = not a usage line.
    private func extractUsage(_ obj: [String: Any], agent: String, parser: Spec.Parser) -> Usage? {
        switch parser {
        case .pi: return extractPi(obj, agent: agent)
        case .claude: return extractClaude(obj, agent: agent)
        case .codex: return extractCodex(obj, agent: agent)
        case .manual: return extractManual(obj, agent: agent)
        case .unsupported: return nil
        }
    }

    private func ts(_ any: Any?) -> Date {
        if let s = any as? String, let d = iso.date(from: s) { return d }
        return Date()
    }

    // verified on this machine: {type, id, timestamp, message:{usage:{input,output,reasoning,cacheRead,cacheWrite}}}
    private func extractPi(_ obj: [String: Any], agent: String) -> Usage? {
        guard let msg = obj["message"] as? [String: Any],
              let u = msg["usage"] as? [String: Any] else { return nil }
        let input = (u["input"] as? NSNumber)?.doubleValue ?? 0
        let output = (u["output"] as? NSNumber)?.doubleValue ?? 0
        let reasoning = (u["reasoning"] as? NSNumber)?.doubleValue ?? 0
        let cacheR = (u["cacheRead"] as? NSNumber)?.doubleValue ?? 0
        let cacheW = (u["cacheWrite"] as? NSNumber)?.doubleValue ?? 0
        let tokens = input + output + reasoning + config.cacheTokenWeight * (cacheR + cacheW)
        return Usage(tokens: tokens, model: (msg["model"] as? String) ?? agent, ts: ts(obj["timestamp"]))
    }

    // {message:{usage:{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}}}
    private func extractClaude(_ obj: [String: Any], agent: String) -> Usage? {
        guard let msg = obj["message"] as? [String: Any],
              let u = msg["usage"] as? [String: Any] else { return nil }
        let input = (u["input_tokens"] as? NSNumber)?.doubleValue ?? 0
        let output = (u["output_tokens"] as? NSNumber)?.doubleValue ?? 0
        let cacheR = (u["cache_read_input_tokens"] as? NSNumber)?.doubleValue ?? 0
        let cacheW = (u["cache_creation_input_tokens"] as? NSNumber)?.doubleValue ?? 0
        let tokens = input + output + config.cacheTokenWeight * (cacheR + cacheW)
        return Usage(tokens: tokens, model: (msg["model"] as? String) ?? agent, ts: ts(obj["timestamp"]))
    }

    // Codex CLI rollout files: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
    // Format per public docs (unverified locally — codex not installed on the dev machine).
    // {"type":"event_msg","payload":{"type":"token_count","info":{
    //   "total_token_usage":{...cumulative...},
    //   "last_token_usage":{"input_tokens":N,"cached_input_tokens":N,
    //     "output_tokens":N,"reasoning_output_tokens":N,"total_tokens":N}}}}
    // Uses last_token_usage deltas — matches our incremental tail-with-offset model.
    private func extractCodex(_ obj: [String: Any], agent: String) -> Usage? {
        guard let payload = obj["payload"] as? [String: Any],
              (payload["type"] as? String) == "token_count",
              let info = payload["info"] as? [String: Any],
              let last = info["last_token_usage"] as? [String: Any] else { return nil }
        let input = (last["input_tokens"] as? NSNumber)?.doubleValue ?? 0
        let output = (last["output_tokens"] as? NSNumber)?.doubleValue ?? 0
        let reasoning = (last["reasoning_output_tokens"] as? NSNumber)?.doubleValue ?? 0
        let cached = (last["cached_input_tokens"] as? NSNumber)?.doubleValue ?? 0
        let tokens = input + output + reasoning + config.cacheTokenWeight * cached
        // turn_context lines carry the model id but are skipped on first sight
        return Usage(tokens: tokens, model: agent, ts: ts(obj["timestamp"]))
    }

    // {"ts": "...", "provider": "...", "model": "...", "tokens_in": N, "tokens_out": N}
    private func extractManual(_ obj: [String: Any], agent: String) -> Usage? {
        guard let tin = (obj["tokens_in"] as? NSNumber)?.doubleValue,
              let tout = (obj["tokens_out"] as? NSNumber)?.doubleValue else { return nil }
        return Usage(tokens: tin + tout, model: (obj["model"] as? String) ?? agent, ts: ts(obj["ts"]))
    }

    private func saveOffsets() {
        try? JSONEncoder().encode(offsets).write(to: offsetsURL)
    }
}
