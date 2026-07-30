import SwiftUI

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
                Toggle("Send automatically after paste", isOn: $model.autoSend)
                Toggle("Start at login", isOn: Binding(
                    get: { model.startAtLogin },
                    set: { model.setStartAtLogin($0) }
                ))
            }

            Text("Sending is manual by default. With auto-send on, the screenshot reaches Anthropic the moment Return fires.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { model.refreshStartAtLogin() }
    }
}
