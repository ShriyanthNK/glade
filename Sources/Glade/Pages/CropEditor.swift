import SwiftUI
import GladeCore

/// The photo with a 16:9 crop box on it. Drag inside to move the box, drag a corner to resize it, pinch to zoom.
/// Everything outside the box is dimmed, so what is left is what the backdrop will show.
struct CropEditor: View {
    let image: CGImage
    @Binding var crop: CropRegion
    var boxWidth: CGFloat = 480
    var boxHeight: CGFloat = 300

    @State private var panStart: CropRegion?
    @State private var pinchStart: CropRegion?

    private var iw: Double { Double(image.width) }
    private var ih: Double { Double(image.height) }
    private var scale: CGFloat { min(boxWidth / CGFloat(iw), boxHeight / CGFloat(ih)) }
    private var shown: CGSize { CGSize(width: CGFloat(iw) * scale, height: CGFloat(ih) * scale) }
    private var origin: CGPoint { CGPoint(x: (boxWidth - shown.width) / 2, y: (boxHeight - shown.height) / 2) }

    private func display(_ r: CGRect) -> CGRect {
        CGRect(x: origin.x + r.minX * scale, y: origin.y + r.minY * scale, width: r.width * scale, height: r.height * scale)
    }

    var body: some View {
        let box = display(crop.exactRect(imageWidth: iw, imageHeight: ih))
        ZStack(alignment: .topLeading) {
            Theme.ink
            Image(decorative: image, scale: 1).resizable().interpolation(.medium)
                .frame(width: shown.width, height: shown.height).offset(x: origin.x, y: origin.y)
            // dim everything outside the box
            Path { p in
                p.addRect(CGRect(origin: origin, size: shown))
                p.addRect(box)
            }
            .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
            // the box: a hairline, thirds, and square corner handles
            Rectangle().stroke(Theme.sparkle, lineWidth: 2).frame(width: box.width, height: box.height).offset(x: box.minX, y: box.minY)
            Path { p in
                for i in 1...2 {
                    let f = CGFloat(i) / 3
                    p.move(to: CGPoint(x: box.minX + box.width * f, y: box.minY)); p.addLine(to: CGPoint(x: box.minX + box.width * f, y: box.maxY))
                    p.move(to: CGPoint(x: box.minX, y: box.minY + box.height * f)); p.addLine(to: CGPoint(x: box.maxX, y: box.minY + box.height * f))
                }
            }
            .stroke(Color.white.opacity(0.28), lineWidth: 1)
            ForEach(CropRegion.Corner.allCases, id: \.self) { corner in handle(corner, box: box) }
        }
        .frame(width: boxWidth, height: boxHeight)
        .coordinateSpace(name: "crop")
        .clipped()
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { v in
                let start = panStart ?? crop
                panStart = start
                crop = start.panned(dx: Double(v.translation.width / scale), dy: Double(v.translation.height / scale), imageWidth: iw, imageHeight: ih)
            }
            .onEnded { _ in panStart = nil })
        .gesture(MagnificationGesture()
            .onChanged { m in
                let start = pinchStart ?? crop
                pinchStart = start
                var z = start; z.zoom = start.zoom * Double(m)
                crop = z.clamped(imageWidth: iw, imageHeight: ih)
            }
            .onEnded { _ in pinchStart = nil })
        .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crop area, zoom \(String(format: "%.1f", crop.zoom)) times")
        .accessibilityHint("Adjust to zoom in or out")
        .accessibilityAdjustableAction { dir in
            var z = crop
            z.zoom += dir == .increment ? 0.25 : -0.25
            crop = z.clamped(imageWidth: iw, imageHeight: ih)
        }
    }

    private func handle(_ corner: CropRegion.Corner, box: CGRect) -> some View {
        let x = (corner == .topLeft || corner == .bottomLeft) ? box.minX : box.maxX
        let y = (corner == .topLeft || corner == .topRight) ? box.minY : box.maxY
        return Rectangle().fill(Theme.paper)
            .frame(width: 12, height: 12)
            .overlay(Rectangle().stroke(Theme.outline, lineWidth: 2))
            .frame(width: 28, height: 28)             // a bigger area to grab
            .contentShape(Rectangle())
            .position(x: x, y: y)
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("crop"))
                .onChanged { v in
                    let p = CGPoint(x: (v.location.x - origin.x) / scale, y: (v.location.y - origin.y) / scale)
                    crop = crop.resizing(corner, to: p, imageWidth: iw, imageHeight: ih)
                })
            .accessibilityHidden(true)
    }
}
