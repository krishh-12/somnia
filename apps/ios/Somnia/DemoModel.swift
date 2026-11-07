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
    var busy = false
    var status = ""
    var showWearable = false
    var showAlarmNotice = false
    var showAlarmScreen = false
    var confirmReset = false

    var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "SomniaAPIBaseURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:8090")!
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
            if role != "patient" {
                showAlarmNotice = false
                showAlarmScreen = false
            }
            try await reload()
        } catch SomniaAPIError.offline {
            status = "The iPhone cannot reach the Somnia service at \(baseURL.host ?? "the server"). Start it, then try again."
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
    }

    func refresh() async {
        guard token != nil else { return }
        do {
            try await reload()
            status = ""
        } catch SomniaAPIError.offline {
            status = "The Somnia service is unreachable."
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
        do {
            live = try await api.run(caseName: caseName)
            events = try await api.events()
            if alarm != nil {
                showAlarmNotice = true
                showAlarmScreen = true
            }
        } catch SomniaAPIError.offline {
            status = "The test could not reach the server."
        } catch SomniaAPIError.message(let text) {
            status = text
        } catch {
            status = "The test did not finish."
        }
        busy = false
    }

    func acknowledge() async {
        guard let alarm else { return }
        busy = true
        do {
            _ = try await api.acknowledge(id: alarm.id)
            try await reload()
            showAlarmNotice = false
            showAlarmScreen = false
        } catch SomniaAPIError.message(let text) {
            status = text
        } catch {
            status = "The alarm could not be turned off."
        }
        busy = false
    }

    func resetData() async {
        guard isPatient else { return }
        busy = true
        status = ""
        do {
            live = try await api.reset()
            events = []
            showAlarmNotice = false
            showAlarmScreen = false
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
        status = ""
    }
}
