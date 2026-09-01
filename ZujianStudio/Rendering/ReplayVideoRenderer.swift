import AVFoundation
import CoreGraphics
import CoreVideo
import SwiftUI

enum VideoCodecOption: String, CaseIterable, Identifiable {
    case h264
    case hevc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        }
    }

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}

struct VideoExportOptions: Equatable {
    var framesPerSecond: Int = 60
    var codec: VideoCodecOption = .h264
}

enum ReplayVideoRendererError: LocalizedError {
    case cannotCreateWriter(String)
    case cannotAddVideoInput
    case cannotStartWriting(String)
    case cannotCreatePixelBuffer
    case cannotRenderFrame(Int)
    case cannotAppendFrame(Int, String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateWriter(let message):
            return "无法创建视频文件：\(message)"
        case .cannotAddVideoInput:
            return "视频编码器不接受当前设置。"
        case .cannotStartWriting(let message):
            return "视频编码无法开始：\(message)"
        case .cannotCreatePixelBuffer:
            return "无法分配视频帧缓存。"
        case .cannotRenderFrame(let index):
            return "第 \(index) 帧渲染失败。"
        case .cannotAppendFrame(let index, let message):
            return "第 \(index) 帧写入失败：\(message)"
        case .exportFailed(let message):
            return "视频导出失败：\(message)"
        }
    }
}

@MainActor
final class ReplayVideoRenderer {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func export(
        recording: AppRecordingDocument,
        options: VideoExportOptions,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {
        let engine = try ReplayEngine(recording: recording)
        let fps = options.framesPerSecond == 30 ? 30 : 60
        let width = recording.device.pixelWidth
        let height = recording.device.pixelHeight
        let outputURL = try makeOutputURL(recording: recording, options: options)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw ReplayVideoRendererError.cannotCreateWriter(error.localizedDescription)
        }

        let bitRate = max(2_000_000, Int(Double(width * height * fps) * 0.22))
        let settings: [String: Any] = [
            AVVideoCodecKey: options.codec.avCodec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw ReplayVideoRendererError.cannotAddVideoInput
        }
        writer.add(input)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.startWriting() else {
            throw ReplayVideoRendererError.cannotStartWriting(
                writer.error?.localizedDescription ?? "未知错误"
            )
        }
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(1, Int(ceil(engine.duration * Double(fps))) + 1)
        do {
            for frameIndex in 0..<frameCount {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed {
                        throw ReplayVideoRendererError.exportFailed(
                            writer.error?.localizedDescription ?? "编码器停止响应"
                        )
                    }
                    try await Task.sleep(nanoseconds: 1_000_000)
                }

                let timestamp = min(
                    engine.duration,
                    Double(frameIndex) / Double(fps)
                )
                guard let image = renderImage(
                    frame: engine.frame(at: timestamp),
                    device: recording.device
                ) else {
                    throw ReplayVideoRendererError.cannotRenderFrame(frameIndex)
                }
                guard let pixelBuffer = makePixelBuffer(
                    adaptor: adaptor,
                    width: width,
                    height: height,
                    image: image
                ) else {
                    throw ReplayVideoRendererError.cannotCreatePixelBuffer
                }

                let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps))
                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw ReplayVideoRendererError.cannotAppendFrame(
                        frameIndex,
                        writer.error?.localizedDescription ?? "编码器拒绝了视频帧"
                    )
                }

                if frameIndex.isMultiple(of: 4) || frameIndex == frameCount - 1 {
                    progress(Double(frameIndex + 1) / Double(frameCount))
                    await Task.yield()
                }
            }

            input.markAsFinished()
            await withCheckedContinuation { continuation in
                writer.finishWriting {
                    continuation.resume()
                }
            }
            guard writer.status == .completed else {
                throw ReplayVideoRendererError.exportFailed(
                    writer.error?.localizedDescription ?? "编码器未完成"
                )
            }
            progress(1)
            return outputURL
        } catch {
            writer.cancelWriting()
            try? fileManager.removeItem(at: outputURL)
            throw error
        }
    }

    private func makeOutputURL(
        recording: AppRecordingDocument,
        options: VideoExportOptions
    ) throws -> URL {
        let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zujian Videos", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "Zujian-\(recording.id.uuidString.prefix(8))-\(options.framesPerSecond)fps-\(options.codec.rawValue).mp4"
        let url = directory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        return url
    }

    private func renderImage(
        frame: ReplayFrame,
        device: RecordingDeviceDescriptor
    ) -> CGImage? {
        let width = CGFloat(device.logicalWidth)
        let height = CGFloat(device.logicalHeight)
        let content = ReplayCanvasView(frame: frame)
            .frame(width: width, height: height)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        renderer.scale = CGFloat(device.scale)
        renderer.isOpaque = true
        return renderer.cgImage
    }

    private func makePixelBuffer(
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        width: Int,
        height: Int,
        image: CGImage
    ) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }
        var optionalBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
              let pixelBuffer = optionalBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
