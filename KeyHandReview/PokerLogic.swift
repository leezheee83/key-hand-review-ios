import Foundation

enum PokerLogic {
    static let ranks = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"]

    static func positions(for playerCount: Int) -> [String] {
        switch playerCount {
        case 4: return ["UTG", "BTN", "SB", "BB"]
        case 5: return ["UTG", "CO", "BTN", "SB", "BB"]
        case 6: return ["UTG", "HJ", "CO", "BTN", "SB", "BB"]
        case 7: return ["UTG", "LJ", "HJ", "CO", "BTN", "SB", "BB"]
        case 8: return ["UTG", "UTG+1", "LJ", "HJ", "CO", "BTN", "SB", "BB"]
        case 9: return ["UTG", "UTG+1", "UTG+2", "LJ", "HJ", "CO", "BTN", "SB", "BB"]
        case 10: return ["UTG", "UTG+1", "UTG+2", "MP", "LJ", "HJ", "CO", "BTN", "SB", "BB"]
        default: return positions(for: 8)
        }
    }

    static func clockwisePositions(for playerCount: Int) -> [String] {
        let positions = positions(for: playerCount)
        guard let buttonIndex = positions.firstIndex(of: "BTN") else { return positions }
        return Array(positions[buttonIndex...]) + Array(positions[..<buttonIndex])
    }

    static func actionOrder(for hand: PokerHand, street: StreetKey) -> [String] {
        let baseOrder = baseActionOrder(for: hand, street: street)
        let actionable = Set(actionablePositions(for: hand, street: street))
        let ordered = baseOrder.filter { actionable.contains($0) }
        return ordered.isEmpty ? baseOrder : ordered
    }

    static func nextActor(for hand: PokerHand, street: StreetKey) -> String {
        let baseOrder = baseActionOrder(for: hand, street: street)
        let actionable = Set(actionablePositions(for: hand, street: street))
        guard !baseOrder.isEmpty else { return hand.heroPosition }
        let activeOrder = baseOrder.filter { actionable.contains($0) }
        guard !activeOrder.isEmpty else { return hand.heroPosition }

        let actions = hand.streets[street]?.actions ?? []
        guard let lastActor = actions.last(where: { baseOrder.contains($0.actor) })?.actor else {
            return activeOrder.first ?? hand.heroPosition
        }
        return nextActor(after: lastActor, in: baseOrder, actionable: actionable) ?? (activeOrder.first ?? hand.heroPosition)
    }

    static func nextActor(after actor: String, hand: PokerHand, street: StreetKey) -> String {
        let baseOrder = baseActionOrder(for: hand, street: street)
        let actionable = Set(actionablePositions(for: hand, street: street))
        return nextActor(after: actor, in: baseOrder, actionable: actionable) ?? nextActor(for: hand, street: street)
    }

    static func predictedActorForInsertion(at index: Int, hand: PokerHand, street: StreetKey) -> String {
        var draft = hand
        var record = draft.streets[street] ?? StreetRecord()
        let safeIndex = min(max(index, 0), record.actions.count)
        record.actions = Array(record.actions.prefix(safeIndex))
        draft.streets[street] = record
        return nextActor(for: draft, street: street)
    }

    private static func baseActionOrder(for hand: PokerHand, street: StreetKey) -> [String] {
        let positions = positions(for: hand.playerCount)
        guard !positions.isEmpty else { return [] }

        if street == .preflop {
            guard let straddle = hand.straddles.first,
                  positions.contains(straddle.position) else {
                return positions
            }
            return rotatedClockwisePositions(for: hand.playerCount, after: straddle.position)
        }

        return rotatedClockwisePositions(for: hand.playerCount, after: "BTN")
    }

    private static func rotatedClockwisePositions(for playerCount: Int, after position: String) -> [String] {
        let clockwise = clockwisePositions(for: playerCount)
        guard let index = clockwise.firstIndex(of: position) else { return clockwise }
        let start = clockwise.index(after: index) == clockwise.endIndex ? clockwise.startIndex : clockwise.index(after: index)
        return Array(clockwise[start...]) + Array(clockwise[..<start])
    }

