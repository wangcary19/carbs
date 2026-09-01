import AppKit
import Foundation
import SwiftUI

@MainActor
final class CarbsModel: ObservableObject {
    @Published var menuBarTitle = "🌱 –"
    @Published var todayDevice = 0.0
    @Published var todayModel = 0.0
    @Published var week = 0.0
    @Published var month = 0.0
    @Published var zoneLabel = "grid: resolving…"
    @Published var watchersLabel = "agents: none detected"

    let paths = CarbsPaths()
    let config: AppConfig
    private let store: Store
    private let grid: GridClient
    private let zoneResolver: ZoneResolver
    private let watcher: AgentWatcher

    private var started = false
    private var lastPowerAt = Date()
    private var resolution: ZoneResolution?
    private var resolving = false

    init() {
        let c = ConfigStore.loadOrCreate(paths: paths)
        config = c
        store = Store(dataDir: paths.data)
        grid = GridClient(cacheURL: paths.gridCacheFile, token: c.grid.token)
        zoneResolver = ZoneResolver(config: c)
        watcher = AgentWatcher(store: store, config: c,
                               offsetsURL: paths.offsetsFile,
                               manualUsageURL: paths.manualUsageFile)
    }

    func start() {
        guard !started else { return }
        started = true
        lastPowerAt = Date()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.samplePower() }
        }.fire()
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }.fire()
    }

    // MARK: device stream

    private func samplePower() {
        let now = Date()
        let dt = now.timeIntervalSince(lastPowerAt)
        lastPowerAt = now
        guard dt > 1, dt < 3600,
              let s = PowerSampler.currentWatts(), s.watts > 0.01 else { return }
        let kwh = s.watts * dt / 3_600_000.0
        let intensity = grid.intensity ?? config.fallbackGridIntensity
        store.append(CarbRecord(ts: now, source: "device", kwh: kwh,
                                g: kwh * intensity, detail: s.source))
        refreshTotals()
    }

    // MARK: model stream + grid

    private func tick() {
        watcher.poll()
        watchersLabel = watcher.discovered.isEmpty
            ? "agents: none detected"
            : "agents: " + watcher.discovered.joined(separator: " · ")

        if resolution == nil {
            guard !resolving else { return }
            resolving = true
            zoneResolver.resolve { [weak self] res in
                Task { @MainActor in
                    guard let self else { return }
                    self.resolution = res
                    self.resolving = false
                    await self.refreshGrid(force: true)
                }
            }
        } else {
            Task { await refreshGrid(force: false) }
        }
        refreshTotals()
    }

    private func refreshGrid(force: Bool) async {
        guard force || grid.needsRefresh else {
            updateZoneLabel()
            return
        }
        var lat: Double?, lon: Double?, explicit: String?
        switch resolution {
        case .zone(let z, _): explicit = z
        case .coords(let la, let lo, _): lat = la; lon = lo
        default: break
        }
        await grid.refresh(zone: explicit, lat: lat, lon: lon)
        updateZoneLabel()
    }

    private func updateZoneLabel() {
        let method: String
        switch resolution {
        case .zone(_, let m): method = " · " + m
        case .coords(_, _, let m): method = " · " + m
        default: method = ""
        }
        if let z = grid.zone, let i = grid.intensity {
            zoneLabel = "grid: \(Int(i)) g/kWh (\(z)\(method))\(grid.stale ? " · stale" : "")"
        } else if config.grid.token.isEmpty {
            zoneLabel = "grid: add Electricity Maps token in config.json"
        } else {
            zoneLabel = "grid: unresolved — set zone in config.json"
        }
    }

    private func refreshTotals() {
        let t = store.totals()
        todayDevice = t.todayDevice
        todayModel = t.todayModel
        week = t.week
        month = t.month
        menuBarTitle = "🌱 \(Int((t.todayDevice + t.todayModel).rounded()))g"
    }

    // MARK: menu actions

    func openConfig() {
        NSWorkspace.shared.open(paths.root)
    }

    func resetTotals() {
        store.reset()
        refreshTotals()
    }
}
