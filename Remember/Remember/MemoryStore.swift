import Foundation
import GRDB

actor MemoryStore {
    private let databasePool: DatabasePool

    init(databaseURL: URL, fileManager: FileManager = .default) throws {
        let directoryURL = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: Self.protectedAttributes
        )

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.label = "RememberMemoryStore"
        databasePool = try DatabasePool(path: databaseURL.path, configuration: configuration)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("createMemory") { database in
            try database.create(table: MemoryItem.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("kind", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("importedAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("state", .text).notNull().indexed()
                table.column("originalFilename", .text).notNull()
                table.column("userCaption", .text)
                table.column("title", .text)
                table.column("summary", .text)
                table.column("extractedText", .text)
                table.column("tagsJSON", .text).notNull().defaults(to: "[]")
                table.column("processingError", .text)
                table.column("modelVersion", .text)
            }
            try database.create(
                index: "memoryByCreatedAt",
                on: MemoryItem.databaseTableName,
                columns: ["createdAt"]
            )
        }
        migrator.registerMigration("createMemorySearchIndex") { database in
            try database.create(table: MemorySearchIndexRecord.databaseTableName) { table in
                table.column("memoryID", .text)
                    .primaryKey()
                    .references(MemoryItem.databaseTableName, onDelete: .cascade)
                table.column("sourceUpdatedAt", .datetime).notNull()
                table.column("searchText", .text).notNull()
                table.column("embeddingData", .blob)
                table.column("embeddingModel", .text).notNull()
            }
        }
        migrator.registerMigration("createLocalAIActivity") { database in
            try database.create(table: LocalAIActivity.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("kind", .text).notNull().indexed()
                table.column("startedAt", .datetime).notNull().indexed()
                table.column("finishedAt", .datetime)
                table.column("status", .text).notNull().indexed()
                table.column("memoryID", .text)
                    .references(MemoryItem.databaseTableName, onDelete: .setNull)
                table.column("sourceCount", .integer).notNull().defaults(to: 0)
                table.column("modelVersion", .text).notNull()
                table.column("failureCategory", .text)
            }
        }
        migrator.registerMigration("createCollections") { database in
            try database.create(table: MemoryCollection.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try database.create(
                index: "collectionNameUnique",
                on: MemoryCollection.databaseTableName,
                columns: ["name"],
                options: [.unique]
            )
            try database.create(table: MemoryCollectionMembership.databaseTableName) { table in
                table.column("collectionID", .text)
                    .notNull()
                    .references(MemoryCollection.databaseTableName, onDelete: .cascade)
                table.column("memoryID", .text)
                    .notNull()
                    .references(MemoryItem.databaseTableName, onDelete: .cascade)
                table.column("addedAt", .datetime).notNull()
                table.primaryKey(["collectionID", "memoryID"])
            }
            try database.create(
                index: "collectionMembershipByMemory",
                on: MemoryCollectionMembership.databaseTableName,
                columns: ["memoryID"]
            )
        }
        migrator.registerMigration("createLivingWiki") { database in
            try database.create(table: WikiPage.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("kind", .text).notNull().indexed()
                table.column("title", .text).notNull()
                table.column("normalizedTitle", .text).notNull()
                table.column("summary", .text).notNull()
                table.column("aliasesJSON", .text).notNull().defaults(to: "[]")
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull().indexed()
                table.column("revisionNumber", .integer).notNull().defaults(to: 1)
                table.uniqueKey(["kind", "normalizedTitle"])
            }
            try database.create(table: WikiEvidence.databaseTableName) { table in
                table.column("pageID", .text)
                    .notNull()
                    .references(WikiPage.databaseTableName, onDelete: .cascade)
                table.column("memoryID", .text)
                    .notNull()
                    .references(MemoryItem.databaseTableName, onDelete: .cascade)
                table.column("effect", .text).notNull()
                table.column("rationale", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.primaryKey(["pageID", "memoryID"])
            }
            try database.create(
                index: "wikiEvidenceByMemory",
                on: WikiEvidence.databaseTableName,
                columns: ["memoryID"]
            )
            try database.create(table: WikiPageLink.databaseTableName) { table in
                table.column("sourcePageID", .text)
                    .notNull()
                    .references(WikiPage.databaseTableName, onDelete: .cascade)
                table.column("targetPageID", .text)
                    .notNull()
                    .references(WikiPage.databaseTableName, onDelete: .cascade)
                table.column("rationale", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.primaryKey(["sourcePageID", "targetPageID"])
            }
            try database.create(table: WikiRevision.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("pageID", .text)
                    .notNull()
                    .references(WikiPage.databaseTableName, onDelete: .cascade)
                table.column("memoryID", .text)
                    .references(MemoryItem.databaseTableName, onDelete: .setNull)
                table.column("revisionNumber", .integer).notNull()
                table.column("effect", .text).notNull()
                table.column("previousSummary", .text)
                table.column("newSummary", .text).notNull()
                table.column("rationale", .text).notNull()
                table.column("createdAt", .datetime).notNull().indexed()
                table.column("modelVersion", .text).notNull()
            }
            try database.create(
                index: "wikiRevisionByPageVersion",
                on: WikiRevision.databaseTableName,
                columns: ["pageID", "revisionNumber"]
            )
            try database.create(table: WikiCompilation.databaseTableName) { table in
                table.column("memoryID", .text)
                    .primaryKey()
                    .references(MemoryItem.databaseTableName, onDelete: .cascade)
                table.column("sourceUpdatedAt", .datetime).notNull()
                table.column("status", .text).notNull().indexed()
                table.column("attemptedAt", .datetime)
                table.column("completedAt", .datetime)
                table.column("errorMessage", .text)
                table.column("modelVersion", .text)
            }
        }
        migrator.registerMigration("createWikiPageSearchIndex") { database in
            try database.create(table: WikiPageSearchIndexRecord.databaseTableName) { table in
                table.column("pageID", .text)
                    .primaryKey()
                    .references(WikiPage.databaseTableName, onDelete: .cascade)
                table.column("sourceUpdatedAt", .datetime).notNull()
                table.column("searchText", .text).notNull()
                table.column("embeddingData", .blob)
                table.column("embeddingModel", .text).notNull()
            }
        }
        migrator.registerMigration("createProjectMemoryResearchHistory") { database in
            try database.create(table: ProjectMemoryRun.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("operation", .text).notNull().indexed()
                table.column("memoryID", .text)
                    .references(MemoryItem.databaseTableName, onDelete: .setNull)
                table.column("startedAt", .datetime).notNull().indexed()
                table.column("completedAt", .datetime)
                table.column("status", .text).notNull().indexed()
                table.column("modelVersion", .text).notNull()
                table.column("promptVersion", .text).notNull()
                table.column("programVersion", .text).notNull()
                table.column("proposedPageCount", .integer).notNull().defaults(to: 0)
                table.column("acceptedPageCount", .integer).notNull().defaults(to: 0)
                table.column("rationale", .text).notNull().defaults(to: "")
            }
            try database.create(table: ProjectMemoryCheck.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("runID", .text)
                    .notNull()
                    .indexed()
                    .references(ProjectMemoryRun.databaseTableName, onDelete: .cascade)
                table.column("checkID", .text).notNull()
                table.column("label", .text).notNull()
                table.column("severity", .text).notNull()
                table.column("passed", .boolean).notNull()
                table.column("message", .text).notNull()
                table.uniqueKey(["runID", "checkID"])
            }
            try database.alter(table: WikiRevision.databaseTableName) { table in
                table.add(column: "runID", .text)
                    .references(ProjectMemoryRun.databaseTableName, onDelete: .setNull)
            }
            try database.create(
                index: "wikiRevisionByRun",
                on: WikiRevision.databaseTableName,
                columns: ["runID"]
            )
        }
        try migrator.migrate(databasePool)
        try fileManager.setAttributes(Self.protectedAttributes, ofItemAtPath: databaseURL.path)
    }

    func contains(id: UUID) async throws -> Bool {
        try await databasePool.read { database in
            try MemoryItem.fetchOne(database, key: id) != nil
        }
    }

    func insertIfNeeded(_ item: MemoryItem) async throws {
        try await databasePool.write { database in
            guard try MemoryItem.fetchOne(database, key: item.id) == nil else {
                return
            }
            try item.insert(database)
        }
    }

    func fetchAll() async throws -> [MemoryItem] {
        try await databasePool.read { database in
            try MemoryItem
                .order(Column("createdAt").desc)
                .fetchAll(database)
        }
    }

    func fetchIndexed() async throws -> [MemoryItem] {
        try await databasePool.read { database in
            try MemoryItem
                .filter(Column("state") == MemoryProcessingState.indexed)
                .order(Column("createdAt").desc)
                .fetchAll(database)
        }
    }

    func fetchSearchIndexRecords() async throws -> [MemorySearchIndexRecord] {
        try await databasePool.read { database in
            try MemorySearchIndexRecord.fetchAll(database)
        }
    }

    func saveSearchIndexRecord(_ record: MemorySearchIndexRecord) async throws {
        try await databasePool.write { database in
            try record.save(database)
        }
    }

    func startActivity(
        kind: LocalAIActivityKind,
        memoryID: UUID? = nil,
        sourceCount: Int = 0,
        modelVersion: String = GemmaMemoryAnalyzer.modelVersion
    ) async throws -> UUID {
        let activity = LocalAIActivity(
            id: UUID(),
            kind: kind,
            startedAt: Date(),
            finishedAt: nil,
            status: .running,
            memoryID: memoryID,
            sourceCount: max(0, sourceCount),
            modelVersion: modelVersion,
            failureCategory: nil
        )
        try await databasePool.write { database in
            try activity.insert(database)
        }
        return activity.id
    }

    func finishActivity(
        id: UUID,
        status: LocalAIActivityStatus,
        sourceCount: Int? = nil,
        failureCategory: String? = nil
    ) async throws {
        try await databasePool.write { database in
            guard var activity = try LocalAIActivity.fetchOne(database, key: id) else {
                return
            }
            activity.finishedAt = Date()
            activity.status = status
            if let sourceCount {
                activity.sourceCount = max(0, sourceCount)
            }
            activity.failureCategory = failureCategory.map { String($0.prefix(80)) }
            try activity.update(database)
        }
    }

    func recoverInterruptedActivities() async throws {
        try await databasePool.write { database in
            try database.execute(
                sql: """
                    UPDATE localAIActivity
                    SET status = ?, finishedAt = ?, failureCategory = ?
                    WHERE status = ?
                    """,
                arguments: [
                    LocalAIActivityStatus.interrupted.rawValue,
                    Date(),
                    "process_interrupted",
                    LocalAIActivityStatus.running.rawValue,
                ]
            )
        }
    }

    func fetchActivities(limit: Int = 100) async throws -> [LocalAIActivity] {
        try await databasePool.read { database in
            try LocalAIActivity
                .order(Column("startedAt").desc)
                .limit(max(1, min(limit, 500)))
                .fetchAll(database)
        }
    }

    func recoverInterruptedProjectMemoryRuns() async throws {
        try await databasePool.write { database in
            try database.execute(
                sql: """
                    UPDATE projectMemoryRun
                    SET status = ?, completedAt = ?, rationale = ?
                    WHERE status = ?
                    """,
                arguments: [
                    ProjectMemoryRunStatus.failed.rawValue,
                    Date(),
                    "The app stopped before this local operation completed.",
                    ProjectMemoryRunStatus.running.rawValue,
                ]
            )
        }
    }

    func startProjectMemoryRun(
        operation: ProjectMemoryRunOperation,
        memoryID: UUID?,
        modelVersion: String,
        promptVersion: String
    ) async throws -> UUID {
        let run = ProjectMemoryRun(
            id: UUID(),
            operation: operation,
            memoryID: memoryID,
            startedAt: Date(),
            completedAt: nil,
            status: .running,
            modelVersion: String(modelVersion.prefix(160)),
            promptVersion: String(promptVersion.prefix(120)),
            programVersion: ProjectMemoryProgram.current.version,
            proposedPageCount: 0,
            acceptedPageCount: 0,
            rationale: ""
        )
        try await databasePool.write { database in
            try run.insert(database)
        }
        return run.id
    }

    func finishProjectMemoryRun(
        id: UUID,
        status: ProjectMemoryRunStatus,
        proposedPageCount: Int,
        acceptedPageCount: Int,
        rationale: String,
        checks: [ProjectMemoryCheckDraft]
    ) async throws {
        try await databasePool.write { database in
            try Self.finishProjectMemoryRunRecord(
                id: id,
                completion: ProjectMemoryRunCompletion(
                    status: status,
                    proposedPageCount: proposedPageCount,
                    acceptedPageCount: acceptedPageCount,
                    rationale: rationale,
                    checks: checks
                ),
                in: database
            )
        }
    }

    func fetchProjectMemoryHistory(limit: Int = 200) async throws -> [ProjectMemoryRunSnapshot] {
        try await databasePool.read { database in
            let runs = try ProjectMemoryRun
                .order(Column("startedAt").desc)
                .limit(max(1, min(limit, 2_000)))
                .fetchAll(database)
            return try runs.map { run in
                let memoryTitle = try run.memoryID
                    .flatMap { try MemoryItem.fetchOne(database, key: $0)?.displayTitle }
                let checks = try ProjectMemoryCheck
                    .filter(Column("runID") == run.id)
                    .order(Column("checkID").asc)
                    .fetchAll(database)
                let revisions = try WikiRevision
                    .filter(Column("runID") == run.id)
                    .order(Column("createdAt").asc)
                    .fetchAll(database)
                let changes = try revisions.compactMap { revision -> ProjectMemoryRevisionChange? in
                    guard let page = try WikiPage.fetchOne(database, key: revision.pageID) else { return nil }
                    return ProjectMemoryRevisionChange(
                        revision: revision,
                        pageTitle: page.title,
                        pageKind: page.kind
                    )
                }
                return ProjectMemoryRunSnapshot(
                    run: run,
                    memoryTitle: memoryTitle,
                    checks: checks,
                    changes: changes
                )
            }
        }
    }

    func fetch(id: UUID) async throws -> MemoryItem? {
        try await databasePool.read { database in
            try MemoryItem.fetchOne(database, key: id)
        }
    }

    func recoverInterruptedProcessing() async throws {
        try await databasePool.write { database in
            try database.execute(
                sql: """
                    UPDATE memory
                    SET state = ?, updatedAt = ?, processingError = NULL
                    WHERE state = ?
                    """,
                arguments: [
                    MemoryProcessingState.captured.rawValue,
                    Date(),
                    MemoryProcessingState.processing.rawValue,
                ]
            )
        }
    }

    func claimNextCaptured() async throws -> MemoryItem? {
        try await databasePool.write { database in
            guard var item = try MemoryItem
                .filter(Column("state") == MemoryProcessingState.captured)
                .order(Column("createdAt").asc)
                .fetchOne(database)
            else {
                return nil
            }
            item.state = .processing
            item.updatedAt = Date()
            item.processingError = nil
            try item.update(database)
            return item
        }
    }

    func markIndexed(id: UUID, analysis: MemoryAnalysisResult) async throws {
        try await update(id: id) { item in
            item.state = .indexed
            item.title = analysis.title
            item.summary = analysis.summary
            item.extractedText = analysis.extractedText
            item.setTags(analysis.tags)
            item.processingError = nil
            item.modelVersion = analysis.modelVersion
        }
    }

    func markFailed(id: UUID, message: String) async throws {
        try await update(id: id) { item in
            item.state = .failed
            item.processingError = String(message.prefix(500))
        }
    }

    func resetToCaptured(id: UUID) async throws {
        try await update(id: id) { item in
            item.state = .captured
            item.processingError = nil
        }
    }

    func updateEditableFields(id: UUID, title: String, summary: String, tags: [String]) async throws {
        try await update(id: id) { item in
            item.title = Self.normalized(title, maximumLength: 120)
            item.summary = Self.normalized(summary, maximumLength: 1_000)
            item.setTags(tags)
        }
    }

    func delete(id: UUID) async throws {
        try await databasePool.write { database in
            _ = try MemoryItem.deleteOne(database, key: id)
        }
    }

    func fetchCollectionSummaries() async throws -> [MemoryCollectionSummary] {
        try await databasePool.read { database in
            let collections = try MemoryCollection
                .order(Column("name").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(database)
            return try collections.map { collection in
                let count = try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM memoryCollectionMembership WHERE collectionID = ?",
                    arguments: [collection.id]
                ) ?? 0
                return MemoryCollectionSummary(collection: collection, memoryCount: count)
            }
        }
    }

    func createCollection(name: String) async throws -> MemoryCollection {
        let normalizedName = try Self.collectionName(name)
        return try await databasePool.write { database in
            guard try !Self.collectionExists(named: normalizedName, in: database) else {
                throw MemoryOrganizationError.duplicateCollectionName
            }
            let now = Date()
            let collection = MemoryCollection(id: UUID(), name: normalizedName, createdAt: now, updatedAt: now)
            try collection.insert(database)
            return collection
        }
    }

    func renameCollection(id: UUID, name: String) async throws {
        let normalizedName = try Self.collectionName(name)
        try await databasePool.write { database in
            guard var collection = try MemoryCollection.fetchOne(database, key: id) else {
                throw MemoryOrganizationError.missingCollection
            }
            let duplicateID = try UUID.fetchOne(
                database,
                sql: "SELECT id FROM memoryCollection WHERE lower(name) = lower(?) AND id <> ? LIMIT 1",
                arguments: [normalizedName, id]
            )
            guard duplicateID == nil else {
                throw MemoryOrganizationError.duplicateCollectionName
            }
            collection.name = normalizedName
            collection.updatedAt = Date()
            try collection.update(database)
        }
    }

    func deleteCollection(id: UUID) async throws {
        try await databasePool.write { database in
            _ = try MemoryCollection.deleteOne(database, key: id)
        }
    }

    func collectionIDs(forMemoryID memoryID: UUID) async throws -> Set<UUID> {
        try await databasePool.read { database in
            let rows = try MemoryCollectionMembership
                .filter(Column("memoryID") == memoryID)
                .fetchAll(database)
            return Set(rows.map(\.collectionID))
        }
    }

    func setMembership(memoryID: UUID, collectionID: UUID, isMember: Bool) async throws {
        try await databasePool.write { database in
            guard try MemoryItem.fetchOne(database, key: memoryID) != nil else {
                throw MemoryStoreError.missingMemory(memoryID)
            }
            guard try MemoryCollection.fetchOne(database, key: collectionID) != nil else {
                throw MemoryOrganizationError.missingCollection
            }
            let key: [String: DatabaseValueConvertible] = [
                "collectionID": collectionID,
                "memoryID": memoryID,
            ]
            if isMember {
                let membership = MemoryCollectionMembership(
                    collectionID: collectionID,
                    memoryID: memoryID,
                    addedAt: Date()
                )
                try membership.insert(database, onConflict: .ignore)
            } else {
                _ = try MemoryCollectionMembership.deleteOne(database, key: key)
            }
        }
    }

    func fetchMemories(inCollectionID collectionID: UUID) async throws -> [MemoryItem] {
        try await databasePool.read { database in
            try MemoryItem.fetchAll(
                database,
                sql: """
                    SELECT memory.*
                    FROM memory
                    JOIN memoryCollectionMembership membership ON membership.memoryID = memory.id
                    WHERE membership.collectionID = ?
                    ORDER BY memory.createdAt DESC
                    """,
                arguments: [collectionID]
            )
        }
    }

    func fetchTagSummaries() async throws -> [MemoryTagSummary] {
        let memories = try await fetchAll()
        var values: [(name: String, count: Int)] = []
        for tag in memories.flatMap(\.tags) {
            if let index = values.firstIndex(where: { $0.name.caseInsensitiveCompare(tag) == .orderedSame }) {
                values[index].count += 1
            } else {
                values.append((tag, 1))
            }
        }
        return values
            .map { MemoryTagSummary(name: $0.name, memoryCount: $0.count) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func renameTag(_ source: String, to target: String) async throws -> [MemoryItem] {
        let normalizedTarget = try Self.tagName(target)
        return try await mutateTag(source) { tags in
            tags.map { $0.caseInsensitiveCompare(source) == .orderedSame ? normalizedTarget : $0 }
        }
    }

    func deleteTag(_ tag: String) async throws -> [MemoryItem] {
        try await mutateTag(tag) { tags in
            tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
        }
    }

    func prepareWikiCompilationQueue() async throws {
        try await databasePool.write { database in
            let memories = try MemoryItem
                .filter(Column("state") == MemoryProcessingState.indexed)
                .fetchAll(database)
            for memory in memories {
                if var compilation = try WikiCompilation.fetchOne(database, key: memory.id) {
                    let failedUnderOlderCompiler = compilation.status == .failed
                        && compilation.modelVersion != GemmaLivingWikiCompiler.modelVersion
                    let discardedNoChangeUnderOlderCompiler = try compilation.status == .compiled
                        && compilation.modelVersion != GemmaLivingWikiCompiler.modelVersion
                        && Self.latestProjectMemoryRunWasDiscardedNoChange(
                            memoryID: memory.id,
                            in: database
                        )
                    guard compilation.sourceUpdatedAt != memory.updatedAt
                            || failedUnderOlderCompiler
                            || discardedNoChangeUnderOlderCompiler,
                          compilation.status != .processing else {
                        continue
                    }
                    compilation.sourceUpdatedAt = memory.updatedAt
                    compilation.status = .pending
                    compilation.attemptedAt = nil
                    compilation.completedAt = nil
                    compilation.errorMessage = nil
                    compilation.modelVersion = nil
                    try compilation.update(database)
                } else {
                    let compilation = WikiCompilation(
                        memoryID: memory.id,
                        sourceUpdatedAt: memory.updatedAt,
                        status: .pending,
                        attemptedAt: nil,
                        completedAt: nil,
                        errorMessage: nil,
                        modelVersion: nil
                    )
                    try compilation.insert(database)
                }
            }
        }
    }

    nonisolated private static func latestProjectMemoryRunWasDiscardedNoChange(
        memoryID: UUID,
        in database: Database
    ) throws -> Bool {
        try Bool.fetchOne(
            database,
            sql: """
                SELECT EXISTS(
                    SELECT 1
                    FROM projectMemoryRun run
                    WHERE run.id = (
                        SELECT run.id
                        FROM projectMemoryRun run
                        WHERE run.memoryID = ? AND run.operation = ?
                        ORDER BY run.startedAt DESC
                        LIMIT 1
                    )
                    AND run.status = ?
                    AND run.acceptedPageCount = 0
                )
                """,
            arguments: [
                memoryID,
                ProjectMemoryRunOperation.compile.rawValue,
                ProjectMemoryRunStatus.discarded.rawValue,
            ]
        ) ?? false
    }

    func recoverInterruptedWikiCompilations() async throws {
        try await databasePool.write { database in
            try database.execute(
                sql: """
                    UPDATE wikiCompilation
                    SET status = ?, attemptedAt = NULL, errorMessage = ?
                    WHERE status = ?
                    """,
                arguments: [
                    WikiCompilationStatus.pending.rawValue,
                    "Previous compilation was interrupted and is ready to retry.",
                    WikiCompilationStatus.processing.rawValue,
                ]
            )
        }
    }

    func claimNextWikiCompilation() async throws -> MemoryItem? {
        try await databasePool.write { database in
            guard let memory = try MemoryItem.fetchOne(
                database,
                sql: """
                    SELECT memory.*
                    FROM memory
                    JOIN wikiCompilation compilation ON compilation.memoryID = memory.id
                    WHERE compilation.status = ? AND memory.state = ?
                    ORDER BY memory.createdAt ASC
                    LIMIT 1
                    """,
                arguments: [WikiCompilationStatus.pending, MemoryProcessingState.indexed]
            ) else {
                return nil
            }
            guard var compilation = try WikiCompilation.fetchOne(database, key: memory.id) else {
                return nil
            }
            compilation.status = .processing
            compilation.attemptedAt = Date()
            compilation.errorMessage = nil
            try compilation.update(database)
            return memory
        }
    }

    func markWikiCompilationFailed(memoryID: UUID, message: String) async throws {
        try await databasePool.write { database in
            guard var compilation = try WikiCompilation.fetchOne(database, key: memoryID) else {
                throw LivingWikiError.missingMemory
            }
            compilation.status = .failed
            compilation.completedAt = Date()
            compilation.errorMessage = String(message.prefix(500))
            compilation.modelVersion = GemmaLivingWikiCompiler.modelVersion
            try compilation.update(database)
        }
    }

    func resetWikiCompilationToPending(memoryID: UUID) async throws {
        try await databasePool.write { database in
            guard var compilation = try WikiCompilation.fetchOne(database, key: memoryID) else {
                return
            }
            compilation.status = .pending
            compilation.attemptedAt = nil
            compilation.completedAt = nil
            compilation.errorMessage = nil
            try compilation.update(database)
        }
    }

    func retryFailedWikiCompilations() async throws {
        try await databasePool.write { database in
            try database.execute(
                sql: """
                    UPDATE wikiCompilation
                    SET status = ?, attemptedAt = NULL, completedAt = NULL, errorMessage = NULL
                    WHERE status = ?
                    """,
                arguments: [WikiCompilationStatus.pending, WikiCompilationStatus.failed]
            )
        }
    }

    func fetchWikiQueueSummary() async throws -> WikiQueueSummary {
        try await databasePool.read { database in
            func count(_ status: WikiCompilationStatus) throws -> Int {
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM wikiCompilation WHERE status = ?",
                    arguments: [status]
                ) ?? 0
            }
            return WikiQueueSummary(
                pending: try count(.pending),
                processing: try count(.processing),
                failed: try count(.failed)
            )
        }
    }

    func fetchWikiPages() async throws -> [WikiPage] {
        try await databasePool.read { database in
            try WikiPage
                .order(Column("updatedAt").desc)
                .fetchAll(database)
        }
    }

    func fetchProjectMemoryLintInput() async throws -> (
        pages: [WikiPage],
        evidence: [WikiEvidence],
        revisions: [WikiRevision],
        links: [WikiPageLink]
    ) {
        try await databasePool.read { database in
            (
                pages: try WikiPage.fetchAll(database),
                evidence: try WikiEvidence.fetchAll(database),
                revisions: try WikiRevision.fetchAll(database),
                links: try WikiPageLink.fetchAll(database)
            )
        }
    }

    func fetchAllWikiPageSnapshots() async throws -> [WikiPageSnapshot] {
        let pages = try await fetchWikiPages()
        var snapshots: [WikiPageSnapshot] = []
        for page in pages {
            if let snapshot = try await fetchWikiPageSnapshot(id: page.id) {
                snapshots.append(snapshot)
            }
        }
        return snapshots
    }

    func fetchWikiPageLinks() async throws -> [WikiPageLink] {
        try await databasePool.read { database in
            try WikiPageLink.fetchAll(database)
        }
    }

    func fetchWikiSearchIndexRecords() async throws -> [WikiPageSearchIndexRecord] {
        try await databasePool.read { database in
            try WikiPageSearchIndexRecord.fetchAll(database)
        }
    }

    func saveWikiSearchIndexRecord(_ record: WikiPageSearchIndexRecord) async throws {
        try await databasePool.write { database in
            try record.save(database)
        }
    }

    func fetchWikiEvidenceMemories(
        pageIDs: [UUID],
        limit: Int = 8
    ) async throws -> [MemoryItem] {
        try await databasePool.read { database in
            let boundedLimit = max(1, min(limit, 12))
            let evidenceByPage = try pageIDs.map { pageID in
                try WikiEvidence
                    .filter(Column("pageID") == pageID)
                    .order(Column("createdAt").desc)
                    .fetchAll(database)
            }
            var memories: [MemoryItem] = []
            var seen = Set<UUID>()
            let maximumEvidenceCount = evidenceByPage.map(\.count).max() ?? 0
            for evidenceIndex in 0 ..< maximumEvidenceCount {
                for evidence in evidenceByPage where evidence.indices.contains(evidenceIndex) {
                    let item = evidence[evidenceIndex]
                    guard !seen.contains(item.memoryID),
                          let memory = try MemoryItem.fetchOne(database, key: item.memoryID) else {
                        continue
                    }
                    seen.insert(memory.id)
                    memories.append(memory)
                    if memories.count >= boundedLimit {
                        return memories
                    }
                }
            }
            return memories
        }
    }

    func fetchWikiPageSnapshot(id: UUID) async throws -> WikiPageSnapshot? {
        try await databasePool.read { database in
            guard let page = try WikiPage.fetchOne(database, key: id) else {
                return nil
            }
            let evidenceRecords = try WikiEvidence
                .filter(Column("pageID") == id)
                .order(Column("createdAt").desc)
                .fetchAll(database)
            let evidence = try evidenceRecords.compactMap { record -> WikiEvidenceSource? in
                guard let memory = try MemoryItem.fetchOne(database, key: record.memoryID) else {
                    return nil
                }
                return WikiEvidenceSource(evidence: record, memory: memory)
            }
            let links = try WikiPageLink.fetchAll(
                database,
                sql: """
                    SELECT * FROM wikiPageLink
                    WHERE sourcePageID = ? OR targetPageID = ?
                    ORDER BY createdAt DESC
                    """,
                arguments: [id, id]
            )
            let linkedPages = try links.compactMap { link -> WikiLinkedPage? in
                let otherID = link.sourcePageID == id ? link.targetPageID : link.sourcePageID
                guard let linkedPage = try WikiPage.fetchOne(database, key: otherID) else {
                    return nil
                }
                return WikiLinkedPage(page: linkedPage, rationale: link.rationale)
            }
            let revisions = try WikiRevision
                .filter(Column("pageID") == id)
                .order(Column("revisionNumber").desc)
                .fetchAll(database)
            return WikiPageSnapshot(
                page: page,
                evidence: evidence,
                linkedPages: linkedPages,
                revisions: revisions
            )
        }
    }

    func applyWikiCompilation(
        memoryID: UUID,
        sourceUpdatedAt: Date,
        proposal: WikiCompilationProposal,
        allowedCandidateIDs: Set<UUID>,
        runID: UUID? = nil,
        runCompletion: ProjectMemoryRunCompletion? = nil
    ) async throws {
        try await databasePool.write { database in
            guard let memory = try MemoryItem.fetchOne(database, key: memoryID) else {
                throw LivingWikiError.missingMemory
            }
            guard memory.updatedAt == sourceUpdatedAt else {
                throw LivingWikiError.sourceChanged
            }
            let now = Date()

            for proposedPage in proposal.pages {
                var effect = proposedPage.effect
                var page: WikiPage
                if let candidateID = proposedPage.candidateID {
                    guard allowedCandidateIDs.contains(candidateID),
                          var existing = try WikiPage.fetchOne(database, key: candidateID) else {
                        throw LivingWikiError.missingPage
                    }
                    let previousSummary = existing.summary
                    existing.summary = String(proposedPage.summary.prefix(1_500))
                    existing.mergeAliases([proposedPage.title] + proposedPage.aliases)
                    existing.updatedAt = now
                    existing.revisionNumber += 1
                    try existing.update(database)
                    page = existing
                    try Self.insertWikiRevision(
                        page: existing,
                        runID: runID,
                        memoryID: memoryID,
                        effect: effect,
                        previousSummary: previousSummary,
                        rationale: proposedPage.rationale,
                        at: now,
                        in: database
                    )
                } else {
                    let normalizedTitle = Self.normalizedWikiTitle(proposedPage.title)
                    if var existing = try WikiPage
                        .filter(Column("kind") == proposedPage.kind)
                        .filter(Column("normalizedTitle") == normalizedTitle)
                        .fetchOne(database) {
                        let previousSummary = existing.summary
                        existing.summary = String(proposedPage.summary.prefix(1_500))
                        existing.mergeAliases(proposedPage.aliases)
                        existing.updatedAt = now
                        existing.revisionNumber += 1
                        try existing.update(database)
                        page = existing
                        effect = .updated
                        try Self.insertWikiRevision(
                            page: existing,
                            runID: runID,
                            memoryID: memoryID,
                            effect: effect,
                            previousSummary: previousSummary,
                            rationale: proposedPage.rationale,
                            at: now,
                            in: database
                        )
                    } else {
                        let created = WikiPage(
                            id: UUID(),
                            kind: proposedPage.kind,
                            title: String(proposedPage.title.prefix(100)),
                            normalizedTitle: normalizedTitle,
                            summary: String(proposedPage.summary.prefix(1_500)),
                            aliasesJSON: WikiPage.encodeAliases(proposedPage.aliases),
                            createdAt: now,
                            updatedAt: now,
                            revisionNumber: 1
                        )
                        try created.insert(database)
                        page = created
                        effect = .introduced
                        try Self.insertWikiRevision(
                            page: created,
                            runID: runID,
                            memoryID: memoryID,
                            effect: effect,
                            previousSummary: nil,
                            rationale: proposedPage.rationale,
                            at: now,
                            in: database
                        )
                    }
                }

                let evidence = WikiEvidence(
                    pageID: page.id,
                    memoryID: memoryID,
                    effect: effect,
                    rationale: String(proposedPage.rationale.prefix(500)),
                    createdAt: now
                )
                try evidence.save(database)

                for relatedID in proposedPage.relatedCandidateIDs where relatedID != page.id {
                    guard allowedCandidateIDs.contains(relatedID),
                          try WikiPage.fetchOne(database, key: relatedID) != nil else {
                        continue
                    }
                    let ordered = Self.orderedPageIDs(page.id, relatedID)
                    let link = WikiPageLink(
                        sourcePageID: ordered.0,
                        targetPageID: ordered.1,
                        rationale: String(proposedPage.rationale.prefix(500)),
                        createdAt: now
                    )
                    try link.save(database)
                }
            }

            var compilation = try WikiCompilation.fetchOne(database, key: memoryID) ?? WikiCompilation(
                memoryID: memoryID,
                sourceUpdatedAt: memory.updatedAt,
                status: .processing,
                attemptedAt: now,
                completedAt: nil,
                errorMessage: nil,
                modelVersion: nil
            )
            compilation.sourceUpdatedAt = memory.updatedAt
            compilation.status = .compiled
            compilation.completedAt = now
            compilation.errorMessage = nil
            compilation.modelVersion = GemmaLivingWikiCompiler.modelVersion
            try compilation.save(database)

            if let runID, let runCompletion {
                try Self.finishProjectMemoryRunRecord(
                    id: runID,
                    completion: runCompletion,
                    in: database
                )
            }
        }
    }

    nonisolated private static func finishProjectMemoryRunRecord(
        id: UUID,
        completion: ProjectMemoryRunCompletion,
        in database: Database
    ) throws {
        guard var run = try ProjectMemoryRun.fetchOne(database, key: id) else { return }
        run.completedAt = Date()
        run.status = completion.status
        run.proposedPageCount = max(0, completion.proposedPageCount)
        run.acceptedPageCount = max(0, completion.acceptedPageCount)
        run.rationale = String(completion.rationale.prefix(800))
        try run.update(database)

        _ = try ProjectMemoryCheck
            .filter(Column("runID") == id)
            .deleteAll(database)
        for check in completion.checks {
            try ProjectMemoryCheck(
                id: UUID(),
                runID: id,
                checkID: String(check.checkID.prefix(100)),
                label: String(check.label.prefix(120)),
                severity: check.severity,
                passed: check.passed,
                message: String(check.message.prefix(500))
            ).insert(database)
        }
    }

    nonisolated private static func insertWikiRevision(
        page: WikiPage,
        runID: UUID?,
        memoryID: UUID,
        effect: WikiChangeKind,
        previousSummary: String?,
        rationale: String,
        at date: Date,
        in database: Database
    ) throws {
        let revision = WikiRevision(
            id: UUID(),
            runID: runID,
            pageID: page.id,
            memoryID: memoryID,
            revisionNumber: page.revisionNumber,
            effect: effect,
            previousSummary: previousSummary,
            newSummary: page.summary,
            rationale: String(rationale.prefix(500)),
            createdAt: date,
            modelVersion: GemmaLivingWikiCompiler.modelVersion
        )
        try revision.insert(database)
    }

    nonisolated private static func normalizedWikiTitle(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
            .prefix(100)
            .description
    }

    nonisolated private static func orderedPageIDs(_ first: UUID, _ second: UUID) -> (UUID, UUID) {
        first.uuidString < second.uuidString ? (first, second) : (second, first)
    }

    private func update(id: UUID, mutation: @Sendable (inout MemoryItem) -> Void) async throws {
        try await databasePool.write { database in
            guard var item = try MemoryItem.fetchOne(database, key: id) else {
                throw MemoryStoreError.missingMemory(id)
            }
            mutation(&item)
            item.updatedAt = Date()
            try item.update(database)
        }
    }

    nonisolated static func defaultDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appendingPathComponent("Remember", isDirectory: true)
            .appendingPathComponent("remember.sqlite", isDirectory: false)
    }

    nonisolated private static var protectedAttributes: [FileAttributeKey: Any] {
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    }

    nonisolated private static func normalized(_ value: String, maximumLength: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maximumLength))
    }

    private func mutateTag(
        _ source: String,
        transform: @Sendable ([String]) -> [String]
    ) async throws -> [MemoryItem] {
        try await databasePool.write { database in
            let memories = try MemoryItem.fetchAll(database)
            var changed: [MemoryItem] = []
            for var memory in memories where memory.tags.contains(where: {
                $0.caseInsensitiveCompare(source) == .orderedSame
            }) {
                memory.setTags(transform(memory.tags))
                memory.updatedAt = Date()
                try memory.update(database)
                changed.append(memory)
            }
            return changed
        }
    }

    nonisolated private static func collectionName(_ value: String) throws -> String {
        guard let name = normalized(value, maximumLength: 80) else {
            throw MemoryOrganizationError.blankCollectionName
        }
        return name
    }

    nonisolated private static func tagName(_ value: String) throws -> String {
        guard let name = normalized(value.lowercased(), maximumLength: 40) else {
            throw MemoryOrganizationError.blankTag
        }
        return name
    }

    nonisolated private static func collectionExists(named name: String, in database: Database) throws -> Bool {
        try Bool.fetchOne(
            database,
            sql: "SELECT EXISTS(SELECT 1 FROM memoryCollection WHERE lower(name) = lower(?) LIMIT 1)",
            arguments: [name]
        ) ?? false
    }
}
