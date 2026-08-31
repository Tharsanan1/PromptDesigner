import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var vm: CanvasViewModel
    @ObservedObject var compiler: CompilerService
    @Binding var result: CompilerResult?
    @Binding var targetEnv: String

    @State private var connectingFrom: String? = nil
    @State private var tempLineEnd: CGPoint? = nil
    @State private var editingConnection: BlockConnection?
    @State private var showCoverage = true

    var body: some View {
        HSplitView {
            // Left: Palette + Files
            VStack(spacing: 0) {
                PaletteView(vm: vm)
                Divider()
                FileBrowserView(vm: vm)
                Divider()
                DiagnosticsView(vm: vm)
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
            .background(Color(nsColor: .windowBackgroundColor))

            // Center: Canvas
            ZStack {
                CanvasView(vm: vm, connectingFrom: $connectingFrom, tempLineEnd: $tempLineEnd, onConnect: { from, to in
                    // Default semantics heuristics
                    let fromBlock = vm.workflow.block(withId: from)
                    let toBlock = vm.workflow.block(withId: to)
                    var semantics: ConnectionSemantics = .sequence
                    if fromBlock?.type == .mainAgent && toBlock?.type == .subagent { semantics = .delegate }
                    else if fromBlock?.type == .subagent && toBlock?.type == .mainAgent { semantics = .handoff }
                    else if fromBlock?.type == .parallel { semantics = .parallelBranch }
                    else if fromBlock?.type == .condition {
                        // Alternate true/false
                        let existing = vm.workflow.outgoing(from: from).filter { $0.semantics == .conditionTrue || $0.semantics == .conditionFalse }
                        semantics = existing.contains(where: { $0.semantics == .conditionTrue }) ? .conditionFalse : .conditionTrue
                    }
                    else if toBlock?.type == .review { semantics = .review }
                    vm.addConnection(from: from, to: to, semantics: semantics)
                })

                // Temp line while dragging connection
                if let from = connectingFrom, let end = tempLineEnd, let startBlock = vm.workflow.block(withId: from) {
                    let start = CGPoint(x: startBlock.position.x + startBlock.size.width, y: startBlock.position.y + startBlock.size.height/2)
                    Path { p in
                        p.move(to: start)
                        p.addCurve(to: end, control1: CGPoint(x: start.x + 80, y: start.y), control2: CGPoint(x: end.x - 80, y: end.y))
                    }.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6,4]))
                }

                // Top bar: zoom + grid toggle
                VStack {
                    HStack {
                        Button(action: { vm.scale = max(0.25, vm.scale - 0.1) }) { Image(systemName: "minus.magnifyingglass") }
                        Text("\(Int(vm.scale*100))%").font(.caption).monospacedDigit()
                        Button(action: { vm.scale = min(2.0, vm.scale + 0.1) }) { Image(systemName: "plus.magnifyingglass") }
                        Button("Reset") { vm.scale = 1; vm.offset = .zero }
                        Toggle("Grid", isOn: $vm.showGrid)
                        Toggle("Minimap", isOn: $vm.showMinimap)
                        Text("Ports v2.1").font(.caption2).padding(4).background(Color.green.opacity(0.2)).cornerRadius(4)
                        Spacer()
                        Text("\(vm.workflow.blocks.count) blocks • \(vm.workflow.connections.count) connections").font(.caption).foregroundColor(.secondary)
                    }.padding(8).background(.thinMaterial).cornerRadius(8).padding(8)
                    Spacer()
                }

                // Minimap
                if vm.showMinimap {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            MinimapView(vm: vm).frame(width: 160, height: 120).background(.thinMaterial).cornerRadius(8).padding(8)
                        }
                    }
                }
            }
            .frame(minWidth: 500)
            .background(Color(nsColor: .textBackgroundColor))

            // Right: Inspector + Compile
            VStack(spacing: 0) {
                InspectorView(vm: vm)
                Divider()
                CompilePanel(compiler: compiler, result: $result, targetEnv: $targetEnv, vm: vm)
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(item: $editingConnection) { conn in
            ConnectionEditSheet(vm: vm, connection: conn)
        }
    }
}

