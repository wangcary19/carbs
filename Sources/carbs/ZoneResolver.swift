import CoreLocation
import Foundation

enum ZoneResolution {
    case zone(String, method: String)
    case coords(lat: Double, lon: Double, method: String)
    case unresolved
}

/// Priority chain: manual config → GPS one-shot → Mac region (single-zone countries) → unresolved.
/// Location is requested once, used only to resolve the grid zone, never stored.
final class ZoneResolver: NSObject, CLLocationManagerDelegate {
    private let config: AppConfig
    private var manager: CLLocationManager?
    private var completion: ((ZoneResolution) -> Void)?

    /// Country code → Electricity Maps zone, only where a national zone is a sane default.
    /// Multi-zone countries (US, CA, AU…) intentionally absent → fall to unresolved/ask.
    private let regionZones: [String: String] = [
        "DE": "DE", "FR": "FR", "GB": "GB", "ES": "ES", "IT": "IT", "SE": "SE",
        "NO": "NO", "NL": "NL", "BE": "BE", "CH": "CH", "AT": "AT", "DK": "DK",
        "FI": "FI", "IE": "IE", "PT": "PT", "PL": "PL", "NZ": "NZ",
    ]

    init(config: AppConfig) {
        self.config = config
    }

    func resolve(completion: @escaping (ZoneResolution) -> Void) {
        // 1. Manual override always wins
        if config.grid.zone != "auto" {
            completion(.zone(config.grid.zone, method: "manual"))
            return
        }
        // 2. GPS one-shot
        if config.grid.useLocation {
            self.completion = completion
            let m = CLLocationManager()
            m.delegate = self
            manager = m
            switch m.authorizationStatus {
            case .notDetermined:
                m.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(localeFallback())
            default:
                m.requestLocation()
            }
            return
        }
        // 3. Mac region
        completion(localeFallback())
    }

    private func localeFallback() -> ZoneResolution {
        if let region = Locale.current.region?.identifier,
           let zone = regionZones[region] {
            return .zone(zone, method: "region")
        }
        return .unresolved
    }

    private func finish(_ res: ZoneResolution) {
        let c = completion
        completion = nil
        manager = nil
        c?(res)
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            finish(localeFallback())
        case .notDetermined:
            break
        default:
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else {
            finish(localeFallback())
            return
        }
        finish(.coords(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, method: "gps"))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(localeFallback())
    }
}
