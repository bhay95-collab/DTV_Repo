import Foundation

/// Accumulates treadmill readings into one workout.
/// Plain value type with no Bluetooth or HealthKit code, so it can be unit tested.
struct WorkoutSession {
    struct Point: Equatable {
        let date: Date
        let distanceM: Double   // cumulative
        let activeKcal: Double  // cumulative
    }

    struct Interval: Equatable {
        let start: Date
        let end: Date
        let distanceM: Double
        let activeKcal: Double
    }

    let startDate: Date
    private(set) var endDate: Date?
    private(set) var distanceM = 0.0
    private(set) var elevationGainM = 0.0
    private(set) var activeKcal = 0.0
    private(set) var maxSpeedKmh = 0.0
    private(set) var points: [Point]
    var bodyMassKg: Double
    /// Incline set by hand on the treadmill (it can't report it). Can change mid-workout;
    /// applies to readings from then on. Ignored if the treadmill reports a non-zero incline.
    var manualInclinePercent: Double

    // Distance bookkeeping for the treadmill's own odometer.
    private var baselineM: Double?
    private var resetOffsetM = 0.0
    private var lastRawDistanceM: Double?
    private var lastReadingDate: Date?

    /// Gap longer than this between readings (e.g. Bluetooth dropout) is not integrated.
    static let maxIntegrationGap: TimeInterval = 5
    /// Odometer going backwards by more than this is treated as the treadmill resetting.
    static let resetThresholdM = 10.0

    init(startDate: Date, bodyMassKg: Double = 75, manualInclinePercent: Double = 0) {
        self.startDate = startDate
        self.bodyMassKg = bodyMassKg
        self.manualInclinePercent = manualInclinePercent
        self.points = [Point(date: startDate, distanceM: 0, activeKcal: 0)]
    }

    var isFinished: Bool { endDate != nil }

    func duration(now: Date = Date()) -> TimeInterval {
        (endDate ?? now).timeIntervalSince(startDate)
    }

    mutating func ingest(_ d: TreadmillData, at now: Date) {
        guard endDate == nil, now >= startDate else { return }
        let speed = max(0, d.speedKmh ?? 0)
        let dt = lastReadingDate.map { now.timeIntervalSince($0) } ?? 0
        let usableDt = (dt > 0 && dt <= Self.maxIntegrationGap) ? dt : 0
        lastReadingDate = now

        var newDistance = distanceM
        if let raw = d.totalDistanceM {
            if baselineM == nil {
                // Belt stopped: whatever the odometer shows is left over from an
                // earlier session, so ignore it. Belt moving: the walk is already
                // under way, so count it.
                baselineM = speed > 0 ? 0 : raw
                lastRawDistanceM = raw
            }
            if let last = lastRawDistanceM, raw + Self.resetThresholdM < last {
                resetOffsetM += last
            }
            lastRawDistanceM = raw
            newDistance = max(distanceM, resetOffsetM + raw - (baselineM ?? 0))
        } else {
            // Treadmill isn't reporting distance: integrate speed instead.
            newDistance = distanceM + speed / 3.6 * usableDt
        }

        let delta = newDistance - distanceM
        distanceM = newDistance
        let reportedIncline = d.inclinePercent ?? 0
        let grade = max(0, (reportedIncline != 0 ? reportedIncline : manualInclinePercent) / 100)
        elevationGainM += delta * grade
        activeKcal += Self.activeKcalPerMinute(speedKmh: speed, grade: grade, massKg: bodyMassKg) * usableDt / 60
        maxSpeedKmh = max(maxSpeedKmh, speed)

        if let last = points.last, now.timeIntervalSince(last.date) >= 1 {
            points.append(Point(date: now, distanceM: distanceM, activeKcal: activeKcal))
        }
    }

    mutating func finish(at end: Date) {
        guard endDate == nil else { return }
        endDate = end
        if let last = points.last, last.date < end {
            points.append(Point(date: end, distanceM: distanceM, activeKcal: activeKcal))
        }
    }

    /// Average speed over the whole workout, km/h.
    var averageSpeedKmh: Double {
        let d = duration(now: endDate ?? Date())
        return d > 0 ? distanceM / d * 3.6 : 0
    }

    /// Splits the workout into chunks of about `bucket` seconds for writing to Apple Health.
    func intervals(bucket: TimeInterval = 60) -> [Interval] {
        guard var windowStart = points.first else { return [] }
        var result: [Interval] = []
        for (i, p) in points.enumerated().dropFirst() {
            let isLast = i == points.count - 1
            if p.date.timeIntervalSince(windowStart.date) >= bucket || isLast {
                result.append(Interval(
                    start: windowStart.date,
                    end: p.date,
                    distanceM: p.distanceM - windowStart.distanceM,
                    activeKcal: p.activeKcal - windowStart.activeKcal
                ))
                windowStart = p
            }
        }
        return result
    }

    /// Active (above resting) energy from the ACSM metabolic equations.
    /// Cheap treadmills' own calorie numbers are unreliable, so we estimate instead.
    static func activeKcalPerMinute(speedKmh: Double, grade: Double, massKg: Double) -> Double {
        guard speedKmh >= 0.5 else { return 0 }
        let metresPerMin = speedKmh * 1000 / 60
        let vo2 = speedKmh < 8
            ? 0.1 * metresPerMin + 1.8 * metresPerMin * grade   // walking
            : 0.2 * metresPerMin + 0.9 * metresPerMin * grade   // running
        return vo2 * massKg / 1000 * 5  // ml/kg/min -> L/min -> kcal/min
    }
}