// MARK: - Palette

struct PaletteView: View {
    @ObservedObject var vm: CanvasViewModel
    let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blocks").font(.headline).padding(.horizontal, 8).padding(.top, 8)
            Text("Drag or double-click to add").font(.caption).foregroundColor(.secondary).padding(.horizontal, 8)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(BlockType.allCases) { type in
                        Button(action: { vm.addBlock(type: type) }) {
                            VStack(spacing: 4) {
                                Image(systemName: type.icon).foregroundColor(type.color)
                                Text(type.displayName).font(.caption2).multilineTextAlignment(.center).lineLimit(2)
                            }.frame(maxWidth: .infinity, minHeight: 54).padding(6).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(type.color.opacity(0.3), lineWidth: 1))
                        }.buttonStyle(.plain)
                            .onDrag { NSItemProvider(object: type.rawValue as NSString) }
                    }
                }.padding(8)
            }
            Divider()
            HStack {
                Button("Single Task") { vm.updateWorkflow(Workflow.templateSingleTask) }.font(.caption)
                Button("Subagents") { vm.updateWorkflow(Workflow.templateSubagents) }.font(.caption)
                Button("Pipeline") { vm.updateWorkflow(Workflow.templatePipeline) }.font(.caption)
            }.padding(.horizontal, 8).padding(.bottom, 8)
        }
    }
}

// MARK: - File Browser

struct FileBrowserView: View {
    @ObservedObject var vm: CanvasViewModel
    @State private var files: [URL] = []

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Projects").font(.headline)
                Spacer()
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                Button(action: { vm.newWorkflow() }) { Image(systemName: "plus") }
            }.padding(.horizontal, 8).padding(.top, 8)
            List(files, id: \.self) { url in
                HStack {
                    Image(systemName: "doc.text")
                    Text(url.deletingPathExtension().lastPathComponent).font(.caption).lineLimit(1)
                    Spacer()
                    if vm.currentFileURL == url { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                }.contentShape(Rectangle()).onTapGesture {
                    try? vm.load(from: url)
                    UserDefaults.standard.set(url.absoluteString, forKey: "lastFile")
                }.contextMenu {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button("Delete", role: .destructive) { try? FileManager.default.removeItem(at: url); refresh() }
                }
            }.listStyle(.plain).frame(height: 120)
        }.onAppear(perform: refresh)
    }

    func refresh() {
        let dir = Workflow.defaultDirectory
        files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles))?.filter { $0.pathExtension == "json" }.sorted { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast) ?? Date.distantPast > (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast) ?? Date.distantPast } ?? []
    }
}

// MARK: - Diagnostics

struct DiagnosticsView: View {
    @ObservedObject var vm: CanvasViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Validation \(vm.validationIssues.isEmpty ? "✓" : "⚠️ \(vm.validationIssues.count)")").font(.headline).padding(.horizontal, 8)
            ScrollView {
                if vm.validationIssues.isEmpty {
                    Text("No issues").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
                } else {
                    ForEach(vm.validationIssues) { iss in
                        HStack(alignment: .top) {
                            Image(systemName: iss.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill").foregroundColor(iss.severity == .error ? .red : .orange).font(.caption)
                            Text(iss.message).font(.caption).lineLimit(3)
                        }.padding(.horizontal, 8).padding(.vertical, 2).contentShape(Rectangle()).onTapGesture {
                            if let bid = iss.blockId { vm.selectedBlockId = bid }
                            if let cid = iss.connectionId { vm.selectedConnectionId = cid }
                        }
                    }
                }
            }.frame(height: 120)
        }.padding(.vertical, 4)
    }
}

// MARK: - Canvas

struct CanvasView: View {
    @ObservedObject var vm: CanvasViewModel
    @Binding var connectingFrom: String?
    @Binding var tempLineEnd: CGPoint?
    var onConnect: (String, String) -> Void

