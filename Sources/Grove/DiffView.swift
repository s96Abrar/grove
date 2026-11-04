import SwiftUI

enum DiffLineKind { case context, addition, deletion, hunkHeader, meta }

struct DiffLine: Identifiable {
    let id: Int
    let kind: DiffLineKind
    let text: String
    let oldNumber: Int?
    let newNumber: Int?
}

struct DiffHunk: Identifiable {
    let id: Int
    let header: String
    let lines: [DiffLine]
}

struct DiffFile: Identifiable {
    let id: String
    let path: String
    let oldPath: String?
    let binary: Bool
    let newFile: Bool
    let deletedFile: Bool
    let renamed: Bool
    let hunks: [DiffHunk]
    var metadata: [String] = []
    /// Precomputed at parse time so views never rescan every line during
    /// body evaluation.
    let additions: Int
    let deletions: Int
}

struct SplitRow: Identifiable {
    let id: Int
    let left: DiffLine?
    let right: DiffLine?
}

enum GitDiffParser {
    /// Git quotes control/non-ASCII UTF-8 bytes using C escapes.
    static func decodedPath(_ raw: String, stripPrefix: Bool = false) -> String {
        var path = raw
        if stripPrefix, let delimiter = path.firstIndex(of: "\t") { path = String(path[..<delimiter]) }
        if path.first == "\"", path.last == "\"" {
            let bytes = Array(path.dropFirst().dropLast().utf8)
            var output: [UInt8] = [], index = 0
            let escapes: [UInt8: UInt8] = [97: 7, 98: 8, 116: 9, 110: 10, 118: 11, 102: 12, 114: 13, 92: 92, 34: 34]
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                guard byte == 92, index < bytes.count else { output.append(byte); continue }
                let next = bytes[index]
                if (48...55).contains(next) {
                    var value = 0, count = 0
                    while index < bytes.count, count < 3, (48...55).contains(bytes[index]) {
                        value = value * 8 + Int(bytes[index] - 48); index += 1; count += 1
                    }
                    output.append(UInt8(truncatingIfNeeded: value))
                } else { output.append(escapes[next] ?? next); index += 1 }
            }
            path = String(decoding: output, as: UTF8.self)
        }
        if stripPrefix && (path.hasPrefix("a/") || path.hasPrefix("b/")) { return String(path.dropFirst(2)) }
        return path
    }

    private static func headerPaths(_ header: String) -> (String, String) {
        let text = String(header.dropFirst("diff --git ".count))
        if text.first == "\"" {
            var escaped = false
            for index in text.indices.dropFirst() {
                let character = text[index]
                if character == "\"" && !escaped {
                    let after = text.index(after: index)
                    return (decodedPath(String(text[..<after]), stripPrefix: true),
                            decodedPath(text[after...].trimmingCharacters(in: .whitespaces), stripPrefix: true))
                }
                if character == "\\" { escaped.toggle() } else { escaped = false }
            }
        }
        // Spaces alone are not quoted by Git. Same-path headers can be resolved
        // by matching both halves; rename headers subsequently supply exact names.
        var search = text.startIndex
        var fallback: (String, String)?
        while search < text.endIndex, let boundary = text.range(of: " b/", range: search..<text.endIndex) {
            let pair = (decodedPath(String(text[..<boundary.lowerBound]), stripPrefix: true),
                        decodedPath(String(text[text.index(after: boundary.lowerBound)...]), stripPrefix: true))
            if pair.0 == pair.1 { return pair }
            if fallback == nil { fallback = pair }
            search = boundary.upperBound
        }
        if let boundary = text.range(of: " \"b/") {
            return (decodedPath(String(text[..<boundary.lowerBound]), stripPrefix: true),
                    decodedPath(String(text[text.index(after: boundary.lowerBound)...]), stripPrefix: true))
        }
        return fallback ?? ("", "")
    }

    static func parse(_ raw: String) -> [DiffFile] {
        guard raw.hasPrefix("diff --git") else { return [] }
        let lines = raw.components(separatedBy: "\n")
        var files: [DiffFile] = []
        var index = 0
        while index < lines.count {
            guard lines[index].hasPrefix("diff --git ") else { index += 1; continue }
            var (oldPath, path) = headerPaths(lines[index])
            var (binary, newFile, deletedFile, renamed) = (false, false, false, false)
            var hunks: [DiffHunk] = []
            var metadata: [String] = []
            var hunkHeader = ""
            var hunkLines: [DiffLine] = []
            var oldCounter = 0, newCounter = 0, lineID = 0
            var additions = 0, deletions = 0
            func flushHunk() {
                if !hunkLines.isEmpty || !hunkHeader.isEmpty {
                    hunks.append(DiffHunk(id: hunks.count, header: hunkHeader, lines: hunkLines))
                    hunkHeader = ""; hunkLines = []
                }
            }
            index += 1
            while index < lines.count {
                let l = lines[index]
                if l.hasPrefix("diff --git ") { break }
                if !hunkLines.isEmpty || !hunkHeader.isEmpty, l.hasPrefix(" ") || l.hasPrefix("+") || l.hasPrefix("-") || l.hasPrefix("\\") {
                    // Content line inside a hunk (checked first: '+', '-' can
                    // legitimately begin content, e.g. "+   +++ b/foo").
                    var oldNo: Int?; var newNo: Int?
                    let body = l.hasPrefix("\\") ? l : String(l.dropFirst())
                    switch l.first {
                    case " ": oldNo = oldCounter; newNo = newCounter; oldCounter += 1; newCounter += 1
                    case "+": newNo = newCounter; newCounter += 1
                    case "-": oldNo = oldCounter; oldCounter += 1
                    default: break
                    }
                    let kind: DiffLineKind = l.hasPrefix(" ") ? .context : (l.hasPrefix("+") ? .addition : (l.hasPrefix("-") ? .deletion : .meta))
                    if kind == .addition { additions += 1 } else if kind == .deletion { deletions += 1 }
                    hunkLines.append(DiffLine(id: lineID, kind: kind, text: body, oldNumber: oldNo, newNumber: newNo))
                    lineID += 1
                } else if l.hasPrefix("@@") {
                    flushHunk()
                    hunkHeader = l
                    let parts = l.split(separator: " ", maxSplits: 3)
                    if parts.count >= 3 {
                        let oldSpec = parts[1].dropFirst().split(separator: ",")
                        let newSpec = parts[2].dropFirst().split(separator: ",")
                        oldCounter = oldSpec.first.flatMap { Int($0) } ?? 0
                        newCounter = newSpec.first.flatMap { Int($0) } ?? 0
                    }
                } else if l.hasPrefix("old mode ") || l.hasPrefix("new mode ") { metadata.append(l) }
                else if l.hasPrefix("new file mode") { newFile = true }
                else if l.hasPrefix("deleted file mode") { deletedFile = true }
                else if l.hasPrefix("rename from ") { renamed = true; oldPath = decodedPath(String(l.dropFirst(12))) }
                else if l.hasPrefix("rename to ") { renamed = true; path = decodedPath(String(l.dropFirst(10))) }
                else if l.hasPrefix("Binary files") || l == "Git binary patch" { binary = true }
                else if l.hasPrefix("--- ") {
                    let p = String(l.dropFirst(4))
                    if p != "/dev/null" { oldPath = decodedPath(p, stripPrefix: true) }
                } else if l.hasPrefix("+++ ") {
                    let p = String(l.dropFirst(4))
                    if p != "/dev/null" { path = decodedPath(p, stripPrefix: true) }
                }
                index += 1
            }
            flushHunk()
            if path.isEmpty { path = oldPath.isEmpty ? "file-\(files.count)" : oldPath }
            files.append(DiffFile(id: path, path: path, oldPath: oldPath.isEmpty ? nil : oldPath,
                                  binary: binary, newFile: newFile, deletedFile: deletedFile,
                                  renamed: renamed, hunks: hunks, metadata: metadata,
                                  additions: additions, deletions: deletions))
        }
        return files
    }

    /// Pair deletions with the additions that follow them for the split view.
    static func splitRows(_ lines: [DiffLine]) -> [SplitRow] {
        var rows: [SplitRow] = []
        var pending: [DiffLine] = []
        var id = 0
        func push(_ left: DiffLine?, _ right: DiffLine?) { rows.append(SplitRow(id: id, left: left, right: right)); id += 1 }
        func drainPending() { for d in pending { push(d, nil) }; pending.removeAll() }
        for line in lines {
            switch line.kind {
            case .context:
                drainPending()
                push(line, line)
            case .deletion:
                pending.append(line)
            case .addition:
                if !pending.isEmpty { push(pending.removeFirst(), line) }
                else { push(nil, line) }
            case .hunkHeader, .meta:
                drainPending()
                push(line, line)
            }
        }
        drainPending()
        return rows
    }
}

