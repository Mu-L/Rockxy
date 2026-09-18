import SwiftUI

// Custom layouts for the Traffic Insights report rows.

// MARK: - TrafficInsightsCardGrid

/// Wraps report cards into equal-width columns that always fill the row.
///
/// The column count is recomputed from the proposed width on every layout pass, so widening
/// the window or hiding the sidebar re-flows the cards immediately. Cards in one row share the
/// row height, and a short last row stays column-aligned unless `fillsLastRow` is set.
struct TrafficInsightsCardGrid: Layout {
    // MARK: Internal

    /// Rows measured for one width. Measuring a card means laying out its chart or list, so
    /// the placement pass reuses what the sizing pass computed instead of measuring twice.
    struct Cache {
        var width: CGFloat?
        var rows: [Row] = []
    }

    struct Row {
        let indices: Range<Int>
        let itemWidth: CGFloat
        let height: CGFloat
    }

    var minimumColumnWidth: CGFloat
    var spacing: CGFloat = Theme.Insights.cardSpacing
    /// Widen the cards on a short last row so the row ends flush with the others. Used for the
    /// headline tiles, where a trailing gap reads as a missing tile rather than alignment.
    var fillsLastRow = false

    /// Number of columns for `itemCount` items in `availableWidth`.
    ///
    /// As many columns as the minimum width allows, then reduced while it keeps the same number
    /// of rows and leaves fewer empty cells, so four cards in a three-column space become 2 + 2
    /// instead of 3 + 1, while five tiles in a four-column space become 3 + 2.
    static func columnCount(
        itemCount: Int,
        availableWidth: CGFloat,
        minimumColumnWidth: CGFloat,
        spacing: CGFloat
    )
        -> Int
    {
        guard itemCount > 1 else {
            return 1
        }
        let unit = max(minimumColumnWidth, 1) + spacing
        let fit = Int(((max(availableWidth, 0) + spacing) / unit).rounded(.down))
        let upper = max(1, min(itemCount, fit))
        let targetRows = rowCount(itemCount: itemCount, columns: upper)
        var best = upper
        var fewestEmpty = targetRows * upper - itemCount
        var columns = upper - 1
        while columns >= 1 {
            let rows = rowCount(itemCount: itemCount, columns: columns)
            guard rows == targetRows else {
                break
            }
            let empty = rows * columns - itemCount
            if empty < fewestEmpty {
                best = columns
                fewestEmpty = empty
            }
            columns -= 1
        }
        return best
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard !subviews.isEmpty else {
            return .zero
        }
        let width = resolvedWidth(for: proposal, subviews: subviews)
        let rows = rows(for: width, subviews: subviews, cache: &cache)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard !subviews.isEmpty else {
            return
        }
        let rows = rows(for: bounds.width, subviews: subviews, cache: &cache)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: row.itemWidth, height: row.height)
                )
                x += row.itemWidth + spacing
            }
            y += row.height + spacing
        }
    }

    // MARK: Private

    private static func rowCount(itemCount: Int, columns: Int) -> Int {
        (itemCount + columns - 1) / columns
    }

    private func rows(for width: CGFloat, subviews: Subviews, cache: inout Cache) -> [Row] {
        if cache.width == width {
            return cache.rows
        }
        let rows = arrange(width: width, subviews: subviews)
        cache = Cache(width: width, rows: rows)
        return rows
    }

    /// With no proposed width (an ideal-size query) the grid reports one row of ideal widths.
    private func resolvedWidth(for proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width {
            return width
        }
        let ideal = subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width }
        return ideal + spacing * CGFloat(max(subviews.count - 1, 0))
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        let columns = Self.columnCount(
            itemCount: subviews.count,
            availableWidth: width,
            minimumColumnWidth: minimumColumnWidth,
            spacing: spacing
        )
        let columnWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        var rows: [Row] = []
        var start = 0
        while start < subviews.count {
            let end = min(start + columns, subviews.count)
            let count = end - start
            let isShortLastRow = count < columns
            let itemWidth = fillsLastRow && isShortLastRow
                ? max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
                : columnWidth
            let height = (start ..< end).reduce(CGFloat(0)) { tallest, index in
                max(tallest, subviews[index].sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height)
            }
            rows.append(Row(indices: start ..< end, itemWidth: itemWidth, height: height))
            start = end
        }
        return rows
    }
}

// MARK: - TrafficInsightsSplitRow

/// A flexible primary card beside a fixed-width secondary card, stacked when the row is too
/// narrow for both. Side by side, both cards take the taller card's height.
struct TrafficInsightsSplitRow: Layout {
    // MARK: Internal

    /// Heights measured for one width; the chart card is expensive to measure, so the
    /// placement pass reuses the sizing pass.
    struct Cache {
        var width: CGFloat?
        var primaryHeight: CGFloat = 0
        var secondaryHeight: CGFloat = 0
    }

    var secondaryWidth: CGFloat
    var minimumPrimaryWidth: CGFloat
    var spacing: CGFloat = Theme.Insights.cardSpacing

    static func fitsSideBySide(
        availableWidth: CGFloat,
        secondaryWidth: CGFloat,
        minimumPrimaryWidth: CGFloat,
        spacing: CGFloat
    )
        -> Bool
    {
        availableWidth >= minimumPrimaryWidth + secondaryWidth + spacing
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard subviews.count == 2 else {
            return .zero
        }
        let width = proposal.width ?? (minimumPrimaryWidth + secondaryWidth + spacing)
        measure(width: width, subviews: subviews, cache: &cache)
        if isSideBySide(width: width) {
            return CGSize(width: width, height: max(cache.primaryHeight, cache.secondaryHeight))
        }
        return CGSize(width: width, height: cache.primaryHeight + spacing + cache.secondaryHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard subviews.count == 2 else {
            return
        }
        let width = bounds.width
        measure(width: width, subviews: subviews, cache: &cache)
        if isSideBySide(width: width) {
            let primaryWidth = width - secondaryWidth - spacing
            let height = max(cache.primaryHeight, cache.secondaryHeight)
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: primaryWidth, height: height)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX + primaryWidth + spacing, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: secondaryWidth, height: height)
            )
            return
        }
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: width, height: cache.primaryHeight)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + cache.primaryHeight + spacing),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: width, height: cache.secondaryHeight)
        )
    }

    // MARK: Private

    private func measure(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        guard cache.width != width else {
            return
        }
        let primaryWidth = isSideBySide(width: width) ? width - secondaryWidth - spacing : width
        let secondaryMeasuredWidth = isSideBySide(width: width) ? secondaryWidth : width
        cache = Cache(
            width: width,
            primaryHeight: subviews[0].sizeThatFits(ProposedViewSize(width: primaryWidth, height: nil)).height,
            secondaryHeight: subviews[1].sizeThatFits(ProposedViewSize(width: secondaryMeasuredWidth, height: nil)).height
        )
    }

    private func isSideBySide(width: CGFloat) -> Bool {
        Self.fitsSideBySide(
            availableWidth: width,
            secondaryWidth: secondaryWidth,
            minimumPrimaryWidth: minimumPrimaryWidth,
            spacing: spacing
        )
    }
}
