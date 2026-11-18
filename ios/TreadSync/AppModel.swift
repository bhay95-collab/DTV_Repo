import Foundation
import HealthKit
import Observation

@Observable
final class AppModel {
    enum ActivityChoice: String, CaseIterable, Identifiable {
        case auto = "Auto", walk = "Walk", run = "Run"
        var id: String { rawValue }
    }

    let treadmill = TreadmillManager()
    @ObservationIgnored let health = HealthKitWriter()

    private(set) var session: WorkoutSession?
    var activityChoice: ActivityChoice = .auto
    private(set) var message: String?
    private(set) var isSaving = false
    private var bodyMassKg = 75.0

    var isRecording: Bool { session != nil && session?.isFinished == false }

    init() {
        treadmill.onData = { [weak self] data, date in
            self?.session?.ingest(data, at: date)
        }
        treadmill.connect()
        Task { await prepareHealth() }
    }

    private func prepareHealth() async {
        guard health.isAvailable else { message = "Apple Health isn't available on this device."; return }
        do {
            try await health.requestAuthorization()
            if let kg = await health.latestBodyMassKg() { bodyMassKg = kg }
        } catch {
            message = "Health permission error: \(error.localizedDescription)"
        }
    }

    func start() {
        message = nil
        session = WorkoutSession(startDate: Date(), bodyMassKg: bodyMassKg)
    }

    func discard() {
        session = nil
        message = "Workout discarded."
    }

    func finishAndSave() {
        guard var s = session, !isSaving else { return }
        s.finish(at: Date())  // no-op if already finished (i.e. retrying a failed save)
        session = s
        let activity = resolvedActivity(for: s)
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await health.save(s, activity: activity)
                let km = String(format: "%.2f", s.distanceM / 1000)
                message = "Saved \(km) km to Apple Health."
                session = nil
            } catch {
                // Keep the finished session so the user can retry the save.
                message = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func resolvedActivity(for s: WorkoutSession) -> HKWorkoutActivityType {
        switch activityChoice {
        case .walk: return .walking
        case .run: return .running
        case .auto: return s.averageSpeedKmh >= 8 ? .running : .walking
        }
    }
}
