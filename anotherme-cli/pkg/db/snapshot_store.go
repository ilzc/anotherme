package db

import (
	"database/sql"
)

// CountSnapshots returns the total number of rows in the personality_snapshots table.
func CountSnapshots(db *sql.DB) (int, error) {
	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM personality_snapshots").Scan(&count)
	return count, err
}

// FetchSnapshots returns the most recent personality snapshots, ordered by snapshotDate DESC.
func FetchSnapshots(db *sql.DB, limit int) ([]PersonalitySnapshot, error) {
	rows, err := db.Query(`
		SELECT id, snapshotDate, fullProfile, summaryText, "trigger"
		FROM personality_snapshots
		ORDER BY snapshotDate DESC
		LIMIT ?
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []PersonalitySnapshot
	for rows.Next() {
		snap, err := scanSnapshot(rows)
		if err != nil {
			return nil, err
		}
		results = append(results, *snap)
	}
	return results, rows.Err()
}

func scanSnapshot(rows *sql.Rows) (*PersonalitySnapshot, error) {
	var snap PersonalitySnapshot
	var (
		snapshotDateStr string
		summaryText     sql.NullString
	)

	err := rows.Scan(
		&snap.ID,
		&snapshotDateStr,
		&snap.FullProfile,
		&summaryText,
		&snap.Trigger,
	)
	if err != nil {
		return nil, err
	}

	snap.SnapshotDate, err = ParseGRDBDate(snapshotDateStr)
	if err != nil {
		return nil, err
	}

	if summaryText.Valid {
		snap.SummaryText = &summaryText.String
	}

	return &snap, nil
}
