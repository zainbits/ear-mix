import AppKit
import SwiftUI

@main
struct EarMixApp: App {
    @StateObject private var controller = MixController()

    var body: some Scene {
        MenuBarExtra {
            MixPanel(controller: controller)
        } label: {
            Image(systemName: controller.isCombined ? "headphones.circle.fill" : "headphones")
                .accessibilityLabel(controller.isCombined ? "EarMix: combined" : "EarMix: off")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MixPanel: View {
    @ObservedObject var controller: MixController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EarMix").font(.headline)
                    Text(controller.statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("Combine", isOn: Binding(
                    get: { controller.isCombined },
                    set: { controller.setCombined($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!controller.isCombined && controller.selectedCount < 2)
                .help(controller.isCombined ? "Stop combining" : "Play on all ticked outputs")
            }

            Divider()

            if controller.devices.isEmpty {
                Text("No outputs connected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(controller.devices) { device in
                DeviceRow(controller: controller, device: device)
            }

            if let error = controller.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                } label: {
                    Label("Sound Settings", systemImage: "gearshape")
                }
                Spacer()
                Button {
                    controller.quit()
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 320)
    }
}

private struct DeviceRow: View {
    @ObservedObject var controller: MixController
    let device: OutputDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { controller.selected.contains(device.uid) },
                    set: { _ in controller.toggleSelection(device) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Include in combined output")

                Image(systemName: device.symbol)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)

                Text(device.name)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text(device.kindLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let volume = device.volume {
                HStack(spacing: 6) {
                    Button {
                        controller.toggleMute(device)
                    } label: {
                        Image(systemName: speakerSymbol(volume))
                            .frame(width: 18, height: 14)
                    }
                    .buttonStyle(.borderless)
                    .help(volume == 0 ? "Unmute" : "Mute")

                    Slider(
                        value: Binding(
                            get: { Double(volume) },
                            set: { controller.setVolume(device, Int($0.rounded())) }
                        ),
                        in: 0...100,
                        onEditingChanged: { controller.setEditing(device, $0) }
                    )
                    .controlSize(.small)

                    Text("\(volume)%")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.leading, 26)
            } else {
                Text("Fixed volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 52)
            }
        }
        .padding(.vertical, 2)
    }

    private func speakerSymbol(_ volume: Int) -> String {
        switch volume {
        case 0: return "speaker.slash.fill"
        case 1..<34: return "speaker.wave.1.fill"
        case 34..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
