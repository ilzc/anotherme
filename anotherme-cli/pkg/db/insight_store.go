package db

import (
	"database/sql"
	"encoding/json"
)

// CountInsights returns the total number of rows in the insights table.
func CountInsights(db *sql.DB) (int, error) {
	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM insights").Scan(&count)
	return count, err
}

// FetchInsights returns the most recent insights, ordered by createdAt DESC.
func FetchInsights(db *sql.DB, limit int) ([]Insight, error) {
	rows, err := db.Query(`
		SELECT id, createdAt, type, title, content, relatedLayers, notified
		FROM insights
		ORDER BY createdAt DESC
		LIMIT ?
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []Insight
	for rows.Next() {
		ins, err := scanInsight(rows)
		if err != nil {
			return nil, err
		}
		results = append(results, *ins)
	}
	return results, rows.Err()
}

func scanInsight(rows *sql.Rows) (*Insight, error) {
	var ins Insight
	var (
		createdAtStr      string
		relatedLayersJSON sql.NullString
		notifiedInt       int
	)

	err := rows.Scan(
		&ins.ID,
		&createdAtStr,
		&ins.Type,
		&ins.Title,
		&ins.Content,
		&relatedLayersJSON,
		&notifiedInt,
	)
	if err != nil {
		return nil, err
	}

	ins.CreatedAt, err = ParseGRDBDate(createdAtStr)
	if err != nil {
		return nil, err
	}

	ins.Notified = notifiedInt != 0

	if relatedLayersJSON.Valid && relatedLayersJSON.String != "" {
		_ = json.Unmarshal([]byte(relatedLayersJSON.String), &ins.RelatedLayers)
	}

	return &ins, nil
}
