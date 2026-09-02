// carbs — grid zone resolution: manual → GPS (two modes) → Mac region → unresolved

import CoreLocation
import Foundation

enum ZoneResolution {
    case zone(String, method: String)
    case coords(lat: Double, lon: Double, method: String)
    case unresolved
}

/// Priority chain: manual config → GPS one-shot → Mac region (single-zone countries) → unresolved.
///
/// The GPS step works two ways depending on whether an Electricity Maps token exists:
///   - token:    coords go to the EM API, which resolves the zone server-side → live data
///   - tokenless: coords are reverse-geocoded ON-DEVICE (CLGeocoder) to country +
///                state/province, then matched against the bundled StaticIntensity table
///                → estimate (e.g. "US-CA", "CA-ON", "DE"). No server call, coords never stored.
final class ZoneResolver: NSObject, CLLocationManagerDelegate {
    private let config: AppConfig
    private var manager: CLLocationManager?
    private var geocoder: CLGeocoder?
    private var completion: ((ZoneResolution) -> Void)?
    /// true → send coords to Electricity Maps; false → reverse-geocode on-device
    private var useServerSideZone = false

    init(config: AppConfig) {
        self.config = config
    }

    func resolve(completion: @escaping (ZoneResolution) -> Void) {
        // 1. Manual override always wins
        if config.grid.zone != "auto" {
            completion(.zone(config.grid.zone, method: "manual"))
            return
        }
        // 2. GPS one-shot (mode depends on token, see class doc)
        if config.grid.useLocation {
            self.completion = completion
            useServerSideZone = !config.grid.token.isEmpty
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

    /// Region settings → table key, only where a national number is sane.
    /// Subdivided countries (US/CA/AU/JP — Quebec 10 vs Alberta 600) fall through.
    private func localeFallback() -> ZoneResolution {
        if let region = Locale.current.region?.identifier,
           !StaticIntensity.subdividedCountries.contains(region),
           StaticIntensity.gPerKwh[region] != nil {
            return .zone(region, method: "region")
        }
        return .unresolved
    }

    private func finish(_ res: ZoneResolution) {
        let c = completion
        completion = nil
        manager = nil
        geocoder = nil
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
        if useServerSideZone {
            finish(.coords(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, method: "gps"))
        } else {
            reverseGeocode(loc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(localeFallback())
    }

    // MARK: tokenless GPS path — on-device reverse geocode → StaticIntensity key

    private func reverseGeocode(_ loc: CLLocation) {
        let g = CLGeocoder()
        geocoder = g // retained until finish()
        g.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self, self.completion != nil else { return }
            let pm = placemarks?.first
            if let key = StaticIntensity.key(forCountry: pm?.isoCountryCode,
                                             admin: pm?.administrativeArea) {
                self.finish(.zone(key, method: "gps"))
            } else {
                self.finish(self.localeFallback())
            }
        }
    }
}