    private static func actionablePositions(for hand: PokerHand, street: StreetKey) -> [String] {
        let positions = positions(for: hand.playerCount)
        var unavailable = Set<String>()
        for key in StreetKey.allCases {
            guard let record = hand.streets[key] else { continue }
            for action in record.actions {
                guard positions.contains(action.actor) else { continue }
                let normalized = action.action.lowercased()
                if normalized.contains("fold")
                    || normalized.contains("弃牌")
                    || normalized.contains("all-in")
                    || normalized.contains("allin")
                    || normalized.contains("all in") {
                    unavailable.insert(action.actor)
                }
            }
            if key == street { break }
        }
        return positions.filter { !unavailable.contains($0) }
    }

    private static func nextActor(after actor: String, in order: [String], actionable: Set<String>) -> String? {
        guard !order.isEmpty else { return nil }
        guard let index = order.firstIndex(of: actor) else {
            return order.first { actionable.contains($0) }
        }
        for offset in 1...order.count {
            let next = order[(index + offset) % order.count]
            if actionable.contains(next) {
                return next
            }
        }
        return nil
    }

    static func positionLabel(_ position: String) -> String {
        [
            "UTG": "枪口位（UTG）",
            "UTG+1": "枪口+1（UTG+1）",
            "UTG+2": "枪口+2（UTG+2）",
            "MP": "中位（MP）",
            "LJ": "低劫持位（LJ）",
            "HJ": "高劫持位（HJ）",
            "CO": "关煞位（CO）",
            "BTN": "庄位（BTN）",
            "SB": "小盲位（SB）",
            "BB": "大盲位（BB）",
            "全桌": "全桌"
        ][position] ?? position
    }

