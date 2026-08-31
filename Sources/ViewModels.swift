import Foundation
import SwiftUI
import Combine

final class CanvasViewModel: ObservableObject {
    @Published var workflow: Workflow
    @Published var selectedBlockId: String?
    @Published var selectedConnectionId: String?
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGSize = .zero
    @Published var showGrid = true
    @Published var showMinimap = false
    @Published var validationIssues: [ValidationIssue] = []
    @Published var isDirty = false

    // Undo/Redo
    private var history: [Workflow] = []
    private var future: [Workflow] = []
    private var historyLimit = 100
    private var isRestoring = false
    private var cancellables = Set<AnyCancellable>()

    // File
    var currentFileURL: URL?
    var onWorkflowChange: (() -> Void)?

    init(workflow: Workflow = Workflow(metadata: Workflow.WorkflowMetadata(name: "Untitled Workflow"))) {
        self.workflow = workflow
        validate()
        setupAutoSave()
        pushHistory()
    }

    var selectedBlock: Block? {
        guard let id = selectedBlockId else { return nil }
        return workflow.block(withId: id)
    }

    // MARK: - History

    func pushHistory() {
        guard !isRestoring else { return }
        history.append(workflow)
        if history.count > historyLimit { history.removeFirst() }
        future.removeAll()
    }

    func undo() {
        guard history.count > 1 else { return }
        isRestoring = true
        future.append(workflow)
        history.removeLast()
        workflow = history.last!
        validate()
        isRestoring = false
        isDirty = true
    }

    func redo() {
        guard let nxt = future.popLast() else { return }
        isRestoring = true
        history.append(nxt)
        workflow = nxt
        validate()
        isRestoring = false
        isDirty = true
    }

    var canUndo: Bool { history.count > 1 }
    var canRedo: Bool { !future.isEmpty }

    // MARK: - Workflow mutations

    func updateWorkflow(_ newWorkflow: Workflow, push: Bool = true) {
        workflow = newWorkflow
        workflow.metadata.updatedAt = Date()
        if push { pushHistory() }
        validate()
        isDirty = true
    }

    func addBlock(type: BlockType, at position: CGPoint? = nil) {
        let pos = position ?? CGPoint(x: 200 + CGFloat.random(in: 0...200), y: 200 + CGFloat.random(in: 0...200))
        let block = Block(type: type, instructions: "", properties: Block.defaultProperties(for: type), position: pos)
        var w = workflow
        w.blocks.append(block)
        updateWorkflow(w)
        selectedBlockId = block.id
    }

    func updateBlock(_ block: Block) {
        var w = workflow
        if let idx = w.blocks.firstIndex(where: { $0.id == block.id }) {
            w.blocks[idx] = block
            updateWorkflow(w)
        }
    }

    func deleteBlock(id: String) {
        var w = workflow
        w.blocks.removeAll(where: { $0.id == id })
        w.connections.removeAll(where: { $0.from == id || $0.to == id })
        updateWorkflow(w)
        if selectedBlockId == id { selectedBlockId = nil }
    }

    func duplicateBlock(id: String) {
        guard let b = workflow.block(withId: id) else { return }
        var copy = b
        copy.id = UUID().uuidString
        copy.title += " Copy"
        copy.position = CGPoint(x: b.position.x + 20, y: b.position.y + 20)
        var w = workflow
        w.blocks.append(copy)
        updateWorkflow(w)
        selectedBlockId = copy.id
    }

    func moveBlock(id: String, to pos: CGPoint) {
        var w = workflow
        if let idx = w.blocks.firstIndex(where: { $0.id == id }) {
            w.blocks[idx].position = pos
            // Don't push history for every drag tick - we'll push on end
            workflow = w
            validate()
        }
    }

    func endMove() { pushHistory(); isDirty = true }

    // Connections

    func addConnection(from: String, to: String, semantics: ConnectionSemantics = .sequence) {
        guard from != to else { return }
        // Prevent duplicate
        if workflow.connections.contains(where: { $0.from == from && $0.to == to && $0.semantics == semantics }) { return }
        var w = workflow
        w.connections.append(BlockConnection(from: from, to: to, semantics: semantics))
        updateWorkflow(w)
    }

