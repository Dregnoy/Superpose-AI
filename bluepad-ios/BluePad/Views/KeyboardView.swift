import SwiftUI
import UIKit

struct KeyboardView: View {
    @ObservedObject var viewModel: AppViewModel

    enum DeckSegment: String, CaseIterable, Identifiable {
        case standard = "Standart"
        case function = "F1-F12"
        case numpad = "Numpad"
        case shortcuts = "Kısayol"

        var id: String { rawValue }
    }

    @State private var selectedSegment: DeckSegment = .standard
    @State private var isSoftKeyboardActive = false
    @State private var showBatchComposer = false
    @State private var batchText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Hidden UIKeyInput bridge for direct key-by-key typing
                LiveKeyInputRepresentable(
                    isActive: isSoftKeyboardActive,
                    onCharacter: { ch in
                        viewModel.sendTypedCharacter(ch)
                    },
                    onBackspace: {
                        viewModel.sendKey(.backspace)
                    },
                    onEnter: {
                        viewModel.sendKey(.enter)
                    }
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)

                // Top bar: Layout Picker + Soft Keyboard + Batch Composer
                HStack(spacing: 8) {
                    Menu {
                        ForEach(KeyboardLayoutKind.allCases) { layout in
                            Button {
                                viewModel.settings.keyboardLayout = layout
                                viewModel.showToast("Klavye düzeni: \(layout.displayName)")
                            } label: {
                                Label(
                                    layout.displayName,
                                    systemImage: viewModel.settings.keyboardLayout == layout ? "checkmark" : "globe"
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "globe")
                            Text(viewModel.settings.keyboardLayout.displayName)
                                .lineLimit(1)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BluePadTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(BluePadTheme.bgElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(BluePadTheme.borderSubtle, lineWidth: 1)
                                )
                        )
                    }

                    Button {
                        isSoftKeyboardActive.toggle()
                        viewModel.triggerHaptic(.light)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isSoftKeyboardActive ? "keyboard.chevron.compact.down.fill" : "keyboard.fill")
                            Text(isSoftKeyboardActive ? "Klavyeyi Kapat" : "iOS Klavye")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isSoftKeyboardActive ? BluePadTheme.bgPrimary : BluePadTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSoftKeyboardActive ? BluePadTheme.accentCyan : BluePadTheme.accentBlue.opacity(0.28))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(BluePadTheme.accentCyan.opacity(0.55), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showBatchComposer.toggle()
                        }
                        viewModel.triggerHaptic(.light)
                    } label: {
                        Image(systemName: "text.bubble.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(showBatchComposer ? BluePadTheme.bgPrimary : BluePadTheme.accentCyan)
                            .frame(width: 40, height: 35)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(showBatchComposer ? BluePadTheme.accentCyan : BluePadTheme.bgElevated)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Toplu Metin Gönder")
                }

                // Batch Text / Clipboard Composer
                if showBatchComposer || viewModel.isTypingText {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Toplu Metin / Pano Gönder", systemImage: "doc.text.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BluePadTheme.accentCyan)
                            Spacer()
                            Button("Panodan Al") {
                                if let str = UIPasteboard.general.string {
                                    batchText = str
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BluePadTheme.accentMint)
                        }

                        TextEditor(text: $batchText)
                            .frame(height: 82)
                            .padding(6)
                            .scrollContentBackground(.hidden)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(BluePadTheme.bgPrimary)
                            )
                            .font(.subheadline)
                            .foregroundStyle(.white)

                        if viewModel.isTypingText {
                            HStack(spacing: 10) {
                                ProgressView(value: viewModel.typingProgress)
                                    .tint(BluePadTheme.accentCyan)
                                Button("Durdur") {
                                    viewModel.cancelTyping()
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BluePadTheme.accentRose)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Button {
                                    isSoftKeyboardActive = false
                                    viewModel.typeText(batchText, appendEnter: false)
                                } label: {
                                    Label("Yaz", systemImage: "paperplane.fill")
                                        .font(.caption.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                }
                                .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.accentBlue.opacity(0.35), border: BluePadTheme.accentCyan))
                                .disabled(batchText.isEmpty)

                                Button {
                                    isSoftKeyboardActive = false
                                    viewModel.typeText(batchText, appendEnter: true)
                                } label: {
                                    Label("Yaz + Enter", systemImage: "return")
                                        .font(.caption.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                }
                                .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.accentMint.opacity(0.25), border: BluePadTheme.accentMint.opacity(0.6)))
                                .disabled(batchText.isEmpty)

