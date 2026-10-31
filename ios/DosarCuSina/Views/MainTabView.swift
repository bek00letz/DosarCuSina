import SwiftUI

public struct MainTabView: View {
    public init() {}
    
    public var body: some View {
        TabView {
            RadarDashboardView()
                .tabItem {
                    Label("Radar", systemImage: "clock.badge.exclamationmark")
                }
            
            AssetsVaultView()
                .tabItem {
                    Label("Active", systemImage: "folder.fill")
                }
            
            FinancialPulseView()
                .tabItem {
                    Label("Finanțe", systemImage: "chart.bar.xaxis")
                }
            
            SettingsView()
                .tabItem {
                    Label("Setări", systemImage: "gearshape.fill")
                }
        }
        .tint(.blue)
    }
}
