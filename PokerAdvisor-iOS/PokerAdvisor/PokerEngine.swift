import Foundation

// Texas Hold'em equity + decision engine.
// Card id = rank*4 + suit, rank 2...14 (J=11 Q=12 K=13 A=14), suit 0...3.
// Ported from the validated web engine (matches textbook equities within ~0.1pp).

struct SimResult {
    let win: Double
    let tie: Double
    let topCat: Int
    var equity: Double { win + tie * 0.5 }
}

struct Decision {
    let action: String   // FOLD / CHECK / CALL / BET / RAISE
    let amount: String   // e.g. "call 50"  ("" if none)
    let reason: String
}

enum PokerEngine {

    static let handNames = ["High card", "One pair", "Two pair", "Three of a kind",
                            "Straight", "Flush", "Full house", "Four of a kind", "Straight flush"]

    // MARK: - 7-card evaluator (higher score = better hand)

    @inline(__always)
    static func straightHigh(_ maskIn: Int) -> Int {
        var mask = maskIn
        if mask & (1 << 14) != 0 { mask |= (1 << 1) } // ace can be low
        var hi = 14
        while hi >= 5 {
            let want = 0b11111 << (hi - 4)
            if (mask & want) == want { return hi }
            hi -= 1
        }
        return 0
    }

    @inline(__always)
    static func enc(_ c: Int, _ a: Int = 0, _ b: Int = 0, _ cc: Int = 0, _ d: Int = 0, _ e: Int = 0) -> Int {
        c * 1048576 + a * 65536 + b * 4096 + cc * 256 + d * 16 + e
    }

    static func evaluate7(_ ids: [Int]) -> Int {
        var rc = [Int](repeating: 0, count: 15)
        var sc = [Int](repeating: 0, count: 4)
        var sm = [Int](repeating: 0, count: 4)
        var rankMask = 0
        for id in ids {
            let r = id >> 2, s = id & 3
            rc[r] += 1; sc[s] += 1; sm[s] |= (1 << r); rankMask |= (1 << r)
        }
        var flushSuit = -1
        for s in 0..<4 where sc[s] >= 5 { flushSuit = s; break }

        // straight flush
        if flushSuit >= 0 {
            let sf = straightHigh(sm[flushSuit])
            if sf > 0 { return enc(8, sf) }
        }
        // group ranks by multiplicity (high to low)
        var q = 0, t = 0, t2 = 0, p1 = 0, p2 = 0
        var r = 14
        while r >= 2 {
            let n = rc[r]
            if n == 4 { q = r }
            else if n == 3 { if t == 0 { t = r } else if t2 == 0 { t2 = r } }
            else if n == 2 { if p1 == 0 { p1 = r } else if p2 == 0 { p2 = r } }
            r -= 1
        }
        // four of a kind
        if q != 0 {
            var k = 0, rr = 14
            while rr >= 2 { if rr != q && rc[rr] > 0 { k = rr; break }; rr -= 1 }
            return enc(7, q, k)
        }
        // full house
        if t != 0 && (t2 != 0 || p1 != 0) { return enc(6, t, t2 != 0 ? t2 : p1) }
        // flush
        if flushSuit >= 0 {
            let m = sm[flushSuit]
            var rs = [Int](); var rr = 14
            while rr >= 2 && rs.count < 5 { if m & (1 << rr) != 0 { rs.append(rr) }; rr -= 1 }
            return enc(5, rs[0], rs[1], rs[2], rs[3], rs[4])
        }
        // straight
        let st = straightHigh(rankMask)
        if st > 0 { return enc(4, st) }
        // trips
        if t != 0 {
            var k1 = 0, k2 = 0, rr = 14
            while rr >= 2 { if rc[rr] == 1 { if k1 == 0 { k1 = rr } else if k2 == 0 { k2 = rr; break } }; rr -= 1 }
            return enc(3, t, k1, k2)
        }
        // two pair
        if p1 != 0 && p2 != 0 {
            var k = 0, rr = 14
            while rr >= 2 { if rr != p1 && rr != p2 && rc[rr] > 0 { k = rr; break }; rr -= 1 }
            return enc(2, p1, p2, k)
        }
        // one pair
        if p1 != 0 {
            var k1 = 0, k2 = 0, k3 = 0, rr = 14
            while rr >= 2 { if rc[rr] == 1 { if k1 == 0 { k1 = rr } else if k2 == 0 { k2 = rr } else if k3 == 0 { k3 = rr; break } }; rr -= 1 }
            return enc(1, p1, k1, k2, k3)
        }
        // high card
        var a = 0, b = 0, c = 0, d = 0, e = 0, rr = 14
        while rr >= 2 { if rc[rr] == 1 { if a == 0 { a = rr } else if b == 0 { b = rr } else if c == 0 { c = rr } else if d == 0 { d = rr } else if e == 0 { e = rr; break } }; rr -= 1 }
        return enc(0, a, b, c, d, e)
    }

    // MARK: - Seeded RNG (deterministic: same hand -> same verdict)

