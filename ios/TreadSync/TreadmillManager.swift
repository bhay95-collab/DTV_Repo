import CoreBluetooth
import Foundation
import Observation

/// Finds the treadmill over Bluetooth, subscribes to FTMS Treadmill Data,
/// and reconnects automatically if the link drops.
@Observable
final class TreadmillManager: NSObject {
    enum ConnectionState: String {
        case bluetoothOff = "Bluetooth off"
        case idle = "Not connected"
        case scanning = "Searching…"
        case connecting = "Connecting…"
        case connected = "Connected"
        case reconnecting = "Reconnecting…"
    }

    private(set) var state: ConnectionState = .idle
    private(set) var deviceName: String?
    private(set) var latest = TreadmillData()
    private(set) var lastPacketHex = ""
    private(set) var lastPacketDate: Date?

    /// Called on the main queue for every Treadmill Data packet, with all fields seen so far merged in.
    var onData: ((TreadmillData, Date) -> Void)?

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private let savedPeripheralKey = "treadmillPeripheralID"

    private let ftmsService = CBUUID(string: FTMS.serviceUUID)
    private let treadmillDataChar = CBUUID(string: FTMS.treadmillDataUUID)

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func connect() {
        wantsConnection = true
        guard central.state == .poweredOn else { return }

        if let idString = UserDefaults.standard.string(forKey: savedPeripheralKey),
           let id = UUID(uuidString: idString),
           let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            attach(known)
            return
        }
        state = .scanning
        central.scanForPeripherals(withServices: [ftmsService])
    }

    func disconnect() {
        wantsConnection = false
        central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        state = .idle
    }

    /// Forget the saved treadmill so the next connect() scans afresh.
    func forgetDevice() {
        disconnect()
        UserDefaults.standard.removeObject(forKey: savedPeripheralKey)
        peripheral = nil
        deviceName = nil
    }

    private func attach(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        deviceName = p.name
        state = .connecting
        central.connect(p)
    }
}

extension TreadmillManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            state = .idle
            if wantsConnection { connect() }
        } else {
            state = .bluetoothOff
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        attach(p)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        UserDefaults.standard.set(p.identifier.uuidString, forKey: savedPeripheralKey)
        deviceName = p.name
        state = .connected
        p.discoverServices([ftmsService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        retry(p)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        retry(p)
    }

    private func retry(_ p: CBPeripheral) {
        guard wantsConnection else { state = .idle; return }
        // A pending connect() never times out: iOS reconnects as soon as the
        // treadmill is back in range, even with the app in the background.
        state = .reconnecting
        central.connect(p)
    }
}

extension TreadmillManager: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for service in p.services ?? [] where service.uuid == ftmsService {
            p.discoverCharacteristics([treadmillDataChar], for: service)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] where c.uuid == treadmillDataChar {
            p.setNotifyValue(true, for: c)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard c.uuid == treadmillDataChar, let value = c.value,
              let parsed = FTMS.parseTreadmillData(value) else { return }
        let now = Date()
        lastPacketHex = value.hexString
        lastPacketDate = now
        latest = latest.merging(parsed)
        onData?(latest, now)
    }
}
