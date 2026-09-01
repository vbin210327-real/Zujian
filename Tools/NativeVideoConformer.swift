import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

enum NativeVideoConformerError: LocalizedError {
    case invalidArguments
    case missingVideoTrack
    case invalidDuration
    case cannotCreateCompositionTrack
    case cannotAddReaderOutput
    case cannotAddWriterInput
    case cannotStartReader(String)
    case cannotStartWriter(String)
    case cannotAppend(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "参数无效。"
        case .missingVideoTrack:
            return "原始录制没有视频轨道。"
        case .invalidDuration:
            return "输出时长无效。"
        case .cannotCreateCompositionTrack:
            return "无法创建视频合成轨道。"
        case .cannotAddReaderOutput:
            return "无法读取原始视频帧。"
        case .cannotAddWriterInput:
            return "视频编码器不接受当前设置。"
        case .cannotStartReader(let message):
            return "无法开始读取视频：\(message)"
        case .cannotStartWriter(let message):
            return "无法开始编码视频：\(message)"
        case .cannotAppend(let message):
            return "无法写入视频帧：\(message)"
        case .exportFailed(let message):
            return "视频导出失败：\(message)"
        }
    }
}

@main
struct NativeVideoConformer {
    static func main() async {
        do {
            try await export()
        } catch {
            FileHandle.standardError.write(
                Data("\(error.localizedDescription)\n".utf8)
            )
            exit(1)
        }
    }

    private static func export() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 7,
              let framesPerSecond = Int(arguments[3]),
              framesPerSecond == 30 || framesPerSecond == 60,
              let requestedDuration = Double(arguments[5]),
              let trimStart = Double(arguments[6]),
              requestedDuration > 0,
              trimStart >= 0 else {
            throw NativeVideoConformerError.invalidArguments
        }

        let inputURL = URL(fileURLWithPath: arguments[1])
        let outputURL = URL(fileURLWithPath: arguments[2])
        let codec: AVVideoCodecType
        switch arguments[4] {
        case "h264": codec = .h264
        case "hevc": codec = .hevc
        default: throw NativeVideoConformerError.invalidArguments
        }

        let sourceAsset = AVURLAsset(url: inputURL)
        guard let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
            throw NativeVideoConformerError.missingVideoTrack
        }
        let assetDuration = try await sourceAsset.load(.duration)
        let availableDuration = CMTimeGetSeconds(assetDuration) - trimStart
        let outputDuration = min(requestedDuration, availableDuration)
        guard outputDuration > 0 else {
            throw NativeVideoConformerError.invalidDuration
        }

        let timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 60_000),
            duration: CMTime(seconds: outputDuration, preferredTimescale: 60_000)
        )

        let naturalSize = try await sourceTrack.load(.naturalSize)
        let reader = try AVAssetReader(asset: sourceAsset)
        reader.timeRange = timeRange
        let readerOutput = AVAssetReaderTrackOutput(
            track: sourceTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw NativeVideoConformerError.cannotAddReaderOutput
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let width = max(2, Int(naturalSize.width.rounded()))
        let height = max(2, Int(naturalSize.height.rounded()))
        let bitRate = max(
            2_000_000,
            Int(Double(width * height * framesPerSecond) * 0.25)
        )
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
                ],
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitRate,
                    AVVideoExpectedSourceFrameRateKey: framesPerSecond,
                    AVVideoMaxKeyFrameIntervalKey: framesPerSecond * 2,
                    AVVideoAllowFrameReorderingKey: false
                ]
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw NativeVideoConformerError.cannotAddWriterInput
        }
        writer.add(writerInput)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.startWriting() else {
            throw NativeVideoConformerError.cannotStartWriter(
                writer.error?.localizedDescription ?? "未知错误"
            )
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            writer.cancelWriting()
            throw NativeVideoConformerError.cannotStartReader(
                reader.error?.localizedDescription ?? "未知错误"
            )
        }

        do {
            var nextSampleBuffer = readerOutput.copyNextSampleBuffer()
            var currentPixelBuffer: CVPixelBuffer?
            let frameCount = max(
                1,
                Int(ceil(outputDuration * Double(framesPerSecond)))
            )

            for frameIndex in 0..<frameCount {
                try Task.checkCancellation()
                guard writer.status != .failed else {
                    throw NativeVideoConformerError.cannotAppend(
                        writer.error?.localizedDescription ?? "编码器已停止"
                    )
                }

                let relativeSeconds = min(
                    outputDuration,
                    Double(frameIndex) / Double(framesPerSecond)
                )
                let sourceTime = CMTime(
                    seconds: trimStart + relativeSeconds,
                    preferredTimescale: 60_000
                )
                while let sampleBuffer = nextSampleBuffer,
                      CMTimeCompare(
                        CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                        sourceTime
                      ) <= 0 {
                    if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        currentPixelBuffer = imageBuffer
                    }
                    nextSampleBuffer = readerOutput.copyNextSampleBuffer()
                }
                if currentPixelBuffer == nil,
                   let nextSampleBuffer,
                   let imageBuffer = CMSampleBufferGetImageBuffer(nextSampleBuffer) {
                    currentPixelBuffer = imageBuffer
                }
                guard let currentPixelBuffer else {
                    throw NativeVideoConformerError.cannotAppend("没有可用的原始画面")
                }

                while !writerInput.isReadyForMoreMediaData {
                    guard writer.status != .failed else {
                        throw NativeVideoConformerError.cannotAppend(
                            writer.error?.localizedDescription ?? "编码器已停止"
                        )
                    }
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                let presentationTime = CMTime(
                    value: CMTimeValue(frameIndex),
                    timescale: CMTimeScale(framesPerSecond)
                )
                guard pixelBufferAdaptor.append(
                    currentPixelBuffer,
                    withPresentationTime: presentationTime
                ) else {
                    throw NativeVideoConformerError.cannotAppend(
                        writer.error?.localizedDescription ?? "编码器拒绝了视频帧"
                    )
                }
            }

            if reader.status == .reading {
                reader.cancelReading()
            } else if reader.status == .failed {
                throw NativeVideoConformerError.exportFailed(
                    reader.error?.localizedDescription ?? "读取器已停止"
                )
            }
            writerInput.markAsFinished()
            await withCheckedContinuation { continuation in
                writer.finishWriting {
                    continuation.resume()
                }
            }
            guard writer.status == .completed else {
                throw NativeVideoConformerError.exportFailed(
                    writer.error?.localizedDescription ?? "编码器未完成"
                )
            }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
