import Foundation

/// Per-file reader bookkeeping bounded to the active window. Stores a byte `offset` and a
/// reader-specific parse `State` per path, and evicts both once a file falls outside the
/// window — the invariant that keeps memory bounded and reactivation double-count-safe
/// (ADR-002, ADR-003).
///
/// `activeFiles(...)` enumerates the given roots with prefetched modification dates and
/// sizes, so dormant files cost one cheap `stat` and no file read. It returns only the files
/// whose mtime is within `window` of `now`, and in the same pass evicts the tracked state of
/// every file that is no longer active (dormant beyond `window`, or deleted). Because the
/// caller always passes `window == retentionTail`, any event re-emitted when an evicted file
/// later reactivates is already outside the backfill tail cutoff, so eviction can never
/// double-count (ADR-003).
///
/// Pure storage + scan: it performs no token parsing, store mutation, or display math.
struct ActiveFileSet<State> {
    struct Entry {
        var offset: UInt64
        var state: State
    }

    /// Per-file bookkeeping keyed by file path. After every `activeFiles(...)` pass its count
    /// equals the active-set size, never the historical file count.
    private(set) var entries: [String: Entry] = [:]

    private static var prefetchKeys: Set<URLResourceKey> {
        [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
    }

    /// Files under `roots` whose mtime is within `window` of `now`, paired with their
    /// prefetched size, AFTER evicting `entries` for any tracked file not in this active set.
    ///
    /// A regular file whose resource values cannot be read is treated as active (returned for
    /// reading) so correctness never depends on the optimization; a non-existent root is
    /// skipped. Multiple roots are supported (Claude passes one tree root; Codex passes recent
    /// date directories) and unioned.
    mutating func activeFiles(
        roots: [URL],
        window: TimeInterval,
        now: Date,
        fileManager: FileManager,
        matches: (URL) -> Bool
    ) -> [(url: URL, size: UInt64)] {
        let cutoff = now.addingTimeInterval(-window)
        let keys = Self.prefetchKeys

        var active: [(url: URL, size: UInt64)] = []
        var activePaths = Set<String>()

        for root in roots {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys)
            ) else { continue }

            for case let url as URL in enumerator where matches(url) {
                let values = try? url.resourceValues(forKeys: keys)

                // Skip directories when we can tell; an unreadable type falls through to the
                // active-treated path below (a stray directory there yields no events).
                if values?.isRegularFile == false { continue }

                let isActive: Bool
                if let mtime = values?.contentModificationDate {
                    isActive = mtime >= cutoff
                } else {
                    isActive = true   // unreadable mtime → read it; never depend on the optimization
                }
                guard isActive else { continue }

                active.append((url: url, size: Self.size(of: url, prefetched: values, fileManager: fileManager)))
                activePaths.insert(url.path)
            }
        }

        // Single-pass eviction: drop tracked state for every file absent from the active set
        // (dormant beyond the window, or deleted), so memory scales with the active set only.
        let stale = entries.keys.filter { !activePaths.contains($0) }
        for path in stale { entries[path] = nil }

        return active
    }

    /// Offset + state access used by the readers to seed, advance, and dedup per file.
    subscript(path: String) -> Entry? {
        get { entries[path] }
        set { entries[path] = newValue }
    }

    /// Prefetched size from the enumerator; falls back to a direct `stat` only when the
    /// prefetch is unavailable (rare), so the common path avoids the second `stat`.
    private static func size(of url: URL, prefetched: URLResourceValues?, fileManager: FileManager) -> UInt64 {
        if let size = prefetched?.fileSize {
            return UInt64(size)
        }
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let size = (attributes[.size] as? NSNumber)?.uint64Value {
            return size
        }
        return 0
    }
}
