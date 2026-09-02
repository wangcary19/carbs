// carbs — usage stats window: past-week consumption graph, Screen Time style

import Charts
import SwiftUI

struct StatsView: View {
    @ObservedObject var model: CarbsModel

    private var dailyAvg: Double { model.week / 7 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Past 7 days")
                    .font(.headline)
                Text("Total \(Int(model.week.rounded())) g CO₂e · avg \(Int(dailyAvg.rounded())) g/day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.dailyStats.allSatisfy({ $0.device + $0.model == 0 }) {
                Text("No data yet — usage accumulates as carbs runs.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                Chart {
                    ForEach(model.dailyStats) { d in
                        BarMark(x: .value("Day", d.day),
                                y: .value("g", d.device))
                            .foregroundStyle(by: .value("Source", "Device"))
                            .cornerRadius(3)
                        BarMark(x: .value("Day", d.day),
                                y: .value("g", d.model))
                            .foregroundStyle(by: .value("Source", "Models"))
                            .cornerRadius(3)
                    }
                    RuleMark(y: .value("Daily average", dailyAvg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("avg")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
                // x stays the ISO day string (chronological order); labels show weekday
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let day = value.as(String.self) {
                                Text(weekdayLabel(day))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(minHeight: 170)
            }
            Divider()
            Text("Today: \(Int((model.todayDevice + model.todayModel).rounded())) g  (device \(Int(model.todayDevice.rounded())) · models \(Int(model.todayModel.rounded())))")
                .font(.caption)
        }
        .padding(16)
        .frame(width: 460)
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let weekdayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()

    private func weekdayLabel(_ day: String) -> String {
        guard let d = Self.dayParser.date(from: day) else { return day }
        return Self.weekdayFmt.string(from: d)
    }
}
