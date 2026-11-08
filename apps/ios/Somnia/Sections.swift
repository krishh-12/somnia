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
                        .listRowBackground(Night.well)
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
    @State private var openSection: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let insights = model.insights {
                        HStack(alignment: .top, spacing: 12) {
                            countCard("Today", value: insights.tonightCount, caption: "anomalies")
                            countCard("This week", value: insights.weekCount, caption: "anomalies")
                        }
                        Text("Tap a header to open it.")
                            .font(.somnia(.footnote))
                            .foregroundStyle(Night.muted)
                        Fold(title: "Today", summary: tonightDetail(insights), isOpen: openSection == "Today") {
                            openSection = openSection == "Today" ? nil : "Today"
                        } content: {
                            Text(model.live?.sleepWindow ?? "Sleep window not loaded")
                            Text(insights.tonightCount == 0 ? "Nothing saved in the current sleep window." : "An alarm needs movement and a higher heart rate. An observation is heart rate alone.")
                        }
                        Fold(title: "This week", summary: weekDetail(), isOpen: openSection == "This week") {
                            openSection = openSection == "This week" ? nil : "This week"
                        } content: {
                            Text(weekCaption())
                        }
                        Fold(title: "Usual hour", summary: insights.commonTime ?? "Not enough yet", isOpen: openSection == "Usual hour") {
                            openSection = openSection == "Usual hour" ? nil : "Usual hour"
                        } content: {
                            Text(commonDetail(insights))
                        }
                        Fold(title: "Written summary", summary: insights.narration == "vultr" ? "From a Vultr model" : "Fixed sentences", isOpen: openSection == "Written summary") {
                            openSection = openSection == "Written summary" ? nil : "Written summary"
                        } content: {
                            Text(insights.cause)
                            Text(insights.action)
                            Text(insights.narration == "vultr" ? "A Vultr model wrote these two paragraphs from the counts. It did not produce the score. This is not a diagnosis." : "These sentences are the backup wording. This is not a diagnosis.")
                        }
                        Fold(title: "Plan for Krish", summary: planSummary(insights), isOpen: openSection == "Plan for Krish") {
                            openSection = openSection == "Plan for Krish" ? nil : "Plan for Krish"
                        } content: {
                            ForEach(Array(planSteps(insights).enumerated()), id: \.offset) { index, step in
                                Text("\(index + 1). \(step)")
                            }
                            Text("Sources: CDC seizure first aid, and Harden et al., Neurology, 2017, a guideline from the American Academy of Neurology and the American Epilepsy Society. The guideline’s nighttime-supervision suggestion is for selected people who already have frequent convulsive seizures. Krish’s nights here are synthetic. This is not a diagnosis or a clinician’s order.")
                                .font(.somnia(.footnote))
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

    private func planSummary(_ insights: NightInsights) -> String {
        insights.hasData ? "Steps from this week’s nights" : "Needs a saved night"
    }

    private func planSteps(_ insights: NightInsights) -> [String] {
        guard insights.hasData else {
            return ["Run a test from Home. The plan uses the saved counts, the usual hour, and the written summary."]
        }
        var steps: [String] = []
        let alarms = model.events.filter { $0.kind == "alarm" }.count
        let noted = model.events.filter { $0.reviewStatus == "patient_noted" }.count
        if alarms > 0 {
            steps.append("If the red screen is up and you are safe, tap I’m okay. That means you are safe. It does not decide whether the pattern was a seizure.")
        }
        if let hour = insights.commonTime {
            steps.append("\(hour) is the hour that shows up most in the saved nights. Keep that hour, and the \(model.live?.sleepWindow ?? "sleep window"), in a note for a clinician.")
        }
        steps.append(insights.action)
        if noted > 0 {
            let noun = noted == 1 ? "event has" : "events have"
            steps.append("\(noted) \(noun) a saved note about what was happening. The note does not change the score, and a physician has not reviewed it yet.")
        }
        steps.append("The caregiver screen is who this demo says it will notify if an alarm stays on. A 2017 guideline found that, for some people who already have frequent convulsive seizures at night, having another person nearby or a listening device was associated with lower sudden-death risk. That finding is not a risk score for Krish.")
        steps.append("CDC first aid says to call emergency services if a seizure lasts longer than 5 minutes, another starts soon after, breathing or waking is difficult, there is an injury, it happens in water, or the person has never had a seizure before.")
        return steps
    }
}

private struct Fold<Content: View>: View {
    var title: String
    var summary: String
    var isOpen: Bool
    var toggle: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Night.reveal) { toggle() }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Circle()
                        .fill(Night.pink)
                        .frame(width: 9, height: 9)
                        .scaleEffect(isOpen ? 1.25 : 0.85)
                        .opacity(isOpen ? 1 : 0.45)
                        .shadow(color: Night.pink.opacity(isOpen ? 0.7 : 0), radius: 6)
                    Text(title)
                        .font(.somnia(.title3, weight: .semibold))
                        .foregroundStyle(Night.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.somnia(.subheadline, weight: .semibold))
                        .foregroundStyle(Night.pink)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .padding(8)
                        .neuRaised(radius: 14)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Hides the details" : "Shows the details")
            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    Text(summary)
                        .font(.somnia(.headline, weight: .semibold))
                        .foregroundStyle(Night.pink)
                    content()
                }
                .font(.somnia(.body))
                .foregroundStyle(Night.muted)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .neuInset()
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)).combined(with: .offset(y: -8)),
                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                ))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuRaised()
        .animation(Night.reveal, value: isOpen)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.85), trigger: isOpen) { _, opened in
            opened
        }
    }
}

