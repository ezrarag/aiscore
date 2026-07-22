import SwiftUI

struct PulseView: View {
    @Environment(ScoreStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Room pulse", systemImage: "person.3.sequence.fill").font(.headline).padding()
            Divider()
            if store.pulses.isEmpty {
                ContentUnavailableView("The room is listening", systemImage: "waveform", description: Text("Student reflections appear here during a live session."))
            } else {
                List(store.pulses) { pulse in VStack(alignment: .leading) { Text(pulse.response); Text(pulse.displayName).font(.caption).foregroundStyle(.secondary) } }
            }
        }
    }
}

