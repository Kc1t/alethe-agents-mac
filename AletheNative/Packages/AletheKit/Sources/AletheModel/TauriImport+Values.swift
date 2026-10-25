import AletheFoundation
import Foundation

extension TauriImport {
    static func folder(of project: [String: Any], terminals: [[String: Any]]) -> String? {
        var candidates: [String?] = [project["defaultCwd"] as? String]
        for terminal in terminals where (terminal["kind"] as? String ?? "terminal") == "terminal" {
            candidates.append(terminal["cwd"] as? String)
            candidates.append(contentsOf: (terminal["tabs"] as? [[String: Any]] ?? []).map { $0["cwd"] as? String })
        }
        return candidates.compactMap { $0 }.first { isAbsolute($0) }.map(trimmedFolder)
    }

    static func isAbsolute(_ path: String) -> Bool { path.hasPrefix("/") }

    static func trimmedFolder(_ path: String) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    static func normalizedFolder(_ path: String) -> String {
        (trimmedFolder(path) as NSString).resolvingSymlinksInPath
    }

    static func projectColor(_ value: Any?) -> ProjectColor? {
        guard let raw = (value as? String)?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
            return nil
        }
        if let named = ProjectColor(rawValue: raw) { return named }
        var hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count >= 6, let value = UInt32(hex.prefix(6), radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xff) / 255, g = Double((value >> 8) & 0xff) / 255, b = Double(value & 0xff) / 255
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        let lightness = (maxC + minC) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        if saturation < 0.2 || delta < 0.08 { return lightness < 0.2 ? .black : .gray }
        var hue: Double
        if case r = maxC { hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if case g = maxC { hue = 60 * ((b - r) / delta + 2) }
        else { hue = 60 * ((r - g) / delta + 4) }
        if hue < 0 { hue += 360 }
        return color(forHue: hue)
    }

    private static func color(forHue hue: Double) -> ProjectColor {
        if case ..<15 = hue { return .red }
        else if case 345... = hue { return .red }
        else if case ..<45 = hue { return .orange }
        else if case ..<70 = hue { return .yellow }
        else if case ..<165 = hue { return .green }
        else if case ..<200 = hue { return .teal }
        else if case ..<250 = hue { return .blue }
        else if case ..<290 = hue { return .purple }
        else { return .pink }
    }

    static func decodeGrid(_ raw: Any) -> CustomGrid? {
        guard JSONSerialization.isValidJSONObject(raw), let data = try? JSONSerialization.data(withJSONObject: raw) else { return nil }
        return try? JSONDecoder().decode(CustomGrid.self, from: data)
    }
}
