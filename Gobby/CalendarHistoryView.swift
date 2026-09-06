import SwiftUI

struct CalendarHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var selectedDate = Date.now
    let query: String

    private let calendar = Calendar.current

    private var selectedItems: [ClipboardItem] {
        appState.store.items.filter { item in
            calendar.isDate(item.createdAt, inSameDayAs: selectedDate) &&
            item.matchesSearch(query)
        }
    }

    private var monthItems: [ClipboardItem] {
        appState.store.items.filter {
            calendar.isDate($0.createdAt, equalTo: month, toGranularity: .month) &&
            (query.isEmpty || $0.matchesSearch(query))
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            calendarHeader
            calendarGrid
            Divider()
            HStack {
                Text(selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.headline)
                Spacer()
                Text("\(selectedItems.count) öğe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if selectedItems.isEmpty {
                ContentUnavailableView("Bu gün için öğe yok", systemImage: "calendar.badge.clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(selectedItems) { item in ClipboardRow(item: item) }
                    }
                }
                .closesOpenSwipeActionsOnVerticalScroll()
            }
        }
    }

    private var calendarHeader: some View {
        HStack {
            Button { shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Spacer()
            Text(month, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button { shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
        }
    }

    private var calendarGrid: some View {
        let symbols = reorderedWeekdaySymbols
        let dates = calendarDates
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 5) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 34)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let hasItems = monthItems.contains { calendar.isDate($0.createdAt, inSameDayAs: date) }
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.callout.weight(isSelected ? .bold : .regular))
                Circle()
                    .fill(hasItems ? Color.accentColor : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(isSelected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var calendarDates: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else { return [] }
        let leading = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: firstDay)
        }
    }

    private var reorderedWeekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let index = calendar.firstWeekday - 1
        return Array(symbols[index...]) + Array(symbols[..<index])
    }

    private func shiftMonth(by delta: Int) {
        month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
    }
}
