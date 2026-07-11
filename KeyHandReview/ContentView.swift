import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: HandStore
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.session == nil {
                    SetupView()
                } else {
                    HomeView(path: $path)
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .quick(let id):
                    QuickHandView(handID: id, path: $path)
                case .route(let id):
                    RouteEditorView(handID: id, path: $path)
                case .detail(let id):
                    DetailView(handID: id, path: $path)
                case .inbox:
                    InboxView(path: $path)
                }
            }
        }
    }
}

struct SetupView: View {
    @EnvironmentObject private var store: HandStore
    @State private var sb = "1"
    @State private var bb = "2"
    @State private var currency = "U"
    @State private var playerCount = 8
    @State private var unit: AmountUnit = .bb
    @State private var straddleEnabled = true
    @State private var straddlePosition = "UTG"
    @State private var straddleAmount = "4"
    @State private var errorMessage: String?

    private let currencies = ["U", "¥", "$", "₩"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("新建复盘记录")
                        .font(.largeTitle.bold())
                    Text("只记录值得复盘的关键手牌，所有内容保存在本机。")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                CardPanel {
                    SectionTitle(title: "盲注与筹码单位")
                    HStack {
                        TextField("小盲", text: $sb)
                            .decimalPadKeyboard()
                            .textFieldStyle(.roundedBorder)
                        TextField("大盲", text: $bb)
                            .decimalPadKeyboard()
                            .textFieldStyle(.roundedBorder)
                        Picker("单位", selection: $currency) {
                            ForEach(currencies, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }

                CardPanel {
                    SectionTitle(title: "本场默认人数", subtitle: "支持 4–10 人；每手牌里也能临时调整。")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(4...10, id: \.self) { count in
                            PillButton(title: "\(count) 人", selected: playerCount == count) {
                                playerCount = count
                            }
                        }
                    }
                }

                CardPanel {
                    SectionTitle(title: "本场默认 straddle")
                    HStack {
                        PillButton(title: "无", selected: !straddleEnabled) { straddleEnabled = false }
                        PillButton(title: "UTG", selected: straddleEnabled) { straddleEnabled = true; straddlePosition = "UTG" }
                    }
                    if straddleEnabled {
                        HStack {
                            Picker("位置", selection: $straddlePosition) {
                                ForEach(["UTG", "BTN"], id: \.self) {
                                    Text(PokerLogic.positionLabel($0)).tag($0)
                                }
                            }
                            .pickerStyle(.menu)
                            TextField("筹码值", text: $straddleAmount)
                                .decimalPadKeyboard()
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                CardPanel {
                    SectionTitle(title: "默认显示单位")
                    HStack {
                        ForEach(AmountUnit.allCases) { option in
                            PillButton(title: option.label, selected: unit == option) {
                                unit = option
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    start()
                } label: {
                    Text("开始记录")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("手牌复盘速记")
    }

    private func start() {
        guard let sbValue = Double(sb), let bbValue = Double(bb), sbValue > 0, bbValue > 0 else {
            errorMessage = "请填写有效的盲注。"
            return
        }
        let straddles: [Straddle]
        if straddleEnabled {
            let chipValue = Double(straddleAmount) ?? bbValue * 2
            straddles = [Straddle(position: straddlePosition, amountBB: chipValue / bbValue)]
        } else {
            straddles = []
        }
        store.startSession(sb: sbValue, bb: bbValue, currency: currency, unit: unit, playerCount: playerCount, straddles: straddles)
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: HandStore
    @Binding var path: [AppRoute]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let session = store.session {
                    CardPanel {
                        Text("本次核心目标")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("只抓住关键手牌")
                            .font(.title2.bold())
                        Text("大池量、纠结牌、对手读牌；其他牌不打扰。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Label("\(store.hands.count) 已保存", systemImage: "tray.full")
                            Spacer()
                            Label("\(store.hands.filter { $0.status == .draft }.count) 待补全", systemImage: "pencil.and.list.clipboard")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                        Text("\(PokerLogic.trim(session.sb))/\(PokerLogic.trim(session.bb)) NLH · 默认 \(session.playerCount) 人桌 · \(session.straddles.isEmpty ? "默认无 straddle" : "默认有 straddle")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    if let hand = store.createDraft() {
                        path.append(.quick(hand.id))
                    }
                } label: {
                    Text("＋ 记关键牌")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("一手结束后打开，先保存，再补完整路线。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                HStack {
                    Text("手牌记录")
                        .font(.headline)
                    Spacer()
                    Button("待复盘") { path.append(.inbox) }
                }

                if store.hands.isEmpty {
                    EmptyStateView(text: "还没有记录。下一手纠结或有学习价值的牌后，点“记关键牌”。")
                } else {
                    VStack(spacing: 12) {
                        ForEach(store.hands) { hand in
                            Button {
                                path.append(hand.status == .draft ? .route(hand.id) : .detail(hand.id))
                            } label: {
                                HandRow(hand: hand, session: store.session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("手牌复盘速记")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(store.session?.unit == .bb ? "bb" : "筹码") {
                    guard var session = store.session else { return }
                    session.unit = session.unit == .bb ? .chips : .bb
                    store.saveSession(session)
                }
            }
        }
    }
}

struct HandRow: View {
    let hand: PokerHand
    let session: ReviewSession?

    var body: some View {
        CardPanel {
            HStack {
                ForEach(hand.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tag == "纠结" ? .orange : .blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((tag == "纠结" ? Color.orange : Color.blue).opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
                Text("\(PokerLogic.completeness(hand))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("\(PokerLogic.positionLabel(hand.heroPosition)) · \(hand.heroCards.map(\.display).joined(separator: " ").ifEmpty("手牌待补")) · \(PokerLogic.formatAmount(hand.effectiveStackBB, session: session))")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("\(hand.playerCount) 人桌\(hand.straddles.isEmpty ? "" : " · 有 straddle") · \(PokerLogic.handSummary(hand, session: session)) · \(hand.status == .draft ? "待补全 · 点击继续补行动路线" : "已完成 · 点击查看回放")")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ProgressView(value: Double(PokerLogic.completeness(hand)), total: 100)
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
