import Foundation
import SwiftUI

// MARK: - Block Types (15 concepts from spec)

enum BlockType: String, CaseIterable, Codable, Identifiable {
    case objective = "objective"
    case context = "context"
    case mainAgent = "main_agent"
    case subagent = "subagent"
    case task = "task"
    case skill = "skill"
    case sequence = "sequence"
    case parallel = "parallel"
    case condition = "condition"
    case delegation = "delegation"
    case handoff = "handoff"
    case review = "review"
    case retry = "retry"
    case completion = "completion"
    case finalOutput = "final_output"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .objective: return "Objective"
        case .context: return "Context / Input"
        case .mainAgent: return "Main Agent"
        case .subagent: return "Subagent"
        case .task: return "Task"
        case .skill: return "Skill"
        case .sequence: return "Sequence"
        case .parallel: return "Parallel"
        case .condition: return "Condition"
        case .delegation: return "Delegation"
        case .handoff: return "Handoff"
        case .review: return "Review"
        case .retry: return "Retry"
        case .completion: return "Completion"
        case .finalOutput: return "Final Output"
        }
    }

    var icon: String {
        switch self {
        case .objective: return "target"
        case .context: return "doc.text"
        case .mainAgent: return "person.crop.circle.badge.checkmark"
        case .subagent: return "person.2"
        case .task: return "checklist"
        case .skill: return "hammer"
        case .sequence: return "arrow.right"
        case .parallel: return "arrow.branch"
        case .condition: return "arrow.triangle.branch"
        case .delegation: return "arrow.turn.down.forward.iphone"
        case .handoff: return "arrow.right.arrow.left"
        case .review: return "eye"
        case .retry: return "arrow.counterclockwise"
        case .completion: return "flag.checkered"
        case .finalOutput: return "doc.richtext"
        }
    }

    var color: Color {
        switch self {
        case .objective: return .purple
        case .context: return .blue
        case .mainAgent: return .indigo
        case .subagent: return .teal
        case .task: return .orange
        case .skill: return .yellow
        case .sequence: return .gray
        case .parallel: return .pink
        case .condition: return .red
        case .delegation: return .indigo
        case .handoff: return .green
        case .review: return .mint
        case .retry: return .brown
        case .completion: return .cyan
        case .finalOutput: return .purple
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .objective, .finalOutput, .completion: return CGSize(width: 260, height: 120)
        case .condition: return CGSize(width: 220, height: 100)
        case .mainAgent, .subagent: return CGSize(width: 240, height: 140)
        default: return CGSize(width: 240, height: 110)
        }
    }

    var requiredFields: [String] {
        switch self {
        case .objective: return ["goal"]
        case .task: return ["description"]
        case .mainAgent, .subagent: return ["role", "responsibility"]
        case .condition: return ["condition"]
        case .review: return ["standards"]
        case .finalOutput: return ["format"]
        default: return []
        }
    }
}

// MARK: - Connection Semantics (7 types)

enum ConnectionSemantics: String, CaseIterable, Codable, Identifiable {
    case sequence = "sequence"           // perform target after source
    case delegate = "delegate"           // delegate work to another agent
    case handoff = "handoff"             // pass source result as context
    case parallelBranch = "parallel_branch" // fork parallel
    case review = "review"               // review source result
    case conditionTrue = "condition_true"
    case conditionFalse = "condition_false"
    case correction = "correction"       // return corrections to earlier step

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sequence: return "Sequence"
        case .delegate: return "Delegate"
        case .handoff: return "Handoff"
        case .parallelBranch: return "Parallel"
        case .review: return "Review"
        case .conditionTrue: return "If True"
        case .conditionFalse: return "If False"
        case .correction: return "Correction"
        }
    }

    var icon: String {
        switch self {
        case .sequence: return "arrow.right"
        case .delegate: return "person.badge.key"
        case .handoff: return "shippingbox"
        case .parallelBranch: return "arrow.branch"
        case .review: return "eye"
        case .conditionTrue: return "checkmark"
        case .conditionFalse: return "xmark"
        case .correction: return "arrow.uturn.left"
        }
    }

    var color: Color {
        switch self {
        case .sequence: return .primary
        case .delegate: return .indigo
        case .handoff: return .green
        case .parallelBranch: return .pink
        case .review: return .orange
        case .conditionTrue: return .green
        case .conditionFalse: return .red
        case .correction: return .brown
        }
    }

    var dash: [CGFloat] {
        switch self {
        case .delegate: return [6, 4]
        case .handoff: return [2, 3]
        case .correction: return [4, 4]
        default: return []
        }
    }
}