// MARK: - GitHub-style changes view (unified / split, colored)

struct ChangesDiffView: View {
    let statusText: String
    let diffText: String
    @State private var split = false
    @State private var collapsed: Set<String> = []
    /// Memoized parse: body evaluations (poll ticks, pane updates) must not
    /// re-parse the full diff text on the main thread; only a changed
    /// diffText triggers a re-parse. A heap cache avoids mutating @State
    /// during view update.
    private final class ParseCache {
        var key: String?
        var files: [DiffFile] = []
    }
    @State private var cache = ParseCache()
    private var files: [DiffFile] {
        if cache.key != diffText {
            cache.key = diffText
            cache.files = GitDiffParser.parse(diffText)
        }
        return cache.files
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(statusText.isEmpty ? "Working tree is clean." : statusText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Picker("Diff layout", selection: $split) {
                    Text("Unified").tag(false)
                    Text("Split").tag(true)
                }.pickerStyle(.segmented).frame(width: 170)
                    .accessibilityLabel("Diff layout")
            }.padding(.horizontal, 22).padding(.vertical, 10)
            Divider()
            if files.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(diffText.isEmpty ? "No tracked changes. Untracked files appear above; add them with Git to include them in the diff." : diffText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(files) { file in
                            DiffFileView(file: file, split: split,
                                         collapsed: Binding(get: { collapsed.contains(file.id) },
                                                            set: { if $0 { collapsed.insert(file.id) } else { collapsed.remove(file.id) } }))
                        }
                    }.padding(22)
                }
            }
        }
    }
}

