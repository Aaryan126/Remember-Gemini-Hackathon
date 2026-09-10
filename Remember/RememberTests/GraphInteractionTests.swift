import Foundation
import CoreGraphics
import Testing
@testable import Remember

struct GraphInteractionTests {
    @Test func nodeLightMovesSubtlyWithPositionAndNeverAnimatesAtRest() {
        let viewport = CGSize(width: 370, height: 600)
        let center = CGPoint(x: 185, y: 280)
        let resting = ProjectGraphLighting(center: center, viewport: viewport, reduceMotion: false)
        #expect(resting.highlightOrigin == CGPoint(x: 0.30, y: 0.18))
        #expect(resting == ProjectGraphLighting(center: center, viewport: viewport, reduceMotion: false))
        var previous = resting
        for offset in stride(from: CGFloat(1), through: 600, by: 1) {
            let next = ProjectGraphLighting(center: CGPoint(x: center.x + offset, y: center.y), viewport: viewport, reduceMotion: false)
            #expect(next.highlightOrigin.x < previous.highlightOrigin.x)
            #expect(abs(next.highlightOrigin.x - previous.highlightOrigin.x) < 0.001)
            #expect(abs(next.rimAngle - previous.rimAngle) < 0.1)
            previous = next
        }
        #expect(previous.highlightOrigin.x >= 0.235)
        #expect(previous.rimAngle <= -113)
    }

    @Test func nodeLightIsBoundedAndReduceMotionKeepsItStatic() {
        let viewport = CGSize(width: 370, height: 600)
        let staticLight = ProjectGraphLighting(center: .zero, viewport: viewport, reduceMotion: true)
        for point in [CGPoint.zero, CGPoint(x: -10000, y: 10000), CGPoint(x: 10000, y: -10000)] {
            let light = ProjectGraphLighting(center: point, viewport: viewport, reduceMotion: false)
            #expect(light.highlightOrigin.x >= 0.235 && light.highlightOrigin.x <= 0.365)
            #expect(light.highlightOrigin.y >= 0.135 && light.highlightOrigin.y <= 0.225)
            #expect(light.rimAngle >= -145 && light.rimAngle <= -105)
            #expect(ProjectGraphLighting(center: point, viewport: viewport, reduceMotion: true) == staticLight)
        }
        #expect(ProjectGraphLighting(center: CGPoint(x: CGFloat.nan, y: 0), viewport: .zero, reduceMotion: false) == staticLight)
    }

    @Test @MainActor func nodeLightSettlesOnTheSameFramesAsTheGrid() {
        let viewport = CGSize(width: 370, height: 600)
        let motion = ProjectGraphMotion()
        motion.beginDrag()
        motion.drag(translation: CGSize(width: 60, height: -30), layout: ProjectGraphLayout(count: 7), viewport: viewport, scale: 1)
        motion.settle(to: .zero, animated: true)
        let lightAtCurrentPosition = {
            ProjectGraphLighting(center: CGPoint(x: 185 + motion.position.width, y: 280 + motion.position.height),
                                 viewport: viewport, reduceMotion: false)
        }
        let release = lightAtCurrentPosition()
        motion.advance(by: ProjectGraphMotion.duration / 2)
        let middle = lightAtCurrentPosition()
        motion.advance(by: ProjectGraphMotion.duration / 2)
        let end = lightAtCurrentPosition()
        #expect(release != middle && middle != end)
        #expect(end == ProjectGraphLighting(center: CGPoint(x: 185, y: 280), viewport: viewport, reduceMotion: false))
        motion.advance(by: 2)
        #expect(lightAtCurrentPosition() == end)
    }

