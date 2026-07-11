import SwiftUI

struct RouteEditorView: View {
    @EnvironmentObject private var store: HandStore
    let handID: UUID
    @Binding var path: [AppRoute]

    @State private var street: StreetKey = .preflop
    @State private var actor = ""
    @State private var action = ""
    @State private var customAction = ""
    @State private var amount = ""
    @State private var sheetTarget: RouteActionSheetTarget?

    var body: some View {
        Group {
            if let hand = store.hand(id: handID) {
                VStack(spacing: 0) {
                    routeContextBar(hand)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header

                            Picker("街", selection: $street) {
                                ForEach(StreetKey.allCases) { key in
                                    Text(key.shortTitle).tag(key)
                                }
                            }
                            .pickerStyle(.segmented)

                            if street == .preflop {
                                preflopTemplates()
                            } else {
                                boardPanel(hand)
                            }

                            actionConsole(hand)
                            routePreview(hand)

                            Button {
                                next(hand)
                            } label: {
                                Text(street == .river ? "完成并查看回放" : "保存本街并继续")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .padding()
                    }
                }
                .background(Color.appGroupedBackground)
                .navigationTitle("补路线")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("查看回放") { path.append(.detail(hand.id)) }
                    }
                }
                .sheet(item: $sheetTarget) { target in
                    if let latest = store.hand(id: handID) {
                        RouteActionMutationSheet(
                            session: store.session,
                            hand: latest,
                            target: target,
                            actionOptions: mutationActionOptions
                        ) { actor, action, amountBB in
                            applyMutation(target, hand: latest, actor: actor, action: action, amountBB: amountBB)
                        }
                    }
                }
                .onAppear {
                    if actor.isEmpty { syncActor(with: hand) }
                    syncActionChoice(with: hand)
                }
                .onChange(of: street) { _ in
                    if let latest = store.hand(id: handID) {
                        syncActor(with: latest)
                        syncActionChoice(with: latest)
                    }
                    amount = ""
                    customAction = ""
                }
            } else {
                EmptyStateView(text: "没有找到这手牌。")
                    .padding()
            }
        }
    }

    private func routeContextBar(_ hand: PokerHand) -> some View {
        let board = boardCards(in: hand, through: street)
        let heroCards = hand.heroCards.map(\.display).joined(separator: " ").ifEmpty("手牌待补")
        let analysis = PokerLogic.streetAnalysis(for: hand, street: street)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(PokerLogic.positionLabel(hand.heroPosition)) \(heroCards)")
                    .font(.footnote.weight(.bold))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if board.isEmpty {
                        Text(boardPlaceholder)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(board) { card in
                            compactCard(card)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(street.shortTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(analysis.isEstimated ? "约 " : "")\(PokerLogic.formatAmount(analysis.potBB, session: store.session))")
                    .font(.footnote.weight(.bold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var boardPlaceholder: String {
        switch street {
        case .preflop: return "公共牌未发"
        case .flop: return "Flop □ □ □"
        case .turn: return "Turn □"
        case .river: return "River □"
        }
    }

    private func compactCard(_ card: PlayingCard) -> some View {
        Text(card.display)
            .font(.caption.weight(.bold))
            .foregroundStyle(card.suit.isRed ? Color.red : Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("补行动路线")
                .font(.largeTitle.bold())
            Text("按行动顺序推进；路线文本会自动生成。漏记时点路线里的动作插入或修正。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func preflopTemplates() -> some View {
        CardPanel {
            SectionTitle(
                title: "翻前结构",
                subtitle: "默认自定义，不预填模板；直接从下方行动顺序开始记录。"
            )
            Label("自定义", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.10))
                .clipShape(Capsule())

            Text("先不展示 Hero open、面对 open、3bet pot 等结构，减少现场记录时的理解成本。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func boardPanel(_ hand: PokerHand) -> some View {
        CardPanel {
            SectionTitle(title: street == .flop ? "Flop 公共牌" : "\(street.title) 新增公共牌")
            CardPickerView(
                cards: Binding(
                    get: { store.hand(id: handID)?.streets[street]?.board ?? [] },
                    set: { cards in
                        guard var updated = store.hand(id: handID) else { return }
                        var record = updated.streets[street] ?? StreetRecord()
                        record.board = cards
                        updated.streets[street] = record
                        store.saveHand(updated)
                    }
                ),
                maxCards: street == .flop ? 3 : 1,
                blockedCards: blockedCards(in: hand, currentStreet: street),
                helper: "会自动防止与 Hero 手牌或已选公共牌重复。"
            )
        }
    }

    private func actionConsole(_ hand: PokerHand) -> some View {
        let analysis = PokerLogic.streetAnalysis(for: hand, street: street)
        let actorsNeedingAction = PokerLogic.actorsNeedingAction(for: hand, street: street)
        let recommendedActor = PokerLogic.nextActorIfNeeded(for: hand, street: street)
        let currentActor = actorsNeedingAction.contains(actor) ? actor : recommendedActor
        let isStreetClosed = currentActor == nil
        let callAmount = currentActor.map { analysis.callAmount(for: $0) } ?? 0
        let choices = currentActor.map { actionChoices(for: hand, actor: $0) } ?? []

        return CardPanel {
            SectionTitle(
                title: "行动顺序与记录",
                subtitle: street == .preflop ? "翻前会考虑 straddle；点位置可直接切到那位补动作。" : "翻后从庄位左手边开始，已弃牌 / all-in 的玩家会被跳过。"
            )

            HStack(spacing: 10) {
                metricTile(title: "底池", value: "\(analysis.isEstimated ? "约 " : "")\(PokerLogic.formatAmount(analysis.potBB, session: store.session))")
                metricTile(title: "当前下注", value: PokerLogic.formatAmount(analysis.currentBetBB, session: store.session))
                metricTile(title: "待跟", value: PokerLogic.formatAmount(callAmount, session: store.session))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PokerLogic.actionOrder(for: hand, street: street), id: \.self) { position in
                        Button {
                            guard actorsNeedingAction.contains(position) else { return }
                            actor = position
                            syncActionChoice(with: hand, actorOverride: position)
                        } label: {
                            VStack(spacing: 3) {
                                Text(orderLabel(position, hand: hand))
                                    .font(.footnote.weight(.semibold))
                                Text(positionState(position, currentActor: currentActor, actions: hand.streets[street]?.actions ?? []))
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(position == currentActor ? .white : positionTextColor(position: position, hand: hand, actorsNeedingAction: actorsNeedingAction))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(position == currentActor ? Color.blue : Color.appSecondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!actorsNeedingAction.contains(position))
                    }
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前行动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(currentActor.map { PokerLogic.positionLabel($0) } ?? "本街已闭合")
                        .font(.headline)
                        .foregroundStyle(currentActor == hand.heroPosition ? .blue : (isStreetClosed ? .green : .primary))
                }

                Spacer()

                Button("用系统推荐") {
                    syncActor(with: hand)
                    syncActionChoice(with: hand)
                }
                .font(.footnote.weight(.semibold))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(choices, id: \.self) { option in
                    PillButton(title: displayAction(option, callAmount: callAmount), selected: action == option, warning: option == "all-in") {
                        action = option
                        if !needsAmount(option) { amount = "" }
                    }
                }
            }

            if action == "自定义" {
                TextField("自定义动作，例如 donk / cold call / tank fold", text: $customAction)
                    .textFieldStyle(.roundedBorder)
            }

            if needsAmount(action) {
                TextField(amountPlaceholder(for: action), text: $amount)
                    .decimalPadKeyboard()
                    .textFieldStyle(.roundedBorder)
                Text(amountHelper(for: action))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if isStreetClosed {
                Text("本街行动已闭合：如果漏记，用下方「本街路线」插入 / 编辑；否则直接进入下一街。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Button {
                    recordCurrentAction(hand)
                } label: {
                    Text("记录 \(currentActor.map { PokerLogic.positionLabel($0) } ?? "当前玩家") \(resolvedAction)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRecordCurrentAction)
            }

            HStack {
                Button("跳过不记") {
                    guard let currentActor else { return }
                    actor = PokerLogic.nextActorAfterManualSkip(after: currentActor, hand: hand, street: street) ?? ""
                    syncActionChoice(with: hand, actorOverride: actor)
                }
                .buttonStyle(.bordered)
                .disabled(isStreetClosed)

                Button("插入/修正") {
                    openInsert(at: (hand.streets[street]?.actions.count ?? 0), hand: hand)
                }
                .buttonStyle(.bordered)

                Spacer()

                if !(hand.streets[street]?.actions.isEmpty ?? true) {
                    Button("撤销上一条") { undo(hand) }
                        .font(.footnote.weight(.semibold))
                }
            }
        }
    }

    private func routePreview(_ hand: PokerHand) -> some View {
        let actions = hand.streets[street]?.actions ?? []

        return CardPanel {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title: "本街路线", subtitle: "自动生成。点任一动作可编辑、前后插入或删除。")
                Spacer()
                Button("+ 插入") { openInsert(at: actions.count, hand: hand) }
                    .font(.footnote.weight(.semibold))
            }

            if actions.isEmpty {
                EmptyStateView(text: "尚未记录本街行动。请从上方行动顺序开始。")
            } else {
                Text(PokerLogic.routeText(actions, session: store.session))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        openInsert(at: 0, hand: hand)
                    } label: {
                        insertRowLabel("+ 插入到开头", hand: hand, index: 0)
                    }
                    .buttonStyle(.plain)

                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                        Menu {
                            Button("编辑这条") { openEdit(index: index, action: item) }
                            Button("插入到这条之前") { openInsert(at: index, hand: hand) }
                            Button("插入到这条之后") { openInsert(at: index + 1, hand: hand) }
                            Button("删除这条", role: .destructive) { deleteAction(hand, index: index) }
                        } label: {
                            routeActionRow(index: index, action: item)
                        }

                        if index < actions.count - 1 {
                            Button {
                                openInsert(at: index + 1, hand: hand)
                            } label: {
                                insertRowLabel("+ 插入遗漏动作", hand: hand, index: index + 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func routeActionRow(index: Int, action: HandAction) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(index + 1).")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(PokerLogic.actionText(action, session: store.session))
                .font(.subheadline)
                .foregroundStyle(action.hero ? .blue : .primary)
            if action.hero {
                Text("Hero")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
            Spacer()
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func insertRowLabel(_ title: String, hand: PokerHand, index: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(PokerLogic.positionLabel(PokerLogic.predictedActorForInsertion(at: index, hand: hand, street: street)))
                .foregroundStyle(.secondary)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.appTertiaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var mutationActionOptions: [String] {
        street == .preflop
            ? ["fold", "limp", "open", "call", "raise", "3bet", "4bet", "all-in", "自定义"]
            : ["check", "bet", "call", "raise", "fold", "all-in", "自定义"]
    }

    private func actionChoices(for hand: PokerHand, actor position: String) -> [String] {
        let analysis = PokerLogic.streetAnalysis(for: hand, street: street)
        let callAmount = analysis.callAmount(for: position)

        if street == .preflop {
            if callAmount > 0 {
                return analysis.currentBetBB <= forcedPreflopBet(hand)
                    ? ["fold", "limp", "open", "all-in", "自定义"]
                    : ["fold", "call", "raise", "all-in", "自定义"]
            }
            return ["check", "raise", "all-in", "自定义"]
        }

        return callAmount > 0
            ? ["fold", "call", "raise", "all-in", "自定义"]
            : ["check", "bet", "all-in", "自定义"]
    }

    private func forcedPreflopBet(_ hand: PokerHand) -> Double {
        max(1, hand.straddles.map(\.amountBB).max() ?? 1)
    }

    private func displayAction(_ option: String, callAmount: Double) -> String {
        if option == "call", callAmount > 0 {
            return "call \(PokerLogic.formatAmount(callAmount, session: store.session))"
        }
        return option
    }

    private func needsAmount(_ action: String) -> Bool {
        ["open", "bet", "raise", "3bet", "4bet", "all-in"].contains(action)
    }

    private func requiresAmount(_ action: String) -> Bool {
        ["open", "bet", "raise", "3bet", "4bet"].contains(action)
    }

    private func amountPlaceholder(for action: String) -> String {
        let unit = store.session?.unit == .chips ? "筹码值" : "bb"
        if action == "all-in" { return "All-in 投入 / 到多少\(unit)，可空" }
        return "输入到多少\(unit)"
    }

    private func amountHelper(for action: String) -> String {
        if action == "all-in" {
            return "All-in 不填金额也能记录，但底池会标记为估算。"
        }
        return "下注和加注统一按「to X」记录，方便系统重算底池。"
    }

    private var resolvedAction: String {
        if action == "自定义" {
            return customAction.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return action
    }

    private var canRecordCurrentAction: Bool {
        guard !resolvedAction.isEmpty else { return false }
        if requiresAmount(action) {
            return Double(amount) != nil
        }
        return true
    }

    private func actorOptions(_ hand: PokerHand) -> [String] {
        PokerLogic.positions(for: hand.playerCount)
    }

    private func positionState(_ position: String, currentActor: String?, actions: [HandAction]) -> String {
        if position == currentActor { return "当前" }
        guard let last = actions.last(where: { $0.actor == position }) else { return "待行动" }
        let normalized = PokerLogic.normalizedAction(last.action)
        if PokerLogic.isFoldAction(normalized) { return "已弃牌" }
        if PokerLogic.isAllInAction(normalized) { return "All-in" }
        return "已行动"
    }

    private func positionTextColor(position: String, hand: PokerHand, actorsNeedingAction: Set<String>) -> Color {
        if !actorsNeedingAction.contains(position) { return .secondary }
        return position == hand.heroPosition ? .blue : .primary
    }

    private func orderLabel(_ position: String, hand: PokerHand) -> String {
        position == hand.heroPosition ? "\(position) Hero" : position
    }

    private func syncActor(with hand: PokerHand) {
        actor = PokerLogic.nextActorIfNeeded(for: hand, street: street) ?? ""
    }

    private func syncActionChoice(with hand: PokerHand, actorOverride: String? = nil) {
        guard let currentActor = actorOverride ?? (actor.isEmpty ? PokerLogic.nextActorIfNeeded(for: hand, street: street) : actor) else {
            action = ""
            amount = ""
            customAction = ""
            return
        }
        let choices = actionChoices(for: hand, actor: currentActor)
        if !choices.contains(action) {
            action = choices.first ?? ""
            amount = ""
            customAction = ""
        }
    }

    private func recordCurrentAction(_ hand: PokerHand) {
        var updated = hand
        var record = updated.streets[street] ?? StreetRecord()
        guard let recommendedActor = PokerLogic.nextActorIfNeeded(for: hand, street: street) else { return }
        let actorsNeedingAction = PokerLogic.actorsNeedingAction(for: hand, street: street)
        let currentActor = actorsNeedingAction.contains(actor) ? actor : recommendedActor
        record.actions.append(
            HandAction(
                actor: currentActor,
                action: resolvedAction,
                amountBB: enteredAmountBB,
                hero: currentActor == hand.heroPosition
            )
        )
        updated.streets[street] = recalculatedRecord(record, hand: updated, street: street)
        store.saveHand(updated)
        amount = ""
        customAction = ""
        actor = PokerLogic.nextActorIfNeeded(for: updated, street: street) ?? ""
        syncActionChoice(with: updated)
    }

    private func applyMutation(_ target: RouteActionSheetTarget, hand: PokerHand, actor: String, action: String, amountBB: Double?) {
        switch target.kind {
        case .insert:
            insertAction(hand, index: target.index, actor: actor, action: action, amountBB: amountBB)
        case .edit:
            updateAction(hand, index: target.index, actor: actor, action: action, amountBB: amountBB)
        }
    }

    private func insertAction(_ hand: PokerHand, index: Int, actor: String, action: String, amountBB: Double?) {
        var updated = hand
        var record = updated.streets[street] ?? StreetRecord()
        let safeIndex = min(max(index, 0), record.actions.count)
        record.actions.insert(HandAction(actor: actor, action: action, amountBB: amountBB, hero: actor == hand.heroPosition), at: safeIndex)
        updated.streets[street] = recalculatedRecord(record, hand: updated, street: street)
        store.saveHand(updated)
        self.actor = PokerLogic.nextActorIfNeeded(for: updated, street: street) ?? ""
        syncActionChoice(with: updated)
    }

    private func updateAction(_ hand: PokerHand, index: Int, actor: String, action: String, amountBB: Double?) {
        var updated = hand
        var record = updated.streets[street] ?? StreetRecord()
        guard record.actions.indices.contains(index) else { return }
        record.actions[index] = HandAction(actor: actor, action: action, amountBB: amountBB, hero: actor == hand.heroPosition)
        updated.streets[street] = recalculatedRecord(record, hand: updated, street: street)
        store.saveHand(updated)
        self.actor = PokerLogic.nextActorIfNeeded(for: updated, street: street) ?? ""
        syncActionChoice(with: updated)
    }

    private func deleteAction(_ hand: PokerHand, index: Int) {
        var updated = hand
        var record = updated.streets[street] ?? StreetRecord()
        guard record.actions.indices.contains(index) else { return }
        record.actions.remove(at: index)
        updated.streets[street] = recalculatedRecord(record, hand: updated, street: street)
        store.saveHand(updated)
        actor = PokerLogic.nextActorIfNeeded(for: updated, street: street) ?? ""
        syncActionChoice(with: updated)
    }

    private func undo(_ hand: PokerHand) {
        var updated = hand
        var record = updated.streets[street] ?? StreetRecord()
        guard !record.actions.isEmpty else { return }
        record.actions.removeLast()
        updated.streets[street] = recalculatedRecord(record, hand: updated, street: street)
        store.saveHand(updated)
        actor = PokerLogic.nextActorIfNeeded(for: updated, street: street) ?? ""
        syncActionChoice(with: updated)
    }

    private func recalculatedRecord(_ record: StreetRecord, hand: PokerHand, street: StreetKey) -> StreetRecord {
        var draft = hand
        draft.streets[street] = record
        let analysis = PokerLogic.streetAnalysis(for: draft, street: street)
        var updatedRecord = record
        updatedRecord.potBB = analysis.potBB
        updatedRecord.confidence = analysis.confidence
        return updatedRecord
    }

    private var enteredAmountBB: Double? {
        guard let rawAmount = Double(amount) else { return nil }
        return PokerLogic.amountToBB(rawAmount, session: store.session)
    }

    private func openInsert(at index: Int, hand: PokerHand) {
        let predicted = PokerLogic.predictedActorForInsertion(at: index, hand: hand, street: street)
        sheetTarget = RouteActionSheetTarget(
            kind: .insert,
            street: street,
            index: index,
            initialActor: predicted,
            initialAction: mutationActionOptions.first ?? "call",
            initialAmountBB: nil
        )
    }

    private func openEdit(index: Int, action: HandAction) {
        sheetTarget = RouteActionSheetTarget(
            kind: .edit,
            street: street,
            index: index,
            initialActor: action.actor,
            initialAction: action.action,
            initialAmountBB: action.amountBB
        )
    }

    private func next(_ hand: PokerHand) {
        guard let index = StreetKey.allCases.firstIndex(of: street) else { return }
        if street == .river {
            var updated = hand
            updated.status = .complete
            store.saveHand(updated)
            if !path.isEmpty { path.removeLast() }
            path.append(.detail(updated.id))
        } else {
            street = StreetKey.allCases[index + 1]
        }
    }

    private func blockedCards(in hand: PokerHand, currentStreet: StreetKey) -> [PlayingCard] {
        let otherBoard = StreetKey.allCases
            .filter { $0 != currentStreet }
            .flatMap { hand.streets[$0]?.board ?? [] }
        return hand.heroCards + otherBoard
    }

    private func boardCards(in hand: PokerHand, through currentStreet: StreetKey) -> [PlayingCard] {
        guard let currentIndex = StreetKey.allCases.firstIndex(of: currentStreet) else { return [] }
        var board: [PlayingCard] = []
        for (index, key) in StreetKey.allCases.enumerated() {
            guard key != .preflop, index <= currentIndex else { continue }
            board.append(contentsOf: hand.streets[key]?.board ?? [])
        }
        return board
    }
}

struct RouteActionSheetTarget: Identifiable {
    enum Kind {
        case insert
        case edit
    }

    let id = UUID()
    var kind: Kind
    var street: StreetKey
    var index: Int
    var initialActor: String
    var initialAction: String
    var initialAmountBB: Double?
}

struct RouteActionMutationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let session: ReviewSession?
    let hand: PokerHand
    let target: RouteActionSheetTarget
    let actionOptions: [String]
    let onSave: (String, String, Double?) -> Void

    @State private var actor: String
    @State private var action: String
    @State private var customAction = ""
    @State private var amount = ""

    init(
        session: ReviewSession?,
        hand: PokerHand,
        target: RouteActionSheetTarget,
        actionOptions: [String],
        onSave: @escaping (String, String, Double?) -> Void
    ) {
        self.session = session
        self.hand = hand
        self.target = target
        self.actionOptions = actionOptions
        self.onSave = onSave

        let existingOption = actionOptions.contains(target.initialAction) ? target.initialAction : "自定义"
        _actor = State(initialValue: target.initialActor)
        _action = State(initialValue: existingOption)
        _customAction = State(initialValue: existingOption == "自定义" ? target.initialAction : "")
        _amount = State(initialValue: Self.displayAmount(target.initialAmountBB, session: session))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(target.kind == .insert ? "插入后会自动重算行动顺序、当前下注和底池。" : "保存后会自动重算行动顺序、当前下注和底池。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("位置") {
                    Picker("位置", selection: $actor) {
                        ForEach(PokerLogic.positions(for: hand.playerCount), id: \.self) { position in
                            Text(PokerLogic.positionLabel(position)).tag(position)
                        }
                    }
                }

                Section("动作") {
                    Picker("动作", selection: $action) {
                        ForEach(actionOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    if action == "自定义" {
                        TextField("自定义动作", text: $customAction)
                    }
                    if needsAmount(action) || action == "自定义" {
                        TextField(amountPlaceholder(for: action), text: $amount)
                            .decimalPadKeyboard()
                    }
                }
            }
            .navigationTitle(target.kind == .insert ? "插入动作" : "编辑动作")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(target.kind == .insert ? "插入" : "保存") {
                        onSave(actor, resolvedAction, amountBB)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var resolvedAction: String {
        if action == "自定义" {
            return customAction.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return action
    }

    private var amountBB: Double? {
        guard let rawAmount = Double(amount) else { return nil }
        return PokerLogic.amountToBB(rawAmount, session: session)
    }

    private var canSave: Bool {
        guard !resolvedAction.isEmpty else { return false }
        if ["open", "bet", "raise", "3bet", "4bet"].contains(action) {
            return Double(amount) != nil
        }
        return true
    }

    private func needsAmount(_ action: String) -> Bool {
        ["open", "bet", "raise", "3bet", "4bet", "all-in"].contains(action)
    }

    private func amountPlaceholder(for action: String) -> String {
        let unit = session?.unit == .chips ? "筹码值" : "bb"
        if action == "all-in" { return "All-in 投入 / 到多少\(unit)，可空" }
        if action == "自定义" { return "金额，可空" }
        return "输入到多少\(unit)"
    }

    private static func displayAmount(_ amountBB: Double?, session: ReviewSession?) -> String {
        guard let amountBB else { return "" }
        if session?.unit == .chips {
            return PokerLogic.trim(amountBB * (session?.bb ?? 1))
        }
        return PokerLogic.trim(amountBB)
    }
}
