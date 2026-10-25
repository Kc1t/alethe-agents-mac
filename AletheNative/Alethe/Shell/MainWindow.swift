import AletheDesign
import AletheGitControl
import AletheIntegrations
import AletheModel
import SwiftUI

struct MainWindow: View {
    @Environment(AppEnvironment.self) var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @Environment(\.undoManager) var undoManager
    @SceneStorage("main.columnVisibility") private var sidebarVisible = true
    @AppStorage("main.rightSidebarWidth") private var rightSidebarWidth = 280.0
    @AppStorage("main.webLeftWidth") private var webLeftWidth = 286.0
    @State private var webSidebarDragging = false
    @State private var webPopoverOpen = false
    @State private var webTrafficLightTrailingEdge: CGFloat = 0
    @State private var showsTitleBarNews = false
    @State private var showsTitleBarMemory = false
    @State private var showsTitleBarCustomization = false
    @AppStorage("main.webRightWidth") private var webRightWidth = 300.0

    var body: some View {
        Group {
            if metrics.isWebInterface {
                webShell
            } else {
                nativeShell
            }
        }
        .background { if metrics.isWebInterface { WebShortcutEvents(environment: environment) } }
        .onReceive(NotificationCenter.default.publisher(for: .aletheOpenTitleBarMemory)) { _ in
            if metrics.isWebInterface { showsTitleBarMemory = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aletheCustomizeTitleBar)) { _ in
            if metrics.isWebInterface { showsTitleBarCustomization = true }
        }
        .onChange(of: environment.editorRequest) { _, request in
            if request != nil { environment.focusModePaneID = nil }
        }
        .onChange(of: metrics.isWebInterface) { _, web in
            if !web {
                showsTitleBarMemory = false
                showsTitleBarNews = false
                showsTitleBarCustomization = false
            }
        }
        .onPreferenceChange(WebTitleBarNewsKey.self) { showsTitleBarNews = $0 }
        .onAppear {
            if metrics.isWebInterface, UserDefaults.standard.object(forKey: "main.webRightSidebarInitialized") == nil {
                environment.rightSidebarVisible = true
                UserDefaults.standard.set(true, forKey: "main.webRightSidebarInitialized")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aletheToggleWebSidebar)) { _ in
            if metrics.isWebInterface { sidebarVisible.toggle() }
        }
        .overlay {
            WindowChromeBridge(web: metrics.isWebInterface, barHeight: metrics.size(32),
                               trafficLightTrailingEdge: $webTrafficLightTrailingEdge)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .ignoresSafeArea(.container, edges: .top)
        }
        .accessibilityHidden(!environment.startupFinished)
        .overlay {
            if !environment.startupFinished { StartupLoadingView() }
        }
        .frame(minWidth: metrics.isWebInterface ? metrics.size(800 / metrics.scale) : 800,
               minHeight: metrics.isWebInterface ? metrics.size(500 / metrics.scale) : 500)
        .blur(radius: webTerminalPresented || showsTitleBarMemory || showsTitleBarNews || showsTitleBarCustomization ? metrics.size(10) : 0)
        .allowsHitTesting(!webTerminalPresented && !showsTitleBarMemory && !showsTitleBarNews && !showsTitleBarCustomization)
        .accessibilityHidden(webTerminalPresented || showsTitleBarMemory || showsTitleBarNews || showsTitleBarCustomization)
        .sheet(item: systemEditorRequest) { request in
            if let workspace = environment.workspace { editor(for: request, workspace: workspace) }
        }
        .overlay {
            if webTerminalPresented, let request = environment.editorRequest, let workspace = environment.workspace {
                editorOverlay(for: request, workspace: workspace)
                .id(request.id)
            }
        }
        .overlay {
            if metrics.isWebInterface, showsTitleBarCustomization {
                ProjectGroupWebOverlay(width: 440, onClose: { showsTitleBarCustomization = false }) { close in
                    WebTitleBarCustomization(close: close)
                }
            }
            if metrics.isWebInterface, showsTitleBarMemory {
                ProjectGroupWebOverlay(width: 760, onClose: { showsTitleBarMemory = false }) { close in
                    WebTitleBarMemory(close: close)
                }
            }
            if metrics.isWebInterface, showsTitleBarNews {
                ProjectGroupWebOverlay(width: 480, onClose: closeTitleBarNews) { close in
                    WebTitleBarNews(close: close)
                }
            }
        }
        .overlay { if metrics.isWebInterface { InAppToastHost() } }
        .gitWebModalLayer()
        .webDialogLayer()
        .modifier(WebChoiceActionLayer())
    }

    private func closeTitleBarNews() {
        showsTitleBarNews = false
        NotificationCenter.default.post(name: .aletheCloseTitleBarNews, object: nil)
    }

    private var webTerminalPresented: Bool {
        guard metrics.isWebInterface, let request = environment.editorRequest else { return false }
        if isPrimaryWebRequest(request) {
            return true
        } else if isAdditionalWebRequest(request) {
            return true
        } else if case .pluginSheet(let viewID, _) = request {
            return viewID == GitControlPlugin.viewID
        } else {
            return false
        }
    }

