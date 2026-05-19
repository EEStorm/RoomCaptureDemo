//
//  PathPlot2D.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/5/19.
//

import SwiftUI

struct PathPlot2D: View {
    let points: [SIMD2<Double>]
    let minPt: SIMD2<Double>
    let maxPt: SIMD2<Double>

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else { return }
            let pad: Double = 16
            let w = Double(size.width)
            let h = Double(size.height)
            let sx = (w - pad * 2) / Swift.max(1e-9, (maxPt.x - minPt.x))
            let sy = (h - pad * 2) / Swift.max(1e-9, (maxPt.y - minPt.y))
            let s = min(sx, sy)

            func map(_ p: SIMD2<Double>) -> CGPoint {
                let x = (p.x - minPt.x) * s + pad
                // Z axis downwards for screen.
                let y = (maxPt.y - p.y) * s + pad
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            path.move(to: map(points[0]))
            for p in points.dropFirst() {
                path.addLine(to: map(p))
            }

            ctx.stroke(path, with: .color(.green.opacity(0.9)), lineWidth: 2)

            // Start/end markers
            let start = map(points.first!)
            let end = map(points.last!)
            ctx.fill(Path(ellipseIn: CGRect(x: start.x - 4, y: start.y - 4, width: 8, height: 8)), with: .color(.blue))
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)), with: .color(.red))
        }
        .padding(10)
    }
}
