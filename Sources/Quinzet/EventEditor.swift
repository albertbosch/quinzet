import SwiftUI
import EventKit

enum RepeatOption: Int, CaseIterable, Identifiable {
    case none, daily, weekly, fortnightly, monthly, yearly, custom
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return L("Mai")
        case .daily: return L("Cada dia")
        case .weekly: return L("Cada setmana")
        case .fortnightly: return L("Cada quinzena")
        case .monthly: return L("Cada mes")
        case .yearly: return L("Cada any")
        case .custom: return L("Personalitzat")
        }
    }

    func rule(end: Date?) -> EKRecurrenceRule? {
        let e = end.map { EKRecurrenceEnd(end: $0) }
        switch self {
        case .none, .custom: return nil
        case .daily: return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: e)
        case .weekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: e)
        case .fortnightly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: e)
        case .monthly: return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: e)
        case .yearly: return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: e)
        }
    }

    static func from(_ ev: EKEvent) -> RepeatOption {
        guard let r = ev.recurrenceRules?.first else { return .none }
        if (ev.recurrenceRules?.count ?? 0) > 1 || (r.daysOfTheWeek?.count ?? 0) > 1 || r.daysOfTheMonth != nil
            || r.setPositions != nil || (r.recurrenceEnd?.occurrenceCount ?? 0) > 0 {
            return .custom
        }
        switch (r.frequency, r.interval) {
        case (.daily, 1): return .daily
        case (.weekly, 1): return .weekly
        case (.weekly, 2): return .fortnightly
        case (.monthly, 1): return .monthly
        case (.yearly, 1): return .yearly
        default: return .custom
        }
    }
}

enum AlarmOption {
    static let list: [(title: String, offset: TimeInterval)] = [
        (L("En el moment de l'esdeveniment"), 0),
        (L("5 minuts abans"), -300),
        (L("10 minuts abans"), -600),
        (L("15 minuts abans"), -900),
        (L("30 minuts abans"), -1800),
        (L("1 hora abans"), -3600),
        (L("2 hores abans"), -7200),
        (L("1 dia abans"), -86_400),
        (L("2 dies abans"), -172_800),
        (L("El mateix dia a les 9:00"), 32_400),
        (L("El dia abans a les 9:00"), -54_000),
    ]
    /// -1 = cap, -2 = personalitzat (no es toca)
    static func index(_ alarms: [EKAlarm]?) -> Int {
        guard let a = alarms?.first else { return -1 }
        if a.absoluteDate != nil || (alarms?.count ?? 0) > 1 { return -2 }
        return list.firstIndex { $0.offset == a.relativeOffset } ?? -2
    }
}

