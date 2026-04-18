#!/usr/bin/env swift
// 生成 BrewMate 的 .iconset 目录和 .icns 文件
// 运行：swift tools/make_icon.swift   (工作目录需为项目根)

import AppKit
import Foundation

// MARK: - 绘图

/// 画一个"啤酒杯 + 琥珀渐变"风格的 App 图标
func renderIcon(size: CGFloat) -> NSImage {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let image = NSImage(size: rect.size)
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // ── 1. 圆角裁剪（macOS Big Sur+ 的"标准"比例 ≈ 0.2237）
    let corner = size * 0.2237
    let bgPath = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // ── 2. 背景：温暖琥珀纵向渐变
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let bgColors: [CGFloat] = [
        1.00, 0.78, 0.32, 1.0,   // 顶部：浅金
        0.92, 0.40, 0.08, 1.0    // 底部：深橙
    ]
    let grad = CGGradient(colorSpace: cs, colorComponents: bgColors, locations: [0, 1], count: 2)!
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: size/2, y: size),
        end: CGPoint(x: size/2, y: 0),
        options: []
    )

    // ── 3. 高光（顶部白色光斑，模拟玻璃质感）
    ctx.saveGState()
    let glossColors: [CGFloat] = [
        1, 1, 1, 0.22,
        1, 1, 1, 0.0
    ]
    let gloss = CGGradient(colorSpace: cs, colorComponents: glossColors, locations: [0, 1], count: 2)!
    ctx.drawLinearGradient(
        gloss,
        start: CGPoint(x: size/2, y: size),
        end: CGPoint(x: size/2, y: size * 0.55),
        options: []
    )
    ctx.restoreGState()

    // ── 4. 啤酒杯
    drawBeerMug(ctx: ctx, canvas: size)

    return image
}

