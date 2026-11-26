import Foundation

/// Pure-Swift protocol encoder/decoder for Samsung Tizen Smart TV WebSocket remote API (2016+, ports 8002/8001).
enum SamsungTizenProtocol {

    static func webSocketURL(host: String, clientName: String, token: String?, secure: Bool) -> URL? {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { return nil }

        let cleanName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedName = Data((cleanName.isEmpty ? "BluePad" : cleanName).utf8).base64EncodedString()

        var components = URLComponents()
        components.scheme = secure ? "wss" : "ws"
        components.host = cleanHost
        components.port = secure ? 8002 : 8001
        components.path = "/api/v2/channels/samsung.remote.control"

        var items = [URLQueryItem(name: "name", value: encodedName)]
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            items.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = items
        return components.url
    }

    static func remoteKeyPayload(_ key: String, cmd: String = "Click") -> String {
        encodeJSON([
            "method": "ms.remote.control",
            "params": [
                "Cmd": cmd,
                "DataOfCmd": key,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey"
            ]
        ])
    }

    static func mouseMovePayload(x: Int, y: Int, timestampMs: Int64) -> String {
        encodeJSON([
            "method": "ms.remote.control",
            "params": [
                "Cmd": "Move",
                "Position": [
                    "x": x,
                    "y": y,
                    "Time": "\(timestampMs)"
                ],
                "TypeOfRemote": "ProcessMouseDevice"
            ]
        ])
    }

    static func mouseClickPayload(rightClick: Bool = false) -> String {
        encodeJSON([
            "method": "ms.remote.control",
            "params": [
                "Cmd": rightClick ? "RightClick" : "LeftClick",
                "TypeOfRemote": "ProcessMouseDevice"
            ]
        ])
    }

    static func inputStringPayload(_ text: String) -> String {
        let b64 = Data(text.utf8).base64EncodedString()
        return encodeJSON([
            "method": "ms.remote.control",
            "params": [
                "Cmd": b64,
                "DataOfCmd": "base64",
                "TypeOfRemote": "SendInputString"
            ]
        ])
    }

    static func launchAppPayload(appID: String) -> String {
        encodeJSON([
            "method": "ms.channel.emit",
            "params": [
                "data": [
                    "action_type": "DEEP_LINK",
                    "appId": appID
                ],
                "event": "ed.apps.launch",
                "to": "host"
            ]
        ])
    }

