#!/usr/bin/env swift
// 生成 FileHound 应用图标（macOS Big Sur 及之后的图标网格：1024 画布 + 824 连续圆角矩形）。
// 用法：swift Scripts/generate_app_icon.swift [输出目录]
// 默认输出到 FileHound/Assets.xcassets/AppIcon.appiconset。

import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(
        colorsSpace: colorSpace,
        colors: stops.map(\.1) as CFArray,
        locations: stops.map(\.0)
    )!
}

// MARK: - 形状

/// Apple 风格的连续曲率圆角矩形（squircle）。
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2 / 1.52866483)
    // 每个角：起点、(终点, 控制点1, 控制点2) 序列，坐标为 (沿来向边距离, 沿去向边距离) * r
    let corners: [(CGPoint, CGVector, CGVector)] = [
        (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: 0, dy: 1), CGVector(dx: 1, dy: 0)),
        (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1)),
        (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0)),
        (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1)),
    ]
    let path = CGMutablePath()
    for (index, (origin, e1, e2)) in corners.enumerated() {
        func p(_ a: CGFloat, _ b: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + (a * e1.dx + b * e2.dx) * r, y: origin.y + (a * e1.dy + b * e2.dy) * r)
        }
        if index == 0 { path.move(to: p(1.52866483, 0)) } else { path.addLine(to: p(1.52866483, 0)) }
        path.addCurve(to: p(0.66993427, 0.06549600), control1: p(1.08849323, 0), control2: p(0.86840689, 0))
        path.addLine(to: p(0.63149399, 0.07491100))
        path.addCurve(to: p(0.07491100, 0.63149399), control1: p(0.37282392, 0.16905899), control2: p(0.16905899, 0.37282392))
        path.addLine(to: p(0.06549600, 0.66993427))
        path.addCurve(to: p(0, 1.52866483), control1: p(0, 0.86840689), control2: p(0, 1.08849323))
    }
    path.closeSubpath()
    return path
}

let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let iconShape = continuousRoundedRect(iconRect, radius: 185)

// 文档
let doc = CGRect(x: 236, y: 172, width: 368, height: 560)
let fold: CGFloat = 112
let docShape: CGPath = {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: doc.minX + 44, y: doc.minY))
    path.addArc(tangent1End: CGPoint(x: doc.maxX - fold, y: doc.minY), tangent2End: CGPoint(x: doc.maxX, y: doc.minY + fold), radius: 14)
    path.addArc(tangent1End: CGPoint(x: doc.maxX, y: doc.minY + fold), tangent2End: CGPoint(x: doc.maxX, y: doc.maxY), radius: 14)
    path.addArc(tangent1End: CGPoint(x: doc.maxX, y: doc.maxY), tangent2End: CGPoint(x: doc.minX, y: doc.maxY), radius: 44)
    path.addArc(tangent1End: CGPoint(x: doc.minX, y: doc.maxY), tangent2End: CGPoint(x: doc.minX, y: doc.minY), radius: 44)
    path.addArc(tangent1End: CGPoint(x: doc.minX, y: doc.minY), tangent2End: CGPoint(x: doc.maxX - fold, y: doc.minY), radius: 44)
    path.closeSubpath()
    return path
}()
let foldShape: CGPath = {
    let path = CGMutablePath()
    let a = CGPoint(x: doc.maxX - fold, y: doc.minY)
    let b = CGPoint(x: doc.maxX, y: doc.minY + fold)
    let corner = CGPoint(x: doc.maxX - fold, y: doc.minY + fold)
    path.move(to: a)
    path.addArc(tangent1End: corner, tangent2End: b, radius: 22)
    path.addLine(to: b)
    path.closeSubpath()
    return path
}()

struct TextLine { let y: CGFloat; let width: CGFloat; let height: CGFloat; let color: UInt32 }
let textLeft = doc.minX + 58
let textLines: [TextLine] = [
    TextLine(y: doc.minY + 112, width: 150, height: 28, color: 0x7C8CA8),
    TextLine(y: doc.minY + 200, width: 252, height: 18, color: 0xC3CDDD),
    TextLine(y: doc.minY + 262, width: 220, height: 18, color: 0xC3CDDD),
    TextLine(y: doc.minY + 324, width: 252, height: 18, color: 0xC3CDDD),
    TextLine(y: doc.minY + 386, width: 210, height: 18, color: 0x45516A), // 命中行
    TextLine(y: doc.minY + 448, width: 252, height: 18, color: 0xC3CDDD),
    TextLine(y: doc.minY + 510, width: 160, height: 18, color: 0xC3CDDD),
]
let matchLine = textLines[4]

// 放大镜
let lensCenter = CGPoint(x: doc.minX + 296, y: doc.minY + 386 + 9)
let lensInner: CGFloat = 126
let lensOuter: CGFloat = 166
let magnification: CGFloat = 1.75

// MARK: - 绘制

