import Foundation
import CoreGraphics
import Testing
@testable import Remember

struct GraphInteractionTests {
    @Test func mapDepthBringsTheCenterForwardAndTracksPanning() {
        let layout = ProjectGraphLayout(memberCounts: [1, 1, 1, 1, 1, 1])
        let viewport = CGSize(width: 370, height: 460)
        let scale = ProjectGraphLayout.browsingScale(in: viewport)
        let initial = ProjectGraphProjection(layout: layout, viewport: viewport, scale: scale, pan: .zero,
            focusedIndex: nil, reduceMotion: false)
        let center = CGPoint(x: viewport.width / 2, y: (viewport.height - 40) / 2)
        let offset = CGSize(width: center.x - initial.nodes[0].center.x, height: center.y - initial.nodes[0].center.y)
        let centered = ProjectGraphProjection(layout: layout, viewport: viewport, scale: scale, pan: offset,
            focusedIndex: nil, reduceMotion: false)
        #expect(centered.nodes[0].diameter > initial.nodes[0].diameter)
        #expect(abs(centered.nodes[0].scale - scale * 1.04) < 0.00001)
        #expect(centered.hitTest(center) == 0)
        #expect(centered.hitTest(CGPoint(x: -10000, y: -10000)) == nil)
    }

    @Test func mapFocusLiftsTheNodeAndMakesRoomWithoutMovingSavedPositions() {
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
        #expect(after > before && after - before <= 7)
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
            for node in overview.nodes {
                let desired = CGSize(width: center.x - node.center.x, height: center.y - node.center.y)
                #expect(ProjectGraphLayout.boundedPan(desired, content: layout.size, viewport: viewport, scale: scale) == desired)
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
        #expect(node.shortTitle == "One two three four five…")
        #expect(node.titleLines.joined(separator: " ") == node.shortTitle)
        snapshot.clusters[id]?.title = "Digital Entrepreneurship Class Important Dates"
        let longWord = ProjectGraphMap(snapshot: snapshot).nodes[0]
        #expect(longWord.titleLines.contains("Entrepreneurship"))
        #expect(longWord.titleLines.count <= 4)
        snapshot.clusters[id]?.title = "abcdefgh abcdefgh abcdefgh abcdefgh abcdefgh"
        let fiveWords = ProjectGraphMap(snapshot: snapshot).nodes[0]
        #expect(fiveWords.titleLines.count <= 4)
        #expect(fiveWords.titleLines.joined(separator: " ") == fiveWords.shortTitle)
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
