import SwiftUI
import QuartzCore

/// One presentation position for dragging and settling; never adds a resetting
/// gesture translation to an already-committed snap destination.
@MainActor @Observable
final class ProjectGraphMotion {
    private(set) var position = CGSize.zero
    private(set) var isDragging = false
    private(set) var isSettling = false
    private var dragOrigin = CGSize.zero
    private var start = CGSize.zero
    private var destination = CGSize.zero
    private var elapsed: TimeInterval = 0
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var previousTimestamp: CFTimeInterval?
    static let duration: TimeInterval = 0.32

    func beginDrag() {
        stop()
        dragOrigin = position
        isDragging = true
    }

    func drag(translation: CGSize, layout: ProjectGraphLayout, viewport: CGSize, scale: CGFloat) {
        guard isDragging else { return }
        position = ProjectGraphLayout.boundedPan(
            CGSize(width: dragOrigin.width + translation.width, height: dragOrigin.height + translation.height),
            content: layout.size, viewport: viewport, scale: scale)
    }

    func settle(to target: CGSize, animated: Bool) {
        stop()
        guard target.width.isFinite, target.height.isFinite else { return }
        destination = target
        guard animated, position != target else { position = target; return }
        start = position
        elapsed = 0
        isSettling = true
        let proxy = FrameTarget()
        proxy.owner = self
        let link = CADisplayLink(target: proxy, selector: #selector(FrameTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    /// Deterministic elapsed-time easing, independent of the screen refresh rate.
    func advance(by interval: TimeInterval) {
        guard isSettling, interval.isFinite, interval > 0 else { return }
        elapsed = min(Self.duration, elapsed + interval)
        let t = CGFloat(elapsed / Self.duration)
        let progress = t * t * (3 - 2 * t)
        position = CGSize(width: start.width + (destination.width - start.width) * progress,
                          height: start.height + (destination.height - start.height) * progress)
        if elapsed >= Self.duration {
            position = destination
            stop()
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = nil
        isDragging = false
        isSettling = false
    }

    private func tick(_ link: CADisplayLink) {
        let interval = previousTimestamp.map { link.timestamp - $0 } ?? (link.targetTimestamp - link.timestamp)
        previousTimestamp = link.timestamp
        // The controller already supplies the visible position for this frame.
        // An inherited focus/navigation animation must not interpolate it again.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { advance(by: interval) }
    }

    private final class FrameTarget: NSObject {
        weak var owner: ProjectGraphMotion?
        @objc func tick(_ link: CADisplayLink) {
            guard let owner else { link.invalidate(); return }
            owner.tick(link)
        }
    }
}
