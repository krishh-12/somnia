import SwiftUI

struct RootView: View {
    @Bindable var model: DemoModel
    @State private var revealed = false

    var body: some View {
        ZStack {
            Group {
                if model.token == nil {
                    WelcomeView(model: model)
                } else if model.role == "caregiver" {
                    CaregiverTabs(model: model)
                } else {
                    PatientTabs(model: model)
                }
            }
            .opacity(revealed ? 1 : 0)
            if !revealed {
                OpeningView {
                    withAnimation(.easeInOut(duration: 0.55)) {
                        revealed = true
                    }
                }
                .transition(.opacity)
            }
        }
        .background(Night.background.ignoresSafeArea())
        .task {
            if model.token == nil {
                await model.enter(role: "patient")
            }
        }
        .fullScreenCover(item: $model.presentedAlarm) { event in
            AlarmView(event: event, busy: model.busy) {
                Task { await model.acknowledge() }
            }
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $model.showFeedback) {
            FeedbackSheet(model: model)
        }
    }
}

struct WelcomeView: View {
    @Bindable var model: DemoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("somnia")
                .font(.somnia(size: 44, weight: .semibold))
            Text("A nighttime prototype for one synthetic patient. It does not diagnose seizures or replace medical care.")
                .font(.somnia(.body))
                .foregroundStyle(Night.muted)
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.somnia(.footnote))
                    .foregroundStyle(Night.danger)
            }
            roleButton("Continue", role: "patient")
            Spacer()
        }
        .padding(24)
    }

    private func roleButton(_ title: String, role: String) -> some View {
        Button {
            Task { await model.enter(role: role) }
        } label: {
            Text(model.busy ? "Opening…" : title)
                .font(.somnia(.headline, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(NeuButtonStyle(prominent: true))
        .disabled(model.busy)
    }
}

struct PatientTabs: View {
    @Bindable var model: DemoModel

    var body: some View {
        TabView {
            PatientHome(model: model)
                .tabItem { Label("Home", systemImage: "moon.stars.fill") }
            InsightsView(model: model)
                .tabItem { Label("Insights", systemImage: "waveform.path.ecg") }
            LogView(model: model)
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
            ProfileView(model: model)
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
        .tint(Night.pink)
    }
}

struct CaregiverTabs: View {
    @Bindable var model: DemoModel

    var body: some View {
        TabView {
            CaregiverHome(model: model)
                .tabItem { Label("Home", systemImage: "bell.fill") }
            CaregiverPlan(model: model)
                .tabItem { Label("Plan", systemImage: "text.bubble.fill") }
        }
        .tint(Night.pink)
    }
}

struct CaregiverHome: View {
    @Bindable var model: DemoModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        Task { await model.enter(role: "patient") }
                    } label: {
                        Text(model.busy ? "Returning…" : "Back to patient")
                            .font(.somnia(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(NeuButtonStyle(prominent: true))
                    .disabled(model.busy)

                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.somnia(.footnote))
                            .foregroundStyle(Night.danger)
                    }

                    if let alarm = model.openAlarm {
                        NightCard {
                            Text("Alert")
                                .font(.somnia(.title2, weight: .semibold))
                                .foregroundStyle(Night.danger)
                            Text("\(model.patientName) has not said they are safe.")
                            Text("Stay nearby. The physician is named on this same alert.")
                                .foregroundStyle(Night.muted)
                            if let score = alarm.scorePeak {
                                Text(String(format: "Peak anomaly score %.2f", score))
                                    .font(.somnia(.footnote))
                                    .foregroundStyle(Night.pink)
                            }
                        }
                    } else {
                        NightCard {
                            Text("No active alert")
                                .font(.somnia(.title3, weight: .semibold))
                            Text("\(model.patientName) has no alarm waiting.")
                                .foregroundStyle(Night.muted)
                        }
                    }

                    Text("Recent anomalies")
                        .font(.somnia(.headline, weight: .semibold))
                    if model.events.isEmpty {
                        Text("None saved yet.")
                            .foregroundStyle(Night.muted)
                    } else {
                        ForEach(model.events) { event in
                            NightCard {
                                if let entry = model.logs.first(where: { $0.eventId == event.id }) {
                                    Text(entry.likely)
                                        .font(.somnia(.headline, weight: .semibold))
                                        .foregroundStyle(entry.kind == "seizure_like" ? Night.danger : Night.pink)
                                    Text(entry.detail)
                                        .foregroundStyle(Night.muted)
                                } else {
                                    Text(event.kind == "alarm" ? "Possible seizure-like event" : "Heart-rate observation")
                                        .font(.somnia(.headline, weight: .semibold))
                                    Text(event.reason)
                                        .foregroundStyle(Night.muted)
                                }
                                Text(event.alarmStatus.replacingOccurrences(of: "_", with: " "))
                                    .font(.somnia(.footnote))
                                    .foregroundStyle(Night.pink)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Night.background)
            .navigationTitle("Caregiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Patient") {
                        Task { await model.enter(role: "patient") }
                    }
                    .disabled(model.busy)
                }
            }
        }
    }
}

struct CaregiverPlan: View {
    @Bindable var model: DemoModel
    @State private var question = ""
    @FocusState private var asking: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.somnia(.footnote))
                            .foregroundStyle(Night.danger)
                    }

                    NightCard {
                        Text("Written for you")
                            .font(.somnia(.title3, weight: .semibold))
                        Text(model.caregiverBrief.isEmpty ? "The night summary appears here once it is loaded." : model.caregiverBrief)
                            .foregroundStyle(model.caregiverBrief.isEmpty ? Night.muted : Night.text)
                        Text(model.caregiverSource == "vultr" ? "Vultr wrote this from the saved night." : "A saved line for this night.")
                            .font(.somnia(.footnote))
                            .foregroundStyle(Night.pink)
                    }

                    NightCard {
                        Text("Plan")
                            .font(.somnia(.title3, weight: .semibold))
                        if let insights = model.insights, insights.hasData {
                            Text(insights.cause)
                            Text(insights.action)
                                .foregroundStyle(Night.muted)
                            if let hour = insights.commonTime {
                                Text("\(hour) is the hour that shows up most. Keep it with this night.")
                                    .foregroundStyle(Night.pink)
                            }
                        } else {
                            Text("The plan fills in after a night is saved.")
                                .foregroundStyle(Night.muted)
                        }
                        ShareLink(item: shareText) {
                            Text("Share this night")
                                .font(.somnia(.headline, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(NeuButtonStyle())
                    }

                    if !model.caregiverReply.isEmpty {
                        NightCard {
                            Text("Answer")
                                .font(.somnia(.title3, weight: .semibold))
                            Text(model.caregiverReply)
                            Text(model.caregiverReplySource == "vultr" ? "Vultr wrote this answer." : "A saved answer for this night.")
                                .font(.somnia(.footnote))
                                .foregroundStyle(Night.pink)
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Night.background)
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ask about this night")
                        .font(.somnia(.footnote))
                        .foregroundStyle(Night.muted)
                    TextField("Type a question", text: $question)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .foregroundStyle(Night.text)
                        .tint(Night.pink)
                        .focused($asking)
                        .submitLabel(.send)
                        .onSubmit(sendQuestion)
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                        .neuInset()
                    Button(action: sendQuestion) {
                        Text(model.busy ? "Asking…" : "Ask")
                            .font(.somnia(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(NeuButtonStyle(prominent: true))
                    .disabled(model.busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Night.background)
            }
        }
    }

    private func sendQuestion() {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, !model.busy else { return }
        Task {
            await model.askCaregiver(asked)
            question = ""
            asking = true
        }
    }

    private var shareText: String {
        var lines = ["somnia night"]
        if !model.caregiverBrief.isEmpty {
            lines.append(model.caregiverBrief)
        }
        if let insights = model.insights, insights.hasData {
            lines.append(insights.cause)
            lines.append(insights.action)
            if let hour = insights.commonTime {
                lines.append(hour)
            }
        }
        for entry in model.logs.prefix(5) {
            lines.append("\(entry.likely). \(entry.detail)")
        }
        return lines.joined(separator: "\n\n")
    }
}