    @State private var dragStart: CGPoint?
    @State private var isPanning = false
    @State private var panStart: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if vm.showGrid { CanvasGrid(scale: 1).opacity(0.15) }
                connectionsLayer
                blocksLayer
            }
            .frame(width: 3000, height: 2000, alignment: .topLeading)
            .scaleEffect(vm.scale, anchor: .topLeading)
            .offset(vm.offset)
            .coordinateSpace(name: "canvas")
            .gesture(
                DragGesture().onChanged { v in
                    if !isPanning && v.translation.width.magnitude < 5 && v.translation.height.magnitude < 5 { return }
                    if vm.selectedBlockId == nil {
                        isPanning = true
                        vm.offset = CGSize(width: panStart.width + v.translation.width, height: panStart.height + v.translation.height)
                    }
                }.onEnded { _ in isPanning = false; panStart = vm.offset }
            )
            .onTapGesture { vm.selectedBlockId = nil; vm.selectedConnectionId = nil }
            .background(Color.clear)
        }
        .clipped()
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: NSString.self) { s, _ in
                    if let raw = s as? String, let type = BlockType(rawValue: raw) {
                        DispatchQueue.main.async { vm.addBlock(type: type) }
                    }
                }
            }
            return true
        }
    }

    private var connectionsLayer: some View {
        ForEach(vm.workflow.connections) { conn in
            if let from = vm.workflow.block(withId: conn.from), let to = vm.workflow.block(withId: conn.to) {
                let s = CGPoint(x: from.position.x + from.size.width, y: from.position.y + from.size.height/2)
                let e = CGPoint(x: to.position.x, y: to.position.y + to.size.height/2)
                let isSelected = vm.selectedConnectionId == conn.id
                ConnectionShape(semantics: conn.semantics, isSelected: isSelected, from: s, to: e, label: conn.label.isEmpty ? conn.semantics.displayName : conn.label)
                    .onTapGesture { vm.selectedConnectionId = conn.id; vm.selectedBlockId = nil }
                    .contextMenu {
                        Button("Delete", role: .destructive) { vm.deleteConnection(id: conn.id) }
                        ForEach(ConnectionSemantics.allCases) { sem in
                            Button(sem.displayName) {
                                var c = conn; c.semantics = sem; vm.updateConnection(c)
                            }
                        }
                    }
            }
        }
    }

    private var blocksLayer: some View {
        ForEach(vm.workflow.blocks) { block in
            ZStack {
                BlockView(block: block, isSelected: vm.selectedBlockId == block.id, issues: vm.validationIssues.filter { $0.blockId == block.id })

                HStack(spacing: 0) {
                    ConnectionPort(color: .green, symbol: "arrow.left", help: "Input — drop connection here")
                    Spacer(minLength: 0)
                    ConnectionPort(color: .accentColor, symbol: "arrow.right", help: "Drag to connect — output")
                        .gesture(
                            DragGesture(coordinateSpace: .named("canvas"))
                                .onChanged { v in
                                    connectingFrom = block.id
                                    tempLineEnd = v.location
                                }
                                .onEnded { v in
                                    if let target = hitTestBlock(at: v.location) { onConnect(block.id, target) }
                                    connectingFrom = nil
                                    tempLineEnd = nil
                                }
                        )
                }
                .padding(.horizontal, 5)
            }
            .frame(width: block.size.width, height: block.size.height)
                .position(x: block.position.x + block.size.width/2, y: block.position.y + block.size.height/2)
                .gesture(
                    DragGesture(coordinateSpace: .local)
                        .onChanged { v in
                            if dragStart == nil { dragStart = block.position }
                            let newPos = CGPoint(x: (dragStart!.x + v.translation.width / vm.scale), y: (dragStart!.y + v.translation.height / vm.scale))
                            vm.moveBlock(id: block.id, to: newPos)
                        }
                        .onEnded { _ in dragStart = nil; vm.endMove() }
                )
                .onTapGesture { vm.selectedBlockId = block.id; vm.selectedConnectionId = nil }
                .contextMenu {
                    Button("Duplicate") { vm.duplicateBlock(id: block.id) }
                    Button("Delete", role: .destructive) { vm.deleteBlock(id: block.id) }
                }
        }
    }

    func hitTestBlock(at point: CGPoint) -> String? {
        // point is in canvas space (after scale+offset); convert to logical
        let logical = CGPoint(x: (point.x - vm.offset.width) / vm.scale, y: (point.y - vm.offset.height) / vm.scale)
        for b in vm.workflow.blocks {
            let rect = CGRect(origin: b.position, size: b.size)
            if rect.insetBy(dx: -10, dy: -10).contains(logical) { return b.id }
        }
        // Fallback: try without conversion (in case coordinate space is unscaled)
        for b in vm.workflow.blocks {
            let rect = CGRect(origin: b.position, size: b.size)
            if rect.insetBy(dx: -10, dy: -10).contains(point) { return b.id }
        }
        return nil
    }
}

