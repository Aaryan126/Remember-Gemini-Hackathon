import Darwin
import Foundation
import FoundationModels
import NaturalLanguage
import SwiftUI

@main
struct EmbeddingProbeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Testing local embeddings with synthetic notes…")
                .padding()
                .task {
                    let report = await EmbeddingProbe().run()
                    print("EMBEDDING_PROBE_RESULT " + report)
                    fflush(stdout)
                    exit(0)
                }
        }
    }
}

actor EmbeddingProbe {
    struct Sample {
        let id: String
        let topic: String
        let text: String
    }
    enum ProbeError: Error { case missingModel, missingAssets, missingVector(String) }

    func run() async -> String {
        var report: [String: Any] = [
            "deviceOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "foundationModels": String(describing: SystemLanguageModel.default.availability),
            "policy": ProjectMath.policy,
            "syntheticInputsOnly": true
        ]
        do {
            guard let model = NLEmbedding.sentenceEmbedding(for: .english) else { throw ProbeError.missingModel }
            report["modelIdentifier"] = "apple-contextual-and-sentence-en"
            report["revision"] = model.revision
            report["dimension"] = model.dimension
            report["maximumChunkCharacters"] = 256
            let samples = [
                Sample(id: "calculus-note", topic: "calculus", text: "Calculus revision: the derivative gives the slope of a curve. Use the chain rule to differentiate composite functions."),
                Sample(id: "calculus-transcript", topic: "calculus", text: "In today's calculus lecture we learned how derivatives describe rates of change and practiced the chain rule for nested functions."),
                Sample(id: "calculus-ocr", topic: "calculus", text: "DIFFERENTIATION WORKSHEET. Find the derivative of each composite function. Show the chain rule and calculate the tangent slope."),
                Sample(id: "bread-note", topic: "bread", text: "Sourdough baking: feed the starter with flour and water, mix the dough, allow it to ferment, then bake in a hot oven."),
                Sample(id: "bread-transcript", topic: "bread", text: "For tomorrow's sourdough loaf, refresh the starter tonight. Knead the bread dough and leave it to rise before baking."),
                Sample(id: "bread-ocr", topic: "bread", text: "BREAD RECIPE. Mix flour, water, salt and active sourdough starter. Bulk ferment the dough and bake the loaf until golden."),
                Sample(id: "ios-note", topic: "ios", text: "SwiftUI development: use State to manage local view data and bindings to update a child view. NavigationStack controls screen navigation."),
                Sample(id: "ios-transcript", topic: "ios", text: "The iPhone app uses SwiftUI. We fixed a view state bug by passing a binding to the child screen inside the navigation stack."),
                Sample(id: "ios-ocr", topic: "ios", text: "SWIFTUI NOTES. State stores view data. Binding shares mutable values with child views. Use NavigationStack for navigation."),
                Sample(id: "travel-note", topic: "travel", text: "Japan holiday itinerary: take the train from Tokyo to Kyoto, visit the temples, and book a hotel near Kyoto station."),
                Sample(id: "travel-transcript", topic: "travel", text: "Let's plan our trip to Japan. After Tokyo we'll catch the train to Kyoto and stay near the station so we can explore the temples."),
                Sample(id: "travel-ocr", topic: "travel", text: "JAPAN TRAVEL PLAN. Tokyo to Kyoto by rail. Reserve a hotel by the railway station. Spend two days visiting temples."),
                // Held-out topics fixed before running the v2 provider.
                Sample(id: "astronomy-note", topic: "astronomy", text: "Saturn's rings consist of icy particles orbiting the planet. A telescope can reveal the rings and some of Saturn's moons."),
                Sample(id: "astronomy-transcript", topic: "astronomy", text: "Tonight we observed Saturn through the telescope. We could see the planet's bright rings and its largest moon, Titan."),
                Sample(id: "astronomy-ocr", topic: "astronomy", text: "SATURN OBSERVATION LOG. Telescope view shows icy rings around the planet and several orbiting moons."),
                Sample(id: "sql-note", topic: "sql", text: "PostgreSQL query optimization: create an index on the customer identifier to avoid scanning every row when finding a customer's orders."),
                Sample(id: "sql-transcript", topic: "sql", text: "The database query was slow because it scanned the entire orders table. Adding an index on customer_id improved the PostgreSQL query plan."),
                Sample(id: "sql-ocr", topic: "sql", text: "DATABASE PERFORMANCE. EXPLAIN ANALYZE shows a sequential table scan. Add a customer_id index to speed up order lookups in PostgreSQL."),
                Sample(id: "running-note", topic: "running", text: "Marathon training plan: gradually increase weekly running mileage and keep the Sunday long run at an easy conversational pace."),
                Sample(id: "running-transcript", topic: "running", text: "I'm preparing for a marathon. This week's schedule includes an easy long run on Sunday and a gradual increase in total distance."),
                Sample(id: "running-ocr", topic: "running", text: "MARATHON SCHEDULE. Easy-paced Sunday long run. Increase weekly mileage gradually and allow recovery between hard runs."),
                Sample(id: "guitar-note", topic: "guitar", text: "Guitar practice: switch smoothly between the G, C and D chords while keeping a steady strumming rhythm."),
                Sample(id: "guitar-transcript", topic: "guitar", text: "During my guitar lesson we practiced changing from G major to C major and D major without interrupting the strumming pattern."),
                Sample(id: "guitar-ocr", topic: "guitar", text: "GUITAR EXERCISE. Practice G-C-D chord changes. Maintain a regular strumming rhythm and clean finger placement."),
                Sample(id: "garden-note", topic: "garden", text: "Tomato seedlings need strong sunlight, regular watering and support stakes. Move the young plants into the vegetable garden after the last frost."),
                Sample(id: "garden-transcript", topic: "garden", text: "We are planting tomatoes in the garden this spring. Give the seedlings plenty of sun, water them regularly and tie the stems to stakes."),
                Sample(id: "garden-ocr", topic: "garden", text: "TOMATO GROWING GUIDE. Transplant seedlings after frost. Use stakes for support, water consistently and choose a sunny vegetable bed."),
                Sample(id: "sewing-note", topic: "sewing", text: "Sewing a cotton shirt: cut the fabric using the paper pattern, pin the pieces together and stitch the seams with a sewing machine."),
                Sample(id: "sewing-transcript", topic: "sewing", text: "In sewing class we made a shirt. First we cut cotton fabric from a pattern, then pinned the sections and machine-stitched the seams."),
                Sample(id: "sewing-ocr", topic: "sewing", text: "SHIRT SEWING INSTRUCTIONS. Trace the pattern onto cotton fabric. Cut and pin the pieces, then sew the seams by machine."),
                // Final holdout: not used to select the dual-v4 thresholds.
                Sample(id: "camera-note", topic: "camera", text: "Photography exposure practice: a wider aperture admits more light and reduces depth of field. Balance shutter speed and ISO for a sharp image."),
                Sample(id: "camera-transcript", topic: "camera", text: "In photography class we adjusted aperture, shutter speed and ISO. Opening the lens aperture brightens the exposure but blurs more of the background."),
                Sample(id: "camera-ocr", topic: "camera", text: "CAMERA EXPOSURE TRIANGLE. Aperture controls light and depth of field. Adjust shutter speed and ISO to expose the photograph correctly."),
                Sample(id: "chemistry-note", topic: "chemistry", text: "Acid-base titration experiment: slowly add sodium hydroxide to hydrochloric acid until the indicator changes color at the neutralization endpoint."),
                Sample(id: "chemistry-transcript", topic: "chemistry", text: "Our chemistry lab measured an acid concentration by titration. We added sodium hydroxide from the burette and watched for the indicator's endpoint color."),
                Sample(id: "chemistry-ocr", topic: "chemistry", text: "TITRATION LAB. Neutralize hydrochloric acid with sodium hydroxide. Record the burette volume when the indicator changes colour."),
                Sample(id: "french-note", topic: "french", text: "French grammar revision: conjugate regular verbs ending in -er in the present tense. Je parle, tu parles, il parle, nous parlons."),
                Sample(id: "french-transcript", topic: "french", text: "Today's French lesson covered present-tense endings for regular -er verbs. We practiced conjugating parler for each subject pronoun."),
                Sample(id: "french-ocr", topic: "french", text: "FRENCH VERB PRACTICE. Present tense of regular -er verbs: parler, je parle, tu parles, nous parlons, vous parlez."),
                Sample(id: "bicycle-note", topic: "bicycle", text: "Bicycle repair: fix a punctured inner tube by removing the wheel and tire, locating the hole, applying a patch and reinflating the tube."),
                Sample(id: "bicycle-transcript", topic: "bicycle", text: "My bicycle had a flat tire. I took the wheel off, pulled out the inner tube, patched the puncture and pumped it up again."),
                Sample(id: "bicycle-ocr", topic: "bicycle", text: "BIKE PUNCTURE REPAIR. Remove the tire and inner tube. Find the leak, attach a patch, replace the tube and inflate the tire.")
            ]
            let provider = AppleProjectEmbedding()
            var vectors: [ProjectEmbedding] = []
            var timings: [Double] = []
            var unavailable: [String] = []
            var checks: [String: Bool] = [:]
            for sample in samples {
                let started = ContinuousClock.now
                guard let value = try await provider.embedding(for: sample.text) else {
                    unavailable.append(sample.id)
                    vectors.append(ProjectEmbedding(vector: [], space: "unavailable"))
                    timings.append(0)
                    continue
                }
                let elapsed = started.duration(to: .now)
                let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
                vectors.append(value)
                timings.append(milliseconds)
                let norm = sqrt(value.vector.reduce(0.0) { $0 + Double($1) * Double($1) })
                checks[sample.id + "-valid"] = value.vector.count == model.dimension && value.vector.allSatisfy(\.isFinite) && abs(norm - 1) < 0.00001
                checks[sample.id + "-space"] = await provider.expectedSpace(for: sample.text) == value.space
                print("EMBEDDING_PROBE sample=\(sample.id) milliseconds=\(milliseconds)")
            }
            report["space"] = vectors[0].space
            report["unavailableSamples"] = unavailable
            let fixtures: [[String: Any]] = zip(samples, vectors).map { sample, embedding in
                ["id": sample.id, "topic": sample.topic, "text": sample.text, "space": embedding.space,
                 "vector": embedding.vector, "semanticVector": embedding.semanticVector ?? []]
            }
            try JSONSerialization.data(withJSONObject: fixtures, options: [.sortedKeys])
                .write(to: URL.documentsDirectory.appendingPathComponent("embedding-fixtures.json"), options: .atomic)
            report["sampleIDs"] = samples.map(\.id)
            report["embeddingMilliseconds"] = timings
            var related: [Double] = []
            var unrelated: [Double] = []
            var matrix: [[Double]] = []
            var nearestMatches = 0
            for i in samples.indices {
                let scores = vectors.map { $0.space == vectors[i].space ? ProjectMath.cosine(vectors[i].vector, $0.vector) : -1 }
                matrix.append(scores)
                guard !vectors[i].vector.isEmpty else { continue }
                let nearest = samples.indices.filter { $0 != i }.max { scores[$0] < scores[$1] }!
                if samples[i].topic == samples[nearest].topic { nearestMatches += 1 }
                for j in samples.indices where j > i {
                    guard !vectors[j].vector.isEmpty, vectors[i].space == vectors[j].space else { continue }
                    if samples[i].topic == samples[j].topic { related.append(scores[j]) }
                    else { unrelated.append(scores[j]) }
                }
            }
            report["cosineMatrix"] = matrix
            report["sameTopicRange"] = [related.min()!, related.max()!]
            report["differentTopicRange"] = [unrelated.min()!, unrelated.max()!]
            report["nearestNeighborSameTopic"] = nearestMatches
            report["differentTopicPairsAtPlacementThreshold"] = unrelated.filter { $0 >= ProjectMath.placementThreshold }.count
            report["differentTopicPairsAtMergeThreshold"] = unrelated.filter { $0 >= ProjectMath.mergeThreshold }.count
            report["differentTopicPairCount"] = unrelated.count
            var unsafePairMatches = 0
            let topicEvidence = samples.map { ProjectTopicEvidence($0.text) }
            var semanticMatrix: [[Double]] = []
            for i in samples.indices {
                semanticMatrix.append(vectors.map { ProjectMath.semanticScore(vectors[i], members: [$0]) })
                for j in samples.indices where j > i && samples[i].topic != samples[j].topic {
                    if ProjectMath.cosine(vectors[i].vector, vectors[j].vector) >= ProjectMath.placementThreshold
                        && ProjectMath.semanticScore(vectors[i], members: [vectors[j]]) >= ProjectMath.semanticThreshold
                        && topicEvidence[i].supports(topicEvidence[j]) {
                        unsafePairMatches += 1
                    }
                }
            }
            report["semanticCosineMatrix"] = semanticMatrix
            report["differentTopicPairsPassingBothSignals"] = unsafePairMatches
            // Raw ranking is a diagnostic, not the policy: grounded matching must
            // reject false neighbors even when embeddings rank them highly.
            report["rawNearestNeighborErrors"] = samples.count - unavailable.count - nearestMatches
            checks["unrelatedPairSafetyAtPlacementThreshold"] = unsafePairMatches == 0
            checks["unrelatedPairSafetyAtMergeThreshold"] = unsafePairMatches == 0
            guard let repeated = try await provider.embedding(for: samples[0].text) else { throw ProbeError.missingVector("repeat") }
            report["repeatCosine"] = ProjectMath.cosine(vectors[0].vector, repeated.vector)
            checks["repeatStable"] = ProjectMath.cosine(vectors[0].vector, repeated.vector) > 0.99999
            checks["emptyReturnsNil"] = try await provider.embedding(for: " \n\t") == nil
            let longText = Array(repeating: samples[0].text, count: 20).joined(separator: "\n")
            let longStarted = ContinuousClock.now
            guard let long = try await provider.embedding(for: longText) else { throw ProbeError.missingVector("long") }
            let duration = longStarted.duration(to: .now)
            report["longInputCharacters"] = longText.count
            report["longInputMilliseconds"] = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
            report["longInputCosineToShort"] = ProjectMath.cosine(long.vector, vectors[0].vector)
            checks["longInputValid"] = long.vector.count == model.dimension && long.vector.allSatisfy(\.isFinite)
            report["checks"] = checks
            report["status"] = checks.values.allSatisfy { $0 } ? "passed" : "quality_checks_failed"
            // Exercise the actual graph and ledger with a separate disposable database.
            // No ContentView, capture pipeline, live store, or cloud reasoner is launched.
            var graphRuns: [[String: Any]] = []
            let baseline = Array(0..<12)
            let heldOut = Array(12..<30)
            let finalHoldout = Array(30..<samples.count)
            let interleaved = (0..<3).flatMap { offset in stride(from: offset, to: samples.count, by: 3) }
            let orders = [baseline, [0, 3, 6, 9, 1, 4, 7, 10, 2, 5, 8, 11],
                          heldOut, Array(heldOut.reversed()), Array(samples.indices), interleaved,
                          Array(interleaved.reversed()), finalHoldout, Array(finalHoldout.reversed())]
            for order in orders {
                let root = URL.temporaryDirectory.appendingPathComponent("EmbeddingGraph-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: root) }
                let store = try MemoryStore(databaseURL: root.appendingPathComponent("test.sqlite"))
                let graph = ProjectGraphService(store: store, embeddings: provider, reasoner: ProbeNoReasoning())
                var sampleIDs: [UUID: String] = [:]
                var topics: [UUID: String] = [:]
                for (offset, index) in order.enumerated() {
                    let sample = samples[index]
                    let date = Date(timeIntervalSince1970: 1_800_000_000 + Double(offset))
                    let item = MemoryItem(id: UUID(), kind: .text, createdAt: date, importedAt: date, updatedAt: date,
                        state: .captured, originalFilename: UUID().uuidString + ".txt", userCaption: sample.id,
                        title: sample.id, summary: nil, extractedText: nil, tagsJSON: "[]", processingError: nil, modelVersion: nil)
                    sampleIDs[item.id] = sample.id
                    topics[item.id] = sample.topic
                    try await store.insertIfNeeded(item)
                    try await store.markIndexed(id: item.id, analysis: MemoryAnalysisResult(title: sample.id,
                        summary: sample.text, tags: [], extractedText: sample.text, modelVersion: "synthetic-device-probe"))
                    try await graph.synchronize()
                }
                let events = try await store.provenanceEvents()
                let snapshot = try ProvenanceSnapshot.replay(events)
                let groups = snapshot.activeClusters.map { cluster in
                    snapshot.members(of: cluster.id).compactMap { sampleIDs[$0.id] }.sorted()
                }.sorted { $0.joined() < $1.joined() }
                let mixed = snapshot.activeClusters.filter { cluster in
                    Set(snapshot.members(of: cluster.id).compactMap { topics[$0.id] }).count > 1
                }.count
                let countBefore = events.count
                try await graph.synchronize()
                graphRuns.append([
                    "inputOrder": order.map { samples[$0].id },
                    "clusters": groups,
                    "mixedTopicClusters": mixed,
                    "unavailableSourcesRemainSingletons": unavailable.filter { id in order.contains { samples[$0].id == id } }
                        .allSatisfy { id in groups.contains([id]) },
                    "repeatSynchronizationAddsNoEvents": try await store.provenanceEvents().count == countBefore,
                    "placementVectorCount": try events.filter { try $0.kind == .placement && $0.payload().vector != nil }.count,
                    "mergeEvents": events.filter { $0.kind == .merge }.count
                ])
            }
            report["actualGraphRunsWithoutReasoning"] = graphRuns
            checks["allGraphOrdersAvoidMixedTopics"] = graphRuns.allSatisfy { ($0["mixedTopicClusters"] as? Int) == 0 }
            checks["unavailableSourcesRemainSingletons"] = graphRuns.allSatisfy { ($0["unavailableSourcesRemainSingletons"] as? Bool) == true }
            checks["graphActuallyGroupsRelatedNotes"] = graphRuns.allSatisfy {
                guard let groups = $0["clusters"] as? [[String]], let order = $0["inputOrder"] as? [String] else { return false }
                return groups.count <= Int(ceil(Double(order.count) * 0.75))
            }
            report["checks"] = checks
            report["status"] = checks.values.allSatisfy { $0 } ? "passed" : "quality_checks_failed"
            // Diagnostic comparison only. This does not change the production provider.
            if let sentenceModel = NLEmbedding.sentenceEmbedding(for: .english) {
                let sentenceVectors = samples.compactMap { sentenceModel.vector(for: $0.text)?.map(Float.init) }
                if sentenceVectors.count == samples.count {
                    var sentenceRelated: [Double] = []
                    var sentenceUnrelated: [Double] = []
                    for i in samples.indices {
                        for j in samples.indices where j > i {
                            let score = ProjectMath.cosine(sentenceVectors[i], sentenceVectors[j])
                            if samples[i].topic == samples[j].topic { sentenceRelated.append(score) }
                            else { sentenceUnrelated.append(score) }
                        }
                    }
                    report["sentenceEmbeddingComparison"] = [
                        "dimension": sentenceModel.dimension,
                        "sameTopicRange": [sentenceRelated.min()!, sentenceRelated.max()!],
                        "differentTopicRange": [sentenceUnrelated.min()!, sentenceUnrelated.max()!]
                    ]
                }
            }
        } catch {
            report["status"] = "error"
            report["error"] = String(describing: error)
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            let url = URL.documentsDirectory.appendingPathComponent("embedding-probe.json")
            try data.write(to: url, options: .atomic)
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "{\"status\":\"report_write_failed\"}"
        }
    }
}

private actor ProbeNoReasoning: ProjectReasoning {
    func decide(source: String, candidates: [(id: UUID, title: String, summary: String)]) async throws -> ProjectReasoningResult? { nil }
}
