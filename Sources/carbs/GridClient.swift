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
    private let token: String
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
        guard !token.isEmpty else { return nil }
        var comps = URLComponents(string: "https://api.electricitymap.org/v3/carbon-intensity/latest")
        if let z = explicitZone {
            comps?.queryItems = [URLQueryItem(name: "zone", value: z)]
        } else if let lat, let lon {
            comps?.queryItems = [
                URLQueryItem(name: "lat", value: String(lat)),
                URLQueryItem(name: "lon", value: String(lon)),
            ]
        } else {
            return nil
        }
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(token, forHTTPHeaderField: "auth-token")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ci = (obj["carbonIntensity"] as? NSNumber)?.doubleValue,
                  let z = obj["zone"] as? String else {
                stale = true
                return nil
            }
            let c = Cache(zone: z, intensity: ci, fetchedAt: Date())
            cache = c
            intensity = ci
            zone = z
            stale = false
            try? JSONEncoder().encode(c).write(to: cacheURL)
            return z
        } catch {
            stale = true
            return nil
        }
    }
}