struct ConnectionPort: View {
    var color: Color
    var symbol: String
    var help: String

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Circle().stroke(Color.black.opacity(0.65), lineWidth: 1)
            Circle().fill(color).padding(3)
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .black))
                .foregroundColor(.white)
        }
        .frame(width: 26, height: 26)
        .contentShape(Circle())
        .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
        .help(help)
        .zIndex(100)
    }
}

struct CanvasGrid: View {
    var scale: CGFloat
    var body: some View {
        GeometryReader { geo in
            let step: CGFloat = 20 * scale
            Path { p in
                var x: CGFloat = 0
                while x < geo.size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: geo.size.height)); x += step }
                var y: CGFloat = 0
                while y < geo.size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)); y += step }
            }.stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        }
    }
}

struct MinimapView: View {
    @ObservedObject var vm: CanvasViewModel
    var body: some View {
        GeometryReader { geo in
            let scale: CGFloat = 0.08
            ZStack {
                ForEach(vm.workflow.blocks) { b in
                    Rectangle().fill(b.type.color).frame(width: b.size.width*scale, height: b.size.height*scale).position(x: b.position.x*scale, y: b.position.y*scale)
                }
                ForEach(vm.workflow.connections) { c in
                    if let f = vm.workflow.block(withId: c.from), let t = vm.workflow.block(withId: c.to) {
                        Path { p in p.move(to: CGPoint(x: f.position.x*scale, y: f.position.y*scale)); p.addLine(to: CGPoint(x: t.position.x*scale, y: t.position.y*scale)) }.stroke(c.semantics.color.opacity(0.6), lineWidth: 1)
                    }
                }
            }
        }
    }
}

struct ConnectionShape: View {
    var semantics: ConnectionSemantics
    var isSelected: Bool
    var from: CGPoint
    var to: CGPoint
    var label: String

    var body: some View {
        let midX = (from.x + to.x)/2
        Path { p in
            p.move(to: from)
            p.addCurve(to: to, control1: CGPoint(x: midX, y: from.y), control2: CGPoint(x: midX, y: to.y))
        }
        .stroke(semantics.color, style: StrokeStyle(lineWidth: isSelected ? 3 : 1.5, lineCap: .round, dash: semantics.dash))
        .overlay {
            // Arrow head
            let angle = atan2(to.y - from.y, to.x - from.x)
            Path { p in
                let len: CGFloat = 10
                p.move(to: to)
                p.addLine(to: CGPoint(x: to.x - len*cos(angle - .pi/6), y: to.y - len*sin(angle - .pi/6)))
                p.move(to: to)
                p.addLine(to: CGPoint(x: to.x - len*cos(angle + .pi/6), y: to.y - len*sin(angle + .pi/6)))
            }.stroke(semantics.color, lineWidth: isSelected ? 3 : 1.5)
        }
        .overlay {
            if !label.isEmpty {
                Text(label).font(.caption2).padding(2).background(.thinMaterial).cornerRadius(4)
                    .position(x: (from.x+to.x)/2, y: (from.y+to.y)/2 - 10)
            }
        }
    }
}

