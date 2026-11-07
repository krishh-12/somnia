import SwiftUI

struct RootView: View {
    @Bindable var model: DemoModel

    var body: some View {
        Group {
            if model.token == nil {
                WelcomeView(model: model)
            } else {
                MainTabView(model: model)
            }
        }
        .background(Night.background.ignoresSafeArea())
        .fullScreenCover(item: alarmBinding) { event in
            AlarmView(event: event, busy: model.busy) {
                Task { await model.acknowledge() }
            }
        }
    }

    private var alarmBinding: Binding<DemoEvent?> {
        Binding(
            get: { model.alarm },
            set: { _ in }
        )
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
            roleButton("Patient", role: "patient", tint: Night.teal)
            roleButton("Caregiver", role: "caregiver", tint: Night.indigo)
            roleButton("Physician", role: "physician", tint: Night.indigo)
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

struct MainTabView: View {
    @Bindable var model: DemoModel

    var body: some View {
        TabView {
            HomeView(model: model)
                .tabItem { Label("Home", systemImage: "moon.stars.fill") }
            HistoryView(model: model)
                .tabItem { Label("History", systemImage: "clock.fill") }
            InsightsView(model: model)
                .tabItem { Label("Insights", systemImage: "waveform.path.ecg") }
            ProfileView(model: model)
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
        .tint(Night.teal)
    }
}
