import Foundation

// MARK: - InvestigationEvidenceGroup

/// Evidence for one `InvestigationEvidenceKind`, used to render dense native "Findings" and
/// "Unknowns" sections in the Investigate dock instead of one flat, ungrouped list.
struct InvestigationEvidenceGroup: Identifiable, Equatable {
    let kind: InvestigationEvidenceKind
    let evidence: [InvestigationEvidence]

    var id: String {
        kind.rawValue
    }

    var isUnknown: Bool {
        kind == .unknown
    }
}

// MARK: - InvestigationResultPresentation

/// Pure grouping/derivation for an `InvestigationResult`. Keeps evidence bucketing out of view
/// bodies so the Investigate dock never re-sorts findings during layout.
enum InvestigationResultPresentation {
    /// Reader-friendly, stable order: observed → derived → inferred → unknown. Empty kinds are
    /// dropped so a group only appears when it has evidence.
    static func evidenceGroups(for evidence: [InvestigationEvidence]) -> [InvestigationEvidenceGroup] {
        let order: [InvestigationEvidenceKind] = [.observed, .derived, .inferred, .unknown]
        return order.compactMap { kind in
            let matches = evidence.filter { $0.kind == kind }
            guard !matches.isEmpty else {
                return nil
            }
            return InvestigationEvidenceGroup(kind: kind, evidence: matches)
        }
    }

    /// Concrete findings — every group except `.unknown`, which reads as open questions.
    static func findingGroups(for evidence: [InvestigationEvidence]) -> [InvestigationEvidenceGroup] {
        evidenceGroups(for: evidence).filter { !$0.isUnknown }
    }

    /// Open questions surfaced as a dedicated "Unknowns" section.
    static func unknowns(for evidence: [InvestigationEvidence]) -> [InvestigationEvidence] {
        evidence.filter { $0.kind == .unknown }
    }

    /// Number of concrete findings (everything that is not an unknown).
    static func findingCount(for evidence: [InvestigationEvidence]) -> Int {
        evidence.count { $0.kind != .unknown }
    }
}
