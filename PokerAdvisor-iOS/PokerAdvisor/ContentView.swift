import SwiftUI
import UIKit

// MARK: - Palette (premium monochrome)

private enum Palette {
    static let bgTop      = Color(white: 0.05)
    static let bgBottom   = Color.black
    static let panel      = Color(white: 0.10)
    static let panelEdge  = Color(white: 0.20)
    static let textHi     = Color.white
    static let textLo     = Color(white: 0.55)
    static let textFaint  = Color(white: 0.38)
    static let cardFace   = Color.white
    static let pipDark    = Color(white: 0.08)            // spades / clubs
    static let pipRed     = Color(red: 0.84, green: 0.20, blue: 0.22)  // hearts / diamonds
    static let fillHi     = Color.white
    static let fillLo     = Color(white: 0.40)
}

// MARK: - Card helpers

private enum Cardz {
    static let suits = ["♠", "♥", "♦", "♣"]
    static func rank(_ id: Int) -> Int { id >> 2 }
    static func suit(_ id: Int) -> Int { id & 3 }
    static func isRed(_ id: Int) -> Bool { let s = id & 3; return s == 1 || s == 2 }
    static func rankLabel(_ r: Int) -> String {
        switch r { case 14: return "A"; case 13: return "K"; case 12: return "Q"; case 11: return "J"; default: return "\(r)" }
    }
}

private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

// MARK: - Playing card view

private struct CardFace: View {
    let id: Int
    var scale: CGFloat = 1
    var body: some View {
        VStack(spacing: 1 * scale) {
            Text(Cardz.rankLabel(Cardz.rank(id)))
                .font(.system(size: 19 * scale, weight: .bold, design: .rounded))
            Text(Cardz.suits[Cardz.suit(id)])
                .font(.system(size: 15 * scale))
        }
        .foregroundColor(Cardz.isRed(id) ? Palette.pipRed : Palette.pipDark)
        .frame(width: 46 * scale, height: 64 * scale)
        .background(RoundedRectangle(cornerRadius: 9 * scale, style: .continuous).fill(Palette.cardFace))
        .overlay(RoundedRectangle(cornerRadius: 9 * scale, style: .continuous).stroke(Color.black.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 4 * scale, x: 0, y: 2 * scale)
    }
}

private struct EmptySlot: View {
    var label: String
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            .foregroundColor(Palette.textFaint)
            .frame(width: 46, height: 64)
            .overlay(Text(label).font(.system(size: 10)).foregroundColor(Palette.textFaint))
    }
}

// MARK: - Result model

private struct ResultData {
    let decision: Decision
    let win: Double
    let tie: Double
    let equity: Double
    let bestHand: String
}

// MARK: - Main view

struct ContentView: View {
    @State private var hero: [Int] = []
    @State private var board: [Int] = []
    @State private var players: Int = 4
    @State private var potText: String = ""
    @State private var callText: String = ""
    @State private var result: ResultData?
    @State private var calculating = false
    @FocusState private var fieldFocused: Bool

