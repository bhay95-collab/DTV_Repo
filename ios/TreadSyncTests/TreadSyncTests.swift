import XCTest

final class FTMSParserTests: XCTestCase {
    private func data(_ hex: String) -> Data {
        Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
    }

    func testFullPacket() throws {
        // flags 0x048C: speed, distance, incline, energy, elapsed time
        let t = try XCTUnwrap(FTMS.parseTreadmillData(
            data("8C 04 5E 01 D2 04 00 14 00 00 00 2D 00 2C 01 05 58 02")))
        XCTAssertEqual(t.speedKmh, 3.5)
        XCTAssertEqual(t.totalDistanceM, 1234)
        XCTAssertEqual(t.inclinePercent, 2.0)
        XCTAssertEqual(t.rampAngleDeg, 0)
        XCTAssertEqual(t.totalEnergyKcal, 45)
        XCTAssertEqual(t.energyPerHourKcal, 300)
        XCTAssertEqual(t.energyPerMinuteKcal, 5)
        XCTAssertEqual(t.elapsedTimeS, 600)
        XCTAssertNil(t.heartRateBpm)
    }

    func testMoreDataBitMeansNoSpeed() throws {
        // flags 0x0005: More Data set (no speed), distance present
        let t = try XCTUnwrap(FTMS.parseTreadmillData(data("05 00 10 27 00")))
        XCTAssertNil(t.speedKmh)
        XCTAssertEqual(t.totalDistanceM, 10_000)
    }

    func testNegativeIncline() throws {
        let t = try XCTUnwrap(FTMS.parseTreadmillData(data("08 00 00 00 F1 FF 00 00")))
        XCTAssertEqual(t.inclinePercent, -1.5)
    }

    func testTruncatedPacketKeepsEarlierFields() throws {
        let t = try XCTUnwrap(FTMS.parseTreadmillData(data("04 00 5E 01 D2")))
        XCTAssertEqual(t.speedKmh, 3.5)
        XCTAssertNil(t.totalDistanceM)
    }

    func testTooShort() {
        XCTAssertNil(FTMS.parseTreadmillData(data("04")))
    }

    func testMerging() {
        let a = TreadmillData(speedKmh: 3, totalDistanceM: 100)
        let b = TreadmillData(totalDistanceM: 120, inclinePercent: 5)
        let m = a.merging(b)
        XCTAssertEqual(m.speedKmh, 3)
        XCTAssertEqual(m.totalDistanceM, 120)
        XCTAssertEqual(m.inclinePercent, 5)
    }
}

final class WorkoutSessionTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    func testUsesOdometerAndIgnoresLeftoverWhenBeltStopped() {
        var s = WorkoutSession(startDate: t0)
        s.ingest(TreadmillData(speedKmh: 0, totalDistanceM: 2000), at: at(1)) // leftover from last walk
        s.ingest(TreadmillData(speedKmh: 4, totalDistanceM: 2000), at: at(2))
        s.ingest(TreadmillData(speedKmh: 4, totalDistanceM: 2150), at: at(3))
        XCTAssertEqual(s.distanceM, 150)
    }

    func testCountsInProgressDistanceWhenBeltAlreadyMoving() {
        var s = WorkoutSession(startDate: t0)
        s.ingest(TreadmillData(speedKmh: 4, totalDistanceM: 300), at: at(1))
        XCTAssertEqual(s.distanceM, 300)
    }

    func testOdometerResetIsAccumulated() {
        var s = WorkoutSession(startDate: t0)
        s.ingest(TreadmillData(speedKmh: 0, totalDistanceM: 0), at: at(1))
        s.ingest(TreadmillData(speedKmh: 4, totalDistanceM: 500), at: at(2))
        s.ingest(TreadmillData(speedKmh: 4, totalDistanceM: 0), at: at(3))   // treadmill restarted
        s.ingest(TreadmillData(speedKmh: 4, totalDistanceM: 200), at: at(4))
        XCTAssertEqual(s.distanceM, 700)
    }

    func testDistanceNeverGoesBackwardsOnSmallJitter() {
        var s = WorkoutSession(startDate: t0)
        s.ingest(TreadmillData(speedKmh: 4, totalDistanceM: 100), at: at(1))
        s.ingest(TreadmillData(speedKmh: 4, totalDistanceM: 98), at: at(2))
        XCTAssertEqual(s.distanceM, 100)
    }

    func testFallsBackToIntegratingSpeed() {
        var s = WorkoutSession(startDate: t0)
        for i in 0...10 { s.ingest(TreadmillData(speedKmh: 3.6), at: at(Double(i))) } // 1 m/s
        XCTAssertEqual(s.distanceM, 10, accuracy: 1e-9)
    }

    func testBluetoothGapIsNotIntegrated() {
        var s = WorkoutSession(startDate: t0)
        s.ingest(TreadmillData(speedKmh: 3.6), at: at(0))
        s.ingest(TreadmillData(speedKmh: 3.6), at: at(60)) // 60 s gap
        XCTAssertEqual(s.distanceM, 0)
    }

    func testElevationFromIncline() {
        var s = WorkoutSession(startDate: t0)
        s.ingest(TreadmillData(speedKmh: 0, totalDistanceM: 0, inclinePercent: 10), at: at(1))
        s.ingest(TreadmillData(speedKmh: 4, totalDistanceM: 1000, inclinePercent: 10), at: at(2))
        XCTAssertEqual(s.elevationGainM, 100, accuracy: 1e-9)
    }

    func testIntervalsSumToTotals() {
        var s = WorkoutSession(startDate: t0)
        for i in 0...300 {
            s.ingest(TreadmillData(speedKmh: 5, totalDistanceM: Double(i) * 1.4), at: at(Double(i)))
        }
        s.finish(at: at(301))
        let ivs = s.intervals(bucket: 60)
        XCTAssertGreaterThanOrEqual(ivs.count, 5)
        XCTAssertEqual(ivs.map(\.distanceM).reduce(0, +), s.distanceM, accuracy: 1e-6)
        XCTAssertEqual(ivs.map(\.activeKcal).reduce(0, +), s.activeKcal, accuracy: 1e-6)
        XCTAssertEqual(ivs.first?.start, t0)
        XCTAssertEqual(ivs.last?.end, at(301))
        for (a, b) in zip(ivs, ivs.dropFirst()) { XCTAssertEqual(a.end, b.start) }
    }

    func testIgnoresDataAfterFinish() {
        var s = WorkoutSession(startDate: t0)
        s.ingest(TreadmillData(speedKmh: 4, totalDistanceM: 100), at: at(1))
        s.finish(at: at(2))
        s.ingest(TreadmillData(speedKmh: 4, totalDistanceM: 500), at: at(3))
        XCTAssertEqual(s.distanceM, 100)
    }

    func testCalorieEstimateIsSane() {
        // 5 km/h flat, 75 kg: roughly 3 kcal/min active (~190 kcal/h)
        let flat = WorkoutSession.activeKcalPerMinute(speedKmh: 5, grade: 0, massKg: 75)
        XCTAssertEqual(flat, 3.125, accuracy: 0.01)
        let hill = WorkoutSession.activeKcalPerMinute(speedKmh: 5, grade: 0.1, massKg: 75)
        XCTAssertGreaterThan(hill, flat * 2)
        XCTAssertEqual(WorkoutSession.activeKcalPerMinute(speedKmh: 0, grade: 0, massKg: 75), 0)
    }
}
