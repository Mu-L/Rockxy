import SwiftUI

// MARK: - ProtobufTreeView

struct ProtobufTreeView: View {
    // MARK: Internal

    let tree: ProtobufDecodedTree

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                ForEach(tree.fields) { field in
                    ProtobufFieldRow(field: field, depth: 0)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Private

    @Environment(\.appUIDisplayMetrics) private var metrics

    private var header: some View {
        HStack(spacing: 12) {
            Text(String(localized: "Field", bundle: RockxyLocalization.bundle))
                .frame(width: 120, alignment: .leading)
            Text(String(localized: "Wire Type", bundle: RockxyLocalization.bundle))
                .frame(width: 130, alignment: .leading)
            Text(String(localized: "Best Guess Value", bundle: RockxyLocalization.bundle))
            Spacer()
        }
        .font(.system(size: metrics.metadataFontSize, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - ProtobufFieldRow

private struct ProtobufFieldRow: View {
    // MARK: Internal

    let field: ProtobufDecodedField
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    if nestedTree != nil {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: metrics.badgeFontSize, weight: .semibold))
                            .frame(width: 10)
                    } else {
                        Color.clear.frame(width: 10)
                    }
                    Text("\(field.fieldNumber)")
                        .font(.system(size: metrics.secondaryFontSize, weight: .medium, design: .monospaced))
                }
                .padding(.leading, CGFloat(depth) * 16)
                .frame(width: 120, alignment: .leading)

                Text(field.wireType.displayName)
                    .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)

                Text(valuePreview)
                    .font(.system(size: metrics.secondaryFontSize, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(SizeFormatter.format(bytes: field.rawBytes.count))
                    .font(.system(size: metrics.metadataFontSize, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                if nestedTree != nil {
                    isExpanded.toggle()
                }
            }

            if isExpanded, let nestedTree {
                ForEach(nestedTree.fields) { child in
                    ProtobufFieldRow(field: child, depth: depth + 1)
                }
            }
        }
    }

    // MARK: Private

    @State private var isExpanded = true
    @Environment(\.appUIDisplayMetrics) private var metrics

    private var nestedTree: ProtobufDecodedTree? {
        if case let .message(tree) = field.value {
            return tree
        }
        return nil
    }

    private var valuePreview: String {
        switch field.value {
        case let .varint(value):
            "\(value)"
        case let .fixed64(value):
            "\(value)"
        case let .fixed32(value):
            "\(value)"
        case let .string(value):
            "\"\(value)\""
        case let .bytes(data):
            String(localized: "raw bytes · \(data.count) bytes", bundle: RockxyLocalization.bundle)
        case let .message(tree):
            String(localized: "nested message · \(tree.fields.count) fields", bundle: RockxyLocalization.bundle)
        }
    }
}

private extension ProtobufWireType {
    var displayName: String {
        switch self {
        case .varint:
            "varint"
        case .fixed64:
            "fixed64"
        case .lengthDelimited:
            "lengthDelimited"
        case .startGroup:
            "startGroup"
        case .endGroup:
            "endGroup"
        case .fixed32:
            "fixed32"
        }
    }
}
