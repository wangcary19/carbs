// carbs — app state: sampling timers, device/model streams, totals, menu actions

import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CarbsModel: ObservableObject {
    @Published var menuBarTitle = "🌱 –"
    @Published var todayDevice = 0.0
    @Published var todayModel = 0.0
    @Published var week = 0.0
    @Published var month = 0.0
    @Published var zoneLabel = "grid: resolving…"
    @Published var watchersLabel = "agents: none detected"
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var menuBarIcon = AppConfig.defaultMenuBarIcon

    let paths = CarbsPaths()
    var config: AppConfig
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
        menuBarIcon = c.menuBarIcon
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
        let g = Int((t.todayDevice + t.todayModel).rounded())
        menuBarTitle = menuBarIcon.isEmpty ? "\(g)g" : "\(menuBarIcon) \(g)g"
    }

    // MARK: menu actions

    func openConfig() {
        NSWorkspace.shared.open(paths.root)
    }

    /// Persists a custom menu-bar prefix; an empty string shows grams only.
    func setMenuBarIcon(_ s: String) {
        let icon = s.trimmingCharacters(in: .whitespacesAndNewlines)
        menuBarIcon = icon
        config.menuBarIcon = icon
        ConfigStore.save(config, paths: paths)
        refreshTotals()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Fails when not running from an .app bundle (e.g. `swift run`) — state reverts below
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func exportCSV() {
        var csv = "day,device_g,model_g,total_g\n"
        for r in store.dailyTotals() {
            csv += String(format: "%@,%.3f,%.3f,%.3f\n", r.day, r.device, r.model, r.device + r.model)
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "carbs-export.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    func resetTotals() {
        store.reset()
        refreshTotals()
    }
}
