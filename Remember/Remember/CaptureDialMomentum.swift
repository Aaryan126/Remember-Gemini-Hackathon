import Foundation
import QuartzCore

/// Velocity is measured in action spacings/second, directly from unwrapped angular motion.
nonisolated struct CaptureDialMomentum {
    static let stopSpeed: CGFloat = 0.08
    private static let friction: CGFloat = 3.5
    private var samples: [(position: CGFloat, time: TimeInterval)] = []
    private var lastDirection: CGFloat = 0

    mutating func record(position: CGFloat, time: TimeInterval) {
        guard position.isFinite, time.isFinite else { return }
        if let last = samples.last {
            guard time > last.time else { return }
            let delta = position - last.position
            if abs(delta) > 0.00001 {
                if lastDirection * delta < 0 {
                    // A reversal must discard the old direction immediately.
                    samples = [last]
                }
                lastDirection = delta
            }
        }
        samples.append((position, time))
        samples.removeAll { time - $0.time > 0.12 }
        if samples.count > 32 { samples.removeFirst(samples.count - 32) }
    }

    func releaseVelocity(at time: TimeInterval) -> CGFloat {
        guard time.isFinite, let first = samples.first, let last = samples.last,
              time >= last.time, time - last.time <= 0.08,
              last.time - first.time >= 0.015 else { return 0 }
        let speed = (last.position - first.position) / CGFloat(last.time - first.time)
        return min(24, max(-24, speed))
    }

    static func advance(velocity: CGFloat, elapsed: TimeInterval) -> (distance: CGFloat, velocity: CGFloat) {
        guard velocity.isFinite, elapsed.isFinite, elapsed > 0 else { return (0, velocity.isFinite ? velocity : 0) }
        let decay = exp(-friction * CGFloat(elapsed))
        return (velocity * (1 - decay) / friction, velocity * decay)
    }
}

/// Only runs while the dial is coasting; frames follow the display's actual refresh cadence.
@MainActor
final class CaptureDialCoaster {
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var velocity: CGFloat = 0
    private var onStep: ((CGFloat) -> Void)?
    var isRunning: Bool { displayLink != nil }

    func start(velocity: CGFloat, onStep: @escaping (CGFloat) -> Void) {
        stop()
        guard velocity.isFinite, abs(velocity) > CaptureDialMomentum.stopSpeed else { return }
        self.velocity = velocity
        self.onStep = onStep
        let target = FrameTarget()
        target.owner = self
        let link = CADisplayLink(target: target, selector: #selector(FrameTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = nil
        onStep = nil
        velocity = 0
    }

    private func tick(_ link: CADisplayLink) {
        let elapsed = previousTimestamp.map { link.timestamp - $0 } ?? (link.targetTimestamp - link.timestamp)
        previousTimestamp = link.timestamp
        let step = CaptureDialMomentum.advance(velocity: velocity, elapsed: min(0.1, elapsed))
        velocity = step.velocity
        onStep?(step.distance)
        if abs(velocity) <= CaptureDialMomentum.stopSpeed { stop() }
    }

    private final class FrameTarget: NSObject {
        weak var owner: CaptureDialCoaster?
        @objc func tick(_ link: CADisplayLink) {
            guard let owner else { link.invalidate(); return }
            owner.tick(link)
        }
    }
}
