import SwiftUI
import RuriCore

struct CommitGraphView: View {
    let row: ChorusCommitGraph.Row
    let columns: Int
    private let palette: [Color] = [.blue, .orange, .purple, .green, .pink, .cyan, .indigo]
    var body: some View {
        Canvas { context, size in
            let center = size.height / 2
            func x(_ column: Int) -> CGFloat { 12 + CGFloat(column) * 18 }
            for edge in row.edges {
                let startY = edge.startsAtNode ? center : 0
                var path = Path()
                path.move(to: CGPoint(x: x(edge.from), y: startY))
                path.addCurve(to: CGPoint(x: x(edge.to), y: size.height),
                              control1: CGPoint(x: x(edge.from), y: (startY + size.height) / 2),
                              control2: CGPoint(x: x(edge.to), y: (startY + size.height) / 2))
                context.stroke(path, with: .color(palette[edge.color % palette.count]), lineWidth: 2)
            }
            if row.incoming {
                var path = Path()
                path.move(to: CGPoint(x: x(row.column), y: 0))
                path.addLine(to: CGPoint(x: x(row.column), y: center))
                context.stroke(path, with: .color(palette[row.color % palette.count]), lineWidth: 2)
            }
            let circle = Path(ellipseIn: CGRect(x: x(row.column) - 4, y: center - 4, width: 8, height: 8))
            context.fill(circle, with: .color(palette[row.color % palette.count]))
        }.frame(width: CGFloat(max(1, columns)) * 18 + 6)
            .accessibilityHidden(true)
    }
}
