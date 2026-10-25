import Foundation
import os
import AletheFoundation

public enum RemoteLimits {
    public static let httpPorts: ClosedRange<UInt16> = 9340...9360
    public static let webSocketPorts: ClosedRange<UInt16> = 9341...9361

    public static let maxBody = 64 * 1024
    public static let maxStaticAsset = 4 * 1024 * 1024
    public static let maxRequestHead = 96 * 1024
    public static let maxMessage = 4 * 1024
    public static let maxScrollback = 512 * 1024
    public static let maxTranscriptEvents = 160
    public static let maxPreview = 120
    public static let maxDeviceName = 48

    public static let maxDevices = 4
    public static let deviceRange: ClosedRange<Int> = 1...maxDevices
    public static let maxConnections = 24

    public static let defaultSessionExpiry: TimeInterval = 60 * 60
    public static let sessionExpiryRange: ClosedRange<TimeInterval> = (5 * 60)...(24 * 60 * 60)
    public static let pairingWindow: TimeInterval = 120
    public static let pairingTokenLength = 32
    public static let sessionTokenLength = 40

    public static let socketTimeout: Duration = .seconds(20)
    public static let webSocketAuthTimeout: Duration = .seconds(10)

    public static let authFailureLimit = 10
    public static let authFailureWindow: TimeInterval = 60
    public static let authLockout: TimeInterval = 5 * 60

    public static let messageRateLimit = 20
    public static let messageRateWindow: TimeInterval = 60

    public static let idleDisable: TimeInterval = 4 * 60 * 60

    public static let tailscaleTimeout: Duration = .seconds(3)
}

enum RemoteLog {
    static let logger = Logger(subsystem: AppLog.subsystem, category: "remote")
}