    struct SeededRNG {
        var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        @inline(__always) mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        @inline(__always) mutating func index(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    static func seedFrom(_ hero: [Int], _ board: [Int], _ players: Int) -> UInt64 {
        var h: UInt64 = 1469598103934665603 // FNV offset basis
        func mix(_ x: Int) { h = (h ^ UInt64(x & 0xff)) &* 1099511628211 }
        mix(players)
        for id in hero { mix(id) }
        mix(99)
        for id in board { mix(id) }
        return h
    }

    // MARK: - Monte Carlo simulation

    static func simulate(hero: [Int], board: [Int], players: Int, iters: Int, seed: UInt64? = nil) -> SimResult {
        var rng = SeededRNG(seed: seed ?? seedFrom(hero, board, players))
        var known = [Bool](repeating: false, count: 60)
        for id in hero { known[id] = true }
        for id in board { known[id] = true }
        var deck = [Int](); deck.reserveCapacity(52)
        for id in 8..<60 where !known[id] { deck.append(id) }

        let opponents = players - 1
        let boardNeed = 5 - board.count
        let need = boardNeed + opponents * 2
        let n = deck.count
        var wins = 0, ties = 0
        var topCounts = [Int](repeating: 0, count: 9)
        var hero7 = [Int](repeating: 0, count: 7)
        var opp7 = [Int](repeating: 0, count: 7)

        for _ in 0..<iters {
            var i = 0
            while i < need {
                let j = i + rng.index(n - i)
                deck.swapAt(i, j)
                i += 1
            }
            var hi = 0
            for id in hero { hero7[hi] = id; hi += 1 }
            for id in board { hero7[hi] = id; hi += 1 }
            var bi = 0
            while bi < boardNeed { hero7[hi] = deck[bi]; hi += 1; bi += 1 }
            let heroScore = evaluate7(hero7)
            topCounts[heroScore / 1048576] += 1

            var beaten = false, tiedWith = 0, idx = boardNeed
            var o = 0
            while o < opponents {
                var oi = 0
                opp7[oi] = deck[idx]; oi += 1; idx += 1
                opp7[oi] = deck[idx]; oi += 1; idx += 1
                for id in board { opp7[oi] = id; oi += 1 }
                var bj = 0
                while bj < boardNeed { opp7[oi] = deck[bj]; oi += 1; bj += 1 }
                let os = evaluate7(opp7)
                if os > heroScore { beaten = true; break }
                else if os == heroScore { tiedWith += 1 }
                o += 1
            }
            if beaten { continue }
            if tiedWith > 0 { ties += 1 } else { wins += 1 }
        }
        var topCat = 0, topN = -1
        for c in 0..<9 where topCounts[c] > topN { topN = topCounts[c]; topCat = c }
        return SimResult(win: Double(wins) / Double(iters),
                         tie: Double(ties) / Double(iters),
                         topCat: topCat)
    }

    // MARK: - Decision logic (always one decisive action)

    static func fmt(_ x: Double) -> String {
        if x == x.rounded() { return String(Int(x.rounded())) }
        return String(format: "%.1f", x)
    }

    static func decide(eq: Double, players: Int, pot: Double, toCall: Double) -> Decision {
        let fair = 1.0 / Double(players)
        let eqp = String(format: "%.1f", eq * 100)
        let fairp = String(format: "%.1f", fair * 100)

        // Facing a bet
        if toCall > 0 {
            let potOdds = toCall / (pot + toCall)
            let need = String(format: "%.1f", potOdds * 100)
            let evCall = eq * (pot + toCall) - toCall
            if eq < potOdds {
                return Decision(action: "FOLD", amount: "",
                    reason: "You need \(need)% equity to call \(fmt(toCall)) into a \(fmt(pot)) pot, but you only have \(eqp)%. Calling loses chips long-term (EV ≈ \(fmt(evCall))). Fold.")
            }
            if eq > 0.66 {
                let raise = (pot + toCall) * 0.75
                return Decision(action: "RAISE", amount: "raise to ~\(fmt(raise))",
                    reason: "Big edge: \(eqp)% equity vs the \(need)% you need. Don't just call — raise ~¾ pot to charge weaker hands.")
            }
            return Decision(action: "CALL", amount: "call \(fmt(toCall))",
                reason: "Call. Your \(eqp)% equity beats the \(need)% break-even, so calling profits over time (EV ≈ +\(fmt(evCall))). Not strong enough to raise for value.")
        }

        // No bet to call yet
        if eq >= 0.58 {
            let amt = pot > 0 ? "bet ~\(fmt(pot * 0.66)) (⅔ pot)" : "bet ~½–¾ pot"
            return Decision(action: "BET", amount: amt,
                reason: "Bet for value. \(eqp)% equity is well above your \(fairp)% fair share — build the pot while you're ahead.")
        }
        if eq >= fair {
            let amt = pot > 0 ? "small bet ~\(fmt(pot * 0.4))" : "small bet (~⅓ pot)"
            return Decision(action: "BET", amount: amt,
                reason: "Slightly ahead: \(eqp)% vs \(fairp)% fair share. A small value bet is fine. If someone bets big into you, be ready to fold.")
        }
        return Decision(action: "CHECK", amount: "",
            reason: "Don't bet. \(eqp)% equity is below your \(fairp)% fair share — check and take a free card. If you're facing a bet, enter the amount to call for a call/fold verdict.")
    }
}
