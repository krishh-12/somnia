import Charts
import SwiftUI

struct PatientHome: View {
    @Bindable var model: DemoModel

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 0).id("night-top")
                    NightCard {
                        HStack(alignment: .center, spacing: 14) {
                            SomniaLogo(draw: 1, settled: 1)
                                .frame(width: 84, height: 84)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.live?.monitoringTitle ?? "Not monitoring")
                                    .font(.somnia(.title, weight: .semibold))
                                Text(model.patientName)
                                    .foregroundStyle(Night.pink)
                            }
                        }
                        Text(model.live?.detail ?? "The graph is empty until a test is scored.")
                            .foregroundStyle(Night.muted)
                            .padding(.top, 6)
                    }

                    if model.alarmRaisedThisSession, let alarm = model.alarm, model.presentedAlarm == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Alarm is still on")
                                .font(.somnia(.headline, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("If you do not say you are okay, somnia will notify your caregiver and physician.")
                                .foregroundStyle(.white.opacity(0.85))
                            Button {
                                Task { await model.acknowledge() }
                            } label: {
                                Text("I'm okay")
                                    .font(.somnia(.headline, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.45, green: 0.02, blue: 0.05))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            Button("Show alarm") { model.presentedAlarm = alarm }
                                .foregroundStyle(.white)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.62, green: 0.05, blue: 0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    HStack(alignment: .top, spacing: 12) {
                        metric("Heart rate", value: heartText, unit: heartUnit)
                        metric("Motion", value: motionText, unit: motionUnit)
                    }

                    NightCard {
                        Text("Movement through the night")
                            .font(.somnia(.headline, weight: .semibold))
                        Text("Across is time of night. Up is stronger movement. The dashed line is sustained strong movement.")
                            .font(.somnia(.footnote))
                            .foregroundStyle(Night.muted)
                        if readings.isEmpty {
                            Text("No readings yet")
                                .foregroundStyle(Night.muted)
                                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                        } else {
                            Chart {
                                RuleMark(y: .value("Sustained movement", motionBar))
                                    .foregroundStyle(Night.danger.opacity(0.85))
                                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                ForEach(readings) { point in
                                    if let motion = point.motionRms {
                                        LineMark(
                                            x: .value("Time of night", point.at),
                                            y: .value("Motion (m/s²)", motion),
                                            series: .value("Run", point.run)
                                        )
                                        .foregroundStyle(Night.pink)
                                        .interpolationMethod(.catmullRom)
                                        if motion >= motionBar, (point.heartRateBpm ?? 0) >= heartBar {
                                            PointMark(
                                                x: .value("Time of night", point.at),
                                                y: .value("Motion (m/s²)", motion)
                                            )
                                            .foregroundStyle(Night.danger)
                                            .symbolSize(40)
                                        }
                                    }
                                }
                            }
                            .chartXAxisLabel("Time of night")
                            .chartYAxisLabel("Motion (m/s²)")
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let date = value.as(Date.self) {
                                            Text(date, format: .dateTime.hour().minute())
                                        }
                                    }
                                }
                            }
                            .chartYAxis { AxisMarks(position: .leading) }
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                            ReadMore(text: "\(readings.count) saved samples. A new test extends this graph. Every third one is the seizure-like pattern. Red points also need heart rate at least 20% above baseline, the low end of the 20–70% rise used in cardiac seizure detection. A 2013 wrist-accelerometer study flagged convulsive seizures when strong movement kept going. A turn stays under the line. \(barNote)")
                        }
                    }

                    NightCard {
                        Text("Heart-rate variability")
                            .font(.somnia(.headline, weight: .semibold))
                        Text("Across is time of night. Up is beat-to-beat variation. It falls at the seizure-like pattern, while heart rate rises.")
                            .font(.somnia(.footnote))
                            .foregroundStyle(Night.muted)
                        if readings.isEmpty {
                            Text("No readings yet")
                                .foregroundStyle(Night.muted)
                                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                        } else {
                            Chart {
                                if let line = model.live?.hrvBar {
                                    RuleMark(y: .value("Reduced variability", line))
                                        .foregroundStyle(Night.danger.opacity(0.85))
                                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                }
                                ForEach(readings) { point in
                                    if let variability = point.hrvRmssd {
                                        LineMark(
                                            x: .value("Time of night", point.at),
                                            y: .value("Variability (ms)", variability),
                                            series: .value("Run", point.run)
                                        )
                                        .foregroundStyle(Night.pink)
                                        .interpolationMethod(.catmullRom)
                                        if (point.motionRms ?? 0) >= motionBar, (point.heartRateBpm ?? 0) >= heartBar {
                                            PointMark(
                                                x: .value("Time of night", point.at),
                                                y: .value("Variability (ms)", variability)
                                            )
                                            .foregroundStyle(Night.danger)
                                            .symbolSize(40)
                                        }
                                    }
                                }
                            }
                            .chartXAxisLabel("Time of night")
                            .chartYAxisLabel("RMSSD (ms)")
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let date = value.as(Date.self) {
                                            Text(date, format: .dateTime.hour().minute())
                                        }
                                    }
                                }
                            }
                            .chartYAxis { AxisMarks(position: .leading) }
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                            ReadMore(text: "Red points are the seizure-like pattern: movement stays strong and heart rate is up, while variability drops. A turn keeps variability near the resting range. Wearable studies of convulsive seizures often report a heart-rate rise together with a fall in variability, measured as RMSSD (Jeppesen et al., Epilepsia, 2015). The dashed line is the compiled variability estimate. This graph is synthetic. \(barNote)")
                        }
                    }

                    Button {
                        Task { await model.run(caseName: nextCase) }
                    } label: {
                        Text(model.busy ? "Scoring…" : "Run anomaly")
                            .font(.somnia(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(NeuButtonStyle(prominent: true))
                    .disabled(model.busy)

                    Button { model.confirmReset = true } label: {
                        Text("Reset data")
                            .font(.somnia(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(NeuButtonStyle())
                    .disabled(model.busy || readings.isEmpty)
                    .opacity(model.busy || readings.isEmpty ? 0.4 : 1)

                    Button {
                        model.showWearable = true
                    } label: {
                        Label("Attach wearable", systemImage: "applewatch")
                            .font(.somnia(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(NeuButtonStyle())

                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.somnia(.footnote))
                            .foregroundStyle(Night.danger)
                    }
                }
                .padding(20)
            }
            .onChange(of: readings.isEmpty) { _, empty in
                if empty {
                    withAnimation(Night.reveal) {
                        proxy.scrollTo("night-top", anchor: .top)
                    }
                }
            }
            }
            .background(Night.background)
            .navigationTitle("somnia")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Reset the saved night?", isPresented: $model.confirmReset) {
                Button("Reset data", role: .destructive) { Task { await model.resetData() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the graph, the alarms, and the log.")
            }
            .sheet(isPresented: $model.showWearable) {
                WearableSheet()
            }
        }
    }

    private var readings: [ReadingPoint] { model.live?.readings ?? [] }
    private var motionBar: Double { model.live?.motionBar ?? 3.5 }
    private var heartBar: Double { model.live?.heartRateBar ?? (model.live?.baselineHr ?? 62) * 1.2 }
    private var barNote: String {
        model.live?.barNote ?? "These lines are estimates, not a published cutoff. This is not a diagnosis."
    }

    /// The 3rd, 6th, and 9th saved runs are the seizure-like pattern. The others rotate.
    private var nextCase: String {
        let click = Set(readings.map(\.run)).count + 1
        if click % 3 == 0 { return "sustained_motor_event" }
        let varied = ["normal_sleep", "turn_in_bed", "hr_only"]
        let slot = click - (click / 3) - 1
        return varied[slot % varied.count]
    }
    private var latest: ReadingPoint? { readings.last }

    private var heartText: String {
        guard let value = latest?.heartRateBpm else { return "—" }
        return String(format: "%.0f", value)
    }

    private var heartUnit: String { latest?.heartRateBpm == nil ? "No sample" : "bpm" }

    private var motionText: String {
        guard let value = latest?.motionRms else { return "—" }
        return String(format: "%.2f", value)
    }

    private var motionUnit: String { latest?.motionRms == nil ? "No sample" : "m/s²" }

    private func metric(_ title: String, value: String, unit: String) -> some View {
        NightCard {
            Text(title)
                .font(.somnia(.subheadline))
                .foregroundStyle(Night.muted)
            Text(value)
                .font(.somnia(size: 34, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 6)
            Text(unit)
                .font(.somnia(.footnote))
                .foregroundStyle(Night.pink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReadMore: View {
    var text: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Night.reveal) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(open ? "Read less" : "Read more")
                        .font(.somnia(.footnote, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.somnia(.caption, weight: .semibold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .foregroundStyle(Night.pink)
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the note" : "Shows the note")
            if open {
                Text(text)
                    .font(.somnia(.footnote))
                    .foregroundStyle(Night.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .neuInset()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .offset(y: -6)),
                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    ))
            }
        }
        .animation(Night.reveal, value: open)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: open) { _, opened in
            opened
        }
    }
}

struct WearableSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Apple Watch")
                    .font(.somnia(.title2, weight: .semibold))
                Text("Wearable import not connected")
                    .font(.somnia(.headline, weight: .semibold))
                    .foregroundStyle(Night.pink)
                Text("Nothing is paired. A later watch can send readings through this same server. The graph keeps using the simulated test until then.")
                    .foregroundStyle(Night.muted)
                Button { dismiss() } label: {
                    Text("Keep the simulated test")
                        .font(.somnia(.headline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(NeuButtonStyle(prominent: true))
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Night.background)
            .navigationTitle("Attach wearable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
