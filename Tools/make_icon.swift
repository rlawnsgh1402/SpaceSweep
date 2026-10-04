// SpaceSweep 앱 아이콘 생성: swift Tools/make_icon.swift <출력.png>
// 디스크 사용량 게이지(링) + 가운데 반짝임 = "공간을 깨끗하게"
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// 1. macOS 아이콘 격자: 824x824 둥근 사각형, 여백 100
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// 그림자
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0, 0, 0, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(rgb(40, 60, 200)); ctx.fillPath()
ctx.restoreGState()

// 배경 그라디언트 (인디고 → 청록)
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [rgb(88, 86, 255), rgb(46, 140, 255), rgb(30, 205, 230)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
// 위쪽 은은한 광택
let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [rgb(255, 255, 255, 0.22), rgb(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.midY), options: [])
ctx.restoreGState()

let c = CGPoint(x: size / 2, y: size / 2 - 6)

// 2. 게이지 링: 바탕 링 + 4분의 3 채워진 흰색 호
let r: CGFloat = 270
let lw: CGFloat = 64
ctx.setLineCap(.round)
ctx.setLineWidth(lw)
ctx.setStrokeColor(rgb(255, 255, 255, 0.22))
ctx.addArc(center: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: rgb(10, 30, 120, 0.35))
ctx.setStrokeColor(rgb(255, 255, 255))
let start = CGFloat.pi / 2                 // 12시 방향에서 시작
ctx.addArc(center: c, radius: r, startAngle: start, endAngle: start - .pi * 1.45, clockwise: true)
ctx.strokePath()
ctx.restoreGState()

// 3. 가운데 반짝임(4각 별) + 작은 별 두 개
func sparkle(_ p: CGPoint, _ s: CGFloat, _ alpha: CGFloat) {
    let path = CGMutablePath()
    let k: CGFloat = 0.22  // 오목한 정도
    path.move(to: CGPoint(x: p.x, y: p.y + s))
    path.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: CGPoint(x: p.x + s * k, y: p.y + s * k))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: CGPoint(x: p.x + s * k, y: p.y - s * k))
    path.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: CGPoint(x: p.x - s * k, y: p.y - s * k))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: CGPoint(x: p.x - s * k, y: p.y + s * k))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: rgb(10, 30, 120, 0.35))
    ctx.addPath(path); ctx.setFillColor(rgb(255, 255, 255, alpha)); ctx.fillPath()
    ctx.restoreGState()
}
sparkle(c, 150, 1)
sparkle(CGPoint(x: c.x + 118, y: c.y + 120), 46, 0.95)
sparkle(CGPoint(x: c.x - 112, y: c.y - 112), 30, 0.85)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("아이콘 생성: \(out)")
