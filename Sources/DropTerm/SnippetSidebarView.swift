import AppKit

@MainActor
final class SnippetSidebarView: NSVisualEffectView, NSSearchFieldDelegate {
    var onRunCommand: ((String) -> Void)?
    var onInsertCommand: ((String) -> Void)?
    var onClose: (() -> Void)?
    var contentBottomInset: CGFloat = 0

    private let store: SnippetStore
    private let tintOverlay = SidebarDecorationView()
    private let titleLabel = NSTextField(labelWithString: "Snippets")
    private let searchBorder = SidebarDecorationView()
    private let searchIcon = NSImageView()
    private let searchField = NSTextField()
    private let addGroupButton = SidebarIconButton()
    private let closeButton = SidebarIconButton()
    private let scrollView = SidebarScrollView()
    private let stack = FlippedStackView()
    private let headerSeparator = NSView()
    private var collapsedGroupIDs: Set<UUID> = []
    private var contentWidthConstraints: [NSLayoutConstraint] = []
    private var activeEditor: Editor?

    private enum Editor: Equatable {
        case addGroup
        case addSnippet(UUID)
        case editGroup(UUID)
        case editSnippet(groupID: UUID, snippetID: UUID)
    }

    init(store: SnippetStore) {
        self.store = store
        super.init(frame: .zero)
        configureAppearance()
        configureHeader()
        configureContent()
        rebuild()
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
        super.resetCursorRects()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseMoved(with: event)
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 16
        let headerHeight: CGFloat = 86
        let contentWidth = max(0, bounds.width - padding * 2 - 1)

        titleLabel.frame = CGRect(x: padding + 1, y: bounds.height - 37, width: 150, height: 20)
        closeButton.frame = CGRect(x: bounds.width - 40, y: bounds.height - 41, width: 26, height: 26)
        addGroupButton.frame = CGRect(x: closeButton.frame.minX - 29, y: bounds.height - 41, width: 26, height: 26)
        searchBorder.frame = CGRect(x: padding + 1, y: bounds.height - 79, width: contentWidth, height: 32)
        searchIcon.frame = CGRect(x: padding + 10, y: bounds.height - 71, width: 16, height: 16)
        searchField.frame = CGRect(x: padding + 31, y: bounds.height - 77, width: max(0, contentWidth - 37), height: 24)
        headerSeparator.frame = CGRect(x: 1, y: bounds.height - headerHeight, width: bounds.width - 1, height: 1)
        scrollView.frame = CGRect(
            x: 1,
            y: 0,
            width: bounds.width - 1,
            height: max(0, bounds.height - headerHeight)
        )

        stack.frame = CGRect(
            x: 0,
            y: 0,
            width: scrollView.contentSize.width,
            height: max(scrollView.contentSize.height, stack.fittingSize.height + 18)
        )
        contentWidthConstraints.forEach { $0.constant = contentWidth }
    }

    private func configureAppearance() {
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        isEmphasized = false
        wantsLayer = true

        tintOverlay.wantsLayer = true
        tintOverlay.layer?.backgroundColor = AppColors.panelBackground(tint: 0.25, alpha: 0.18).cgColor
        tintOverlay.autoresizingMask = [.width, .height]
        tintOverlay.frame = bounds
        addSubview(tintOverlay)

        headerSeparator.wantsLayer = true
        headerSeparator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        addSubview(headerSeparator)
    }

    private func configureHeader() {
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        searchBorder.wantsLayer = true
        searchBorder.layer?.cornerRadius = 15
        searchBorder.layer?.cornerCurve = .continuous
        searchBorder.layer?.borderWidth = 1
        searchBorder.layer?.borderColor = NSColor.white.withAlphaComponent(0.11).cgColor
        searchBorder.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.018).cgColor
        addSubview(searchBorder)

        addGroupButton.configure(
            symbol: "plus",
            toolTip: "Add Group",
            target: self,
            action: #selector(addGroupClicked(_:))
        )
        addSubview(addGroupButton)

        closeButton.configure(
            symbol: "chevron.right",
            toolTip: "Close Snippets (⇧⌘S)",
            target: self,
            action: #selector(closeClicked(_:))
        )
        addSubview(closeButton)

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        searchIcon.contentTintColor = .secondaryLabelColor
        addSubview(searchIcon)

