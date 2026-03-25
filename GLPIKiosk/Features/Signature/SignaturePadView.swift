// GLPIKiosk — SignaturePadView.swift
// Pad de signature : Canvas UIKit wrappé en SwiftUI.
// Produit une image PNG encodée en base64.

import SwiftUI

struct SignaturePadView: View {
    @Binding var signatureB64: String?
    var strokeColor: Color = .black
    var strokeWidth: CGFloat = 3

    @State private var paths: [DrawPath] = []
    @State private var currentPath = DrawPath()

    var body: some View {
        ZStack {
            // Bordure visible sans fond blanc
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(.systemGray4), lineWidth: 1.5)
                .shadow(color: .black.opacity(0.07), radius: 4, x: 0, y: 2)

            // Canvas de dessin
            Canvas { context, size in
                for path in paths + [currentPath] {
                    var p = Path()
                    guard let first = path.points.first else { continue }
                    p.move(to: first)
                    for pt in path.points.dropFirst() {
                        p.addLine(to: pt)
                    }
                    context.stroke(
                        p,
                        with: .color(strokeColor),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        currentPath.points.append(value.location)
                    }
                    .onEnded { _ in
                        paths.append(currentPath)
                        currentPath = DrawPath()
                        exportSignature()
                    }
            )
            .cornerRadius(12)

            // Placeholder
            if paths.isEmpty && currentPath.points.isEmpty {
                Text("Signez ici")
                    .font(.title2)
                    .foregroundStyle(.gray.opacity(0.4))
                    .allowsHitTesting(false)
            }

            // Bouton effacer
            VStack {
                HStack {
                    Spacer()
                    Button {
                        paths      = []
                        currentPath = DrawPath()
                        signatureB64 = nil
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.footnote.weight(.bold))
                            .padding(8)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                    .padding(10)
                }
                Spacer()
            }
        }
    }

    var isEmpty: Bool { paths.isEmpty }

    // MARK: - Export

    private func exportSignature() {
        guard !paths.isEmpty else { signatureB64 = nil; return }

        let size = CGSize(width: 600, height: 200)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in

            UIColor.black.setStroke()
            for path in paths {
                guard let first = path.points.first else { continue }
                let bpath = UIBezierPath()
                bpath.lineWidth      = strokeWidth
                bpath.lineCapStyle   = .round
                bpath.lineJoinStyle  = .round
                bpath.move(to: first)
                for pt in path.points.dropFirst() {
                    bpath.addLine(to: pt)
                }
                bpath.stroke()
            }
        }

        if let data = image.pngData() {
            signatureB64 = "data:image/png;base64," + data.base64EncodedString()
        }
    }
}

// MARK: - DrawPath

private struct DrawPath {
    var points: [CGPoint] = []
}
