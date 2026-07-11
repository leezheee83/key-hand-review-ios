import Foundation

final class HandStore: ObservableObject {
    @Published var session: ReviewSession? {
        didSet { save() }
    }

    @Published var hands: [PokerHand] = [] {
        didSet { save() }
    }

    private let sessionKey = "keyhand_ios_session_v1"
    private let handsKey = "keyhand_ios_hands_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func startSession(sb: Double, bb: Double, currency: String, unit: AmountUnit, playerCount: Int, straddles: [Straddle]) {
        session = ReviewSession(sb: sb, bb: bb, currency: currency, unit: unit, playerCount: playerCount, straddles: straddles)
        hands = []
    }

    func saveSession(_ value: ReviewSession) {
        session = value
    }

    func createDraft() -> PokerHand? {
        guard let session else { return nil }
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

    private func load() {
        if let data = UserDefaults.standard.data(forKey: sessionKey) {
            session = try? decoder.decode(ReviewSession.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: handsKey) {
            hands = (try? decoder.decode([PokerHand].self, from: data)) ?? []
        }
    }

    private func save() {
        if let session, let data = try? encoder.encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: sessionKey)
        }
        if let data = try? encoder.encode(hands) {
            UserDefaults.standard.set(data, forKey: handsKey)
        }
    }
}
