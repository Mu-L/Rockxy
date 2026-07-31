import SwiftUI

// MARK: - BreakpointTemplateWindowView

struct BreakpointTemplateWindowView: View {
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            editor
        }
        .font(toolMetrics.font())
        .frame(
            minWidth: max(860, toolMetrics.bodyFontSize * 28 + 496),
            minHeight: max(620, toolMetrics.bodyFontSize * 18 + 386)
        )
        .onAppear {
            synchronizeEditorDraft()
        }
        .onChange(of: store.selectedTemplateID) { _, _ in
            commitNameDraft()
            synchronizeEditorDraft()
        }
        .onChange(of: isNameFieldFocused) { _, isFocused in
            guard !isFocused else {
                return
            }
            commitNameDraft()
            synchronizeEditorDraft()
        }
        .onDisappear {
            commitNameDraft()
        }
        .alert(
            String(localized: "Delete Template?"),
            isPresented: Binding(
                get: { templatePendingDeletion != nil },
                set: { if !$0 { templatePendingDeletion = nil } }
            ),
            presenting: templatePendingDeletion
        ) { template in
            Button(String(localized: "Cancel"), role: .cancel) {
                templatePendingDeletion = nil
            }
            Button(String(localized: "Delete"), role: .destructive) {
                commitNameDraft()
                store.deleteTemplate(id: template.id)
                templatePendingDeletion = nil
            }
        } message: { template in
            Text(String(localized: "“\(displayName(for: template))” will be removed from the template library."))
        }
    }

    @Environment(\.appUIDisplayMetrics) private var appMetrics
    @Environment(\.openWindow) private var openWindow
    @State private var store = BreakpointTemplateStore.shared
    @State private var searchText = ""
    @State private var editorTemplateID: UUID?
    @State private var nameDraft = ""
    @State private var templatePendingDeletion: BreakpointTemplate?
    @FocusState private var isNameFieldFocused: Bool

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: toolMetrics.headerSpacing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Breakpoint Templates"))
                        .font(.system(size: max(15, toolMetrics.bodyFontSize + 2), weight: .semibold))
                    Text(String(localized: "Reusable raw HTTP messages for paused traffic."))
                        .font(toolMetrics.secondaryFont())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker(String(localized: "Template Kind"), selection: $store.selectedKind) {
                    Text(String(localized: "Request"))
                        .tag(BreakpointTemplateKind.request)
                    Text(String(localized: "Response"))
                        .tag(BreakpointTemplateKind.response)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.regular)
                .frame(height: toolMetrics.formControlHeight)
                .accessibilityLabel(String(localized: "Template kind"))

                TextField(String(localized: "Search templates"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(toolMetrics.font())
                    .frame(height: toolMetrics.formControlHeight)
                    .accessibilityLabel(String(localized: "Search templates"))
                    .keyboardShortcut("f", modifiers: .command)
            }
            .padding(.horizontal, toolMetrics.contentHorizontalPadding)
            .padding(.top, toolMetrics.headerTopPadding)
            .padding(.bottom, toolMetrics.headerBottomPadding)

            Divider()

            List(selection: $store.selectedTemplateID) {
                ForEach(filteredTemplates) { template in
                    templateRow(template)
                        .tag(template.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if filteredTemplates.isEmpty {
                    ContentUnavailableView {
                        Label(
                            isSearching
                                ? String(localized: "No Matching Templates")
                                : String(localized: "No \(store.selectedKind.pluralTitle)"),
                            systemImage: isSearching ? "magnifyingglass" : "doc.badge.plus"
                        )
                    } description: {
                        Text(
                            isSearching
                                ? String(localized: "Try a different template name.")
                                : String(localized: "Create a reusable \(store.selectedKind.rawValue) message.")
                        )
                    } actions: {
                        if !isSearching {
                            Button(String(localized: "New Template")) {
                                store.addTemplate()
                            }
                        }
                    }
                }
            }

            Divider()
            sidebarFooter
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func templateRow(_ template: BreakpointTemplate) -> some View {
        let validation = template.validation
        return HStack(spacing: 8) {
            Image(systemName: template.kind == .request ? "arrow.up.right" : "arrow.down.left")
                .foregroundStyle(.secondary)
                .frame(width: 15)
            Text(displayName(for: template))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Image(systemName: validation.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: toolMetrics.smallIconFontSize))
                .foregroundStyle(validation.isValid ? Color.green : Color.orange)
                .help(validation.message)
                .accessibilityLabel(
                    validation.isValid
                        ? String(localized: "Valid template")
                        : String(localized: "Invalid template: \(validation.message)")
                )
        }
        .font(toolMetrics.font())
        .help(displayName(for: template))
    }

    private var sidebarFooter: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            compactAddRemoveControl

            Text(String(localized: "\(filteredTemplates.count) templates"))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
            moreMenu
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
    }

    private var compactAddRemoveControl: some View {
        HStack(spacing: 0) {
            Button {
                store.addTemplate()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: toolMetrics.smallIconFontSize))
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel(String(localized: "New \(store.selectedKind.singularTitle)"))

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 18)

            Button {
                requestDeletion()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: toolMetrics.smallIconFontSize))
                    .frame(width: toolMetrics.compactButtonSize - 5, height: toolMetrics.compactButtonSize - 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.selectedTemplate == nil)
            .accessibilityLabel(String(localized: "Delete selected template"))
        }
        .foregroundStyle(.primary)
        .frame(width: max(43, toolMetrics.compactButtonSize * 2 + 1), height: toolMetrics.footerControlHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(String(localized: "New Request Template")) {
                store.addTemplate(kind: .request)
            }
            Button(String(localized: "New Response Template")) {
                store.addTemplate(kind: .response)
            }

            Divider()

            Button(String(localized: "Duplicate")) {
                commitNameDraft()
                store.duplicateSelectedTemplate()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(store.selectedTemplate == nil)

            Button(String(localized: "Reset Raw Message")) {
                store.resetSelectedTemplateToSample()
            }
            .disabled(store.selectedTemplate == nil)

            Divider()

            Button(String(localized: "Delete Template"), role: .destructive) {
                requestDeletion()
            }
            .disabled(store.selectedTemplate == nil)
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "More"))
                Image(systemName: "chevron.down")
                    .font(.system(size: toolMetrics.smallIconFontSize, weight: .semibold))
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.bordered)
        .fixedSize()
    }

    @ViewBuilder
    private var editor: some View {
        if let template = store.selectedTemplate {
            VStack(alignment: .leading, spacing: 0) {
                editorHeader(template)
                infoBanner

                ScrollView {
                    VStack(alignment: .leading, spacing: toolMetrics.formRowSpacing + 3) {
                        templateDetailsSection(template)
                        rawMessageSection(template)
                    }
                    .padding(.horizontal, toolMetrics.formHorizontalPadding)
                    .padding(.vertical, toolMetrics.formVerticalPadding)
                }

                Divider()
                editorFooter
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(String(localized: "No Template Selected"), systemImage: "doc.text")
            } description: {
                Text(String(localized: "Select a template, or create one to start with a valid HTTP sample."))
            } actions: {
                Button(String(localized: "New Request Template")) {
                    store.addTemplate(kind: .request)
                }
                Button(String(localized: "New Response Template")) {
                    store.addTemplate(kind: .response)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func editorHeader(_ template: BreakpointTemplate) -> some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(template.kind.singularTitle)
                    .font(.system(size: max(15, toolMetrics.bodyFontSize + 2), weight: .semibold))
                Text(String(localized: "Edit the exact message to apply while traffic is paused."))
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            validationStatusCapsule(template.validation)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.headerTopPadding)
    }

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(
                String(
                    localized:
                    """
                    Apply templates from the Raw tab in the Breakpoint Queue. A valid request template replaces \
                    method, target, headers, and body; a valid response template replaces status, headers, and body.
                    """
                )
            )
            .font(toolMetrics.secondaryFont())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(String(localized: "Open Queue")) {
                openWindow(id: "breakpoints")
            }
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.controlSpacing)
        .background(Color.accentColor.opacity(0.055))
    }

    private func templateDetailsSection(_ template: BreakpointTemplate) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Template Details"))
                .font(toolMetrics.font(weight: .semibold))

            sectionCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Name"))
                        .font(toolMetrics.font())
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Untitled Template"), text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(toolMetrics.font())
                        .controlSize(.regular)
                        .frame(height: toolMetrics.formControlHeight)
                        .focused($isNameFieldFocused)
                        .onSubmit {
                            commitNameDraft()
                            isNameFieldFocused = false
                        }
                        .accessibilityLabel(String(localized: "Template name"))
                }
            }
        }
    }

    private func rawMessageSection(_ template: BreakpointTemplate) -> some View {
        let validation = template.validation
        return VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Raw HTTP Message"))
                .font(toolMetrics.font(weight: .semibold))

            sectionCard {
                VStack(alignment: .leading, spacing: toolMetrics.controlSpacing) {
                    Label(
                        validation.message,
                        systemImage: validation.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(toolMetrics.secondaryFont())
                    .foregroundStyle(validation.isValid ? Color.green : Color.red)
                    .fixedSize(horizontal: false, vertical: true)

                    MapLocalHTTPMessageEditor(
                        text: Binding(
                            get: { template.rawMessage },
                            set: { store.updateTemplate(id: template.id, rawMessage: $0) }
                        ),
                        editorSettings: toolMetrics.codeEditorSettings
                    )
                    .frame(minHeight: 300)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                }
            }
        }
    }

    private var editorFooter: some View {
        HStack(spacing: toolMetrics.controlSpacing) {
            Text(String(localized: "Changes save automatically. Invalid templates remain in the library but cannot be applied."))
                .font(toolMetrics.secondaryFont())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(String(localized: "Duplicate")) {
                commitNameDraft()
                store.duplicateSelectedTemplate()
            }
            .disabled(store.selectedTemplate == nil)

            Button(String(localized: "Reset Message")) {
                store.resetSelectedTemplateToSample()
            }
            .disabled(store.selectedTemplate == nil)
        }
        .padding(.horizontal, toolMetrics.contentHorizontalPadding)
        .padding(.vertical, toolMetrics.footerTopPadding)
    }

    private var filteredTemplates: [BreakpointTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return store.selectedTemplates
        }
        return store.selectedTemplates.filter { template in
            template.name.localizedCaseInsensitiveContains(query)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var toolMetrics: ToolWindowDisplayMetrics {
        ToolWindowDisplayMetrics(appMetrics: appMetrics)
    }

    private func sectionCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, toolMetrics.formHorizontalPadding - 2)
            .padding(.vertical, toolMetrics.formVerticalPadding - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
    }

    private func validationStatusCapsule(_ validation: BreakpointTemplateValidation) -> some View {
        Text(
            validation.isValid
                ? String(localized: "VALID")
                : String(localized: "NEEDS ATTENTION")
        )
        .font(toolMetrics.secondaryFont(weight: .semibold))
        .foregroundStyle(validation.isValid ? Color.green : Color.orange)
        .padding(.horizontal, 9)
        .frame(height: toolMetrics.footerControlHeight)
        .background((validation.isValid ? Color.green : Color.orange).opacity(0.1))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke((validation.isValid ? Color.green : Color.orange).opacity(0.25), lineWidth: 1)
        }
        .help(validation.message)
    }

    private func requestDeletion() {
        guard let selectedTemplate = store.selectedTemplate else {
            return
        }
        templatePendingDeletion = selectedTemplate
    }

    private func synchronizeEditorDraft() {
        editorTemplateID = store.selectedTemplateID
        nameDraft = store.selectedTemplate?.name ?? ""
    }

    private func commitNameDraft() {
        guard let editorTemplateID else {
            return
        }
        store.updateTemplate(id: editorTemplateID, name: nameDraft)
    }

    private func displayName(for template: BreakpointTemplate) -> String {
        template.name.isEmpty ? String(localized: "Untitled") : template.name
    }
}