struct LogView: View {
    @Bindable var model: DemoModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.logs.isEmpty {
                        Text("No anomalies logged yet. A turn, a heart-rate change, or a seizure-like pattern appears here. Quiet sleep does not.")
                            .foregroundStyle(Night.muted)
                    } else {
                        ForEach(model.logs) { entry in
                            NightCard {
                                Text(entry.at, format: .dateTime.hour().minute())
                                    .font(.somnia(.footnote))
                                    .foregroundStyle(Night.muted)
                                Text(entry.likely)
                                    .font(.somnia(.headline, weight: .semibold))
                                    .foregroundStyle(entry.kind == "seizure_like" ? Night.danger : Night.pink)
                                Text(entry.detail)
                                if let heart = entry.heartRateBpm, let variability = entry.hrvRmssd, let motion = entry.motionRms {
                                    Text("Heart rate \(Int(heart.rounded())) bpm")
                                    Text("Variability \(Int(variability.rounded())) ms")
                                    Text(String(format: "Motion %.2f m/s²", motion))
                                        .foregroundStyle(Night.muted)
                                }
                                Text(entry.source == "vultr" ? "Compiled by a Vultr model from these measurements. This is not a diagnosis." : "Fixed wording from these measurements. A Vultr model was not used for this line.")
                                    .font(.somnia(.footnote))
                                    .foregroundStyle(entry.source == "vultr" ? Night.pink : Night.muted)
                                if entry.synthetic {
                                    Text("Synthetic night")
                                        .font(.somnia(.footnote))
                                        .foregroundStyle(Night.muted)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Night.background)
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
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
                    .buttonStyle(NeuButtonStyle(prominent: true))
                    Button {
                        model.showWearable = true
                    } label: {
                        Label(model.live?.wearableLabel ?? "Wearable import not connected", systemImage: "applewatch")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(NeuButtonStyle())
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
                    Text("Choose the closest description. A note is optional. somnia saves this with the event for a later review. It does not change the score, and it is not a diagnosis.")
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
                        .buttonStyle(NeuButtonStyle(prominent: choice == key))
                    }
                    TextField("Add a note", text: $note, axis: .vertical)
                        .font(.somnia(.body))
                        .foregroundStyle(Night.text)
                        .lineLimit(3 ... 5)
                        .padding(12)
                        .neuInset()
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
                    .buttonStyle(NeuButtonStyle(prominent: true))
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
                Text("If you do not say you are okay, somnia will notify your caregiver and physician.")
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
