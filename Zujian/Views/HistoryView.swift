import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
#if DEBUG
    @EnvironmentObject private var appRecorder: AppRecordingController
#endif

    var body: some View {
        Group {
            if history.records.isEmpty {
                VStack(spacing: 6) {
                    Image("PetHistoryEmpty")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .accessibilityHidden(true)

                    Text("暂无训练")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List {
                    ForEach(history.records) { record in
                        NavigationLink {
                            HistoryDetailView(record: record)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.startDate, format: .dateTime.month().day().hour().minute())
                                    .font(.caption.weight(.semibold))
                                Text("\(record.sets.count) 组 · \(DurationText.concise(record.duration))")
                                    .font(.caption2)
                                    .foregroundStyle(Color.quietSecondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
#if DEBUG
                                appRecorder.recordGesture(
                                    "history.swipeDelete",
                                    value: .text(record.id.uuidString)
                                )
#endif
                                history.delete(record)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .recordableScrollAnchor(
                            "history",
                            value: Double(history.records.firstIndex(where: { $0.id == record.id }) ?? 0)
                        )
                    }
                }
            }
        }
        .navigationTitle("训练记录")
        .recordableScreen(.history)
    }
}

struct HistoryDetailView: View {
    let record: WorkoutRecord

    var body: some View {
        List {
            Section {
                LabeledContent("时长", value: DurationText.concise(record.duration))
                LabeledContent("组数", value: "\(record.sets.count)")
            }

            if !record.sets.isEmpty {
                Section("每组心率") {
                    ForEach(record.sets) { set in
                        SetHeartRateRow(set: set)
                    }
                }
            }
        }
        .navigationTitle(Text(record.startDate, format: .dateTime.month().day()))
        .recordableScreen(.historyDetail, context: record.id.uuidString)
    }
}
