import SwiftUI

/// 显示器布局可视化视图
struct DisplayLayoutView: View {
    let displays: [DisplayInfo]
    let sharedEdges: [SharedEdge]
    let totalBounds: CGRect
    var onDisplayRename: ((DisplayInfo) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            let scale = PortalDrawingGeometry.calculateScale(for: geometry.size, totalBounds: totalBounds)
            let offset = PortalDrawingGeometry.calculateOffset(for: geometry.size, scale: scale, totalBounds: totalBounds)

            ZStack {
                // 绘制显示器矩形
                ForEach(displays) { display in
                    DisplayRectView(
                        display: display,
                        onRename: onDisplayRename.map { rename in
                            { rename(display) }
                        }
                    )
                        .frame(
                            width: display.frame.width * scale,
                            height: display.frame.height * scale
                        )
                        .position(
                            x: (display.frame.midX - totalBounds.minX) * scale + offset.x,
                            y: (display.frame.midY - totalBounds.minY) * scale + offset.y
                        )
                }

                // 绘制共享边界
                ForEach(sharedEdges) { edge in
                    Path { path in
                        let startX = (edge.start.x - totalBounds.minX) * scale + offset.x
                        let startY = (edge.start.y - totalBounds.minY) * scale + offset.y
                        let endX = (edge.end.x - totalBounds.minX) * scale + offset.x
                        let endY = (edge.end.y - totalBounds.minY) * scale + offset.y

                        path.move(to: CGPoint(x: startX, y: startY))
                        path.addLine(to: CGPoint(x: endX, y: endY))
                    }
                    .stroke(Color.green, lineWidth: 4)
                    .shadow(color: .green.opacity(0.5), radius: 4)
                }
            }
        }
    }

}

/// 单个显示器矩形视图
struct DisplayRectView: View {
    let display: DisplayInfo
    var onRename: (() -> Void)? = nil
    @State private var isRenameButtonHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(display.isMain ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))

            RoundedRectangle(cornerRadius: 8)
                .stroke(display.isMain ? Color.blue : Color.gray, lineWidth: 2)

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(display.name)
                        .font(.headline)
                        .foregroundColor(display.isMain ? .blue : .primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if let onRename {
                        Button(action: onRename) {
                            Image(systemName: "pencil")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(isRenameButtonHovered ? .primary : .secondary)
                                .frame(width: 18, height: 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isRenameButtonHovered ? Color.secondary.opacity(0.12) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: 4))
                        .onHover { isRenameButtonHovered = $0 }
                        .help(L("display.rename"))
                        .accessibilityLabel(L("display.rename"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Text("\(display.width) × \(display.height)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}