    @Test @MainActor func snapAnimationStartsAtReleaseAndEasesEveryFrame() {
        let layout = ProjectGraphLayout(count: 7)
        for release in [CGSize(width: 35, height: 18), CGSize(width: -65, height: 90), CGSize(width: 10, height: -8)] {
            for rate: Double in [30, 60, 120] {
                let motion = ProjectGraphMotion()
                motion.beginDrag()
                motion.drag(translation: release, layout: layout, viewport: CGSize(width: 370, height: 600), scale: 1)
                motion.settle(to: .zero, animated: true)
                #expect(motion.position == release, "Releasing must not reset or jump the presentation offset.")
                #expect(motion.isSettling && !motion.isDragging)
                let distance = hypot(release.width, release.height)
                var previous = motion.position
                var remaining = distance
                for _ in 0..<Int(ceil(ProjectGraphMotion.duration * rate)) {
                    motion.advance(by: 1 / rate)
                    let next = motion.position
                    let step = hypot(next.width - previous.width, next.height - previous.height)
                    #expect(step < distance * 0.17)
                    let nextRemaining = hypot(next.width, next.height)
                    #expect(nextRemaining <= remaining)
                    previous = next; remaining = nextRemaining
                }
                #expect(motion.position == .zero)
                #expect(!motion.isSettling)
            }
        }
    }

    @Test @MainActor func grabbingMidSnapContinuesFromVisiblePositionAndDiscardsOldTarget() {
        let layout = ProjectGraphLayout(count: 7)
        let viewport = CGSize(width: 370, height: 600)
        let motion = ProjectGraphMotion()
        motion.beginDrag()
        motion.drag(translation: CGSize(width: 45, height: 30), layout: layout, viewport: viewport, scale: 1)
        motion.settle(to: .zero, animated: true)
        motion.advance(by: 0.12)
        let visible = motion.position
        #expect(visible != .zero)
        motion.beginDrag()
        #expect(motion.position == visible && !motion.isSettling)
        motion.drag(translation: CGSize(width: -20, height: 8), layout: layout, viewport: viewport, scale: 1)
        let dragged = CGSize(width: visible.width - 20, height: visible.height + 8)
        #expect(motion.position == dragged)
        motion.advance(by: 1)
        #expect(motion.position == dragged, "A cancelled frame cannot revive the previous snap.")
        let target = CGSize(width: -80, height: 90)
        motion.settle(to: target, animated: true)
        #expect(motion.position == dragged)
        motion.advance(by: ProjectGraphMotion.duration)
        #expect(motion.position == target && !motion.isSettling)
    }

    @Test @MainActor func snapMotionStopsForReducedMotionNoOpAndDisappearance() {
        let motion = ProjectGraphMotion()
        motion.settle(to: .zero, animated: true)
        #expect(!motion.isSettling)
        let target = CGSize(width: 80, height: -40)
        motion.settle(to: target, animated: false)
        #expect(motion.position == target && !motion.isSettling)
        motion.settle(to: .zero, animated: true)
        motion.advance(by: 0.1)
        let visible = motion.position
        motion.stop()
        motion.advance(by: 1)
        #expect(motion.position == visible && !motion.isSettling && !motion.isDragging)
    }

    @Test func mapDepthBringsTheCenterForwardAndTracksPanning() throws {
        let layout = ProjectGraphLayout(memberCounts: [1, 1, 1, 1, 1, 1])
        let viewport = CGSize(width: 370, height: 460)
        let scale = ProjectGraphLayout.browsingScale(in: viewport)
        let initial = ProjectGraphProjection(layout: layout, viewport: viewport, scale: scale, pan: .zero,
            focusedIndex: nil, reduceMotion: false)
        let center = CGPoint(x: viewport.width / 2, y: (viewport.height - 40) / 2)
        let peripheral = try #require((0..<layout.count).first { $0 != layout.centralIndex })
        let point = layout.position(peripheral)
        let offset = CGSize(width: (layout.size.width / 2 - point.x) * scale,
                            height: (layout.size.height / 2 - point.y) * scale)
        let centered = ProjectGraphProjection(layout: layout, viewport: viewport, scale: scale, pan: offset,
            focusedIndex: nil, reduceMotion: false)
        #expect(centered.nodes[peripheral].diameter > initial.nodes[peripheral].diameter * 1.15)
        #expect(abs(centered.nodes[peripheral].scale - scale * 1.16) < 0.00001)
        #expect(centered.hitTest(center) == peripheral)
        #expect(centered.hitTest(CGPoint(x: -10000, y: -10000)) == nil)
    }

