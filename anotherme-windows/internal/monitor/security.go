package monitor

import (
	"path/filepath"
	"strings"
	"sync"
)

// AppCategory classifies applications by security risk level.
type AppCategory int

const (
	// CategoryHighRisk includes browsers, terminals, and code editors
	// that may display sensitive content.
	CategoryHighRisk AppCategory = iota
	// CategoryLowRisk includes social and communication apps that are
	// less likely to show sensitive data.
	CategoryLowRisk
	// CategoryUnknown is used for unrecognized applications.
	CategoryUnknown
)

// SecurityFilter determines whether a capture should be blocked or filtered
// based on the active application and window title content.
type SecurityFilter struct {
	hardBlockedProcesses map[string]bool
	userBlacklist        map[string]bool
	sensitiveKeywords    []string
	highDangerKeywords   []string
	appCategories        map[string]AppCategory
	mu                   sync.RWMutex
}

// NewSecurityFilter creates a SecurityFilter initialized with default
// blocked processes, sensitive keywords, and app categories for Windows.
func NewSecurityFilter() *SecurityFilter {
	sf := &SecurityFilter{
		hardBlockedProcesses: map[string]bool{
			// Password managers
			"1password.exe":  true,
			"bitwarden.exe":  true,
			"keepass.exe":    true,
			"lastpass.exe":   true,
			"keepassxc.exe":  true,
			"dashlane.exe":   true,
			"roboform.exe":  true,

			// Crypto wallets
			"ledger live.exe":  true,
			"trezor suite.exe": true,
			"exodus.exe":       true,
			"electrum.exe":     true,
			"metamask.exe":     true,

			// System credential processes
			"credentialuibroker.exe": true,
			"vaultcmd.exe":          true,
		},
		userBlacklist: make(map[string]bool),
		highDangerKeywords: []string{
			"密码", "password", "passwd",
			"银行卡", "bank card",
			"seed phrase", "助记词",
			"私钥", "private key",
			"2FA", "验证码", "verification code",
			"secret key", "recovery phrase",
		},
		sensitiveKeywords: []string{
			"网银", "银行登录",
			"Internet Banking", "Online Banking",
			"payment checkout", "付款",
			"MetaMask", "Binance", "币安",
			"Coinbase", "OKX", "Huobi", "火币",
			"credit card", "信用卡",
			"social security", "身份证",
			"login", "sign in", "登录",
			"authenticate", "认证",
		},
		appCategories: map[string]AppCategory{
			// High risk: browsers, terminals, editors
			"chrome.exe":           CategoryHighRisk,
			"msedge.exe":           CategoryHighRisk,
			"firefox.exe":          CategoryHighRisk,
			"brave.exe":            CategoryHighRisk,
			"opera.exe":            CategoryHighRisk,
			"iexplore.exe":         CategoryHighRisk,
			"cmd.exe":              CategoryHighRisk,
			"powershell.exe":       CategoryHighRisk,
			"pwsh.exe":             CategoryHighRisk,
			"windowsterminal.exe":  CategoryHighRisk,
			"code.exe":             CategoryHighRisk,
			"devenv.exe":           CategoryHighRisk,

			// Low risk: social and communication
			"wechat.exe":   CategoryLowRisk,
			"slack.exe":    CategoryLowRisk,
			"teams.exe":    CategoryLowRisk,
			"outlook.exe":  CategoryLowRisk,
			"feishu.exe":   CategoryLowRisk,
			"discord.exe":  CategoryLowRisk,
			"telegram.exe": CategoryLowRisk,
			"dingtalk.exe": CategoryLowRisk,
			"zoom.exe":     CategoryLowRisk,
		},
	}
	return sf
}

// IsHardBlocked returns true if the given process name belongs to a
// hard-blocked application (password managers, crypto wallets, etc.)
// that must never be captured.
func (sf *SecurityFilter) IsHardBlocked(processName string) bool {
	sf.mu.RLock()
	defer sf.mu.RUnlock()

	normalized := normalizeProcessName(processName)
	if sf.hardBlockedProcesses[normalized] {
		return true
	}
	if sf.userBlacklist[normalized] {
		return true
	}
	return false
}

// IsSoftFiltered returns true if the given process or window title contains
// sensitive keywords that suggest the user is viewing private content.
func (sf *SecurityFilter) IsSoftFiltered(processName, windowTitle string) bool {
	sf.mu.RLock()
	defer sf.mu.RUnlock()

	titleLower := strings.ToLower(windowTitle)

	// High-danger keywords always block.
	for _, kw := range sf.highDangerKeywords {
		if strings.Contains(titleLower, strings.ToLower(kw)) {
			return true
		}
	}

	// Sensitive keywords only block for high-risk apps.
	normalized := normalizeProcessName(processName)
	cat, exists := sf.appCategories[normalized]
	if !exists {
		cat = CategoryUnknown
	}
	if cat == CategoryHighRisk {
		for _, kw := range sf.sensitiveKeywords {
			if strings.Contains(titleLower, strings.ToLower(kw)) {
				return true
			}
		}
	}

	return false
}

// AddToBlacklist adds a process name to the user-managed blacklist.
// The process is treated as hard-blocked.
func (sf *SecurityFilter) AddToBlacklist(processName string) {
	sf.mu.Lock()
	defer sf.mu.Unlock()
	sf.userBlacklist[normalizeProcessName(processName)] = true
}

// RemoveFromBlacklist removes a process name from the user-managed blacklist.
func (sf *SecurityFilter) RemoveFromBlacklist(processName string) {
	sf.mu.Lock()
	defer sf.mu.Unlock()
	delete(sf.userBlacklist, normalizeProcessName(processName))
}

// GetAppCategory returns the security category for the given process name.
func (sf *SecurityFilter) GetAppCategory(processName string) AppCategory {
	sf.mu.RLock()
	defer sf.mu.RUnlock()
	cat, exists := sf.appCategories[normalizeProcessName(processName)]
	if !exists {
		return CategoryUnknown
	}
	return cat
}

// normalizeProcessName extracts the base filename and lowercases it.
func normalizeProcessName(processName string) string {
	return strings.ToLower(filepath.Base(processName))
}
