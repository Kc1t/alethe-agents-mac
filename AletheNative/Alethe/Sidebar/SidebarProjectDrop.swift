import AletheModel
import SwiftUI

struct SidebarProjectDrop: DropDelegate {
    @Binding var targeted: Bool
    @Binding var inside: Bool
    let project: ProjectID
    let actions: SidebarActions

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText, SidebarDrag.paneType])
    }

    func dropEntered(info: DropInfo) {
        targeted = true
        inside = info.hasItemsConforming(to: [SidebarDrag.paneType])
    }

    func dropExited(info: DropInfo) { targeted = false }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        MainActor.assumeIsolated {
            SidebarDrag.load(info.itemProviders(for: [.plainText, SidebarDrag.paneType])) {
                actions.drop($0, onProject: project)
            }
        }
        return true
    }
}