func fillLinear(_ ctx: CGContext, _ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func drawBackground(_ ctx: CGContext) {
    fillLinear(ctx, iconShape, gradient([
        (0, color(0x56B4FF)),
        (0.55, color(0x2D7BF4)),
        (1, color(0x2346D8)),
    ]), from: CGPoint(x: 512, y: iconRect.minY), to: CGPoint(x: 512, y: iconRect.maxY))

    // 顶部柔光
    ctx.saveGState()
    ctx.addPath(iconShape)
    ctx.clip()
    ctx.drawRadialGradient(
        gradient([(0, color(0xFFFFFF, 0.28)), (1, color(0xFFFFFF, 0))]),
        startCenter: CGPoint(x: 340, y: 150), startRadius: 0,
        endCenter: CGPoint(x: 340, y: 150), endRadius: 560, options: []
    )
    ctx.restoreGState()
}

func drawDocument(_ ctx: CGContext, shadow: Bool) {
    ctx.saveGState()
    if shadow {
        ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 44, color: color(0x0B1F6B, 0.40))
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    fillLinear(ctx, docShape, gradient([(0, color(0xFFFFFF)), (1, color(0xEAF0F8))]),
               from: CGPoint(x: 0, y: doc.minY), to: CGPoint(x: 0, y: doc.maxY))
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // 折角
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -4, height: -6), blur: 12, color: color(0x0B1F6B, 0.18))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    fillLinear(ctx, foldShape, gradient([(0, color(0xF5F8FD)), (1, color(0xD3DCEA))]),
               from: CGPoint(x: doc.maxX - fold, y: doc.minY + fold), to: CGPoint(x: doc.maxX - fold / 2, y: doc.minY + fold / 2))
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // 命中高亮
    let marker = CGRect(x: textLeft - 18, y: matchLine.y - 16, width: matchLine.width + 36, height: matchLine.height + 32)
    ctx.addPath(CGPath(roundedRect: marker, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(color(0xFFD60A))
    ctx.fillPath()

    for line in textLines {
        let rect = CGRect(x: textLeft, y: line.y, width: line.width, height: line.height)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: line.height / 2, cornerHeight: line.height / 2, transform: nil))
        ctx.setFillColor(color(line.color))
        ctx.fillPath()
    }
}

func drawLens(_ ctx: CGContext) {
    let inner = CGPath(ellipseIn: CGRect(x: lensCenter.x - lensInner, y: lensCenter.y - lensInner, width: lensInner * 2, height: lensInner * 2), transform: nil)

    // 镜片内放大的内容
    ctx.saveGState()
    ctx.addPath(inner)
    ctx.clip()
    ctx.translateBy(x: lensCenter.x, y: lensCenter.y)
    ctx.scaleBy(x: magnification, y: magnification)
    ctx.translateBy(x: -lensCenter.x, y: -lensCenter.y)
    drawBackground(ctx)
    drawDocument(ctx, shadow: true)
    ctx.restoreGState()

    // 玻璃质感
    ctx.saveGState()
    ctx.addPath(inner)
    ctx.clip()
    ctx.drawRadialGradient(
        gradient([(0, color(0xFFFFFF, 0)), (0.75, color(0xBFE3FF, 0.10)), (1, color(0x7FBFFF, 0.35))]),
        startCenter: lensCenter, startRadius: 0, endCenter: lensCenter, endRadius: lensInner, options: []
    )
    // 左上高光
    let glare = CGMutablePath()
    glare.addEllipse(in: CGRect(x: lensCenter.x - lensInner * 0.86, y: lensCenter.y - lensInner * 0.92, width: lensInner * 1.05, height: lensInner * 0.62),
                     transform: CGAffineTransform(translationX: lensCenter.x, y: lensCenter.y).rotated(by: -.pi / 5).translatedBy(x: -lensCenter.x, y: -lensCenter.y))
    ctx.addPath(glare)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(0, color(0xFFFFFF, 0.55)), (1, color(0xFFFFFF, 0))]),
        start: CGPoint(x: lensCenter.x - lensInner * 0.6, y: lensCenter.y - lensInner * 0.8),
        end: CGPoint(x: lensCenter.x - lensInner * 0.1, y: lensCenter.y - lensInner * 0.1), options: []
    )
    ctx.restoreGState()

    // 镜片内缘阴影
    ctx.saveGState()
    ctx.addPath(inner)
    ctx.clip()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x000000, 0.35))
    ctx.addRect(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    ctx.addPath(inner)
    ctx.setFillColor(color(0x000000))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
}

