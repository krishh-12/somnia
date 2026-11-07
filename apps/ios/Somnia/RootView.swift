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
                    CaregiverHome(model: model)
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
        .alert("Possible seizure-like event", isPresented: $model.showAlarmNotice) {
            Button("Turn off") { Task { await model.acknowledge() } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("If you do not turn this off, Somnia will notify your caregiver and physician.")
        }
        .fullScreenCover(isPresented: $model.showAlarmScreen) {
            if let event = model.alarm {
                AlarmView(event: event, busy: model.busy) {
                    Task { await model.acknowledge() }
                } onDismiss: {
                    model.showAlarmScreen = false
                }
            }
        }
    }
}

struct WelcomeView: View {
    @Bindable var model: DemoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("Somnia")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
            Text("A nighttime prototype for one synthetic patient. It does not diagnose seizures or replace medical care.")
                .font(.body)
                .foregroundStyle(Night.muted)
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(Night.danger)
            }
            roleButton("Continue", role: "patient", tint: Night.pink)
            Spacer()
        }
        .padding(24)
    }

    private func roleButton(_ title: String, role: String, tint: Color) -> some View {
        Button {
            Task { await model.enter(role: role) }
        } label: {
            Text(model.busy ? "Opening…" : title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
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
            ProfileView(model: model)
                .tabItem { Label("Profile", systemImage: "person.fill") }
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
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Night.pink)
                    .disabled(model.busy)

                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.footnote)
                            .foregroundStyle(Night.danger)
                    }

                    if let alarm = model.openAlarm {
                        NightCard {
                            Text("Alert")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Night.danger)
                            Text("Avery has not turned off a possible seizure-like event.")
                            Text("If it stays on, the caregiver and physician are the people Somnia says it will notify.")
                                .foregroundStyle(Night.muted)
                            if let score = alarm.scorePeak {
                                Text(String(format: "Peak anomaly score %.2f", score))
                                    .font(.footnote)
                                    .foregroundStyle(Night.teal)
                            }
                        }
                    } else {
                        NightCard {
                            Text("No active alert")
                                .font(.title3.weight(.semibold))
                            Text("Avery has no alarm waiting to be turned off.")
                                .foregroundStyle(Night.muted)
                        }
                    }

                    Text("Recent anomalies")
                        .font(.headline)
                    if model.events.isEmpty {
                        Text("None saved yet.")
                            .foregroundStyle(Night.muted)
                    } else {
                        ForEach(model.events) { event in
                            NightCard {
                                Text(event.kind == "alarm" ? "Possible seizure-like event" : "Heart-rate observation")
                                    .font(.headline)
                                Text(event.reason)
                                    .foregroundStyle(Night.muted)
                                Text(event.alarmStatus.replacingOccurrences(of: "_", with: " "))
                                    .font(.footnote)
                                    .foregroundStyle(Night.teal)
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
