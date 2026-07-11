import SwiftUI

struct QuickHandView: View {
    @EnvironmentObject private var store: HandStore
    let handID: UUID
    @Binding var path: [AppRoute]

    @State private var hand = PokerHand()
    @State private var customStack = ""
    @State private var errorMessage: String?

    private let tagOptions = PokerLogic.handTagOptions
    private let stacks: [Double] = [50, 75, 100, 150, 200, 300]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("快速保存")
                        .font(.largeTitle.bold())
                    Text("先保住“为什么这手值得复盘”。")
                        .foregroundStyle(.secondary)
                }

                CardPanel {
                    SectionTitle(title: "标记这手", subtitle: "至少选一个。")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(tagOptions, id: \.self) { tag in
                            PillButton(title: tag, selected: PokerLogic.normalizedHandTags(hand.tags).contains(tag)) {
                                toggleTag(tag)
                            }
                        }
                    }
                }

                CardPanel {
                    SectionTitle(title: "本手桌况", subtitle: "默认沿用上一手；有人进出桌时再调整。")

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(4...10, id: \.self) { count in
                            PillButton(title: "\(count) 人", selected: hand.playerCount == count) {
                                choosePlayerCount(count)
                            }
                        }
                    }

                    Text("Hero 位置")
                        .font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                        ForEach(PokerLogic.positions(for: hand.playerCount), id: \.self) { position in
                            PillButton(title: PokerLogic.positionLabel(position), selected: hand.heroPosition == position) {
                                hand.heroPosition = position
                            }
                        }
                    }

                    Text("本手 straddle")
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        PillButton(title: "无", selected: hand.straddles.isEmpty) {
                            hand.straddles = []
                        }
                        PillButton(title: "枪口位（UTG）", selected: hand.straddles.first?.position == "UTG") {
                            setStraddle("UTG")
                        }
                        PillButton(title: "庄位（BTN）", selected: hand.straddles.first?.position == "BTN") {
                            setStraddle("BTN")
                        }
                    }
                }

                CardPanel {
                    SectionTitle(title: "有效后手")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(stacks, id: \.self) { stack in
                            PillButton(title: PokerLogic.formatAmount(stack, session: store.session), selected: hand.effectiveStackBB == stack && customStack.isEmpty) {
                                hand.effectiveStackBB = stack
                                customStack = ""
                            }
                        }
                    }
                    TextField(store.session?.unit == .chips ? "或输入其他筹码值" : "或输入其他 bb", text: $customStack)
                        .decimalPadKeyboard()
                        .textFieldStyle(.roundedBorder)
                }

                CardPanel {
                    SectionTitle(title: "Hero 手牌（可跳过）")
                    CardPickerView(
                        cards: $hand.heroCards,
                        maxCards: 2,
                        emptyLabels: ["第 1 张", "第 2 张"],
                        helper: "第二张会自动切换；同一张牌不能重复选择。"
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    saveAndContinue()
                } label: {
                    Text("立即保存")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("记关键牌")
        .inlineNavigationTitle()
        .onAppear {
            if let loaded = store.hand(id: handID) {
                hand = loaded
                hand.tags = PokerLogic.normalizedHandTags(loaded.tags)
            }
        }
    }

    private func toggleTag(_ tag: String) {
        var tags = PokerLogic.normalizedHandTags(hand.tags)
        if let index = tags.firstIndex(of: tag) {
            tags.remove(at: index)
        } else {
            tags.append(tag)
        }
        hand.tags = tags
    }

    private func choosePlayerCount(_ count: Int) {
        hand.playerCount = count
        let positions = PokerLogic.positions(for: count)
        if !positions.contains(hand.heroPosition) {
            hand.heroPosition = positions.contains("CO") ? "CO" : (positions.first ?? "UTG")
        }
    }

    private func setStraddle(_ position: String) {
        hand.straddles = [Straddle(position: position, amountBB: 2)]
    }

    private func saveAndContinue() {
        hand.tags = PokerLogic.normalizedHandTags(hand.tags)
        guard !hand.tags.isEmpty else {
            errorMessage = "至少选择一个标签。"
            return
        }
        guard !hand.heroPosition.isEmpty else {
            errorMessage = "请确认本手 Hero 位置。"
            return
        }
        if let value = Double(customStack), value > 0 {
            hand.effectiveStackBB = PokerLogic.amountToBB(value, session: store.session)
        }
        store.saveHand(hand)
        if !path.isEmpty { path.removeLast() }
        path.append(.route(hand.id))
    }
}
