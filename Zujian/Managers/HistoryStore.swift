import Foundation

final class HistoryStore: ObservableObject {
    @Published private(set) var records: [WorkoutRecord] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zujian", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("workouts.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func add(_ record: WorkoutRecord) {
        records.insert(record, at: 0)
        persist()
    }

    func delete(_ record: WorkoutRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

#if DEBUG
    func applyNativeReplay(_ summaries: [ReplayWorkoutSummary]) {
        let replayRecords = summaries.map(WorkoutRecord.init(replaySummary:))
        if records != replayRecords {
            records = replayRecords
        }
    }
#endif

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([WorkoutRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded.sorted { $0.startDate > $1.startDate }
    }

    private func persist() {
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
