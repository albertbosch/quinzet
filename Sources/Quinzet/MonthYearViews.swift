import SwiftUI
import EventKit

// MARK: - Mes: cada fila és una quinzena de 14 columnes

struct MonthView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var state: AppState

    var body: some View {
        let rows = Q.fortnightRows(forMonthOf: state.cursor)
        let first = rows[0]
        let byDay = store.eventsByDay(from: first, days: rows.count * 14)
        let month = Q.comps(state.cursor).m

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 30, height: 1)
                ForEach(0..<14, id: \.self) { i in
                    HStack(spacing: 2) {
                        Text(Q.shortDays[i % 7]).fontWeight(.semibold)
                        Text(i < 7 ? "1" : "2").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
                    .padding(.vertical, 6)
                }
            }
            Divider()
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    Text("Q\(Q.qNumber(rows[r]).q)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .rotationEffect(.degrees(-90))
                        .frame(width: 30)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { state.go(rows[r], mode: .fortnight) }
                        .help("Obre la quinzena")
                    ForEach(0..<14, id: \.self) { i in
                        MonthCell(
                            day: Q.add(i, to: rows[r]),
                            month: month,
                            firstVisible: first,
                            events: byDay[r * 14 + i],
                            sep: i == 7
                        )
                    }
                }
                .frame(maxHeight: .infinity)
                Divider()
            }
        }
    }
}

struct MonthCell: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var state: AppState
    let day: Date
    let month: Int
    let firstVisible: Date
    let events: [EKEvent]
    let sep: Bool
    @State private var targeted = false

    var body: some View {
        let c = Q.comps(day)
        let inMonth = c.m == month
        let isToday = Q.day(state.now) == day
        let bg: Color = targeted ? Color.accentColor.opacity(0.15)
            : (!inMonth ? Color.primary.opacity(0.03) : (Q.isWeekend(day) ? Color.primary.opacity(0.018) : Color.clear))

        GeometryReader { geo in
            let capacity = max(0, Int((geo.size.height - 26) / 18))
            let shown = events.count > capacity ? max(0, capacity - 1) : events.count
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if c.d == 1 {
                        Text(String(Q.monthName(day).prefix(3)) + ".")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("\(c.d)")
                        .font(.system(size: 13, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.6)))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(isToday ? Color.red : Color.clear))
                        .onTapGesture { state.go(day, mode: .day) }
                }
                ForEach(events.prefix(shown), id: \.qid) { ev in
                    EventChip(
                        ev: ev,
                        primary: Q.day(ev.startDate) == day || (ev.startDate < firstVisible && day == firstVisible),
                        showTime: true
                    )
                }
                if events.count > shown {
                    Text("+\(events.count - shown) més")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .onTapGesture { state.go(day, mode: .day) }
                }
                Spacer(minLength: 0)
            }
            .padding(3)
        }
        .background(bg)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(sep ? 0.45 : 0.12))
                .frame(width: sep ? 1.5 : 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { state.newEvent(at: day, allDay: true) }
        .onTapGesture { state.select(nil) }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            return store.move(qid: id, toDay: day)
        } isTargeted: { targeted = $0 }
    }
}

// MARK: - Any

struct YearView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var state: AppState

    var body: some View {
        let y = Q.comps(state.cursor).y
        let jan1 = Q.cal.date(from: DateComponents(year: y, month: 1, day: 1))!
        let gridStart = Q.start(jan1)
        let total = Q.daysBetween(gridStart, Q.cal.date(from: DateComponents(year: y + 1, month: 1, day: 15))!)
        let busy = store.busyDays(from: gridStart, days: total)

        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 28)], alignment: .leading, spacing: 26) {
                ForEach(1...12, id: \.self) { m in
                    MiniMonth(
                        month: Q.cal.date(from: DateComponents(year: y, month: m, day: 1))!,
                        busy: busy,
                        gridStart: gridStart
                    ) { d in state.go(d, mode: .fortnight) }
                }
            }
            .padding(22)
        }
    }
}

/// Mes petit en 14 columnes (vista d'any i barra lateral).
struct MiniMonth: View {
    @EnvironmentObject var state: AppState
    let month: Date
    var showTitle = true
    var busy: Set<Int> = []
    var gridStart: Date? = nil
    var highlight: ClosedRange<Date>? = nil
    var onPick: (Date) -> Void

    var body: some View {
        let rows = Q.fortnightRows(forMonthOf: month)
        let mc = Q.comps(month)
        let today = Q.day(state.now)
        let tc = Q.comps(today)

        VStack(alignment: .leading, spacing: 4) {
            if showTitle {
                Text(Q.monthsCap[mc.m - 1])
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tc.m == mc.m && tc.y == mc.y ? Color.red : Color.primary)
                    .onTapGesture { state.go(month, mode: .month) }
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 1) {
                GridRow {
                    Color.clear.frame(width: 22, height: 1)
                    ForEach(0..<14, id: \.self) { i in
                        Text(Q.shortDays[i % 7] + (i < 7 ? "¹" : "²"))
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .leading) {
                                if i == 7 { Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1) }
                            }
                    }
                }
                ForEach(rows, id: \.self) { s in
                    GridRow {
                        Text("Q\(Q.qNumber(s).q)")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22)
                        ForEach(0..<14, id: \.self) { i in
                            dayCell(Q.add(i, to: s), month: mc.m, today: today, sep: i == 7)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ d: Date, month: Int, today: Date, sep: Bool) -> some View {
        let inMonth = Q.comps(d).m == month
        let isToday = d == today
        let hi = highlight?.contains(d) ?? false
        let hasEv: Bool = {
            guard let g = gridStart else { return false }
            return busy.contains(Q.daysBetween(g, d))
        }()
        return Text("\(Q.comps(d).d)")
            .font(.system(size: 11, weight: isToday ? .bold : .regular))
            .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.5)))
            .frame(width: 20, height: 20)
            .background(Circle().fill(isToday ? Color.red : Color.clear))
            .overlay(alignment: .bottom) {
                if hasEv && !isToday {
                    Circle().fill(Color.secondary).frame(width: 3, height: 3).offset(y: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 1)
            .background(hi ? Color.accentColor.opacity(0.14) : Color.clear)
            .overlay(alignment: .leading) {
                if sep { Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1) }
            }
            .contentShape(Rectangle())
            .onTapGesture { onPick(d) }
    }
}

// MARK: - Cerca

struct SearchResults: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var state: AppState

    var body: some View {
        let results = store.search(state.search)
        List {
            if results.isEmpty {
                Text("Cap resultat").foregroundStyle(.secondary)
            }
            ForEach(results, id: \.qid) { ev in
                HStack(spacing: 10) {
                    Circle().fill(ev.qColor).frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ev.title ?? "").fontWeight(.semibold)
                        if let loc = ev.location, !loc.isEmpty {
                            Text(loc).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Q.dateString(ev.startDate) + (ev.isAllDay ? "" : " · " + Q.time(ev.startDate)))
                        Text("\(Q.longLabel(ev.startDate)) · \(Q.qString(ev.startDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture {
                    state.search = ""
                    state.go(ev.startDate, mode: .fortnight)
                    state.select(ev)
                }
            }
        }
    }
}
