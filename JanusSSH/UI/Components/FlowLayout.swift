import SwiftUI

/// 把 subviews 从左到右排,装不下当前行宽度时自动换行。
/// 用法:
///   FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
///     ForEach(items) { item in PillView(item: item) }
///   }
///
/// 跟普通 HStack 的区别:父容器宽度有限时,会按"行"折行而不是溢出截断。
/// 跟 LazyVGrid 的区别:行高由该行最高的 subview 决定,不需要预设列数。
///
/// 实现基于 SwiftUI 4 (macOS 13+) 的 Layout 协议。
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let containerWidth = proposal.width ?? CGFloat.infinity
        let rows = arrange(in: containerWidth, subviews: subviews)
        let totalHeight = rows.reduce(0) { $0 + $1.maxHeight }
            + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        let width = containerWidth.isFinite
            ? containerWidth
            : (rows.map(\.width).max() ?? 0)
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = arrange(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.maxHeight + verticalSpacing
        }
    }

    // MARK: - Row bookkeeping

    private struct RowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0      // 不含行尾 spacing
        var maxHeight: CGFloat = 0
    }

    /// 把所有 subviews 按"行"分组。每行第一个 item 紧贴行首,后续 item 之前加
    /// horizontalSpacing;若加完超过 containerWidth 就换行。
    private func arrange(in containerWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            var current = rows[rows.count - 1]
            let leadingSpacing: CGFloat = current.items.isEmpty ? 0 : horizontalSpacing
            let needed = current.width + leadingSpacing + size.width

            if needed > containerWidth, !current.items.isEmpty, containerWidth.isFinite {
                var newRow = Row()
                newRow.items.append(RowItem(subview: subview, size: size))
                newRow.width = size.width
                newRow.maxHeight = size.height
                rows.append(newRow)
            } else {
                current.items.append(RowItem(subview: subview, size: size))
                current.width += leadingSpacing + size.width
                current.maxHeight = max(current.maxHeight, size.height)
                rows[rows.count - 1] = current
            }
        }
        return rows
    }
}
