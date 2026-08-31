import Foundation
import Combine
import SwiftUI

// MARK: - Compiler Service (LLM only, OpenRouter)

final class CompilerService: ObservableObject {
    @Published var isCompiling = false
    @Published var lastError: String?

    static func resolveAPIKey() -> String? {
        let qa = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/quickassist/config.json")
        if let data = try? Data(contentsOf: qa),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let providers = json["providers"] as? [[String: Any]] {
                for p in providers where (p["name"] as? String) == "openrouter" {
                    if let k = p["api_key"] as? String {
                        if !k.trimmingCharacters(in: .whitespaces).isEmpty { return k }
                    }
                }
            }
            if let k = json["api_key"] as? String {
                if !k.isEmpty { return k }
            }
        }
        let pd = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/prompt-designer/config.json")
        if let data = try? Data(contentsOf: pd),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let k = json["openrouter_key"] as? String {
            if !k.isEmpty { return k }
        }
        if let k = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] {
            if !k.isEmpty { return k }
        }
        return nil
    }

    static var skillPrompt: String {
        """
        You are the PromptDesigner Compiler — a dedicated skill that converts a structured visual AI workflow JSON into a polished natural-language prompt.

        Input: JSON with version, metadata, blocks[], connections[].
        Each block has id, type, title, instructions, properties, position.
        Each connection has from, to, semantics (sequence, delegate, handoff, parallel_branch, review, condition_true, condition_false, correction), label, condition.

        Your job is SEMANTIC compilation, not template concatenation.

        Rules:
        - Preserve EVERY block with instructions/properties. Do not omit. Do not invent agents/tasks not in JSON.
        - Preserve agent boundaries: Main Agent vs Subagents, their roles/responsibilities/constraints/skills.
        - Understand sequential vs parallel: sequence = do after; parallel_branch = fork parallel, join semantics; handoff = pass result as context.
        - Explain delegation clearly: who delegates to whom, with what context, and what returns.
        - Preserve conditions: describe branching logic, true/false paths.
        - Preserve review gates: what is reviewed, standards, approval required, what happens on failure (correction/retry).
        - Preserve completion criteria and final output format.
        - Adapt tone for target environment: Generic, Claude, OpenAI Agents, Gemini — but do not change meaning.
        - Report ambiguities/contradictions/missing required fields as warnings — do not silently guess.
        - Avoid omitting details during compilation.

        Output: STRICT JSON with keys: prompt (string, the complete prompt), warnings (array of strings), coverageMap (array of {blockId, blockTitle, excerpt, start, end} where excerpt is the exact quoted substring from prompt that corresponds to the block, and start/end are character offsets).

        Coverage map must reference every block that has non-empty instructions or required properties. Excerpt must be verbatim substring of prompt.

        Example output shape:
        {
          "prompt": "You are ...",
          "warnings": ["Parallel 'Research' has only 1 branch", "Review 'QA' has no incoming"],
          "coverageMap": [{"blockId":"abc","blockTitle":"Objective","excerpt":"Objective: Build ...","start":0,"end":32}]
        }

        Input workflow JSON follows:
        """
    }

    func compile(workflow: Workflow, target: String = "Generic", completion: @escaping (Result<CompilerResult, Error>) -> Void) {
        guard let apiKey = Self.resolveAPIKey(), !apiKey.isEmpty else {
            completion(.failure(NSError(domain: "CompilerService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing OpenRouter API key. Set it in QuickAssist (✨ → Set API Keys…) or in ~/.config/prompt-designer/config.json {\"openrouter_key\":\"sk-or-...\"} or env OPENROUTER_API_KEY."])))
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let workflowData = try? encoder.encode(workflow),
              let workflowJSON = String(data: workflowData, encoding: .utf8) else {
            completion(.failure(NSError(domain: "CompilerService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to encode workflow"])))
            return
        }
        let userContent = "Target environment: \(target)\n\nWorkflow JSON:\n\(workflowJSON)"
        let models = [
            "poolside/laguna-s-2.1:free",
            "minimax/minimax-m3:free",
            "google/gemma-4-31b-it:free",
            "google/gemma-4-26b-a4b-it:free",
            "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"
        ]
        DispatchQueue.main.async { self.isCompiling = true; self.lastError = nil }

        func attempt(_ idx: Int) {
            guard idx < models.count else {
                DispatchQueue.main.async {
                    self.isCompiling = false
                    completion(.failure(NSError(domain: "CompilerService", code: 429, userInfo: [NSLocalizedDescriptionKey: "All free models rate-limited. Retry shortly or add provider key at https://openrouter.ai/settings/integrations"])))
                }
                return
            }
            let model = models[idx]
            let body: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "system", "content": Self.skillPrompt],
                    ["role": "user", "content": userContent]
                ],
                "response_format": ["type": "json_object"],
                "max_tokens": 8000,
                "temperature": 0.2
            ]
            guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions"),
                  let data = try? JSONSerialization.data(withJSONObject: body) else {
                completion(.failure(NSError(domain: "CompilerService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Bad request"])))
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = data
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("PromptDesigner", forHTTPHeaderField: "X-Title")
            req.timeoutInterval = 60

            URLSession.shared.dataTask(with: req) { data, resp, error in
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 200
                let isRateLimited = status == 429 || status == 502 || status == 503

                if let error = error {
                    if isRateLimited && idx + 1 < models.count {
                        attempt(idx + 1); return
                    }
                    DispatchQueue.main.async {
                        self.isCompiling = false
                        completion(.failure(error))
                    }
                    return
                }
                guard let data = data else {
                    DispatchQueue.main.async {
                        self.isCompiling = false
                        completion(.failure(NSError(domain: "CompilerService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Empty response"])))
                    }
                    return
                }
                // Try to parse success
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Check for error envelope first (rate limit)
                    if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
                        let code = err["code"] as? Int ?? status
                        if (code == 429 || code == 502 || code == 503) && idx + 1 < models.count {
                            attempt(idx + 1); return
                        }
                        DispatchQueue.main.async {
                            self.isCompiling = false
                            completion(.failure(NSError(domain: "CompilerService", code: code, userInfo: [NSLocalizedDescriptionKey: msg])))
                        }
                        return
                    }
                    if let choices = json["choices"] as? [[String: Any]],
                       let msg = choices.first?["message"] as? [String: Any],
                       let content = msg["content"] as? String {
                        let isSafety = content.count < 80 && content.lowercased().contains("safe")
                        if isSafety && idx + 1 < models.count {
                            attempt(idx + 1); return
                        }
                        if let cData = content.data(using: .utf8),
                           let comp = try? JSONDecoder().decode(CompilerResult.self, from: cData) {
                            DispatchQueue.main.async {
                                self.isCompiling = false
                                completion(.success(comp))
                            }
                            return
                        }
                        if let start = content.firstIndex(of: "{"),
                           let end = content.lastIndex(of: "}"),
                           let sub = String(content[start...end]).data(using: .utf8),
                           let comp = try? JSONDecoder().decode(CompilerResult.self, from: sub) {
                            DispatchQueue.main.async {
                                self.isCompiling = false
                                completion(.success(comp))
                            }
                            return
                        }
                        let fallback = CompilerResult(prompt: content, warnings: ["Compiler returned non-JSON; coverage map unavailable."], coverageMap: [])
                        DispatchQueue.main.async {
                            self.isCompiling = false
                            completion(.success(fallback))
                        }
                        return
                    }
                }
                if isRateLimited && idx + 1 < models.count {
                    attempt(idx + 1); return
                }
                DispatchQueue.main.async {
                    self.isCompiling = false
                    completion(.failure(NSError(domain: "CompilerService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse compiler response"])))
                }
            }.resume()
        }
        attempt(0)
    }
}

extension CompilerResult {
    static func mock(for workflow: Workflow) -> CompilerResult {
        var prompt = "# \(workflow.metadata.name)\n\nObjective: \(workflow.metadata.objective)\n\n"
        for b in workflow.blocks {
            prompt += "## \(b.type.displayName): \(b.title)\n\(b.instructions)\n"
            for (k,v) in b.properties where !v.isEmpty { prompt += "- \(k): \(v)\n" }
            prompt += "\n"
        }
        prompt += "Connections:\n"
        for c in workflow.connections {
            prompt += "- \(c.semantics.rawValue) from \(workflow.block(withId: c.from)?.title ?? c.from) to \(workflow.block(withId: c.to)?.title ?? c.to)\n"
        }
        let coverage = workflow.blocks.map { b in
            CompilerResult.CoverageEntry(blockId: b.id, blockTitle: b.title, excerpt: b.title, start: 0, end: b.title.count)
        }
        return CompilerResult(prompt: prompt, warnings: ["Mock compilation (no API key) — not semantic"], coverageMap: coverage)
    }
}
