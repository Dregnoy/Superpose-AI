    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        flushQueues()
    }
}
// MARK: - CBCentralManagerDelegate (iOS Permission Prompt Bootstrap)
extension BLEHIDPeripheralService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        emitLog(
            .ble,
            "Central durumu: \(stateName(central.state)) (raw=\(central.state.rawValue)), yetki: \(authorizationText(CBManager.authorization))"
        )
        switch central.state {
        case .poweredOn:
            if peripheralManager == nil || peripheralManager?.state == .unknown {
                servicesPublished = false
                hidServicePublished = false
                pendingServicesToAdd.removeAll()
                peripheralManager?.delegate = nil
                emitLog(.ble, "Central açıldı; CBPeripheralManager başlatılıyor...")
                peripheralManager = CBPeripheralManager(
                    delegate: self,
                    queue: nil,
                    options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
                )
            } else if let manager = peripheralManager {
                handleManagerState(manager)
            }
        case .unauthorized:
            emitState(.unauthorized)
        case .poweredOff:
            emitState(.poweredOff)
        case .unsupported:
            if peripheralManager == nil || peripheralManager?.state == .unknown {
                emitState(.unsupported)
            }
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
    }
}
