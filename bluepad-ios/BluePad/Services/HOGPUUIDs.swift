import CoreBluetooth
import Foundation

/// Full 128-bit canonical Bluetooth SIG UUIDs for HOGP (HID over GATT Profile).
/// Note: iOS CoreBluetooth reserves short 16-bit SIG UUID strings (e.g. "1812", "2908")
/// in CBPeripheralManager; always expand to the canonical 128-bit Bluetooth Base UUID.
enum HOGPUUID {
    static func sig128(_ shortHex: String) -> CBUUID {
        CBUUID(string: "0000\(shortHex.uppercased())-0000-1000-8000-00805F9B34FB")
    }

    // MARK: Primary / Adopted Services
    static let deviceInformationService = sig128("180A")
    static let batteryService           = sig128("180F")
    static let hidService               = sig128("1812")

    /// 16-bit short HID Service UUID (4 bytes in BLE ADV packet, AD Type 0x03) used ONLY in
    /// `CBAdvertisementDataServiceUUIDsKey` so Windows/Android/TV scanners discover BluePad
    /// without overflowing the 31-byte BLE advertisement packet into Apple's proprietary overflow area.
    static let hidServiceAdvertising16Bit = CBUUID(string: "1812")

    // MARK: Device Information Characteristics
    static let manufacturerName         = sig128("2A29")
    static let modelNumber              = sig128("2A24")
    static let pnpID                    = sig128("2A50")

    // MARK: Battery Service Characteristics
    static let batteryLevel             = sig128("2A19")

    // MARK: HID Service Characteristics
    static let hidInformation           = sig128("2A4A")
    static let reportMap                = sig128("2A4B")
    static let hidControlPoint          = sig128("2A4C")
    static let report                   = sig128("2A4D")
    static let protocolMode             = sig128("2A4E")
    static let bootKeyboardInput        = sig128("2A22")
    static let bootKeyboardOutput       = sig128("2A32")
    static let bootMouseInput           = sig128("2A33")

    // MARK: Descriptors
    static let reportReference          = sig128("2908")

    // MARK: Static GATT Payloads
    /// USB HID v1.11 (0x0111 LE), Country Code 0x00 (Not Localized), Flags 0x02 (NormallyConnectable).
    static let hidInfoValue = Data([0x11, 0x01, 0x00, 0x02])

    /// PnP ID: Vendor ID Source = 0x02 (USB Implementers Forum), VID = 0x1209 (pid.codes), PID = 0x4201, Version = 0x0100.
    static let pnpIDValue = Data([0x02, 0x09, 0x12, 0x01, 0x42, 0x00, 0x01])

    static let manufacturerData = Data("BluePad".utf8)
    static let modelNumberData  = Data("BluePad HID iOS".utf8)

    // MARK: Fixed Custom UUIDs for GATT Service Changed Trigger
    static let serviceChangedTriggerService = CBUUID(string: "7F4B2C10-5E8A-4D31-9B72-0C1A3E5F7B90")
    static let serviceChangedTriggerCharacteristic = CBUUID(string: "7F4B2C11-5E8A-4D31-9B72-0C1A3E5F7B90")
}