    @Test func mapFocusMagnifiesWithoutMovingAnyGridSlot() {
        let layout = ProjectGraphLayout(memberCounts: [2, 2])
        let viewport = CGSize(width: 370, height: 460)
        let idle = ProjectGraphProjection(layout: layout, viewport: viewport, scale: 1, pan: .zero,
            focusedIndex: nil, reduceMotion: false)
        let focus = ProjectGraphProjection(layout: layout, viewport: viewport, scale: 1, pan: .zero,
            focusedIndex: 0, reduceMotion: false)
        #expect(focus.nodes[0].center == idle.nodes[0].center)
        #expect(abs(focus.nodes[0].diameter / idle.nodes[0].diameter - 1.06) < 0.00001)
        let before = hypot(idle.nodes[1].center.x - idle.nodes[0].center.x, idle.nodes[1].center.y - idle.nodes[0].center.y)
        let after = hypot(focus.nodes[1].center.x - focus.nodes[0].center.x, focus.nodes[1].center.y - focus.nodes[0].center.y)
        #expect(after == before)
        #expect(focus.nodes[1].center == idle.nodes[1].center)
        #expect(focus.hitTest(focus.nodes[0].center) == 0)
    }

    @Test func mapReduceMotionDisablesDepthLiftAndNeighborMovement() {
        let layout = ProjectGraphLayout(memberCounts: [1, 5])
        let viewport = CGSize(width: 370, height: 460)
        let idle = ProjectGraphProjection(layout: layout, viewport: viewport, scale: 0.8, pan: .zero,
            focusedIndex: nil, reduceMotion: true)
        let focus = ProjectGraphProjection(layout: layout, viewport: viewport, scale: 0.8, pan: .zero,
            focusedIndex: 0, reduceMotion: true)
        for index in idle.nodes.indices {
            #expect(focus.nodes[index].center == idle.nodes[index].center)
            #expect(focus.nodes[index].diameter == layout.diameter(index) * 0.8)
        }
    }

    @Test func mapConnectionsMeetProjectedRimsAndHandleEmptyLayouts() throws {
        let layout = ProjectGraphLayout(memberCounts: [1, 5])
        let projection = ProjectGraphProjection(layout: layout, viewport: CGSize(width: 370, height: 460), scale: 0.8,
            pan: CGSize(width: 20, height: -15), focusedIndex: 0, reduceMotion: false)
        let ends = try #require(projection.endpoints(for: .init(first: 0, second: 1)))
        let node = projection.nodes[0]
        #expect(abs(hypot(ends.start.x - node.center.x, ends.start.y - node.center.y) - node.diameter / 2 - 2) < 0.00001)
        #expect(projection.endpoints(for: .init(first: 0, second: 0)) == nil)
        let empty = ProjectGraphProjection(layout: .init(count: 0), viewport: .zero, scale: 0, pan: .zero,
            focusedIndex: 12, reduceMotion: false)
        #expect(empty.nodes.isEmpty && empty.hitTest(.zero) == nil)
        #expect(empty.endpoints(for: .init(first: 0, second: 1)) == nil)
    }

    @Test func mapFocusDepthPreservesSeparationAcrossViewportSizes() {
        for count in [2, 6, 9, 40] {
            let layout = ProjectGraphLayout(memberCounts: (0..<count).map { 1 + $0 % 8 })
            for viewport in [CGSize(width: 288, height: 350), CGSize(width: 370, height: 600), CGSize(width: 800, height: 900)] {
                let projection = ProjectGraphProjection(layout: layout, viewport: viewport, scale: ProjectGraphLayout.browsingScale(in: viewport),
                    pan: CGSize(width: 35, height: -15), focusedIndex: count / 2, reduceMotion: false)
                for first in 0..<count {
                    for second in (first + 1)..<count {
                        let a = projection.nodes[first], b = projection.nodes[second]
                        #expect(hypot(a.center.x - b.center.x, a.center.y - b.center.y) >= (a.diameter + b.diameter) / 2)
                    }
                }
            }
        }
    }

    @Test @MainActor func coastingStopsImmediatelyAndDoesNotStartForZeroSpeed() {
        let coaster = CaptureDialCoaster()
        coaster.start(velocity: 10) { _ in }
        #expect(coaster.isRunning)
        coaster.stop()
        #expect(!coaster.isRunning)
        coaster.stop()
        coaster.start(velocity: 0) { _ in }
        #expect(!coaster.isRunning)
    }

