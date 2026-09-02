import Foundation

// MARK: - AssistantProductHandoff

/// A single validated direct-open navigation target the product-help Assistant may offer.
/// Every case maps to a real, no-selection-safe `Window(id:)` declared in `RockxyApp`. The
/// Assistant only ever navigates — it never executes a workflow, mutates state, runs a rule, or
/// toggles the proxy. Window IDs are static here and never model-selected.
enum AssistantProductHandoff: String, CaseIterable, Identifiable, Sendable {
    case developerSetup
    case httpsDecryption
    case mapLocal
    case mapRemote
    case blockList
    case allowList
    case modifyHeaders
    case networkConditions
    case breakpointRules
    case externalProxy
    case scripting

    // MARK: Internal

    var id: String {
        rawValue
    }

    /// Exact `Window(id:)` opened by `@Environment(\.openWindow)`. Static and validated — the
    /// value never originates from model output.
    var windowID: String {
        switch self {
        case .developerSetup: "developerSetupHub"
        case .httpsDecryption: "sslProxyingList"
        case .mapLocal: "mapLocal"
        case .mapRemote: "mapRemote"
        case .blockList: "blockList"
        case .allowList: "allowList"
        case .modifyHeaders: "modifyHeaders"
        case .networkConditions: "networkConditions"
        case .breakpointRules: "breakpointRules"
        case .externalProxy: "externalProxySettings"
        case .scripting: "scriptingList"
        }
    }

    /// The exact destination window name — must match the `Window(...)` title in `RockxyApp`.
    var destinationName: String {
        switch self {
        case .developerSetup: String(localized: "Developer Setup", bundle: RockxyLocalization.bundle)
        case .httpsDecryption: String(localized: "HTTPS Decryption", bundle: RockxyLocalization.bundle)
        case .mapLocal: String(localized: "Map Local", bundle: RockxyLocalization.bundle)
        case .mapRemote: String(localized: "Map Remote", bundle: RockxyLocalization.bundle)
        case .blockList: String(localized: "Block List", bundle: RockxyLocalization.bundle)
        case .allowList: String(localized: "Allow List", bundle: RockxyLocalization.bundle)
        case .modifyHeaders: String(localized: "Modify Headers", bundle: RockxyLocalization.bundle)
        case .networkConditions: String(localized: "Network Conditions", bundle: RockxyLocalization.bundle)
        case .breakpointRules: String(localized: "Breakpoint Rules", bundle: RockxyLocalization.bundle)
        case .externalProxy: String(localized: "External Proxy Settings", bundle: RockxyLocalization.bundle)
        case .scripting: String(localized: "Scripting", bundle: RockxyLocalization.bundle)
        }
    }

    /// The button label. Labels match the destination window exactly, prefixed with "Open".
    var actionTitle: String {
        String(localized: "Open \(destinationName)", bundle: RockxyLocalization.bundle)
    }

    var accessibilityLabel: String {
        actionTitle
    }

    var accessibilityHint: String {
        String(localized: "Opens the \(destinationName) window.", bundle: RockxyLocalization.bundle)
    }
}

// MARK: - AssistantProductHelpTopic

/// One catalog entry: the intent keywords, the model-grounding capability line, the deterministic
/// user-facing answer, and the single handoff offered when the topic matches.
struct AssistantProductHelpTopic {
    let handoff: AssistantProductHandoff
    let keywords: [String]
    /// English capability line supplied to the model as grounding. Not user-facing prose.
    let capability: String
    /// Concise user-facing answer used when the configured model is unavailable.
    let answer: String
}

// MARK: - AssistantProductHelpResponse

/// A deterministic product-help reply: the concise answer text plus at most one optional handoff.
struct AssistantProductHelpResponse: Equatable {
    let text: String
    let handoff: AssistantProductHandoff?
}

// MARK: - AssistantProductHelpCatalog

/// The single source of truth for product-help. Deterministic fallback answers, model prompt
/// grounding, and handoff intent matching all read the same topic list, so a claim and the button
/// offered beside it can never drift apart. Matching is purely deterministic keyword scoring — no
/// model, no captured traffic.
struct AssistantProductHelpCatalog: Sendable {
    // MARK: Internal