    static func trim(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func formatAmount(_ bbValue: Double?, session: ReviewSession?, paired: Bool = false) -> String {
        guard let bbValue else { return "未记" }
        let sessionBB = session?.bb ?? 1
        let currency = session?.currency ?? "U"
        let chips = "\(currency)\(trim(bbValue * sessionBB))"
        if paired { return "\(trim(bbValue))bb（\(chips)）" }
        return session?.unit == .chips ? chips : "\(trim(bbValue))bb"
    }

    static func amountToBB(_ value: Double, session: ReviewSession?) -> Double {
        guard session?.unit == .chips else { return value }
        return value / max(session?.bb ?? 1, 0.0001)
    }

    static func actionText(_ action: HandAction, session: ReviewSession?, paired: Bool = false) -> String {
        let amount = action.amountBB.map { " \(formatAmount($0, session: session, paired: paired))" } ?? ""
        return "\(positionLabel(action.actor)) \(action.action)\(amount)"
    }

    static func routeText(_ actions: [HandAction], session: ReviewSession?) -> String {
        actions.isEmpty ? "尚未记录行动。" : actions.map { actionText($0, session: session) }.joined(separator: " → ")
    }

    static func handSummary(_ hand: PokerHand, session: ReviewSession?) -> String {
        let actions = hand.streets[.preflop]?.actions ?? []
        return actions.isEmpty ? "已保存关键标签，路线待补" : routeText(Array(actions.prefix(3)), session: session)
    }

    static func completeness(_ hand: PokerHand) -> Int {
        var score = 25
        if !hand.heroPosition.isEmpty { score += 12 }
        if hand.effectiveStackBB > 0 { score += 12 }
        if !hand.heroCards.isEmpty { score += 12 }
        if !(hand.streets[.preflop]?.actions.isEmpty ?? true) { score += 16 }
        if !(hand.streets[.flop]?.actions.isEmpty ?? true) { score += 11 }
        if !(hand.streets[.turn]?.actions.isEmpty ?? true) || !(hand.streets[.river]?.actions.isEmpty ?? true) { score += 7 }
        if !hand.review.decision.isEmpty { score += 5 }
        return min(100, score)
    }

    static func markdown(for hand: PokerHand, session: ReviewSession?) -> String {
        let date = hand.createdAt.formatted(date: .numeric, time: .omitted)
        let sections = StreetKey.allCases.compactMap { street -> String? in
            guard let data = hand.streets[street], (!data.actions.isEmpty || !data.board.isEmpty) else { return nil }
            let board = street == .preflop || data.board.isEmpty ? "" : "：\(data.board.map(\.display).joined(separator: " "))"
            let line = data.actions.isEmpty ? "[待补]" : data.actions.map { actionText($0, session: session, paired: true) }.joined(separator: "；")
            let pot = data.potBB.map { "\n池量：\(data.confidence == "estimated" ? "约 " : "")\(formatAmount($0, session: session, paired: true))。" } ?? ""
            return "## \(street.title)\(board)\n\(line)\(pot)"
        }.joined(separator: "\n\n")

        let straddle = hand.straddles.isEmpty
            ? "none"
            : hand.straddles.map { "\(positionLabel($0.position)) \(formatAmount($0.amountBB, session: session, paired: true))" }.joined(separator: ", ")
        let game = session.map { "\(trim($0.sb))/\(trim($0.bb)) NLH Hand Review" } ?? "NLH Hand Review"
        let heroCards = hand.heroCards.map(\.display).joined(separator: " ")

        return """
        ---
        date: \(date)
        game: \(game)
        players: \(hand.playerCount)
        straddle: \(straddle)
        tags: [\(hand.tags.joined(separator: ", "))]
        ---

        # \(positionLabel(hand.heroPosition)) \(heroCards.isEmpty ? "[手牌待补]" : heroCards)｜有效后手 \(formatAmount(hand.effectiveStackBB, session: session, paired: true))

        \(sections)

        ## 复盘
        - 关键决策：\(hand.review.decision.isEmpty ? "[待补]" : hand.review.decision)
        - 当时依据：\(hand.review.basis.isEmpty ? "[待补]" : hand.review.basis)
        - 下次默认修正：\(hand.review.correction.isEmpty ? "[待补]" : hand.review.correction)

        """
    }

    static func markdown(for hands: [PokerHand], session: ReviewSession?) -> String {
        let title = session.map { "# \(trim($0.sb))/\(trim($0.bb)) NLH 手牌复盘" } ?? "# NLH 手牌复盘"
        let index = hands.enumerated().map { idx, hand in
            let heroCards = hand.heroCards.map(\.display).joined(separator: " ")
            return "- 手牌 \(idx + 1)：\(positionLabel(hand.heroPosition)) \(heroCards.isEmpty ? "[手牌待补]" : heroCards) · \(hand.tags.joined(separator: "/"))"
        }.joined(separator: "\n")
        return "\(title)\n\n\(index)\n\n\(hands.map { markdown(for: $0, session: session) }.joined(separator: "\n\n---\n\n"))"
    }

    static func templateRoute(_ template: String, hand: PokerHand) -> (potBB: Double, actions: [HandAction]) {
        let positions = positions(for: hand.playerCount)
        let hero = hand.heroPosition
        switch template {
        case "open":
            return (16, [
                HandAction(actor: hero, action: "open", amountBB: 5, hero: true),
                HandAction(actor: "BTN", action: "call", hero: false),
                HandAction(actor: "BB", action: "call", hero: false)
            ])
        case "vsopen", "3bet":
            return (38, [
                HandAction(actor: "HJ", action: "open", amountBB: 5, hero: false),
                HandAction(actor: hero, action: "3bet", amountBB: 18, hero: true),
                HandAction(actor: "HJ", action: "call", hero: false)
            ])
        default:
            let second = positions[min(2, max(0, positions.count - 3))]
            return (19, [
                HandAction(actor: positions.first ?? "UTG", action: "limp", hero: false),
                HandAction(actor: second, action: "limp", hero: false),
                HandAction(actor: hero, action: "ISO", amountBB: 6, hero: true),
                HandAction(actor: "BB", action: "call", hero: false),
                HandAction(actor: positions.first ?? "UTG", action: "call", hero: false)
            ])
        }
    }
}
