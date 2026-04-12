#!/usr/bin/env swift

import AppKit
import Foundation

struct AppIconGenerator {
    let masterSize: CGFloat = 1024
    let outputDirectory: URL

    func run() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let masterURL = outputDirectory.appendingPathComponent("filehound_app_icon_master_1024.png")
        try writeMaster(to: masterURL)

        let exports: [(String, Int)] = [
            ("app_icon_16.png", 16),
            ("app_icon_16@2x.png", 32),
            ("app_icon_32.png", 32),
            ("app_icon_32@2x.png", 64),
            ("app_icon_128.png", 128),
            ("app_icon_128@2x.png", 256),
            ("app_icon_256.png", 256),
            ("app_icon_256@2x.png", 512),
            ("app_icon_512.png", 512),
            ("app_icon_512@2x.png", 1024)
        ]

        for (name, size) in exports {
            let destination = outputDirectory.appendingPathComponent(name)
            try export(masterURL: masterURL, destinationURL: destination, pixelSize: size)
        }
    }

    private func writeMaster(to url: URL) throws {
        let frame = NSRect(x: 0, y: 0, width: masterSize, height: masterSize)
        let view = AppIconView(frame: frame)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: frame) else {
            throw NSError(
                domain: "AppIconGenerator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create bitmap rep"]
            )
        }
        view.cacheDisplay(in: frame, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "AppIconGenerator",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"]
            )
        }
        try data.write(to: url)
    }

    private func export(masterURL: URL, destinationURL: URL, pixelSize: Int) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = [
            "-z", "\(pixelSize)", "\(pixelSize)",
            masterURL.path,
            "--out", destinationURL.path
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "AppIconGenerator",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "sips export failed for \(destinationURL.lastPathComponent)"]
            )
        }
    }
}

