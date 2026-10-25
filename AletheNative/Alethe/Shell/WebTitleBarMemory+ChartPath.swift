import AletheDesign
import AletheModel
import SwiftUI

struct MemoryChartPath: Shape {
    let points: [CGPoint]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        path.move(to: points[0])
        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            for index in 0..<(points.count - 1) {
                let p0 = points[index == 0 ? 0 : index - 1], p1 = points[index], p2 = points[index + 1]
                let p3 = points[index + 2 < points.count ? index + 2 : index + 1]
                path.addCurve(to: p2,
                              control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                              control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
            }
        }
        if closed {
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        }
        return path
    }
}
