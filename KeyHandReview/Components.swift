import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    static var appGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGroupedBackground)
        #else
        return Color.gray.opacity(0.08)
        #endif
    }

    static var appSecondaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color.gray.opacity(0.12)
        #endif
    }

    static var appTertiaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.tertiarySystemBackground)
        #else
        return Color.gray.opacity(0.06)
        #endif
    }
}

extension View {
    @ViewBuilder
    func decimalPadKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

struct CardPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
    }
}

struct PillButton: View {
    let title: String
    var selected = false
    var warning = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 42)
                .background(selected ? (warning ? Color.orange : Color.blue) : Color.appSecondaryBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CardText: View {
    let card: PlayingCard
    var large = false

    var body: some View {
        Text(card.display)
            .font(.system(size: large ? 30 : 20, weight: .bold, design: .rounded))
            .foregroundStyle(card.suit.isRed ? Color.red : Color.primary)
            .frame(width: large ? 62 : 46, height: large ? 78 : 56)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
    }
}

struct CardPickerView: View {
    @Binding var cards: [PlayingCard]
    var maxCards: Int
    var blockedCards: [PlayingCard] = []
    var emptyLabels: [String] = []
    var helper = "先选牌槽，再点花色和点数；会自动防止重复。"

    @State private var activeSlot = 0
    @State private var selectedSuit: Suit = .spade

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(0..<maxCards, id: \.self) { index in
                    Button {
                        let firstEmpty = cards.count < maxCards ? cards.count : nil
                        activeSlot = min(index, firstEmpty ?? index)
                    } label: {
                        Text(label(for: index))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(cardColor(for: index))
                            .frame(width: 82, height: 58)
                            .background(activeSlot == index ? Color.blue.opacity(0.14) : Color.appSecondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(activeSlot == index ? Color.blue : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("清除") {
                    cards.removeAll()
                    activeSlot = 0
                }
                .font(.footnote.weight(.semibold))
            }

            HStack(spacing: 10) {
                ForEach(Suit.allCases) { suit in
                    Button {
                        selectedSuit = suit
                    } label: {
                        Text(suit.rawValue)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(suit.isRed ? Color.red : Color.primary)
                            .frame(width: 48, height: 42)
                            .background(selectedSuit == suit ? Color.blue.opacity(0.14) : Color.appSecondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(PokerLogic.ranks, id: \.self) { rank in
                    let card = PlayingCard(rank: rank, suit: selectedSuit)
                    Button {
                        choose(card)
                    } label: {
                        Text(rank)
                            .font(.headline)
                            .foregroundStyle(disabled(card) ? .secondary : .primary)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(disabled(card) ? Color.appTertiaryBackground : Color.appSecondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .disabled(disabled(card))
                    .buttonStyle(.plain)
                }
            }

            Text(helper)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChange(of: cards) { _ in
            if activeSlot >= maxCards { activeSlot = max(0, maxCards - 1) }
        }
    }

    private func label(for index: Int) -> String {
        if index < cards.count { return cards[index].display }
        if index < emptyLabels.count { return emptyLabels[index] }
        return "选牌"
    }

    private func cardColor(for index: Int) -> Color {
        guard index < cards.count else { return .secondary }
        return cards[index].suit.isRed ? .red : .primary
    }

    private func disabled(_ card: PlayingCard) -> Bool {
        if blockedCards.contains(card) { return true }
        let target = min(activeSlot, cards.count)
        return cards.enumerated().contains { index, existing in
            existing == card && index != target
        }
    }

    private func choose(_ card: PlayingCard) {
        guard !disabled(card) else { return }
        var updated = cards
        let target = min(activeSlot, updated.count)
        if target < updated.count {
            updated[target] = card
        } else if updated.count < maxCards {
            updated.append(card)
        }
        cards = updated
        if target + 1 < maxCards {
            activeSlot = target + 1
        }
    }
}

struct EmptyStateView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(28)
            .background(Color.appSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