struct DiffFileView: View {
    let file: DiffFile
    let split: Bool
    @Binding var collapsed: Bool
    private var title: String {
        if file.renamed, let old = file.oldPath { return "\(old) → \(file.path)" }
        if file.deletedFile { return file.oldPath ?? file.path }
        return file.path
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { collapsed.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    if file.newFile { Text("NEW").font(.system(size: 8, weight: .bold)).foregroundStyle(.green) }
                    if file.deletedFile { Text("DELETED").font(.system(size: 8, weight: .bold)).foregroundStyle(.red) }
                    if file.renamed { Text("RENAMED").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange) }
                    if file.binary { Text("BINARY").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary) }
                    Text(title)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("+\(file.additions)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.green)
                    Text("−\(file.deletions)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.red)
                }
            }.buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("File \(title), \(file.additions) additions, \(file.deletions) deletions\(collapsed ? ", collapsed" : "")")
            if !collapsed {
                if file.binary {
                    Text("Binary file not shown.").font(.caption).foregroundStyle(.secondary).padding(10)
                } else if file.hunks.isEmpty {
                    Text(file.metadata.isEmpty ? "No text changes." : file.metadata.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).padding(10)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(file.hunks) { hunk in
                            if split { SplitHunkView(hunk: hunk) } else { UnifiedHunkView(hunk: hunk) }
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }.textSelection(.enabled)
    }
}

// MARK: - Unified (merge) view

struct UnifiedHunkView: View {
    let hunk: DiffHunk
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiffRowBar(text: hunk.header, color: Color.blue.opacity(0.10))
            ForEach(hunk.lines) { line in
                UnifiedLineRow(line: line)
            }
        }
    }
}

