import SwiftUI

struct SparklineView: View {
    let values: [Double]
    var height: CGFloat = 34

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard values.count > 1 else { return }

                let width = proxy.size.width
                let height = proxy.size.height
                let step = width / CGFloat(values.count - 1)

                for index in values.indices {
                    let x = CGFloat(index) * step
                    let y = height - (CGFloat(values[index].clampedPercent) / 100 * height)
                    let point = CGPoint(x: x, y: y)

                    if index == values.startIndex {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .stroke(.tertiary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
