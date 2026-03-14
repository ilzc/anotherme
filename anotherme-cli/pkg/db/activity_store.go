package db

import (
	"database/sql"
	"encoding/json"
	"time"
)

// CountActivities returns the total number of rows in activity_logs.
func CountActivities(db *sql.DB) (int, error) {
	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM activity_logs").Scan(&count)
	return count, err
}

// LatestActivity returns the most recent activity record, or nil if the table is empty.
func LatestActivity(db *sql.DB) (*ActivityRecord, error) {
	row := db.QueryRow(`
		SELECT id, timestamp, appName, windowTitle, extractedText, contentSummary,
		       userIntent, activityCategory, topics, screenIndex, captureMode,
		       analyzed, visibleApps, userAuthored, userExpressions, engagementLevel
		FROM activity_logs
		ORDER BY timestamp DESC
		LIMIT 1
	`)

	rec, err := scanActivityRecord(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return rec, nil
}

// FetchActivities returns activities with timestamp >= since, ordered by timestamp DESC.
func FetchActivities(db *sql.DB, since time.Time, limit int) ([]ActivityRecord, error) {
	rows, err := db.Query(`
		SELECT id, timestamp, appName, windowTitle, extractedText, contentSummary,
		       userIntent, activityCategory, topics, screenIndex, captureMode,
		       analyzed, visibleApps, userAuthored, userExpressions, engagementLevel
		FROM activity_logs
		WHERE timestamp >= ?
		ORDER BY timestamp DESC
		LIMIT ?
	`, FormatGRDBDate(since), limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []ActivityRecord
	for rows.Next() {
		rec, err := scanActivityRows(rows)
		if err != nil {
			return nil, err
		}
		results = append(results, *rec)
	}
	return results, rows.Err()
}

// scanner is satisfied by both *sql.Row and *sql.Rows.
type scanner interface {
	Scan(dest ...interface{}) error
}

func scanActivity(s scanner) (*ActivityRecord, error) {
	var rec ActivityRecord
	var (
		tsStr            string
		extractedText    sql.NullString
		contentSummary   sql.NullString
		userIntent       sql.NullString
		topicsJSON       sql.NullString
		analyzedInt      int
		visibleAppsJSON  sql.NullString
		userAuthored     sql.NullString
		userExprsJSON    sql.NullString
		engagementLevel  sql.NullString
	)

	err := s.Scan(
		&rec.ID,
		&tsStr,
		&rec.AppName,
		&rec.WindowTitle,
		&extractedText,
		&contentSummary,
		&userIntent,
		&rec.ActivityCategory,
		&topicsJSON,
		&rec.ScreenIndex,
		&rec.CaptureMode,
		&analyzedInt,
		&visibleAppsJSON,
		&userAuthored,
		&userExprsJSON,
		&engagementLevel,
	)
	if err != nil {
		return nil, err
	}

	rec.Timestamp, err = ParseGRDBDate(tsStr)
	if err != nil {
		return nil, err
	}

	rec.Analyzed = analyzedInt != 0

	if extractedText.Valid {
		rec.ExtractedText = &extractedText.String
	}
	if contentSummary.Valid {
		rec.ContentSummary = &contentSummary.String
	}
	if userIntent.Valid {
		rec.UserIntent = &userIntent.String
	}
	if userAuthored.Valid {
		rec.UserAuthored = &userAuthored.String
	}
	if engagementLevel.Valid {
		rec.EngagementLevel = &engagementLevel.String
	}

	if topicsJSON.Valid && topicsJSON.String != "" {
		_ = json.Unmarshal([]byte(topicsJSON.String), &rec.Topics)
	}
	if visibleAppsJSON.Valid && visibleAppsJSON.String != "" {
		_ = json.Unmarshal([]byte(visibleAppsJSON.String), &rec.VisibleApps)
	}
	if userExprsJSON.Valid && userExprsJSON.String != "" {
		_ = json.Unmarshal([]byte(userExprsJSON.String), &rec.UserExpressions)
	}

	return &rec, nil
}

func scanActivityRecord(row *sql.Row) (*ActivityRecord, error) {
	return scanActivity(row)
}

func scanActivityRows(rows *sql.Rows) (*ActivityRecord, error) {
	return scanActivity(rows)
}
