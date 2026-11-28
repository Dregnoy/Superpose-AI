import SwiftUI

struct WatchContentView: View {
    @State private var client = WatchSessionClient()

    private var ringColor: Color {
        if let score = client.matchScore, score >= client.threshold {
            return .green
        }
        return client.isShotReady ? .green : .cyan
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 6)
                if let score = client.matchScore {
                    Circle()
                        .trim(from: 0, to: CGFloat(min(100, max(0, score))) / 100.0)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.2), value: score)
                    VStack(spacing: 0) {
                        Text("%\(score)")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(ringColor)
                        Text("Poz")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3)
                        .foregroundStyle(ringColor)
                }
            }
            .frame(width: 72, height: 72)

            Text(client.lightingMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Button {
                    client.sendCaptureCommand(timerSeconds: 0)
                } label: {
                    Label("Çek", systemImage: "camera.shutter.button")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ringColor)
                .foregroundStyle(.black)

                Button {
                    client.sendCaptureCommand(timerSeconds: 3)
                } label: {
                    Text("3s")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
            }
        }
        .padding(.horizontal, 6)
    }
}
