import SwiftUI
import EventKit
import AppKit

/// Vista horària per a 1 dia o una quinzena (14 columnes).
struct TimeGridView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var state: AppState
    @AppStorage("dayStartHour") private var startHour = 7
    let days: [Date]

    private let hourH: CGFloat = 48
    private let labelW: CGFloat = 54

    var body: some View {
        let byDay = store.eventsByDay(from: days[0], days: days.count)
        VStack(spacing: 0) {
            header
            allDayRow(byDay)
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        hourLabels
                        GeometryReader { geo in
                            grid(byDay, width: geo.size.width)
                        }
                        .frame(height: hourH * 24)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
                .onAppear { proxy.scrollTo(startHour, anchor: .top) }
            }
        }
    }

    // MARK: Capçalera

    private func sepLine(_ i: Int) -> some View {
        let sep = days.count == 14 && i == 7
        return Rectangle()
            .fill(Color.primary.opacity(sep ? 0.45 : 0.12))
            .frame(width: sep ? 1.5 : 0.5)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: labelW, height: 1)
            ForEach(days.indices, id: \.self) { i in
                let d = days[i]
                let isToday = Q.day(state.now) == d
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(days.count == 1 ? Q.longLabel(d) : Q.shortLabel(d))
                        .font(.system(size: 12))
                        .foregroundStyle(isToday ? Color.red : Color.secondary)
                    Text("\(Q.comps(d).d)")
                        .font(.system(size: 20, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.white : Color.primary)
                        .padding(.horizontal, isToday ? 6 : 0)
                        .background(Capsule().fill(isToday ? Color.red : Color.clear))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .overlay(alignment: .leading) { sepLine(i) }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { state.go(d, mode: .day) }
                .help("Doble clic: obre el dia")
            }
        }
    }

    private func allDayRow(_ byDay: [[EKEvent]]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("tot el dia")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: labelW - 6, alignment: .trailing)
                .padding(.trailing, 6)
                .padding(.top, 5)
            ForEach(days.indices, id: \.self) { i in
                let d = days[i]
                VStack(spacing: 2) {
                    ForEach(byDay[i].filter { $0.isLong }, id: \.qid) { ev in
                        EventChip(ev: ev, primary: i == max(0, Q.daysBetween(days[0], ev.startDate)))
                    }
                }
                .padding(2)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .top)
                .background(
                    Color.primary.opacity(0.001)
                        .onTapGesture(count: 2) { state.newEvent(at: d, allDay: true) }
                )
                .overlay(alignment: .leading) { sepLine(i) }
                .dropDestination(for: String.self) { items, _ in
                    guard let id = items.first else { return false }
                    return store.move(qid: id, toDay: d)
                }
            }
        }
    }

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Text(h == 0 ? "" : String(format: "%02d:00", h))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: labelW - 8, height: hourH, alignment: .topTrailing)
                    .offset(y: -6)
                    .id(h)
            }
        }
        .frame(width: labelW, alignment: .leading)
    }

    // MARK: Graella

    private func grid(_ byDay: [[EKEvent]], width: CGFloat) -> some View {
        let colW = width / CGFloat(days.count)
        return ZStack(alignment: .topLeading) {
            GridBackground(days: days, hourH: hourH)
                .frame(width: width, height: hourH * 24)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { loc in createAt(loc, colW: colW) }
                .onTapGesture { state.select(nil) }

            ForEach(days.indices, id: \.self) { i in
                ForEach(layoutDay(byDay[i].filter { !$0.isLong }, day: days[i])) { p in
                    TimedEventView(
                        p: p, colW: colW, hourH: hourH, x: CGFloat(i) * colW,
                        primary: i == max(0, Q.daysBetween(days[0], p.ev.startDate))
                    )
                }
            }

            if let ti = days.firstIndex(where: { $0 == Q.day(state.now) }) {
                let y = CGFloat(state.now.timeIntervalSince(Q.day(state.now)) / 3600) * hourH
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.red).frame(width: colW, height: 1.5)
                    Circle().fill(Color.red).frame(width: 9, height: 9).offset(x: -4.5)
                }
                .frame(width: colW, height: 9, alignment: .leading)
                .position(x: CGFloat(ti) * colW + colW / 2, y: y)
                .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: hourH * 24, alignment: .topLeading)
    }

    private func createAt(_ loc: CGPoint, colW: CGFloat) {
        let i = min(days.count - 1, max(0, Int(loc.x / colW)))
        let mins = Int((loc.y / hourH * 2).rounded(.down)) * 30
        let start = Q.cal.date(byAdding: .minute, value: max(0, min(mins, 23 * 60)), to: days[i]) ?? days[i]
        state.newEvent(at: start)
    }
}

struct GridBackground: View {
    let days: [Date]
    let hourH: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let n = days.count
            let w = size.width / CGFloat(n)
            if n > 1 {
                for (i, d) in days.enumerated() where Q.isWeekend(d) {
                    ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: 0, width: w, height: size.height)),
                             with: .color(Color.primary.opacity(0.035)))
                }
            }
            for h in 0...24 {
                var p = Path()
                let y = CGFloat(h) * hourH
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(Color.primary.opacity(0.12)), lineWidth: 0.5)
            }
            for i in 0...n {
                var p = Path()
                let x = CGFloat(i) * w
                p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                let sep = n == 14 && i == 7
                ctx.stroke(p, with: .color(Color.primary.opacity(sep ? 0.45 : 0.12)), lineWidth: sep ? 1.5 : 0.5)
            }
        }
    }
}

