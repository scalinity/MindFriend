// MindFriend Certificate Unfurl Effect
// Scroll/diploma unfurl animation with gold seal

import SwiftUI

/// Diploma-style certificate that unfurls vertically with seal stamp
struct CertificateUnfurlEffect: View {
    let programName: String
    let certificateNumber: String
    let completionDate: Date
    let onSealStamp: (() -> Void)?

    @State private var unfurlScale: CGFloat = 0.1
    @State private var unfurlOpacity: Double = 0
    @State private var showSeal = false
    @State private var sealScale: CGFloat = 0.3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let goldColor = Color(red: 0.85, green: 0.65, blue: 0.13)
    private let creamColor = Color(red: 1.0, green: 0.98, blue: 0.94)

    init(
        programName: String,
        certificateNumber: String,
        completionDate: Date = Date(),
        onSealStamp: (() -> Void)? = nil
    ) {
        self.programName = programName
        self.certificateNumber = certificateNumber
        self.completionDate = completionDate
        self.onSealStamp = onSealStamp
    }

    var body: some View {
        ZStack {
            // Certificate body (diploma scroll)
            VStack(spacing: 0) {
                // Top rolled edge
                CertificateRollEdge()
                    .fill(
                        LinearGradient(
                            colors: [creamColor.opacity(0.8), creamColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 20)

                // Main certificate body
                VStack(spacing: 16) {
                    // Decorative top border
                    Rectangle()
                        .fill(goldColor)
                        .frame(height: 3)
                        .padding(.horizontal, 20)

                    // Title
                    Text("Certificate of Completion")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(goldColor.opacity(0.8))
                        .tracking(2)

                    // Program name
                    Text(programName)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Date
                    Text(completionDate.formatted(date: .long, time: .omitted))
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(.gray)

                    // Certificate number
                    Text(certificateNumber)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.gray.opacity(0.6))
                        .padding(.top, 8)

                    // Decorative bottom border
                    Rectangle()
                        .fill(goldColor)
                        .frame(height: 3)
                        .padding(.horizontal, 20)
                }
                .padding(.vertical, 24)
                .frame(width: 280)
                .background(creamColor)

                // Bottom rolled edge
                CertificateRollEdge()
                    .fill(
                        LinearGradient(
                            colors: [creamColor, creamColor.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 20)
                    .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
            }
            .frame(width: 280)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            .scaleEffect(x: 1, y: unfurlScale)
            .opacity(unfurlOpacity)

            // Gold seal
            if showSeal {
                ZStack {
                    // Seal base
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [goldColor, goldColor.opacity(0.8)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                        .frame(width: 60, height: 60)
                        .shadow(color: goldColor.opacity(0.5), radius: 8)

                    // Seal ridges
                    ForEach(0..<12, id: \.self) { index in
                        Rectangle()
                            .fill(goldColor.opacity(0.3))
                            .frame(width: 2, height: 30)
                            .offset(y: -15)
                            .rotationEffect(.degrees(Double(index) * 30))
                    }

                    // Seal icon
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                .scaleEffect(sealScale)
                .offset(y: 80)
            }
        }
        .onAppear {
            if reduceMotion {
                unfurlScale = 1
                unfurlOpacity = 1
                showSeal = true
                sealScale = 1
            } else {
                animateUnfurl()
            }
        }
    }

    private func animateUnfurl() {
        // Certificate unfurls
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            unfurlScale = 1
            unfurlOpacity = 1
        }

        // Seal stamps down
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showSeal = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                sealScale = 1
            }
            HapticManager.certificateSeal()
            onSealStamp?()
        }
    }
}

// MARK: - Certificate Roll Edge Shape

/// Curved edge shape for scroll/diploma effect
struct CertificateRollEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

// MARK: - Preview

#Preview("Certificate Unfurl") {
    ZStack {
        Color.black.ignoresSafeArea()
        CertificateUnfurlEffect(
            programName: "Anxiety Relief Program",
            certificateNumber: "MF-A1B2C3D4"
        )
    }
}

#Preview("Sleep Program") {
    ZStack {
        LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        CertificateUnfurlEffect(
            programName: "Better Sleep in 21 Days",
            certificateNumber: "MF-SLEEP123"
        )
    }
}
