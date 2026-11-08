import SwiftUI

struct HistoryView: View {
    @Bindable var model: DemoModel

    var body: some View {
        NavigationStack {
            Group {
                if model.events.isEmpty {
                    ContentUnavailableView(
                        "No events saved yet",
                        systemImage: "clock",
                        description: Text("A scored test will appear here after the server saves it.")
                    )
                } else {
                    List(model.events) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.kind == "alarm" ? "Possible seizure-like event" : "Heart-rate observation")
                                .font(.somnia(.headline, weight: .semibold))
                            Text(event.reason)
                                .font(.somnia(.subheadline))
                                .foregroundStyle(Night.muted)
                            Text(event.synthetic ? "Synthetic · \(event.alarmStatus.replacingOccurrences(of: "_", with: " "))" : event.alarmStatus)
                                .font(.somnia(.footnote))
                                .foregroundStyle(Night.pink)
                            if let score = event.scorePeak {
                                Text(String(format: "Peak anomaly score %.2f", score))
                                    .font(.somnia(.footnote))
                                    .foregroundStyle(Night.muted)
                            }
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(Night.card)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Night.background)
            .navigationTitle("History")
        }
    }
}

struct InsightsView: View {
    @Bindable var model: DemoModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let insights = model.insights {
                        HStack(alignment: .top, spacing: 12) {
                            countCard("Tonight", value: insights.tonightCount, caption: "anomalies")
                            countCard("This week", value: insights.weekCount, caption: "anomalies")
                        }
                        InsightModule(title: "Sleep window", detail: model.live?.sleepWindow ?? "Not loaded") {
                            Text("The modules below use saved events from this window and the last seven days.")
                        }
                        InsightModule(title: "Tonight", detail: tonightDetail(insights)) {
                            Text(insights.tonightCount == 0 ? "Nothing saved in the current sleep window." : "An alarm needs movement and a higher heart rate. An observation is heart rate alone.")
                        }
                        InsightModule(title: "This week", detail: weekDetail()) {
                            Text(weekCaption())
                        }
                        InsightModule(title: "Most common time", detail: insights.commonTime ?? "Not enough yet") {
                            Text(commonDetail(insights))
                        }
                        InsightModule(title: "What may be going on", detail: nil) {
                            Text(insights.cause)
                        }
                        InsightModule(title: "What to do", detail: nil) {
                            Text(insights.action)
                        }
                        if insights.narration == "vultr" {
                            Text("The two written sections come from a Vultr model. The counts, score, and times do not. This is not a diagnosis.")
                                .font(.somnia(.footnote))
                                .foregroundStyle(Night.pink)
                        }
                        if insights.synthetic {
                            Text("These modules use saved synthetic nights.")
                                .font(.somnia(.footnote))
                                .foregroundStyle(Night.muted)
                        }
                    } else {
                        Text(model.status.isEmpty ? "Loading the night summary…" : model.status)
                            .foregroundStyle(Night.muted)
                    }
                }
                .padding(20)
            }
            .background(Night.background)
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func countCard(_ title: String, value: Int, caption: String) -> some View {
        NightCard {
            Text(title)
                .font(.somnia(.subheadline))
                .foregroundStyle(Night.muted)
            Text("\(value)")
                .font(.somnia(size: 40, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.somnia(.footnote))
                .foregroundStyle(Night.pink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tonightEvents() -> [DemoEvent] {
        let start = Date().addingTimeInterval(-16 * 60 * 60)
        return model.events.filter { $0.startedAt >= start }
    }

    private func tonightDetail(_ insights: NightInsights) -> String {
        let events = tonightEvents()
        let alarms = events.filter { $0.kind == "alarm" }.count
        let observations = events.filter { $0.kind == "observation" }.count
        if insights.tonightCount == 0 {
            return "None saved"
        }
        return "\(insights.tonightCount) total · \(alarms) alarm · \(observations) observation"
    }

    private func weekDetail() -> String {
        let alarms = model.events.filter { $0.kind == "alarm" }.count
        let observations = model.events.filter { $0.kind == "observation" }.count
        let turnedOff = model.events.filter { $0.acknowledgedAt != nil }.count
        let peak = model.events.compactMap(\.scorePeak).max()
        var parts = ["\(alarms) alarm", "\(observations) observation", "\(turnedOff) turned off"]
        if let peak {
            parts.append(String(format: "peak %.2f", peak))
        }
        return parts.joined(separator: " · ")
    }

    private func weekCaption() -> String {
        let waiting = model.events.filter { $0.alarmStatus == "awaiting_ack" }.count
        if model.events.isEmpty {
            return "This fills in after the server saves an anomaly."
        }
        if waiting == 1 {
            return "One saved alarm is still marked waiting. Opening the app does not start it."
        }
        if waiting > 1 {
            return "\(waiting) saved alarms are still marked waiting. Opening the app does not start them."
        }
        return "Turned off means someone marked that alarm as safe. The peak is the highest anomaly score in the saved list."
    }

    private func commonDetail(_ insights: NightInsights) -> String {
        guard insights.hasData, insights.commonTimeCount > 0 else {
            return "This fills in after the server saves an anomaly."
        }
        let noun = insights.commonTimeCount == 1 ? "anomaly" : "anomalies"
        return "\(insights.commonTimeCount) \(noun) this week started in that hour."
    }
}

private struct InsightModule<Detail: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var note: () -> Detail

    var body: some View {
        NightCard {
            Text(title)
                .font(.somnia(.subheadline))
                .foregroundStyle(Night.pink)
            if let detail {
                Text(detail)
                    .font(.somnia(.title3, weight: .semibold))
            }
            note()
                .font(.somnia(.footnote))
                .foregroundStyle(Night.muted)
        }
    }
}

struct ProfileView: View {
    @Bindable var model: DemoModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NightCard {
                        Text(model.displayName)
                            .font(.somnia(.title2, weight: .semibold))
                        Text(model.role.capitalized)
                            .foregroundStyle(Night.pink)
                        Text(model.live?.sleepWindow ?? "Sleep window loads from the server")
                            .font(.somnia(.footnote))
                            .foregroundStyle(Night.muted)
                            .padding(.top, 6)
                    }
                    Button {
                        Task { await model.enter(role: "caregiver") }
                    } label: {
                        Text("Switch to caregiver")
                            .font(.somnia(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Night.pink)
                    Button {
                        model.showWearable = true
                    } label: {
                        Label(model.live?.wearableLabel ?? "Wearable import not connected", systemImage: "applewatch")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(Night.indigo)
                    Text("Somnia is a prototype. It does not diagnose seizures, predict events, or replace medical care. On iPhone the alarm plays a sound and a haptic while its screen is open. It is not a locked-phone alarm.")
                        .font(.somnia(.footnote))
                        .foregroundStyle(Night.muted)
                    Button("Leave demo", role: .destructive) {
                        model.leave()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .background(Night.background)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $model.showWearable) {
                WearableSheet()
            }
        }
    }
}

struct FeedbackSheet: View {
    @Bindable var model: DemoModel
    @Environment(\.dismiss) private var dismiss
    @State private var choice = ""
    @State private var note = ""

    private let choices = [
        ("turning_over", "I was turning over"),
        ("awake", "I was awake"),
        ("unsure", "I'm not sure"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose the closest description. A note is optional. Somnia saves this with the event for a later review. It does not change the score, and it is not a diagnosis.")
                        .foregroundStyle(Night.muted)
                    ForEach(choices, id: \.0) { key, title in
                        Button {
                            choice = key
                        } label: {
                            Text(title)
                                .font(.somnia(.headline, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(choice == key ? Night.pink : Night.card)
                    }
                    TextField("Add a note", text: $note, axis: .vertical)
                        .font(.somnia(.body))
                        .foregroundStyle(Night.text)
                        .lineLimit(3 ... 5)
                        .padding(12)
                        .background(Night.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button {
                        Task {
                            let saved = await model.sendFeedback(label: choice, note: note)
                            if saved { dismiss() }
                        }
                    } label: {
                        Text(model.busy ? "Saving…" : "Save")
                            .font(.somnia(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Night.pink)
                    .disabled(model.busy || choice.isEmpty)
                    Button {
                        model.showFeedback = false
                        dismiss()
                    } label: {
                        Text("Skip")
                            .font(.somnia(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .disabled(model.busy)
                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.somnia(.footnote))
                            .foregroundStyle(Night.danger)
                    }
                }
                .padding(20)
            }
            .background(Night.background)
            .navigationTitle("What was happening?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

struct AlarmView: View {
    let event: DemoEvent
    let busy: Bool
    let acknowledge: () -> Void
    @State private var signal = AlarmSignal()
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color(red: 0.42, green: 0.02, blue: 0.06)
            Circle()
                .fill(Color(red: 0.92, green: 0.12, blue: 0.16))
                .frame(width: pulse ? 520 : 180, height: pulse ? 520 : 180)
                .blur(radius: 18)
                .opacity(0.85)
            VStack(alignment: .leading, spacing: 18) {
                Text("Alarm")
                    .font(.somnia(size: 52, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Possible seizure-like event")
                    .font(.somnia(.title, weight: .semibold))
                    .foregroundStyle(.white)
                Text("If you do not say you are okay, Somnia will notify your caregiver and physician.")
                    .font(.somnia(.title3))
                    .foregroundStyle(.white.opacity(0.92))
                Text(event.reason)
                    .foregroundStyle(.white.opacity(0.82))
                Text("I'm okay means you are safe. It does not decide whether the pattern was a seizure.")
                    .font(.somnia(.footnote))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 24)
                Button {
                    signal.stop()
                    acknowledge()
                } label: {
                    Text(busy ? "Saving…" : "I'm okay")
                        .font(.somnia(.title3, weight: .semibold))
                        .foregroundStyle(Color(red: 0.45, green: 0.02, blue: 0.05))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .disabled(busy)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.42, green: 0.02, blue: 0.06))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                pulse = true
            }
            signal.start()
        }
        .onDisappear {
            signal.stop()
        }
    }
}
