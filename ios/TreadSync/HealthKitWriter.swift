import Foundation
import HealthKit

/// Saves a finished WorkoutSession to Apple Health as an indoor walk or run.
final class HealthKitWriter {
    private let store = HKHealthStore()
    private let distanceType = HKQuantityType(.distanceWalkingRunning)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let bodyMassType = HKQuantityType(.bodyMass)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(
            toShare: [HKObjectType.workoutType(), distanceType, energyType],
            read: [bodyMassType]
        )
    }

    /// Most recent body weight from Health, used for the calorie estimate.
    func latestBodyMassKg() async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMassType)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let results = try? await descriptor.result(for: store)
        return results?.first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    @discardableResult
    func save(_ session: WorkoutSession, activity: HKWorkoutActivityType) async throws -> HKWorkout? {
        guard let end = session.endDate else { return nil }

        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: session.startDate)

        var samples: [HKSample] = []
        for iv in session.intervals() where iv.end > iv.start {
            if iv.distanceM > 0 {
                samples.append(HKQuantitySample(
                    type: distanceType,
                    quantity: HKQuantity(unit: .meter(), doubleValue: iv.distanceM),
                    start: iv.start, end: iv.end))
            }
            if iv.activeKcal > 0 {
                samples.append(HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: iv.activeKcal),
                    start: iv.start, end: iv.end))
            }
        }
        if !samples.isEmpty { try await builder.addSamples(samples) }

        var metadata: [String: Any] = [HKMetadataKeyIndoorWorkout: true]
        if session.elevationGainM > 0.5 {
            metadata[HKMetadataKeyElevationAscended] =
                HKQuantity(unit: .meter(), doubleValue: session.elevationGainM)
        }
        try await builder.addMetadata(metadata)

        try await builder.endCollection(at: end)
        return try await builder.finishWorkout()
    }
}
