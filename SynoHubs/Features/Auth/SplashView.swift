import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0
    @State private var glowRadius: CGFloat = 0

    var onFinished: () -> Void

    var body: some View {
        ZStack {
            Color.synoBackground.ignoresSafeArea()

            // Ambient glow
            Circle()
                .fill(Color.synoPrimaryContainer.opacity(0.08))
                .frame(width: 300)
                .blur(radius: 80)

            VStack(spacing: 16) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(colors: [.synoPrimary, .synoPrimaryContainer],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .scaleEffect(scale)
                    .shadow(color: .synoPrimaryContainer.opacity(0.4), radius: glowRadius, y: 2)

                Text("SynoHub")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.synoOnSurface)
                    .opacity(opacity)

                Text("Synology NAS Management")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.synoOnSurfaceVariant)
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                scale = 1.0
            }
            withAnimation(.easeIn(duration: 0.6).delay(0.3)) {
                opacity = 1
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowRadius = 30
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                onFinished()
            }
        }
    }
}
