import Foundation
import AppKit

// MARK: - CaptureBlockResult

/// Result of the hard-block check performed before any screenshot is taken.
enum CaptureBlockResult {
    /// Capture is allowed to proceed.
    case allowed
    /// Capture is blocked; no screenshot or metadata is recorded.
    case blocked(reason: String)
    /// Capture is blocked but the app name should be recorded as metadata.
    case blockedWithMetadata(app: String)
}

// MARK: - AppCategory

/// Broad classification of an application for keyword-filtering strategy selection.
enum AppCategory {
    /// Browsers, terminals, IDEs — can display arbitrary content.
    case highRiskContainer
    /// Chat / email apps — mostly conversational, lower risk.
    case lowRiskSocial
    /// Everything else.
    case unknown
}

// MARK: - SecurityFilter

/// Two-layer security filter that runs **before** screen capture.
///
/// - **Hard block** (`shouldBlockCapture`): unconditional block based on
///   Secure Input state or a bundleID blacklist. Cannot be overridden.
/// - **Soft filter** (`shouldSkipAnalysis`): context-aware keyword match on
///   the active window title, with the keyword set determined by app category.
struct SecurityFilter {

    // MARK: - UserDefaults Keys

    private static let userBlocklistKey = "SecurityFilter.userBlockedBundleIDs"

    // MARK: - Default Hard-Block Blacklist

    /// Built-in bundleIDs that are always blocked (password managers, system
    /// security utilities, cryptocurrency wallets).
    private static let defaultHardBlockBundleIDs: Set<String> = [
        // Password managers
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.lastpass.LastPass",
        // System security
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        // Cryptocurrency wallets
        "com.ledger.live",
        "io.trezor.suite",
        "com.exodus.wallet",
    ]

    /// Merged set: built-in defaults + user-added entries from UserDefaults.
    private var hardBlockBundleIDs: Set<String> {
        var ids = Self.defaultHardBlockBundleIDs
        if let extras = UserDefaults.standard.stringArray(forKey: Self.userBlocklistKey) {
            ids.formUnion(extras)
        }
        return ids
    }

    // MARK: - Sensitive Keywords

    /// Full set of sensitive keywords used for high-risk containers and unknown apps.
    private let allSensitiveKeywords: [String] = [
        // Banking / payment
        "网银", "银行登录", "Internet Banking", "online banking",
        "payment checkout", "付款", "收银台", "信用卡还款",
        // Credentials
        "密码", "password", "2FA", "验证码", "authenticator",
        // Crypto
        "seed phrase", "助记词", "私钥", "private key",
        "MetaMask", "Binance", "币安", "Coinbase", "OKX",
    ]

    /// High-danger subset used for low-risk social apps (chat, email).
    private let highDangerKeywordsOnly: [String] = [
        "密码", "password", "银行卡",
    ]

    // MARK: - App Category Mapping

    /// BundleID prefixes / exact matches → high-risk container.
    private static let highRiskContainerBundleIDs: Set<String> = [
        // Browsers
        "com.apple.Safari",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",  // Arc
        "com.operasoftware.Opera",
        // Terminals
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        // IDEs
        "com.microsoft.VSCode",
        // Note: JetBrains IDEs are matched by prefix "com.jetbrains." in highRiskContainerPrefixes.
    ]

    /// BundleID prefixes / exact matches → low-risk social.
    private static let lowRiskSocialBundleIDs: Set<String> = [
        "com.tencent.xinWeChat",       // 微信
        "com.apple.MobileSMS",         // iMessage
        "com.apple.mail",              // Apple Mail
        "com.tinyspeck.slackmacgap",   // Slack
        "com.electron.lark",           // 飞书
        "ru.keepcoder.Telegram",       // Telegram
        "com.facebook.archon",         // Messenger
        "us.zoom.xos",                 // Zoom
        "com.readdle.smartemail-macos", // Spark
    ]

    // MARK: - Hard Block (Gate 2)

    /// Check whether capture should be blocked entirely.
    ///
    /// This runs **before** any screenshot is taken.
    /// - SecureInput detection is unconditional and cannot be disabled.
    /// - BundleID blacklist supports user-added entries via UserDefaults.
    func shouldBlockCapture() -> CaptureBlockResult {
        // 1. Secure Input detection (always on, not user-overridable)
        if isSecureInputActive() {
            return .blocked(reason: "secure_input")
        }

        // 2. Application blacklist
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if hardBlockBundleIDs.contains(bundleID) {
            return .blockedWithMetadata(app: bundleID)
        }

        return .allowed
    }

    // MARK: - Soft Filter (Gate 3)

    /// Check whether the current window context should be skipped for analysis.
    ///
    /// Uses the app category to decide which keyword set to apply against the
    /// window title. Returns `true` if any sensitive keyword is found.
    func shouldSkipAnalysis(windowTitle: String, appBundleID: String) -> Bool {
        let category = categorize(appBundleID)
        let keywords: [String]
        switch category {
        case .highRiskContainer: keywords = allSensitiveKeywords
        case .lowRiskSocial:     keywords = highDangerKeywordsOnly
        case .unknown:           keywords = allSensitiveKeywords
        }
        return keywords.contains { windowTitle.localizedCaseInsensitiveContains($0) }
    }

    // MARK: - App Classification

    /// Prefixes that identify high-risk container apps (covers all JetBrains IDEs, etc.).
    private static let highRiskContainerPrefixes: [String] = [
        "com.jetbrains.",    // IntelliJ, PyCharm, WebStorm, GoLand, etc.
    ]

    /// Classify an application by its bundleID.
    func categorize(_ bundleID: String) -> AppCategory {
        if Self.highRiskContainerBundleIDs.contains(bundleID) {
            return .highRiskContainer
        }
        if Self.highRiskContainerPrefixes.contains(where: { bundleID.hasPrefix($0) }) {
            return .highRiskContainer
        }
        if Self.lowRiskSocialBundleIDs.contains(bundleID) {
            return .lowRiskSocial
        }
        return .unknown
    }

    // MARK: - Secure Input Detection

    /// Returns `true` when macOS Secure Input is active (e.g. password fields).
    ///
    /// Uses `CGSessionCopyCurrentDictionary` to read the session-level
    /// `kCGSSessionSecureInputPID` key. When any process has enabled Secure
    /// Input, this key is present and non-zero.
    ///
    /// Note: This relies on an undocumented key. An alternative is
    /// `IsSecureEventInputEnabled()` from Carbon/HIToolbox, but that only
    /// reports the current process's state. The CGSession approach detects
    /// system-wide Secure Input regardless of which process enabled it.
    private func isSecureInputActive() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        if let pid = dict["kCGSSessionSecureInputPID"] as? Int, pid > 0 {
            return true
        }
        return false
    }
}