    @ViewBuilder
    private func editorOverlay(for request: EditorRequest, workspace: WorkspaceModel) -> some View {
        if usesGitOverlay(request) {
            GitWebOverlay(width: modalWidth(request), close: { environment.editorRequest = nil }) {
                editor(for: request, workspace: workspace)
            }
        } else if case .onboarding = request {
            OnboardingWebOverlay {
                editor(for: request, workspace: workspace)
                    .environment(\.modalsM2Close, { environment.editorRequest = nil })
            }
        } else if usesStandardOverlay(request) {
            NewTerminalWebOverlay(onClose: { environment.editorRequest = nil }, defaultWidth: modalWidth(request),
                                  minimumWidth: 320) { close in
                editor(for: request, workspace: workspace)
                    .environment(\.modalsM2Close, close)
            }
        } else if case .dataManagement = request {
            NewTerminalWebOverlay(onClose: { environment.editorRequest = nil }, defaultWidth: 620) { close in
                editor(for: request, workspace: workspace, closeOverlay: close)
            }
        } else if case .findJump = request {
            ProjectGroupWebOverlay(width: 520, onClose: { environment.editorRequest = nil }) { close in
                WebTitleBarSearch(workspace: workspace, undoManager: undoManager, close: close)
            }
        } else if case .aiUsage = request {
            ProjectGroupWebOverlay(width: 920, onClose: { environment.editorRequest = nil }) { close in
                WebTitleBarUsage(close: close)
            }
        } else if usesProjectGroupOverlay(request) {
            ProjectGroupWebOverlay(width: projectGroupModalWidth(request),
                                   onClose: { environment.editorRequest = nil }) { close in
                editor(for: request, workspace: workspace, closeOverlay: close)
            }
        } else {
            NewTerminalWebOverlay(onClose: { environment.editorRequest = nil }) { close in
                editor(for: request, workspace: workspace, closeOverlay: close)
            }
        }
    }

    private var systemEditorRequest: Binding<EditorRequest?> {
        Binding { webTerminalPresented ? nil : environment.editorRequest } set: { environment.editorRequest = $0 }
    }

    private var webShell: some View {
        GeometryReader { windowGeometry in
            VStack(spacing: 0) {
                WebTitleBar(sidebarVisible: $sidebarVisible, trafficLightTrailingEdge: webTrafficLightTrailingEdge)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        WebShellPanel(visible: sidebarVisible,
                                      width: min(metrics.size(webLeftWidth), geometry.size.width * 0.30)) {
                            LeftSidebar()
                        }
                        WebShellSeparator(width: $webLeftWidth, limits: 220...380,
                                          visible: sidebarVisible, dragging: $webSidebarDragging)
                        WorkspaceView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .overlay(alignment: .bottom) { DictationHUD() }
                        WebShellSeparator(width: $webRightWidth, limits: 260...420, trailing: true,
                                          visible: environment.rightSidebarVisible, dragging: $webSidebarDragging)
                        WebShellPanel(visible: environment.rightSidebarVisible,
                                      width: min(metrics.size(webRightWidth), geometry.size.width * 0.30),
                                      trailing: true) {
                            RightSidebar()
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .animation(Motion.webShellCurve(duration: 0.22, reduceMotion: metrics.reducesMotion),
                               value: sidebarVisible)
                    .animation(Motion.webShellCurve(duration: 0.22, reduceMotion: metrics.reducesMotion),
                               value: environment.rightSidebarVisible)
                    .transaction { transaction in
                        if webSidebarDragging || metrics.reducesMotion {
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                    }
                }
            }
            .frame(width: windowGeometry.size.width, height: windowGeometry.size.height, alignment: .topLeading)
            .onPreferenceChange(WebTitleBarPopoverOpenKey.self) { webPopoverOpen = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(WebTitleBarPopoverLayer())
        .background(theme[.bg])
        .ignoresSafeArea(.container, edges: .top)
        .toolbarVisibility(.hidden, for: .windowToolbar)
    }

    private var nativeShell: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            LeftSidebar()
                .navigationSplitViewColumnWidth(min: metrics.size(200), ideal: metrics.size(240), max: metrics.size(360))
        } detail: {
            WorkspaceView()
                .overlay(alignment: .bottom) { DictationHUD() }
                .animation(environment.reducesMotion ? nil : .easeOut(duration: 0.2), value: environment.dictation.machine.phase)
                .modifier(MainToolbar())
                .inspector(isPresented: rightSidebarVisible) {
                    RightSidebar()
                        .inspectorColumnWidth(min: metrics.size(220), ideal: rightSidebarWidth, max: metrics.size(480))
                        .onGeometryChange(for: Double.self) { $0.size.width } action: { width in
                            if width > 0 { rightSidebarWidth = width }
                        }
                }
        }
    }

    var editorRequest: Binding<EditorRequest?> {
        Binding { environment.editorRequest } set: { environment.editorRequest = $0 }
    }

    private var rightSidebarVisible: Binding<Bool> {
        Binding { environment.rightSidebarVisible } set: { environment.rightSidebarVisible = $0 }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding {
            sidebarVisible ? .all : .detailOnly
        } set: { visibility in
            sidebarVisible = visibility != .detailOnly
        }
    }


}