/// Bloc d'esdeveniment amb hora: clic selecciona, doble clic edita, arrossega per moure, vora inferior per canviar la durada.
struct TimedEventView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var state: AppState
    let p: Placed
    let colW: CGFloat
    let hourH: CGFloat
    let x: CGFloat
    let primary: Bool

    @State private var drag: CGSize = .zero
    @State private var resize: CGFloat = 0

    var body: some View {
        let ev = p.ev
        let laneW = colW / CGFloat(p.lanes)
        let w = max(laneW - 3, 10)
        let y = CGFloat(p.start) / 60 * hourH
        let h = max(CGFloat(p.end - p.start) / 60 * hourH - 2 + resize, 14)
        let selected = state.selectedUID == ev.qid
        let px: CGFloat = x + CGFloat(p.lane) * laneW + 1 + w / 2 + drag.width
        let py: CGFloat = y + h / 2 + drag.height

        EventBox(ev: ev, selected: selected, showTime: h > 30)
            .frame(width: w, height: h)
            .overlay(alignment: .bottom) {
                if ev.editable {
                    Color.primary.opacity(0.001)
                        .frame(height: 6)
                        .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                        .gesture(resizeGesture(ev))
                }
            }
            .modifier(EditorPopover(ev: ev, enabled: primary))
            .onTapGesture(count: 2) { state.open(ev) }
            .onTapGesture { state.select(ev) }
            .gesture(moveGesture(ev), including: ev.editable ? .all : .subviews)
            .contextMenu { EventMenu(ev: ev) }
            .position(x: px, y: py)
            .zIndex(drag == .zero ? 0 : 10)
    }

    private func snap(_ dy: CGFloat) -> Double {
        (Double(dy) / Double(hourH) * 60 / 15).rounded() * 15
    }

    private func moveGesture(_ ev: EKEvent) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                drag = v.translation
                if state.selectedUID != ev.qid { state.select(ev) }
            }
            .onEnded { v in
                let mins = snap(v.translation.height)
                let dd = Int((v.translation.width / colW).rounded())
                drag = .zero
                if mins != 0 || dd != 0 {
                    store.move(ev, to: Q.add(dd, to: ev.startDate).addingTimeInterval(mins * 60))
                }
            }
    }

    private func resizeGesture(_ ev: EKEvent) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in resize = v.translation.height }
            .onEnded { v in
                let mins = snap(v.translation.height)
                resize = 0
                if mins != 0 { store.setEnd(ev, ev.endDate.addingTimeInterval(mins * 60)) }
            }
    }
}

struct EventBox: View {
    let ev: EKEvent
    let selected: Bool
    var showTime = true

    var body: some View {
        let c = ev.qColor
        HStack(spacing: 0) {
            Rectangle().fill(c).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(ev.title ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(3)
                if showTime {
                    Text("\(Q.time(ev.startDate))–\(Q.time(ev.endDate))")
                        .font(.system(size: 10))
                        .opacity(0.8)
                }
                if let loc = ev.location, !loc.isEmpty, showTime {
                    Text(loc).font(.system(size: 10)).opacity(0.75).lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? c : c.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }
}

/// Xip compacte (fila de tot el dia i vista de mes). Es pot arrossegar a un altre dia.
struct EventChip: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var state: AppState
    let ev: EKEvent
    let primary: Bool
    var showTime = false

    var body: some View {
        let sel = state.selectedUID == ev.qid
        let filled = sel || ev.isLong
        HStack(spacing: 4) {
            if !ev.isLong {
                Circle().fill(sel ? Color.white : ev.qColor).frame(width: 7, height: 7)
            }
            if showTime && !ev.isLong {
                Text(Q.time(ev.startDate)).opacity(0.7)
            }
            Text(ev.title ?? "").lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .foregroundStyle(filled ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(filled ? ev.qColor.opacity(sel || !ev.isLong ? 1 : 0.85) : Color.clear)
        )
        .contentShape(Rectangle())
        .modifier(EditorPopover(ev: ev, enabled: primary))
        .onTapGesture(count: 2) { state.open(ev) }
        .onTapGesture { state.select(ev) }
        .draggable(ev.qid)
        .contextMenu { EventMenu(ev: ev) }
    }
}

struct EventMenu: View {
    @EnvironmentObject var state: AppState
    let ev: EKEvent

    var body: some View {
        Button("Obre") { state.open(ev) }
        Button("Ves a la quinzena") { state.go(ev.startDate, mode: .fortnight); state.select(ev) }
        if ev.editable {
            Divider()
            Button("Elimina", role: .destructive) { state.requestDelete(ev) }
        }
    }
}

struct EditorPopover: ViewModifier {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var state: AppState
    let ev: EKEvent
    let enabled: Bool

    func body(content: Content) -> some View {
        content.popover(
            isPresented: Binding(
                get: { enabled && state.editingUID == ev.qid },
                set: { if !$0 && state.editingUID == ev.qid { state.editingUID = nil } }
            ),
            arrowEdge: .trailing
        ) {
            EventEditor(event: ev)
                .environmentObject(store)
                .environmentObject(state)
        }
    }
}
