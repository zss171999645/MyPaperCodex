import SwiftUI

enum PaperCodexTypography {
    static let defaultBodySize: CGFloat = 13
    static let fixedFontNoBoostThreshold: CGFloat = 24
    static let fixedFontSingleBoostThreshold: CGFloat = 20

    static func scaledFixedSize(_ size: CGFloat) -> CGFloat {
        if size >= fixedFontNoBoostThreshold {
            return size
        }
        if size >= fixedFontSingleBoostThreshold {
            return size + 1
        }
        return size + 2
    }
}

extension Font {
    static func paperCodexSystem(
        size: CGFloat,
        weight: Font.Weight? = nil,
        design: Font.Design? = nil
    ) -> Font {
        .system(size: PaperCodexTypography.scaledFixedSize(size), weight: weight, design: design)
    }
}

private struct PaperCodexTypographyScale: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.paperCodexSystem(size: PaperCodexTypography.defaultBodySize))
            .dynamicTypeSize(.xLarge)
    }
}

extension View {
    func paperCodexTypographyScale() -> some View {
        modifier(PaperCodexTypographyScale())
    }
}
