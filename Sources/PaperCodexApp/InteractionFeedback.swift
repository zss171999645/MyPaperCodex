import PaperCodexCore
import SwiftUI

enum InteractionNoticeKind: Equatable {
    case success
    case info
    case warning
    case error

    var systemImage: String {
        switch self {
        case .success:
            "checkmark.circle.fill"
        case .info:
            "info.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success:
            .green
        case .info:
            .blue
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

struct InteractionNotice: Identifiable, Equatable {
    var id = UUID()
    var kind: InteractionNoticeKind
    var title: String
    var message: String
    var createdAt = Date()
    var autoDismissAfter: TimeInterval? = 4
}

struct AppOperationStatus: Equatable {
    var title: String
    var detail: String
    var systemImage: String
    var tint: Color
}

struct CacheStorageSummary: Equatable {
    var libraryBytes: Int64 = 0
    var disposableCacheBytes: Int64 = 0
    var arxivCacheBytes: Int64 = 0
    var thumbnailBytes: Int64 = 0
    var refreshedAt: Date?

    var totalCacheBytes: Int64 {
        disposableCacheBytes + arxivCacheBytes + thumbnailBytes
    }

    var detailText: String {
        "Library \(Self.formatBytes(libraryBytes)) · Cache \(Self.formatBytes(totalCacheBytes))"
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct CitationReturnPoint: Equatable {
    var paperID: String
    var paperTitle: String
    var position: PaperReaderPosition
    var label: String
}

enum PDFKitCommandKind: Equatable {
    case zoomIn
    case zoomOut
    case fitWidth
    case fitPage
    case previousPage
    case nextPage
    case restorePosition(PaperReaderPosition)
}

struct PDFKitCommand: Identifiable, Equatable {
    var id = UUID()
    var kind: PDFKitCommandKind
}

struct PDFDocumentStatus: Equatable {
    var pageIndex: Int
    var pageCount: Int
    var scaleFactor: Double
}

enum DiscoverPaperInteractionState: Equatable {
    case queued
    case processing
    case processed
    case cached
    case failed
    case cancelled
    case downloading
    case pdfCached
}

struct InteractionNoticeStack: View {
    var notices: [InteractionNotice]
    var onDismiss: (InteractionNotice.ID) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(notices) { notice in
                InteractionNoticeCard(notice: notice) {
                    onDismiss(notice.id)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(14)
        .frame(maxWidth: 420, alignment: .topTrailing)
        .animation(.spring(response: 0.22, dampingFraction: 0.86), value: notices)
    }
}

private struct InteractionNoticeCard: View {
    var notice: InteractionNotice
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.kind.systemImage)
                .foregroundStyle(notice.kind.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(.paperCodexSystem(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !notice.message.isEmpty {
                    Text(notice.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.paperCodexSystem(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(notice.kind.tint.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 6)
    }
}

struct GlobalOperationStatusView: View {
    var status: AppOperationStatus

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Image(systemName: status.systemImage)
                .foregroundStyle(status.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.caption.weight(.semibold))
                Text(status.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(status.tint.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.title). \(status.detail)")
    }
}
