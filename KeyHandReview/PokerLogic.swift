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
        nextActorIfNeeded(for: hand, street: street) ?? hand.heroPosition
    }

    static func nextActorIfNeeded(for hand: PokerHand, street: StreetKey) -> String? {
        let baseOrder = baseActionOrder(for: hand, street: street)
        let actionable = Set(actionablePositions(for: hand, street: street))
        guard !baseOrder.isEmpty else { return nil }
        let activeOrder = baseOrder.filter { actionable.contains($0) }
        guard activeOrder.count > 1 else { return nil }

        let actions = hand.streets[street]?.actions ?? []
        guard let lastActor = actions.last(where: { baseOrder.contains($0.actor) })?.actor else {
            return activeOrder.first
        }
        let actorsNeedingAction = actorsNeedingAction(for: hand, street: street, order: baseOrder, activeActors: actionable)
        guard !actorsNeedingAction.isEmpty else { return nil }
        return nextActor(after: lastActor, in: baseOrder, actionable: actionable, requiringAction: actorsNeedingAction)
            ?? activeOrder.first { actorsNeedingAction.contains($0) }
    }

    static func nextActor(after actor: String, hand: PokerHand, street: StreetKey) -> String {
        guard let next = nextActorAfterManualSkip(after: actor, hand: hand, street: street) else {
            return nextActor(for: hand, street: street)
        }
        return next
    }

    static func nextActorAfterManualSkip(after actor: String, hand: PokerHand, street: StreetKey) -> String? {
        let baseOrder = baseActionOrder(for: hand, street: street)
        let actionable = Set(actionablePositions(for: hand, street: street))
        let actorsNeedingAction = actorsNeedingAction(for: hand, street: street, order: baseOrder, activeActors: actionable)
        guard !actorsNeedingAction.isEmpty else { return nil }
        return nextActor(after: actor, in: baseOrder, actionable: actionable, requiringAction: actorsNeedingAction)
    }

    static func actorsNeedingAction(for hand: PokerHand, street: StreetKey) -> Set<String> {
        let baseOrder = baseActionOrder(for: hand, street: street)
        let actionable = Set(actionablePositions(for: hand, street: street))
        return actorsNeedingAction(for: hand, street: street, order: baseOrder, activeActors: actionable)
    }

    static func predictedActorForInsertion(at index: Int, hand: PokerHand, street: StreetKey) -> String {
        var draft = hand
        var record = draft.streets[street] ?? StreetRecord()
        let safeIndex = min(max(index, 0), record.actions.count)
        record.actions = Array(record.actions.prefix(safeIndex))
        draft.streets[street] = record
        return nextActor(for: draft, street: street)
    }

    struct StreetAnalysis {
        var startingPotBB: Double
        var potBB: Double
        var currentBetBB: Double
        var contributions: [String: Double]
        var confidence: String

        var isEstimated: Bool { confidence == "estimated" }

        func callAmount(for actor: String) -> Double {
            max(currentBetBB - (contributions[actor] ?? 0), 0)
        }
    }

    static func streetAnalysis(for hand: PokerHand, street: StreetKey) -> StreetAnalysis {
        let positions = positions(for: hand.playerCount)
        let actions = hand.streets[street]?.actions ?? []
        var confidence = "exact"
        var contributions: [String: Double] = [:]
        var startingPotBB: Double = 0
        var currentBetBB: Double = 0

        if street == .preflop {
            if positions.contains("SB") { contributions["SB"] = 0.5 }
            if positions.contains("BB") { contributions["BB"] = 1 }
            for straddle in hand.straddles where positions.contains(straddle.position) {
                contributions[straddle.position] = max(contributions[straddle.position] ?? 0, straddle.amountBB)
            }
            startingPotBB = contributions.values.reduce(0, +)
            currentBetBB = contributions.values.max() ?? 0
        } else {
            startingPotBB = potBefore(street: street, hand: hand)
        }

        for action in actions {
            let normalized = normalizedAction(action.action)
            let currentContribution = contributions[action.actor] ?? 0

            if isFoldAction(normalized) || normalized == "check" || normalized == "过牌" {
                continue
            }

            if normalized == "call" || normalized == "跟注" {
                let added = action.amountBB ?? max(currentBetBB - currentContribution, 0)
                contributions[action.actor] = currentContribution + max(added, 0)
                continue
            }

            if normalized == "limp" || normalized == "limped" || normalized == "跛入" {
                let target = max(currentBetBB, street == .preflop ? 1 : 0)
                contributions[action.actor] = currentContribution + max(target - currentContribution, 0)
                currentBetBB = max(currentBetBB, target)
                continue
            }

            if isAggressiveAction(normalized) {
                guard let target = action.amountBB else {
                    confidence = "estimated"
                    continue
                }
                contributions[action.actor] = currentContribution + max(target - currentContribution, 0)
                currentBetBB = max(currentBetBB, target)
                continue
            }

            if isAllInAction(normalized) {
                guard let target = action.amountBB else {
                    confidence = "estimated"
                    continue
                }
                let effectiveTarget = max(target, currentBetBB)
                contributions[action.actor] = currentContribution + max(effectiveTarget - currentContribution, 0)
                currentBetBB = max(currentBetBB, effectiveTarget)
                continue
            }

            if action.amountBB != nil {
                confidence = "estimated"
            }
        }

        let potBB = startingPotBB + contributions.values.reduce(0, +) - (street == .preflop ? startingPotBB : 0)
        return StreetAnalysis(
            startingPotBB: startingPotBB,
            potBB: potBB,
            currentBetBB: currentBetBB,
            contributions: contributions,
            confidence: confidence
        )
    }

    private static func potBefore(street: StreetKey, hand: PokerHand) -> Double {
        guard let index = StreetKey.allCases.firstIndex(of: street), index > 0 else { return 0 }
        let previousStreet = StreetKey.allCases[index - 1]
        let previousRecord = hand.streets[previousStreet] ?? StreetRecord()
        if !previousRecord.actions.isEmpty || previousStreet == .preflop {
            return streetAnalysis(for: hand, street: previousStreet).potBB
        }
        return previousRecord.potBB ?? potBefore(street: previousStreet, hand: hand)
    }

    static func normalizedAction(_ action: String) -> String {
        action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isFoldAction(_ normalizedAction: String) -> Bool {
        normalizedAction.contains("fold") || normalizedAction.contains("弃牌")
    }

    static func isAllInAction(_ normalizedAction: String) -> Bool {
        normalizedAction.contains("all-in")
            || normalizedAction.contains("allin")
            || normalizedAction.contains("all in")
            || normalizedAction.contains("全下")
    }

    static func isAggressiveAction(_ normalizedAction: String) -> Bool {
        normalizedAction == "open"
            || normalizedAction == "bet"
            || normalizedAction == "raise"
            || normalizedAction == "3bet"
            || normalizedAction == "4bet"
            || normalizedAction == "iso"
            || normalizedAction == "加注"
            || normalizedAction == "下注"
            || normalizedAction.contains("bet")
            || normalizedAction.contains("raise")
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

    private static func nextActor(after actor: String, in order: [String], actionable: Set<String>, requiringAction: Set<String>) -> String? {
        guard !order.isEmpty else { return nil }
        guard let index = order.firstIndex(of: actor) else {
            return order.first { actionable.contains($0) && requiringAction.contains($0) }
        }
        for offset in 1...order.count {
            let next = order[(index + offset) % order.count]
            if actionable.contains(next) && requiringAction.contains(next) {
                return next
            }
        }
        return nil
    }

    private static func actorsNeedingAction(for hand: PokerHand, street: StreetKey, order: [String], activeActors: Set<String>) -> Set<String> {
        let activeOrder = order.filter { activeActors.contains($0) }
        guard activeOrder.count > 1 else { return [] }

        let actions = hand.streets[street]?.actions ?? []
        guard !actions.isEmpty else { return Set(activeOrder) }

        let analysis = streetAnalysis(for: hand, street: street)
        let latestAggressiveIndex = actions.indices.reversed().first { index in
            isAggressiveAction(normalizedAction(actions[index].action))
        }

        func hasAction(_ actor: String) -> Bool {
            actions.contains { $0.actor == actor }
        }

        func hasActionAfterLatestAggression(_ actor: String, latestAggressiveIndex: Int) -> Bool {
            actions.indices.contains { index in
                index > latestAggressiveIndex && actions[index].actor == actor
            }
        }

        if let latestAggressiveIndex {
            let aggressor = actions[latestAggressiveIndex].actor
            return Set(activeOrder.filter { actor in
                guard actor != aggressor else { return false }
                let hasResponded = hasActionAfterLatestAggression(actor, latestAggressiveIndex: latestAggressiveIndex)
                let hasMatchedCurrentBet = (analysis.contributions[actor] ?? 0) >= analysis.currentBetBB
                return !hasResponded || !hasMatchedCurrentBet
            })
        }

        return Set(activeOrder.filter { actor in
            let hasActed = hasAction(actor)
            let hasMatchedForcedBet = (analysis.contributions[actor] ?? 0) >= analysis.currentBetBB
            if street == .preflop {
                return !hasActed || !hasMatchedForcedBet
            }
            return !hasActed
        })
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