/// 绘制啤酒杯（白色杯身、琥珀啤酒、白色泡沫、环形把手）
private func drawBeerMug(ctx: CGContext, canvas s: CGFloat) {
    // 整体略微左移，给右侧把手腾出空间
    let mugW = s * 0.46
    let mugH = s * 0.58
    let mugX = (s - mugW) / 2 - s * 0.055
    let mugY = (s - mugH) / 2 - s * 0.02
    let bodyCorner = s * 0.045

    // —— 把手（外圆 - 内孔，使用 even-odd 填充画出"环"）
    let handleW = s * 0.17
    let handleH = mugH * 0.56
    let handleX = mugX + mugW - s * 0.012
    let handleY = mugY + mugH * 0.18
    let handleOuter = CGPath(
        roundedRect: CGRect(x: handleX, y: handleY, width: handleW, height: handleH),
        cornerWidth: handleW / 2, cornerHeight: handleW / 2, transform: nil
    )
    let holeInset: CGFloat = s * 0.035
    let hole = CGPath(
        roundedRect: CGRect(
            x: handleX + holeInset,
            y: handleY + holeInset,
            width: handleW - holeInset * 2,
            height: handleH - holeInset * 2
        ),
        cornerWidth: (handleW - holeInset * 2) / 2,
        cornerHeight: (handleW - holeInset * 2) / 2,
        transform: nil
    )
    ctx.saveGState()
    ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    ctx.beginPath()
    ctx.addPath(handleOuter)
    ctx.addPath(hole)
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    // —— 杯身（纯白）
    let body = CGPath(
        roundedRect: CGRect(x: mugX, y: mugY, width: mugW, height: mugH),
        cornerWidth: bodyCorner, cornerHeight: bodyCorner, transform: nil
    )
    ctx.addPath(body)
    ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    ctx.fillPath()

    // —— 啤酒液体（琥珀渐变）
    let inset = s * 0.028
    let beerH = mugH * 0.70
    let beerRect = CGRect(
        x: mugX + inset,
        y: mugY + inset,
        width: mugW - inset * 2,
        height: beerH
    )
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let beerColors: [CGFloat] = [
        0.99, 0.83, 0.28, 1.0,   // 上亮
        0.94, 0.54, 0.10, 1.0    // 下深
    ]
    let beerGrad = CGGradient(colorSpace: cs, colorComponents: beerColors, locations: [0, 1], count: 2)!
    ctx.saveGState()
    let beerPath = CGPath(
        roundedRect: beerRect,
        cornerWidth: bodyCorner * 0.65, cornerHeight: bodyCorner * 0.65, transform: nil
    )
    ctx.addPath(beerPath)
    ctx.clip()
    ctx.drawLinearGradient(
        beerGrad,
        start: CGPoint(x: beerRect.midX, y: beerRect.maxY),
        end: CGPoint(x: beerRect.midX, y: beerRect.minY),
        options: []
    )
    ctx.restoreGState()

    // —— 气泡（亮琥珀内几个小圆点）
    ctx.setFillColor(red: 1, green: 0.97, blue: 0.62, alpha: 0.85)
    let bubbles: [(CGFloat, CGFloat, CGFloat)] = [
        (0.30, 0.25, 0.030),
        (0.58, 0.38, 0.022),
        (0.42, 0.50, 0.018),
        (0.70, 0.60, 0.026)
    ]
    for (fx, fy, fr) in bubbles {
        let cx = beerRect.minX + beerRect.width * fx
        let cy = beerRect.minY + beerRect.height * fy
        let r = s * fr
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    // —— 泡沫（白色 cloud 形状：一条底边 + 三个凸起圆）
    let foamY = mugY + beerH + inset
    let foamBaseH = s * 0.04
    let foamBase = CGRect(x: mugX + inset, y: foamY, width: mugW - inset * 2, height: foamBaseH)
    ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    ctx.fill(foamBase)

    let bumpR = s * 0.06
    let bumpY = foamY + foamBaseH - s * 0.005
    let bumpCenters: [CGFloat] = [0.22, 0.52, 0.80]
    for fx in bumpCenters {
        let cx = mugX + mugW * fx
        ctx.fillEllipse(in: CGRect(x: cx - bumpR, y: bumpY, width: bumpR * 2, height: bumpR * 1.5))
    }
}

// MARK: - 导出 PNG

@discardableResult
func writePNG(_ image: NSImage, toPath path: String, pixels: Int) -> Bool {
    // 强制以指定像素尺寸位图化（避免 lockFocus 基于 backing scale 的缩放差异）
    guard let tiff = image.tiffRepresentation,
          let src = NSBitmapImageRep(data: tiff) else { return false }
    // src 已是 pixel-size 正确的位图（因为我们以像素大小 lockFocus）
    _ = src
    let out = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = out.representation(using: .png, properties: [:]) else { return false }
    do {
        try data.write(to: URL(fileURLWithPath: path))
        return true
    } catch {
        print("write failed: \(path) — \(error)")
        return false
    }
}

// MARK: - 主流程

let fm = FileManager.default
let iconsetDir = "assets/BrewMate.iconset"
try? fm.removeItem(atPath: iconsetDir)
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

struct Variant { let name: String; let px: Int }
let variants: [Variant] = [
    Variant(name: "icon_16x16.png",       px: 16),
    Variant(name: "icon_16x16@2x.png",    px: 32),
    Variant(name: "icon_32x32.png",       px: 32),
    Variant(name: "icon_32x32@2x.png",    px: 64),
    Variant(name: "icon_128x128.png",     px: 128),
    Variant(name: "icon_128x128@2x.png",  px: 256),
    Variant(name: "icon_256x256.png",     px: 256),
    Variant(name: "icon_256x256@2x.png",  px: 512),
    Variant(name: "icon_512x512.png",     px: 512),
    Variant(name: "icon_512x512@2x.png",  px: 1024)
]

// 为每个像素尺寸单独渲染，保证细节清晰
var masterCache: [Int: NSImage] = [:]
for v in variants {
    let img: NSImage
    if let cached = masterCache[v.px] {
        img = cached
    } else {
        img = renderIcon(size: CGFloat(v.px))
        masterCache[v.px] = img
    }
    let path = "\(iconsetDir)/\(v.name)"
    if writePNG(img, toPath: path, pixels: v.px) {
        print("✓ \(path)  (\(v.px)x\(v.px))")
    } else {
        print("✗ \(path)")
        exit(1)
    }
}

print("\nRun: iconutil -c icns \(iconsetDir) -o assets/BrewMate.icns")
