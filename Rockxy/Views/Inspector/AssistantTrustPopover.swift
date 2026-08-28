import SwiftUI

/// Compact native explanation of the Assistant's local trust boundary.
struct AssistantTrustPopover: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "Read-only by default", bundle: RockxyLocalization.bundle),
                systemImage: "lock.shield.fill"
            )
            .font(.headline)

            trustRow(
                String(localized: "Selected traffic only", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Related requests are included only when you opt in.",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: "checkmark.circle"
            )
            trustRow(
                String(localized: "Review before model access", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "You see the exact redacted snapshot before it is processed.",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: "eye"
            )
            trustRow(
                String(localized: "Actions stay under your control", bundle: RockxyLocalization.bundle),
                detail: String(
                    localized: "Compose, replay, export, and sharing open a native review step.",
                    bundle: RockxyLocalization.bundle
                ),
                systemImage: "hand.raised"
            )
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }

    // MARK: Private

    private func trustRow(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
