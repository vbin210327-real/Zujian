import SwiftUI
import UniformTypeIdentifiers

struct StudioRootView: View {
    @EnvironmentObject private var library: RecordingLibrary
    @State private var showsImporter = false
    @State private var recordingPendingDeletion: StoredRecording?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(library.connectionText, systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.callout)
                }

                Section("录制") {
                    if library.recordings.isEmpty {
                        ContentUnavailableView(
                            "还没有录制",
                            systemImage: "film.stack",
                            description: Text("在 Apple Watch 开始并停止一次 App 自录制，文件会自动出现在这里。")
                        )
                    } else {
                        ForEach(library.recordings) { recording in
                            NavigationLink(value: recording.id) {
                                RecordingRow(recording: recording)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    recordingPendingDeletion = recording
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("从文件导入 JSON", systemImage: "square.and.arrow.down") {
                        showsImporter = true
                    }
                } footer: {
                    Text("手动导入使用与 WatchConnectivity 相同的录制格式，方便模拟器和 Mac 文件中转。")
                }
            }
            .navigationTitle("组间素材台")
            .navigationDestination(for: UUID.self) { id in
                if let recording = library.recording(id: id) {
                    RecordingDetailView(recording: recording)
                } else {
                    ContentUnavailableView("录制不存在", systemImage: "exclamationmark.triangle")
                }
            }
            .fileImporter(
                isPresented: $showsImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    library.importFile(at: url)
                } else if case .failure(let error) = result {
                    library.errorMessage = error.localizedDescription
                }
            }
            .alert(
                "无法完成",
                isPresented: Binding(
                    get: { library.errorMessage != nil },
                    set: { if !$0 { library.errorMessage = nil } }
                )
            ) {
                Button("知道了") { library.errorMessage = nil }
            } message: {
                Text(library.errorMessage ?? "未知错误")
            }
            .alert(
                "删除这条录制？",
                isPresented: Binding(
                    get: { recordingPendingDeletion != nil },
                    set: { if !$0 { recordingPendingDeletion = nil } }
                ),
                presenting: recordingPendingDeletion
            ) { recording in
                Button("删除", role: .destructive) {
                    library.delete(recording)
                    recordingPendingDeletion = nil
                }
                Button("取消", role: .cancel) {
                    recordingPendingDeletion = nil
                }
            } message: { _ in
                Text("只删除素材台里的原始录制数据，已经生成的 MP4 不会受影响。")
            }
        }
    }
}

private struct RecordingRow: View {
    let recording: StoredRecording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.document.createdAt, format: .dateTime.year().month().day().hour().minute())
                .font(.headline)
            HStack(spacing: 8) {
                Label(durationText, systemImage: "clock")
                Label("\(recording.document.events.count) 个事件", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var durationText: String {
        let total = max(0, Int(recording.document.duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct RecordingDetailView: View {
    let recording: StoredRecording
    private let engine: ReplayEngine?

    @State private var playhead: TimeInterval = 0
    @State private var isPlaying = false
    @State private var framesPerSecond = 60
    @State private var codec: VideoCodecOption = .h264
    @State private var isExporting = false
    @State private var exportProgress = 0.0
    @State private var exportedURL: URL?
    @State private var exportError: String?

    init(recording: StoredRecording) {
        self.recording = recording
        engine = try? ReplayEngine(recording: recording.document)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                preview

                if let engine {
                    VStack(spacing: 8) {
                        Slider(value: $playhead, in: 0...max(0.01, engine.duration))
                        HStack {
                            Button {
                                if playhead >= engine.duration {
                                    playhead = 0
                                }
                                isPlaying.toggle()
                            } label: {
                                Label(isPlaying ? "暂停" : "播放", systemImage: isPlaying ? "pause.fill" : "play.fill")
                            }
                            Spacer()
                            Text("\(timeText(playhead)) / \(timeText(engine.duration))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("最终宣传视频")
                        .font(.headline)

                    ShareLink(item: recording.fileURL) {
                        Label("导出 JSON 给 Mac 原生渲染", systemImage: "doc.badge.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("这条路径会在 Mac 的 Watch 模拟器中直接运行组间现有 View；不会使用下方的近似画布。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    Text("仅检查时间轴（非成片）")
                        .font(.subheadline.weight(.semibold))

                    Picker("帧率", selection: $framesPerSecond) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.segmented)

                    Picker("编码", selection: $codec) {
                        ForEach(VideoCodecOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if isExporting {
                        ProgressView(value: exportProgress) {
                            Text("正在生成近似预览视频")
                        } currentValueLabel: {
                            Text("\(Int(exportProgress * 100))%")
                        }
                    }

                    Button {
                        exportVideo()
                    } label: {
                        Label("生成近似预览 MP4", systemImage: "film")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExporting || engine == nil)

                    Text("此按钮仍是 iPhone 上的快速重建，不是原生 watchOS UI。宣传素材请在 Mac 导出 JSON 后，使用项目 Tools 中的原生 Watch 渲染脚本。")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    if let exportedURL {
                        ShareLink(item: exportedURL) {
                            Label("共享或存到“文件”", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

                metadata
            }
            .padding()
        }
        .navigationTitle("录制详情")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: isPlaying) {
            guard isPlaying, let engine else { return }
            let startDate = Date()
            let initialPlayhead = playhead
            while !Task.isCancelled && isPlaying {
                let next = initialPlayhead + Date().timeIntervalSince(startDate)
                if next >= engine.duration {
                    playhead = engine.duration
                    isPlaying = false
                    break
                }
                playhead = next
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
        .alert(
            "导出失败",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("知道了") { exportError = nil }
        } message: {
            Text(exportError ?? "未知错误")
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let engine {
            let device = recording.document.device
            GeometryReader { proxy in
                let logicalWidth = CGFloat(device.logicalWidth)
                let logicalHeight = CGFloat(device.logicalHeight)
                let scale = min(
                    proxy.size.width / logicalWidth,
                    proxy.size.height / logicalHeight
                )
                ReplayCanvasView(frame: engine.frame(at: playhead))
                    .frame(width: logicalWidth, height: logicalHeight)
                    .scaleEffect(scale)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .aspectRatio(device.logicalWidth / device.logicalHeight, contentMode: .fit)
            .frame(maxHeight: 430)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                Text("快速预览 · 非最终画面")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.72), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(10)
            }
        } else {
            ContentUnavailableView("无法读取录制", systemImage: "exclamationmark.triangle")
        }
    }

    private var metadata: some View {
        let device = recording.document.device
        return VStack(alignment: .leading, spacing: 5) {
            Text("录制信息")
                .font(.headline)
            Text("设备：\(device.model) · watchOS \(device.systemVersion)")
            Text("画布：\(Int(device.logicalWidth))×\(Int(device.logicalHeight)) pt · \(device.pixelWidth)×\(device.pixelHeight) px")
            Text("App：\(recording.document.app.version) (\(recording.document.app.build))")
            Text("该页预览为近似重建；Mac 原生导出直接运行 Watch 端现有 View，不包含手表外壳和录制控制按钮。")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exportVideo() {
        guard !isExporting else { return }
        isPlaying = false
        isExporting = true
        exportProgress = 0
        exportedURL = nil
        let options = VideoExportOptions(framesPerSecond: framesPerSecond, codec: codec)
        Task { @MainActor in
            do {
                let renderer = ReplayVideoRenderer()
                exportedURL = try await renderer.export(
                    recording: recording.document,
                    options: options
                ) { progress in
                    exportProgress = progress
                }
            } catch {
                exportError = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func timeText(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
