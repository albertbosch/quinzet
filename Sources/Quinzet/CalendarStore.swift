import Foundation
import EventKit
import SwiftUI
import AppKit

struct CalGroup: Identifiable {
    let id: String
    let title: String
    let calendars: [EKCalendar]
}

/// Embolcall d'EKEventStore: els mateixos calendaris que l'app Calendar (iCloud, Google, Exchange, subscripcions…).
final class CalendarStore: ObservableObject {
    let ek = EKEventStore()
    @Published var authorized = false
    @Published var denied = false
    @Published var calendars: [EKCalendar] = []
    @Published var hidden: Set<String>
    @Published var revision = 0
    @Published var lastError: String?

    private var index: [String: EKEvent] = [:]
    private var pool: [EKEvent] = []
    private var poolRev = -1
    private var observer: NSObjectProtocol?

    init() {
        hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenCalendars") ?? [])
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: ek, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    // MARK: Accés

    func checkStatus() {
        let s = EKEventStore.authorizationStatus(for: .event)
        if s == .fullAccess {
            authorized = true; denied = false; reload()
        } else if s == .notDetermined {
            denied = false
        } else {
            denied = true
        }
    }

    func requestAccess() {
        ek.requestFullAccessToEvents { [weak self] ok, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorized = ok
                self.denied = !ok
                if ok { self.ek.reset(); self.reload() }
            }
        }
    }

    // MARK: Calendaris

    func reload() {
        guard authorized else { return }
        calendars = ek.calendars(for: .event).sorted { a, b in
            let ka: (String, String) = (a.source?.title ?? "", a.title)
            let kb: (String, String) = (b.source?.title ?? "", b.title)
            return ka < kb
        }
        bump()
    }

    func bump() { revision &+= 1 }

