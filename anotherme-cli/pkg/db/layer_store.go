package db

import (
	"database/sql"
	"fmt"
)

// traitTableName returns the table name for the given layer number.
func traitTableName(layer int) string {
	switch layer {
	case 1:
		return "rhythm_traits"
	case 2:
		return "knowledge_traits"
	case 3:
		return "cognitive_traits"
	case 4:
		return "expression_traits"
	case 5:
		return "value_traits"
	default:
		return ""
	}
}

// CountTraits returns the total number of traits in the given layer.
func CountTraits(db *sql.DB, layer int) (int, error) {
	table := traitTableName(layer)
	if table == "" {
		return 0, fmt.Errorf("invalid layer: %d", layer)
	}
	var count int
	err := db.QueryRow(fmt.Sprintf("SELECT COUNT(*) FROM %s", table)).Scan(&count)
	return count, err
}

// FetchTraits returns all traits from the given layer database.
// The query columns vary by layer:
//
//	L1: id, dimension, value, confidence, evidenceCount, firstObserved, lastUpdated, version
//	L2: id, dimension, value, confidence, lastUpdated, version
//	L3: id, dimension, value, description, confidence, evidenceCount, firstObserved, lastUpdated, version
//	L4: id, dimension, value, confidence, lastUpdated, version
//	L5: id, dimension, value, description, confidence, evidenceCount, firstObserved, lastUpdated, version
func FetchTraits(db *sql.DB, layer int) ([]Trait, error) {
	table := traitTableName(layer)
	if table == "" {
		return nil, fmt.Errorf("invalid layer: %d", layer)
	}

	var query string
	switch layer {
	case 1:
		query = fmt.Sprintf(
			"SELECT id, dimension, value, confidence, evidenceCount, firstObserved, lastUpdated, version FROM %s", table)
	case 2, 4:
		query = fmt.Sprintf(
			"SELECT id, dimension, value, confidence, lastUpdated, version FROM %s", table)
	case 3, 5:
		query = fmt.Sprintf(
			"SELECT id, dimension, value, description, confidence, evidenceCount, firstObserved, lastUpdated, version FROM %s", table)
	}

	rows, err := db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var traits []Trait
	for rows.Next() {
		t, err := scanTrait(rows, layer)
		if err != nil {
			return nil, err
		}
		traits = append(traits, *t)
	}
	return traits, rows.Err()
}

func scanTrait(rows *sql.Rows, layer int) (*Trait, error) {
	var t Trait
	t.Layer = layer

	var (
		lastUpdatedStr string
		evidenceCount  sql.NullInt64
		firstObserved  sql.NullString
		description    sql.NullString
	)

	var err error
	switch layer {
	case 1:
		err = rows.Scan(
			&t.ID, &t.Dimension, &t.Value,
			&t.Confidence, &evidenceCount, &firstObserved,
			&lastUpdatedStr, &t.Version,
		)
	case 2, 4:
		err = rows.Scan(
			&t.ID, &t.Dimension, &t.Value,
			&t.Confidence,
			&lastUpdatedStr, &t.Version,
		)
	case 3, 5:
		err = rows.Scan(
			&t.ID, &t.Dimension, &t.Value, &description,
			&t.Confidence, &evidenceCount, &firstObserved,
			&lastUpdatedStr, &t.Version,
		)
	}
	if err != nil {
		return nil, err
	}

	t.LastUpdated, err = ParseGRDBDate(lastUpdatedStr)
	if err != nil {
		return nil, fmt.Errorf("parse lastUpdated: %w", err)
	}

	if description.Valid {
		t.Description = &description.String
	}

	if evidenceCount.Valid {
		ec := int(evidenceCount.Int64)
		t.EvidenceCount = &ec
	}

	if firstObserved.Valid && firstObserved.String != "" {
		fo, err := ParseGRDBDate(firstObserved.String)
		if err != nil {
			return nil, fmt.Errorf("parse firstObserved: %w", err)
		}
		t.FirstObserved = &fo
	}

	return &t, nil
}
