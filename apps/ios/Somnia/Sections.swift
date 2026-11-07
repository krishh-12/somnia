import Charts
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
                                .font(.headline)
                            Text(event.reason)
                                .font(.subheadline)
                                .foregroundStyle(Night.muted)
                            Text(event.synthetic ? "Synthetic · \(event.alarmStatus.replacingOccurrences(of: "_", with: " "))" : event.alarmStatus)
                                .font(.footnote)
                                .foregroundStyle(Night.teal)
                            if let score = event.scorePeak {
                                Text(String(format: "Peak anomaly score %.2f", score))
                                    .font(.footnote)
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
                    NightCard {
                        Text("Anomaly score")
                            .font(.headline)
                        Text("Isolation Forest on this patient’s normal baseline. A higher score is more unusual. It is not a seizure probability.")
                            .font(.footnote)
                            .foregroundStyle(Night.muted)
                        if let threshold = model.live?.modelThreshold {
                            Text(String(format: "Server threshold %.2f · baseline heart rate %.0f", threshold, model.live?.baselineHr ?? 0))
                                .font(.footnote)
                                .foregroundStyle(Night.teal)
                                .padding(.top, 6)
                        }
                    }
                    NightCard {
                        if let readings = model.live?.readings, readings.contains(where: { $0.score != nil }) {
                            Chart(readings) { point in
                                if let score = point.score {
                                    AreaMark(
                                        x: .value("Second", point.sequence),
                                        y: .value("Score", score)
                                    )
                                    .foregroundStyle(Night.indigo.opacity(0.35))
                                    LineMark(
                                        x: .value("Second", point.sequence),
                                        y: .value("Score", score)
                                    )
                                    .foregroundStyle(Night.indigo)
                                }
                            }
                            .frame(height: 180)
                        } else {
                            Text("No scored windows yet. Run a test from Home.")
                                .foregroundStyle(Night.muted)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                        }
                    }
                    NightCard {
                        Text("Plan and physician review")
                            .font(.headline)
                        Text("Not in this version. The next section saves a caregiver escalation and a physician review on these same events.")
                            .foregroundStyle(Night.muted)
                    }
                }
                .padding(20)
            }
            .background(Night.background)
            .navigationTitle("Insights")
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
                            .font(.title2.weight(.semibold))
                        Text(model.role.capitalized)
                            .foregroundStyle(Night.teal)
                        Text(model.live?.sleepWindow ?? "Sleep window loads from the server")
                            .font(.footnote)
                            .foregroundStyle(Night.muted)
                            .padding(.top, 6)
                    }
                    NightCard {
                        Text("Demo view")
                            .font(.headline)
                        Text("Switching view does not create another patient.")
                            .font(.footnote)
                            .foregroundStyle(Night.muted)
                        viewButton("Patient", role: "patient")
                        viewButton("Caregiver", role: "caregiver")
                        viewButton("Physician", role: "physician")
                    }
                    Button {
                        model.showWearable = true
                    } label: {
                        Label(model.live?.wearableLabel ?? "Wearable import not connected", systemImage: "applewatch")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(Night.indigo)
                    Text("Somnia is a prototype. It does not diagnose seizures, predict events, or replace medical care. This alarm is on-screen only and is not a locked-phone alarm.")
                        .font(.footnote)
                        .foregroundStyle(Night.muted)
                    Button("Leave demo", role: .destructive) {
                        model.leave()
                    }
                }
                .padding(20)
            }
            .background(Night.background)
            .navigationTitle("Profile")
            .sheet(isPresented: $model.showWearable) {
                WearableSheet()
            }
        }
    }

    private func viewButton(_ title: String, role: String) -> some View {
        Button(title) {
            Task { await model.enter(role: role) }
        }
        .buttonStyle(.bordered)
        .tint(model.role == role ? Night.teal : Night.indigo)
        .padding(.top, 6)
    }
}

struct AlarmView: View {
    let event: DemoEvent
    let busy: Bool
    let acknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Possible seizure-like event")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
            Text(event.reason)
                .font(.title3)
            if let score = event.scorePeak {
                Text(String(format: "Peak anomaly score %.2f", score))
                    .foregroundStyle(Night.teal)
            }
            Text("Synthetic test. Acknowledging means you are safe. It does not label the event as not a seizure.")
                .foregroundStyle(Night.muted)
            if let deadline = event.deadlineAt {
                Text("Server deadline \(deadline.formatted(date: .omitted, time: .standard))")
                    .font(.footnote)
                    .foregroundStyle(Night.muted)
            }
            Spacer()
            Button(busy ? "Saving…" : "I’m safe") {
                acknowledge()
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .buttonStyle(.borderedProminent)
            .tint(Night.teal)
            .disabled(busy)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Night.background)
    }
}
