// carbs — bundled grid intensity estimates (tokenless estimation tier)

import Foundation

/// Approximate annual-average g CO₂/kWh, keyed three ways:
///   - Electricity Maps zone ids  ("US-CAL-CISO", "GB", "DE"…)
///   - ISO subdivisions           ("US-CA", "US-TX", "CA-QC"…) — from on-device reverse geocode
///   - country codes              ("DE", "JP", "US"…) — national averages / fallbacks
///
/// Sources (rounded 2023–2024 annual averages — order-of-magnitude honest, not precise):
///   - US states:            EPA eGRID state emission rates
///   - Canadian provinces:   ECCC / National Inventory Report provincial factors
///   - Countries (Europe +): Ember yearly electricity data, Electricity Maps averages
/// Anything computed from this table is labeled "estimate" in the UI.
enum StaticIntensity {
    static let gPerKwh: [String: Double] = [
        // ---- Europe: national (EM zones = bidding zones = countries) ----
        "AL": 30, "AT": 110, "BA": 650, "BE": 150, "BG": 450, "CH": 30,
        "CY": 550, "CZ": 450, "DE": 380, "DK": 130, "EE": 500, "ES": 150,
        "FI": 60, "FR": 50, "GB": 170, "GR": 350, "HR": 200, "HU": 200,
        "IE": 250, "IS": 1, "IT": 330, "LT": 150, "LU": 100, "LV": 120,
        "MK": 600, "MT": 350, "NL": 300, "NO": 25, "PL": 700, "PT": 160,
        "RO": 250, "RS": 600, "SE": 30, "SI": 250, "SK": 130, "TR": 420,
        "UA": 250,

        // ---- US: state-level (eGRID) ----
        "US-AL": 330, "US-AK": 450, "US-AZ": 330, "US-AR": 360, "US-CA": 230,
        "US-CO": 430, "US-CT": 240, "US-DE": 400, "US-DC": 250, "US-FL": 360,
        "US-GA": 330, "US-HI": 550, "US-ID": 120, "US-IL": 320, "US-IN": 570,
        "US-IA": 330, "US-KS": 300, "US-KY": 600, "US-LA": 350, "US-ME": 150,
        "US-MD": 300, "US-MA": 250, "US-MI": 390, "US-MN": 330, "US-MS": 330,
        "US-MO": 560, "US-MT": 400, "US-NE": 450, "US-NV": 300, "US-NH": 130,
        "US-NJ": 220, "US-NM": 410, "US-NY": 210, "US-NC": 300, "US-ND": 550,
        "US-OH": 430, "US-OK": 330, "US-OR": 180, "US-PA": 330, "US-RI": 270,
        "US-SC": 230, "US-SD": 170, "US-TN": 280, "US-TX": 370, "US-UT": 540,
        "US-VT": 20, "US-VA": 280, "US-WA": 90, "US-WV": 700, "US-WI": 440,
        "US-WY": 650,
        // US: balancing-authority zones (EM ids, for manual grid.zone entries)
        "US-CAL-CISO": 230, "US-TEX-ERCO": 370, "US-NY-NYIS": 240,
        "US-FLA-FPL": 380, "US-MIDA-PJM": 350, "US-MIDW-MISO": 430,
        "US-NE-ISNE": 250, "US-NW-BPAT": 250,
        "US": 370, // national fallback

        // ---- Canada: province/territory-level (ECCC) ----
        "CA-ON": 70, "CA-QC": 10, "CA-BC": 15, "CA-AB": 600, "CA-SK": 650,
        "CA-MB": 5, "CA-NB": 300, "CA-NS": 600, "CA-PE": 250, "CA-NL": 20,
        "CA-YT": 80, "CA-NT": 250, "CA-NU": 800,
        "CA": 120, // national fallback

        // ---- Asia-Pacific ----
        "AU-NSW": 600, "AU-VIC": 700, "AU-QLD": 650, "AU-SA": 250,
        "AU-WA": 500, "AU-TAS": 100, "AU": 550, // national fallback
        "NZ": 110, "JP-TK": 450, "JP-KN": 420, "JP": 460, // national fallback
        "KR": 430, "TW": 530, "SG": 420, "IN": 630, "CN": 550,

        // ---- Rest of world ----
        "MX": 400, "BR": 90, "AR": 330, "CL": 330, "ZA": 700,
    ]

    /// Countries subdivided in the table — country-level region fallback is too
    /// coarse for these (e.g. Quebec 10 vs Alberta 600), so resolution should
    /// fall through to GPS/manual instead of using the national number.
    static let subdividedCountries: Set<String> = ["US", "CA", "AU", "JP"]

    static func intensity(forZone zone: String?) -> Double? {
        zone.flatMap { gPerKwh[$0] }
    }

    /// Resolves a reverse-geocoded placemark to a table key:
    /// "<CC>-<admin>" (with name→code aliases) first, then bare country code.
    static func key(forCountry country: String?, admin: String?) -> String? {
        guard let country, !country.isEmpty else { return nil }
        if let admin, !admin.isEmpty {
            let code = admin.count == 2 && admin == admin.uppercased()
                ? admin
                : (subdivisionAliases[admin] ?? admin)
            let k = "\(country)-\(code)"
            if gPerKwh[k] != nil { return k }
        }
        return gPerKwh[country] != nil ? country : nil
    }

    /// CLPlacemark.administrativeArea may be a code ("CA") or full name
    /// ("California") depending on locale — map names to codes for US + CA.
    private static let subdivisionAliases: [String: String] = [
        "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR",
        "California": "CA", "Colorado": "CO", "Connecticut": "CT", "Delaware": "DE",
        "District of Columbia": "DC", "Florida": "FL", "Georgia": "GA", "Hawaii": "HI",
        "Idaho": "ID", "Illinois": "IL", "Indiana": "IN", "Iowa": "IA",
        "Kansas": "KS", "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME",
        "Maryland": "MD", "Massachusetts": "MA", "Michigan": "MI", "Minnesota": "MN",
        "Mississippi": "MS", "Missouri": "MO", "Montana": "MT", "Nebraska": "NE",
        "Nevada": "NV", "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM",
        "New York": "NY", "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH",
        "Oklahoma": "OK", "Oregon": "OR", "Pennsylvania": "PA", "Rhode Island": "RI",
        "South Carolina": "SC", "South Dakota": "SD", "Tennessee": "TN", "Texas": "TX",
        "Utah": "UT", "Vermont": "VT", "Virginia": "VA", "Washington": "WA",
        "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY",
        "Ontario": "ON", "Quebec": "QC", "British Columbia": "BC", "Alberta": "AB",
        "Saskatchewan": "SK", "Manitoba": "MB", "New Brunswick": "NB",
        "Nova Scotia": "NS", "Prince Edward Island": "PE",
        "Newfoundland and Labrador": "NL", "Yukon": "YT",
        "Northwest Territories": "NT", "Nunavut": "NU",
    ]
}
