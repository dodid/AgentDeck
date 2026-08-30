import SwiftUI

struct StreamingStatusView: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary.opacity(phase == index ? 0.9 : 0.35))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(360))
                phase = (phase + 1) % 3
            }
        }
    }
}

#Preview {
    StreamingStatusView()
}