    @Test func momentumDeceleratesWithoutReversingAndIsFrameRateIndependent() {
        for speed: CGFloat in [-20, 20] {
            let first = CaptureDialMomentum.advance(velocity: speed, elapsed: 0.1)
            let second = CaptureDialMomentum.advance(velocity: first.velocity, elapsed: 0.1)
            let combined = CaptureDialMomentum.advance(velocity: speed, elapsed: 0.2)
            #expect(first.distance * speed > 0)
            #expect(abs(second.velocity) < abs(first.velocity))
            #expect(abs(second.distance) < abs(first.distance))
            #expect(abs(first.distance + second.distance - combined.distance) < 0.00001)
            #expect(abs(second.velocity - combined.velocity) < 0.00001)
            #expect(abs(CaptureDialMomentum.advance(velocity: speed, elapsed: 2).velocity) < CaptureDialMomentum.stopSpeed)
        }
    }

    @Test func momentumUsesRecentDirectionAndHoldingStopsTheFling() {
        var motion = CaptureDialMomentum()
        motion.record(position: 0, time: 0)
        motion.record(position: -0.5, time: 0.05)
        #expect(motion.releaseVelocity(at: 0.05) == -10)
        motion.record(position: -0.5, time: 0.06)
        motion.record(position: -0.2, time: 0.10)
        #expect(motion.releaseVelocity(at: 0.10) > 0)
        #expect(motion.releaseVelocity(at: 0.25) == 0)
        #expect(motion.releaseVelocity(at: -1) == 0)
    }

    @Test func momentumBoundsFastFlingsAndIgnoresInvalidSamples() {
        var motion = CaptureDialMomentum()
        motion.record(position: 0, time: 0)
        motion.record(position: 100, time: 0.02)
        motion.record(position: .nan, time: 0.03)
        #expect(motion.releaseVelocity(at: 0.02) == 24)
        #expect(CaptureDialMomentum.advance(velocity: 0, elapsed: 1).distance == 0)
        #expect(CaptureDialMomentum.advance(velocity: .nan, elapsed: 1).distance == 0)
        #expect(CaptureDialMomentum.advance(velocity: 10, elapsed: -1).distance == 0)
    }

    @Test func riverMediaUsesTheSavedRevisionAndRejectsEscapingPaths() throws {
        let root = URL(fileURLWithPath: "/tmp/river-test-originals", isDirectory: true)
        #expect(try RiverMediaView.originalURL(filename: "revision-2.jpg", directory: root) == root.appendingPathComponent("revision-2.jpg"))
        #expect(throws: Error.self) { try RiverMediaView.originalURL(filename: "../outside.jpg", directory: root) }
        #expect(throws: Error.self) { try RiverMediaView.originalURL(filename: "", directory: root) }
    }

    @Test func cameraCaptureDeclaresItsPrivacyPurpose() {
        let description = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        #expect(description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    @Test func dialFollowsFingerAtTopAndLeftOfArc() {
        let center = CGPoint.zero
        // At the top, a leftward drag moves the actions left. At the left,
        // an upward drag moves them up: the signs must differ around the hub.
        #expect(CaptureDialDrag.progress(from: CGPoint(x: 0, y: -135), to: CGPoint(x: -67.5, y: -116.913), center: center) < 0)
        #expect(CaptureDialDrag.progress(from: CGPoint(x: -135, y: 0), to: CGPoint(x: -116.913, y: -67.5), center: center) > 0)
    }

    @Test func dialDirectionIsContinuousAcrossAngleBoundaryAndReversible() {
        let a = CGPoint(x: -135, y: 1), b = CGPoint(x: -135, y: -1)
        let forward = CaptureDialDrag.progress(from: a, to: b, center: .zero)
        let backward = CaptureDialDrag.progress(from: b, to: a, center: .zero)
        #expect(forward > 0 && forward < 0.1)
        #expect(abs(forward + backward) < 0.00001)
        #expect(CaptureDialDrag.progress(from: .zero, to: a, center: .zero) == 0)
        #expect(CaptureDialDrag.progress(from: a, to: a, center: .zero) == 0)
        #expect(CaptureDialDrag.progress(from: a, to: CGPoint(x: 135, y: 0), center: .zero) == 0)
    }

