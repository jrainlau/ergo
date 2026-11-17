import SwiftUI
import ErgoCore
import ErgoPluginKit

struct SettingsRootView: View {
    let host: PluginHost
    let services: CoreServices
    @Bindable var nav: SettingsNavigation
    let resetPlacement: () -> Void

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.page) {
                Section {
                    Label("通用", systemImage: "gearshape").tag(SettingsPage.general)
                    Label("外观", systemImage: "paintbrush").tag(SettingsPage.appearance)
                    Label("权限", systemImage: "lock.shield").tag(SettingsPage.permissions)
                }
                Section("插件") {
                    ForEach(host.registrations) { reg in
                        Label(reg.manifest.name, systemImage: reg.manifest.symbolName)
                            .tag(SettingsPage.plugin(reg.id))
                    }
                }
                Section {
                    Label("关于", systemImage: "info.circle").tag(SettingsPage.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            switch nav.page {
            case .general: GeneralPage(settings: services.appSettings, resetPlacement: resetPlacement)
            case .appearance: AppearancePage(settings: services.appSettings)
            case .permissions: PermissionsPage(host: host, services: services)
            case .plugin(let id):
                if let reg = host.registration(for: id) {
                    PluginDetailView(host: host, registration: reg, services: services, nav: nav).id(id)
                }
            case .about: AboutPage()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}