        searchField.placeholderString = "Search"
        searchField.isContinuous = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.focusRingType = .none
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.backgroundColor = .clear
        searchField.font = .systemFont(ofSize: 14)
        addSubview(searchField)
    }

    private func configureContent() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.onSwipeRight = { [weak self] in self?.onClose?() }
        addSubview(scrollView)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 16, bottom: 7, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

    }

    func controlTextDidChange(_ notification: Notification) {
        rebuild()
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        contentWidthConstraints.removeAll()
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if activeEditor == .addGroup {
            addInlineEditor(mode: .addGroup)
        }

        for group in store.groups {
            let matchingSnippets = query.isEmpty
                ? group.snippets
                : group.snippets.filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                        || $0.command.localizedCaseInsensitiveContains(query)
                        || group.name.localizedCaseInsensitiveContains(query)
                }
            guard query.isEmpty || !matchingSnippets.isEmpty else { continue }

            let isCollapsed = collapsedGroupIDs.contains(group.id) && query.isEmpty
            let header = SnippetGroupHeaderView(
                title: group.name,
                isCollapsed: isCollapsed,
                onToggle: { [weak self] in self?.toggleGroup(group.id) },
                onAdd: { [weak self] in self?.addSnippet(to: group.id) },
                onEdit: { [weak self] in self?.editGroup(group.id) },
                onDelete: { [weak self] in
                    self?.store.removeGroup(id: group.id)
                    self?.rebuild()
                }
            )
            addContentView(header)

            if activeEditor == .editGroup(group.id) {
                addInlineEditor(mode: .editGroup(group))
            }
            if activeEditor == .addSnippet(group.id) {
                addInlineEditor(mode: .addSnippet(group.id))
            }

            guard !isCollapsed else { continue }
            for snippet in matchingSnippets {
                let row = SnippetCommandRow(
                    snippet: snippet,
                    onInsert: { [weak self] in self?.onInsertCommand?(snippet.command) },
                    onRun: { [weak self] in self?.onRunCommand?(snippet.command) },
                    onEdit: { [weak self] in self?.editSnippet(snippet.id, in: group.id) },
                    onDelete: { [weak self] in
                        self?.store.removeSnippet(id: snippet.id, from: group.id)
                        self?.rebuild()
                    }
                )
                addContentView(row)
                if activeEditor == .editSnippet(groupID: group.id, snippetID: snippet.id) {
                    addInlineEditor(mode: .editSnippet(groupID: group.id, snippet: snippet))
                }
            }
        }

        if store.groups.isEmpty {
            addContentView(emptyStateView())
        } else if stack.arrangedSubviews.isEmpty {
            let noResults = NSTextField(labelWithString: "No matching snippets")
            noResults.font = .systemFont(ofSize: 12)
            noResults.textColor = .secondaryLabelColor
            noResults.alignment = .center
            noResults.heightAnchor.constraint(equalToConstant: 48).isActive = true
            addContentView(noResults)
        }
        needsLayout = true
    }

    private func addContentView(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        let constraint = view.widthAnchor.constraint(equalToConstant: max(0, stack.frame.width))
        constraint.isActive = true
        contentWidthConstraints.append(constraint)
    }

    private func addInlineEditor(mode: EditorPresentation) {
        let editor = InlineSnippetEditor(
            mode: mode.isGroup ? .group : .snippet,
            initialName: mode.name,
            initialCommands: mode.commands
        ) { [weak self] name, command in
            guard let self else { return }
            switch mode {
            case .addGroup:
                self.store.addGroup(named: name)
            case .addSnippet(let groupID):
                guard let command else { return }
                self.store.addSnippet(name: name, command: command, to: groupID)
                self.collapsedGroupIDs.remove(groupID)
            case .editGroup(let group):
                self.store.renameGroup(id: group.id, to: name)
            case .editSnippet(let groupID, let snippet):
                guard let command else { return }
                self.store.updateSnippet(id: snippet.id, in: groupID, name: name, command: command)
            }
            self.activeEditor = nil
            self.rebuild()
        } onCancel: { [weak self] in
            self?.activeEditor = nil
            self?.rebuild()
        }
        addContentView(editor)
        DispatchQueue.main.async { [weak self, weak editor] in
            guard let self, let editor, editor.superview != nil else { return }
            self.window?.makeFirstResponder(editor.firstField)
        }
    }

    private func emptyStateView() -> NSView {
        let card = SidebarEmptyStateView()
        card.onAdd = { [weak self] in self?.addGroup() }
        return card
    }

    private func toggleGroup(_ id: UUID) {
        if collapsedGroupIDs.contains(id) {
            collapsedGroupIDs.remove(id)
        } else {
            collapsedGroupIDs.insert(id)
        }
        rebuild()
    }

    @objc private func searchChanged(_ sender: NSTextField) { rebuild() }
    @objc private func addGroupClicked(_ sender: Any?) { addGroup() }
    @objc private func closeClicked(_ sender: Any?) { onClose?() }

    private func addGroup() {
        activeEditor = activeEditor == .addGroup ? nil : .addGroup
        rebuild()
    }

    private func addSnippet(to groupID: UUID) {
        let editor = Editor.addSnippet(groupID)
        activeEditor = activeEditor == editor ? nil : editor
        collapsedGroupIDs.remove(groupID)
        rebuild()
    }

    private func editGroup(_ groupID: UUID) {
        let editor = Editor.editGroup(groupID)
        activeEditor = activeEditor == editor ? nil : editor
        rebuild()
    }

    private func editSnippet(_ snippetID: UUID, in groupID: UUID) {
        let editor = Editor.editSnippet(groupID: groupID, snippetID: snippetID)
        activeEditor = activeEditor == editor ? nil : editor
        collapsedGroupIDs.remove(groupID)
        rebuild()
    }
}

