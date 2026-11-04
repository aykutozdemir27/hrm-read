import CoreBluetooth
import Combine
import Foundation

final class BluetoothMonitor: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var devices: [CBPeripheral] = []
    @Published var bpm: Int?
    @Published var status = "Tap Find strap to begin"
    @Published var scanning = false
    @Published var connected = false
    @Published var busy = false
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var lastReading: Date?
    private var timer: AnyCancellable?
    private var deadline: DispatchWorkItem?
    private var wantsScan = false
    private var reconnectWork: DispatchWorkItem?
    private var shouldReconnect = false
    private let service = CBUUID(string: "180D")
    private let measurement = CBUUID(string: "2A37")

    override init() {
        super.init()
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, let last = self.lastReading,
                  Date().timeIntervalSince(last) > 6 else { return }
            self.bpm = nil
            self.status = "No recent reading — check strap contact"
        }
    }

    func scan() {
        wantsScan = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central.state == .poweredOn { startScan() }
        else { centralManagerDidUpdateState(central) }
    }

    private func startScan() {
        devices = []
        scanning = true
        wantsScan = false
        status = "Looking for heart rate straps…"
        central.scanForPeripherals(withServices: [service])
        setDeadline(seconds: 15) { [weak self] in
            guard let self else { return }
            self.central.stopScan()
            self.scanning = false
            self.status = self.devices.isEmpty ? "No strap found. Wake it and use open mode." : "Choose your strap below"
        }
    }

    private func setDeadline(seconds: Double, action: @escaping () -> Void) {
        deadline?.cancel()
        let work = DispatchWorkItem(block: action)
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func connect(_ device: CBPeripheral) {
        shouldReconnect = true
        reconnectWork?.cancel()
        deadline?.cancel()
        central.stopScan()
        scanning = false
        peripheral = device
        device.delegate = self
        busy = true
        status = "Connecting…"
        central.connect(device)
        setDeadline(seconds: 20) { [weak self] in
            guard let self, self.busy else { return }
            self.disconnect()
            self.status = "Connection timed out. Try again in open mode."
        }
    }

    func disconnect() {
        shouldReconnect = false
        reconnectWork?.cancel()
        wantsScan = false
        deadline?.cancel()
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        scanning = false
        connected = false
        busy = false
        bpm = nil
        lastReading = nil
        status = "Disconnected"
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if shouldReconnect, peripheral != nil { reconnect() }
            else if wantsScan { startScan() }
            return
        }
        deadline?.cancel()
        bpm = nil
        lastReading = nil
        connected = false
        busy = false
        scanning = false
        reconnectWork?.cancel()
        switch central.state {
        case .poweredOff: status = shouldReconnect ? "Bluetooth off — reconnects when turned on" : "Turn on Bluetooth, then tap Find strap"
        case .unauthorized: status = "Allow Bluetooth for HRM Read in Settings"
        case .unsupported: status = "Bluetooth Low Energy is unavailable"
        default: status = "Bluetooth is starting…"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !devices.contains(where: { $0.identifier == peripheral.identifier }) { devices.append(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard shouldReconnect, self.peripheral?.identifier == peripheral.identifier else {
            central.cancelPeripheralConnection(peripheral); return
        }
        reconnectWork?.cancel()
        setDeadline(seconds: 20) { [weak self] in
            self?.fail("Strap setup timed out. Check open mode and try again.")
        }
        status = "Connected — finding heart rate service…"
        peripheral.discoverServices([service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        reconnect(after: 5)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        reconnect(after: 2)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard shouldReconnect, self.peripheral?.identifier == peripheral.identifier else { return }
        guard error == nil, let hr = peripheral.services?.first(where: { $0.uuid == service }) else {
            fail("Heart rate service unavailable. Try open mode."); return
        }
        peripheral.discoverCharacteristics([measurement], for: hr)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard shouldReconnect, self.peripheral?.identifier == peripheral.identifier else { return }
        guard error == nil, let value = service.characteristics?.first(where: { $0.uuid == measurement }),
              value.properties.contains(.notify) else {
            fail("This strap did not offer live heart rate notifications."); return
        }
        peripheral.setNotifyValue(true, for: value)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard shouldReconnect, self.peripheral?.identifier == peripheral.identifier else { return }
        guard error == nil, characteristic.isNotifying else { fail("Could not start live readings."); return }
        deadline?.cancel()
        busy = false
        connected = true
        lastReading = Date()
        status = "Waiting for heart rate…"
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard shouldReconnect, self.peripheral?.identifier == peripheral.identifier else { return }
        guard characteristic.uuid == measurement, error == nil,
              let data = characteristic.value, let reading = HeartRateMeasurement(data: data) else { return }
        lastReading = Date()
        if reading.contactDetected == false || reading.bpm == 0 {
            bpm = nil
            status = "Check strap fit and moisten the electrodes"
        } else {
            bpm = reading.bpm
            status = "Live · \(peripheral.name ?? "Heart rate strap")"
        }
    }

    private func fail(_ message: String) { disconnect(); status = message }

    private func reconnect(after delay: Double = 0) {
        guard shouldReconnect, let device = peripheral else { return }
        deadline?.cancel()
        reconnectWork?.cancel()
        bpm = nil
        lastReading = nil
        connected = false
        guard central.state == .poweredOn else {
            busy = false
            status = "Waiting for Bluetooth — reconnects when available"
            return
        }
        busy = true
        status = "Reconnecting to your strap… Tap Stop to cancel."
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.shouldReconnect, self.central.state == .poweredOn,
                  self.peripheral?.identifier == device.identifier else { return }
            // Core Bluetooth keeps this request pending until the strap is available.
            self.central.connect(device)
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