/// Inspector d'esdeveniment (com el popover de Calendar). Els canvis es desen en tancar-lo.
struct EventEditor: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var state: AppState
    let event: EKEvent

    @State private var title: String
    @State private var location: String
    @State private var allDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var rep: RepeatOption
    @State private var hasEnd: Bool
    @State private var repEnd: Date
    @State private var alarm: Int
    @State private var calendarID: String
    @State private var url: String
    @State private var notes: String
    @State private var futureSpan = false
    @State private var deleted = false
    @State private var askDelete = false

    private let o: Snapshot

    private struct Snapshot {
        let title, location, url, notes, calendarID: String
        let allDay: Bool
        let start, end: Date
        let rep: RepeatOption
        let hasEnd: Bool
        let repEnd: Date
        let alarm: Int
    }

    init(event: EKEvent) {
        self.event = event
        let rEnd = event.recurrenceRules?.first?.recurrenceEnd?.endDate
        let snap = Snapshot(
            title: event.title ?? "",
            location: event.location ?? "",
            url: event.url?.absoluteString ?? "",
            notes: event.notes ?? "",
            calendarID: event.calendar?.calendarIdentifier ?? "",
            allDay: event.isAllDay,
            start: event.startDate,
            end: event.endDate,
            rep: RepeatOption.from(event),
            hasEnd: rEnd != nil,
            repEnd: rEnd ?? Q.addMonths(3, to: event.startDate),
            alarm: AlarmOption.index(event.alarms)
        )
        o = snap
        _title = State(initialValue: snap.title)
        _location = State(initialValue: snap.location)
        _allDay = State(initialValue: snap.allDay)
        _start = State(initialValue: snap.start)
        _end = State(initialValue: snap.end)
        _rep = State(initialValue: snap.rep)
        _hasEnd = State(initialValue: snap.hasEnd)
        _repEnd = State(initialValue: snap.repEnd)
        _alarm = State(initialValue: snap.alarm)
        _calendarID = State(initialValue: snap.calendarID)
        _url = State(initialValue: snap.url)
        _notes = State(initialValue: snap.notes)
    }

    private var editable: Bool { event.editable }

    /// Canviar l'inici desplaça el final (mantenint la durada), com a Calendar.
    private var startBinding: Binding<Date> {
        Binding(
            get: { start },
            set: { new in
                end = end.addingTimeInterval(new.timeIntervalSince(start))
                start = new
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Títol", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold))
                TextField("Afegeix una ubicació", text: $location)
                    .textFieldStyle(.plain)
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("tot el dia:").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Toggle("", isOn: $allDay).labelsHidden().toggleStyle(.checkbox)
                    }
                    GridRow {
                        Text("comença:").foregroundStyle(.secondary)
                        DatePicker("", selection: startBinding,
                                   displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                    GridRow {
                        Text("acaba:").foregroundStyle(.secondary)
                        DatePicker("", selection: $end, in: Q.day(start)...,
                                   displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                    GridRow {
                        Text("es repeteix:").foregroundStyle(.secondary)
                        Picker("", selection: $rep) {
                            ForEach(RepeatOption.allCases.filter { $0 != .custom || o.rep == .custom }) { r in
                                Text(r.title).tag(r)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                    if rep != RepeatOption.none && rep != .custom {
                        GridRow {
                            Text("final:").foregroundStyle(.secondary)
                            HStack {
                                Picker("", selection: $hasEnd) {
                                    Text("Mai").tag(false)
                                    Text("En una data").tag(true)
                                }
                                .labelsHidden()
                                .frame(maxWidth: 130)
                                if hasEnd {
                                    DatePicker("", selection: $repEnd, in: start..., displayedComponents: .date)
                                        .labelsHidden()
                                }
                            }
                        }
                    }
                    GridRow {
                        Text("avís:").foregroundStyle(.secondary)
                        Picker("", selection: $alarm) {
                            Text("Cap").tag(-1)
                            if o.alarm == -2 { Text("Personalitzat").tag(-2) }
                            ForEach(AlarmOption.list.indices, id: \.self) { i in
                                Text(AlarmOption.list[i].title).tag(i)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 230)
                    }
                    GridRow {
                        Text("calendari:").foregroundStyle(.secondary)
                        Picker("", selection: $calendarID) {
                            if !editable {
                                Text(event.calendar?.title ?? "").tag(o.calendarID)
                            }
                            ForEach(store.writableCalendars, id: \.calendarIdentifier) { c in
                                Text("\(c.title) — \(c.source?.title ?? "")").tag(c.calendarIdentifier)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 230)
                    }
                    GridRow {
                        Text("URL:").foregroundStyle(.secondary)
                        TextField("Cap", text: $url).textFieldStyle(.roundedBorder)
                    }
                }
                TextField("Afegeix notes", text: $notes, axis: .vertical)
                    .lineLimit(2...8)
                    .textFieldStyle(.roundedBorder)

                if let att = event.attendees, !att.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Convidats").font(.caption).foregroundStyle(.secondary)
                        ForEach(att.indices, id: \.self) { i in
                            Text("• " + (att[i].name ?? att[i].url.absoluteString.replacingOccurrences(of: "mailto:", with: "")))
                                .font(.caption)
                        }
                    }
                }
            }
            .disabled(!editable)

            if editable && event.hasRecurrenceRules {
                Picker("Aplica els canvis a:", selection: $futureSpan) {
                    Text("Només aquest").tag(false)
                    Text("Aquest i els futurs").tag(true)
                }
                .pickerStyle(.segmented)
                .font(.caption)
            }

            HStack {
                Text("\(Q.longLabel(start)) · \(Q.qString(start))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !editable {
                    Label("Només lectura", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if editable {
                    Button("Elimina", role: .destructive) {
                        if event.hasRecurrenceRules { askDelete = true } else { remove(.thisEvent) }
                    }
                }
                Button("Fet") { state.editingUID = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 380)
        .onChange(of: allDay) { _, isAll in
            if !isAll && Q.day(start) == start {
                let s = Q.atTime(start, hour: 9)
                start = s
                end = s.addingTimeInterval(3600)
            }
        }
        .onDisappear { if !deleted && editable { save() } }
        .confirmationDialog("Aquest és un esdeveniment periòdic.", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Elimina només aquest", role: .destructive) { remove(.thisEvent) }
            Button("Elimina aquest i els futurs", role: .destructive) { remove(.futureEvents) }
            Button("Cancel·la", role: .cancel) {}
        }
    }

    private func remove(_ span: EKSpan) {
        deleted = true
        state.editingUID = nil
        state.select(nil)
        store.delete(event, span: span)
    }

    private func save() {
        var changed = false
        if title != o.title { event.title = title; changed = true }
        if location != o.location { event.location = location.isEmpty ? nil : location; changed = true }
        if notes != o.notes { event.notes = notes.isEmpty ? nil : notes; changed = true }
        if url != o.url { event.url = URL(string: url.trimmingCharacters(in: .whitespaces)); changed = true }

        if allDay != o.allDay || start != o.start || end != o.end {
            if allDay {
                let s = Q.day(start)
                let e = max(Q.day(end), s)
                event.isAllDay = true
                event.startDate = s
                event.endDate = e.addingTimeInterval(86_399)
            } else {
                event.isAllDay = false
                event.startDate = start
                event.endDate = end > start ? end : start.addingTimeInterval(3600)
            }
            changed = true
        }

        if rep != o.rep || hasEnd != o.hasEnd || (hasEnd && repEnd != o.repEnd) {
            if rep != .custom {
                event.recurrenceRules = rep.rule(end: hasEnd ? repEnd : nil).map { [$0] }
                changed = true
            }
        }

        if alarm != o.alarm && alarm != -2 {
            event.alarms = alarm >= 0 ? [EKAlarm(relativeOffset: AlarmOption.list[alarm].offset)] : nil
            changed = true
        }

        if calendarID != o.calendarID, let c = store.calendar(calendarID) {
            event.calendar = c
            changed = true
        }

        if changed {
            store.save(event, span: (futureSpan && o.rep != RepeatOption.none) ? .futureEvents : .thisEvent)
        }
    }
}
