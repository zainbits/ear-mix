import AppKit
import CoreAudio
import Foundation

@MainActor
final class MixController: ObservableObject {
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var isCombined = false
    @Published private(set) var memberCount = 0
    @Published private(set) var currentOutputName = ""
    @Published private(set) var lastError: String?
    @Published private(set) var selected: Set<String>

    private let defaults = UserDefaults.standard
    private var seen: Set<String>
    private var mutedLevels: [String: Int] = [:]
    /// Sliders the user is dragging; periodic refreshes leave these alone.
    private var editing: Set<String> = []
    private var refreshPending = false
    private var timer: Timer?

    private enum Key {
        static let selected = "selectedUIDs"
        static let seen = "seenUIDs"
        static let previousOutput = "previousOutputUID"
    }

    init() {
        selected = Set(defaults.stringArray(forKey: Key.selected) ?? [])
        seen = Set(defaults.stringArray(forKey: Key.seen) ?? [])
        reload()

        CoreAudioDevices.observe([kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice]) { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        // Hardware buttons on earphones change volume behind our back; keep sliders honest.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVolumes() }
        }
    }

    var selectedCount: Int { devices.filter { selected.contains($0.uid) }.count }

    var statusLine: String {
        if isCombined { return "Playing on \(memberCount) devices" }
        return currentOutputName.isEmpty ? "Off" : "Off · \(currentOutputName)"
    }

    // MARK: Actions

    func setCombined(_ on: Bool) {
        lastError = nil
        if on { combine() } else { separate() }
        reload()
    }

    func toggleSelection(_ device: OutputDevice) {
        if selected.contains(device.uid) { selected.remove(device.uid) } else { selected.insert(device.uid) }
        defaults.set(Array(selected), forKey: Key.selected)
        if isCombined { syncMix() }
    }

    func setVolume(_ device: OutputDevice, _ value: Int) {
        CoreAudioDevices.setVolume(of: device.id, to: value)
        mutedLevels[device.uid] = nil
        if let i = devices.firstIndex(where: { $0.uid == device.uid }) { devices[i].volume = value }
    }

    func toggleMute(_ device: OutputDevice) {
        guard let volume = device.volume else { return }
        if volume == 0 {
            setVolume(device, mutedLevels[device.uid] ?? 50)
        } else {
            setVolume(device, 0)
            mutedLevels[device.uid] = volume
        }
    }

    func setEditing(_ device: OutputDevice, _ isEditing: Bool) {
        if isEditing { editing.insert(device.uid) } else { editing.remove(device.uid) }
    }

    func quit() {
        if isCombined { separate() }
        NSApplication.shared.terminate(nil)
    }

    // MARK: Mixing

    private func combine() {
        let members = devices.filter { selected.contains($0.uid) }
        guard members.count >= 2 else {
            lastError = "Tick at least two outputs to combine."
            return
        }
        let current = CoreAudioDevices.defaultOutput()
        if CoreAudioDevices.mixDeviceID() != current {
            defaults.set(CoreAudioDevices.uid(of: current), forKey: Key.previousOutput)
        }
        do {
            let mix = try CoreAudioDevices.createMix(members)
            CoreAudioDevices.setDefaultOutput(mix)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func separate() {
        CoreAudioDevices.destroyMix()
        let previous = defaults.string(forKey: Key.previousOutput).flatMap(CoreAudioDevices.deviceID(forUID:))
        let fallback = devices.first { selected.contains($0.uid) && $0.kind != .bluetooth }?.id
            ?? devices.first { $0.kind == .speakers }?.id
        if let target = previous ?? fallback { CoreAudioDevices.setDefaultOutput(target) }
    }

    /// Rebuild the mix when the ticked, connected set no longer matches its members.
    private func syncMix() {
        let wanted = devices.filter { selected.contains($0.uid) }.map(\.uid)
        guard Set(wanted) != Set(CoreAudioDevices.mixMemberUIDs()) else { return }
        if wanted.count >= 2 {
            combine()
        } else {
            separate()
            lastError = "Combining stopped: fewer than two outputs left."
        }
        reload()
    }

    // MARK: State

    private func scheduleReload() {
        guard !refreshPending else { return }
        refreshPending = true
        // Bluetooth connects fire several notifications in a burst; settle first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshPending = false
                self.reload()
                if self.isCombined { self.syncMix() }
            }
        }
    }

    private func reload() {
        let found = CoreAudioDevices.physicalOutputs()
        for device in found where !seen.contains(device.uid) {
            seen.insert(device.uid)
            if device.isEarphone { selected.insert(device.uid) }
        }
        defaults.set(Array(seen), forKey: Key.seen)
        defaults.set(Array(selected), forKey: Key.selected)

        devices = found.sorted { order($0) < order($1) }
        let current = CoreAudioDevices.defaultOutput()
        isCombined = CoreAudioDevices.mixDeviceID() == current
        memberCount = isCombined ? CoreAudioDevices.mixMemberUIDs().count : 0
        currentOutputName = found.first { $0.id == current }?.name ?? ""
    }

    private func refreshVolumes() {
        for i in devices.indices where !editing.contains(devices[i].uid) {
            let volume = CoreAudioDevices.volume(of: devices[i].id)
            if devices[i].volume != volume { devices[i].volume = volume }
        }
    }

    private func order(_ device: OutputDevice) -> Int {
        switch device.kind {
        case .usb: return 0
        case .headphoneJack: return 1
        case .bluetooth: return 2
        case .other: return 3
        case .speakers: return 4
        case .display: return 5
        }
    }
}
