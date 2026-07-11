import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct StreetDisplay: Identifiable {
    let id: StreetKey
    let title: String
    let board: [PlayingCard]
    let potText: String
    let actions: [HandAction]
}

struct DetailView: View {
    @EnvironmentObject private var store: HandStore
    let handID: UUID
    @Binding var path: [AppRoute]

    @State private var review = ReviewNote()
    @State private var copied = false

    var body: some View {
        Group {
            if let hand = store.hand(id: handID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        replayHeader(hand)

                        ForEach(streetDisplays(hand)) { item in
                            streetReplay(item)
                        }

                        reviewPanel(hand)

                        let markdown = PokerLogic.markdown(for: hand, session: store.session)
                        HStack {
                            Button("复制 Markdown") {
                                copy(markdown)
                                copied = true
                            }
                            .buttonStyle(.borderedProminent)

                            ShareLink(item: markdown) {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
                .background(Color.appGroupedBackground)
                .navigationTitle("回放")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        if hand.status == .draft {
                            Button("继续补路线") { path.append(.route(hand.id)) }
                        }
                    }
                }
                .onAppear {
                    review = hand.review
                }
                .alert("已复制", isPresented: $copied) {
                    Button("好", role: .cancel) { }
                } message: {
                    Text("Markdown 已复制到剪贴板。")
                }
            } else {
                EmptyStateView(text: "没有找到这手牌。")
                    .padding()
            }
        }
    }

    private func replayHeader(_ hand: PokerHand) -> some View {
        CardPanel {
            Text("\(PokerLogic.positionLabel(hand.heroPosition)) \(hand.heroCards.map(\.display).joined(separator: " ").ifEmpty("手牌待补"))")
                .font(.title.bold())

            if let session = store.session {
                Text("\(PokerLogic.trim(session.sb))/\(PokerLogic.trim(session.bb)) NLH · \(hand.playerCount) 人桌 · 有效后手 \(PokerLogic.formatAmount(hand.effectiveStackBB, session: session, paired: true))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(hand.heroCards) { card in
                    CardText(card: card, large: true)
                }
                if hand.heroCards.isEmpty {
                    Text("▢ ▢")
                        .font(.title.bold())
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                ForEach(PokerLogic.normalizedHandTags(hand.tags), id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(tagColor(for: tag))
                        .background(tagColor(for: tag).opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func streetReplay(_ item: StreetDisplay) -> some View {
        CardPanel {
            HStack {
                Text(item.title)
                    .font(.headline)
                Spacer()
                Text(item.potText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !item.board.isEmpty {
                HStack(spacing: 8) {
                    ForEach(item.board) { card in
                        CardText(card: card)
                    }
                }
            } else if item.id == .preflop {
                Text("按行动路线回放翻前参与过程")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if item.actions.isEmpty {
                Text("本街行动待补。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.actions) { action in
                        Text(PokerLogic.actionText(action, session: store.session, paired: true))
                            .font(.subheadline.weight(action.hero ? .bold : .regular))
                            .foregroundStyle(action.hero ? .blue : .primary)
                    }
                }
            }
        }
    }

    private func reviewPanel(_ hand: PokerHand) -> some View {
        CardPanel {
            SectionTitle(title: "复盘")

            Text("关键决策")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $review.decision)
                .frame(minHeight: 70)
                .padding(8)
                .background(Color.appSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("当时依据")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $review.basis)
                .frame(minHeight: 70)
                .padding(8)
                .background(Color.appSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("下次默认修正")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $review.correction)
                .frame(minHeight: 70)
                .padding(8)
                .background(Color.appSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                var updated = hand
                updated.review = review
                store.saveHand(updated)
                path.removeAll()
            } label: {
                Text("保存并返回首页")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func streetDisplays(_ hand: PokerHand) -> [StreetDisplay] {
        var board: [PlayingCard] = []
        return StreetKey.allCases.compactMap { key in
            guard let record = hand.streets[key] else { return nil }
            if key != .preflop { board.append(contentsOf: record.board) }
            let shouldShow = !record.actions.isEmpty || (key != .preflop && !board.isEmpty)
            guard shouldShow else { return nil }
            let potText = record.potBB.map {
                "\(record.confidence == "estimated" ? "约 " : "")\(PokerLogic.formatAmount($0, session: store.session, paired: true))"
            } ?? "池量待补"
            return StreetDisplay(id: key, title: key.title, board: board, potText: potText, actions: record.actions)
        }
    }

    private func copy(_ markdown: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = markdown
        #endif
    }

    private func tagColor(for tag: String) -> Color {
        switch tag {
        case "诈唬": return .purple
        case "抓诈": return .orange
        case "Hero Fold": return .red
        case "价值": return .green
        case "冤家": return .pink
        case "自定义": return .secondary
        default: return .blue
        }
    }
}

struct InboxView: View {
    @EnvironmentObject private var store: HandStore
    @Binding var path: [AppRoute]
    @State private var copied = false

    private var sortedHands: [PokerHand] {
        store.hands.filter(PokerLogic.isSavedHand).sorted {
            let lhsNeedsCompletion = PokerLogic.needsCompletion($0)
            let rhsNeedsCompletion = PokerLogic.needsCompletion($1)
            if lhsNeedsCompletion != rhsNeedsCompletion {
                return lhsNeedsCompletion
            }
            if ($0.status == .draft) != ($1.status == .draft) {
                return $0.status == .draft
            }
            return $0.createdAt > $1.createdAt
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("待复盘")
                        .font(.largeTitle.bold())
                    Text("待补全优先，最新在前。")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("待补全")
                    Text("最新记录")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

                if sortedHands.isEmpty {
                    EmptyStateView(text: "还没有可复盘的手牌。")
                } else {
                    ForEach(sortedHands) { hand in
                        Button {
                            path.append(hand.status == .draft ? .route(hand.id) : .detail(hand.id))
                        } label: {
                            HandRow(hand: hand, session: store.session)
                        }
                        .buttonStyle(.plain)
                    }
                }

                let markdown = PokerLogic.markdown(for: sortedHands, session: store.session)
                HStack {
                    Button("复制全部 Markdown") {
                        copy(markdown)
                        copied = true
                    }
                    .buttonStyle(.borderedProminent)
                    ShareLink(item: markdown) {
                        Label("分享全部", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("待复盘")
        .inlineNavigationTitle()
        .alert("已复制", isPresented: $copied) {
            Button("好", role: .cancel) { }
        } message: {
            Text("Markdown 已复制到剪贴板。")
        }
    }

    private func copy(_ markdown: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = markdown
        #endif
    }
}
