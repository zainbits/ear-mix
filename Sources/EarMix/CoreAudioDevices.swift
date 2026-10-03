import CoreAudio
import Foundation

/// Thin wrappers over the CoreAudio HAL: device discovery, per-device volume,
/// default output, and the stacked aggregate ("Multi-Output Device") EarMix owns.
enum CoreAudioDevices {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let mixName = "EarMix"
    static let mixUID = "dev.zainbits.earmix.multi-output"

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var a = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr, let v = value else { return "" }
        return v.takeRetainedValue() as String
    }

    static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var a = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value)
        return value
    }

    static func allDeviceIDs() -> [AudioDeviceID] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids)
        return ids
    }

    static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var a = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr && size > 0
    }

    static func uid(of id: AudioDeviceID) -> String { string(id, kAudioDevicePropertyDeviceUID) }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { self.uid(of: $0) == uid }
    }

    /// Physical outputs only: virtual devices (Zoom, Teams) and aggregates are skipped.
    static func physicalOutputs() -> [OutputDevice] {
        allDeviceIDs().compactMap { id in
            guard hasOutput(id) else { return nil }
            let transport = uint32(id, kAudioDevicePropertyTransportType)
            if transport == kAudioDeviceTransportTypeVirtual || transport == kAudioDeviceTransportTypeAggregate {
                return nil
            }
            let uid = uid(of: id)
            guard uid != mixUID else { return nil }
            return OutputDevice(id: id, uid: uid, name: string(id, kAudioObjectPropertyName),
                                transport: transport, volume: volume(of: id))
        }
    }

    // MARK: Volume

    /// Prefer the main volume control; fall back to per-channel controls.
    private static func volumeElements(_ id: AudioDeviceID) -> [AudioObjectPropertyElement] {
        var channels: [AudioObjectPropertyElement] = []
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var a = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, element)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(id, &a),
                  AudioObjectIsPropertySettable(id, &a, &settable) == noErr, settable.boolValue else { continue }
            if element == kAudioObjectPropertyElementMain { return [element] }
            channels.append(element)
        }
        return channels
    }

    static func volume(of id: AudioDeviceID) -> Int? {
        guard let element = volumeElements(id).first else { return nil }
        var a = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, element)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr else { return nil }
        return Int((value * 100).rounded())
    }

    static func setVolume(of id: AudioDeviceID, to percent: Int) {
        var value = Float32(min(100, max(0, percent))) / 100
        for element in volumeElements(id) {
            var a = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, element)
            AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    // MARK: Default output

    static func defaultOutput() -> AudioDeviceID { uint32(system, kAudioHardwarePropertyDefaultOutputDevice) }

    static func setDefaultOutput(_ id: AudioDeviceID) {
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var a = address(selector)
            var device = id
            AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device)
        }
    }

    // MARK: Multi-output device

    static func mixDeviceID() -> AudioDeviceID? { deviceID(forUID: mixUID) }

    static func mixMemberUIDs() -> [String] {
        guard let mix = mixDeviceID() else { return [] }
        var a = address(kAudioAggregateDevicePropertyFullSubDeviceList)
        var list: Unmanaged<CFArray>?
        var size = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
        guard AudioObjectGetPropertyData(mix, &a, 0, nil, &size, &list) == noErr,
              let uids = list?.takeRetainedValue() as? [String] else { return [] }
        return uids
    }

    static func destroyMix() {
        if let mix = mixDeviceID() { AudioHardwareDestroyAggregateDevice(mix) }
    }

    /// Creates a stacked aggregate so every member plays the same audio.
    /// A wired device is the clock master; the rest get drift correction.
    static func createMix(_ members: [OutputDevice]) throws -> AudioDeviceID {
        destroyMix()
        let master = members.first { $0.kind == .usb } ?? members.first { $0.kind == .headphoneJack }
            ?? members.first { $0.kind != .bluetooth } ?? members[0]
        let subDevices: [[String: Any]] = members.map {
            [kAudioSubDeviceUIDKey: $0.uid, kAudioSubDeviceDriftCompensationKey: $0.uid == master.uid ? 0 : 1]
        }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: mixName,
            kAudioAggregateDeviceUIDKey: mixUID,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceMainSubDeviceKey: master.uid,
            kAudioAggregateDeviceIsStackedKey: 1,
            kAudioAggregateDeviceIsPrivateKey: 0,
        ]
        var id: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr else { throw MixError.createFailed(status) }
        return id
    }

    // MARK: Change notifications

    static func observe(_ selectors: [AudioObjectPropertySelector], _ handler: @escaping () -> Void) {
        for selector in selectors {
            var a = address(selector)
            AudioObjectAddPropertyListenerBlock(system, &a, DispatchQueue.main) { _, _ in handler() }
        }
    }
}

enum MixError: LocalizedError {
    case createFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .createFailed(let status): return "Could not combine outputs (CoreAudio error \(status))."
        }
    }
}
