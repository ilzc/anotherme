import Foundation

/// Global observable state for MBTI and Big Five analysis, persists across view lifecycle.
@MainActor
@Observable
final class PersonalityAnalysisState {
    static let shared = PersonalityAnalysisState()

    // MARK: - MBTI State

    var mbtiResult: MBTIResult?
    var isMBTIAnalyzing = false
    var mbtiLog = ""

    // MARK: - Big Five State

    var bigFiveResult: BigFiveResult?
    var isBigFiveAnalyzing = false
    var bigFiveLog = ""

    // MARK: - MBTI Analysis

    func startMBTIAnalysis() {
        guard !isMBTIAnalyzing else { return }
        isMBTIAnalyzing = true
        mbtiLog = ""

        Task.detached {
            do {
                let dbm = DatabaseManager.shared
                guard let l1DB = dbm.layer1DB,
                      let l2DB = dbm.layer2DB,
                      let l3DB = dbm.layer3DB,
                      let l4DB = dbm.layer4DB,
                      let l5DB = dbm.layer5DB,
                      let snDB = dbm.snapshotsDB else {
                    await MainActor.run { [self] in
                        mbtiLog = "Database not initialized"
                        isMBTIAnalyzing = false
                    }
                    return
                }

                let stores = (
                    Layer1Store(db: l1DB),
                    Layer2Store(db: l2DB),
                    Layer3Store(db: l3DB),
                    Layer4Store(db: l4DB),
                    Layer5Store(db: l5DB)
                )

                let result = try await MBTIAnalyzer.analyze(
                    stores: stores,
                    snapshotStore: SnapshotStore(db: snDB),
                    aiClient: AIClient.shared,
                    onProgress: { @Sendable step in
                        await MainActor.run { [self] in mbtiLog = step }
                    }
                )

                await MainActor.run { [self] in
                    mbtiResult = result
                    mbtiLog = "Analysis complete: \(result.mbtiType)"
                    isMBTIAnalyzing = false
                }
            } catch {
                await MainActor.run { [self] in
                    mbtiLog = "Analysis failed: \(error.localizedDescription)"
                    isMBTIAnalyzing = false
                }
            }
        }
    }

    // MARK: - Big Five Analysis

    func startBigFiveAnalysis() {
        guard !isBigFiveAnalyzing else { return }
        isBigFiveAnalyzing = true
        bigFiveLog = ""

        Task.detached {
            do {
                let dbm = DatabaseManager.shared
                guard let l1DB = dbm.layer1DB,
                      let l2DB = dbm.layer2DB,
                      let l3DB = dbm.layer3DB,
                      let l4DB = dbm.layer4DB,
                      let l5DB = dbm.layer5DB,
                      let snDB = dbm.snapshotsDB else {
                    await MainActor.run { [self] in
                        bigFiveLog = "Database not initialized"
                        isBigFiveAnalyzing = false
                    }
                    return
                }

                let stores = (
                    Layer1Store(db: l1DB),
                    Layer2Store(db: l2DB),
                    Layer3Store(db: l3DB),
                    Layer4Store(db: l4DB),
                    Layer5Store(db: l5DB)
                )

                let result = try await BigFiveAnalyzer.analyze(
                    stores: stores,
                    snapshotStore: SnapshotStore(db: snDB),
                    aiClient: AIClient.shared,
                    onProgress: { @Sendable step in
                        await MainActor.run { [self] in bigFiveLog = step }
                    }
                )

                await MainActor.run { [self] in
                    bigFiveResult = result
                    bigFiveLog = "Analysis complete"
                    isBigFiveAnalyzing = false
                }
            } catch {
                await MainActor.run { [self] in
                    bigFiveLog = "Analysis failed: \(error.localizedDescription)"
                    isBigFiveAnalyzing = false
                }
            }
        }
    }

    // MARK: - Data Loading

    func loadResults() {
        Task.detached {
            let dbm = DatabaseManager.shared
            var mbti: MBTIResult? = nil
            var bigFive: BigFiveResult? = nil

            if let db = dbm.snapshotsDB {
                mbti = try? SnapshotStore(db: db).fetchLatestMBTI()
                bigFive = try? SnapshotStore(db: db).fetchLatestBigFive()
            }

            await MainActor.run { [self] in
                if mbtiResult == nil { mbtiResult = mbti }
                if bigFiveResult == nil { bigFiveResult = bigFive }
            }
        }
    }
}
