package credential

// Store provides a platform-independent interface for secure credential storage.
// On Windows, it uses the Windows Credential Manager via advapi32.dll.
// On other platforms, it provides a stub implementation for development.
type Store struct{}

// NewStore creates a new credential Store instance.
func NewStore() *Store {
	return &Store{}
}

// targetName builds the credential target name in the format "AnotherMe/{service}/{account}".
func targetName(service, account string) string {
	return "AnotherMe/" + service + "/" + account
}
