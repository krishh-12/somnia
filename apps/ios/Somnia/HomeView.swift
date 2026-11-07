import Charts
import SwiftUI

struct HomeView: View {
    @Bindable var model: DemoModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NightCard {
                        Text(model.live?.monitoringTitle ?? "Not monitoring")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                        Text(model.live?.detail ?? "Run a synthetic test. No wearable is connected.")
                            .foregroundStyle(Night.muted)
                            .padding(.top, 4)
                        Text(model.patientName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Night.teal)
                            .padding(.top, 8)
                    }
                    HStack(spacing: 12) {
                        metric("Heart rate", value: heartText, unit: heartUnit)
                        metric("Motion", value: motionText, unit: "m/s²")
                    }
                    NightCard {
                        Text("Live trend")
                            .font(.headline)
                        Text("Server samples from the latest synthetic test.")
                            .font(.footnote)
                            .foregroundStyle(Night.muted)
                        if let readings = model.live?.readings, !readings.isEmpty {
                            Chart(readings) { point in
                                if let motion = point.motionRms {
                                    LineMark(
                                        x: .value("Second", point.sequence),
                                        y: .value("Motion", motion)
                                    )
                                    .foregroundStyle(Night.teal)
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                            .frame(height: 140)
                            .chartYAxis {
                                AxisMarks(position: .leading)
                            }
                        } else {
                            Text("No samples yet")
                                .foregroundStyle(Night.muted)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                        }
                    }
                    if model.isPatient {
                        Text("Synthetic tests")
                            .font(.headline)
                            .padding(.top, 4)
                        testButton("Seizure-like event", caseName: "sustained_motor_event", primary: true)
                        testButton("Normal sleep", caseName: "normal_sleep", primary: false)
                        testButton("Turn in bed", caseName: "turn_in_bed", primary: false)
                        testButton("Heart-rate change", caseName: "hr_only", primary: false)
                    } else {
                        NightCard {
                            Text("This \(model.role) view watches Avery’s saved server record. Switch to Patient to run a test.")
                                .foregroundStyle(Night.muted)
                        }
                    }
                    Button {
                        model.showWearable = true
                    } label: {
                        Label("Attach wearable", systemImage: "applewatch")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(Night.indigo)
                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.footnote)
                            .foregroundStyle(Night.danger)
                    }
                }
                .padding(20)
            }
            .background(Night.background)
            .navigationTitle("Tonight")
            .toolbarBackground(Night.background, for: .navigationBar)
            .sheet(isPresented: $model.showWearable) {
                WearableSheet()
            }
        }
    }

    private var latest: ReadingPoint? { model.live?.readings.last }

    private var heartText: String {
        guard let value = latest?.heartRateBpm else { return "—" }
        return String(format: "%.0f", value)
    }

    private var heartUnit: String { latest?.heartRateBpm == nil ? "waiting" : "bpm" }

    private var motionText: String {
        guard let value = latest?.motionRms else { return "—" }
        return String(format: "%.2f", value)
    }

    private func metric(_ title: String, value: String, unit: String) -> some View {
        NightCard {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Night.muted)
            Text(value)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .padding(.top, 6)
            Text(unit)
                .font(.footnote)
                .foregroundStyle(Night.teal)
        }
    }

    private func testButton(_ title: String, caseName: String, primary: Bool) -> some View {
        Button {
            Task { await model.run(caseName: caseName) }
        } label: {
            Text(model.busy ? "Scoring on the server…" : title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(primary ? Night.teal : Night.indigo)
        .disabled(model.busy)
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
                Text("A later Apple Watch, HealthKit import, or Bluetooth device can send heart rate and motion through this same server. Nothing is paired now. Imported Health history would be stored samples, not a live motion stream.")
                    .foregroundStyle(Night.muted)
                Button("Keep using the simulated wearable") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Night.teal)
                Spacer()
            }
            .padding(24)
            .background(Night.background)
            .navigationTitle("Attach wearable")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
