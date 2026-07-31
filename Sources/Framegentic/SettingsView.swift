import SwiftUI
import FramegenticKit

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Capture Shortcut")
                    .font(.headline)
                HStack(spacing: 10) {
                    ShortcutRecorderField(
                        idleTitle: model.hotKeyConfig.displayString,
                        onRecord: { model.apply($0) },
                        onBeginRecording: { model.beginRecording() },
                        onEndRecording: { model.endRecording() }
                    )
                    .frame(width: 200, height: 26)

                    Button("Reset to Default") { model.resetToDefault() }
                        .disabled(!model.canResetToDefault)
                }
                if let error = model.shortcutError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !model.hotKeyRegistered {
                    Text("\(model.hotKeyConfig.displayString) could not be registered. Pick another.")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Picker("Deliver to", selection: Binding(
                    get: { model.deliveryTarget.id },
                    set: { id in
                        if let target = TargetRegistry.target(id: id) { model.deliveryTarget = target }
                    }
                )) {
                    ForEach(TargetRegistry.all) { target in
                        Text(target.displayName).tag(target.id)
                    }
                }
                .pickerStyle(.menu)

                if model.deliveryTarget.autoPaste {
                    Toggle("Send automatically after paste", isOn: $model.autoSend)
                    Text("Pasting into \(model.deliveryTarget.displayName) needs Accessibility permission.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Captures go to the clipboard. Paste them wherever you like with ⌘V — no extra permission needed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Start at login", isOn: Binding(
                    get: { model.startAtLogin },
                    set: { model.setStartAtLogin($0) }
                ))
            }

            if model.deliveryTarget.autoPaste {
                Text("Sending is manual by default. With auto-send on, the capture is delivered and submitted to \(model.deliveryTarget.displayName) the moment Return fires — there's no undo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { model.refreshStartAtLogin() }
    }
}