    static let shared = AssistantProductHelpCatalog()

    let topics: [AssistantProductHelpTopic] = [
        AssistantProductHelpTopic(
            handoff: .developerSetup,
            keywords: [
                "get started", "getting started", "set up", "setup", "onboard", "how do i start",
                "debug my app", "connect my app", "proxy my app", "capture traffic from",
                "node", "ios simulator", "android", "react native", "flutter", "configure my app",
            ],
            capability: "Developer Setup: guided onboarding to route a runtime, browser, or device through Rockxy's proxy.",
            answer: String(
                localized: "Developer Setup walks you through pointing a runtime, browser, or device at Rockxy's proxy and verifying traffic flows.",
                bundle: RockxyLocalization.bundle
            )
        ),
        AssistantProductHelpTopic(
            handoff: .httpsDecryption,
            keywords: [
                "https", "ssl proxying", "ssl proxy", "decrypt", "encrypted traffic", "tls intercept",
                "see the body", "can't read https", "enable https",
            ],
            capability: "HTTPS Decryption: choose Decrypt or Tunnel behavior for an application or host so encrypted traffic is handled predictably.",
            answer: String(
                localized: """
                HTTPS Decryption lets you decrypt traffic from an application or a specific host, or keep it \
                tunneled. Trust Rockxy's root certificate before decrypting.
                """,
                bundle: RockxyLocalization.bundle
            )
        ),
        AssistantProductHelpTopic(
            handoff: .mapLocal,
            keywords: [
                "map local", "local file", "mock response", "serve a file", "return a local",
                "fake response", "stub response", "static response",
            ],
            capability: "Map Local: serve a response from a local file with a custom status code, headers, and body.",
            answer: String(
                localized: "Map Local serves a matching request from a local file — you set the status code, headers, and body — so you can mock an endpoint.",
                bundle: RockxyLocalization.bundle
            )
        ),
        AssistantProductHelpTopic(
            handoff: .mapRemote,
            keywords: [
                "map remote", "redirect", "reroute", "point to another", "forward to",
                "different server", "swap the host", "route to staging",
            ],
            capability: "Map Remote: redirect a matching request to a different protocol, host, port, or path.",
            answer: String(
                localized: "Map Remote redirects a matching request to a different host, port, or path — handy for pointing an app at staging or a local server.",
                bundle: RockxyLocalization.bundle
            )
        ),
        AssistantProductHelpTopic(
            handoff: .blockList,
            keywords: [
                "block list", "blocklist", "block request", "block a domain", "deny request",
                "drop connection", "return 403",
            ],
            capability: "Block List: return 403 or drop connections for matching requests.",
            answer: String(
                localized: "The Block List returns 403 or drops the connection for matching requests, so you can simulate an endpoint being unavailable.",
                bundle: RockxyLocalization.bundle
            )
        ),
        AssistantProductHelpTopic(
            handoff: .allowList,
            keywords: [
                "allow list", "allowlist", "only capture", "whitelist", "restrict capture",
                "limit to", "just capture",
            ],
            capability: "Allow List: restrict capture to matching hosts so unrelated traffic is ignored.",
            answer: String(
                localized: "The Allow List restricts capture to the hosts you specify, so Rockxy ignores everything else and the request list stays focused.",
                bundle: RockxyLocalization.bundle
            )
        ),
        AssistantProductHelpTopic(
            handoff: .modifyHeaders,
            keywords: [
                "header", "modify header", "add header", "change header", "rewrite header",
                "set header", "inject header", "remove header", "override header",
            ],
            capability: "Modify Headers: add, remove, or replace request or response headers via a rule.",
            answer: String(
                localized: "Modify Headers adds, removes, or replaces headers on matching requests or responses — for example injecting or stripping one.",
                bundle: RockxyLocalization.bundle
            )
        ),
        AssistantProductHelpTopic(
            handoff: .networkConditions,
            keywords: [
                "network condition", "throttle", "slow network", "latency", "bandwidth",
                "simulate slow", "3g", "packet loss", "slow connection",
            ],
            capability: "Network Conditions: throttle bandwidth and add latency to simulate slow or unreliable networks.",
            answer: String(
                localized: "Network Conditions throttles bandwidth and adds latency so you can reproduce how your app behaves on a slow connection.",
                bundle: RockxyLocalization.bundle
            )
        ),
        AssistantProductHelpTopic(
            handoff: .breakpointRules,
            keywords: [
                "breakpoint", "pause", "intercept", "pause request", "pause the request",
                "intercept and edit", "edit before it", "stop the request", "modify in flight",
            ],
            capability: "Breakpoint Rules: pause a matching request or response mid-flight to edit it before it continues.",
            answer: String(
                localized: "Breakpoint Rules pause a matching request or response mid-flight so you can edit the URL, headers, body, or status first.",
                bundle: RockxyLocalization.bundle
            )
        ),
        AssistantProductHelpTopic(
            handoff: .externalProxy,
            keywords: [
                "socks", "socks5",
            ],
            capability: "SOCKS5 upstream proxy: not available in this build — only HTTP/HTTPS CONNECT and PAC URL upstream routing apply.",
            answer: String(
                localized: """
                SOCKS5 upstream proxying isn't available in this build — only HTTP/HTTPS proxies \
                or a PAC URL can be applied. Open External Proxy Settings to configure one of those.
                """, bundle: RockxyLocalization.bundle
            )
        ),
        AssistantProductHelpTopic(
            handoff: .externalProxy,
            keywords: [
                "upstream proxy", "external proxy", "chain proxy", "pac", "secondary proxy",
                "route through another proxy", "corporate proxy",
            ],
            capability: "External Proxy: route captured traffic out through an upstream HTTP/HTTPS CONNECT proxy, or auto-select via a PAC URL.",
            answer: String(
                localized: "External Proxy Settings route Rockxy's outbound traffic through an upstream HTTP/HTTPS proxy, or a PAC URL.",
                bundle: RockxyLocalization.bundle
            )
        ),
        AssistantProductHelpTopic(
            handoff: .scripting,
            keywords: [
                "script", "javascript", "automate", "programmatically", "custom logic", "hook",
                "write code to modify",
            ],
            capability: "Scripting: run JavaScript hooks that inspect or modify requests and responses programmatically.",
            answer: String(
                localized: "Scripting runs JavaScript hooks that inspect or modify requests and responses programmatically, beyond what a static rule does.",
                bundle: RockxyLocalization.bundle
            )
        ),
    ]