final class AppIconView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let plateRect = bounds.insetBy(dx: 56, dy: 56)
        let platePath = NSBezierPath(roundedRect: plateRect, xRadius: 230, yRadius: 230)

        let plateGradient = NSGradient(colors: [
            NSColor(srgbRed: 0.08, green: 0.20, blue: 0.25, alpha: 1),
            NSColor(srgbRed: 0.10, green: 0.33, blue: 0.38, alpha: 1),
            NSColor(srgbRed: 0.05, green: 0.16, blue: 0.19, alpha: 1)
        ])!
        plateGradient.draw(in: platePath, angle: -90)

        let rimPath = NSBezierPath(
            roundedRect: plateRect.insetBy(dx: 8, dy: 8),
            xRadius: 220,
            yRadius: 220
        )
        NSColor.white.withAlphaComponent(0.08).setStroke()
        rimPath.lineWidth = 12
        rimPath.stroke()

        let lensCenter = CGPoint(x: bounds.midX - 36, y: bounds.midY + 20)
        let lensRadius: CGFloat = 240

        let lensShadow = NSShadow()
        lensShadow.shadowBlurRadius = 24
        lensShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        lensShadow.shadowOffset = NSSize(width: 0, height: -8)
        lensShadow.set()

        let lensRect = NSRect(
            x: lensCenter.x - lensRadius,
            y: lensCenter.y - lensRadius,
            width: lensRadius * 2,
            height: lensRadius * 2
        )
        let lensFill = NSBezierPath(ovalIn: lensRect)
        NSColor(srgbRed: 0.75, green: 0.95, blue: 0.96, alpha: 0.20).setFill()
        lensFill.fill()

        let ring = NSBezierPath(ovalIn: lensRect.insetBy(dx: 12, dy: 12))
        NSColor(srgbRed: 0.86, green: 0.98, blue: 0.98, alpha: 0.92).setStroke()
        ring.lineWidth = 34
        ring.stroke()

        let innerGlow = NSBezierPath(ovalIn: lensRect.insetBy(dx: 38, dy: 38))
        NSColor.white.withAlphaComponent(0.14).setStroke()
        innerGlow.lineWidth = 10
        innerGlow.stroke()

        NSGraphicsContext.current?.saveGraphicsState()
        let clipPath = NSBezierPath(ovalIn: lensRect.insetBy(dx: 34, dy: 34))
        clipPath.addClip()

        let fileRect = NSRect(x: lensCenter.x - 132, y: lensCenter.y - 155, width: 260, height: 320)
        let filePath = NSBezierPath(roundedRect: fileRect, xRadius: 34, yRadius: 34)
        NSColor(srgbRed: 0.95, green: 0.99, blue: 0.99, alpha: 0.95).setFill()
        filePath.fill()

        let dogEar = NSBezierPath()
        dogEar.move(to: NSPoint(x: fileRect.maxX - 78, y: fileRect.maxY))
        dogEar.line(to: NSPoint(x: fileRect.maxX, y: fileRect.maxY - 78))
        dogEar.line(to: NSPoint(x: fileRect.maxX, y: fileRect.maxY))
        dogEar.close()
        NSColor(srgbRed: 0.82, green: 0.94, blue: 0.95, alpha: 1).setFill()
        dogEar.fill()

        let lines: [(CGFloat, CGFloat, NSColor)] = [
            (fileRect.maxY - 94, 144, NSColor(srgbRed: 0.11, green: 0.25, blue: 0.30, alpha: 0.95)),
            (fileRect.maxY - 140, 170, NSColor(srgbRed: 0.13, green: 0.31, blue: 0.36, alpha: 0.92)),
            (fileRect.maxY - 186, 182, NSColor(srgbRed: 0.13, green: 0.31, blue: 0.36, alpha: 0.92)),
            (fileRect.maxY - 232, 146, NSColor(srgbRed: 0.13, green: 0.31, blue: 0.36, alpha: 0.92))
        ]

        for (y, width, color) in lines {
            let lineRect = NSRect(x: fileRect.minX + 42, y: y, width: width, height: 24)
            let path = NSBezierPath(roundedRect: lineRect, xRadius: 12, yRadius: 12)
            color.setFill()
            path.fill()
        }

        let hitRect = NSRect(x: fileRect.minX + 38, y: fileRect.maxY - 190, width: 188, height: 34)
        let hitPath = NSBezierPath(roundedRect: hitRect, xRadius: 14, yRadius: 14)
        NSColor(srgbRed: 0.44, green: 0.96, blue: 0.70, alpha: 1).setFill()
        hitPath.fill()

        let gridRect = NSRect(x: fileRect.minX + 42, y: fileRect.minY + 42, width: 176, height: 68)
        for column in 0..<3 {
            let cellRect = NSRect(
                x: gridRect.minX + CGFloat(column) * 58,
                y: gridRect.minY,
                width: 42,
                height: 42
            )
            let cellPath = NSBezierPath(roundedRect: cellRect, xRadius: 10, yRadius: 10)
            NSColor(srgbRed: 0.13, green: 0.31, blue: 0.36, alpha: 0.22).setFill()
            cellPath.fill()
        }

        NSGraphicsContext.current?.restoreGraphicsState()

        let handlePath = NSBezierPath()
        handlePath.move(to: NSPoint(x: lensCenter.x + 168, y: lensCenter.y - 150))
        handlePath.line(to: NSPoint(x: lensCenter.x + 278, y: lensCenter.y - 260))
        NSColor(srgbRed: 0.90, green: 0.98, blue: 0.98, alpha: 0.96).setStroke()
        handlePath.lineWidth = 68
        handlePath.lineCapStyle = .round
        handlePath.stroke()

        let handleCore = NSBezierPath()
        handleCore.move(to: NSPoint(x: lensCenter.x + 170, y: lensCenter.y - 152))
        handleCore.line(to: NSPoint(x: lensCenter.x + 276, y: lensCenter.y - 258))
        NSColor(srgbRed: 0.08, green: 0.23, blue: 0.27, alpha: 0.95).setStroke()
        handleCore.lineWidth = 34
        handleCore.lineCapStyle = .round
        handleCore.stroke()

        let sparkRect = NSRect(x: lensCenter.x + 80, y: lensCenter.y + 118, width: 72, height: 72)
        let sparkPath = NSBezierPath()
        sparkPath.move(to: NSPoint(x: sparkRect.midX, y: sparkRect.maxY))
        sparkPath.line(to: NSPoint(x: sparkRect.midX + 12, y: sparkRect.midY + 12))
        sparkPath.line(to: NSPoint(x: sparkRect.maxX, y: sparkRect.midY))
        sparkPath.line(to: NSPoint(x: sparkRect.midX + 12, y: sparkRect.midY - 12))
        sparkPath.line(to: NSPoint(x: sparkRect.midX, y: sparkRect.minY))
        sparkPath.line(to: NSPoint(x: sparkRect.midX - 12, y: sparkRect.midY - 12))
        sparkPath.line(to: NSPoint(x: sparkRect.minX, y: sparkRect.midY))
        sparkPath.line(to: NSPoint(x: sparkRect.midX - 12, y: sparkRect.midY + 12))
        sparkPath.close()
        NSColor.white.withAlphaComponent(0.95).setFill()
        sparkPath.fill()
    }
}

let arguments = CommandLine.arguments

if arguments.contains("--help") || arguments.contains("-h") {
    print("Usage: swift scripts/generate_app_icon.swift --output-dir <directory>")
    exit(0)
}

guard let outputIndex = arguments.firstIndex(of: "--output-dir"),
      arguments.indices.contains(outputIndex + 1) else {
    fputs("Usage: swift scripts/generate_app_icon.swift --output-dir <directory>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: arguments[outputIndex + 1], isDirectory: true)

do {
    try AppIconGenerator(outputDirectory: outputDirectory).run()
    print("Generated icon assets in \(outputDirectory.path)")
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
