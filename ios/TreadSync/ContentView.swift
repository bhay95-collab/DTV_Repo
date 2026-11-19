import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        let t = model.treadmill
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Form {
                Section("Treadmill") {
                    LabeledContent("Status", value: t.state.rawValue)
                    LabeledContent("Device", value: t.deviceName ?? "—")
                    LabeledContent("Speed", value: fmt(t.latest.speedKmh, "%.1f km/h"))
                    LabeledContent("Treadmill distance", value: fmt(t.latest.totalDistanceM, "%.0f m"))
                    Stepper(value: $model.manualInclinePercent, in: 0...15, step: 1) {
                        LabeledContent("Incline (set by hand)", value: String(format: "%.0f %%", model.manualInclinePercent))
                    }
                    LabeledContent("Treadmill time", value: t.latest.elapsedTimeS.map { clock($0) } ?? "—")
                    HStack {
                        Button("Reconnect") { t.connect() }
                        Spacer()
                        Button("Forget device", role: .destructive) { t.forgetDevice() }
                    }
                    .buttonStyle(.borderless)
                }

                Section("Workout") {
                    Picker("Type", selection: $model.activityChoice) {
                        ForEach(AppModel.ActivityChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let s = model.session {
                        LabeledContent("Time", value: clock(Int(s.duration(now: context.date))))
                        LabeledContent("Distance", value: String(format: "%.2f km", s.distanceM / 1000))
                        LabeledContent("Climb", value: String(format: "%.0f m", s.elevationGainM))
                        LabeledContent("Active energy (est.)", value: String(format: "%.0f kcal", s.activeKcal))
                        Button(s.isFinished ? "Retry save to Apple Health" : "Finish & save to Apple Health") {
                            model.finishAndSave()
                        }
                        .disabled(model.isSaving)
                        Button("Discard", role: .destructive) { model.discard() }
                            .disabled(model.isSaving)
                    } else {
                        Button("Start workout") { model.start() }
                    }
                    if let msg = model.message { Text(msg).font(.footnote) }
                }

                Section("Debug: last raw packet") {
                    Text(t.lastPacketHex.isEmpty ? "No data yet" : t.lastPacketHex)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func fmt(_ v: Double?, _ format: String) -> String {
        v.map { String(format: format, $0) } ?? "—"
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
