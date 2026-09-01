# 🌱 carbs

A dead-simple macOS menu-bar app that shows your **net carbon output (g CO₂e)** from two sources:

1. **Device** — your Mac's electricity use × live local grid carbon intensity
2. **Models** — your personal AI model usage, auto-detected by tailing local agent transcripts (cloud models). Local models (Ollama/LM Studio) need no accounting — their energy is already inside the device watt signal.

Display-only. No optimization, no nudges, no charts. Standalone app — **not** an extension of any agent.

```text
🌱 142g
```

## Build & run

```sh
swift build                 # compile check
Scripts/bundle.sh           # produces Carbs.app (LSUIElement: menu-bar only)
open Carbs.app
```

Or run unpackaged during development: `swift run carbs` (location permission and menu-bar-only behavior require the bundled app).

## How it works

| Signal | Source | Cadence |
| --- | --- | --- |
| Device watts | IOKit `AppleSmartBattery` (Voltage × InstantAmperage). No sudo. | 60 s |
| Grid intensity | [Electricity Maps](https://api.electricitymap.org) `/v3/carbon-intensity/latest` | hourly, 6 h stale cache |
| Agent tokens | Poll-tail of `~/.pi/agent/sessions/**` (pi) and `~/.claude/projects/**` (Claude Code) with persisted byte offsets | 10 s |

**Zone resolution** (priority): manual `grid.zone` in config → CoreLocation one-shot (server resolves lat/lon to a zone) → Mac region for single-zone countries → set it manually. Location is never stored.

**Math:**

- `device_g = Σ kWh × grid_intensity(g/kWh)` — falls back to `fallback_grid_intensity_g_per_kwh` when no live data
- `model_g = tokens × wh_per_1M_tokens(model) / 1e6 × dc_intensity / 1000`
- Tokens counted: `input + output + reasoning` (+ cache tokens × `cache_token_weight`, default 0)

Model energy factors are **rough, editable placeholders** (per-token energy is an order-of-magnitude research debate, not a constant). Edit `~/.carbs/config.json`:

```json
{
  "dc_intensity_g_per_kwh": 350,
  "fallback_grid_intensity_g_per_kwh": 400,
  "cache_token_weight": 0.0,
  "grid": { "provider": "electricitymaps", "zone": "auto", "use_location": true, "token": "" },
  "model_factors_wh_per_1M_tokens": { "default": 1500, "light:*": 500, "heavy:*": 5000 }
}
```

Optional manual feed: append lines like
`{"ts":"2026-06-01T14:23:00Z","provider":"openai","model":"gpt-5.2","tokens_in":12000,"tokens_out":3400}`
to `~/.carbs/usage.jsonl` for anything without a watcher. Nothing depends on it.

Data lives in `~/.carbs/` (append-only daily JSONL, offsets, grid cache). No telemetry, no network beyond one GET/hour.

## Known limitations (v1)

- Battery-rail power undercounts when plugged in with a full battery (amperage ≈ 0)
- First sight of a transcript file skips its history (only new usage is counted)
- Browser-based chat (ChatGPT/Claude web) leaves no local trace — invisible
- Codex CLI discovery path registered, parser pending (M4)
- Agent transcript formats drift; parsers are versioned and fail safe

Roadmap: Claude/Codex parser hardening, Ollama display polish, launch-at-login, CSV export, notarized release. See `PLAN.md`.
