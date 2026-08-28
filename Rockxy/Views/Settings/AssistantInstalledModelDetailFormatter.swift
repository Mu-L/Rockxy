import Foundation

enum AssistantInstalledModelDetailFormatter {
    static func text(for model: AssistantModel) -> String {
        var parts = [model.parameterSize, model.quantizationLevel].compactMap { $0 }
        if let sizeBytes = model.sizeBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
        }
        if let contextWindow = model.inputTokenLimit {
            parts.append(String(localized: "\(contextWindow.formatted()) context", bundle: RockxyLocalization.bundle))
        }
        if model.capabilities.contains(.tools) {
            parts.append(String(localized: "Tool-ready model", bundle: RockxyLocalization.bundle))
        }
        return parts.isEmpty ? String(localized: "Installed in Ollama", bundle: RockxyLocalization.bundle) : parts
            .joined(separator: " · ")
    }
}
