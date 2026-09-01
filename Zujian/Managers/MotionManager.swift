import CoreMotion
import Foundation

enum MotionManagerError: LocalizedError {
    case unavailable
    case failed(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "这台 Apple Watch 无法提供所需的运动数据。"
        case .failed(let error):
            return "运动传感器启动失败：\(error.localizedDescription)"
        }
    }
}

final class MotionManager {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.linfanbin.zujian.motion"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var sampleHandler: ((MotionSample) -> Void)?
    private var failureHandler: ((MotionManagerError) -> Void)?

    var isAvailable: Bool {
#if targetEnvironment(simulator)
        true
#else
        manager.isDeviceMotionAvailable
#endif
    }

    func start(
        handler: @escaping (MotionSample) -> Void,
        onFailure: @escaping (MotionManagerError) -> Void
    ) throws {
        guard isAvailable else { throw MotionManagerError.unavailable }
        sampleHandler = handler
        failureHandler = onFailure

#if targetEnvironment(simulator)
        return
#else
        guard !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 25.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            if let error {
                DispatchQueue.main.async {
                    self?.sampleHandler = nil
                    let failure = MotionManagerError.failed(error)
                    self?.failureHandler?(failure)
                    self?.failureHandler = nil
                }
                return
            }
            guard let motion else { return }
            let acceleration = motion.userAcceleration
            let rotation = motion.rotationRate
            let gravity = motion.gravity
            let attitude = motion.attitude.quaternion
            let sample = MotionSample(
                date: Date(),
                uptime: motion.timestamp,
                userAcceleration: MotionVector3(
                    x: acceleration.x,
                    y: acceleration.y,
                    z: acceleration.z
                ),
                rotationRate: MotionVector3(
                    x: rotation.x,
                    y: rotation.y,
                    z: rotation.z
                ),
                gravity: MotionVector3(
                    x: gravity.x,
                    y: gravity.y,
                    z: gravity.z
                ),
                attitude: MotionQuaternion(
                    x: attitude.x,
                    y: attitude.y,
                    z: attitude.z,
                    w: attitude.w
                )
            )
            DispatchQueue.main.async {
                self?.sampleHandler?(sample)
            }
        }
#endif
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        sampleHandler = nil
        failureHandler = nil
    }
}
