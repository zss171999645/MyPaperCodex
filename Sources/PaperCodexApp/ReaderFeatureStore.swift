import Foundation
import PaperCodexCore

@MainActor
final class ReaderFeatureStore: ObservableObject {
    @Published var readerReturnRoute: AppRoute = .library
    @Published var selectedPaper: Paper?
    @Published var readerTabState = ReaderTabState()
    @Published var selectedSession: PaperSession?
    @Published var sessions: [PaperSession] = []
    @Published var recentSessions: [PaperSession] = []
    @Published var recentSessionPapersByID: [String: [Paper]] = [:]
    @Published var selectedSessionPanelTab: SessionPanelTab = .chat
    @Published var messages: [ChatMessage] = []
    @Published var currentSelection: PDFSelectionInfo?
    @Published var pdfJumpTarget: PDFJumpTarget?
    @Published var readerPosition: PaperReaderPosition?
    @Published var citationReturnPoint: CitationReturnPoint?
    @Published var pdfKitCommand: PDFKitCommand?
    @Published var pdfDocumentStatus: PDFDocumentStatus?
}
