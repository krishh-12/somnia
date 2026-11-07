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
                    if let insights = model.insights {
                        HStack(alignment: .top, spacing: 12) {
                            countCard("Tonight", value: insights.tonightCount, caption: "anomalies")
                            countCard("This week", value: insights.weekCount, caption: "anomalies")
                        }
                        NightCard {
                            Text("Most common time")
                                .font(.subheadline)
                                .foregroundStyle(Night.muted)
                            Text(insights.commonTime ?? "Not enough yet")
                                .font(.title2.weight(.semibold))
                            Text(commonDetail(insights))
                                .font(.footnote)
                                .foregroundStyle(Night.muted)
                        }
                        NightCard {
                            Text("What may be going on")
                                .font(.headline)
                            Text(insights.cause)
                                .foregroundStyle(Night.muted)
                        }
                        NightCard {
                            Text("What to do")
                                .font(.headline)
                            Text(insights.action)
                                .foregroundStyle(Night.muted)
                        }
                        if insights.narration == "vultr" {
                            Text("This wording comes from a Vultr model. The counts and the anomaly score do not. This is not a diagnosis.")
                                .font(.footnote)
                                .foregroundStyle(Night.pink)
                        }
                        if insights.synthetic {
                            Text("These counts come from saved synthetic nights. They are not a diagnosis.")
                                .font(.footnote)
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
                .font(.subheadline)
                .foregroundStyle(Night.muted)
            Text("\(value)")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Night.teal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commonDetail(_ insights: NightInsights) -> String {
        guard insights.hasData, insights.commonTimeCount > 0 else {
            return "This fills in after the server saves an anomaly."
        }
        let noun = insights.commonTimeCount == 1 ? "anomaly" : "anomalies"
        return "\(insights.commonTimeCount) \(noun) this week started in that hour."
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
                    Button {
                        Task { await model.enter(role: "caregiver") }
                    } label: {
                        Text("Switch to caregiver")
                            .font(.headline)
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
                    Text("Somnia is a prototype. It does not diagnose seizures, predict events, or replace medical care. This alarm is on-screen only and is not a locked-phone alarm.")
                        .font(.footnote)
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

struct AlarmView: View {
    let event: DemoEvent
    let busy: Bool
    let acknowledge: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Alarm")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
            Text("Possible seizure-like event")
                .font(.title2)
            Text("If you do not turn this off, Somnia will notify your caregiver and physician.")
                .font(.title3)
            Text(event.reason)
                .foregroundStyle(Night.muted)
            Text("Turning this off means you are safe. It does not decide whether the pattern was a seizure.")
                .font(.footnote)
                .foregroundStyle(Night.muted)
            Spacer()
            Button(action: acknowledge) {
                Text(busy ? "Saving…" : "Turn off")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(Night.teal)
            .disabled(busy)
            Button(action: onDismiss) {
                Text("Not now")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .disabled(busy)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Night.background)
    }
}
