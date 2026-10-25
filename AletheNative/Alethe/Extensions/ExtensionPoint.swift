import AletheExtensionSDK
import ExtensionFoundation

extension AppExtensionPoint {
    @Definition
    static var aletheSidebarTab: AppExtensionPoint {
        Name("sidebar-tab")
        Scope(restriction: .none)
        UserInterface(true)
    }
}
