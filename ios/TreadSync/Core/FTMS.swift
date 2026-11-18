import Foundation

/// Decoded fields from a Bluetooth FTMS "Treadmill Data" (0x2ACD) notification.
/// Every field is optional because the treadmill chooses which fields to send,
/// and may split them across several notifications.
struct TreadmillData: Equatable {
    var speedKmh: Double?
    var averageSpeedKmh: Double?
    var totalDistanceM: Double?
    var inclinePercent: Double?
    var rampAngleDeg: Double?
    var elevationGainPositiveM: Double?
    var elevationGainNegativeM: Double?
    var paceKmPerMin: Double?
    var averagePaceKmPerMin: Double?
    var totalEnergyKcal: Double?
    var energyPerHourKcal: Double?
    var energyPerMinuteKcal: Double?
    var heartRateBpm: Int?
    var metabolicEquivalent: Double?
    var elapsedTimeS: Int?
    var remainingTimeS: Int?
    var forceOnBeltN: Int?
    var powerW: Int?

    /// Fields present in `newer` replace ours; fields it lacks keep their previous value.
    func merging(_ newer: TreadmillData) -> TreadmillData {
        var m = self
        m.speedKmh = newer.speedKmh ?? speedKmh
        m.averageSpeedKmh = newer.averageSpeedKmh ?? averageSpeedKmh
        m.totalDistanceM = newer.totalDistanceM ?? totalDistanceM
        m.inclinePercent = newer.inclinePercent ?? inclinePercent
        m.rampAngleDeg = newer.rampAngleDeg ?? rampAngleDeg
        m.elevationGainPositiveM = newer.elevationGainPositiveM ?? elevationGainPositiveM
        m.elevationGainNegativeM = newer.elevationGainNegativeM ?? elevationGainNegativeM
        m.paceKmPerMin = newer.paceKmPerMin ?? paceKmPerMin
        m.averagePaceKmPerMin = newer.averagePaceKmPerMin ?? averagePaceKmPerMin
        m.totalEnergyKcal = newer.totalEnergyKcal ?? totalEnergyKcal
        m.energyPerHourKcal = newer.energyPerHourKcal ?? energyPerHourKcal
        m.energyPerMinuteKcal = newer.energyPerMinuteKcal ?? energyPerMinuteKcal
        m.heartRateBpm = newer.heartRateBpm ?? heartRateBpm
        m.metabolicEquivalent = newer.metabolicEquivalent ?? metabolicEquivalent
        m.elapsedTimeS = newer.elapsedTimeS ?? elapsedTimeS
        m.remainingTimeS = newer.remainingTimeS ?? remainingTimeS
        m.forceOnBeltN = newer.forceOnBeltN ?? forceOnBeltN
        m.powerW = newer.powerW ?? powerW
        return m
    }
}

enum FTMS {
    static let serviceUUID = "1826"
    static let treadmillDataUUID = "2ACD"

    /// Parses a Treadmill Data payload (Bluetooth FTMS spec v1.0, section 4.9).
    /// Returns nil only if the 2-byte flags field is missing. A truncated packet
    /// returns whatever fields fit before the data ran out.
    static func parseTreadmillData(_ data: Data) -> TreadmillData? {
        var r = ByteReader(bytes: [UInt8](data))
        guard let flags = r.u16() else { return nil }
        func has(_ bit: Int) -> Bool { flags & (1 << bit) != 0 }

        var t = TreadmillData()
        // Bit 0 is "More Data": when it is 0, Instantaneous Speed IS present.
        if !has(0) {
            guard let v = r.u16() else { return t }
            t.speedKmh = Double(v) / 100
        }
        if has(1) {
            guard let v = r.u16() else { return t }
            t.averageSpeedKmh = Double(v) / 100
        }
        if has(2) {
            guard let v = r.u24() else { return t }
            t.totalDistanceM = Double(v)
        }
        if has(3) {
            guard let inc = r.s16(), let ramp = r.s16() else { return t }
            t.inclinePercent = Double(inc) / 10
            t.rampAngleDeg = Double(ramp) / 10
        }
        if has(4) {
            guard let pos = r.u16(), let neg = r.u16() else { return t }
            t.elevationGainPositiveM = Double(pos) / 10
            t.elevationGainNegativeM = Double(neg) / 10
        }
        if has(5) {
            // Spec: uint8, km/min, resolution 0.1.
            guard let v = r.u8() else { return t }
            t.paceKmPerMin = Double(v) / 10
        }
        if has(6) {
            guard let v = r.u8() else { return t }
            t.averagePaceKmPerMin = Double(v) / 10
        }
        if has(7) {
            guard let total = r.u16(), let perHour = r.u16(), let perMin = r.u8() else { return t }
            t.totalEnergyKcal = Double(total)
            t.energyPerHourKcal = Double(perHour)
            t.energyPerMinuteKcal = Double(perMin)
        }
        if has(8) {
            guard let v = r.u8() else { return t }
            t.heartRateBpm = Int(v)
        }
        if has(9) {
            guard let v = r.u8() else { return t }
            t.metabolicEquivalent = Double(v) / 10
        }
        if has(10) {
            guard let v = r.u16() else { return t }
            t.elapsedTimeS = Int(v)
        }
        if has(11) {
            guard let v = r.u16() else { return t }
            t.remainingTimeS = Int(v)
        }
        if has(12) {
            guard let force = r.s16(), let power = r.s16() else { return t }
            t.forceOnBeltN = Int(force)
            t.powerW = Int(power)
        }
        return t
    }
}

/// Little-endian reader over a byte array.
struct ByteReader {
    let bytes: [UInt8]
    private(set) var index = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func u8() -> UInt8? {
        guard index < bytes.count else { return nil }
        defer { index += 1 }
        return bytes[index]
    }

    mutating func u16() -> UInt16? {
        guard index + 2 <= bytes.count else { return nil }
        defer { index += 2 }
        return UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
    }

    mutating func s16() -> Int16? { u16().map { Int16(bitPattern: $0) } }

    mutating func u24() -> UInt32? {
        guard index + 3 <= bytes.count else { return nil }
        defer { index += 3 }
        return UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]) << 16
    }
}

extension Data {
    var hexString: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
