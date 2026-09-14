import SwiftUI
import AppKit

/// Loads the illustrations that are actually compiled into `Assets.xcassets`.
public enum AppArt: String {
    case cameraConnect   = "CameraConnect"
    case darkroomHero    = "DarkroomHero"
    case filmStrip       = "FilmStrip"

    @MainActor private static let cache = NSCache<NSString, NSImage>()

    @MainActor public var nsImage: NSImage? {
        if let cached = AppArt.cache.object(forKey: rawValue as NSString) {
            return cached
        }
        // Asset catalogs do not expose stable loose-file URLs in a packaged
        // app. `NSImage(named:)` is the supported lookup for both Debug and
        // release bundles.
        if let image = NSImage(named: NSImage.Name(rawValue)) {
            AppArt.cache.setObject(image, forKey: rawValue as NSString)
            return image
        }
        return nil
    }

    /// SwiftUI image, or `nil` if the asset is missing.
    @MainActor public var image: Image? {
        nsImage.map { Image(nsImage: $0) }
    }
}

// MARK: - Programmatic Vector Artworks for 2026 Sleek Visual Polish

public struct CameraHeroIllustration: View {
    @State private var pulse: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            // Ambient lens aura
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.fujiAmber.opacity(0.18), Theme.fujiRed.opacity(0.04), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 160
                    )
                )
                .frame(width: 320, height: 320)
                .scaleEffect(pulse ? 1.05 : 0.95)
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: pulse)

            // Machined camera body outline
            VStack(spacing: 0) {
                // Top deck rangefinder step
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.22), Color(white: 0.12)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 110, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                        )
                    Spacer()
                    // Shutter release & dial knobs
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.fujiRed)
                            .frame(width: 14, height: 14)
                            .shadow(color: Theme.fujiRed.opacity(0.6), radius: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(white: 0.35))
                            .frame(width: 24, height: 12)
                    }
                    .padding(.trailing, 16)
                }
                .frame(width: 280)

                // Main camera chassis
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.15), Color(white: 0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 280, height: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )

                    // Textured grip wrap
                    HStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(white: 0.05))
                            .frame(width: 60, height: 130)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
                            )
                            .padding(.leading, 10)
                        Spacer()
                    }
                    .frame(width: 280)

                    // Fujinon 23mm F2 Lens barrel
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(white: 0.28), Color(white: 0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 106, height: 106)
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.2))

                        Circle()
                            .fill(Color.black)
                            .frame(width: 86, height: 86)

                        // Glass element reflection
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Theme.cyanAccent.opacity(0.5),
                                        Theme.fujiAmber.opacity(0.2),
                                        Color.black
                                    ],
                                    center: .topLeading,
                                    startRadius: 5,
                                    endRadius: 50
                                )
                            )
                            .frame(width: 68, height: 68)
                            .overlay(
                                Image(systemName: "camera.aperture")
                                    .font(.system(size: 32, weight: .thin))
                                    .foregroundStyle(Color.white.opacity(0.7))
                            )
                    }
                }
            }
            .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 12)
        }
        .frame(height: 220)
        .onAppear { pulse = true }
    }
}

public struct DarkroomHeroIllustration: View {
    public init() {}

    public var body: some View {
        ZStack {
            // Ambient red/amber darkroom glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.fujiRed.opacity(0.25),
                            Theme.fujiAmber.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 20)

            // Film frame card mockup
            HStack(spacing: 12) {
                // Negative strip
                VStack(spacing: 6) {
                    ForEach(0..<4) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 8, height: 12)
                    }
                }
                .padding(.vertical, 8)
                .frame(width: 18)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Developing RAW canvas preview
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Theme.fujiAmber)
                        Text("X-TRANS V RAW PROCESSOR")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("40.2 MP")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.cyanAccent)
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.12, green: 0.14, blue: 0.18),
                                        Color(red: 0.08, green: 0.09, blue: 0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 100)

                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 38, weight: .ultraLight))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Theme.fujiAmber, Theme.fujiRed],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.glassElevatedBg)
                        .background(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.specularBorder, lineWidth: 0.8)
                )
                .frame(width: 260)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.specularGlowBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.5), radius: 20, y: 10)
        }
        .frame(height: 200)
    }
}
