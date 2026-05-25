import SwiftUI

struct PaperCodexToolbarButton: View {
    @State private var isHovering = false

    var title: String
    var systemImage: String
    var tint: Color = .blue
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(LocalizedStringKey(title))
                    .lineLimit(1)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.paperCodexSystem(size: 12.5, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(disabled ? Color.secondary.opacity(0.55) : (isHovering ? tint : Color.primary.opacity(0.82)))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(disabled ? Color(nsColor: .controlBackgroundColor).opacity(0.55) : (isHovering ? tint.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(disabled ? Color.black.opacity(0.06) : (isHovering ? tint.opacity(0.45) : Color.black.opacity(0.10)), lineWidth: 1)
                    )
            )
            .shadow(color: isHovering && !disabled ? tint.opacity(0.18) : .clear, radius: 7, y: 3)
            .scaleEffect(isHovering && !disabled ? 1.025 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

struct PaperCodexIconButton: View {
    var title: String
    var systemImage: String
    var tint: Color = .secondary
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.paperCodexSystem(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.45) : tint)
        .disabled(disabled)
        .help(title)
        .accessibilityLabel(title)
    }
}
