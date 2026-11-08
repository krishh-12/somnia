import Charts
import SwiftUI

struct PatientHome: View {
    @Bindable var model: DemoModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                            Text("If you do not say you are okay, Somnia will notify your caregiver and physician.")
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
                        Text("Across is time of night. Up is stronger movement.")
                            .font(.somnia(.footnote))
                            .foregroundStyle(Night.muted)
                        if readings.isEmpty {
                            Text("No readings yet")
                                .foregroundStyle(Night.muted)
                                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                        } else {
                            Chart(readings) { point in
                                if let motion = point.motionRms {
                                    LineMark(
                                        x: .value("Time of night", point.at),
                                        y: .value("Motion (m/s²)", motion),
                                        series: .value("Run", point.run)
                                    )
                                    .foregroundStyle(Night.pink)
                                    .interpolationMethod(.catmullRom)
                                    if motion >= 1 {
                                        PointMark(
                                            x: .value("Time of night", point.at),
                                            y: .value("Motion (m/s²)", motion)
                                        )
                                        .foregroundStyle(Night.danger)
                                        .symbolSize(40)
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
                            Text("\(readings.count) saved samples. A new test extends this graph.")
                                .font(.somnia(.footnote))
                                .foregroundStyle(Night.muted)
                        }
                    }

                    Button {
                        Task { await model.run(caseName: "sustained_motor_event") }
                    } label: {
                        Text(model.busy ? "Scoring…" : "Run anomaly")
                            .font(.somnia(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Night.pink)
                    .disabled(model.busy)

                    Button { model.confirmReset = true } label: {
                        Text("Reset data")
                            .font(.somnia(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(Night.indigo)
                    .disabled(model.busy || readings.isEmpty)

                    Button {
                        model.showWearable = true
                    } label: {
                        Label("Attach wearable", systemImage: "applewatch")
                            .font(.somnia(.headline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(Night.indigo)

                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.somnia(.footnote))
                            .foregroundStyle(Night.danger)
                    }
                    Text("Prototype only. This does not diagnose seizures. The alarm stays on this screen.")
                        .font(.somnia(.footnote))
                        .foregroundStyle(Night.muted)
                }
                .padding(20)
            }
            .background(Night.background)
            .navigationTitle("Somnia")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Reset the saved graph?", isPresented: $model.confirmReset, titleVisibility: .visible) {
                Button("Reset data", role: .destructive) { Task { await model.resetData() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the compounded readings and alarms on the server.")
            }
            .sheet(isPresented: $model.showWearable) {
                WearableSheet()
            }
        }
    }

    private var readings: [ReadingPoint] { model.live?.readings ?? [] }
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
                Button("Keep the simulated test") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Night.pink)
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