// MARK: - BlockView

struct BlockView: View {
    var block: Block
    var isSelected: Bool
    var issues: [ValidationIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: block.type.icon).foregroundColor(block.type.color).font(.caption)
                Text(block.type.displayName).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                Spacer()
                if !issues.isEmpty {
                    Image(systemName: issues.contains(where: { $0.severity == .error }) ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(issues.contains(where: { $0.severity == .error }) ? .red : .orange).font(.caption2)
                }
                Text(block.title).font(.caption).bold().lineLimit(1)
            }
            Divider()
            if !block.instructions.isEmpty {
                Text(block.instructions).font(.caption2).lineLimit(3).foregroundColor(.primary)
            } else {
                Text("No instructions").font(.caption2).italic().foregroundColor(.secondary)
            }
            if !block.properties.filter({ !$0.value.isEmpty }).isEmpty {
                ForEach(Array(block.properties.filter { !$0.value.isEmpty }.prefix(2)), id: \.key) { k,v in
                    HStack { Text(k+":").font(.caption2).foregroundColor(.secondary); Text(v).font(.caption2).lineLimit(1) }
                }
            }
        }
        .padding(8)
        .frame(width: block.size.width, height: block.size.height, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : block.type.color.opacity(0.4), lineWidth: isSelected ? 2 : 1))
        .shadow(color: .black.opacity(0.1), radius: isSelected ? 6 : 2, x: 0, y: 2)
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @ObservedObject var vm: CanvasViewModel
    @State private var editingInstructions = ""
    @State private var editingTitle = ""
    @State private var connectTargetId: String = ""
    @State private var connectSemantics: ConnectionSemantics = .sequence

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspector").font(.headline).padding(8)
            Divider()
            if let block = vm.selectedBlock {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Title
                        VStack(alignment: .leading) {
                            Text("Title").font(.caption).bold()
                            TextField("Title", text: Binding(
                                get: { block.title },
                                set: { var b = block; b.title = $0; vm.updateBlock(b) }
                            )).textFieldStyle(.roundedBorder).font(.caption)
                        }

                        // Type (read-only)
                        HStack { Text("Type:").font(.caption).foregroundColor(.secondary); Text(block.type.displayName).font(.caption).bold().foregroundColor(block.type.color) }

                        // Instructions
                        VStack(alignment: .leading) {
                            Text("Instructions *").font(.caption).bold()
                            TextEditor(text: Binding(
                                get: { block.instructions },
                                set: { var b = block; b.instructions = $0; vm.updateBlock(b) }
                            )).font(.caption).frame(height: 100).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                            Text("Markdown supported").font(.caption2).foregroundColor(.secondary)
                        }

                        // Properties per type
                        ForEach(Array(block.properties.keys.sorted()), id: \.self) { key in
                            VStack(alignment: .leading) {
                                Text(key).font(.caption2).foregroundColor(.secondary)
                                TextField(key, text: Binding(
                                    get: { block.properties[key] ?? "" },
                                    set: { var b = block; b.properties[key] = $0; vm.updateBlock(b) }
                                )).textFieldStyle(.roundedBorder).font(.caption)
                            }
                        }

                        Divider()
                        HStack {
                            Button("Duplicate") { vm.duplicateBlock(id: block.id) }
                            Button("Delete", role: .destructive) { vm.deleteBlock(id: block.id) }
                        }.font(.caption)

                        // Connections list
                        VStack(alignment: .leading) {
                            Text("Connections").font(.caption).bold()
                            ForEach(vm.workflow.connections.filter { $0.from == block.id || $0.to == block.id }) { c in
                                HStack {
                                    Text("\(vm.workflow.block(withId: c.from)?.title ?? c.from) → \(vm.workflow.block(withId: c.to)?.title ?? c.to)").font(.caption2).lineLimit(1)
                                    Spacer()
                                    Text(c.semantics.displayName).font(.caption2).foregroundColor(c.semantics.color)
                                }
                            }
                            if vm.workflow.connections.filter({ $0.from == block.id || $0.to == block.id }).isEmpty {
                                Text("No connections").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Create Connection").font(.caption).bold()
                            Text("Drag ● (right, blue) → ○ (left, green) or use below").font(.caption2).foregroundColor(.secondary)
                            Picker("To", selection: $connectTargetId) {
                                Text("Select target…").tag("")
                                ForEach(vm.workflow.blocks.filter { $0.id != block.id }) { b in
                                    Text(b.title).tag(b.id)
                                }
                            }.pickerStyle(.menu).font(.caption)
                            Picker("As", selection: $connectSemantics) {
                                ForEach(ConnectionSemantics.allCases) { s in Text(s.displayName).tag(s) }
                            }.pickerStyle(.menu).font(.caption)
                            Button("Connect") {
                                guard !connectTargetId.isEmpty else { return }
                                vm.addConnection(from: block.id, to: connectTargetId, semantics: connectSemantics)
                                connectTargetId = ""
                            }.disabled(connectTargetId.isEmpty).font(.caption)
                        }.padding(6).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(6)
                    }.padding(8)
                }
            } else if let cid = vm.selectedConnectionId, let conn = vm.workflow.connections.first(where: { $0.id == cid }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connection").font(.headline)
                        Picker("Semantics", selection: Binding(
                            get: { conn.semantics },
                            set: { var c = conn; c.semantics = $0; vm.updateConnection(c) }
                        )) {
                            ForEach(ConnectionSemantics.allCases) { s in Text(s.displayName).tag(s) }
                        }.pickerStyle(.menu).font(.caption)
                        TextField("Label", text: Binding(
                            get: { conn.label },
                            set: { var c = conn; c.label = $0; vm.updateConnection(c) }
                        )).textFieldStyle(.roundedBorder).font(.caption)
                        TextField("Condition", text: Binding(
                            get: { conn.condition },
                            set: { var c = conn; c.condition = $0; vm.updateConnection(c) }
                        )).textFieldStyle(.roundedBorder).font(.caption)
                        Button("Delete", role: .destructive) { vm.deleteConnection(id: conn.id) }
                    }.padding(8)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis").font(.largeTitle).foregroundColor(.secondary)
                    Text("Select a block or connection to inspect").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Divider()
                    ExecutionOrderView(vm: vm)
                }.padding(8)
            }
            Spacer()
        }
    }
}

