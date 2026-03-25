import SwiftUI

struct DebugBarOverlay: ViewModifier {
    @ObservedObject private var logger = DebugLogger.shared
    @State private var expanded = false

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if logger.isEnabled {
                debugBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var debugBar: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ladybug.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)

                    if let last = logger.entries.last {
                        Text(last.message)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)

                        if let d = last.duration {
                            Text(String(format: "%.1fs", d))
                                .font(.caption2.monospaced().bold())
                                .foregroundStyle(d > 5 ? .red : d > 2 ? .orange : .green)
                        }
                    } else {
                        Text("Debug actif")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    Text("\(logger.entries.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.65))

                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.88))
            }
            .buttonStyle(.plain)

            if expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(logger.entries.suffix(80)) { entry in
                                HStack(spacing: 4) {
                                    Text(entry.formattedTime)
                                        .foregroundStyle(.gray)
                                    Text(entry.category)
                                        .foregroundStyle(categoryColor(entry.category))
                                    if let d = entry.duration {
                                        Text(String(format: "%.1fs", d))
                                            .foregroundStyle(d > 5 ? .red : d > 2 ? .orange : .green)
                                    }
                                    Text(entry.message)
                                        .foregroundStyle(entry.isError ? .red : .white.opacity(0.92))
                                        .lineLimit(2)
                                }
                                .font(.system(size: 10, design: .monospaced))
                                .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 210)
                    .background(Color.black.opacity(0.92))
                    .onChange(of: logger.entries.count) { _, _ in
                        if let last = logger.entries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "HTTP":
            return .cyan
        case "Planning":
            return .orange
        case "BL":
            return .pink
        default:
            return .gray
        }
    }
}

extension View {
    func debugBar() -> some View {
        modifier(DebugBarOverlay())
    }

    @ViewBuilder
    func debugBar(if condition: Bool) -> some View {
        if condition {
            self.debugBar()
        } else {
            self
        }
    }
}
