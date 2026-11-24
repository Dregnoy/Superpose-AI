import SwiftUI
import UIKit

struct ToolsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showMacroEditor = false
    @State private var clipboardPreview: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 1. Keep-Alive / Mouse Jiggler
                jigglerCard

                // 2. Custom Macros Grid
                macrosCard

                // 3. QR & Barcode Scanner
                scannerCard

                // 4. Voice Dictation
                DictationCardView(
                    dictation: viewModel.dictationService,
                    onSendText: { text, appendEnter in
                        viewModel.typeText(text, appendEnter: appendEnter)
                    }
                )

                // 5. Clipboard Sender
                clipboardCard
            }
            .padding(14)
        }
        .background(BluePadTheme.bgPrimary)
        .onAppear {
            refreshClipboardPreview()
        }
        .sheet(isPresented: $showMacroEditor) {
            MacroEditorSheet { newMacro in
                viewModel.addOrUpdateMacro(newMacro)
            }
        }
    }

    // MARK: Keep-Alive Jiggler

    private var jigglerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Uyanık Tut (Mouse Jiggler)", systemImage: "cup.and.saucer.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.amberOrPrimary(viewModel.isJigglerActive))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.isJigglerActive },
                    set: { active in
                        if active != viewModel.isJigglerActive {
                            viewModel.toggleJiggler()
                        }
                    }
                ))
                .labelsHidden()
                .tint(BluePadTheme.accentAmber)
            }

            Text(
                viewModel.isJigglerActive
                    ? "Aktif · Sonraki darbe: \(viewModel.jigglerCountdownSeconds) saniye (Ekran açık tutuluyor)"
                    : "Bilgisayarın uyku moduna geçmesini veya ekran kilidini önlemek için periyodik gizli HID sinyali gönderir."
            )
            .font(.caption)
            .foregroundStyle(BluePadTheme.textSecondary)

            HStack(spacing: 8) {
                ForEach([15, 30, 45, 60, 120], id: \.self) { sec in
                    Button {
                        viewModel.settings.jigglerIntervalSeconds = sec
                        viewModel.triggerHaptic(.light)
                    } label: {
                        Text("\(sec)s")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(viewModel.settings.jigglerIntervalSeconds == sec ? BluePadTheme.bgPrimary : BluePadTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(viewModel.settings.jigglerIntervalSeconds == sec ? BluePadTheme.accentAmber : BluePadTheme.bgKeycap)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("Yöntem", selection: $viewModel.settings.jigglerMode) {
                ForEach(JigglerMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .glassCard()
    }

    // MARK: Custom Macros Grid

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Özel Makrolar ve Kısayollar", systemImage: "square.grid.2x2.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentCyan)
                Spacer()
                Menu {
                    Button {
                        showMacroEditor = true
                    } label: {
                        Label("Yeni Makro Ekle", systemImage: "plus")
                    }
                    Button(role: .destructive) {
                        viewModel.resetDefaultMacros()
                    } label: {
                        Label("Varsayılanları Geri Yükle", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(BluePadTheme.textSecondary)
                }

                Button {
                    showMacroEditor = true
                } label: {
                    Label("Ekle", systemImage: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BluePadTheme.bgPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(BluePadTheme.accentCyan))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(viewModel.macros) { macro in
                    Button {
                        viewModel.runMacro(macro)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: macro.sfSymbol)
                                .font(.headline)
                                .foregroundStyle(Color(hex: macro.accentHex))
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(hex: macro.accentHex).opacity(0.16))
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(macro.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BluePadTheme.textPrimary)
                                    .lineLimit(1)
                                Text(macro.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(BluePadTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                    }
                    .buttonStyle(KeycapButtonStyle(cornerRadius: 14))
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.deleteMacro(id: macro.id)
                        } label: {
                            Label("Makroyu Sil", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: QR & Barcode Scanner

    private var scannerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("QR & Barkod Tarayıcı", systemImage: "qrcode.viewfinder")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentViolet)
                Spacer()
                Toggle("Otomatik Enter", isOn: $viewModel.settings.scannerAutoEnter)
                    .labelsHidden()
                    .tint(BluePadTheme.accentViolet)
                Text("Enter")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BluePadTheme.textSecondary)
            }

            Button {
                viewModel.isScannerPresented = true
            } label: {
                Label("Kamerayı Aç ve Tara", systemImage: "camera.viewfinder")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.bgPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.accentViolet, border: BluePadTheme.accentViolet))

            if !viewModel.lastScannedBarcode.isEmpty {
                HStack {
                    Text("Son: \(viewModel.lastScannedBarcode)")
                        .font(.caption.monospaced())
                        .foregroundStyle(BluePadTheme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Tekrar Yaz") {
                        viewModel.typeText(viewModel.lastScannedBarcode, appendEnter: viewModel.settings.scannerAutoEnter)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentCyan)
                }
            }
        }
        .glassCard()
    }

    // MARK: Clipboard Card

    private var clipboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Pano Gönderici", systemImage: "doc.on.clipboard.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BluePadTheme.accentMint)
                Spacer()
                Button("Yenile") {
                    refreshClipboardPreview()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(BluePadTheme.accentCyan)
            }

            Text(clipboardPreview.isEmpty ? "iPhone panosu şu anda boş görünüyor." : clipboardPreview)
                .font(.caption)
                .foregroundStyle(BluePadTheme.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BluePadTheme.bgPrimary)
                )

            HStack(spacing: 8) {
                Button {
                    viewModel.pasteClipboard(appendEnter: false)
                } label: {
                    Label("Panoyu Yaz", systemImage: "paperplane.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BluePadTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(KeycapButtonStyle())

                Button {
                    viewModel.pasteClipboard(appendEnter: true)
                } label: {
                    Label("Yaz + Enter", systemImage: "return")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BluePadTheme.bgPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.accentMint, border: BluePadTheme.accentMint))
            }
        }
        .glassCard()
    }

    private func refreshClipboardPreview() {
        clipboardPreview = UIPasteboard.general.string ?? ""
    }
}

