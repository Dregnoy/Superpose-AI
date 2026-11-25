import SwiftUI

struct FullPCKeyboardView: View {
    @ObservedObject var viewModel: AppViewModel

    private struct HardwareKey: Identifiable {
        let id = UUID()
        let label: String
        let code: HIDKeyCode
        var widthWeight: CGFloat = 1.0
        var accent: Bool = false
    }

    private var isTurkishQ: Bool {
        viewModel.settings.keyboardLayout == .turkishQ || viewModel.settings.keyboardLayout == .turkishF
    }

    private var functionRow: [HardwareKey] {
        [
            HardwareKey(label: "Esc", code: .escape, accent: true),
            HardwareKey(label: "F1", code: .f1),
            HardwareKey(label: "F2", code: .f2),
            HardwareKey(label: "F3", code: .f3),
            HardwareKey(label: "F4", code: .f4),
            HardwareKey(label: "F5", code: .f5),
            HardwareKey(label: "F6", code: .f6),
            HardwareKey(label: "F7", code: .f7),
            HardwareKey(label: "F8", code: .f8),
            HardwareKey(label: "F9", code: .f9),
            HardwareKey(label: "F10", code: .f10),
            HardwareKey(label: "F11", code: .f11),
            HardwareKey(label: "F12", code: .f12),
            HardwareKey(label: "PrtSc", code: .printScreen),
            HardwareKey(label: "Del", code: .deleteForward, accent: true)
        ]
    }

    private var numberRow: [HardwareKey] {
        [
            HardwareKey(label: "1", code: .digit1),
            HardwareKey(label: "2", code: .digit2),
            HardwareKey(label: "3", code: .digit3),
            HardwareKey(label: "4", code: .digit4),
            HardwareKey(label: "5", code: .digit5),
            HardwareKey(label: "6", code: .digit6),
            HardwareKey(label: "7", code: .digit7),
            HardwareKey(label: "8", code: .digit8),
            HardwareKey(label: "9", code: .digit9),
            HardwareKey(label: "0", code: .digit0),
            HardwareKey(label: isTurkishQ ? "*" : "-", code: .minus),
            HardwareKey(label: "⌫", code: .backspace, widthWeight: 1.4, accent: true)
        ]
    }

    private var topLetterRow: [HardwareKey] {
        [
            HardwareKey(label: "Q", code: .q),
            HardwareKey(label: "W", code: .w),
            HardwareKey(label: "E", code: .e),
            HardwareKey(label: "R", code: .r),
            HardwareKey(label: "T", code: .t),
            HardwareKey(label: "Y", code: .y),
            HardwareKey(label: "U", code: .u),
            HardwareKey(label: isTurkishQ ? "I" : "I", code: .i),
            HardwareKey(label: "O", code: .o),
            HardwareKey(label: "P", code: .p),
            HardwareKey(label: isTurkishQ ? "Ğ" : "[", code: .leftBracket),
            HardwareKey(label: isTurkishQ ? "Ü" : "]", code: .rightBracket)
        ]
    }

    private var middleLetterRow: [HardwareKey] {
        [
            HardwareKey(label: "A", code: .a),
            HardwareKey(label: "S", code: .s),
            HardwareKey(label: "D", code: .d),
            HardwareKey(label: "F", code: .f),
            HardwareKey(label: "G", code: .g),
            HardwareKey(label: "H", code: .h),
            HardwareKey(label: "J", code: .j),
            HardwareKey(label: "K", code: .k),
            HardwareKey(label: "L", code: .l),
            HardwareKey(label: isTurkishQ ? "Ş" : ";", code: .semicolon),
            HardwareKey(label: isTurkishQ ? "İ" : "'", code: .apostrophe),
            HardwareKey(label: "⏎", code: .enter, widthWeight: 1.4, accent: true)
        ]
    }

    private var bottomLetterRow: [HardwareKey] {
        [
            HardwareKey(label: "Caps", code: .capsLock, widthWeight: 1.25, accent: true),
            HardwareKey(label: "Z", code: .z),
            HardwareKey(label: "X", code: .x),
            HardwareKey(label: "C", code: .c),
            HardwareKey(label: "V", code: .v),
            HardwareKey(label: "B", code: .b),
            HardwareKey(label: "N", code: .n),
            HardwareKey(label: "M", code: .m),
            HardwareKey(label: isTurkishQ ? "Ö" : ",", code: .comma),
            HardwareKey(label: isTurkishQ ? "Ç" : ".", code: .period),
            HardwareKey(label: isTurkishQ ? "." : "/", code: .slash)
        ]
    }

    var body: some View {
        VStack(spacing: 7) {
            // Scrollable Function / System Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(functionRow) { item in
                        Button {
                            viewModel.sendKey(item.code)
                        } label: {
                            Text(item.label)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(item.accent ? BluePadTheme.accentCyan : BluePadTheme.textPrimary)
                                .padding(.horizontal, 9)
                                .frame(height: 32)
                        }
                        .buttonStyle(KeycapButtonStyle(cornerRadius: 8))
                    }
                }
            }

            // Number Row
            keyRow(numberRow, height: 38)

            // QWERTY / TR-Q Top Row
            keyRow(topLetterRow, height: 40)

            // Home Row
            keyRow(middleLetterRow, height: 40)

            // Bottom Letter Row
            keyRow(bottomLetterRow, height: 40)

            // Space, Tab & Arrows Row
            HStack(spacing: 4) {
                compactActionKey("Tab", code: .tab, width: 42)
                compactActionKey("Home", code: .home, width: 44)
                compactActionKey("Boşluk (Space)", code: .space, width: nil)
                compactArrowKey("chevron.left", code: .leftArrow)
                VStack(spacing: 3) {
                    compactArrowKey("chevron.up", code: .upArrow, height: 19)
                    compactArrowKey("chevron.down", code: .downArrow, height: 19)
                }
                compactArrowKey("chevron.right", code: .rightArrow)
            }
        }
        .glassCard(cornerRadius: 18, padding: 8)
    }

    private func keyRow(_ keys: [HardwareKey], height: CGFloat) -> some View {
        HStack(spacing: 3) {
            ForEach(keys) { item in
                Button {
                    viewModel.sendKey(item.code)
                } label: {
                    Text(item.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item.accent ? BluePadTheme.accentCyan : BluePadTheme.textPrimary)
                        .frame(maxWidth: item.widthWeight > 1.0 ? 52 : .infinity)
                        .frame(height: height)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .buttonStyle(KeycapButtonStyle(cornerRadius: 7))
            }
        }
    }

    private func compactActionKey(_ title: String, code: HIDKeyCode, width: CGFloat?) -> some View {
        Button {
            viewModel.sendKey(code)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BluePadTheme.textPrimary)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .frame(width: width, height: 41)
        }
        .buttonStyle(KeycapButtonStyle(cornerRadius: 8))
    }

    private func compactArrowKey(_ symbol: String, code: HIDKeyCode, height: CGFloat = 41) -> some View {
        Button {
            viewModel.sendKey(code)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BluePadTheme.accentCyan)
                .frame(width: 32, height: height)
        }
        .buttonStyle(KeycapButtonStyle(cornerRadius: 7))
    }
}
