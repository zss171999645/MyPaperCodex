import SwiftUI

struct SidebarRowButton: View {
    @State private var isHovering = false

    var title: String
    var systemImage: String
    var selected: Bool
    var depth: Int = 0
    var trailingReserve: CGFloat = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.78))
                Text(title)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth * 14) + 9)
            .padding(.trailing, 9 + trailingReserve)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: isHovering ? Color.black.opacity(0.08) : .clear, radius: 7, y: 3)
            .scaleEffect(isHovering ? 1.015 : 1, anchor: .center)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.14) : (isHovering ? Color(nsColor: .textBackgroundColor) : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? Color.accentColor.opacity(0.25) : Color.clear, lineWidth: 1)
            )
    }
}