private extension BluePadTheme {
    static func amberOrPrimary(_ active: Bool) -> Color {
        active ? accentAmber : textPrimary
    }
}

// MARK: - Observed Speech Dictation Subview

private struct DictationCardView: View {
    @ObservedObject var dictation: SpeechDictationService
    let onSendText: (String, Bool) -> Void

    @State private var locale: DictationLocale = .turkish

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Sesle Yazma (Dikte)", systemImage: "mic.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(dictation.isRecording ? BluePadTheme.accentRose : BluePadTheme.accentCyan)
                Spacer()
                Picker("Dil", selection: $locale) {
                    ForEach(DictationLocale.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .tint(BluePadTheme.accentCyan)
            }

            TextEditor(text: $dictation.transcript)
                .frame(height: 76)
                .padding(6)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BluePadTheme.bgPrimary)
                )
                .font(.subheadline)
                .foregroundStyle(.white)

            if let err = dictation.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(BluePadTheme.accentRose)
            }

            HStack(spacing: 8) {
                Button {
                    dictation.toggleRecording(locale: locale)
                } label: {
                    Label(
                        dictation.isRecording ? "Durdur" : "Dinle",
                        systemImage: dictation.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                }
                .buttonStyle(
                    KeycapButtonStyle(
                        fill: dictation.isRecording ? BluePadTheme.accentRose : BluePadTheme.accentBlue.opacity(0.45),
                        border: dictation.isRecording ? BluePadTheme.accentRose : BluePadTheme.accentCyan
                    )
                )

                Button {
                    onSendText(dictation.transcript, false)
                } label: {
                    Label("Yaz", systemImage: "keyboard")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BluePadTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(KeycapButtonStyle())
                .disabled(dictation.transcript.isEmpty)

                Button {
                    onSendText(dictation.transcript, true)
                } label: {
                    Label("Yaz + ⏎", systemImage: "return")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BluePadTheme.bgPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(KeycapButtonStyle(fill: BluePadTheme.accentCyan, border: BluePadTheme.accentCyan))
                .disabled(dictation.transcript.isEmpty)
            }
        }
        .glassCard()
    }
}

// MARK: - Custom Macro Editor Sheet

