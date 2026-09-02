import Foundation

/// Electricity Maps carbon-intensity client. One GET/hour, 6h stale window,
/// persisted cache so restarts and offline periods keep working.
final class GridClient {
    struct Cache: Codable {
        var zone: String
        var intensity: Double
        var fetchedAt: Date
    }

    private(set) var intensity: Double?
    private(set) var zone: String?
    private(set) var stale = true

    private let cacheURL: URL
    var token: String // var: updatable from Settings without relaunch
    private var cache: Cache?

    init(cacheURL: URL, token: String) {
        self.cacheURL = cacheURL
        self.token = token
        if let data = try? Data(contentsOf: cacheURL),
           let c = try? JSONDecoder().decode(Cache.self, from: data) {
            cache = c
            intensity = c.intensity
            zone = c.zone
            stale = Date().timeIntervalSince(c.fetchedAt) > 6 * 3600
        }
    }

    var needsRefresh: Bool {
        guard let c = cache else { return true }
        return Date().timeIntervalSince(c.fetchedAt) > 3600
    }

    /// Fetch latest intensity. Pass an explicit zone, or lat/lon (server resolves the zone).
    /// Returns the resolved zone name on success; marks cache stale on failure.
    @discardableResult
    func refresh(zone explicitZone: String?, lat: Double? = nil, lon: Double? = nil) async -> String? {
        guard !token.isEmpty, let url = requestURL(zone: explicitZone, lat: lat, lon: lon)
        else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(token, forHTTPHeaderField: "auth-token")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let c = parseCache(data) else {
                stale = true
                return nil
            }
            cache = c
            intensity = c.intensity
            zone = c.zone
            stale = false
            try? JSONEncoder().encode(c).write(to: cacheURL, options: .atomic)
            return c.zone
        } catch {
            stale = true
            return nil
        }
    }

    private func requestURL(zone: String?, lat: Double?, lon: Double?) -> URL? {
        var comps = URLComponents(string: "https://api.electricitymap.org/v3/carbon-intensity/latest")
        if let zone {
            comps?.queryItems = [URLQueryItem(name: "zone", value: zone)]
        } else if let lat, let lon {
            comps?.queryItems = [
                URLQueryItem(name: "lat", value: String(lat)),
                URLQueryItem(name: "lon", value: String(lon)),
            ]
        } else {
            return nil
        }
        return comps?.url
    }

    /// GB live intensity without any token: NESO Carbon Intensity API
    /// (api.carbonintensity.org.uk) — anonymous REST/JSON, no key, no registration,
    /// half-hourly national data. Auto-selected when the zone resolves to GB and
    /// no Electricity Maps token is configured.
    @discardableResult
    func refreshGBKeyless() async -> String? {
        guard let url = URL(string: "https://api.carbonintensity.org.uk/intensity") else { return nil }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["data"] as? [[String: Any]],
                  let intensityObj = arr.first?["intensity"] as? [String: Any] else {
                stale = true
                return nil
            }
            // "actual" is null until the half-hour settles; forecast is fine for display
            guard let ci = (intensityObj["actual"] as? NSNumber)?.doubleValue
                ?? (intensityObj["forecast"] as? NSNumber)?.doubleValue else {
                stale = true
                return nil
            }
            let c = Cache(zone: "GB", intensity: ci, fetchedAt: Date())
            cache = c
            intensity = ci
            zone = "GB"
            stale = false
            try? JSONEncoder().encode(c).write(to: cacheURL, options: .atomic)
            return "GB"
        } catch {
            stale = true
            return nil
        }
    }

    private func parseCache(_ data: Data) -> Cache? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ci = (obj["carbonIntensity"] as? NSNumber)?.doubleValue,
              let zone = obj["zone"] as? String else { return nil }
        return Cache(zone: zone, intensity: ci, fetchedAt: Date())
    }
}
