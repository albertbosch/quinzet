import SwiftUI
import EventKit
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct QuinzetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = CalendarStore()
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Quinzet", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(state)
                .frame(minWidth: 1100, minHeight: 640)
                .onAppear { state.store = store }
        }
        .defaultSize(width: 1440, height: 900)
        .commands { AppCommands(state: state) }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(state)
        }
    }
}

struct AppCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nou esdeveniment") { state.newEvent() }
                .keyboardShortcut("n")
            Button("Nou calendari…") { state.showNewCalendar = true }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Nova subscripció a calendari…") { state.showSubscribe = true }
                .keyboardShortcut("s", modifiers: [.command, .option])
        }
        CommandGroup(before: .toolbar) {
            Button("Dia") { state.mode = .day }.keyboardShortcut("1")
            Button("Quinzena") { state.mode = .fortnight }.keyboardShortcut("2")
            Button("Mes") { state.mode = .month }.keyboardShortcut("3")
            Button("Any") { state.mode = .year }.keyboardShortcut("4")
            Divider()
            Button("Avui") { state.today() }.keyboardShortcut("t")
            Button("Anterior") { state.step(-1) }.keyboardShortcut(.leftArrow)
            Button("Següent") { state.step(1) }.keyboardShortcut(.rightArrow)
            Divider()
        }
    }
}

final class AppState: ObservableObject {
    weak var store: CalendarStore?

    @Published var mode: ViewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .fortnight {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "viewMode") }
    }
    @Published var cursor: Date = Q.day(Date())
    @Published var selectedUID: String?
    @Published var selectedEvent: EKEvent?
    @Published var editingUID: String?
    @Published var pendingDelete: EKEvent?
    @Published var search = ""
    @Published var showNewCalendar = false
    @Published var showSubscribe = false
    @Published var now = Date()

    var title: String {
        switch mode {
        case .day:
            let c = Q.comps(cursor)
            return "\(c.d) \(Q.deMonth(c.m)) de \(c.y)"
        case .fortnight:
            let s = Q.start(cursor), e = Q.add(13, to: s)
            let a = Q.comps(s), b = Q.comps(e)
            if a.m == b.m { return "\(a.d) – \(b.d) \(Q.deMonth(b.m)) de \(b.y)" }
            if a.y == b.y { return "\(a.d) \(Q.deMonth(a.m)) – \(b.d) \(Q.deMonth(b.m)) de \(b.y)" }
            return "\(a.d) \(Q.deMonth(a.m)) de \(a.y) – \(b.d) \(Q.deMonth(b.m)) de \(b.y)"
        case .month:
            let c = Q.comps(cursor)
            return "\(Q.monthsCap[c.m - 1]) de \(c.y)"
        case .year:
            return "\(Q.comps(cursor).y)"
        }
    }

    var subtitle: String {
        switch mode {
        case .day: return "\(Q.longLabel(cursor)) · \(Q.qString(cursor))"
        case .fortnight: return Q.qString(cursor)
        default: return ""
        }
    }

    var visibleRange: ClosedRange<Date> {
        switch mode {
        case .day: return cursor...cursor
        case .fortnight: let s = Q.start(cursor); return s...Q.add(13, to: s)
        case .month:
            let rows = Q.fortnightRows(forMonthOf: cursor)
            return rows.first!...Q.add(13, to: rows.last!)
        case .year:
            let y = Q.comps(cursor).y
            let a = Q.cal.date(from: DateComponents(year: y, month: 1, day: 1))!
            return a...Q.add(-1, to: Q.cal.date(from: DateComponents(year: y + 1, month: 1, day: 1))!)
        }
    }

    func step(_ dir: Int) {
        switch mode {
        case .day: cursor = Q.add(dir, to: cursor)
        case .fortnight: cursor = Q.add(14 * dir, to: cursor)
        case .month: cursor = Q.addMonths(dir, to: Q.monthStart(cursor))
        case .year: cursor = Q.cal.date(byAdding: .year, value: dir, to: cursor)!
        }
    }

    func today() { cursor = Q.day(Date()) }

    func go(_ d: Date, mode m: ViewMode) {
        cursor = Q.day(d)
        mode = m
    }

    func select(_ ev: EKEvent?) {
        selectedUID = ev?.qid
        selectedEvent = ev
    }

    func open(_ ev: EKEvent) {
        select(ev)
        editingUID = ev.qid
    }

    func requestDelete(_ ev: EKEvent) {
        guard ev.editable else { return }
        if ev.hasRecurrenceRules {
            pendingDelete = ev
        } else {
            store?.delete(ev)
            select(nil)
        }
    }

    /// Crea un esdeveniment (com Calendar: es desa de seguida i s'obre l'editor).
    func newEvent(at start: Date? = nil, allDay: Bool = false) {
        guard let store else { return }
        var s: Date
        if let start {
            s = start
        } else if Q.day(cursor) == Q.day(Date()) && !allDay {
            let c = Q.cal.dateComponents([.year, .month, .day, .hour], from: Date())
            s = Q.cal.date(from: c)!.addingTimeInterval(3600)
        } else {
            s = Q.atTime(cursor, hour: 9)
        }
        if allDay { s = Q.day(s) }
        let e = allDay ? s.addingTimeInterval(86_399) : s.addingTimeInterval(3600)
        if mode == .year { mode = .fortnight }
        if !visibleRange.contains(Q.day(s)) { cursor = Q.day(s) }
        guard let ev = store.newEvent(start: s, end: e, allDay: allDay) else { return }
        select(ev)
        let id = ev.qid
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.editingUID = id
        }
    }
}
