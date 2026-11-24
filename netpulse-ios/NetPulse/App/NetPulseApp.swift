import SwiftUI

@main
struct NetPulseApp: App {
    @StateObject private var vm = AppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .bottom) {
                TabView(selection: $vm.selectedTab) {
                    SummaryView(vm: vm)
                        .tabItem {
                            Label("Özet", systemImage: "waveform.path.ecg")
                        }
                        .tag(AppTab.summary)

                    ToolsView(vm: vm)
                        .tabItem {
                            Label("Araçlar", systemImage: "wrench.and.screwdriver")
                        }
                        .tag(AppTab.tools)

                    ReportsView(vm: vm)
                        .tabItem {
                            Label("Kayıtlar", systemImage: "doc.text.magnifyingglass")
                        }
                        .tag(AppTab.reports)
                }
                .tint(Color.npBlue)
                .preferredColorScheme(.dark)

                if let toast = vm.statusBanner {
                    Text(toast.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(toast.isError ? Color.npRed.opacity(0.92) : Color.npSurfaceSoft.opacity(0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(toast.isError ? Color.npRed : Color.npGreen, lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 64)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .confirmationDialog(
                vm.pendingConfirm?.label ?? "Onay Gerekli",
                isPresented: Binding(
                    get: { vm.pendingConfirm != nil },
                    set: { if !$0 { vm.pendingConfirm = nil } }
                ),
                presenting: vm.pendingConfirm
            ) { action in
                Button("Evet, Uygula", role: .destructive) {
                    vm.triggerAction(action, confirmed: true)
                }
                Button("Vazgeç", role: .cancel) {}
            } message: { action in
                Text(action.description)
            }
            .task {
                vm.startMonitoring()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    vm.startMonitoring()
                } else if phase == .background {
                    vm.stopMonitoring()
                }
            }
        }
    }
}
