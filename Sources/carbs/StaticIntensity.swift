// carbs — bundled per-zone annual-average grid intensity (tokenless estimation tier)

import Foundation

/// Approximate annual-average g CO₂/kWh per Electricity Maps zone.
///
/// Used only when no live data is available (no Electricity Maps token and no
/// keyless provider for the zone). Values are rounded 2023–2024 annual averages
/// compiled from Ember's yearly electricity data, Electricity Maps' published
/// averages, and EPA eGRID subregion rates — they are *order-of-magnitude
/// honest*, not precise, same philosophy as the model energy factors.
/// The UI labels any number computed from this table as "estimate".
enum StaticIntensity {
    static let gPerKwh: [String: Double] = [
        // Europe (all region-mappable countries in ZoneResolver must appear here)
        "DE": 380, "FR": 50, "GB": 170, "ES": 150, "IT": 330, "SE": 30,
        "NO": 25, "NL": 300, "BE": 150, "CH": 30, "AT": 110, "DK": 130,
        "FI": 60, "IE": 250, "PT": 160, "PL": 700, "CZ": 450, "GR": 350,
        "HU": 200, "RO": 250,

        // North America
        "US-CAL-CISO": 230, "US-TEX-ERCO": 370, "US-NY-NYIS": 240,
        "US-FLA-FPL": 380, "US-MIDA-PJM": 350, "US-MIDW-MISO": 430,
        "US-NE-ISNE": 250, "US-NW-BPAT": 250, "CA-ON": 70, "CA-AB": 600,
        "CA-QC": 10, "MX": 400,

        // Asia-Pacific
        "AU-NSW": 600, "AU-VIC": 700, "AU-QLD": 650, "AU-SA": 250,
        "AU-WA": 500, "AU-TAS": 100, "NZ": 110,
        "JP-TK": 450, "JP-KN": 420, "KR": 430, "TW": 530, "SG": 420,
        "IN": 630, "CN": 550,

        // Rest of world
        "BR": 90, "AR": 330, "CL": 330, "ZA": 700,
    ]

    static func intensity(forZone zone: String?) -> Double? {
        zone.flatMap { gPerKwh[$0] }
    }
}
