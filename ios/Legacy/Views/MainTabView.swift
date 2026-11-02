import SwiftUI

public struct MainTabView: View {
    public init() {}
    
    public var body: some View {
        TabView {
            AssetsHomeDashboardView()
                .tabItem {
                    Label("Active", systemImage: "square.grid.2x2.fill")
                }
            
            RadarDashboardView()
                .tabItem {
                    Label("Radar", systemImage: "clock.badge.exclamationmark")
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
