import SwiftUI

struct RouteEditorView: View {
    @EnvironmentObject private var store: HandStore
    let handID: UUID
    @Binding var path: [AppRoute]

    @State private var street: StreetKey = .preflop
    @State private var selectedTemplate = ""
    @State private var actor = ""
    @State private var action = ""
    @State private var customAction = ""
    @State private var amount = ""
    @State private var showInsertSheet = false
    @State private var insertIndex = 0

    private let templates = [
        ("open", "Hero open"),
        ("vsopen", "面对 open"),
        ("limped", "limped / ISO"),
        ("3bet", "3bet pot"),
        ("custom", "自定义")
    ]

    var body: some View {
        Group {
            if let hand = store.hand(id: handID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("补行动路线")
                                .font(.largeTitle.bold())
                            Text("闪记已保存。路线可分街补充，随时返回，不会丢失。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Picker("街", selection: $street) {
                            ForEach(StreetKey.allCases) { key in
                                Text(key.shortTitle).tag(key)
                            }
                        }
                        .pickerStyle(.segmented)

                        if street == .preflop {
                            preflopTemplates(hand)
                            preflopBreakdown(hand)
                        } else {
                            boardPanel(hand)
                        }

                        actionOrderPanel(hand)

                        CardPanel {
                            SectionTitle(title: "本街路线")
                            Text(PokerLogic.routeText(hand.streets[street]?.actions ?? [], session: store.session))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        actionPanel(hand)

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
                .background(Color.appGroupedBackground)
                .navigationTitle("补路线")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("查看回放") { path.append(.detail(hand.id)) }
                    }
                }
                .sheet(isPresented: $showInsertSheet) {
                    if let latest = store.hand(id: handID) {
                        InsertActionSheet(
                            session: store.session,
                            hand: latest,
                            street: street,
                            actorOptions: actorOptions(latest),
                            actionOptions: actionOptions,
                            initialActor: PokerLogic.predictedActorForInsertion(at: insertIndex, hand: latest, street: street)
                        ) { insertedActor, insertedAction, insertedAmountBB, shouldRecalculate in
                            insertAction(
                                hand: latest,
                                index: insertIndex,
                                actor: insertedActor,
                                action: insertedAction,
                                amountBB: insertedAmountBB,
                                shouldRecalculate: shouldRecalculate
                            )
                        }
                    }
                }
                .onAppear {
                    if actor.isEmpty { syncActor(with: hand) }
                    if action.isEmpty { action = actionOptions.first ?? "call" }
                }
                .onChange(of: street) { _ in
                    let hand = store.hand(id: handID)
                    if let hand { syncActor(with: hand) }
                    action = actionOptions.first ?? action
                    amount = ""
                    customAction = ""
                }
            } else {
                EmptyStateView(text: "没有找到这手牌。")
                    .padding()
            }
        }
    }

    private func actionOrderPanel(_ hand: PokerHand) -> some View {
        let order = PokerLogic.actionOrder(for: hand, street: street)

        return CardPanel {
            SectionTitle(title: "行动顺序", subtitle: street == .preflop ? "翻前按位置 / straddle 自动推；Hero 只高亮，不再默认从 Hero 开始。" : "翻后从庄位左手边第一个仍在牌中的玩家开始。")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(order, id: \.self) { position in
                        Text(orderLabel(position, hand: hand))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(actor == position ? .white : (position == hand.heroPosition ? .blue : .primary))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(actor == position ? Color.blue : Color.appSecondaryBackground)
                            .clipShape(Capsule())
                    }
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前行动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(PokerLogic.positionLabel(actor.isEmpty ? PokerLogic.nextActor(for: hand, street: street) : actor))
                        .font(.headline)
                        .foregroundStyle(actor == hand.heroPosition ? .blue : .primary)
                }

                Spacer()

                Menu("改当前玩家") {
                    ForEach(actorOptions(hand), id: \.self) { position in
                        Button(PokerLogic.positionLabel(position)) {
                            actor = position
                        }
                    }
                }
                .font(.footnote.weight(.semibold))
            }

            HStack {
                Button("用系统推荐") {
                    syncActor(with: hand)
                }
                .buttonStyle(.bordered)

                Button("跳过这位") {
                    actor = PokerLogic.nextActor(after: actor, hand: hand, street: street)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func preflopTemplates(_ hand: PokerHand) -> some View {
        CardPanel {
            SectionTitle(title: "翻前结构（可选）", subtitle: selectedTemplate == "custom" ? "自定义不会预填行动；从下方逐条记录即可。" : "点一次生成常见路线；复杂局面也可随时逐条补充。")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                ForEach(templates, id: \.0) { key, label in
                    PillButton(title: label, selected: selectedTemplate == key) {
                        applyTemplate(key, hand: hand)
                    }
                }
            }
        }
    }

    private func preflopBreakdown(_ hand: PokerHand) -> some View {
        let actions = hand.streets[.preflop]?.actions ?? []
        let heroIndex = actions.firstIndex { $0.hero }
        let before = heroIndex.map { Array(actions.prefix($0)) } ?? actions
        let heroAction = heroIndex.map { actions[$0] }
        let after = heroIndex.map { Array(actions.suffix(from: $0 + 1)) } ?? []

        return CardPanel {
            SectionTitle(title: "路线拆解")
            routeBlock(title: "① 前序行动", actions: before, empty: "无人先行动，或前序行动待补。")
            if let heroAction {
                Text("② Hero 决策")
                    .font(.subheadline.weight(.semibold))
                Text(PokerLogic.actionText(heroAction, session: store.session))
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            } else {
                routeBlock(title: "② Hero 决策", actions: [], empty: "待记录：可追加 Hero 的 call、raise、fold 或行动尺度。")
            }
            routeBlock(title: "③ 后续行动", actions: after, empty: "后续行动待补。")
        }
    }

    @ViewBuilder
    private func routeBlock(title: String, actions: [HandAction], empty: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
        if actions.isEmpty {
            Text(empty)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(actions) { item in
                    Text("• \(PokerLogic.actionText(item, session: store.session))")
                        .font(.subheadline)
                }
            }
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

    private func actionPanel(_ hand: PokerHand) -> some View {
        CardPanel {
            HStack {
                SectionTitle(title: "逐条记录行动", subtitle: "默认记录当前行动玩家；漏记时在时间线里点「+ 插入」。")
                Spacer()
                if !(hand.streets[street]?.actions.isEmpty ?? true) {
                    Button("撤销上一条") { undo(hand) }
                        .font(.footnote.weight(.semibold))
                }
            }

            Picker("当前玩家", selection: $actor) {
                ForEach(actorOptions(hand), id: \.self) {
                    Text(PokerLogic.positionLabel($0)).tag($0)
                }
            }
            .pickerStyle(.menu)

            Picker("动作", selection: $action) {
                ForEach(actionOptions, id: \.self) {
                    Text($0).tag($0)
                }
            }
            .pickerStyle(.segmented)

            if action == "自定义" {
                TextField("自定义动作，例如 donk / cold call / tank fold", text: $customAction)
                    .textFieldStyle(.roundedBorder)
            }

            TextField(store.session?.unit == .chips ? "尺度：筹码值，可空" : "尺度：bb，可空", text: $amount)
                .decimalPadKeyboard()
                .textFieldStyle(.roundedBorder)

            Button {
                appendAction(hand)
            } label: {
                Text("记录 \(actor.isEmpty ? "当前玩家" : PokerLogic.positionLabel(actor))")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(resolvedAction.isEmpty)

            Divider()

            timelineList(hand)
        }
    }

    private var actionOptions: [String] {
        street == .preflop ? ["limp", "open", "call", "raise", "3bet", "4bet", "fold", "all-in", "自定义"] : ["check", "bet", "call", "raise", "fold", "all-in", "自定义"]
    }

    private func actorOptions(_ hand: PokerHand) -> [String] {
        Array(Set(PokerLogic.positions(for: hand.playerCount) + ["全桌"])).sorted { lhs, rhs in
            let order = PokerLogic.positions(for: hand.playerCount) + ["全桌"]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }

    private func applyTemplate(_ key: String, hand: PokerHand) {
        selectedTemplate = key
        guard key != "custom" else { return }
        var updated = hand
        let route = PokerLogic.templateRoute(key, hand: hand)
        var record = updated.streets[.preflop] ?? StreetRecord()
        record.potBB = route.potBB
        record.confidence = "estimated"
        record.actions = route.actions
        updated.streets[.preflop] = record
        store.saveHand(updated)
        syncActor(with: updated)
    }

    private func appendAction(_ hand: PokerHand) {
        var updated = hand
        var record = updated.streets[street] ?? StreetRecord()
        let rawAmount = Double(amount)
        let amountBB = rawAmount.map { PokerLogic.amountToBB($0, session: store.session) }
        let safeActor = actor.isEmpty ? PokerLogic.nextActor(for: hand, street: street) : actor
        record.actions.append(HandAction(actor: safeActor, action: resolvedAction, amountBB: amountBB, hero: safeActor == hand.heroPosition))
        updated.streets[street] = record
        store.saveHand(updated)
        amount = ""
        customAction = ""
        actor = PokerLogic.nextActor(for: updated, street: street)
    }

    private func insertAction(hand: PokerHand, index: Int, actor: String, action: String, amountBB: Double?, shouldRecalculate: Bool) {
        var updated = hand
        var record = updated.streets[street] ?? StreetRecord()
        let safeIndex = min(max(index, 0), record.actions.count)
        record.actions.insert(HandAction(actor: actor, action: action, amountBB: amountBB, hero: actor == hand.heroPosition), at: safeIndex)
        updated.streets[street] = record
        store.saveHand(updated)
        if shouldRecalculate {
            self.actor = PokerLogic.nextActor(for: updated, street: street)
        }
    }

    private func undo(_ hand: PokerHand) {
        var updated = hand
        var record = updated.streets[street] ?? StreetRecord()
        guard !record.actions.isEmpty else { return }
        record.actions.removeLast()
        updated.streets[street] = record
        store.saveHand(updated)
        actor = PokerLogic.nextActor(for: updated, street: street)
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

    private var resolvedAction: String {
        if action == "自定义" {
            return customAction.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return action
    }

    private func syncActor(with hand: PokerHand) {
        actor = PokerLogic.nextActor(for: hand, street: street)
    }

    private func orderLabel(_ position: String, hand: PokerHand) -> String {
        position == hand.heroPosition ? "\(position) Hero" : position
    }

    private func timelineList(_ hand: PokerHand) -> some View {
        let actions = hand.streets[street]?.actions ?? []

        return VStack(alignment: .leading, spacing: 10) {
            Text("可修正时间线")
                .font(.subheadline.weight(.semibold))

            insertButton(index: 0, title: actions.isEmpty ? "+ 插入第一条动作" : "+ 插入到开头", hand: hand)

            if actions.isEmpty {
                Text("尚未记录本街行动。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(PokerLogic.actionText(item, session: store.session))
                            .font(.subheadline)
                            .foregroundStyle(item.hero ? .blue : .primary)
                        if item.hero {
                            Text("Hero")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    insertButton(index: index + 1, title: index == actions.count - 1 ? "+ 插入到末尾" : "+ 插入遗漏动作", hand: hand)
                }
            }
        }
    }

    private func insertButton(index: Int, title: String, hand: PokerHand) -> some View {
        Button {
            insertIndex = index
            showInsertSheet = true
        } label: {
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
        .buttonStyle(.plain)
    }
}

struct InsertActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let session: ReviewSession?
    let hand: PokerHand
    let street: StreetKey
    let actorOptions: [String]
    let actionOptions: [String]
    let initialActor: String
    let onInsert: (String, String, Double?, Bool) -> Void

    @State private var actor: String
    @State private var action: String
    @State private var customAction = ""
    @State private var amount = ""
    @State private var shouldRecalculate = false

    init(
        session: ReviewSession?,
        hand: PokerHand,
        street: StreetKey,
        actorOptions: [String],
        actionOptions: [String],
        initialActor: String,
        onInsert: @escaping (String, String, Double?, Bool) -> Void
    ) {
        self.session = session
        self.hand = hand
        self.street = street
        self.actorOptions = actorOptions
        self.actionOptions = actionOptions
        self.initialActor = initialActor
        self.onInsert = onInsert
        _actor = State(initialValue: initialActor)
        _action = State(initialValue: actionOptions.first ?? "call")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("插入动作不会强迫你重写整条路线；默认只是把遗漏动作塞回时间线。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("位置") {
                    Picker("位置", selection: $actor) {
                        ForEach(actorOptions, id: \.self) { position in
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
                    TextField(session?.unit == .chips ? "尺度：筹码值，可空" : "尺度：bb，可空", text: $amount)
                        .decimalPadKeyboard()
                }

                Section {
                    Toggle("插入后重算当前行动玩家", isOn: $shouldRecalculate)
                    Text("默认关闭：只修正文案时间线。打开后，会按插入后的路线重新推荐下一位行动玩家。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("插入遗漏动作")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("插入") {
                        onInsert(actor, resolvedAction, amountBB, shouldRecalculate)
                        dismiss()
                    }
                    .disabled(resolvedAction.isEmpty)
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
}
