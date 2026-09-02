// carbs — paths, config schema, energy factors, config persistence

import Foundation

struct CarbsPaths {
    let root: URL
    var data: URL { root.appendingPathComponent("data") }
    var configFile: URL { root.appendingPathComponent("config.json") }
    var gridCacheFile: URL { root.appendingPathComponent("grid-cache.json") }
    var offsetsFile: URL { root.appendingPathComponent("offsets.json") }
    var manualUsageFile: URL { root.appendingPathComponent("usage.jsonl") }

    init() {
        root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".carbs")
        try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        // Usage data and (legacy) tokens live here — owner-only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
}

struct GridConfig: Codable {
    var provider: String
    var zone: String
    var useLocation: Bool
    var token: String

    enum CodingKeys: String, CodingKey {
        case provider, zone, token
        case useLocation = "use_location"
    }

    init(provider: String = "electricitymaps", zone: String = "auto",
         useLocation: Bool = true, token: String = "") {
        self.provider = provider
        self.zone = zone
        self.useLocation = useLocation
        self.token = token
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "electricitymaps"
        zone = try c.decodeIfPresent(String.self, forKey: .zone) ?? "auto"
        useLocation = try c.decodeIfPresent(Bool.self, forKey: .useLocation) ?? true
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
    }
}

struct AppConfig: Codable {
    /// Default menu-bar prefix before the gram value (subscript-2 CO₂).
    static let defaultMenuBarIcon = "CO\u{2082}"

    var dcIntensity: Double
    var cacheTokenWeight: Double
    var fallbackGridIntensity: Double
    var grid: GridConfig
    var modelFactors: [String: Double]
    var menuBarIcon: String

    enum CodingKeys: String, CodingKey {
        case grid
        case dcIntensity = "dc_intensity_g_per_kwh"
        case cacheTokenWeight = "cache_token_weight"
        case fallbackGridIntensity = "fallback_grid_intensity_g_per_kwh"
        case modelFactors = "model_factors_wh_per_1M_tokens"
        case menuBarIcon = "menu_bar_icon"
    }

    init() {
        dcIntensity = 350
        cacheTokenWeight = 0
        fallbackGridIntensity = 400
        grid = GridConfig()
        modelFactors = ["default": 1500, "light:*": 500, "heavy:*": 5000]
        menuBarIcon = Self.defaultMenuBarIcon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dcIntensity = try c.decodeIfPresent(Double.self, forKey: .dcIntensity) ?? 350
        cacheTokenWeight = try c.decodeIfPresent(Double.self, forKey: .cacheTokenWeight) ?? 0
        fallbackGridIntensity = try c.decodeIfPresent(Double.self, forKey: .fallbackGridIntensity) ?? 400
        grid = try c.decodeIfPresent(GridConfig.self, forKey: .grid) ?? GridConfig()
        modelFactors = try c.decodeIfPresent([String: Double].self, forKey: .modelFactors)
            ?? ["default": 1500, "light:*": 500, "heavy:*": 5000]
        menuBarIcon = try c.decodeIfPresent(String.self, forKey: .menuBarIcon) ?? Self.defaultMenuBarIcon
    }

    /// Wh per 1M tokens for a model id: exact match → prefix glob ("light:*") → default.
    func factorWhPer1MTokens(for model: String) -> Double {
        if let exact = modelFactors[model] { return exact }
        for (key, value) in modelFactors where key.hasSuffix(":*") {
            if model.hasPrefix(key.dropLast(1)) { return value }
        }
        return modelFactors["default"] ?? 1500
    }
}

enum ConfigStore {
    static func save(_ cfg: AppConfig, paths: CarbsPaths) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(cfg).write(to: paths.configFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.configFile.path)
    }

    static func loadOrCreate(paths: CarbsPaths) -> AppConfig {
        if !FileManager.default.fileExists(atPath: paths.configFile.path) {
            let cfg = AppConfig()
            save(cfg, paths: paths)
            return cfg
        }
        guard let data = try? Data(contentsOf: paths.configFile),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return cfg
    }
}
