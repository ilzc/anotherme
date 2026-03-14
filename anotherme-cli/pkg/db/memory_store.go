package db

import (
	"database/sql"
	"encoding/json"
)

// CountMemories returns the total number of rows in the memories table.
func CountMemories(db *sql.DB) (int, error) {
	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM memories").Scan(&count)
	return count, err
}

// SearchMemories searches memories whose content contains the given keyword.
// Results are ordered by importance DESC, then createdAt DESC.
func SearchMemories(db *sql.DB, keyword string, limit int) ([]Memory, error) {
	rows, err := db.Query(`
		SELECT id, content, category, keywords, importance, accessCount,
		       pinned, sourceType, sourceId, createdAt, lastAccessedAt
		FROM memories
		WHERE content LIKE '%' || ? || '%' OR keywords LIKE '%' || ? || '%'
		ORDER BY importance DESC, createdAt DESC
		LIMIT ?
	`, keyword, keyword, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []Memory
	for rows.Next() {
		m, err := scanMemory(rows)
		if err != nil {
			return nil, err
		}
		results = append(results, *m)
	}
	return results, rows.Err()
}

func scanMemory(rows *sql.Rows) (*Memory, error) {
	var m Memory
	var (
		keywordsJSON sql.NullString
		pinnedInt    int
		sourceID     sql.NullString
		createdStr   string
		accessedStr  string
	)

	err := rows.Scan(
		&m.ID,
		&m.Content,
		&m.Category,
		&keywordsJSON,
		&m.Importance,
		&m.AccessCount,
		&pinnedInt,
		&m.SourceType,
		&sourceID,
		&createdStr,
		&accessedStr,
	)
	if err != nil {
		return nil, err
	}

	m.Pinned = pinnedInt != 0

	if sourceID.Valid {
		m.SourceID = &sourceID.String
	}

	m.CreatedAt, err = ParseGRDBDate(createdStr)
	if err != nil {
		return nil, err
	}

	m.LastAccessedAt, err = ParseGRDBDate(accessedStr)
	if err != nil {
		return nil, err
	}

	if keywordsJSON.Valid && keywordsJSON.String != "" {
		_ = json.Unmarshal([]byte(keywordsJSON.String), &m.Keywords)
	}

	return &m, nil
}

// FetchRecentMemories returns the most recent memories, ordered by lastAccessedAt DESC.
func FetchRecentMemories(db *sql.DB, limit int) ([]Memory, error) {
	rows, err := db.Query(`
		SELECT id, content, category, keywords, importance, accessCount,
		       pinned, sourceType, sourceId, createdAt, lastAccessedAt
		FROM memories
		ORDER BY lastAccessedAt DESC
		LIMIT ?
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []Memory
	for rows.Next() {
		m, err := scanMemory(rows)
		if err != nil {
			return nil, err
		}
		results = append(results, *m)
	}
	return results, rows.Err()
}
