import Foundation

/// NSMetadataQuery 必须在带 RunLoop 的主线程使用，所以整体放在 MainActor。
@MainActor
final class SpotlightSearcher {
    private var active: NSMetadataQuery?

    func search(text: String, settings: FileSearchSettings, limit: Int = 300) async -> [FileHit] {
        cancel()
        let terms = FileQuery.terms(from: text)
        guard let str = FileQuery.predicateString(terms: terms, searchContent: settings.searchContent) else { return [] }
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(fromMetadataQueryString: str)
        q.searchScopes = settings.homeOnly ? [NSHomeDirectory()] : [NSMetadataQueryLocalComputerScope]
        q.sortDescriptors = [NSSortDescriptor(key: kMDItemLastUsedDate as String, ascending: false)]
        active = q

        let box = QueryBox(q)
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let gate = Gate(cont)
                let obs = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { _ in
                    MainActor.assumeIsolated { gate.fire() }
                }
                gate.cleanup = { NotificationCenter.default.removeObserver(obs) }
                box.gate = gate
                q.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { gate.fire() }
            }
        } onCancel: {
            Task { @MainActor in box.gate?.fire() }
        }

        q.disableUpdates()
        var hits: [FileHit] = []
        let count = min(q.resultCount, limit * 3)
        for i in 0..<count {
            guard let item = q.result(at: i) as? NSMetadataItem, let path = item.value(forAttribute: kMDItemPath as String) as? String else { continue }
            if FileQuery.isExcluded(path, patterns: settings.excludedPatterns) { continue }
            let name = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? (path as NSString).lastPathComponent
            let type = item.value(forAttribute: kMDItemContentType as String) as? String
            hits.append(FileHit(
                path: path, displayName: name, isDirectory: type == "public.folder" || type == "com.apple.package",
                lastUsed: item.value(forAttribute: kMDItemLastUsedDate as String) as? Date,
                modified: item.value(forAttribute: kMDItemContentModificationDate as String) as? Date
            ))
            if hits.count >= limit { break }
        }
        q.stop()
        if active === q { active = nil }
        return hits
    }

    func cancel() {
        active?.stop()
        active = nil
    }
}

@MainActor
private final class QueryBox {
    let query: NSMetadataQuery
    var gate: Gate?
    init(_ q: NSMetadataQuery) { query = q }
}

@MainActor
private final class Gate {
    private var cont: CheckedContinuation<Void, Never>?
    var cleanup: (() -> Void)?
    init(_ c: CheckedContinuation<Void, Never>) { cont = c }
    func fire() {
        guard let c = cont else { return }
        cont = nil
        cleanup?()
        cleanup = nil
        c.resume()
    }
}
