// carbs — usage stats window: 14-day stacked bar chart (device vs models) + summary

import Charts
import SwiftUI

struct StatsView: View {
    @ObservedObject var model: CarbsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Past 14 days")
                .font(.headline)
            if model.dailyStats.isEmpty {
                Text("No data yet — usage accumulates as carbs runs.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(model.dailyStats) { d in
                    BarMark(x: .value("Day", shortDay(d.day)),
                            y: .value("g", d.device))
                        .foregroundStyle(by: .value("Source", "Device"))
                    BarMark(x: .value("Day", shortDay(d.day)),
                            y: .value("g", d.model))
                        .foregroundStyle(by: .value("Source", "Models"))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                        AxisValueLabel().font(.caption2)
                    }
                }
                .frame(minHeight: 180)
            }
            Divider()
            Text("Today: \(Int((model.todayDevice + model.todayModel).rounded())) g  (device \(Int(model.todayDevice.rounded())) · models \(Int(model.todayModel.rounded())))")
                .font(.caption)
            Text("7 days: \(Int(model.week.rounded())) g · 30 days: \(Int(model.month.rounded())) g")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 440)
    }

    private func shortDay(_ day: String) -> String {
        String(day.suffix(5)) // "yyyy-MM-dd" → "MM-dd"
    }
}
