import SwiftUI

struct FinishedView: View {
    @EnvironmentObject private var coordinator: WorkoutCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                PetMascotView(state: .finished)
                    .frame(height: 68)
                Text("训练完成")
                    .font(.headline)

                if let record = coordinator.lastSummary {
                    HStack(spacing: 16) {
                        Metric(value: DurationText.concise(record.duration), label: "时长")
                        Metric(value: "\(record.sets.count)", label: "组数")
                    }

                    if !record.sets.isEmpty {
                        Divider()
                        ForEach(record.sets) { set in
                            SetHeartRateRow(set: set)
                        }
                    }
                }

                Button("完成") {
                    coordinator.dismissSummary()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 8)
            .recordableScrollContent("finished")
        }
        .recordableScrollContainer("finished")
        .recordableScreen(.finished)
    }
}

private struct Metric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.quietSecondary)
        }
    }
}

struct SetHeartRateRow: View {
    let set: SetRecord

    var body: some View {
        HStack {
            Text("第 \(set.number) 组")
                .font(.caption.weight(.semibold))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("平均 \(heartRate(set.averageHeartRate))")
                Text("最高 \(heartRate(set.maximumHeartRate))")
                    .foregroundStyle(Color.quietSecondary)
            }
            .font(.caption2.monospacedDigit())
        }
        .padding(.vertical, 2)
    }

    private func heartRate(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))"
    }
}