struct UnifiedLineRow: View {
    let line: DiffLine
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.oldNumber.map(String.init) ?? "")
                .frame(width: 42, alignment: .trailing).padding(.horizontal, 4)
            Text(line.newNumber.map(String.init) ?? "")
                .frame(width: 42, alignment: .trailing).padding(.horizontal, 4)
            Text(prefix + line.text)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
        }
        .foregroundStyle(textColor)
        .background(background)
        .overlay(alignment: .leading) {
            if line.kind == .addition || line.kind == .deletion {
                Rectangle().fill(line.kind == .addition ? Color.green : Color.red).frame(width: 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }
    private var prefix: String {
        switch line.kind {
        case .addition: return "+ "
        case .deletion: return "− "
        case .hunkHeader, .meta: return ""
        case .context: return "  "
        }
    }
    private var textColor: Color {
        switch line.kind {
        case .hunkHeader: return .blue
        case .meta: return .secondary
        default: return .primary
        }
    }
    private var background: Color {
        switch line.kind {
        case .addition: return Color.green.opacity(0.16)
        case .deletion: return Color.red.opacity(0.16)
        case .hunkHeader: return Color.blue.opacity(0.10)
        default: return .clear
        }
    }
    private var accessibilityText: String {
        switch line.kind {
        case .addition: return "Added line \(line.newNumber ?? 0): \(line.text)"
        case .deletion: return "Removed line \(line.oldNumber ?? 0): \(line.text)"
        case .context: return "Line \(line.oldNumber ?? 0): \(line.text)"
        case .hunkHeader: return "Hunk: \(line.text)"
        case .meta: return line.text
        }
    }
}

func DiffRowBar(text: String, color: Color) -> some View {
    Text(text)
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Color.blue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
        .background(color)
}

// MARK: - Split (side-by-side) view

struct SplitHunkView: View {
    let hunk: DiffHunk
    private var rows: [SplitRow] { GitDiffParser.splitRows(hunk.lines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiffRowBar(text: hunk.header, color: Color.blue.opacity(0.10))
            ForEach(rows) { row in
                if row.left?.kind == .hunkHeader || row.left?.kind == .meta {
                    DiffRowBar(text: row.left?.text ?? "", color: .clear)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        SplitCell(line: row.left, oldSide: true)
                        Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1)
                        SplitCell(line: row.right, oldSide: false)
                    }
                }
            }
        }
    }
}

struct SplitCell: View {
    let line: DiffLine?
    var oldSide = true
    var lineNumber: Int? { oldSide ? line?.oldNumber : line?.newNumber }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(lineNumber.map(String.init) ?? "")
                .frame(width: 40, alignment: .trailing).padding(.horizontal, 4)
            Text(prefix + (line?.text ?? ""))
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
        }
        .foregroundStyle(textColor)
        .background(background)
        .overlay(alignment: .leading) {
            if line?.kind == .addition || line?.kind == .deletion {
                Rectangle().fill(line?.kind == .addition ? Color.green : Color.red).frame(width: 2)
            }
        }
        .frame(minHeight: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }
    private var prefix: String {
        guard let line else { return "" }
        switch line.kind {
        case .addition: return "+ "
        case .deletion: return "− "
        default: return line.text.isEmpty ? "" : "  "
        }
    }
    private var textColor: Color {
        guard let line else { return .secondary }
        return line.kind == .hunkHeader ? .blue : .primary
    }
    private var background: Color {
        guard let line else { return Color.primary.opacity(0.03) }
        switch line.kind {
        case .addition: return Color.green.opacity(0.16)
        case .deletion: return Color.red.opacity(0.16)
        case .hunkHeader: return Color.blue.opacity(0.10)
        default: return .clear
        }
    }
    private var accessibilityText: String {
        guard let line else { return "Empty" }
        switch line.kind {
        case .addition: return "Added line \(line.newNumber ?? 0): \(line.text)"
        case .deletion: return "Removed line \(line.oldNumber ?? 0): \(line.text)"
        default: return line.text
        }
    }
}
