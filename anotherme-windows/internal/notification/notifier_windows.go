//go:build windows

package notification

import (
	"log"
	"os/exec"
	"strings"
)

// escapePowerShellString escapes single quotes for safe interpolation into
// PowerShell single-quoted strings.
func escapePowerShellString(s string) string {
	return strings.ReplaceAll(s, "'", "''")
}

// escapeXML escapes special XML characters to prevent XML injection.
func escapeXML(s string) string {
	s = strings.ReplaceAll(s, "&", "&amp;")
	s = strings.ReplaceAll(s, "<", "&lt;")
	s = strings.ReplaceAll(s, ">", "&gt;")
	s = strings.ReplaceAll(s, "\"", "&quot;")
	s = strings.ReplaceAll(s, "'", "&apos;")
	return s
}

// sendNotification sends a Windows toast notification using PowerShell.
// Falls back to logging if PowerShell is unavailable.
func sendNotification(title, message string) {
	safeTitle := escapePowerShellString(title)
	safeMessage := escapePowerShellString(message)

	// Try BurntToast PowerShell module first.
	cmd := exec.Command("powershell", "-Command",
		`New-BurntToastNotification -Text '`+safeTitle+`', '`+safeMessage+`'`)
	if err := cmd.Run(); err != nil {
		// Fallback: use basic PowerShell notification via .NET.
		xmlTitle := escapeXML(safeTitle)
		xmlMessage := escapeXML(safeMessage)
		fallbackCmd := exec.Command("powershell", "-Command", `
			[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
			[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
			$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
			$xml.LoadXml('<toast><visual><binding template="ToastText02"><text id="1">`+xmlTitle+`</text><text id="2">`+xmlMessage+`</text></binding></visual></toast>')
			$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
			[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("AnotherMe").Show($toast)
		`)
		if err := fallbackCmd.Run(); err != nil {
			// Final fallback: just log it.
			log.Printf("[Notification] %s: %s", title, message)
		}
	}
}