    var groups: [CalGroup] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var cals: [String: [EKCalendar]] = [:]
        for c in calendars {
            let sid = c.source?.sourceIdentifier ?? "-"
            if cals[sid] == nil { order.append(sid); titles[sid] = c.source?.title ?? L("Altres"); cals[sid] = [] }
            cals[sid]!.append(c)
        }
        return order.map { CalGroup(id: $0, title: titles[$0] ?? "", calendars: cals[$0] ?? []) }
    }

    var writableCalendars: [EKCalendar] { calendars.filter { $0.allowsContentModifications } }

    var writableSources: [EKSource] {
        ek.sources.filter { [.local, .calDAV, .exchange, .mobileMe].contains($0.sourceType) }
    }

    func calendar(_ id: String) -> EKCalendar? { calendars.first { $0.calendarIdentifier == id } }

    func isVisible(_ c: EKCalendar) -> Bool { !hidden.contains(c.calendarIdentifier) }

    func setVisible(_ c: EKCalendar, _ on: Bool) {
        if on { hidden.remove(c.calendarIdentifier) } else { hidden.insert(c.calendarIdentifier) }
        UserDefaults.standard.set(Array(hidden), forKey: "hiddenCalendars")
        bump()
    }

    var defaultCalendar: EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: "defaultCalendarID"), let c = calendar(id), c.allowsContentModifications {
            return c
        }
        if let d = ek.defaultCalendarForNewEvents, d.allowsContentModifications, isVisible(d) { return d }
        return writableCalendars.first(where: isVisible) ?? ek.defaultCalendarForNewEvents
    }

    func createCalendar(title: String, color: Color, sourceID: String?) {
        let c = EKCalendar(for: .event, eventStore: ek)
        c.title = title.isEmpty ? L("Sense títol") : title
        c.color = NSColor(color)
        c.source = writableSources.first { $0.sourceIdentifier == sourceID }
            ?? ek.defaultCalendarForNewEvents?.source
            ?? writableSources.first
        do { try ek.saveCalendar(c, commit: true); reload() } catch { lastError = error.localizedDescription }
    }

    func deleteCalendar(_ c: EKCalendar) {
        do { try ek.removeCalendar(c, commit: true); reload() } catch { lastError = error.localizedDescription }
    }

    /// Les subscripcions (webcal) les crea l'app Calendar; Quinzet les veu automàticament.
    func subscribe(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("https://") { s = "webcal://" + s.dropFirst(8) }
        else if s.hasPrefix("http://") { s = "webcal://" + s.dropFirst(7) }
        else if !s.hasPrefix("webcal://") { s = "webcal://" + s }
        if let url = URL(string: s) { NSWorkspace.shared.open(url) } else { lastError = L("L'adreça no és vàlida.") }
    }

    // MARK: Esdeveniments

    func events(from: Date, to: Date) -> [EKEvent] {
        _ = revision
        let cals = calendars.filter(isVisible)
        guard authorized, !cals.isEmpty, from < to else { return [] }
        let p = ek.predicateForEvents(withStart: from, end: to, calendars: cals)
        let evs = ek.events(matching: p).sorted {
            if $0.isLong != $1.isLong { return $0.isLong }
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return ($0.title ?? "") < ($1.title ?? "")
        }
        for e in evs { index[e.qid] = e }
        return evs
    }

    /// Esdeveniments agrupats per dia (un esdeveniment de diversos dies apareix a cada dia).
    func eventsByDay(from: Date, days: Int) -> [[EKEvent]] {
        let start = Q.day(from)
        var out = Array(repeating: [EKEvent](), count: days)
        for e in events(from: start, to: Q.add(days, to: start)) {
            let s = max(0, Q.daysBetween(start, e.startDate))
            var last = Q.daysBetween(start, e.endDate)
            if e.endDate > e.startDate && Q.day(e.endDate) == e.endDate { last -= 1 }
            last = min(days - 1, max(last, s))
            if s > days - 1 { continue }
            for i in s...last { out[i].append(e) }
        }
        return out
    }

    func busyDays(from: Date, days: Int) -> Set<Int> {
        var set = Set<Int>()
        for (i, list) in eventsByDay(from: from, days: days).enumerated() where !list.isEmpty { set.insert(i) }
        return set
    }

    func search(_ text: String) -> [EKEvent] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        if poolRev != revision {
            let now = Date()
            pool = events(from: Q.cal.date(byAdding: .year, value: -1, to: now)!, to: Q.cal.date(byAdding: .year, value: 2, to: now)!)
                .sorted { $0.startDate < $1.startDate }
            poolRev = revision
        }
        return pool.filter {
            ($0.title ?? "").lowercased().contains(q)
            || ($0.location ?? "").lowercased().contains(q)
            || ($0.notes ?? "").lowercased().contains(q)
        }
    }

    func event(qid: String) -> EKEvent? { index[qid] }

    @discardableResult
    func newEvent(start: Date, end: Date, allDay: Bool) -> EKEvent? {
        guard let cal = defaultCalendar else { lastError = L("No hi ha cap calendari on es pugui escriure."); return nil }
        let ev = EKEvent(eventStore: ek)
        ev.title = L("Nou esdeveniment")
        ev.isAllDay = allDay
        ev.startDate = start
        ev.endDate = end
        ev.calendar = cal
        do {
            try ek.save(ev, span: .thisEvent, commit: true)
            bump()
            return ev
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func save(_ ev: EKEvent, span: EKSpan = .thisEvent) {
        do { try ek.save(ev, span: span, commit: true) } catch {
            lastError = error.localizedDescription
            _ = ev.refresh()
        }
        bump()
    }

    func delete(_ ev: EKEvent, span: EKSpan = .thisEvent) {
        do { try ek.remove(ev, span: span, commit: true) } catch { lastError = error.localizedDescription }
        bump()
    }

    func move(_ ev: EKEvent, to newStart: Date) {
        guard ev.editable else { return }
        let dur = ev.endDate.timeIntervalSince(ev.startDate)
        ev.startDate = newStart
        ev.endDate = newStart.addingTimeInterval(dur)
        save(ev)
    }

    func setEnd(_ ev: EKEvent, _ end: Date) {
        guard ev.editable else { return }
        ev.endDate = max(end, ev.startDate.addingTimeInterval(15 * 60))
        save(ev)
    }

    /// Mou un esdeveniment a un altre dia mantenint l'hora (arrossegar i deixar anar).
    func move(qid: String, toDay day: Date) -> Bool {
        guard let ev = index[qid], ev.editable else { return false }
        let delta = Q.daysBetween(ev.startDate, day)
        guard delta != 0 else { return false }
        move(ev, to: Q.add(delta, to: ev.startDate))
        return true
    }
}