struct ExecutionOrderView: View {
    @ObservedObject var vm: CanvasViewModel
    var body: some View {
        VStack(alignment: .leading) {
            Text("Execution Order").font(.caption).bold()
            ForEach(Array(vm.workflow.executionOrder().enumerated()), id: \.element.id) { idx, b in
                HStack { Text("\(idx+1).").font(.caption2).monospacedDigit(); Text(b.title).font(.caption2).lineLimit(1); Text("(\(b.type.displayName))").font(.caption2).foregroundColor(.secondary) }
            }
        }.padding(8).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(6).padding(8)
    }
}

struct ConnectionEditSheet: View {
    @ObservedObject var vm: CanvasViewModel
    var connection: BlockConnection
    @Environment(\.dismiss) var dismiss
    @State private var semantics: ConnectionSemantics
    @State private var label: String

    init(vm: CanvasViewModel, connection: BlockConnection) {
        self.vm = vm
        self.connection = connection
        _semantics = State(initialValue: connection.semantics)
        _label = State(initialValue: connection.label)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Edit Connection").font(.headline)
            Picker("Semantics", selection: $semantics) { ForEach(ConnectionSemantics.allCases) { s in Text(s.displayName).tag(s) } }
            TextField("Label", text: $label)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    var c = connection; c.semantics = semantics; c.label = label; vm.updateConnection(c); dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }.padding().frame(width: 360)
    }
}

