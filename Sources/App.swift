import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct PromptDesignerApp: App {
    @StateObject private var vm = CanvasViewModel(workflow: Workflow.templateSingleTask)
    @StateObject private var compiler = CompilerService()
    @State private var showingCompiler = false
    @State private var compilerResult: CompilerResult?
    @State private var targetEnv = "Generic"
    @State private var showingSavePanel = false
    @State private var showingOpenPanel = false

    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm, compiler: compiler, result: $compilerResult, targetEnv: $targetEnv)
                .frame(minWidth: 1280, minHeight: 800)
                .navigationTitle(vm.workflow.metadata.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { compile() }) {
                            Label(compiler.isCompiling ? "Compiling…" : "Compile", systemImage: "wand.and.stars")
                        }.disabled(compiler.isCompiling)
                    }
                    ToolbarItem {
                        Button(action: { vm.showMinimap.toggle() }) {
                            Label("Minimap", systemImage: "map")
                        }
                    }
                }
                .onAppear {
                    // Restore last file if exists
                    if let last = UserDefaults.standard.string(forKey: "lastFile"), let url = URL(string: last), FileManager.default.fileExists(atPath: url.path) {
                        try? vm.load(from: url)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Workflow") { vm.newWorkflow() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New from Template — Single Task") { vm.updateWorkflow(Workflow.templateSingleTask) }
                Button("New from Template — Subagents") { vm.updateWorkflow(Workflow.templateSubagents) }
                Button("New from Template — Pipeline") { vm.updateWorkflow(Workflow.templatePipeline) }
                Divider()
                Button("Open…") { openPanel() }.keyboardShortcut("o", modifiers: .command)
                Button("Save…") { savePanel() }.keyboardShortcut("s", modifiers: .command)
                Button("Export JSON…") { exportJSON() }.keyboardShortcut("e", modifiers: .command)
                Button("Import JSON…") { importJSON() }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { vm.undo() }.keyboardShortcut("z", modifiers: .command).disabled(!vm.canUndo)
                Button("Redo") { vm.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!vm.canRedo)
            }
            CommandMenu("Workflow") {
                Button("Delete Selection") { vm.deleteSelection() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(!vm.hasSelection)
                Divider()
                Button("Validate") { vm.validate() }
                Button("Copy Prompt") {
                    if let r = compilerResult { copyToClipboard(r.prompt) }
                }.disabled(compilerResult == nil)
            }
        }

        Settings {
            SettingsView()
        }
    }

    func compile() {
        compiler.compile(workflow: vm.workflow, target: targetEnv) { res in
            switch res {
            case .success(let r): compilerResult = r
            case .failure(let e):
                compilerResult = CompilerResult(prompt: "Compile failed: \(e.localizedDescription)", warnings: [e.localizedDescription], coverageMap: [])
            }
            showingCompiler = true
        }
    }

    func copyToClipboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    func savePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "\(vm.workflow.metadata.name).pwd.json"
        panel.directoryURL = Workflow.defaultDirectory
        if panel.runModal() == .OK, let url = panel.url {
            try? vm.save(to: url)
            UserDefaults.standard.set(url.absoluteString, forKey: "lastFile")
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.directoryURL = Workflow.defaultDirectory
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.urls.first {
            try? vm.load(from: url)
            UserDefaults.standard.set(url.absoluteString, forKey: "lastFile")
        }
    }

    func exportJSON() { savePanel() }
    func importJSON() { openPanel() }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Prompt Designer v1.0 — Local-first, LLM compiler only (OpenRouter).")
            Text("API key: reuse QuickAssist at ~/.config/quickassist/config.json or set ~/.config/prompt-designer/config.json {\"openrouter_key\":\"sk-or-...\"} or env OPENROUTER_API_KEY.")
                .font(.caption).foregroundColor(.secondary)
            Link("OpenRouter Models (free)", destination: URL(string: "https://openrouter.ai/models?max_price=0")!)
        }.padding().frame(width: 500, height: 200)
    }
}
