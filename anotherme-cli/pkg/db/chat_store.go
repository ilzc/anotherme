package db

import (
	"database/sql"
	"encoding/json"
)

// CreateSession inserts a new chat session into the chat_sessions table.
func CreateSession(db *sql.DB, session ChatSession) error {
	_, err := db.Exec(`
		INSERT INTO chat_sessions (id, createdAt, title)
		VALUES (?, ?, ?)
	`, session.ID, FormatGRDBDate(session.CreatedAt), session.Title)
	return err
}

// CreateMessage inserts a new chat message into the chat_messages table.
func CreateMessage(db *sql.DB, msg ChatMessage) error {
	layersJSON, err := json.Marshal(msg.ReferencedLayers)
	if err != nil {
		return err
	}

	dataJSON, err := json.Marshal(msg.ReferencedData)
	if err != nil {
		return err
	}

	_, err = db.Exec(`
		INSERT INTO chat_messages (id, sessionID, timestamp, role, content, referencedLayers, referencedData)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	`, msg.ID, msg.SessionID, FormatGRDBDate(msg.Timestamp), msg.Role, msg.Content,
		string(layersJSON), string(dataJSON))
	return err
}

// FetchSessionMessages returns all messages for a given session, ordered by timestamp ASC.
func FetchSessionMessages(db *sql.DB, sessionID string) ([]ChatMessage, error) {
	rows, err := db.Query(`
		SELECT id, sessionID, timestamp, role, content, referencedLayers, referencedData
		FROM chat_messages
		WHERE sessionID = ?
		ORDER BY timestamp ASC
	`, sessionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []ChatMessage
	for rows.Next() {
		msg, err := scanChatMessage(rows)
		if err != nil {
			return nil, err
		}
		results = append(results, *msg)
	}
	return results, rows.Err()
}

// FetchRecentSessions returns the most recent chat sessions, ordered by createdAt DESC.
func FetchRecentSessions(db *sql.DB, limit int) ([]ChatSession, error) {
	rows, err := db.Query(`
		SELECT id, createdAt, title
		FROM chat_sessions
		ORDER BY createdAt DESC
		LIMIT ?
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []ChatSession
	for rows.Next() {
		sess, err := scanChatSession(rows)
		if err != nil {
			return nil, err
		}
		results = append(results, *sess)
	}
	return results, rows.Err()
}

func scanChatMessage(rows *sql.Rows) (*ChatMessage, error) {
	var msg ChatMessage
	var (
		timestampStr      string
		referencedLayers  sql.NullString
		referencedData    sql.NullString
	)

	err := rows.Scan(
		&msg.ID,
		&msg.SessionID,
		&timestampStr,
		&msg.Role,
		&msg.Content,
		&referencedLayers,
		&referencedData,
	)
	if err != nil {
		return nil, err
	}

	msg.Timestamp, err = ParseGRDBDate(timestampStr)
	if err != nil {
		return nil, err
	}

	if referencedLayers.Valid && referencedLayers.String != "" {
		_ = json.Unmarshal([]byte(referencedLayers.String), &msg.ReferencedLayers)
	}

	if referencedData.Valid && referencedData.String != "" {
		_ = json.Unmarshal([]byte(referencedData.String), &msg.ReferencedData)
	}

	return &msg, nil
}

func scanChatSession(rows *sql.Rows) (*ChatSession, error) {
	var sess ChatSession
	var createdAtStr string

	err := rows.Scan(
		&sess.ID,
		&createdAtStr,
		&sess.Title,
	)
	if err != nil {
		return nil, err
	}

	sess.CreatedAt, err = ParseGRDBDate(createdAtStr)
	if err != nil {
		return nil, err
	}

	return &sess, nil
}
