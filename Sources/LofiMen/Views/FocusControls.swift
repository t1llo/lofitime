import LofiMenCore
import SwiftUI

/// The countdown itself is the editor. Return, Start, or leaving the field applies it.
struct FocusControls: View {
    @Environment(\.roomTheme) private var theme
    var model: AppModel
    var compact = false
    @FocusState private var editing: Bool

    private var input: String { model.durationInput ?? model.remainingText }
    private var valid: Bool { SessionDuration.parse(input) != nil }

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            HStack(spacing: 3) {
                ForEach(FocusMode.allCases, id: \.self) { mode in
                    Button {
                        editing = false
                        model.selectMode(mode)
                    } label: {
                        Text(mode.title).font(.room(size: compact ? 12 : 13, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: compact ? 34 : 40)
                            .foregroundStyle(model.timer.mode == mode ? theme.text : theme.text.opacity(compact ? 0.82 : 0.55))
                            .background(model.timer.mode == mode ? theme.accent.opacity(0.2) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).accessibilityAddTraits(model.timer.mode == mode ? .isSelected : [])
                }
            }.padding(3).background(.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))

            VStack(spacing: 2) {
                Group {
                    if model.timer.status == .running {
                        Text(model.remainingText).monospacedDigit()
                    } else {
                        TextField("25:00", text: Binding(
                            get: { input },
                            set: { model.durationInput = $0 == model.remainingText ? nil : $0 }
                        )).textFieldStyle(.plain)
                            .multilineTextAlignment(.center).focused($editing)
                            .onSubmit { if model.applyDurationInput() { editing = false } }
                            .accessibilityLabel("Session duration in minutes or mm:ss")
                            .accessibilityIdentifier("session-duration")
                    }
                }
                .font(.room(size: compact ? 52 : 68, weight: compact ? .semibold : .regular)).monospacedDigit().tracking(-1.5)
                .foregroundStyle(theme.text).frame(height: compact ? 62 : 83)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 3)

                if !valid && !input.isEmpty && model.timer.status != .running {
                    Text("Use minutes or mm:ss, from 0:01 to 180:00")
                        .font(.room(size: 10)).foregroundStyle(theme.amber)
                }
            }

            HStack(spacing: 9) {
                Button(action: toggleTimer) {
                    HStack(spacing: 8) {
                        Image(systemName: model.timer.status == .running ? "pause.fill" : "play.fill").font(.system(size: 10))
                        Text(model.timerActionTitle).font(.room(size: 12, weight: .semibold))
                    }.frame(maxWidth: .infinity).frame(height: compact ? 34 : 40)
                        .foregroundStyle(theme.background).background(theme.accent, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).disabled(!valid && model.timer.status != .running)
                    .opacity(!valid && model.timer.status != .running ? 0.5 : 1)
                    .help("\(model.timerActionTitle) · ⌘Return")

                OverlayIconButton(symbol: "arrow.counterclockwise", label: "Reset timer", size: compact ? 34 : 40) {
                    editing = false
                    model.resetTimer()
                }
            }
        }
        .onChange(of: model.timer.mode) { _, _ in editing = false }
        .onChange(of: editing) { _, focused in
            if !focused { model.applyDurationInput() }
        }
        .onDisappear { if editing { model.applyDurationInput() } }
    }

    private func toggleTimer() {
        model.toggleTimer()
        if model.durationInput == nil { editing = false }
    }
}
