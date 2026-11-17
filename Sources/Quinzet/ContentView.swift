import SwiftUI
import EventKit
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var state: AppState
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.authorized {
                mainView
            } else {
                AccessView()
            }
        }
        .onAppear {
            store.checkStatus()
            if !store.authorized && !store.denied { store.requestAccess() }
        }
        .onReceive(timer) { state.now = $0 }
    }

    private var mainView: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 300, ideal: 310, max: 380)
        } detail: {
            VStack(spacing: 0) {
                TitleBar()
                Divider()
                Group {
                    if !state.search.trimmingCharacters(in: .whitespaces).isEmpty {
                        SearchResults()
                    } else {
                        switch state.mode {
                        case .day:
                            TimeGridView(days: [Q.day(state.cursor)])
                        case .fortnight:
                            TimeGridView(days: (0..<14).map { Q.add($0, to: Q.start(state.cursor)) })
                        case .month:
                            MonthView()
                        case .year:
                            YearView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Vista", selection: $state.mode) {
                    ForEach(ViewMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { state.newEvent() } label: { Image(systemName: "plus") }
                    .help("Nou esdeveniment (⌘N)")
            }
        }
        .searchable(text: $state.search, placement: .toolbar, prompt: "Cerca")
        .onDeleteCommand {
            if let ev = state.selectedEvent, state.editingUID == nil { state.requestDelete(ev) }
        }
        .confirmationDialog(
            "Aquest és un esdeveniment periòdic.",
            isPresented: Binding(get: { state.pendingDelete != nil }, set: { if !$0 { state.pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Elimina només aquest", role: .destructive) {
                if let ev = state.pendingDelete { store.delete(ev, span: .thisEvent) }
                state.pendingDelete = nil; state.select(nil)
            }
            Button("Elimina aquest i els futurs", role: .destructive) {
                if let ev = state.pendingDelete { store.delete(ev, span: .futureEvents) }
                state.pendingDelete = nil; state.select(nil)
            }
            Button("Cancel·la", role: .cancel) { state.pendingDelete = nil }
        }
        .alert(
            "No s'ha pogut completar l'acció",
            isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })
        ) {
            Button("D'acord", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .sheet(isPresented: $state.showNewCalendar) { NewCalendarSheet() }
        .sheet(isPresented: $state.showSubscribe) { SubscribeSheet() }
    }
}

// MARK: - Barra de títol

struct TitleBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(state.title)
                .font(.system(size: 24, weight: .bold))
            if !state.subtitle.isEmpty {
                Text(state.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Button { state.step(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Anterior (⌘←)")
                Button("Avui") { state.today() }
                    .help("Avui (⌘T)")
                Button { state.step(1) } label: { Image(systemName: "chevron.right") }
                    .help("Següent (⌘→)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

// MARK: - Accés

struct AccessView: View {
    @EnvironmentObject var store: CalendarStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Quinzet necessita accés als teus calendaris")
                .font(.title2.weight(.semibold))
            Text("Fa servir els mateixos calendaris que l'app Calendar (iCloud, Google, Exchange, subscripcions…) i els mostra en quinzenes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            if store.denied {
                Button("Obre Configuració del Sistema") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Text("Activa Quinzet a Privadesa i seguretat › Calendaris i torna a obrir l'app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Torna-ho a comprovar") { store.checkStatus() }
            } else {
                Button("Dona accés") { store.requestAccess() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Barra lateral

struct Sidebar: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var state: AppState
    @State private var miniMonth = Q.monthStart(Date())
    @State private var calendarToDelete: EKCalendar?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(Q.monthsCap[Q.comps(miniMonth).m - 1]) \(String(Q.comps(miniMonth).y))")
                            .font(.headline)
                        Spacer()
                        Button { miniMonth = Q.addMonths(-1, to: miniMonth) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless)
                        Button { miniMonth = Q.addMonths(1, to: miniMonth) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.borderless)
                    }
                    MiniMonth(month: miniMonth, showTitle: false, highlight: state.visibleRange) { d in
                        state.cursor = d
                        if state.mode == .year { state.mode = .fortnight }
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(store.groups) { g in
                Section(g.title) {
                    ForEach(g.calendars, id: \.calendarIdentifier) { c in
                        Toggle(isOn: Binding(get: { store.isVisible(c) }, set: { store.setVisible(c, $0) })) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(nsColor: c.color ?? .systemBlue)).frame(width: 10, height: 10)
                                Text(c.title)
                                    .lineLimit(1)
                                if !c.allowsContentModifications {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .contextMenu {
                            Button("Mostra només aquest") {
                                for other in store.calendars { store.setVisible(other, other.calendarIdentifier == c.calendarIdentifier) }
                            }
                            Button("Mostra'ls tots") {
                                for other in store.calendars { store.setVisible(other, true) }
                            }
                            if c.allowsContentModifications && !c.isImmutable {
                                Divider()
                                Button("Elimina el calendari…", role: .destructive) { calendarToDelete = c }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { state.showNewCalendar = true } label: { Label("Calendari", systemImage: "plus") }
                Button { state.showSubscribe = true } label: { Label("Subscripció", systemImage: "antenna.radiowaves.left.and.right") }
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .onChange(of: state.cursor) { _, new in miniMonth = Q.monthStart(new) }
        .confirmationDialog(
            "Vols eliminar el calendari «\(calendarToDelete?.title ?? "")» i tots els seus esdeveniments?",
            isPresented: Binding(get: { calendarToDelete != nil }, set: { if !$0 { calendarToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) {
                if let c = calendarToDelete { store.deleteCalendar(c) }
                calendarToDelete = nil
            }
            Button("Cancel·la", role: .cancel) { calendarToDelete = nil }
        }
    }
}

// MARK: - Fulls: nou calendari i subscripció

struct NewCalendarSheet: View {
    @EnvironmentObject var store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var color = Color.blue
    @State private var sourceID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nou calendari").font(.headline)
            Form {
                TextField("Nom", text: $title)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                Picker("Compte", selection: $sourceID) {
                    ForEach(store.writableSources, id: \.sourceIdentifier) { s in
                        Text(s.title).tag(s.sourceIdentifier)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel·la") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Crea") {
                    store.createCalendar(title: title, color: color, sourceID: sourceID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            sourceID = store.ek.defaultCalendarForNewEvents?.source?.sourceIdentifier
                ?? store.writableSources.first?.sourceIdentifier ?? ""
        }
    }
}

struct SubscribeSheet: View {
    @EnvironmentObject var store: CalendarStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nova subscripció a calendari").font(.headline)
            Text("Enganxa l'adreça d'un calendari en línia (.ics o webcal://). S'obrirà l'app Calendar per confirmar la subscripció i, un cop feta, apareixerà automàticament a Quinzet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("webcal://exemple.com/calendari.ics", text: $url)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel·la") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Subscriu-t'hi") {
                    store.subscribe(url)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

// MARK: - Configuració

struct SettingsView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var state: AppState
    @AppStorage("anchorDate") private var anchorT: Double = 0
    @AppStorage("dayStartHour") private var startHour = 7
    @AppStorage("defaultCalendarID") private var defaultCalendarID = ""

    var body: some View {
        Form {
            Section("Quinzenes") {
                DatePicker(
                    "Un «Dilluns 1» de referència:",
                    selection: Binding(
                        get: { anchorT == 0 ? Q.defaultAnchor : Date(timeIntervalSinceReferenceDate: anchorT) },
                        set: { anchorT = Q.mondayOf($0).timeIntervalSinceReferenceDate; state.objectWillChange.send() }
                    ),
                    displayedComponents: .date
                )
                Text("Qualsevol data s'ajusta al dilluns de la seva setmana. Per defecte: 12 d’octubre de 2026.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Restableix el valor per defecte") {
                    anchorT = 0
                    state.objectWillChange.send()
                }
            }
            Section("Agenda") {
                Stepper("La vista horària comença a les \(startHour):00", value: $startHour, in: 0...12)
                Picker("Calendari per a esdeveniments nous:", selection: $defaultCalendarID) {
                    Text("El predeterminat del sistema").tag("")
                    ForEach(store.writableCalendars, id: \.calendarIdentifier) { c in
                        Text("\(c.title) (\(c.source?.title ?? ""))").tag(c.calendarIdentifier)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}
