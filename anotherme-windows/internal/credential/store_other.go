//go:build !windows

package credential

import "fmt"

// Set is a stub for non-Windows platforms.
// TODO: Implement using platform-specific keychain (e.g., macOS Keychain, Linux secret-service).
func (s *Store) Set(service, account, secret string) error {
	return fmt.Errorf("credential store not implemented on this platform")
}

// Get is a stub for non-Windows platforms.
func (s *Store) Get(service, account string) (string, error) {
	return "", fmt.Errorf("credential store not implemented on this platform")
}

// Delete is a stub for non-Windows platforms.
func (s *Store) Delete(service, account string) error {
	return fmt.Errorf("credential store not implemented on this platform")
}
