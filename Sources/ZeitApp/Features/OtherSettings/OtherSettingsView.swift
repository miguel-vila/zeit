import ComposableArchitecture
import SwiftUI

struct OtherSettingsView: View {
    @Bindable var store: StoreOf<OtherSettingsFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Schedule")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("When should this machine track? Always, or only inside a list of windows.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            ScrollView {
                ScheduleEditorView(
                    state: store.editor,
                    onSetAlways: { store.send(.setAlways($0)) },
                    onAddWindow: { store.send(.addWindow) },
                    onRemoveWindow: { store.send(.removeWindow($0)) },
                    onChangeWindow: { store.send(.changeWindow($0)) },
                    onSetInterval: { store.send(.setInterval($0)) },
                    onSetSkipOnBattery: { store.send(.setSkipOnBattery($0)) }
                )
            }

            // Buttons
            HStack {
                Spacer()

                Button("Done") {
                    store.send(.done)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(minWidth: 500, minHeight: 420)
        .task {
            await store.send(.task).finish()
        }
    }

}