private struct MacroEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (CustomMacro) -> Void

    enum ActionKind: String, CaseIterable, Identifiable {
        case keyCombo = "Tuş Kombinasyonu"
        case typeText = "Metin Yaz"
        case consumer = "Medya Tuşu"
        case system = "Sistem"

        var id: String { rawValue }
    }

    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var category: MacroCategory = .custom
    @State private var selectedSymbol: String = "bolt.fill"
    @State private var selectedHex: String = "#38BDF8"
    @State private var actionKind: ActionKind = .keyCombo

    // Key combo state
    @State private var selectedKeyCode: HIDKeyCode = .a
    @State private var useCtrl = true
    @State private var useShift = false
    @State private var useAlt = false
    @State private var useAltGr = false
    @State private var useGUI = false

    // Type text state
    @State private var textPayload = ""
    @State private var appendEnter = true

    // Consumer / System state
    @State private var selectedConsumer: HIDConsumerUsage = .playPause
    @State private var selectedSystemRaw: UInt8 = HIDSystemUsage.sleep.rawValue

    private let symbolChoices = [
        "bolt.fill", "terminal.fill", "lock.fill", "camera.viewfinder",
        "playpause.fill", "doc.on.clipboard.fill", "star.fill", "keyboard.fill",
        "folder.fill", "wand.and.stars", "speaker.wave.2.fill", "power"
    ]

    private let colorChoices = [
        "#38BDF8", "#34D399", "#A78BFA", "#FBBF24", "#FB7185", "#60A5FA"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Makro Bilgileri") {
                    TextField("Başlık (örn. Terminali Aç)", text: $title)
                    TextField("Alt Başlık (isteğe bağlı)", text: $subtitle)
                    Picker("Kategori", selection: $category) {
                        ForEach(MacroCategory.allCases) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }
                }

                Section("Eylem Tipi") {
                    Picker("Eylem", selection: $actionKind) {
                        ForEach(ActionKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch actionKind {
                    case .keyCombo:
                        Picker("Ana Tuş", selection: $selectedKeyCode) {
                            ForEach(HIDKeyCode.allCases.filter { $0 != .none }, id: \.self) { code in
                                Text(code.displayName).tag(code)
                            }
                        }
                        Toggle("Ctrl", isOn: $useCtrl)
                        Toggle("Shift", isOn: $useShift)
                        Toggle("Alt", isOn: $useAlt)
                        Toggle("AltGr", isOn: $useAltGr)
                        Toggle("Win / ⌘", isOn: $useGUI)

                    case .typeText:
                        TextField("Yazılacak metin", text: $textPayload)
                        Toggle("Sonuna Enter ekle", isOn: $appendEnter)

                    case .consumer:
                        Picker("Medya İşlevi", selection: $selectedConsumer) {
                            ForEach(HIDConsumerUsage.allCases.filter { $0 != .none }, id: \.self) { item in
                                Text(item.displayName).tag(item)
                            }
                        }

                    case .system:
                        Picker("Sistem Komutu", selection: $selectedSystemRaw) {
                            Text("Uyku (Sleep)").tag(HIDSystemUsage.sleep.rawValue)
                            Text("Uyandır (Wake)").tag(HIDSystemUsage.wakeUp.rawValue)
                            Text("Güç (Power Down)").tag(HIDSystemUsage.powerDown.rawValue)
                        }
                    }
                }

                Section("Simge ve Renk") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(symbolChoices, id: \.self) { sym in
                            Button {
                                selectedSymbol = sym
                            } label: {
                                Image(systemName: sym)
                                    .font(.headline)
                                    .foregroundStyle(selectedSymbol == sym ? Color(hex: selectedHex) : .secondary)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedSymbol == sym ? Color(hex: selectedHex).opacity(0.2) : Color.secondary.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)

                    HStack(spacing: 14) {
                        ForEach(colorChoices, id: \.self) { hex in
                            Button {
                                selectedHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedHex == hex ? 3 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Yeni Makro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        saveMacro()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveMacro() {
        let action: MacroAction
        switch actionKind {
        case .keyCombo:
            var mods: HIDModifier = []
            if useCtrl { mods.insert(.leftControl) }
            if useShift { mods.insert(.leftShift) }
            if useAlt { mods.insert(.leftAlt) }
            if useAltGr { mods.insert(.rightAlt) }
            if useGUI { mods.insert(.leftGUI) }
            action = .keyCombo(keyCode: selectedKeyCode.rawValue, modifiersRaw: mods.rawValue)
        case .typeText:
            action = .typeText(text: textPayload, appendEnter: appendEnter)
        case .consumer:
            action = .consumerKey(usageRaw: selectedConsumer.rawValue)
        case .system:
            action = .systemKey(usageRaw: selectedSystemRaw)
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSub = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let macro = CustomMacro(
            title: cleanTitle,
            subtitle: cleanSub.isEmpty ? action.summaryLabel : cleanSub,
            sfSymbol: selectedSymbol,
            accentHex: selectedHex,
            category: category,
            action: action
        )
        onSave(macro)
        dismiss()
    }
}
