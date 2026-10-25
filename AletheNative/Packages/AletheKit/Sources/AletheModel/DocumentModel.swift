import AletheFoundation
import Foundation
import Observation

@Observable
@MainActor
public final class DocumentModel<Document: VersionedDocument> {
    public private(set) var document: Document
    public let loadOutcome: DocumentLoadOutcome?
    public let loadError: DocumentStoreError?

    @ObservationIgnored private let store: DocumentStore<Document>
    @ObservationIgnored private var revision: UInt64 = 0

    private init(store: DocumentStore<Document>, document: Document, outcome: DocumentLoadOutcome?, error: DocumentStoreError?) {
        self.store = store
        self.document = document
        loadOutcome = outcome
        loadError = error
    }

    public static func load(from url: URL) async -> DocumentModel {
        let store = DocumentStore<Document>(url: url)
        let name = url.lastPathComponent
        do {
            let (document, outcome) = try await store.load()
            if case .migrated(let version, _) = outcome { AppLog.info(.persistence, "\(name) migrated from version \(version)") } else if case .recoveredFromCorruption(let movedTo) = outcome { AppLog.record(.warning, .persistence, "\(name) was unreadable; moved to \(movedTo.lastPathComponent)") } else if case .fresh = outcome {
            } else {
            }
            return DocumentModel(store: store, document: document, outcome: outcome, error: nil)
        } catch let error as DocumentStoreError {
            AppLog.record(.error, .persistence, "\(name) not loaded: \(error)")
            return DocumentModel(store: store, document: Document.initial, outcome: nil, error: error)
        } catch {
            AppLog.record(.error, .persistence, "\(name) not loaded: \(error.localizedDescription)")
            return DocumentModel(store: store, document: Document.initial, outcome: nil, error: nil)
        }
    }

    public func update(_ body: (inout Document) -> Void) {
        var next = document
        body(&next)
        guard next != document else { return }
        replace(with: next)
    }

    public func update(undoManager: UndoManager?, actionName: String, _ body: (inout Document) -> Void) {
        let before = document
        update(body)
        guard document != before else { return }
        registerUndo(undoManager, restoring: before, actionName: actionName)
    }

    private func registerUndo(_ undoManager: UndoManager?, restoring snapshot: Document, actionName: String) {
        guard let undoManager else { return }
        let current = document
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.replace(with: snapshot)
                model.registerUndo(undoManager, restoring: current, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }

    private func replace(with next: Document) {
        document = next
        revision += 1
        let snapshot = next
        let revision = revision
        Task { await store.scheduleSave(snapshot, revision: revision) }
    }

    public func flush() async {
        revision += 1
        try? await store.save(document, revision: revision)
    }
}

public typealias WorkspaceModel = DocumentModel<WorkspaceDocument>
public typealias PreferencesModel = DocumentModel<PreferencesDocument>
