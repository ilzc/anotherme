//go:build !windows

package notification

import "log"

// sendNotification logs the notification on non-Windows platforms.
// TODO: Implement platform-specific notifications for development/testing.
func sendNotification(title, message string) {
	log.Printf("[Notification] %s: %s", title, message)
}