private enum EditorPresentation {
    case addGroup
    case addSnippet(UUID)
    case editGroup(SnippetGroup)
    case editSnippet(groupID: UUID, snippet: CommandSnippet)

    var isGroup: Bool {
        switch self {
        case .addGroup, .editGroup: true
        case .addSnippet, .editSnippet: false
        }
    }

    var name: String {
        switch self {
        case .editGroup(let group): group.name
        case .editSnippet(_, let snippet): snippet.name
        default: ""
        }
    }

    var commands: [String] {
        guard case .editSnippet(_, let snippet) = self else { return [] }
        return snippet.command.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }
}

@MainActor
private final class InlineSnippetEditor: NSView, NSTextFieldDelegate {
    enum Mode: Equatable { case group, snippet }

    let firstField = NSTextField()
    private var commandFields: [NSTextField] = []
    private let addCommandButton = NSButton()
    private let saveButton = SidebarIconButton()
    private let cancelButton = SidebarIconButton()
    private let mode: Mode
    private let onSave: (String, String?) -> Void
    private let onCancel: () -> Void
    private var editorHeightConstraint: NSLayoutConstraint?
    private var commandActionTargets: [ButtonClosureTarget] = []

    init(
        mode: Mode,
        initialName: String = "",
        initialCommands: [String] = [],
        onSave: @escaping (String, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous

        configure(firstField, placeholder: mode == .group ? "Group name" : "Snippet name")
        firstField.stringValue = initialName
        addSubview(firstField)
        if mode == .snippet {
            for command in initialCommands.isEmpty ? [""] : initialCommands {
                addCommandField(value: command)
            }
            addCommandButton.title = "+ Add command"
            addCommandButton.isBordered = false
            addCommandButton.font = .systemFont(ofSize: 11.5)
            addCommandButton.contentTintColor = .secondaryLabelColor
            addCommandButton.target = self
            addCommandButton.action = #selector(addCommandClicked(_:))
            addSubview(addCommandButton)
        }

        saveButton.configure(symbol: "checkmark", toolTip: "Save", target: self, action: #selector(saveClicked(_:)))
        saveButton.contentTintColor = .controlAccentColor
        addSubview(saveButton)
        cancelButton.configure(symbol: "xmark", toolTip: "Cancel", target: self, action: #selector(cancelClicked(_:)))
        addSubview(cancelButton)
        let heightConstraint = heightAnchor.constraint(equalToConstant: preferredHeight)
        heightConstraint.isActive = true
        editorHeightConstraint = heightConstraint
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let fieldWidth = max(0, bounds.width - 72)
        if mode == .group {
            firstField.frame = CGRect(x: 10, y: 7, width: fieldWidth, height: 24)
        } else {
            firstField.frame = CGRect(x: 10, y: bounds.height - 31, width: fieldWidth, height: 22)
            for (index, field) in commandFields.enumerated() {
                let y = bounds.height - 59 - CGFloat(index * 28)
                field.frame = CGRect(x: 16, y: y, width: max(0, bounds.width - 108), height: 22)
                layoutCommandActions(at: index, y: y)
            }
            addCommandButton.frame = CGRect(x: 10, y: 7, width: 100, height: 22)
        }
        cancelButton.frame = CGRect(x: bounds.width - 27, y: bounds.height - 32, width: 22, height: 24)
        saveButton.frame = CGRect(x: cancelButton.frame.minX - 25, y: cancelButton.frame.minY, width: 22, height: 24)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel()
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if mode == .snippet, control === firstField {
                window?.makeFirstResponder(commandFields.first)
            } else if let index = commandFields.firstIndex(where: { $0 === control }) {
                if commandFields.indices.contains(index + 1) {
                    window?.makeFirstResponder(commandFields[index + 1])
                } else {
                    addCommandField(focusing: true)
                }
            } else {
                save()
            }
            return true
        }
        return false
    }

    private func configure(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12.5)
        field.delegate = self
    }

    @objc private func saveClicked(_ sender: Any?) { save() }
    @objc private func cancelClicked(_ sender: Any?) { onCancel() }
    @objc private func addCommandClicked(_ sender: Any?) { addCommandField(focusing: true) }

    private func save() {
        let name = firstField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            NSSound.beep()
            window?.makeFirstResponder(firstField)
            return
        }
        guard mode == .snippet else {
            onSave(name, nil)
            return
        }
        let commands = commandFields
            .map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !commands.isEmpty else {
            NSSound.beep()
            window?.makeFirstResponder(commandFields.first)
            return
        }
        onSave(name, commands.joined(separator: "\n"))
    }