    func updateConnection(_ conn: BlockConnection) {
        var w = workflow
        if let idx = w.connections.firstIndex(where: { $0.id == conn.id }) {
            w.connections[idx] = conn
            updateWorkflow(w)
        }
    }

    func deleteConnection(id: String) {
        var w = workflow
        w.connections.removeAll(where: { $0.id == id })
        updateWorkflow(w)
        if selectedConnectionId == id { selectedConnectionId = nil }
    }

    // MARK: - Validation

    func validate() {
        validationIssues = WorkflowValidator.validate(workflow)
    }

    // MARK: - Persistence

    private func setupAutoSave() {
        $workflow
            .dropFirst()
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.autoSave()
            }
            .store(in: &cancellables)
    }

    func autoSave() {
        guard let url = currentFileURL else { return }
        try? workflow.save(to: url)
        isDirty = false
    }

    func save(to url: URL) throws {
        try workflow.save(to: url)
        currentFileURL = url
        isDirty = false
    }

    func load(from url: URL) throws {
        let w = try Workflow.load(from: url)
        workflow = w
        currentFileURL = url
        history = [w]
        future = []
        validate()
        isDirty = false
    }

    func newWorkflow() {
        workflow = Workflow(metadata: Workflow.WorkflowMetadata(name: "Untitled Workflow"))
        currentFileURL = nil
        history = [workflow]
        future = []
        selectedBlockId = nil
        selectedConnectionId = nil
        validate()
    }

    // MARK: - File helpers for patterns

    func saveAsPattern(blockIds: Set<String>) {
        let patternBlocks = workflow.blocks.filter { blockIds.contains($0.id) }
        guard !patternBlocks.isEmpty else { return }
        // Normalize positions to origin
        let minX = patternBlocks.map { $0.position.x }.min() ?? 0
        let minY = patternBlocks.map { $0.position.y }.min() ?? 0
        let normBlocks = patternBlocks.map { b -> Block in
            var nb = b; nb.position = CGPoint(x: b.position.x - minX, y: b.position.y - minY); return nb
        }
        let patternConns = workflow.connections.filter { blockIds.contains($0.from) && blockIds.contains($0.to) }
        let pattern = Workflow(metadata: Workflow.WorkflowMetadata(name: "Pattern"), blocks: normBlocks, connections: patternConns)
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PromptDesigner/Patterns", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(workflow.metadata.name)-pattern-\(Date().timeIntervalSince1970).pwd.json")
        try? pattern.save(to: url)
    }
}

// MARK: - Templates

extension Workflow {
    static var templateSingleTask: Workflow {
        let obj = Block(type: .objective, title: "Objective", instructions: "Summarize this article in 3 bullet points for a busy exec.", position: CGPoint(x: 100, y: 200))
        let task = Block(type: .task, title: "Summarize", instructions: "Read the input article, extract 3 key points, keep each under 20 words.", position: CGPoint(x: 400, y: 200))
        let out = Block(type: .finalOutput, title: "Output", instructions: "Bullet list, markdown", properties: ["format":"markdown"], position: CGPoint(x: 700, y: 200))
        return Workflow(metadata: WorkflowMetadata(name: "Single Task", objective: "Simple summarization"), blocks: [obj, task, out], connections: [BlockConnection(from: obj.id, to: task.id, semantics: .sequence), BlockConnection(from: task.id, to: out.id, semantics: .sequence)])
    }

    static var templateSubagents: Workflow {
        let obj = Block(type: .objective, title: "Objective", instructions: "Create a product launch plan.", position: CGPoint(x: 100, y: 300))
        let main = Block(type: .mainAgent, title: "Launch Lead", instructions: "Coordinate subagents and synthesize final plan.", properties: Block.defaultProperties(for: .mainAgent), position: CGPoint(x: 400, y: 300))
        let research = Block(type: .subagent, title: "Researcher", instructions: "Research competitors and pricing.", position: CGPoint(x: 700, y: 150))
        let writer = Block(type: .subagent, title: "Writer", instructions: "Draft messaging and FAQ.", position: CGPoint(x: 700, y: 450))
        let out = Block(type: .finalOutput, title: "Launch Plan", instructions: "Sections: Positioning, Pricing, Channels, Timeline, Risks", position: CGPoint(x: 1000, y: 300))
        return Workflow(metadata: WorkflowMetadata(name: "Subagents", objective: "Coordinated launch"), blocks: [obj, main, research, writer, out], connections: [
            BlockConnection(from: obj.id, to: main.id, semantics: .sequence),
            BlockConnection(from: main.id, to: research.id, semantics: .delegate),
            BlockConnection(from: main.id, to: writer.id, semantics: .delegate),
            BlockConnection(from: research.id, to: main.id, semantics: .handoff, label: "research"),
            BlockConnection(from: writer.id, to: main.id, semantics: .handoff, label: "draft"),
            BlockConnection(from: main.id, to: out.id, semantics: .sequence)
        ])
    }

