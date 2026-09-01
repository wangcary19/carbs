# carbs — Plan

A dead-simple, self-contained macOS menu-bar app that shows your **net carbon output (g CO₂e)** from two sources:

1. **Device** — your Mac's electricity use × live local grid carbon intensity
2. **Models** — your personal AI model usage, **auto-detected** by discovering local agent installations and tailing their usage transcripts (cloud models), with local-model inference already inside the device watt signal

Display-only. No optimization, no scheduling, no nudges. **Not an extension of any agent** — a standalone app that works even if no agent is installed. v1 scope is frozen at the above.

---

## 1. UX

- Menu bar item: `🌱 142g` (today's running total)
- Click → dropdown:
  - Today: total g CO₂e
  - Breakdown: `Device 96g · Models 46g`
  - Grid now: `238 g/kWh (CA-ON · auto)` — shows zone + how it was resolved (auto/manual/stale)
  - Watchers: `pi ✓ · ollama ✓ (local)` — which agents were discovered and are being tailed
  - This week / this month totals
  - Quit, Reset totals, Open config folder
- Nothing else. No charts in v1.

## 2. The math (all of it)

```text
device_co2e(g)  = Σ [ watts(t) × Δt(h) / 1000 ] × grid_intensity(t)     # g/kWh
model_co2e(g)   = Σ [ tokens × wh_per_1M_tokens(model) / 1e6 ] × dc_intensity
total           = device_co2e + model_co2e
```

- `grid_intensity(t)` — live, hourly, from Electricity Maps; fallback to last cached value, then to a static annual-average for the resolved zone (flagged "stale")
- `dc_intensity` — datacenter carbon intensity; single configurable constant (default ~350 g/kWh)
- `wh_per_1M_tokens` — per-model-class factors in an editable config file (§6)
- **Token counting rule (v1):** count `input + output + reasoning`. Cache-read/write tokens are counted at 0% by default (config flag `cache_token_weight`, e.g. 0.1, since cache reads still cost memory-bandwidth energy). Never double-count: local-model inference is excluded from token accounting because it is already in the device watt stream.

## 3. Grid zone resolution (priority order)

| Priority | Method | Detail |
| --- | --- | --- |
| 1 | **Manual override** | `config.json: grid.zone = "US-CAL-CISO"` — always wins, no location permission needed |
| 2 | **GPS one-shot** | CoreLocation single fix at launch (and on wake/network change) → Electricity Maps carbon-intensity endpoint accepts `lat`/`lon` and resolves the zone server-side → cache the resolved zone. Requires location permission prompt (one-time); decline → falls through |
| 3 | **Mac region settings** | `Locale.regionCode` → country-level zone where one exists (`DE`, `FR`, `GB`…); for multi-zone countries (US, CA, AU) country-level is too coarse → fall through |
| 4 | **Ask once** | First-run dropdown lists Electricity Maps zones; user picks; stored as manual override |

Electricity Maps free personal tier: one zone, hourly. UK alternative: carbonintensity.org.uk, no key needed.

## 4. Model usage: auto-discovery + tailing (the core of v1)

Two distinct kinds of "installed models," handled differently:

- **Local models** (Ollama `~/.ollama/models`, LM Studio `~/.lmstudio`): detected for display, but **no token accounting** — their energy is already measured in the device watt stream. This avoids double counting by construction.
- **Cloud agents** (CLI tools that call remote APIs): discovered by probing well-known paths, then their session transcripts are **tailed incrementally** (FSEvents + file-offset bookkeeping) and token usage is extracted per message.

### Watcher registry (`watchers.json`, user-extensible)

| Agent | Discovery path (verified) | Transcript format | Usage fields |
| --- | --- | --- | --- |
| **pi** | `~/.pi/agent/sessions/<encoded-cwd>/*.jsonl` | one JSON/line: `{type, id, timestamp, message}` | `message.usage.{input, output, reasoning, cacheRead, cacheWrite}` ✅ verified on this machine |
| **Claude Code** | `~/.claude/projects/<dir>/*.jsonl` | one JSON/line | `message.usage.{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}` (field names per public docs; parser versioned, verify on first detect) |
| **Codex CLI** | `~/.codex/sessions/**/*.jsonl` | one JSON/line, `token_count` events | verify on first detect |
| **Ollama / LM Studio** | model dirs above | — | display-only (local, in watt stream) |

Rules:

- Parsers are **versioned per agent**; unrecognized lines are skipped, parse failures log and degrade — never crash the meter.
- **Dedupe** via `{file, byte-offset}` persistence; a rescan never double-counts.
- New-agent detection: re-probe discovery paths on wake + every 15 min; a new path appearing activates its watcher automatically.
- **`usage.jsonl` manual feed is kept** (`~/.carbs/usage.jsonl`) as an optional escape hatch for anything without a watcher — but nothing in v1 depends on it, and no agent extension is required.

## 5. Architecture (6 small components, one process)

```text
┌────────────────────────── carbs (Swift, MenuBarExtra) ──┐
│ PowerSampler ──┐                                             │
│ ZoneResolver ──┤                                             │
│ GridClient ────┼──> Store (JSONL daily files) ──> MenuBarUI  │
│ AgentWatcher ──┤         ~/.carbs/data/                  │
│ Config: ~/.carbs/{config, factors, watchers}.json        │
└──────────────────────────────────────────────────────────────┘
```

- **PowerSampler** — `pmset -g batt` / `pmset -g ac` every 60s, integrate watts → Wh. ~40 lines.
- **ZoneResolver** — priority chain from §3; CoreLocation one-shot; caches resolved zone. ~80 lines.
- **GridClient** — hourly fetch, 6h cache, stale flag. ~60 lines.
- **AgentWatcher** — discovery prober + FSEvents tailer + per-agent parser registry. ~200 lines, the biggest piece.
- **Store** — append-only JSONL per day (`{ts, source, kwh_or_tokens, gco2e}`); totals folded on read. KB/day — no SQLite in v1.
- **MenuBarUI** — SwiftUI `MenuBarExtra`, 10s refresh from in-memory totals.

**Stack:** native Swift (SwiftUI `MenuBarExtra`) — no runtime deps, ~2MB, a carbon meter should sip power itself. Direct distribution (signed/notarized), not App Store — location + file access outside sandbox is simpler. (Fallback if Swift is a blocker: Python + `rumps` prototype, at the cost of a resident Python runtime.)

## 6. Config (`~/.carbs/factors.json`, user-editable)

```json
{
  "dc_intensity_g_per_kwh": 350,
  "cache_token_weight": 0.0,
  "grid": { "provider": "electricitymaps", "zone": "auto", "use_location": true, "token": "..." },
  "model_factors_wh_per_1M_tokens": {
    "default":  1500,
    "light:*":  500,
    "heavy:*":  5000
  }
}
```

Model factors are **rough placeholders by design** — per-token energy is an active research debate (order-of-magnitude, not precision). Three editable classes (light chat / standard / heavy-reasoning) beat fake precision. Seed from Epoch AI per-query estimates and provider disclosures as they appear.

## 7. Sanity-check numbers (why both streams matter)

- MacBook at 10–20W × 10h on a 400 g/kWh grid ≈ **40–80 g/day**
- Heavy agent day (5M standard tokens) ≈ 7.5 Wh → **~2.6 g/day** at defaults; a heavy *reasoning-model* day can be 10× that (pi transcripts expose `reasoning` separately — handy)
- Local model inference: inside the device number — no double counting, by construction

## 8. Milestones

| # | Deliverable | Done when |
| --- | --- | --- |
| M1 | Menu-bar scaffold + PowerSampler + Store | Total Wh today survives app restart |
| M2 | ZoneResolver + GridClient + CO₂ conversion | Menu bar shows g CO₂e with resolved zone labeled (auto/manual/stale); offline works |
| M3 | AgentWatcher (pi parser first — format verified) + breakdown UI | Running a pi session moves the "Models" number within 10s; restart doesn't double-count |
| M4 | Claude Code + Codex parsers; Ollama detection display | Watchers row shows all detected agents |
| M5 | Polish | Launch-at-login, reset, export CSV, signed/notarized binary |

Risks are low: `pmset` parsing, hourly API caching, FSEvents tailing. No sudo, no kernel APIs, network = one GET/hour.

## 9. Honest limitations (v2 candidates, explicitly out of v1)

- **Transcript format drift** — agent vendors change formats without notice; parsers are versioned and fail safe, but breakage is a matter of when, not if
- **Invisible usage** — browser-based chat (ChatGPT/Claude web) leaves no local trace; only CLI/local agents are seen
- Cache-token energy weight is a guess; default 0% until better data exists
- Location permission prompt may annoy some users → manual zone always available
- Per-process device attribution (powermetrics needs sudo) — v2
- Embodied/hardware emissions (Boavizta) — v2
- PUE/water folded into the single dc_intensity constant
- Windows/Linux ports (Scaphandre on Linux) — v2
- Historical charts, carbon-aware nudges — rejected by scope, on purpose