// MARK: - Block

struct Block: Identifiable, Codable, Equatable {
    var id: String
    var type: BlockType
    var title: String
    var instructions: String
    var properties: [String: String] // flexible structured props per type
    var position: CGPoint
    var size: CGSize

    init(id: String = UUID().uuidString, type: BlockType, title: String? = nil, instructions: String = "", properties: [String: String] = [:], position: CGPoint = .zero, size: CGSize? = nil) {
        self.id = id
        self.type = type
        self.title = title ?? type.displayName
        self.instructions = instructions
        self.properties = properties
        self.position = position
        self.size = size ?? type.defaultSize
    }

    // Default properties per type
    static func defaultProperties(for type: BlockType) -> [String: String] {
        switch type {
        case .mainAgent:
            return ["role": "", "responsibility": "", "constraints": "", "skills": "", "expectedResult": ""]
        case .subagent:
            return ["role": "", "responsibility": "", "constraints": "", "skills": ""]
        case .review:
            return ["standards": "", "approvalRequired": "true", "onFailure": "request corrections"]
        case .condition:
            return ["condition": "", "trueLabel": "Yes", "falseLabel": "No"]
        case .retry:
            return ["maxRetries": "3", "onFailure": "escalate"]
        case .completion:
            return ["criteria": "", "requiredApprovals": ""]
        case .finalOutput:
            return ["format": "markdown", "sections": ""]
        case .handoff:
            return ["payload": "", "context": ""]
        case .delegation:
            return ["delegateTo": "", "context": ""]
        default:
            return [:]
        }
    }

    var isValid: Bool {
        for field in type.requiredFields {
            if (properties[field] ?? instructions).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // For required fields, either dedicated prop or instructions must be non-empty
                if field == "description" && !instructions.isEmpty { continue }
                if field == "goal" && !instructions.isEmpty { continue }
                // check property
                if let v = properties[field], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                return false
            }
        }
        return true
    }
}

// MARK: - Connection

struct BlockConnection: Identifiable, Codable, Equatable {
    var id: String
    var from: String // block id
    var to: String   // block id
    var semantics: ConnectionSemantics
    var label: String // optional extra label (condition text, payload name)
    var condition: String // for condition edges

    init(id: String = UUID().uuidString, from: String, to: String, semantics: ConnectionSemantics = .sequence, label: String = "", condition: String = "") {
        self.id = id
        self.from = from
        self.to = to
        self.semantics = semantics
        self.label = label
        self.condition = condition
    }
}

// MARK: - Workflow (source of truth)

struct Workflow: Codable, Equatable {
    var version: String = "1.0"
    var metadata: WorkflowMetadata
    var blocks: [Block]
    var connections: [BlockConnection]

    struct WorkflowMetadata: Codable, Equatable {
        var name: String
        var objective: String
        var createdAt: Date
        var updatedAt: Date
        var description: String

        init(name: String = "Untitled Workflow", objective: String = "", description: String = "") {
            self.name = name
            self.objective = objective
            self.description = description
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    init(metadata: WorkflowMetadata = WorkflowMetadata(), blocks: [Block] = [], connections: [BlockConnection] = []) {
        self.metadata = metadata
        self.blocks = blocks
        self.connections = connections
    }

    // Helpers
    func block(withId id: String) -> Block? { blocks.first(where: { $0.id == id }) }
    func outgoing(from id: String) -> [BlockConnection] { connections.filter { $0.from == id } }
    func incoming(to id: String) -> [BlockConnection] { connections.filter { $0.to == id } }

    // Topological sort respecting semantics (Kahn)
    func executionOrder() -> [Block] {
        var inDegree: [String: Int] = [:]
        for b in blocks { inDegree[b.id] = 0 }
        for c in connections { inDegree[c.to, default: 0] += 1 }
        var queue = blocks.filter { inDegree[$0.id] == 0 }
        var result: [Block] = []
        var idx = 0
        while idx < queue.count {
            let n = queue[idx]; idx += 1
            result.append(n)
            for e in outgoing(from: n.id) {
                inDegree[e.to, default: 0] -= 1
                if inDegree[e.to] == 0, let nb = block(withId: e.to) { queue.append(nb) }
            }
        }
        // If cycle, append remaining arbitrarily
        if result.count < blocks.count {
            let remaining = blocks.filter { b in !result.contains(where: { $0.id == b.id }) }
            result.append(contentsOf: remaining)
        }
        return result
    }

    func hasCycle() -> Bool {
        // DFS
        var visited: Set<String> = []
        var stack: Set<String> = []
        var adj: [String: [String]] = [:]
        for c in connections { adj[c.from, default: []].append(c.to) }
        func dfs(_ node: String) -> Bool {
            visited.insert(node); stack.insert(node)
            for nxt in adj[node] ?? [] {
                if !visited.contains(nxt) { if dfs(nxt) { return true } }
                else if stack.contains(nxt) { return true }
            }
            stack.remove(node); return false
        }
        for b in blocks { if !visited.contains(b.id) && dfs(b.id) { return true } }
        return false
    }
}

// MARK: - Validation

struct ValidationIssue: Identifiable {
    var id = UUID()
    var severity: Severity
    var message: String
    var blockId: String?
    var connectionId: String?

