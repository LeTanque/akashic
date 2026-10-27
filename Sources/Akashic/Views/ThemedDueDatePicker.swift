import SwiftUI

struct ThemedDueDatePicker: View {
    @Environment(\.textZoom) private var textZoom

    let savedCompleteBy: Date?
    let onSave: (Date?) -> Void

    @State private var isOpen = false
    @State private var draft = DueDateDraft(saved: nil)
    @State private var displayedMonth: Date = Date()
    @State private var isTriggerHovered = false

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                openPicker()
            } label: {
                HStack {
                    Text(triggerLabel)
                        .font(AkashicFont.mono(AkashicFont.callout, zoom: textZoom))
                        .foregroundStyle(CyberpunkTheme.neonCyan)
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CyberpunkTheme.neonCyan.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Rectangle().fill(Color.black.opacity(isTriggerHovered || isOpen ? 0.5 : 0.35)))
                .overlay(
                    Rectangle()
                        .stroke(
                            CyberpunkTheme.neonCyan.opacity(isTriggerHovered || isOpen ? 1 : 0.55),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
            .onHover { isTriggerHovered = $0 }
            .accessibilityLabel("Due date")
            .background {
                BorderlessFloatingPanelAnchor(isPresented: $isOpen) {
                    pickerPanel
                }
            }
        }
        .onChange(of: savedCompleteBy) { _, newValue in
            if !isOpen {
                draft.syncSaved(newValue)
            }
        }
        .onAppear {
            draft.syncSaved(savedCompleteBy)
        }
    }

    private var triggerLabel: String {
        if let savedCompleteBy {
            return Self.formatDateTime(savedCompleteBy)
        }
        return "Set due date…"
    }

    private func openPicker() {
        draft.syncSaved(savedCompleteBy)
        displayedMonth = draft.pending ?? Date()
        isOpen = true
    }

    private var pickerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusLines
            monthHeader
            weekdayHeader
            dayGrid
            timeRow
            actionRow
        }
        .padding(12)
        .frame(width: 280)
        .background(Color.black.opacity(0.94))
        .overlay(Rectangle().stroke(CyberpunkTheme.neonCyan.opacity(0.75), lineWidth: 1))
        .preferredColorScheme(.dark)
        .background(
            DueDatePickerKeyHandler(
                isActive: isOpen,
                onCancel: cancelPicker,
                onSave: {
                    if draft.hasChanges {
                        saveDueDate()
                    }
                }
            )
        )
    }

    private var statusLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved: \(savedLine(savedCompleteBy))")
            Text("Pending: \(savedLine(draft.pending))")
        }
        .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
        .foregroundStyle(CyberpunkTheme.completedShaded)
    }

    private func savedLine(_ date: Date?) -> String {
        guard let date else { return "None" }
        return Self.formatDateTime(date)
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(by: -1) } label: {
                chevronLabel("chevron.left")
            }
            .buttonStyle(.plain)
            .focusable(false)

            Spacer()
            Text(monthTitle(for: displayedMonth))
                .font(AkashicFont.mono(AkashicFont.callout, zoom: textZoom))
                .foregroundStyle(CyberpunkTheme.neonCyan)
            Spacer()

            Button { shiftMonth(by: 1) } label: {
                chevronLabel("chevron.right")
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
    }

    private func chevronLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(CyberpunkTheme.neonCyan)
            .frame(width: 28, height: 24)
            .background(Rectangle().fill(Color.black.opacity(0.35)))
            .overlay(Rectangle().stroke(CyberpunkTheme.neonCyan.opacity(0.5), lineWidth: 1))
    }

    private var weekdayHeader: some View {
        let symbols = calendar.shortWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(AkashicFont.mono(AkashicFont.micro, zoom: textZoom))
                    .foregroundStyle(CyberpunkTheme.completedShaded)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        let days = monthGrid(for: displayedMonth)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
            ForEach(days, id: \.self) { day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 28)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = draft.pending.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let today = calendar.isDateInToday(day)
        return Button {
            selectDay(day)
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                .foregroundStyle(selected ? Color.black : CyberpunkTheme.neonCyan)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    Rectangle().fill(
                        selected
                            ? CyberpunkTheme.neonCyan
                            : Color.black.opacity(today ? 0.45 : 0.2)
                    )
                )
                .overlay(
                    Rectangle().stroke(
                        today && !selected
                            ? CyberpunkTheme.neonCyan.opacity(0.9)
                            : CyberpunkTheme.neonCyan.opacity(selected ? 1 : 0.25),
                        lineWidth: today && !selected ? 1.5 : 1
                    )
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
    }

    private var timeRow: some View {
        HStack(spacing: 8) {
            Text("Time")
                .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                .foregroundStyle(CyberpunkTheme.completedShaded)
            Spacer()
            if Self.uses24HourClock {
                timeStepper(label: "Hour", value: hourBinding, range: 0 ... 23)
                timeStepper(label: "Min", value: minuteBinding, range: 0 ... 59)
            } else {
                timeStepper(label: "Hour", value: hour12Binding, range: 1 ... 12)
                Button(action: toggleMeridiem) {
                    Text(meridiemLabel)
                        .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                        .foregroundStyle(CyberpunkTheme.neonCyan)
                        .frame(width: 36, height: 36)
                        .background(Rectangle().fill(Color.black.opacity(0.35)))
                        .overlay(Rectangle().stroke(CyberpunkTheme.neonCyan.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .focusable(false)
                timeStepper(label: "Min", value: minuteBinding, range: 0 ... 59)
            }
        }
    }

    private func timeStepper(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            Button {
                let next = value.wrappedValue - 1
                value.wrappedValue = next < range.lowerBound ? range.upperBound : next
            } label: {
                Text("−")
                    .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .focusable(false)

            VStack(spacing: 0) {
                Text(label)
                    .font(AkashicFont.mono(AkashicFont.micro, zoom: textZoom))
                    .foregroundStyle(CyberpunkTheme.completedShaded)
                Text(String(format: "%02d", value.wrappedValue))
                    .font(AkashicFont.mono(AkashicFont.callout, zoom: textZoom))
                    .foregroundStyle(CyberpunkTheme.neonCyan)
                    .monospacedDigit()
            }
            .frame(width: 36)

            Button {
                let next = value.wrappedValue + 1
                value.wrappedValue = next > range.upperBound ? range.lowerBound : next
            } label: {
                Text("+")
                    .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(4)
        .background(Rectangle().fill(Color.black.opacity(0.35)))
        .overlay(Rectangle().stroke(CyberpunkTheme.neonCyan.opacity(0.45), lineWidth: 1))
    }

    private func toggleMeridiem() {
        var base = draft.pending ?? Date()
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: base)
        let hour = components.hour ?? 0
        components.hour = hour >= 12 ? hour - 12 : hour + 12
        if let merged = calendar.date(from: components) {
            draft.select(merged)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Clear") {
                draft.clearPending()
            }
            .buttonStyle(CyberBorderedButtonStyle())
            .help("Remove due date when saved")

            Spacer()

            Button("Cancel") {
                cancelPicker()
            }
            .buttonStyle(CyberBorderedButtonStyle())

            Button("SAVE DUE DATE") {
                saveDueDate()
            }
            .buttonStyle(CyberBorderedButtonStyle())
            .disabled(!draft.hasChanges)
        }
    }

    private func cancelPicker() {
        draft.cancel()
        isOpen = false
    }

    private func saveDueDate() {
        let committed = draft.commit()
        onSave(committed)
        isOpen = false
    }

    private func selectDay(_ day: Date) {
        var base = draft.pending ?? Date()
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: base)
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        components.year = dayParts.year
        components.month = dayParts.month
        components.day = dayParts.day
        if components.hour == nil { components.hour = 12 }
        if components.minute == nil { components.minute = 0 }
        if let merged = calendar.date(from: components) {
            draft.select(merged)
        }
    }

    private func shiftMonth(by offset: Int) {
        if let next = calendar.date(byAdding: .month, value: offset, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private func monthTitle(for date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    private func monthGrid(for month: Date) -> [Date?] {
        guard
            let dayRange = calendar.range(of: .day, in: .month, for: month),
            let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }

        let leading = (calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: {
                let date = draft.pending ?? Date()
                return calendar.component(.hour, from: date)
            },
            set: { updateTime(hour: $0) }
        )
    }

    private var hour12Binding: Binding<Int> {
        Binding(
            get: {
                let date = draft.pending ?? Date()
                let hour = calendar.component(.hour, from: date)
                let h = hour % 12
                return h == 0 ? 12 : h
            },
            set: { updateTime(hour12: $0) }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: {
                let date = draft.pending ?? Date()
                return calendar.component(.minute, from: date)
            },
            set: { updateTime(minute: $0) }
        )
    }

    private var meridiemLabel: String {
        let date = draft.pending ?? Date()
        let hour = calendar.component(.hour, from: date)
        return hour >= 12 ? "PM" : "AM"
    }

    private func updateTime(hour: Int? = nil, hour12: Int? = nil, minute: Int? = nil) {
        var base = draft.pending ?? Date()
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: base)
        if let hour {
            components.hour = (hour + 24) % 24
        }
        if let hour12 {
            let isPM = (components.hour ?? 0) >= 12
            var h = hour12 % 12
            if h == 0 { h = 12 }
            var hour24 = h % 12
            if isPM { hour24 += 12 }
            components.hour = hour24
        }
        if let minute {
            let normalized = (minute + 60) % 60
            components.minute = normalized
        }
        if let merged = calendar.date(from: components) {
            draft.select(merged)
        }
    }

    private static var uses24HourClock: Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !template.contains("a")
    }

    static func formatDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct DueDatePickerKeyHandler: NSViewRepresentable {
    var isActive: Bool
    var onCancel: () -> Void
    var onSave: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sync(
            active: isActive,
            onCancel: onCancel,
            onSave: onSave
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator {
        private var monitor: Any?
        private var onCancel: (() -> Void)?
        private var onSave: (() -> Void)?

        func sync(active: Bool, onCancel: @escaping () -> Void, onSave: @escaping () -> Void) {
            self.onCancel = onCancel
            self.onSave = onSave
            if active, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    switch event.keyCode {
                    case 53:
                        self.onCancel?()
                        return nil
                    case 36, 76:
                        self.onSave?()
                        return nil
                    default:
                        return event
                    }
                }
            } else if !active {
                teardown()
            }
        }

        func teardown() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
