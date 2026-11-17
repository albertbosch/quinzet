import Foundation
import EventKit
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case day, fortnight, month, year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return L("Dia")
        case .fortnight: return L("Quinzena")
        case .month: return L("Mes")
        case .year: return L("Any")
        }
    }
}

/// Aritmètica de quinzenes. Un "dilluns 1" de referència (per defecte el 12 d'octubre de 2026)
/// defineix totes les quinzenes: Dl 1 … Dg 1, Dl 2 … Dg 2.
enum Q {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: Lang.isEnglish ? "en_GB" : "ca_ES")
        c.firstWeekday = 2
        return c
    }()

    static let shortDays = Lang.isEnglish
        ? ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        : ["Dl", "Dt", "Dc", "Dj", "Dv", "Ds", "Dg"]
    static let longDays = Lang.isEnglish
        ? ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        : ["Dilluns", "Dimarts", "Dimecres", "Dijous", "Divendres", "Dissabte", "Diumenge"]
    static let monthsCap = Lang.isEnglish
        ? ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        : ["Gener", "Febrer", "Març", "Abril", "Maig", "Juny", "Juliol", "Agost", "Setembre", "Octubre", "Novembre", "Desembre"]
    static let months = Lang.isEnglish
        ? monthsCap
        : ["gener", "febrer", "març", "abril", "maig", "juny", "juliol", "agost", "setembre", "octubre", "novembre", "desembre"]

    static let defaultAnchor: Date = cal.date(from: DateComponents(year: 2026, month: 10, day: 12))!

    static func mondayOf(_ d: Date) -> Date {
        cal.dateInterval(of: .weekOfYear, for: d)?.start ?? cal.startOfDay(for: d)
    }

    static var anchor: Date {
        let t = UserDefaults.standard.double(forKey: "anchorDate")
        return mondayOf(t == 0 ? defaultAnchor : Date(timeIntervalSinceReferenceDate: t))
    }

    static func day(_ d: Date) -> Date { cal.startOfDay(for: d) }
    static func add(_ n: Int, to d: Date) -> Date { cal.date(byAdding: .day, value: n, to: d)! }
    static func addMonths(_ n: Int, to d: Date) -> Date { cal.date(byAdding: .month, value: n, to: d)! }
    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        cal.dateComponents([.day], from: day(a), to: day(b)).day ?? 0
    }

    /// Posició 0…13 dins la quinzena.
    static func pos(_ d: Date) -> Int {
        let i = daysBetween(anchor, d) % 14
        return i < 0 ? i + 14 : i
    }
    /// Dilluns 1 de la quinzena que conté `d`.
    static func start(_ d: Date) -> Date { add(-pos(d), to: day(d)) }

    static func shortLabel(_ d: Date) -> String {
        let p = pos(d); return "\(shortDays[p % 7]) \(p < 7 ? 1 : 2)"
    }
    static func longLabel(_ d: Date) -> String {
        let p = pos(d); return "\(longDays[p % 7]) \(p < 7 ? 1 : 2)"
    }
    static func isWeekend(_ d: Date) -> Bool { pos(d) % 7 >= 5 }

    /// Número de quinzena dins l'any (Q1 = la que conté l'1 de gener; compta per l'any on acaba).
    static func qNumber(_ d: Date) -> (q: Int, year: Int) {
        let s = start(d)
        let y = cal.component(.year, from: add(13, to: s))
        let s1 = start(cal.date(from: DateComponents(year: y, month: 1, day: 1))!)
        return (daysBetween(s1, s) / 14 + 1, y)
    }
    static func qString(_ d: Date) -> String {
        let q = qNumber(d); return "Q\(q.q) · \(q.year)"
    }

    static func comps(_ d: Date) -> (y: Int, m: Int, d: Int) {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return (c.year!, c.month!, c.day!)
    }
    static func monthStart(_ d: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: d))!
    }
    static func monthName(_ d: Date) -> String { months[cal.component(.month, from: d) - 1] }
    static func deMonth(_ m: Int) -> String {
        let n = months[m - 1]
        if Lang.isEnglish { return n }
        return (n.hasPrefix("a") || n.hasPrefix("o")) ? "d’\(n)" : "de \(n)"
    }

    /// Inicis de les quinzenes que toquen el mes de `d`.
    static func fortnightRows(forMonthOf d: Date) -> [Date] {
        let first = monthStart(d)
        let last = add(-1, to: addMonths(1, to: first))
        var rows: [Date] = []
        var s = start(first)
        while s <= last { rows.append(s); s = add(14, to: s) }
        return rows
    }

    static func atTime(_ d: Date, hour: Int, minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: day(d)) ?? d
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: Lang.isEnglish ? "en_GB" : "ca_ES"); f.dateFormat = "HH:mm"; return f
    }()
    private static let longFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: Lang.isEnglish ? "en_GB" : "ca_ES"); f.dateFormat = "d MMM yyyy"; return f
    }()
    static func time(_ d: Date) -> String { timeFmt.string(from: d) }
    static func dateString(_ d: Date) -> String { longFmt.string(from: d) }
}

extension EKEvent {
    /// Identificador únic també per a les ocurrències d'esdeveniments periòdics.
    var qid: String {
        let d: Date? = occurrenceDate ?? startDate
        let t = d?.timeIntervalSinceReferenceDate ?? 0
        return "\(eventIdentifier ?? "nou")|\(t)"
    }
    var qColor: Color { Color(nsColor: calendar?.color ?? .systemBlue) }
    var isLong: Bool { isAllDay || endDate.timeIntervalSince(startDate) >= 86_400 }
    var editable: Bool { calendar?.allowsContentModifications ?? false }
}

/// Esdeveniment col·locat en una columna horària.
struct Placed: Identifiable {
    let ev: EKEvent
    let start: Double   // minuts des de mitjanit
    let end: Double
    var lane = 0
    var lanes = 1
    var id: String { ev.qid }
}

func layoutDay(_ evs: [EKEvent], day: Date) -> [Placed] {
    let d0 = Q.day(day), d1 = Q.add(1, to: d0)
    let items: [Placed] = evs.map { e in
        let s = max(e.startDate, d0), en = min(e.endDate, d1)
        let a = s.timeIntervalSince(d0) / 60
        let b = max(en.timeIntervalSince(d0) / 60, a + 20)
        return Placed(ev: e, start: a, end: b)
    }.sorted { $0.start < $1.start || ($0.start == $1.start && $0.end > $1.end) }

    var out: [Placed] = []
    var cluster: [Placed] = []
    var clusterEnd = -1.0
    func flush() {
        var laneEnds: [Double] = []
        for i in cluster.indices {
            if let l = laneEnds.firstIndex(where: { $0 <= cluster[i].start }) {
                cluster[i].lane = l; laneEnds[l] = cluster[i].end
            } else {
                cluster[i].lane = laneEnds.count; laneEnds.append(cluster[i].end)
            }
        }
        for i in cluster.indices { cluster[i].lanes = laneEnds.count }
        out.append(contentsOf: cluster)
        cluster = []
    }
    for it in items {
        if !cluster.isEmpty && it.start >= clusterEnd { flush(); clusterEnd = -1 }
        cluster.append(it)
        clusterEnd = max(clusterEnd, it.end)
    }
    if !cluster.isEmpty { flush() }
    return out
}