    static func parseConnectToken(from text: String) -> (connected: Bool, token: String?) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else {
            return (false, nil)
        }
        if event == "ms.channel.connect" {
            let payloadData = json["data"] as? [String: Any]
            let token = (payloadData?["token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (true, (token?.isEmpty == false) ? token : nil)
        }
        return (false, nil)
    }

    static func keyCode(for hidKeyCode: HIDKeyCode) -> String? {
        switch hidKeyCode {
        case .upArrow: return "KEY_UP"
        case .downArrow: return "KEY_DOWN"
        case .leftArrow: return "KEY_LEFT"
        case .rightArrow: return "KEY_RIGHT"
        case .enter, .kpEnter: return "KEY_ENTER"
        case .escape: return "KEY_RETURN"
        case .backspace: return "KEY_BACKSPACE"
        case .home: return "KEY_HOME"
        case .application: return "KEY_MENU"
        case .pageUp: return "KEY_CHUP"
        case .pageDown: return "KEY_CHDOWN"
        default: return nil
        }
    }

    static func keyCode(for consumerUsage: HIDConsumerUsage) -> String? {
        switch consumerUsage {
        case .power: return "KEY_POWER"
        case .menu: return "KEY_MENU"
        case .menuPick: return "KEY_ENTER"
        case .menuUp: return "KEY_UP"
        case .menuDown: return "KEY_DOWN"
        case .menuLeft: return "KEY_LEFT"
        case .menuRight: return "KEY_RIGHT"
        case .menuEscape, .acBack: return "KEY_RETURN"
        case .acHome: return "KEY_HOME"
        case .acSearch: return "KEY_CONTENTS"
        case .playPause: return "KEY_PLAY"
        case .stop: return "KEY_STOP"
        case .rewind: return "KEY_REWIND"
        case .fastForward: return "KEY_FF"
        case .scanNextTrack: return "KEY_FF"
        case .scanPreviousTrack: return "KEY_REWIND"
        case .mute: return "KEY_MUTE"
        case .volumeIncrement: return "KEY_VOLUP"
        case .volumeDecrement: return "KEY_VOLDOWN"
        default: return nil
        }
    }

    static func keyCode(for systemUsage: HIDSystemUsage) -> String? {
        if systemUsage.contains(.powerDown) || systemUsage.contains(.sleep) {
            return "KEY_POWER"
        }
        if systemUsage.contains(.wakeUp) {
            return "KEY_POWERON"
        }
        return nil
    }

    static func appID(forAppURL url: String) -> String? {
        let lower = url.lowercased()
        if lower.contains("youtube") { return "111299001912" }
        if lower.contains("netflix") { return "3201907018807" }
        if lower.contains("spotify") { return "3201606009684" }
        if lower.contains("primevideo") { return "3201910019365" }
        if lower.contains("disneyplus") { return "3201901017640" }
        return nil
    }

    private static func encodeJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

/// Pure-Swift protocol encoder/decoder for LG webOS SSAP + Magic Remote Pointer Input Socket (ports 3001/3000).
enum LGWebOSProtocol {

    static func ssapURL(host: String, secure: Bool) -> URL? {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = secure ? "wss" : "ws"
        components.host = cleanHost
        components.port = secure ? 3001 : 3000
        return components.url
    }

    static func registerPayload(clientKey: String?, requestID: String = "register_0") -> String {
        var payload: [String: Any] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "permissions": [
                    "LAUNCH",
                    "CONTROL_AUDIO",
                    "CONTROL_INPUT_MEDIA_PLAYBACK",
                    "CONTROL_INPUT_TV",
                    "CONTROL_POWER",
                    "CONTROL_INPUT_TEXT",
                    "CONTROL_MOUSE_AND_KEYBOARD",
                    "READ_INPUT_DEVICE_LIST",
                    "READ_RUNNING_APPS"
                ]
            ]
        ]
        if let key = clientKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            payload["client-key"] = key
        }
        return encodeJSON([
            "type": "register",
            "id": requestID,
            "payload": payload
        ])
    }

    static func requestPayload(id: String, uri: String, payload: [String: Any] = [:]) -> String {
        encodeJSON([
            "id": id,
            "type": "request",
            "uri": uri,
            "payload": payload
        ])
    }

    static func pointerMoveMessage(dx: Int, dy: Int, buttonDown: Bool = false) -> String {
        "type:move\ndx:\(dx)\ndy:\(dy)\ndown:\(buttonDown ? 1 : 0)\n\n"
    }

    static func pointerClickMessage() -> String {
        "type:click\n\n"
    }

    static func pointerScrollMessage(dx: Int, dy: Int) -> String {
        "type:scroll\ndx:\(dx)\ndy:\(dy)\n\n"
    }

    static func pointerButtonMessage(_ name: String) -> String {
        "type:button\nname:\(name)\n\n"
    }

    static func buttonName(for hidKeyCode: HIDKeyCode) -> String? {
        switch hidKeyCode {
        case .upArrow: return "UP"
        case .downArrow: return "DOWN"
        case .leftArrow: return "LEFT"
        case .rightArrow: return "RIGHT"
        case .enter, .kpEnter: return "ENTER"
        case .escape: return "BACK"
        case .home: return "HOME"
        case .application: return "MENU"
        default: return nil
        }
    }

    static func buttonName(for consumerUsage: HIDConsumerUsage) -> String? {
        switch consumerUsage {
        case .menu: return "MENU"
        case .menuPick: return "ENTER"
        case .menuUp: return "UP"
        case .menuDown: return "DOWN"
        case .menuLeft: return "LEFT"
        case .menuRight: return "RIGHT"
        case .menuEscape, .acBack: return "BACK"
        case .acHome: return "HOME"
        default: return nil
        }
    }

    static func ssapCommand(for consumerUsage: HIDConsumerUsage) -> (uri: String, payload: [String: Any])? {
        switch consumerUsage {
        case .power: return ("ssap://system/turnOff", [:])
        case .playPause: return ("ssap://media.controls/play", [:])
        case .stop: return ("ssap://media.controls/stop", [:])
        case .rewind: return ("ssap://media.controls/rewind", [:])
        case .fastForward, .scanNextTrack: return ("ssap://media.controls/fastForward", [:])
        case .scanPreviousTrack: return ("ssap://media.controls/rewind", [:])
        case .mute: return ("ssap://audio/setMute", ["mute": true])
        case .volumeIncrement: return ("ssap://audio/volumeUp", [:])
        case .volumeDecrement: return ("ssap://audio/volumeDown", [:])
        default: return nil
        }
    }

    static func ssapCommand(for systemUsage: HIDSystemUsage) -> (uri: String, payload: [String: Any])? {
        if systemUsage.contains(.powerDown) || systemUsage.contains(.sleep) {
            return ("ssap://system/turnOff", [:])
        }
        return nil
    }

    static func appID(forAppURL url: String) -> String? {
        let lower = url.lowercased()
        if lower.contains("youtube") { return "youtube.leanback.v4" }
        if lower.contains("netflix") { return "netflix" }
        if lower.contains("spotify") { return "spotify-beehive" }
        if lower.contains("primevideo") { return "amazon" }
        if lower.contains("disneyplus") { return "com.disney.disneyplus-prod" }
        return nil
    }

    private static func encodeJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}
