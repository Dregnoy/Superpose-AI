import SwiftUI

@main
struct BluePadApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootContentView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            BluePadTheme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                StatusHeaderBar(viewModel: viewModel)

                TabView(selection: $viewModel.selectedTab) {
                    TrackpadView(viewModel: viewModel)
                        .tabItem {
                            Label("Trackpad", systemImage: "hand.point.up.left.fill")
                        }
                        .tag(AppTab.trackpad)

                    KeyboardView(viewModel: viewModel)
                        .tabItem {
                            Label("Klavye", systemImage: "keyboard.fill")
                        }
                        .tag(AppTab.keyboard)

                    RemotePresenterView(viewModel: viewModel)
                        .tabItem {
                            Label("Kumanda", systemImage: "play.tv.fill")
                        }
                        .tag(AppTab.remote)

                    ToolsView(viewModel: viewModel)
                        .tabItem {
                            Label("Araçlar", systemImage: "wrench.and.screwdriver.fill")
                        }
                        .tag(AppTab.tools)

                    ConnectionSettingsView(viewModel: viewModel)
                        .tabItem {
                            Label("Bağlantı", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .tag(AppTab.connection)
                }
                .tint(BluePadTheme.accentCyan)
            }

            if let toast = viewModel.toastMessage {
                ToastBanner(message: toast)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(50)
            }
        }
        .sheet(isPresented: $viewModel.isScannerPresented) {
            BarcodeScannerSheet(
                onScanned: { code in
                    viewModel.handleScannedBarcode(code)
                },
                onDismiss: {
                    viewModel.isScannerPresented = false
                }
            )
        }
        .onAppear {
            viewModel.startBluetoothIfNeeded()
        }
    }
}