                                Button {
                                    batchText = ""
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                }
                                .buttonStyle(KeycapButtonStyle())
                            }
                        }
                    }
                    .glassCard(cornerRadius: 16, padding: 12)
                }

                // Sticky / Lockable Modifier Keys Bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("DEĞİŞTİRİCİ TUŞLAR")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(BluePadTheme.textSecondary)
                        Spacer()
                        Text("Dokun: 1 kez · Çift dokun: Kilitle")
                            .font(.system(size: 10))
                            .foregroundStyle(BluePadTheme.textSecondary)
                    }

                    HStack(spacing: 7) {
                        modifierKey("Ctrl", modifier: .leftControl)
                        modifierKey("Alt", modifier: .leftAlt)
                        modifierKey("AltGr", modifier: .rightAlt)
                        modifierKey("Shift", modifier: .leftShift)
                        modifierKey("Win/⌘", modifier: .leftGUI)
                    }
                }
                .glassCard(cornerRadius: 16, padding: 10)

                // Segmented Hardware Deck Picker
                Picker("Tuş Takımı", selection: $selectedSegment) {
                    ForEach(DeckSegment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)

                // Selected Key Deck
                switch selectedSegment {
                case .standard:
                    standardAndArrowsDeck
                case .function:
                    functionKeysDeck
                case .numpad:
                    numpadDeck
                case .shortcuts:
                    shortcutsDeck
                }
            }
            .padding(14)
        }
        .background(BluePadTheme.bgPrimary)
    }

    // MARK: Modifier Key Pill

    private func modifierKey(_ title: String, modifier: HIDModifier) -> some View {
        let isLocked = viewModel.lockedModifiers.contains(modifier)
        let isArmed = viewModel.armedModifiers.contains(modifier)

        let fillColor: Color = isLocked
            ? BluePadTheme.accentAmber
            : (isArmed ? BluePadTheme.accentCyan : BluePadTheme.bgKeycap)
        let textColor: Color = (isLocked || isArmed) ? BluePadTheme.bgPrimary : BluePadTheme.textPrimary

        return VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.bold))
            if isLocked {
                Text("KİLİT")
                    .font(.system(size: 8, weight: .black))
            } else if isArmed {
                Text("1x")
                    .font(.system(size: 8, weight: .black))
            }
        }
        .foregroundStyle(textColor)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(BluePadTheme.borderSubtle, lineWidth: 1)
                )
        )
        .onTapGesture(count: 2) {
            viewModel.toggleLockModifier(modifier)
        }
        .onTapGesture(count: 1) {
            viewModel.tapModifier(modifier)
        }
    }

    // MARK: Key Decks

    private var standardAndArrowsDeck: some View {
        VStack(spacing: 10) {
            // Top navigation / system keys
            HStack(spacing: 8) {
                hwKey("Esc", code: .escape)
                hwKey("Tab", code: .tab)
                hwKey("Caps", code: .capsLock, highlight: viewModel.ledState.contains(.capsLock))
                hwKey("Del", code: .deleteForward)
                hwKey("Bksp", code: .backspace, icon: "delete.left")
            }

            HStack(spacing: 8) {
                hwKey("Ins", code: .insert)
                hwKey("Home", code: .home)
                hwKey("PgUp", code: .pageUp)
                hwKey("PrtSc", code: .printScreen)
                hwKey("Menü", code: .application)
            }

            HStack(spacing: 8) {
                hwKey("End", code: .end)
                hwKey("PgDn", code: .pageDown)
                hwKey("Boşluk", code: .space)
                hwKey("Enter ⏎", code: .enter, accent: true)
            }

            // Ergonomic Inverted-T Arrow Pad
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Spacer()
                    arrowKey(systemImage: "chevron.up", code: .upArrow)
                    Spacer()
                }
                HStack(spacing: 8) {
                    arrowKey(systemImage: "chevron.left", code: .leftArrow)
                    arrowKey(systemImage: "chevron.down", code: .downArrow)
                    arrowKey(systemImage: "chevron.right", code: .rightArrow)
                }
            }
            .padding(.top, 4)

            // Panic Release Button
            Button {
                viewModel.releaseAllInputs()
            } label: {
                Label("Tüm Basılı Tuşları Sıfırla", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BluePadTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.bgCard))
        }
    }

    private var functionKeysDeck: some View {
        let fKeys: [(String, HIDKeyCode)] = [
            ("F1", .f1), ("F2", .f2), ("F3", .f3), ("F4", .f4),
            ("F5", .f5), ("F6", .f6), ("F7", .f7), ("F8", .f8),
            ("F9", .f9), ("F10", .f10), ("F11", .f11), ("F12", .f12)
        ]

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(fKeys, id: \.0) { label, code in
                hwKey(label, code: code, height: 52)
            }
        }
    }

    private var numpadDeck: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                hwKey("Num", code: .numLock, highlight: viewModel.ledState.contains(.numLock))
                hwKey("/", code: .kpDivide)
                hwKey("*", code: .kpMultiply)
                hwKey("-", code: .kpMinus)
            }
            HStack(spacing: 8) {
                hwKey("7", code: .kp7)
                hwKey("8", code: .kp8)
                hwKey("9", code: .kp9)
                hwKey("+", code: .kpPlus)
            }
            HStack(spacing: 8) {
                hwKey("4", code: .kp4)
                hwKey("5", code: .kp5)
                hwKey("6", code: .kp6)
                hwKey("Bksp", code: .backspace, icon: "delete.left")
            }
            HStack(spacing: 8) {
                hwKey("1", code: .kp1)
                hwKey("2", code: .kp2)
                hwKey("3", code: .kp3)
                hwKey("⏎", code: .kpEnter, accent: true)
            }
            HStack(spacing: 8) {
                hwKey("0", code: .kp0)
                hwKey(".", code: .kpPeriod)
                hwKey("Tab", code: .tab)
            }
        }
    }

    private var shortcutsDeck: some View {
        let primaryMod = viewModel.settings.hostOS.primaryModifier
        let modTag = viewModel.settings.hostOS.primaryModifierLabel
        let lock = viewModel.settings.hostOS.lockScreenCombo
        let switcher = viewModel.settings.hostOS.taskSwitcherCombo
        let shot = viewModel.settings.hostOS.screenshotCombo
        let desktop = viewModel.settings.hostOS.showDesktopCombo
        let taskMgr = viewModel.settings.hostOS.taskManagerCombo

        let items: [(String, String, UInt8, HIDModifier)] = [
            ("Kopyala", "\(modTag)+C", HIDKeyCode.c.rawValue, primaryMod),
            ("Yapıştır", "\(modTag)+V", HIDKeyCode.v.rawValue, primaryMod),
            ("Kes", "\(modTag)+X", HIDKeyCode.x.rawValue, primaryMod),
            ("Geri Al", "\(modTag)+Z", HIDKeyCode.z.rawValue, primaryMod),
            ("Yinele", "\(modTag)+Y", HIDKeyCode.y.rawValue, primaryMod),
            ("Tümünü Seç", "\(modTag)+A", HIDKeyCode.a.rawValue, primaryMod),
            ("Bul", "\(modTag)+F", HIDKeyCode.f.rawValue, primaryMod),
            ("Kaydet", "\(modTag)+S", HIDKeyCode.s.rawValue, primaryMod),
            ("Sekme Kapat", "\(modTag)+W", HIDKeyCode.w.rawValue, primaryMod),
            ("Yeni Sekme", "\(modTag)+T", HIDKeyCode.t.rawValue, primaryMod),
            ("Pencere Geç", "Alt/⌘+Tab", switcher.keyCode, switcher.modifiers),
            ("Masaüstü", "Masaüstü", desktop.keyCode, desktop.modifiers),
            ("Ekran Kilitle", "Kilit", lock.keyCode, lock.modifiers),
            ("Ekran Görüntü", "Yakala", shot.keyCode, shot.modifiers),
            ("Görev Yön.", "Sistem", taskMgr.keyCode, taskMgr.modifiers)
        ]

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(items, id: \.0) { title, sub, code, mods in
                Button {
                    viewModel.sendRawKey(code, extraModifiers: mods)
                } label: {
                    VStack(spacing: 3) {
                        Text(title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BluePadTheme.textPrimary)
                            .lineLimit(1)
                        Text(sub)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(BluePadTheme.accentCyan)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .buttonStyle(KeycapButtonStyle())
            }
        }
    }

    // MARK: Key Helpers

    private func hwKey(
        _ title: String,
        code: HIDKeyCode,
        icon: String? = nil,
        accent: Bool = false,
        highlight: Bool = false,
        height: CGFloat = 46
    ) -> some View {
        Button {
            viewModel.sendKey(code)
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption.weight(.bold))
                }
                if icon == nil || title != "Bksp" {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if highlight {
                    Circle()
                        .fill(BluePadTheme.accentAmber)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(accent ? BluePadTheme.bgPrimary : BluePadTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
        .buttonStyle(
            KeycapButtonStyle(
                fill: accent ? BluePadTheme.accentCyan : BluePadTheme.bgKeycap,
                border: highlight ? BluePadTheme.accentAmber : BluePadTheme.borderSubtle
            )
        )
    }

    private func arrowKey(systemImage: String, code: HIDKeyCode) -> some View {
        Button {
            viewModel.sendKey(code)
        } label: {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(BluePadTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(KeycapButtonStyle())
    }
}

// MARK: - UIKeyInput Direct Keystroke Bridge

struct LiveKeyInputRepresentable: UIViewRepresentable {
    var isActive: Bool
    var onCharacter: (Character) -> Void
    var onBackspace: () -> Void
    var onEnter: () -> Void

    func makeUIView(context: Context) -> LiveKeyInputView {
        let view = LiveKeyInputView()
        sync(view)
        return view
    }

    func updateUIView(_ uiView: LiveKeyInputView, context: Context) {
        sync(uiView)
        if isActive && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
            }
        } else if !isActive && uiView.isFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.resignFirstResponder()
            }
        }
    }

    private func sync(_ view: LiveKeyInputView) {
        view.onCharacter = onCharacter
        view.onBackspace = onBackspace
        view.onEnter = onEnter
    }
}

final class LiveKeyInputView: UIView, UIKeyInput {
    var onCharacter: ((Character) -> Void)?
    var onBackspace: (() -> Void)?
    var onEnter: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    var hasText: Bool { true }

    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardAppearance: UIKeyboardAppearance = .dark

    func insertText(_ text: String) {
        for ch in text {
            if ch == "\n" || ch == "\r" {
                onEnter?()
            } else {
                onCharacter?(ch)
            }
        }
    }

    func deleteBackward() {
        onBackspace?()
    }
}