    private var preferredHeight: CGFloat {
        mode == .group ? 38 : 70 + CGFloat(commandFields.count * 28)
    }

    private func addCommandField(value: String = "", focusing: Bool = false) {
        let field = NSTextField()
        configure(field, placeholder: "Command \(commandFields.count + 1)")
        field.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        field.stringValue = value
        commandFields.append(field)
        addSubview(field)
        rebuildCommandActions()
        editorHeightConstraint?.constant = preferredHeight
        needsLayout = true
        superview?.needsLayout = true
        if focusing {
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field else { return }
                self.window?.makeFirstResponder(field)
            }
        }
    }

    private func rebuildCommandActions() {
        subviews.filter { $0.identifier?.rawValue.hasPrefix("command-action-") == true }
            .forEach { $0.removeFromSuperview() }
        commandActionTargets.removeAll()
        for index in commandFields.indices {
            let actions: [(String, Int, () -> Void)] = [
                ("chevron.up", 0, { [weak self] in self?.moveCommand(at: index, offset: -1) }),
                ("chevron.down", 1, { [weak self] in self?.moveCommand(at: index, offset: 1) }),
                ("xmark", 2, { [weak self] in self?.removeCommand(at: index) })
            ]
            for (symbol, actionIndex, action) in actions {
                let target = ButtonClosureTarget(action: action)
                commandActionTargets.append(target)
                let button = SidebarIconButton()
                button.identifier = NSUserInterfaceItemIdentifier("command-action-\(index)-\(actionIndex)")
                button.configure(symbol: symbol, toolTip: actionIndex == 2 ? "Remove Command" : "Move Command", target: target, action: #selector(ButtonClosureTarget.invoke(_:)))
                button.contentTintColor = .tertiaryLabelColor
                addSubview(button)
            }
        }
    }

    private func layoutCommandActions(at index: Int, y: CGFloat) {
        for actionIndex in 0..<3 {
            let identifier = NSUserInterfaceItemIdentifier("command-action-\(index)-\(actionIndex)")
            guard let button = subviews.first(where: { $0.identifier == identifier }) else { continue }
            button.frame = CGRect(x: bounds.width - 82 + CGFloat(actionIndex * 24), y: y, width: 22, height: 22)
        }
    }

    private func moveCommand(at index: Int, offset: Int) {
        let destination = index + offset
        guard commandFields.indices.contains(index), commandFields.indices.contains(destination) else { return }
        commandFields.swapAt(index, destination)
        rebuildCommandActions()
        needsLayout = true
    }

    private func removeCommand(at index: Int) {
        guard commandFields.indices.contains(index) else { return }
        let field = commandFields.remove(at: index)
        field.removeFromSuperview()
        if commandFields.isEmpty { addCommandField() }
        rebuildCommandActions()
        editorHeightConstraint?.constant = preferredHeight
        needsLayout = true
        superview?.needsLayout = true
    }
}

