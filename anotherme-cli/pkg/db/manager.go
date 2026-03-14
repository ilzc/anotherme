package db

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"

	_ "modernc.org/sqlite"
)

// Manager holds connections to all 10 SQLite databases.
type Manager struct {
	dbPath     string
	activityDB *sql.DB
	layerDBs   [5]*sql.DB // index 0 = layer1 … 4 = layer5
	memoryDB   *sql.DB
	chatDB     *sql.DB
	insightDB  *sql.DB
	snapshotDB *sql.DB
}

// NewManager opens every database under dbPath.
// All databases are read-only except chat.sqlite.
func NewManager(dbPath string) (*Manager, error) {
	// Expand ~ if needed
	if len(dbPath) >= 2 && dbPath[:2] == "~/" {
		home, err := os.UserHomeDir()
		if err != nil {
			return nil, fmt.Errorf("resolve home directory: %w", err)
		}
		dbPath = filepath.Join(home, dbPath[2:])
	}

	m := &Manager{dbPath: dbPath}

	// Read-only databases
	roDBs := []struct {
		file   string
		target **sql.DB
	}{
		{"activity.sqlite", &m.activityDB},
		{"memory.sqlite", &m.memoryDB},
		{"insights.sqlite", &m.insightDB},
		{"snapshots.sqlite", &m.snapshotDB},
	}

	for _, entry := range roDBs {
		path := filepath.Join(dbPath, entry.file)
		db, err := openReadOnly(path)
		if err != nil {
			m.Close()
			return nil, fmt.Errorf("open %s: %w", entry.file, err)
		}
		if err := db.Ping(); err != nil {
			db.Close()
			m.Close()
			return nil, fmt.Errorf("ping %s: %w", entry.file, err)
		}
		*entry.target = db
	}

	// Layer databases (read-only)
	// Actual file names: layer1_rhythms, layer2_knowledge, layer3_cognitive, layer4_expression, layer5_values
	layerFiles := [5]string{
		"layer1_rhythms.sqlite",
		"layer2_knowledge.sqlite",
		"layer3_cognitive.sqlite",
		"layer4_expression.sqlite",
		"layer5_values.sqlite",
	}
	for i, file := range layerFiles {
		path := filepath.Join(dbPath, file)
		db, err := openReadOnly(path)
		if err != nil {
			m.Close()
			return nil, fmt.Errorf("open %s: %w", file, err)
		}
		if err := db.Ping(); err != nil {
			db.Close()
			m.Close()
			return nil, fmt.Errorf("ping %s: %w", file, err)
		}
		m.layerDBs[i] = db
	}

	// Chat database (read-write)
	chatPath := filepath.Join(dbPath, "chat.sqlite")
	chatDB, err := openReadWrite(chatPath)
	if err != nil {
		m.Close()
		return nil, fmt.Errorf("open chat.sqlite: %w", err)
	}
	if err := chatDB.Ping(); err != nil {
		chatDB.Close()
		m.Close()
		return nil, fmt.Errorf("ping chat.sqlite: %w", err)
	}
	if err := ensureChatTables(chatDB); err != nil {
		chatDB.Close()
		m.Close()
		return nil, fmt.Errorf("migrate chat.sqlite: %w", err)
	}
	m.chatDB = chatDB

	return m, nil
}

// ensureChatTables creates the chat tables if they don't exist.
// This is needed when the CLI creates chat.sqlite before the Swift app has run.
func ensureChatTables(db *sql.DB) error {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS "chat_sessions" (
			"id" TEXT PRIMARY KEY,
			"createdAt" DATETIME NOT NULL,
			"title" TEXT NOT NULL DEFAULT ''
		);
		CREATE TABLE IF NOT EXISTS "chat_messages" (
			"id" TEXT PRIMARY KEY,
			"sessionId" TEXT NOT NULL REFERENCES "chat_sessions"("id") ON DELETE CASCADE,
			"timestamp" DATETIME NOT NULL,
			"role" TEXT NOT NULL,
			"content" TEXT NOT NULL,
			"referencedLayers" TEXT NOT NULL DEFAULT '[]',
			"referencedData" TEXT NOT NULL DEFAULT '{}'
		);
		CREATE INDEX IF NOT EXISTS "chat_messages_on_sessionId" ON "chat_messages"("sessionId");
	`)
	return err
}

func openReadOnly(path string) (*sql.DB, error) {
	dsn := fmt.Sprintf("file:%s?mode=ro&_journal_mode=WAL", path)
	return sql.Open("sqlite", dsn)
}

func openReadWrite(path string) (*sql.DB, error) {
	dsn := fmt.Sprintf("file:%s?_journal_mode=WAL", path)
	return sql.Open("sqlite", dsn)
}

// DBPath returns the base directory path for all databases.
func (m *Manager) DBPath() string { return m.dbPath }

// ActivityDB returns the activity.sqlite connection.
func (m *Manager) ActivityDB() *sql.DB { return m.activityDB }

// LayerDB returns the layer N database (1-5). Returns nil for invalid N.
func (m *Manager) LayerDB(n int) *sql.DB {
	if n < 1 || n > 5 {
		return nil
	}
	return m.layerDBs[n-1]
}

// MemoryDB returns the memory.sqlite connection.
func (m *Manager) MemoryDB() *sql.DB { return m.memoryDB }

// ChatDB returns the chat.sqlite connection (read-write).
func (m *Manager) ChatDB() *sql.DB { return m.chatDB }

// InsightDB returns the insights.sqlite connection.
func (m *Manager) InsightDB() *sql.DB { return m.insightDB }

// SnapshotDB returns the snapshots.sqlite connection.
func (m *Manager) SnapshotDB() *sql.DB { return m.snapshotDB }

// Close closes all open database connections.
func (m *Manager) Close() {
	dbs := []*sql.DB{m.activityDB, m.memoryDB, m.chatDB, m.insightDB, m.snapshotDB}
	for _, db := range m.layerDBs {
		dbs = append(dbs, db)
	}
	for _, db := range dbs {
		if db != nil {
			db.Close()
		}
	}
}
