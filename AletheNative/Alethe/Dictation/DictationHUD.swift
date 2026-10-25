import AletheDesign
import AletheFoundation
import AppKit
import SwiftUI

struct DictationHUD: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        let dictation = environment.dictation
        if metrics.isWebInterface, dictation.jev.open {
            ZStack(alignment: .bottom) {
                JevVoiceEdge(listening: dictation.jev.listening, processing: dictation.machine.phase == .finishing)
                JevVoiceBar()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        } else if dictation.machine.phase != .idle {
            HStack(spacing: metrics.space(.m)) {
                icon(dictation.machine.phase)
                content(dictation)
                    .frame(maxWidth: metrics.size(420), alignment: .leading)
            }
            .padding(.horizontal, metrics.space(.xl))
            .padding(.vertical, metrics.space(.m))
            .background(theme[.surfaceModal], in: Capsule())
            .overlay(Capsule().strokeBorder(theme[.borderStrong]).allowsHitTesting(false))
            .padding(.bottom, metrics.space(.xxl))
            .transition(environment.reducesMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dictation.hud")
        }
    }

    private func icon(_ phase: DictationMachine.Phase) -> some View {
        let failed = if case .failed = phase { true } else { false }
        return Image(systemName: failed ? "mic.slash" : "mic.fill")
            .foregroundStyle(failed ? theme[.textTertiary] : phase == .listening ? theme[.statusStopped] : theme[.textSecondary])
            .symbolEffect(.pulse, isActive: phase == .listening && !environment.reducesMotion)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(_ dictation: DictationController) -> some View {
        if case .failed(let failure) = dictation.machine.phase {
            Text(message(failure)).font(metrics.font(.body))
            if failure == .microphoneDenied {
                Button("dictation.openSettings") {
                    let settings = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    if let url = URL(string: settings) { NSWorkspace.shared.open(url) }
                    dictation.dismissFailure()
                }
                .accessibilityIdentifier("dictation.openSettings")
            }
            Button { dictation.dismissFailure() } label: {
                Image(systemName: "xmark")
                    .frame(width: metrics.size(22), height: metrics.size(22))
                    .contentShape(Rectangle())
            }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("dictation.dismiss"))
                .accessibilityIdentifier("dictation.dismiss")
        } else if case .starting = dictation.machine.phase {
            Text(dictation.downloadingModel ? "dictation.downloading" : "dictation.starting")
                .font(metrics.font(.body)).foregroundStyle(theme[.textSecondary])
        } else {
            Text(dictation.liveText.isEmpty ? String(localized: "dictation.listening") : dictation.liveText)
                .font(metrics.font(.body))
                .foregroundStyle(dictation.liveText.isEmpty ? theme[.textSecondary] : theme[.textPrimary])
                .lineLimit(2)
                .truncationMode(.head)
            Text(metrics.isWebInterface ? "dictation.webHint" : "dictation.hint").font(metrics.font(.caption))
                .foregroundStyle(theme[.textTertiary])
        }
    }

    private func message(_ failure: DictationMachine.Failure) -> LocalizedStringKey {
        if case .microphoneDenied = failure { return "dictation.denied" }
        if case .languageUnsupported = failure { return "dictation.language" }
        return "dictation.unavailable"
    }
}
