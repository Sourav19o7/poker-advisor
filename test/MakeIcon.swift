import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("ctx")
}
let S = CGFloat(size)

// ---- Background: subtle charcoal radial gradient (premium, near-black) ----
let bgColors = [CGColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1),
                CGColor(red: 0.04, green: 0.04, blue: 0.045, alpha: 1)] as CFArray
let bg = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0, 1])!
ctx.drawRadialGradient(bg,
                       startCenter: CGPoint(x: S*0.5, y: S*0.60), startRadius: 0,
                       endCenter: CGPoint(x: S*0.5, y: S*0.5), endRadius: S*0.78,
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// ---- Poker-chip ring (thin, dashed outer rim) ----
let center = CGPoint(x: S*0.5, y: S*0.5)
ctx.setStrokeColor(CGColor(red: 0.5, green: 0.5, blue: 0.52, alpha: 0.9))
ctx.setLineWidth(S*0.014)
ctx.addEllipse(in: CGRect(x: center.x - S*0.40, y: center.y - S*0.40, width: S*0.80, height: S*0.80))
ctx.strokePath()
// dashed inner accent ring
ctx.setStrokeColor(CGColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 0.65))
ctx.setLineWidth(S*0.020)
ctx.setLineDash(phase: 0, lengths: [S*0.052, S*0.052])
ctx.addEllipse(in: CGRect(x: center.x - S*0.345, y: center.y - S*0.345, width: S*0.69, height: S*0.69))
ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])

// ---- Spade (built from triangle + two lobes + stalk; union via nonzero fill) ----
ctx.saveGState()
let scale = S * 0.0044                 // design space is ~100 units tall
ctx.translateBy(x: S*0.5, y: S*0.5)
ctx.scaleBy(x: scale, y: -scale)       // flip so design y is top-down
ctx.translateBy(x: -50, y: -52)

// Use even-odd-safe union: fill each subpath independently with the same color
// by clipping to a combined path built so all subpaths wind the same way.
let spade = CGMutablePath()
// upper triangle (clockwise in y-down to match CGPath ellipse winding)
spade.move(to: CGPoint(x: 50, y: 8))
spade.addLine(to: CGPoint(x: 84, y: 55))
spade.addLine(to: CGPoint(x: 16, y: 55))
spade.closeSubpath()
// left & right lobes
spade.addEllipse(in: CGRect(x: 8, y: 33, width: 44, height: 44))
spade.addEllipse(in: CGRect(x: 48, y: 33, width: 44, height: 44))
// stalk (flared base, clockwise)
spade.move(to: CGPoint(x: 47, y: 66))
spade.addCurve(to: CGPoint(x: 53, y: 66),
               control1: CGPoint(x: 53, y: 78), control2: CGPoint(x: 57, y: 86))
spade.addLine(to: CGPoint(x: 62, y: 92))
spade.addLine(to: CGPoint(x: 38, y: 92))
spade.addCurve(to: CGPoint(x: 47, y: 66),
               control1: CGPoint(x: 43, y: 86), control2: CGPoint(x: 47, y: 78))
spade.closeSubpath()

// clip to spade, fill with a soft white -> light-gray vertical gradient
ctx.addPath(spade)
ctx.clip(using: .winding)
let spColors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                CGColor(red: 0.80, green: 0.80, blue: 0.82, alpha: 1)] as CFArray
let spGrad = CGGradient(colorsSpace: cs, colors: spColors, locations: [0, 1])!
ctx.drawLinearGradient(spGrad,
                       start: CGPoint(x: 50, y: 8), end: CGPoint(x: 50, y: 92),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

// ---- Write PNG ----
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let url = URL(fileURLWithPath: outPath)
guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("dest")
}
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")