    @Test func dialDiagonalDoesNotSwitchDirectionWhenDominantAxisChanges() {
        let points = [CGPoint(x: -30, y: -130), CGPoint(x: -65, y: -115), CGPoint(x: -100, y: -90), CGPoint(x: -130, y: -40)]
        for index in 1..<points.count {
            #expect(CaptureDialDrag.progress(from: points[index - 1], to: points[index], center: .zero) < 0)
        }
    }

    @Test func mapLayoutKeepsEveryCircleInsideBoundsAndApart() {
        for count in [0, 1, 2, 6, 8, 9, 40] {
            let layout = ProjectGraphLayout(memberCounts: (0..<count).map { 1 + $0 % 8 })
            for index in 0..<count {
                let point = layout.position(index)
                let radius = layout.diameter(index) / 2
                #expect(point.x >= radius && point.x + radius <= layout.size.width)
                #expect(point.y >= radius && point.y + radius <= layout.size.height)
                for next in (index + 1)..<count {
                    let other = layout.position(next)
                    #expect(hypot(point.x - other.x, point.y - other.y) >= radius + layout.diameter(next) / 2 + 20)
                }
            }
        }
    }

    @Test func browsingScaleKeepsLabelsReadableWithoutFittingTheLibrary() {
        for width: CGFloat in [0, 288, 343, 402, 800] {
            let scale = ProjectGraphLayout.browsingScale(in: CGSize(width: width, height: 600))
            #expect(scale >= 0.8 && scale <= 1)
            #expect(scale == ProjectGraphLayout.browsingScale(in: CGSize(width: width, height: 200)))
            let small = ProjectGraphLayout(count: 1)
            let large = ProjectGraphLayout(count: 40)
            #expect(small.diameter(0) * scale == large.diameter(0) * scale)
            #expect(large.diameter(0) * scale * 0.9 > 80)
        }
    }

    @Test func panningCanBringEveryCircleToTheCenterWithoutZoom() {
        for count in [1, 6, 9, 40] {
            let layout = ProjectGraphLayout(memberCounts: (0..<count).map { 1 + $0 % 8 })
            let viewport = CGSize(width: 370, height: 600)
            let scale = ProjectGraphLayout.browsingScale(in: viewport)
            let center = CGPoint(x: viewport.width / 2, y: (viewport.height - 40) / 2)
            let overview = ProjectGraphProjection(layout: layout, viewport: viewport, scale: scale, pan: .zero,
                focusedIndex: nil, reduceMotion: false)
            for index in overview.nodes.indices {
                let point = layout.position(index)
                let desired = CGSize(width: (layout.size.width / 2 - point.x) * scale,
                                     height: (layout.size.height / 2 - point.y) * scale)
                #expect(ProjectGraphLayout.boundedPan(desired, content: layout.size, viewport: viewport, scale: scale) == desired)
                let centered = ProjectGraphProjection(layout: layout, viewport: viewport, scale: scale, pan: desired,
                    focusedIndex: nil, reduceMotion: false)
                #expect(abs(centered.nodes[index].center.x - center.x) < 0.00001)
                #expect(abs(centered.nodes[index].center.y - center.y) < 0.00001)
            }
        }
    }