// MARK: - Compile Panel

struct CompilePanel: View {
    @ObservedObject var compiler: CompilerService
    @Binding var result: CompilerResult?
    @Binding var targetEnv: String
    @ObservedObject var vm: CanvasViewModel
    @State private var showPrompt = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Compiler").font(.headline)
                Spacer()
                Picker("", selection: $targetEnv) {
                    Text("Generic").tag("Generic")
                    Text("Claude").tag("Claude")
                    Text("OpenAI").tag("OpenAI")
                    Text("Gemini").tag("Gemini")
                }.pickerStyle(.menu).frame(width: 120)
                Button(compiler.isCompiling ? "Compiling…" : "Compile") {
                    compiler.compile(workflow: vm.workflow, target: targetEnv) { res in
                        switch res {
                        case .success(let r): result = r
                        case .failure(let e): result = CompilerResult(prompt: "Error: \(e.localizedDescription)", warnings: [e.localizedDescription], coverageMap: [])
                        }
                    }
                }.disabled(compiler.isCompiling).keyboardShortcut("r", modifiers: .command)
            }.padding(.horizontal, 8).padding(.top, 8)

            if let r = result {
                Picker("View", selection: $showPrompt) {
                    Text("Prompt").tag(true); Text("Warnings (\(r.warnings.count))").tag(false)
                }.pickerStyle(.segmented).padding(.horizontal, 8)

                if showPrompt {
                    ScrollView {
                        Text(r.prompt).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }.background(Color(nsColor: .textBackgroundColor)).cornerRadius(6).padding(.horizontal, 8)
                    Button("Copy Prompt") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r.prompt, forType: .string)
                    }.font(.caption).padding(.horizontal, 8)
                    CoverageView(result: r, vm: vm)
                } else {
                    ScrollView {
                        if r.warnings.isEmpty {
                            Text("No warnings — workflow looks clean ✓").font(.caption).foregroundColor(.green).padding(8)
                        } else {
                            ForEach(r.warnings, id: \.self) { w in
                                HStack(alignment: .top) { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.caption); Text(w).font(.caption) }.padding(.horizontal, 8).padding(.vertical, 2)
                            }
                        }
                    }.frame(height: 200)
                    CoverageView(result: r, vm: vm)
                }
            } else {
                Text("Click Compile to generate prompt via LLM (OpenRouter). Requires API key.").font(.caption).foregroundColor(.secondary).padding(8)
                if let err = compiler.lastError { Text(err).font(.caption2).foregroundColor(.red).padding(.horizontal, 8) }
            }
            Spacer()
        }
    }
}

struct CoverageView: View {
    var result: CompilerResult
    @ObservedObject var vm: CanvasViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("Coverage Map \(result.coverageMap.isEmpty ? "(unavailable)" : "(\(result.coverageMap.count)/\(vm.workflow.blocks.count) blocks)")").font(.caption).bold().padding(.horizontal, 8)
            ScrollView {
                ForEach(result.coverageMap) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(e.blockTitle).font(.caption2).bold()
                            Text(e.blockId.prefix(4)).font(.caption2).foregroundColor(.secondary).monospaced()
                            Spacer()
                            if vm.workflow.block(withId: e.blockId) != nil { Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption2) } else { Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.caption2) }
                        }
                        Text(e.excerpt).font(.caption2).foregroundColor(.secondary).lineLimit(2).truncationMode(.tail).textSelection(.enabled)
                        Text("\(e.start)–\(e.end)").font(.caption2).foregroundColor(.secondary).monospacedDigit()
                    }.padding(6).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(6).padding(.horizontal, 8).padding(.vertical, 2)
                    .onTapGesture { vm.selectedBlockId = e.blockId }
                }
                if result.coverageMap.isEmpty {
                    Text("No coverage entries").font(.caption2).foregroundColor(.secondary).padding(8)
                }
            }.frame(height: 180)
        }
    }
}