    /// The best-matching topic for a prompt, or nil when nothing is recognized. Scores each topic by
    /// how many of its keywords appear as substrings of the lowercased prompt; ties break by
    /// declaration order (the earlier, more general topic wins).
    func match(prompt: String) -> AssistantProductHelpTopic? {
        let normalized = prompt.lowercased()
        guard !normalized.isEmpty else {
            return nil
        }
        var best: (topic: AssistantProductHelpTopic, score: Int)?
        for topic in topics {
            let score = topic.keywords.reduce(into: 0) { partial, keyword in
                if normalized.contains(keyword) {
                    partial += 1
                }
            }
            guard score > (best?.score ?? 0) else {
                continue
            }
            best = (topic, score)
        }
        return best?.topic
    }

    /// The concise deterministic reply used when the configured model is off or unavailable.
    /// Recognized questions get the matched topic's answer plus its handoff; unknown questions get an
    /// honest help fallback with no fabricated capabilities and no handoff.
    func deterministicResponse(for prompt: String) -> AssistantProductHelpResponse {
        guard let topic = match(prompt: prompt) else {
            return AssistantProductHelpResponse(text: unknownFallbackText, handoff: nil)
        }
        return AssistantProductHelpResponse(text: topic.answer, handoff: topic.handoff)
    }

    /// The source-backed capability catalog injected into the model prompt as grounding. English,
    /// not user-facing prose — it constrains the model to real Rockxy features.
    func groundingText() -> String {
        topics.map { "- \($0.capability)" }.joined(separator: "\n")
    }

    // MARK: Private

    private var unknownFallbackText: String {
        String(
            localized: """
            I can help with Rockxy's workflows — capture, HTTPS decryption, mapping, \
            breakpoints, rules, and scripting. I couldn't match that to a feature; \
            try naming the workflow or open Settings.
            """, bundle: RockxyLocalization.bundle
        )
    }
}