@MainActor
private final class SnippetGroupHeaderView: NSView {
    private let toggleButton = SidebarIconButton()
    private let titleLabel: NSTextField
    private let addButton = SidebarIconButton()
    private let editButton = SidebarIconButton()
    private let deleteButton = SidebarIconButton()
    private let toggleTarget: ButtonClosureTarget
    private let addTarget: ButtonClosureTarget
    private let editTarget: ButtonClosureTarget
    private let deleteTarget: ButtonClosureTarget

    init(
        title: String,
        isCollapsed: Bool,
        onToggle: @escaping () -> Void,
        onAdd: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        titleLabel = NSTextField(labelWithString: title)
        toggleTarget = ButtonClosureTarget(action: onToggle)
        addTarget = ButtonClosureTarget(action: onAdd)
        editTarget = ButtonClosureTarget(action: onEdit)
        deleteTarget = ButtonClosureTarget(action: onDelete)
        super.init(frame: .zero)

        toggleButton.configure(
            symbol: isCollapsed ? "chevron.right" : "chevron.down",
            toolTip: isCollapsed ? "Expand Group" : "Collapse Group",
            target: toggleTarget,
            action: #selector(ButtonClosureTarget.invoke(_:))
        )
        addSubview(toggleButton)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        addButton.configure(symbol: "plus", toolTip: "Add Command", target: addTarget, action: #selector(ButtonClosureTarget.invoke(_:)))
        addSubview(addButton)
        editButton.configure(symbol: "pencil", toolTip: "Rename Group", target: editTarget, action: #selector(ButtonClosureTarget.invoke(_:)))
        editButton.contentTintColor = .tertiaryLabelColor
        addSubview(editButton)
        deleteButton.configure(symbol: "trash", toolTip: "Delete Group", target: deleteTarget, action: #selector(ButtonClosureTarget.invoke(_:)))
        deleteButton.contentTintColor = .tertiaryLabelColor
        addSubview(deleteButton)

        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        toggleButton.frame = CGRect(x: 0, y: 3, width: 22, height: 22)
        titleLabel.frame = CGRect(x: 26, y: 4, width: max(0, bounds.width - 106), height: 20)
        deleteButton.frame = CGRect(x: bounds.width - 23, y: 3, width: 22, height: 22)
        editButton.frame = CGRect(x: deleteButton.frame.minX - 24, y: 3, width: 22, height: 22)
        addButton.frame = CGRect(x: editButton.frame.minX - 24, y: 3, width: 22, height: 22)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            editTarget.invoke(self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        for button in [toggleButton, addButton, editButton, deleteButton] where button.frame.contains(localPoint) {
            return button.hitTest(localPoint)
        }
        return bounds.contains(localPoint) ? self : nil
    }
}

@MainActor
private final class SnippetCommandRow: NSView {
    private let iconView = NSImageView()
    private let titleLabel: NSTextField
    private let commandLabel: NSTextField
    private let runButton = SidebarIconButton()
    private let editButton = SidebarIconButton()
    private let deleteButton = SidebarIconButton()
    private let insertTarget: ButtonClosureTarget
    private let runTarget: ButtonClosureTarget
    private let editTarget: ButtonClosureTarget
    private let deleteTarget: ButtonClosureTarget
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(
        snippet: CommandSnippet,
        onInsert: @escaping () -> Void,
        onRun: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        let commands = snippet.command
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let preview = commands.first ?? snippet.command
        titleLabel = NSTextField(labelWithString: snippet.name)
        commandLabel = NSTextField(labelWithString: commands.count > 1 ? "\(commands.count) commands  ·  \(preview)" : preview)
        insertTarget = ButtonClosureTarget(action: onInsert)
        runTarget = ButtonClosureTarget(action: onRun)
        editTarget = ButtonClosureTarget(action: onEdit)
        deleteTarget = ButtonClosureTarget(action: onDelete)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous

        iconView.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Command")
        iconView.contentTintColor = .secondaryLabelColor
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        commandLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        commandLabel.textColor = .tertiaryLabelColor
        commandLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(commandLabel)

        runButton.configure(symbol: "play.fill", toolTip: "Run Snippet", target: runTarget, action: #selector(ButtonClosureTarget.invoke(_:)))
        addSubview(runButton)
        editButton.configure(symbol: "pencil", toolTip: "Edit Snippet", target: editTarget, action: #selector(ButtonClosureTarget.invoke(_:)))
        editButton.contentTintColor = .tertiaryLabelColor
        addSubview(editButton)
        deleteButton.configure(symbol: "xmark", toolTip: "Delete Command", target: deleteTarget, action: #selector(ButtonClosureTarget.invoke(_:)))
        deleteButton.contentTintColor = .tertiaryLabelColor
        addSubview(deleteButton)
        heightAnchor.constraint(equalToConstant: 46).isActive = true
        updateHoverAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        iconView.frame = CGRect(x: 10, y: 14, width: 18, height: 18)
        let actionsWidth: CGFloat = isHovered ? 73 : 25
        titleLabel.frame = CGRect(x: 36, y: 23, width: max(0, bounds.width - 46 - actionsWidth), height: 17)
        commandLabel.frame = CGRect(x: 36, y: 7, width: max(0, bounds.width - 46 - actionsWidth), height: 14)
        runButton.frame = CGRect(x: bounds.width - 28, y: 11, width: 23, height: 24)
        editButton.frame = CGRect(x: runButton.frame.minX - 24, y: 11, width: 22, height: 24)
        deleteButton.frame = CGRect(x: editButton.frame.minX - 24, y: 11, width: 22, height: 24)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateHoverAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateHoverAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            editTarget.invoke(self)
        } else {
            insertTarget.invoke(self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        if runButton.frame.contains(localPoint) {
            return runButton.hitTest(localPoint)
        }
        if !editButton.isHidden, editButton.frame.contains(localPoint) {
            return editButton.hitTest(localPoint)
        }
        if !deleteButton.isHidden, deleteButton.frame.contains(localPoint) {
            return deleteButton.hitTest(localPoint)
        }
        return bounds.contains(localPoint) ? self : nil
    }

    private func updateHoverAppearance() {
        layer?.backgroundColor = isHovered
            ? NSColor.systemPurple.withAlphaComponent(0.14).cgColor
            : NSColor.white.withAlphaComponent(0.025).cgColor
        editButton.isHidden = !isHovered
        deleteButton.isHidden = !isHovered
        runButton.contentTintColor = isHovered ? .controlAccentColor : .secondaryLabelColor
        needsLayout = true
    }
}

@MainActor
private final class SidebarEmptyStateView: NSView {
    var onAdd: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: "No snippets yet")
    private let detailLabel = NSTextField(wrappingLabelWithString: "Create a group and keep your most-used commands one click away.")
    private let addButton = NSButton(title: "Create Group", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.035).cgColor
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        addButton.bezelStyle = .rounded
        addButton.controlSize = .small
        addButton.target = self
        addButton.action = #selector(addClicked(_:))
        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(addButton)
        heightAnchor.constraint(equalToConstant: 126).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        titleLabel.frame = CGRect(x: 14, y: bounds.height - 36, width: bounds.width - 28, height: 20)
        detailLabel.frame = CGRect(x: 14, y: bounds.height - 77, width: bounds.width - 28, height: 36)
        addButton.frame = CGRect(x: 14, y: 13, width: 102, height: 26)
    }

    @objc private func addClicked(_ sender: Any?) { onAdd?() }
}

private final class SidebarIconButton: NSButton {
    func configure(symbol: String, toolTip: String, target: AnyObject?, action: Selector?) {
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
        imageScaling = .scaleProportionallyDown
        isBordered = false
        contentTintColor = .secondaryLabelColor
        self.toolTip = toolTip
        self.target = target
        self.action = action
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

private final class SidebarScrollView: NSScrollView {
    var onSwipeRight: (() -> Void)?
    private var gestureTranslation = CGPoint.zero
    private var didTriggerSwipe = false

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else {
            super.scrollWheel(with: event)
            return
        }

        if event.phase == .mayBegin || event.phase == .began {
            gestureTranslation = .zero
            didTriggerSwipe = false
        }
        guard !didTriggerSwipe else { return }

        gestureTranslation.x += event.scrollingDeltaX
        gestureTranslation.y += event.scrollingDeltaY
        let horizontalDistance = abs(gestureTranslation.x)

        if gestureTranslation.x > 0,
           horizontalDistance >= 42,
           horizontalDistance > abs(gestureTranslation.y) {
            didTriggerSwipe = true
            onSwipeRight?()
            return
        }

        if event.phase == .ended || event.phase == .cancelled {
            gestureTranslation = .zero
        }
        super.scrollWheel(with: event)
    }
}

private final class SidebarDecorationView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class ButtonClosureTarget: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func invoke(_ sender: Any?) { action() }
}