    private var stageLabel: String {
        switch board.count {
        case 5: return "River"
        case 4: return "Turn"
        case 3: return "Flop"
        default: return "Pre-flop"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        handPanel
                        boardPanel
                        deckPanel
                        settingsPanel
                        if let r = result { resultPanel(r).id("result") }
                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .onChange(of: result == nil) { _, isNil in
                    if !isNil { withAnimation { proxy.scrollTo("result", anchor: .bottom) } }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = false }.foregroundColor(.white)
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 3) {
            Text("POKER ADVISOR")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(Palette.textHi)
            Text("Texas Hold'em — math-backed decisions")
                .font(.system(size: 12))
                .foregroundColor(Palette.textLo)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var handPanel: some View {
        Panel(title: "YOUR HAND") {
            HStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { i in
                    if i < hero.count {
                        Button { toggle(hero[i]) } label: { CardFace(id: hero[i]) }
                            .buttonStyle(.plain)
                    } else {
                        EmptySlot(label: "card \(i + 1)")
                    }
                }
                Spacer()
            }
        }
    }

    private var boardPanel: some View {
        Panel(title: "COMMUNITY", trailing: stageLabel) {
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    if i < board.count {
                        Button { toggle(board[i]) } label: { CardFace(id: board[i], scale: 0.92) }
                            .buttonStyle(.plain)
                    } else {
                        EmptySlot(label: "—").frame(width: 42, height: 59)
                    }
                }
            }
        }
    }

    private var deckPanel: some View {
        Panel(title: "PICK CARDS", trailing: "tap to add / remove") {
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { s in
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
                    LazyVGrid(columns: cols, spacing: 6) {
                        ForEach(Array(stride(from: 14, through: 2, by: -1)), id: \.self) { r in
                            let id = r * 4 + s
                            let used = hero.contains(id) || board.contains(id)
                            Button { toggle(id) } label: {
                                CardFace(id: id, scale: 0.74)
                                    .opacity(used ? 0.22 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var settingsPanel: some View {
        Panel(title: "TABLE") {
            VStack(spacing: 16) {
                HStack {
                    Text("Players").foregroundColor(Palette.textLo).font(.system(size: 15))
                    Spacer()
                    Stepperz(value: $players, range: 2...10)
                }
                Divider().overlay(Palette.panelEdge)
                HStack(spacing: 12) {
                    MoneyField(title: "Pot size", text: $potText, focused: $fieldFocused)
                    MoneyField(title: "To call", text: $callText, focused: $fieldFocused)
                }
                Text("Enter “To call” when facing a bet to get a CALL / FOLD / RAISE verdict.")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func resultPanel(_ r: ResultData) -> some View {
        Panel(title: "VERDICT") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.decision.action)
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundColor(Palette.textHi)
                        if !r.decision.amount.isEmpty {
                            Text(r.decision.amount)
                                .font(.system(size: 15))
                                .foregroundColor(Palette.textLo)
                        }
                    }
                    Spacer()
                    Text(String(format: "%.1f%%", r.equity * 100))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color(white: 0.18)))
                        .foregroundColor(Palette.textHi)
                }

                EquityBar(value: r.equity)

                HStack(spacing: 0) {
                    stat("Win", String(format: "%.1f%%", r.win * 100))
                    stat("Tie", String(format: "%.1f%%", r.tie * 100))
                    stat("Equity", String(format: "%.1f%%", r.equity * 100))
                    stat("Best", r.bestHand, wide: true)
                }

                Divider().overlay(Palette.panelEdge)
                Text(r.decision.reason)
                    .font(.system(size: 13.5))
                    .foregroundColor(Palette.textLo)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stat(_ label: String, _ value: String, wide: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: wide ? 14 : 18, weight: .bold, design: .rounded))
                .foregroundColor(Palette.textHi)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 10)).tracking(0.5)
                .foregroundColor(Palette.textFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Text("Win odds from a 100k-deal Monte Carlo simulation.\nA study & play-money aid — gamble responsibly.")
            .font(.system(size: 10))
            .foregroundColor(Palette.textFaint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { clearAll() } label: {
                Text("Clear")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Palette.textHi)
                    .frame(height: 52).padding(.horizontal, 22)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.16)))
            }
            Button { runCalc() } label: {
                ZStack {
                    if calculating {
                        ProgressView().tint(.black)
                    } else {
                        Text("Calculate")
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.fillHi))
            }
            .disabled(calculating)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    // MARK: Logic

    private func toggle(_ id: Int) {
        haptic()
        if let i = hero.firstIndex(of: id) { hero.remove(at: i); return }
        if let i = board.firstIndex(of: id) { board.remove(at: i); return }
        if hero.count < 2 { hero.append(id) }
        else if board.count < 5 { board.append(id) }
    }

    private func clearAll() {
        haptic()
        hero = []; board = []; result = nil; potText = ""; callText = ""
    }

    private func runCalc() {
        fieldFocused = false
        guard hero.count == 2 else { haptic(.rigid); return }
        guard board.count == 0 || board.count >= 3 else { haptic(.rigid); return }

        let h = hero, b = board, p = players
        let pot = max(0, Double(potText) ?? 0)
        let toCall = max(0, Double(callText) ?? 0)
        let iters = p <= 7 ? 100_000 : 60_000

        haptic(.medium)
        calculating = true
        DispatchQueue.global(qos: .userInitiated).async {
            let sim = PokerEngine.simulate(hero: h, board: b, players: p, iters: iters)
            let eq = sim.equity
            let dec = PokerEngine.decide(eq: eq, players: p, pot: pot, toCall: toCall)
            let data = ResultData(decision: dec, win: sim.win, tie: sim.tie, equity: eq,
                                  bestHand: PokerEngine.handNames[sim.topCat])
            DispatchQueue.main.async {
                calculating = false
                withAnimation(.easeOut(duration: 0.25)) { result = data }
                haptic(.light)
            }
        }
    }
}

// MARK: - Reusable components

private struct Panel<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).tracking(1.2)
                    .foregroundColor(Palette.textLo)
                if let trailing {
                    Text("· " + trailing).font(.system(size: 11)).foregroundColor(Palette.textFaint)
                }
                Spacer()
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.panelEdge, lineWidth: 1))
    }
}

private struct Stepperz: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var body: some View {
        HStack(spacing: 14) {
            circle("−") { if value > range.lowerBound { value -= 1; haptic() } }
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Palette.textHi)
                .frame(minWidth: 28)
            circle("+") { if value < range.upperBound { value += 1; haptic() } }
        }
    }
    private func circle(_ s: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(s).font(.system(size: 22, weight: .medium))
                .foregroundColor(Palette.textHi)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color(white: 0.18)))
        }
        .buttonStyle(.plain)
    }
}

private struct MoneyField: View {
    let title: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundColor(Palette.textLo)
            TextField("optional", text: $text)
                .keyboardType(.decimalPad)
                .focused(focused)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(Palette.textHi)
                .padding(.horizontal, 12).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.16)))
        }
    }
}

private struct EquityBar: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.20))
                Capsule()
                    .fill(LinearGradient(colors: [Palette.fillLo, Palette.fillHi],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * value))
            }
        }
        .frame(height: 12)
    }
}

#Preview {
    ContentView().preferredColorScheme(.dark)
}
