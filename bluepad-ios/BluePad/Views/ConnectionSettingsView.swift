    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BluePadTheme.textSecondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(BluePadTheme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BluePadTheme.bgPrimary)
        )
    }
    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(BluePadTheme.accentCyan)
            }
            Slider(value: value, in: range, step: step)
                .tint(BluePadTheme.accentCyan)
        }
    }
    private func categoryColor(_ category: HIDDiagnosticEvent.Category) -> Color {
        switch category {
        case .ble: return BluePadTheme.accentCyan
        case .gatt: return BluePadTheme.accentMint
        case .tx: return BluePadTheme.accentBlue
        case .rx: return BluePadTheme.accentAmber
        case .error: return BluePadTheme.accentRose
        }
    }
}