    @Test func honeycombHasSixEquidistantNeighborsAndCentersTheLargestThread() throws {
        let layout = ProjectGraphLayout(memberCounts: [1, 1, 8, 1, 1, 1, 1])
        #expect(layout.centralIndex == 2)
        let center = layout.position(2)
        #expect(center == CGPoint(x: layout.size.width / 2, y: layout.size.height / 2))
        let neighbors = (0..<7).filter { $0 != 2 }.map(layout.position)
        let radius = hypot(neighbors[0].x - center.x, neighbors[0].y - center.y)
        for point in neighbors { #expect(abs(hypot(point.x - center.x, point.y - center.y) - radius) < 0.00001) }
        for index in neighbors.indices {
            let a = neighbors[index], b = neighbors[(index + 1) % 6]
            #expect(abs(hypot(a.x - b.x, a.y - b.y) - radius) < 0.00001)
        }
    }

    @Test func snappingCentersEveryOccupiedSlotAndIsIdempotent() throws {
        for count in [1, 6, 19, 40] {
            let layout = ProjectGraphLayout(memberCounts: (0..<count).map { 1 + $0 % 8 })
            for scale: CGFloat in [0.8, 1] {
                for index in 0..<count {
                    let point = layout.position(index)
                    let exact = CGSize(width: (layout.size.width / 2 - point.x) * scale,
                                       height: (layout.size.height / 2 - point.y) * scale)
                    for drift in [CGSize.zero, CGSize(width: 25, height: -30), CGSize(width: -35, height: 20)] {
                        let released = CGSize(width: exact.width + drift.width, height: exact.height + drift.height)
                        let target = try #require(layout.snapTarget(for: released, scale: scale))
                        #expect(target.index == index)
                        #expect(target.pan == exact)
                        #expect(layout.snapTarget(for: target.pan, scale: scale)?.pan == exact)
                        let viewport = CGSize(width: 370, height: 600)
                        #expect(ProjectGraphLayout.boundedPan(exact, content: layout.size, viewport: viewport, scale: scale) == exact)
                        let projection = ProjectGraphProjection(layout: layout, viewport: viewport, scale: scale,
                            pan: target.pan, focusedIndex: index, reduceMotion: false)
                        #expect(abs(projection.nodes[index].center.x - 185) < 0.00001)
                        #expect(abs(projection.nodes[index].center.y - 280) < 0.00001)
                    }
                }
            }
        }
    }

    @Test func snappingChoosesNearestExistingNodeAtEdgesAndAcrossThreshold() throws {
        let layout = ProjectGraphLayout(count: 6)
        let center = try #require(layout.centralIndex)
        let neighbor = try #require((0..<layout.count).first { $0 != center })
        let point = layout.position(neighbor)
        let target = CGSize(width: layout.size.width / 2 - point.x, height: layout.size.height / 2 - point.y)
        #expect(layout.snapTarget(for: CGSize(width: target.width * 0.45, height: target.height * 0.45), scale: 1)?.index == center)
        #expect(layout.snapTarget(for: CGSize(width: target.width * 0.55, height: target.height * 0.55), scale: 1)?.index == neighbor)
        for released in [CGSize(width: 900, height: -800), CGSize(width: -700, height: 950)] {
            let snapped = try #require(layout.snapTarget(for: released, scale: 1))
            let distance = hypot(snapped.pan.width - released.width, snapped.pan.height - released.height)
            for index in 0..<layout.count {
                let p = layout.position(index)
                let candidate = hypot(layout.size.width / 2 - p.x - released.width, layout.size.height / 2 - p.y - released.height)
                #expect(distance <= candidate + 0.00001)
            }
        }
        #expect(ProjectGraphLayout(count: 0).snapTarget(for: .zero, scale: 1) == nil)
        #expect(layout.snapTarget(for: .zero, scale: 0) == nil)
        #expect(layout.snapTarget(for: CGSize(width: CGFloat.nan, height: 0), scale: 1) == nil)
    }

    @Test func lensMagnifiesSizesWhileCentersTrackPanExactly() {
        let layout = ProjectGraphLayout(count: 1)
        let viewport = CGSize(width: 370, height: 600)
        var previousX: CGFloat = -.infinity
        var previousSize: CGFloat = .infinity
        for offset in stride(from: CGFloat(0), through: 600, by: 10) {
            let projection = ProjectGraphProjection(layout: layout, viewport: viewport, scale: 1,
                pan: CGSize(width: offset, height: 0), focusedIndex: nil, reduceMotion: false)
            let node = projection.nodes[0]
            #expect(node.center.x > previousX && node.diameter <= previousSize)
            #expect(node.scale.isFinite && node.scale > 0)
            #expect(abs(node.center.x - viewport.width / 2 - offset) < 0.00001)
            previousX = node.center.x; previousSize = node.diameter
        }
    }

    @Test func honeycombSlotsRemainRigidThroughoutPanAndFocusChanges() {
        for count in [1, 7, 19, 40] {
            let layout = ProjectGraphLayout(memberCounts: (0..<count).map { 1 + $0 % 8 })
            for viewport in [CGSize(width: 288, height: 350), CGSize(width: 800, height: 900)] {
                let scale = ProjectGraphLayout.browsingScale(in: viewport)
                let origin = CGPoint(x: viewport.width / 2, y: (viewport.height - 40) / 2)
                for pan in [CGSize.zero, CGSize(width: 120, height: -75), CGSize(width: -260, height: 310)] {
                    for focus in [nil, 0, count - 1] as [Int?] {
                        let projection = ProjectGraphProjection(layout: layout, viewport: viewport, scale: scale,
                            pan: pan, focusedIndex: focus, reduceMotion: false)
                        for index in 0..<count {
                            let slot = layout.position(index)
                            let node = projection.nodes[index]
                            #expect(abs(node.center.x - origin.x - pan.width - (slot.x - layout.size.width / 2) * scale) < 0.00001)
                            #expect(abs(node.center.y - origin.y - pan.height - (slot.y - layout.size.height / 2) * scale) < 0.00001)
                            for next in (index + 1)..<count {
                                let other = projection.nodes[next]
                                #expect(hypot(node.center.x - other.center.x, node.center.y - other.center.y)
                                    >= (node.diameter + other.diameter) / 2 + 10 * scale)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func fullyVisibleLensCirclesRemainUsableTouchTargets() {
        let layout = ProjectGraphLayout(count: 40)
        for viewport in [CGSize(width: 288, height: 350), CGSize(width: 370, height: 600)] {
            for pan in [CGSize.zero, CGSize(width: 170, height: -250)] {
                let projection = ProjectGraphProjection(layout: layout, viewport: viewport,
                    scale: ProjectGraphLayout.browsingScale(in: viewport), pan: pan, focusedIndex: nil, reduceMotion: false)
                for node in projection.nodes {
                    let frame = CGRect(x: node.center.x - node.diameter / 2, y: node.center.y - node.diameter / 2,
                                       width: node.diameter, height: node.diameter)
                    if CGRect(origin: .zero, size: viewport).contains(frame) { #expect(node.diameter >= 44) }
                }
            }
        }
    }

    @Test func circleSizeReflectsVolumeAndIsBoundedIndependentOfOtherThreads() {
        let layout = ProjectGraphLayout(memberCounts: [0, 1, 2, 3, 5, 1_000, Int.max])
        #expect(layout.diameter(0) == layout.diameter(1))
        #expect(layout.diameter(1) < layout.diameter(2))
        #expect(layout.diameter(2) < layout.diameter(3))
        #expect(layout.diameter(3) < layout.diameter(4))
        #expect(layout.diameter(6) == 172)
        #expect(layout.diameter(2) == ProjectGraphLayout(memberCounts: [2]).diameter(0))
        #expect(layout.diameter(0) >= 44)
    }

    @Test func mapKeepsFullTitleButUsesCompactWordsInTheCircle() {
        var snapshot = makeSnapshot(count: 1)
        let id = snapshot.activeClusters[0].id
        let title = "One two three four five six seven"
        snapshot.clusters[id]?.title = title
        let node = ProjectGraphMap(snapshot: snapshot).nodes[0]
        #expect(node.cluster.title == title)
        #expect(node.shortTitle == "One two seven")
        #expect(node.titleLines.joined(separator: " ") == node.shortTitle)
        snapshot.clusters[id]?.title = "Digital Entrepreneurship Class Important Dates"
        let longWord = ProjectGraphMap(snapshot: snapshot).nodes[0]
        #expect(longWord.shortTitle == "Digital Entrepreneurship Dates")
        #expect(longWord.titleLines.contains("Entrepreneurship"))
        #expect(longWord.titleLines.count <= 3)
        snapshot.clusters[id]?.title = "abcdefgh abcdefgh abcdefgh abcdefgh abcdefgh"
        let fiveWords = ProjectGraphMap(snapshot: snapshot).nodes[0]
        #expect(fiveWords.titleLines.count <= 3)
        #expect(fiveWords.titleLines.joined(separator: " ") == fiveWords.shortTitle)
    }

    @Test func compactMapLabelsKeepQualifiersAndNeverCutWords() {
        #expect(ProjectGraphLabel(title: "Digital Entrepreneurship Class Important Dates").text == "Digital Entrepreneurship Dates")
        #expect(ProjectGraphLabel(title: "Digital Entrepreneurship Class Important Assignments").text == "Digital Entrepreneurship Assignments")
        #expect(ProjectGraphLabel(title: "Best Use of Gemma for Gemini Hackathon").text == "Gemma Gemini Hackathon")
        #expect(ProjectGraphLabel(title: "Application Submission Confirmation").text == "Application Submission Confirmation")
        #expect(ProjectGraphLabel(title: "  My\n travel  plans ").text == "My travel plans")
        #expect(ProjectGraphLabel(title: "").text == "Untitled thread")
        #expect(ProjectGraphLabel(title: "研究計画").text == "研究計画")
        let longWord = "Supercalifragilisticexpialidocious"
        #expect(ProjectGraphLabel(title: longWord).text == longWord)
        for title in ["one two three four five", "Greeting and Recording Intent", "Judging Criteria for Hackathon"] {
            let label = ProjectGraphLabel(title: title)
            #expect(label.words.count <= 3)
            #expect(label.lines.count <= 3)
            #expect(!label.text.contains("…"))
            #expect(label.words.allSatisfy { title.split(separator: " ").contains(Substring($0)) })
        }
    }

    @Test func mapPanIsBoundedAndResetIsCentered() {
        let size = CGSize(width: 368, height: 440)
        let viewport = CGSize(width: 343, height: 420)
        #expect(ProjectGraphLayout.boundedPan(.zero, content: size, viewport: viewport, scale: 1) == .zero)
        let pan = ProjectGraphLayout.boundedPan(CGSize(width: 10000, height: -10000), content: size, viewport: viewport, scale: 1)
        #expect(pan.width == 112 && pan.height == -148)
    }

    @Test func mapShowsOnlyEvidenceBasedConnectionsAndExcludesArchivedSources() {
        var snapshot = makeSnapshot(count: 3)
        let ids = snapshot.activeClusters.map(\.id)
        #expect(ProjectGraphMap(snapshot: snapshot).edges.isEmpty)
        snapshot.memories[ids[0]]?.setTags(["Design", "iOS"])
        snapshot.memories[ids[1]]?.setTags(["design", "ios"])
        var map = ProjectGraphMap(snapshot: snapshot)
        #expect(map.edges == [.init(first: 0, second: 1)])
        #expect(map.isConnected(ids[0], to: ids[1]))
        #expect(!map.isConnected(ids[0], to: ids[2]))
        snapshot.memberships[ids[2]] = [ids[0], ids[2]]
        map = ProjectGraphMap(snapshot: snapshot)
        #expect(map.edges.contains(.init(first: 0, second: 2)))
        snapshot.memories[ids[2]]?.isArchived = true
        #expect(ProjectGraphMap(snapshot: snapshot).nodes.count == 2)
    }

    @Test func mapBoundsLargeLibrariesWithoutHidingTotalCount() {
        let map = ProjectGraphMap(snapshot: makeSnapshot(count: 45))
        #expect(map.nodes.count == 40)
        #expect(map.totalCount == 45)
        #expect(map.edges.isEmpty)
    }

    private func makeSnapshot(count: Int) -> ProvenanceSnapshot {
        var snapshot = ProvenanceSnapshot()
        for index in 0..<count {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
            let date = Date(timeIntervalSince1970: Double(index))
            snapshot.clusters[id] = ProvenanceCluster(id: id, title: String(format: "Thread %02d", index))
            snapshot.memories[id] = MemoryItem(id: id, kind: .text, createdAt: date, importedAt: date, updatedAt: date,
                state: .indexed, originalFilename: "fixture.txt", title: "Source \(index)", tagsJSON: "[]")
            snapshot.memberships[id] = [id]
        }
        return snapshot
    }
}