    static var templatePipeline: Workflow {
        let obj = Block(type: .objective, title: "Objective", instructions: "Research, draft, review, and polish a technical blog post.", position: CGPoint(x: 80, y: 300))
        let ctx = Block(type: .context, title: "Input", instructions: "Topic: 'AI agent workflows'. Audience: engineers. Length: 800 words.", position: CGPoint(x: 280, y: 300))
        let main = Block(type: .mainAgent, title: "Editor", instructions: "Own the post, delegate research and drafting, ensure review gate passes.", position: CGPoint(x: 500, y: 300))
        let researcher = Block(type: .subagent, title: "Researcher", instructions: "Find 5 credible sources, extract key insights and citations.", position: CGPoint(x: 750, y: 150))
        let drafter = Block(type: .subagent, title: "Drafter", instructions: "Write first draft from research, 800 words, clear headings.", position: CGPoint(x: 750, y: 450))
        let review = Block(type: .review, title: "Review", instructions: "Check accuracy, clarity, no hallucinations, citation coverage.", properties: ["standards":"accuracy, clarity, citations","approvalRequired":"true"], position: CGPoint(x: 1000, y: 300))
        let retry = Block(type: .retry, title: "Correct", instructions: "Apply reviewer feedback, fix citations and structure.", position: CGPoint(x: 1000, y: 500))
        let out = Block(type: .finalOutput, title: "Published Post", instructions: "Markdown with title, intro, 3 sections, conclusion, references", position: CGPoint(x: 1250, y: 300))
        let completion = Block(type: .completion, title: "Gate", instructions: "Review approval = true and all citations verified", position: CGPoint(x: 1250, y: 500))
        return Workflow(metadata: WorkflowMetadata(name: "Multi-Stage Pipeline", objective: "Blog post pipeline"), blocks: [obj, ctx, main, researcher, drafter, review, retry, out, completion], connections: [
            BlockConnection(from: obj.id, to: ctx.id, semantics: .sequence),
            BlockConnection(from: ctx.id, to: main.id, semantics: .handoff, label: "topic"),
            BlockConnection(from: main.id, to: researcher.id, semantics: .delegate),
            BlockConnection(from: main.id, to: drafter.id, semantics: .delegate),
            BlockConnection(from: researcher.id, to: drafter.id, semantics: .handoff, label: "insights"),
            BlockConnection(from: drafter.id, to: review.id, semantics: .review),
            BlockConnection(from: review.id, to: retry.id, semantics: .conditionFalse, label: "needs fix"),
            BlockConnection(from: retry.id, to: review.id, semantics: .correction),
            BlockConnection(from: review.id, to: out.id, semantics: .conditionTrue, label: "approved"),
            BlockConnection(from: out.id, to: completion.id, semantics: .sequence)
        ])
    }

    static var complexExample: Workflow {
        var w = templatePipeline
        w.metadata.name = "Complex Example (10+ blocks)"
        // Add parallel and condition
        let parallel = Block(type: .parallel, title: "Parallel", instructions: "Run research branches in parallel", position: CGPoint(x: 500, y: 150))
        let cond = Block(type: .condition, title: "Scope?", instructions: "Is the topic research-heavy?", properties: ["condition":"topic complexity > high"], position: CGPoint(x: 750, y: 650))
        w.blocks.append(contentsOf: [parallel, cond])
        // Add extra handoffs to reach 11 blocks
        return w
    }
}
