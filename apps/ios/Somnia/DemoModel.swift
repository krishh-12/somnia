import Foundation
import SwiftUI

@MainActor
@Observable
final class DemoModel {
    var token: String?
    var role = ""
    var displayName = ""
    var patientName = "Avery Quinn"
    var live: LiveSnapshot?
    var events: [DemoEvent] = []
    var logs: [NightLogEntry] = []
    var insights: NightInsights?
    var busy = false
    var status = ""
    var showWearable = false
    var presentedAlarm: DemoEvent?
    var alarmRaisedThisSession = false
    var confirmReset = false
    var showFeedback = false
    var feedbackEventId: UUID?

    var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "SomniaAPIBaseURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://149.28.253.209:8090")!
    }

    var isPatient: Bool { role == "patient" }

    var openAlarm: DemoEvent? {
        guard let event = live?.activeEvent, event.alarmStatus == "awaiting_ack" else { return nil }
        return event
    }

    var alarm: DemoEvent? {
        isPatient ? openAlarm : nil
    }

    private var api: SomniaAPI { SomniaAPI(baseURL: baseURL, token: token) }

    func enter(role: String) async {
        busy = true
        status = ""
        do {
            let session = try await SomniaAPI(baseURL: baseURL).enter(role: role)
            token = session.accessToken
            self.role = session.role
            displayName = session.displayName
            patientName = session.patientName
            presentedAlarm = nil
            alarmRaisedThisSession = false
            showFeedback = false
            feedbackEventId = nil
            try await reload()
        } catch SomniaAPIError.offline {
            status = "The iPhone cannot reach the somnia service at \(baseURL.host ?? "the server"). Start it, then try again."
        } catch SomniaAPIError.message(let text) {
            status = text
        } catch {
            status = "Sign-in failed."
        }
        busy = false
    }

    func reload() async throws {
        live = try await api.live()
        events = try await api.events()
        insights = try await api.insights()
        if let fetched = try? await api.logs() {
            logs = fetched
        } else {
            logs = NightLogEntry.compiled(from: events)
        }
    }

    func refresh() async {
        guard token != nil else { return }
        do {
            try await reload()
            status = ""
        } catch SomniaAPIError.offline {
            status = "The somnia service is unreachable."
        } catch SomniaAPIError.message(let text) {
            status = text
        } catch {
            status = "The latest readings could not be loaded."
        }
    }

    func run(caseName: String) async {
        guard isPatient else { return }
        busy = true
        status = ""
        var raised: DemoEvent?
        do {
            live = try await api.run(caseName: caseName)
            events = try await api.events()
            insights = try await api.insights()
            raised = alarm
        } catch SomniaAPIError.offline {
            status = "The test could not reach the server."
        } catch SomniaAPIError.message(let text) {
            status = text
        } catch {
            status = "The test did not finish."
        }
        busy = false
        if let raised {
            alarmRaisedThisSession = true
            presentedAlarm = raised
        }
    }

    func acknowledge() async {
        let eventId = presentedAlarm?.id ?? alarm?.id
        guard let eventId else { return }
        let coverWasOpen = presentedAlarm != nil
        busy = true
        do {
            _ = try await api.acknowledge(id: eventId)
            try await reload()
            alarmRaisedThisSession = false
            presentedAlarm = nil
            status = ""
            feedbackEventId = eventId
            if coverWasOpen {
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    showFeedback = true
                }
            } else {
                showFeedback = true
            }
        } catch SomniaAPIError.message(let text) {
            status = text
        } catch {
            status = "The alarm could not be turned off."
        }
        busy = false
    }

    func sendFeedback(label: String, note: String) async -> Bool {
        guard let feedbackEventId else { return false }
        busy = true
        status = ""
        let trimmed = String(note.prefix(280)).trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await api.feedback(id: feedbackEventId, label: label, note: trimmed)
            try await reload()
            showFeedback = false
            self.feedbackEventId = nil
            busy = false
            return true
        } catch SomniaAPIError.message(let text) {
            status = text
        } catch {
            status = "The note could not be saved."
        }
        busy = false
        return false
    }

    func resetData() async {
        guard isPatient else { return }
        busy = true
        status = ""
        do {
            live = try await api.reset()
            events = []
            logs = []
            insights = try await api.insights()
            alarmRaisedThisSession = false
            presentedAlarm = nil
            showFeedback = false
            feedbackEventId = nil
        } catch SomniaAPIError.message(let text) {
            status = text
        } catch {
            status = "The saved graph could not be cleared."
        }
        busy = false
    }

    func leave() {
        token = nil
        role = ""
        live = nil
        events = []
        logs = []
        status = ""
        presentedAlarm = nil
        alarmRaisedThisSession = false
    }
}
