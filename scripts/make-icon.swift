// Build AppIcon.icns from a square source image on a flat dark background.
//
//   swift scripts/make-icon.swift Resources/icon-source.png Resources/AppIcon.icns
//
// Steps: find the artwork's bounding box (pixels brighter than the
// background), fit it into the 824x824 area a macOS icon occupies on a
// 1024x1024 canvas, clip to Apple's rounded-rectangle icon shape so the
// background corners become transparent, then write every iconset size and
// run iconutil. Only Apple frameworks are used, so it runs with the Command
// Line Tools alone.
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <source.png> <AppIcon.icns>\n".utf8))
    exit(2)
}
let sourceURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])

guard let source = NSImage(contentsOf: sourceURL),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { FileHandle.standardError.write(Data("cannot read \(sourceURL.path)\n".utf8)); exit(1) }

// --- 1. bounding box of the artwork ------------------------------------
let width = cg.width, height = cg.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

let threshold: UInt8 = 28
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        if max(pixels[i], pixels[i + 1], pixels[i + 2]) > threshold {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
}
guard maxX >= minX else { FileHandle.standardError.write(Data("no artwork found\n".utf8)); exit(1) }
// Bitmap memory row 0 is the top of the image, and CGImage.cropping takes a
// top-left rect, so the buffer coordinates can be used directly.
let art = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
guard let cropped = cg.cropping(to: art) else { exit(1) }
print("artwork bounds (top-left origin): \(Int(art.minX)),\(Int(art.minY)) – \(Int(art.maxX)),\(Int(art.maxY))  \(Int(art.width))×\(Int(art.height))")

// --- 2. render one canvas size ------------------------------------------
func render(_ canvas: Int) -> CGImage {
    let c = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    let scale = Double(canvas) / 1024.0
    // Apple's macOS icon grid: the icon body is 824pt on a 1024pt canvas,
    // corner radius ≈ 22.37% of the body (a squircle approximation).
    let body = 824.0 * scale
    let inset = (Double(canvas) - body) / 2
    let rect = CGRect(x: inset, y: inset, width: body, height: body)
    let path = CGPath(roundedRect: rect, cornerWidth: body * 0.2237, cornerHeight: body * 0.2237, transform: nil)
    c.addPath(path)
    c.clip()
    // "Cover" fit: scale the artwork so it fills the body on both axes and
    // centre it, cropping the few pixels that overhang. A non-square frame
    // therefore never leaves a sliver of background inside the icon shape.
    let scaleToFill = max(body / Double(cropped.width), body / Double(cropped.height))
    let drawW = Double(cropped.width) * scaleToFill, drawH = Double(cropped.height) * scaleToFill
    let drawRect = CGRect(x: rect.midX - drawW / 2, y: rect.midY - drawH / 2, width: drawW, height: drawH)
    c.draw(cropped, in: drawRect)
    return c.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try! data.write(to: url)
}

// --- 3. iconset + iconutil -----------------------------------------------
let iconset = outputURL.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for s in sizes { writePNG(render(s.px), to: iconset.appendingPathComponent("\(s.name).png")) }
writePNG(render(1024), to: outputURL.deletingLastPathComponent().appendingPathComponent("AppIcon-1024.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", outputURL.path]
try! task.run(); task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard task.terminationStatus == 0 else { exit(task.terminationStatus) }
print("wrote \(outputURL.path)")
