import Foundation

final class HandStore: ObservableObject {
    @Published var session: ReviewSession? {
        didSet { persistIfNeeded() }
    }

    @Published var hands: [PokerHand] = [] {
        didSet { persistIfNeeded() }
    }

    private struct StoreSnapshot: Codable {
        var activeSessionID: UUID?
        var archives: [SessionArchive]
    }

    private let legacySessionKey = "keyhand_ios_session_v1"
    private let legacyHandsKey = "keyhand_ios_hands_v1"
    private let storageFileName = "KeyHandReviewStore.json"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var archives: [SessionArchive] = []
    private var isApplyingSnapshot = false

    var sessionHistory: [SessionArchive] {
        mergedArchives().sorted { $0.session.createdAt > $1.session.createdAt }
    }

    init() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func startSession(sb: Double, bb: Double, currency: String, unit: AmountUnit, playerCount: Int, straddles: [Straddle]) {
        let newSession = ReviewSession(sb: sb, bb: bb, currency: currency, unit: unit, playerCount: playerCount, straddles: straddles)
        applySnapshot {
            session = newSession
            hands = []
            archives = upsert(SessionArchive(session: newSession, hands: []), into: archives)
        }
    }

    func saveSession(_ value: ReviewSession) {
        session = value
    }

    func endCurrentSession() {
        guard var current = session else { return }
        current.endedAt = Date()
        let finished = SessionArchive(session: current, hands: hands)
        applySnapshot {
            archives = upsert(finished, into: archives)
            session = nil
            hands = []
        }
    }

    func resumeCurrentSession() {
        guard var current = session else { return }
        current.endedAt = nil
        applySnapshot {
            session = current
            archives = upsert(SessionArchive(session: current, hands: hands), into: archives)
        }
    }

    func openSession(_ id: UUID) {
        guard let archive = sessionHistory.first(where: { $0.id == id }) else { return }
        applySnapshot {
            session = archive.session
            hands = archive.hands
        }
    }

    func closeCurrentSession() {
        applySnapshot {
            if let session {
                archives = upsert(SessionArchive(session: session, hands: hands), into: archives)
            }
            session = nil
            hands = []
        }
    }

    func createDraft() -> PokerHand? {
        guard let session, !session.isEnded else { return nil }
        let previous = hands.first
        var hand = PokerHand()
        hand.playerCount = previous?.playerCount ?? session.playerCount
        hand.heroPosition = previous?.heroPosition ?? "CO"
        hand.straddles = previous?.straddles ?? session.straddles
        saveHand(hand)
        return hand
    }

    func hand(id: UUID) -> PokerHand? {
        hands.first { $0.id == id }
    }

    func saveHand(_ hand: PokerHand) {
        if let index = hands.firstIndex(where: { $0.id == hand.id }) {
            hands[index] = hand
        } else {
            hands.insert(hand, at: 0)
        }
    }

    func deleteHands(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            hands.remove(at: index)
        }
    }

    func deleteHand(id: UUID) {
        hands.removeAll { $0.id == id }
    }

    private var storeURL: URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent(storageFileName)
    }

    private func load() {
        if let data = try? Data(contentsOf: storeURL),
           let snapshot = try? decoder.decode(StoreSnapshot.self, from: data) {
            applyLoadedSnapshot(snapshot)
            return
        }

        migrateLegacyUserDefaults()
    }

    private func migrateLegacyUserDefaults() {
        var migratedSession: ReviewSession?
        var migratedHands: [PokerHand] = []

        if let data = UserDefaults.standard.data(forKey: legacySessionKey) {
            migratedSession = try? decoder.decode(ReviewSession.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: legacyHandsKey) {
            migratedHands = (try? decoder.decode([PokerHand].self, from: data)) ?? []
        }

        guard let migratedSession else { return }
        applySnapshot {
            session = migratedSession
            hands = migratedHands
            archives = [SessionArchive(session: migratedSession, hands: migratedHands)]
        }
    }

    private func applyLoadedSnapshot(_ snapshot: StoreSnapshot) {
        isApplyingSnapshot = true
        archives = snapshot.archives
        if let activeSessionID = snapshot.activeSessionID,
           let active = snapshot.archives.first(where: { $0.id == activeSessionID }) {
            session = active.session
            hands = active.hands
        } else {
            session = nil
            hands = []
        }
        isApplyingSnapshot = false
    }

    private func applySnapshot(_ changes: () -> Void) {
        isApplyingSnapshot = true
        changes()
        isApplyingSnapshot = false
        save()
    }

    private func persistIfNeeded() {
        guard !isApplyingSnapshot else { return }
        save()
    }

    private func save() {
        let snapshot = StoreSnapshot(activeSessionID: session?.id, archives: mergedArchives())
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: storeURL, options: [.atomic])
    }

    private func mergedArchives() -> [SessionArchive] {
        guard let session else { return archives }
        return upsert(SessionArchive(session: session, hands: hands), into: archives)
    }

    private func upsert(_ archive: SessionArchive, into source: [SessionArchive]) -> [SessionArchive] {
        var updated = source
        if let index = updated.firstIndex(where: { $0.id == archive.id }) {
            updated[index] = archive
        } else {
            updated.insert(archive, at: 0)
        }
        return updated
    }
}