    enum Severity { case warning, error }
}

struct WorkflowValidator {
    static func validate(_ w: Workflow) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Check disconnected blocks
        let connectedIds = Set(w.connections.flatMap { [$0.from, $0.to] })
        for b in w.blocks where !connectedIds.contains(b.id) && w.blocks.count > 1 {
            // Objective and Final Output may be terminals, but still warn if isolated
            issues.append(ValidationIssue(severity: .warning, message: "Block '\(b.title)' is disconnected", blockId: b.id))
        }

        // Missing required fields
        for b in w.blocks where !b.isValid {
            issues.append(ValidationIssue(severity: .error, message: "\(b.type.displayName) '\(b.title)' is missing required instructions/properties", blockId: b.id))
        }

        // Parallel checks
        for b in w.blocks where b.type == .parallel {
            let outs = w.outgoing(from: b.id).filter { $0.semantics == .parallelBranch }
            if outs.count < 2 {
                issues.append(ValidationIssue(severity: .warning, message: "Parallel '\(b.title)' should have ≥2 branches (has \(outs.count))", blockId: b.id))
            }
        }

        // Condition checks
        for b in w.blocks where b.type == .condition {
            let outs = w.outgoing(from: b.id)
            let hasTrue = outs.contains(where: { $0.semantics == .conditionTrue })
            let hasFalse = outs.contains(where: { $0.semantics == .conditionFalse })
            if !hasTrue || !hasFalse {
                issues.append(ValidationIssue(severity: .warning, message: "Condition '\(b.title)' should have both True and False branches", blockId: b.id))
            }
        }

        // Review checks
        for b in w.blocks where b.type == .review {
            let ins = w.incoming(to: b.id)
            if ins.isEmpty {
                issues.append(ValidationIssue(severity: .warning, message: "Review '\(b.title)' has no incoming result to review", blockId: b.id))
            }
        }

        // Cycle detection (allowed for retry loops, but warn)
        if w.hasCycle() {
            issues.append(ValidationIssue(severity: .warning, message: "Workflow contains a cycle — ensure Retry/Correction semantics are intentional"))
        }

        // Dangling connections
        let blockIds = Set(w.blocks.map { $0.id })
        for c in w.connections {
            if !blockIds.contains(c.from) || !blockIds.contains(c.to) {
                issues.append(ValidationIssue(severity: .error, message: "Connection references missing block", connectionId: c.id))
            }
            if c.from == c.to {
                issues.append(ValidationIssue(severity: .warning, message: "Self-loop on '\(w.block(withId: c.from)?.title ?? c.from)'", connectionId: c.id))
            }
        }

        // Completion criteria
        if !w.blocks.contains(where: { $0.type == .objective }) {
            issues.append(ValidationIssue(severity: .warning, message: "Missing Objective block"))
        }
        if !w.blocks.contains(where: { $0.type == .finalOutput }) {
            issues.append(ValidationIssue(severity: .warning, message: "Missing Final Output block"))
        }

        return issues
    }
}

// MARK: - Compiler Result

struct CompilerResult: Codable {
    var prompt: String
    var warnings: [String]
    var coverageMap: [CoverageEntry]

    struct CoverageEntry: Codable, Identifiable {
        var id: String { blockId }
        var blockId: String
        var blockTitle: String
        var excerpt: String
        var start: Int
        var end: Int
    }
}

// MARK: - File helpers

extension Workflow {
    static var defaultDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("PromptDesigner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var configDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/prompt-designer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func save(to url: URL) throws {
        var copy = self
        copy.metadata.updatedAt = Date()
        let data = try JSONEncoder().encode(copy)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> Workflow {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Workflow.self, from: data)
    }
}
