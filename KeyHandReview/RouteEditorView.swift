import SwiftUI

struct RouteEditorView: View {
    @EnvironmentObject private var store: HandStore
    let handID: UUID
    @Binding var path: [AppRoute]

    @State private var street: StreetKey = .preflop
    @State private var selectedTemplate = ""
    @State private var actor = ""
    @State private var action = ""
    @State private var amount = ""

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
                .onAppear {
                    if actor.isEmpty { actor = hand.heroPosition }
                    if action.isEmpty { action = actionOptions.first ?? "call" }
                }
                .onChange(of: street) { _ in
                    let hand = store.hand(id: handID)
                    actor = hand?.heroPosition ?? actor
                    action = actionOptions.first ?? action
                    amount = ""
                }
            } else {
                EmptyStateView(text: "没有找到这手牌。")
                    .padding()
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
                SectionTitle(title: "逐条记录行动")
                Spacer()
                if !(hand.streets[street]?.actions.isEmpty ?? true) {
                    Button("撤销上一条") { undo(hand) }
                        .font(.footnote.weight(.semibold))
                }
            }

            if let actions = hand.streets[street]?.actions, !actions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                        Text("\(index + 1). \(PokerLogic.actionText(item, session: store.session))")
                            .font(.subheadline)
                            .foregroundStyle(item.hero ? .blue : .primary)
                    }
                }
            }

            Picker("位置", selection: $actor) {
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

            TextField(store.session?.unit == .chips ? "尺度：筹码值，可空" : "尺度：bb，可空", text: $amount)
                .decimalPadKeyboard()
                .textFieldStyle(.roundedBorder)

            Button {
                appendAction(hand)
            } label: {
                Text("记录这条")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var actionOptions: [String] {
        street == .preflop ? ["limp", "open", "call", "raise", "3bet", "4bet", "fold", "all-in"] : ["check", "bet", "call", "raise", "fold", "all-in"]
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
    }

    private func appendAction(_ hand: PokerHand) {
        var updated = hand
        var record = updated.streets[street] ?? StreetRecord()
        let rawAmount = Double(amount)
        let amountBB = rawAmount.map { PokerLogic.amountToBB($0, session: store.session) }
        record.actions.append(HandAction(actor: actor, action: action, amountBB: amountBB, hero: actor == hand.heroPosition))
        updated.streets[street] = record
        store.saveHand(updated)
        amount = ""
    }

    private func undo(_ hand: PokerHand) {
        var updated = hand
        var record = updated.streets[street] ?? StreetRecord()
        guard !record.actions.isEmpty else { return }
        record.actions.removeLast()
        updated.streets[street] = record
        store.saveHand(updated)
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
}
