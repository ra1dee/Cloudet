import AppKit
import SwiftUI

@MainActor
final class ShortcutSettings: ObservableObject {
    @Published var combo: KeyCombo?
    @Published var isRecording = false
    @Published private(set) var issue: ShortcutIssue?

    private let hotKeys: HotKeyCenter

    init(hotKeys: HotKeyCenter) {
        self.hotKeys = hotKeys
        combo = hotKeys.combo ?? ShortcutStore.load()
        issue = warningIssue(for: combo)
    }

    func refreshIssue() {
        issue = hotKeys.apply(combo, persist: false)
    }

    private func warningIssue(for combo: KeyCombo?) -> ShortcutIssue? {
        guard let combo else { return nil }
        guard ShortcutRules.hasChordModifier(combo.flags) else { return .needsModifier }
        return ShortcutRules.isReserved(combo, system: SystemHotKeys.enabled()) ? .reservedBySystem : nil
    }

    func noteNeedsModifier() {
        issue = .needsModifier
    }

    func update(_ combo: KeyCombo?) {
        self.combo = combo
        isRecording = false
        issue = hotKeys.apply(combo, persist: true)
    }

    var warning: String? {
        switch issue {
        case .needsModifier:
            return L10n.tr("Use Command, Option, or Control.")
        case .reservedBySystem:
            return L10n.tr("This shortcut is reserved by macOS.")
        case .alreadyInUse:
            return L10n.tr("This shortcut is already in use.")
        case nil:
            return nil
        }
    }
}

@MainActor
final class SettingsWindow {
    private let window: NSWindow
    private let settings: ShortcutSettings

    init(hotKeys: HotKeyCenter) {
        settings = ShortcutSettings(hotKeys: hotKeys)
        let host = NSHostingView(rootView: SettingsView(model: settings))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 210),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("Settings")
        window.titlebarSeparatorStyle = .none
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
    }

    func show() {
        settings.refreshIssue()
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: ShortcutSettings

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.tr("Show or Hide Cloud")) {
                    HStack(spacing: 8) {
                        ShortcutWell(model: model)
                        if model.combo != nil, !model.isRecording {
                            Button {
                                model.update(nil)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.tr("Clear Shortcut"))
                            .accessibilityLabel(L10n.tr("Clear Shortcut"))
                        }
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                footnote
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 210, alignment: .top)
    }

    private var footnote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if model.warning != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
            }
            Text(model.warning ?? L10n.tr("Click the field and press a shortcut."))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(model.warning == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShortcutWell: View {
    @ObservedObject var model: ShortcutSettings

    var body: some View {
        HStack(spacing: 4) {
            if model.isRecording {
                Text(L10n.tr("Type a shortcut"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .phaseAnimator([0.45, 1]) { content, phase in
                        content.opacity(phase)
                    } animation: { _ in
                        .easeInOut(duration: 0.85)
                    }
            } else if let combo = model.combo {
                ForEach(Array(KeyComboLabel.parts(for: combo).enumerated()), id: \.offset) { _, part in
                    KeyCap(text: part)
                }
            } else {
                Text(L10n.tr("Record Shortcut"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
        .frame(minWidth: 148, minHeight: 34)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(model.isRecording ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    model.isRecording ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.10),
                    lineWidth: model.isRecording ? 1.5 : 1
                )
        }
        .animation(.easeOut(duration: 0.16), value: model.isRecording)
        .animation(.easeOut(duration: 0.16), value: model.combo)
        .overlay {
            ShortcutRecorderRepresentable(model: model)
        }
    }
}

private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: text.count > 1 ? 11 : 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, text.count > 1 ? 7 : 5)
            .frame(minWidth: 24, minHeight: 24)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 0.4, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.7)
            }
    }
}

private struct ShortcutRecorderRepresentable: NSViewRepresentable {
    @ObservedObject var model: ShortcutSettings

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onChange = { model.update($0) }
        view.onNeedsModifier = { model.noteNeedsModifier() }
        view.onRecording = { model.isRecording = $0 }
        view.focusRingType = .none
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.combo = model.combo
        view.isRecording = model.isRecording
        view.onChange = { model.update($0) }
        view.onNeedsModifier = { model.noteNeedsModifier() }
        view.onRecording = { model.isRecording = $0 }
    }
}

final class ShortcutRecorderView: NSView {
    var combo: KeyCombo? {
        didSet { needsDisplay = true }
    }
    var isRecording = false {
        didSet { needsDisplay = true }
    }
    var onChange: ((KeyCombo?) -> Void)?
    var onNeedsModifier: (() -> Void)?
    var onRecording: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { endRecording() }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        let mods = ShortcutRules.chord(from: event.modifierFlags)
        if event.keyCode == 53, !ShortcutRules.hasChordModifier(mods) {
            endRecording()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            onChange?(nil)
            endRecording()
            return
        }
        guard ShortcutRules.hasChordModifier(mods) else {
            onNeedsModifier?()
            return
        }
        onChange?(KeyCombo(keyCode: event.keyCode, modifiers: mods))
        endRecording()
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        onRecording?(true)
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        onRecording?(false)
        window?.makeFirstResponder(nil)
    }
}