func drawMagnifierBody(_ ctx: CGContext) {
    let ring = CGMutablePath()
    ring.addEllipse(in: CGRect(x: lensCenter.x - lensOuter, y: lensCenter.y - lensOuter, width: lensOuter * 2, height: lensOuter * 2))
    ring.addEllipse(in: CGRect(x: lensCenter.x - lensInner, y: lensCenter.y - lensInner, width: lensInner * 2, height: lensInner * 2))

    // 手柄：在旋转坐标系中沿 +x 方向绘制（45° 指向右下）
    let rotate = CGAffineTransform(translationX: lensCenter.x, y: lensCenter.y).rotated(by: .pi / 4)
    let gripRect = CGRect(x: lensOuter + 40, y: -42, width: 156, height: 84)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(0x07134A, 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    // 颈部
    ctx.saveGState()
    ctx.concatenate(rotate)
    fillLinear(ctx, CGPath(roundedRect: CGRect(x: lensOuter - 12, y: -26, width: 64, height: 52), cornerWidth: 8, cornerHeight: 8, transform: nil),
               gradient([(0, color(0x9AA3B4)), (0.5, color(0x5D6577)), (1, color(0x2F343F))]),
               from: CGPoint(x: 0, y: -26), to: CGPoint(x: 0, y: 26))
    ctx.restoreGState()

    // 镜圈
    ctx.saveGState()
    ctx.addPath(ring)
    ctx.clip(using: .evenOdd)
    ctx.drawLinearGradient(
        gradient([(0, color(0x6A7284)), (0.45, color(0x3A404D)), (1, color(0x1A1D24))]),
        start: CGPoint(x: lensCenter.x - lensOuter * 0.7, y: lensCenter.y - lensOuter * 0.7),
        end: CGPoint(x: lensCenter.x + lensOuter * 0.7, y: lensCenter.y + lensOuter * 0.7), options: []
    )
    ctx.restoreGState()

    // 握柄
    ctx.saveGState()
    ctx.concatenate(rotate)
    fillLinear(ctx, CGPath(roundedRect: gripRect, cornerWidth: 42, cornerHeight: 42, transform: nil),
               gradient([(0, color(0x5A6172)), (0.35, color(0x343945)), (1, color(0x14161B))]),
               from: CGPoint(x: 0, y: -42), to: CGPoint(x: 0, y: 42))
    // 握柄高光
    let shine = CGRect(x: gripRect.minX + 28, y: -28, width: gripRect.width - 52, height: 12)
    ctx.addPath(CGPath(roundedRect: shine, cornerWidth: 6, cornerHeight: 6, transform: nil))
    ctx.setFillColor(color(0xFFFFFF, 0.22))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // 镜圈外缘与内缘高光
    ctx.saveGState()
    ctx.setLineWidth(3)
    ctx.addEllipse(in: CGRect(x: lensCenter.x - lensOuter + 1.5, y: lensCenter.y - lensOuter + 1.5, width: lensOuter * 2 - 3, height: lensOuter * 2 - 3))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(0, color(0xFFFFFF, 0.55)), (0.5, color(0xFFFFFF, 0.05)), (1, color(0xFFFFFF, 0))]),
        start: CGPoint(x: lensCenter.x - lensOuter, y: lensCenter.y - lensOuter),
        end: CGPoint(x: lensCenter.x + lensOuter * 0.4, y: lensCenter.y + lensOuter * 0.4), options: []
    )
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setLineWidth(3)
    ctx.addEllipse(in: CGRect(x: lensCenter.x - lensInner - 1.5, y: lensCenter.y - lensInner - 1.5, width: lensInner * 2 + 3, height: lensInner * 2 + 3))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(0, color(0xFFFFFF, 0)), (0.6, color(0xFFFFFF, 0.08)), (1, color(0xFFFFFF, 0.40))]),
        start: CGPoint(x: lensCenter.x - lensInner, y: lensCenter.y - lensInner),
        end: CGPoint(x: lensCenter.x + lensInner, y: lensCenter.y + lensInner), options: []
    )
    ctx.restoreGState()
}

func renderMaster() -> CGImage {
    let ctx = CGContext(
        data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    // 翻转为左上角原点，便于按设计稿坐标绘制
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)

    // 底板投影（macOS 图标模板）
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.30))
    ctx.addPath(iconShape)
    ctx.setFillColor(color(0x2D7BF4))
    ctx.fillPath()
    ctx.restoreGState()

    drawBackground(ctx)

    ctx.saveGState()
    ctx.addPath(iconShape)
    ctx.clip()
    drawDocument(ctx, shadow: true)
    drawMagnifierBody(ctx)
    drawLens(ctx)
    ctx.restoreGState()

    // 底板内描边
    ctx.saveGState()
    ctx.addPath(iconShape)
    ctx.clip()
    ctx.setLineWidth(4)
    ctx.addPath(iconShape)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(0, color(0xFFFFFF, 0.45)), (0.3, color(0xFFFFFF, 0.08)), (1, color(0x000000, 0.10))]),
        start: CGPoint(x: 512, y: iconRect.minY), end: CGPoint(x: 512, y: iconRect.maxY), options: []
    )
    ctx.restoreGState()

    return ctx.makeImage()!
}

func resized(_ image: CGImage, to pixels: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AppIcon", code: 1)
    }
    try data.write(to: url)
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let defaultOutput = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("FileHound/Assets.xcassets/AppIcon.appiconset")
let outputDir = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : defaultOutput

let master = renderMaster()
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = scale == 1 ? "app_icon_\(base).png" : "app_icon_\(base)@2x.png"
        let image = pixels == Int(canvas) ? master : resized(master, to: pixels)
        try writePNG(image, to: outputDir.appendingPathComponent(name))
    }
}
print("已生成图标到 \(outputDir.path)")
