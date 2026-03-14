//go:build windows

package credential

import (
	"fmt"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	modadvapi32  = windows.NewLazySystemDLL("advapi32.dll")
	procCredWriteW  = modadvapi32.NewProc("CredWriteW")
	procCredReadW   = modadvapi32.NewProc("CredReadW")
	procCredDeleteW = modadvapi32.NewProc("CredDeleteW")
	procCredFree    = modadvapi32.NewProc("CredFree")
)

const (
	credTypeGeneric          = 1
	credPersistLocalMachine  = 2
)

// credential is the CREDENTIALW structure.
type credential struct {
	Flags              uint32
	Type               uint32
	TargetName         *uint16
	Comment            *uint16
	LastWritten        syscall.Filetime
	CredentialBlobSize uint32
	CredentialBlob     *byte
	Persist            uint32
	AttributeCount     uint32
	Attributes         uintptr
	TargetAlias        *uint16
	UserName           *uint16
}

// Set stores a credential in the Windows Credential Manager.
func (s *Store) Set(service, account, secret string) error {
	target, err := syscall.UTF16PtrFromString(targetName(service, account))
	if err != nil {
		return fmt.Errorf("encode target name: %w", err)
	}

	user, err := syscall.UTF16PtrFromString(account)
	if err != nil {
		return fmt.Errorf("encode account: %w", err)
	}

	blob := []byte(secret)

	cred := credential{
		Type:               credTypeGeneric,
		TargetName:         target,
		CredentialBlobSize: uint32(len(blob)),
		Persist:            credPersistLocalMachine,
		UserName:           user,
	}
	if len(blob) > 0 {
		cred.CredentialBlob = &blob[0]
	}

	ret, _, err := procCredWriteW.Call(
		uintptr(unsafe.Pointer(&cred)),
		0, // flags
	)
	if ret == 0 {
		return fmt.Errorf("CredWriteW failed: %w", err)
	}

	return nil
}

// Get retrieves a credential from the Windows Credential Manager.
func (s *Store) Get(service, account string) (string, error) {
	target, err := syscall.UTF16PtrFromString(targetName(service, account))
	if err != nil {
		return "", fmt.Errorf("encode target name: %w", err)
	}

	var pcred *credential
	ret, _, err := procCredReadW.Call(
		uintptr(unsafe.Pointer(target)),
		uintptr(credTypeGeneric),
		0, // flags
		uintptr(unsafe.Pointer(&pcred)),
	)
	if ret == 0 {
		return "", fmt.Errorf("CredReadW failed: %w", err)
	}
	defer procCredFree.Call(uintptr(unsafe.Pointer(pcred)))

	if pcred.CredentialBlobSize == 0 {
		return "", nil
	}

	blob := make([]byte, pcred.CredentialBlobSize)
	copy(blob, unsafe.Slice(pcred.CredentialBlob, pcred.CredentialBlobSize))

	return string(blob), nil
}

// Delete removes a credential from the Windows Credential Manager.
func (s *Store) Delete(service, account string) error {
	target, err := syscall.UTF16PtrFromString(targetName(service, account))
	if err != nil {
		return fmt.Errorf("encode target name: %w", err)
	}

	ret, _, err := procCredDeleteW.Call(
		uintptr(unsafe.Pointer(target)),
		uintptr(credTypeGeneric),
		0, // flags
	)
	if ret == 0 {
		return fmt.Errorf("CredDeleteW failed: %w", err)
	}

	return nil
}
