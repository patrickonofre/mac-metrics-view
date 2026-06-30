import SwiftUI

/// Full-screen SwiftUI view rendered inside every `LockOverlayWindow`.
/// Shows the countdown and the emergency-abort instruction.
struct LockOverlayView: View {
    @ObservedObject var lock: CleaningLockModel

    var body: some View {
        ZStack {
            // Solid pure black so dirt and smudges on the screen are easy to spot.
            Color.black
                .ignoresSafeArea()

            // Centered counter — dimmed so it doesn't wash out the black surface.
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))

                Text(countdownText)
                    .font(.system(size: 64, weight: .thin, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeInOut(duration: 0.3), value: lock.remaining)
            }
            .multilineTextAlignment(.center)

            // Very discreet abort hint, tucked at the bottom of the screen.
            VStack {
                Spacer()
                Text("Segure Esc por 3s para cancelar")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.18))
                    .padding(.bottom, 28)
            }
        }
    }

    private var countdownText: String {
        CleaningLockCountdownFormatter.string(
            forRemaining: lock.remaining,
            total: lock.settings.selectedDuration
        )
    }
}
