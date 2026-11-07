import Charts
import SwiftUI

struct PatientHome: View {
    @Bindable var model: DemoModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NightCard {
                        Text(model.live?.monitoringTitle ?? "Not monitoring")
                            .font(.title.weight(.semibold))
                        Text(model.patientName)
                            .foregroundStyle(Night.teal)
                            .padding(.top, 2)
                        Text(model.live?.detail ?? "The graph is empty until a test is scored.")
                            .foregroundStyle(Night.muted)
                            .padding(.top, 6)
                    }

                    if model.alarm != nil && !model.showAlarmScreen {
                        NightCard {
                            Text("Alarm is still on")
                                .font(.headline)
                            Text("If you do not turn this off, Somnia will notify your caregiver and physician.")
                                .foregroundStyle(Night.muted)
                                .padding(.top, 4)
                            Button("Turn off") { Task { await model.acknowledge() } }
                                .buttonStyle(.borderedProminent)
                                .tint(Night.danger)
                                .padding(.top, 8)
                            Button("Show alarm") { model.showAlarmScreen = true }
                                .padding(.top, 4)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        metric("Heart rate", value: heartText, unit: heartUnit)
                        metric("Motion", value: motionText, unit: motionUnit)
                    }

                    NightCard {
                        Text("Graph")
                            .font(.headline)
                        if readings.isEmpty {
                            Text("No readings yet")
                                .foregroundStyle(Night.muted)
                                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                        } else {
                            Chart(readings) { point in
                                if let motion = point.motionRms {
                                    LineMark(
                                        x: .value("Sample", point.index),
                                        y: .value("Motion", motion),
                                        series: .value("Run", point.run)
                                    )
                                    .foregroundStyle(Night.teal)
                                    .interpolationMethod(.catmullRom)
                                    if motion >= 1 {
                                        PointMark(
                                            x: .value("Sample", point.index),
                                            y: .value("Motion", motion)
                                        )
                                        .foregroundStyle(Night.danger)
                                        .symbolSize(40)
                                    }
                                }
                            }
                            .chartYAxis { AxisMarks(position: .leading) }
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                            .frame(maxWidth: .infinity)
                            .frame(height: 190)
                            Text("\(readings.count) saved samples. A new test extends this graph.")
                                .font(.footnote)
                                .foregroundStyle(Night.muted)
                        }
                    }

                    Button {
                        Task { await model.run(caseName: "sustained_motor_event") }
                    } label: {
                        Text(model.busy ? "Scoring…" : "Run anomaly")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Night.teal)
                    .disabled(model.busy)

                    Button { model.confirmReset = true } label: {
                        Text("Reset data")
                            .font(.headline)
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
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(Night.indigo)

                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.footnote)
                            .foregroundStyle(Night.danger)
                    }
                    Text("Prototype only. This does not diagnose seizures. The alarm stays on this screen.")
                        .font(.footnote)
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
                .font(.subheadline)
                .foregroundStyle(Night.muted)
            Text(value)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 6)
            Text(unit)
                .font(.footnote)
                .foregroundStyle(Night.teal)
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
                    .font(.title2.weight(.semibold))
                Text("Wearable import not connected")
                    .font(.headline)
                    .foregroundStyle(Night.teal)
                Text("Nothing is paired. A later watch can send readings through this same server. The graph keeps using the simulated test until then.")
                    .foregroundStyle(Night.muted)
                Button("Keep the simulated test") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(Night.teal)
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
