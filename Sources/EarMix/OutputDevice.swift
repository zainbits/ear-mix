import CoreAudio

struct OutputDevice: Identifiable, Equatable {
    enum Kind {
        case bluetooth, usb, headphoneJack, speakers, display, other
    }

    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32
    /// 0...100, or nil when the device has no software volume control.
    var volume: Int?

    var kind: Kind {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: return .display
        case kAudioDeviceTransportTypeBuiltIn:
            return name.localizedCaseInsensitiveContains("speaker") ? .speakers : .headphoneJack
        default: return .other
        }
    }

    /// Earphones are ticked automatically the first time they appear.
    var isEarphone: Bool { [.bluetooth, .usb, .headphoneJack].contains(kind) }

    var symbol: String {
        switch kind {
        case .bluetooth: return "airpods"
        case .usb: return "cable.connector"
        case .headphoneJack: return "headphones"
        case .speakers: return "laptopcomputer"
        case .display: return "display"
        case .other: return "hifispeaker"
        }
    }

    var kindLabel: String {
        switch kind {
        case .bluetooth: return "Bluetooth"
        case .usb: return "USB"
        case .headphoneJack: return "AUX"
        case .speakers: return "Built-in"
        case .display: return "Display"
        case .other: return "Output"
        }
    }
}
