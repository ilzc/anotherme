//go:build !darwin

package config

// MigrateFromSwiftApp is not available on non-macOS platforms.
// It always returns nil.
func MigrateFromSwiftApp() *Config {
	return nil
}
