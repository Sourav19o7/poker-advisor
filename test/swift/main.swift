import Foundation

func c(_ r: Int, _ s: Int) -> Int { r * 4 + s }

// hand-ranking order
let royal = PokerEngine.evaluate7([c(14,0),c(13,0),c(12,0),c(11,0),c(10,0),c(2,1),c(3,1)])
let quad  = PokerEngine.evaluate7([c(9,0),c(9,1),c(9,2),c(9,3),c(2,0),c(5,1),c(7,2)])
let fh    = PokerEngine.evaluate7([c(9,0),c(9,1),c(9,2),c(2,0),c(2,1),c(5,1),c(7,2)])
let flush = PokerEngine.evaluate7([c(2,0),c(5,0),c(9,0),c(11,0),c(13,0),c(3,1),c(4,2)])
let wheel = PokerEngine.evaluate7([c(14,0),c(2,1),c(3,2),c(4,3),c(5,0),c(13,1),c(11,2)])
print("order royal>quad>fh>flush:", royal>quad && quad>fh && fh>flush)
print("wheel is straight (cat4):", wheel/1048576 == 4)

func eq(_ name: String, _ h: [Int], _ p: Int, _ exp: String) {
    let r = PokerEngine.simulate(hero: h, board: [], players: p, iters: 100000)
    print(name, String(format: "%.2f", r.win*100) + "%  (exp \(exp))")
}
eq("AA  vs1 ", [c(14,0),c(14,1)], 2, "~85")
eq("AA  vs4 ", [c(14,0),c(14,1)], 5, "~56")
eq("AKs vs1 ", [c(14,0),c(13,0)], 2, "~67")
eq("72o vs1 ", [c(7,0),c(2,1)],   2, "~32 win")

// determinism: same hand twice -> identical
let d1 = PokerEngine.simulate(hero: [c(14,0),c(14,1)], board: [], players: 4, iters: 100000)
let d2 = PokerEngine.simulate(hero: [c(14,0),c(14,1)], board: [], players: 4, iters: 100000)
print("deterministic:", d1.win == d2.win && d1.tie == d2.tie)

// decision smoke
let dec = PokerEngine.decide(eq: 0.638, players: 4, pot: 100, toCall: 50)
print("decide(63.8%, call 50 into 100):", dec.action, "/", dec.amount)
