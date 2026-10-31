#!/usr/bin/env python3
"""
Adversarial Stress Test Harness for Android Room Database & TypeConverters.
Author: challenger_2 (Adversarial Empirical Verification)

Adversarial Objectives:
1. Massive Relational Integrity Stress Test:
   - Insert 100 assets.
   - For each asset, insert 4 lifecycle events (400 events).
   - For each event, insert 2 event-linked attachments (800 attachments).
   - For each asset, insert 1 asset-linked attachment (100 attachments).
   - For each asset, insert 3 dynamic fields (300 dynamic fields).
   - Total rows: 100 + 400 + 900 + 300 = 1700 rows.
   - Execute batch delete of 50 assets and individual delete of 50 assets.
   - Assert with zero tolerance: exactly 0 orphan lifecycle_events, attachments, or dynamic_fields remain.
2. Dual Foreign Key Cascade Isolation:
   - Delete a single event: assert its attachments are deleted while other events/attachments under the same asset remain intact.
3. TypeConverter Stress Testing:
   - Empty lists ([] and None)
   - Single elements ([0], [1], [-1], [-30])
   - Standard negative offset lists ([-30, -7, -1, 0])
   - Large lists (10,000 elements)
   - Adversarial malformed string inputs (whitespace, non-integers, 64-bit int overflow strings)
"""

import sqlite3
import sys
import time
import uuid

# MARK: - TypeConverter Under Test (Direct replica of Converters.kt logic)

class RoomConverters:
    @staticmethod
    def from_int_list(int_list):
        if int_list is None:
            return None
        return ",".join(str(x) for x in int_list)

    @staticmethod
    def to_int_list(data):
        if not data:
            return []
        result = []
        for token in data.split(","):
            token = token.strip()
            try:
                # 32-bit signed integer check matching Kotlin toIntOrNull()
                val = int(token)
                if -2147483648 <= val <= 2147483647:
                    result.append(val)
            except ValueError:
                pass
        return result


# MARK: - Database Schema Setup

def create_in_memory_db():
    conn = sqlite3.connect(":memory:")
    conn.execute("PRAGMA foreign_keys = ON;")
    cursor = conn.cursor()
    cursor.executescript("""
        CREATE TABLE IF NOT EXISTS assets (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            subtitle TEXT,
            categoryRaw TEXT NOT NULL,
            iconName TEXT NOT NULL,
            accentColorHex TEXT NOT NULL,
            currentMetricValue REAL,
            metricUnit TEXT,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS lifecycle_events (
            id TEXT PRIMARY KEY NOT NULL,
            assetId TEXT NOT NULL,
            title TEXT NOT NULL,
            eventDescription TEXT,
            dueDate INTEGER NOT NULL,
            completedDate INTEGER,
            isCompleted INTEGER NOT NULL DEFAULT 0,
            cost REAL,
            currency TEXT NOT NULL DEFAULT 'RON',
            cadenceDays INTEGER,
            cadenceMetricInterval REAL,
            metricTriggerValue REAL,
            reminderOffsetDays TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            FOREIGN KEY (assetId) REFERENCES assets(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS index_lifecycle_events_assetId ON lifecycle_events(assetId);
        CREATE INDEX IF NOT EXISTS index_lifecycle_events_dueDate ON lifecycle_events(dueDate);
        CREATE INDEX IF NOT EXISTS index_lifecycle_events_isCompleted ON lifecycle_events(isCompleted);

        CREATE TABLE IF NOT EXISTS attachments (
            id TEXT PRIMARY KEY NOT NULL,
            assetId TEXT,
            eventId TEXT,
            fileName TEXT NOT NULL,
            fileExtension TEXT NOT NULL,
            filePath TEXT,
            extractedText TEXT,
            createdAt INTEGER NOT NULL,
            FOREIGN KEY (assetId) REFERENCES assets(id) ON DELETE CASCADE,
            FOREIGN KEY (eventId) REFERENCES lifecycle_events(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS index_attachments_assetId ON attachments(assetId);
        CREATE INDEX IF NOT EXISTS index_attachments_eventId ON attachments(eventId);

        CREATE TABLE IF NOT EXISTS dynamic_fields (
            id TEXT PRIMARY KEY NOT NULL,
            assetId TEXT NOT NULL,
            key TEXT NOT NULL,
            label TEXT NOT NULL,
            fieldTypeRaw TEXT NOT NULL,
            stringValue TEXT,
            numberValue REAL,
            dateValue INTEGER,
            boolValue INTEGER,
            FOREIGN KEY (assetId) REFERENCES assets(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS index_dynamic_fields_assetId ON dynamic_fields(assetId);
    """)
    conn.commit()
    return conn


# MARK: - Tests

def test_100_assets_cascade_delete_stress():
    print("▶ Running 100 Assets Massive Cascade Deletion Stress Test...")
    conn = create_in_memory_db()
    cur = conn.cursor()

    asset_ids = []
    event_ids = []
    att_ids = []
    field_ids = []

    now_ms = int(time.time() * 1000)

    # 1. Insert 100 Assets
    for i in range(100):
        a_id = f"asset_{i:03d}_{uuid.uuid4().hex[:8]}"
        asset_ids.append(a_id)
        cur.execute("""
            INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (a_id, f"Asset #{i}", f"Subtitle {i}", "vehicle" if i % 2 == 0 else "home",
              "car.fill", "007AFF", float(i * 1000), "km", now_ms, now_ms))

        # 3 Dynamic Fields per asset
        for f in range(3):
            fid = f"field_{i}_{f}_{uuid.uuid4().hex[:6]}"
            field_ids.append(fid)
            cur.execute("""
                INSERT INTO dynamic_fields VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (fid, a_id, f"custom_key_{f}", f"Field {f}", "text", f"Val_{i}_{f}", None, None, None))

        # 1 Direct Asset Attachment
        att_asset_id = f"att_asset_{i}_{uuid.uuid4().hex[:6]}"
        att_ids.append(att_asset_id)
        cur.execute("""
            INSERT INTO attachments VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (att_asset_id, a_id, None, f"contract_{i}.pdf", "pdf", f"/docs/{i}.pdf", "OK", now_ms))

        # 4 Lifecycle Events per asset
        for e in range(4):
            eid = f"event_{i}_{e}_{uuid.uuid4().hex[:6]}"
            event_ids.append(eid)
            cur.execute("""
                INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (eid, a_id, f"Obligație {i}-{e}", f"Desc {e}", now_ms + (e * 86400000),
                  None, 0, 150.0 + (e * 50), "RON", 365, None, None, "-30,-7,-1,0", now_ms))

            # 2 Attachments per event
            for ea in range(2):
                att_event_id = f"att_ev_{i}_{e}_{ea}_{uuid.uuid4().hex[:6]}"
                att_ids.append(att_event_id)
                cur.execute("""
                    INSERT INTO attachments VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (att_event_id, a_id, eid, f"factura_{i}_{e}_{ea}.pdf", "pdf", f"/inv/{i}/{e}.pdf", "FACTURA", now_ms))

    conn.commit()

    # Verify counts before deletion
    cur.execute("SELECT count(*) FROM assets")
    assert cur.fetchone()[0] == 100, "Must have 100 assets"
    cur.execute("SELECT count(*) FROM lifecycle_events")
    assert cur.fetchone()[0] == 400, "Must have 400 events"
    cur.execute("SELECT count(*) FROM attachments")
    assert cur.fetchone()[0] == 900, "Must have 900 attachments (100 asset-direct + 800 event-linked)"
    cur.execute("SELECT count(*) FROM dynamic_fields")
    assert cur.fetchone()[0] == 300, "Must have 300 dynamic fields"

    print("  ✓ Successfully inserted 1,700 relational records across 100 assets.")

    # Phase A: Delete first 50 assets in one bulk query
    half_assets = asset_ids[:50]
    placeholders = ",".join("?" for _ in half_assets)
    cur.execute(f"DELETE FROM assets WHERE id IN ({placeholders})", half_assets)
    conn.commit()

    # Verify remaining counts
    cur.execute("SELECT count(*) FROM assets")
    assert cur.fetchone()[0] == 50, "50 assets should remain"
    cur.execute("SELECT count(*) FROM lifecycle_events")
    assert cur.fetchone()[0] == 200, "200 events should remain"
    cur.execute("SELECT count(*) FROM attachments")
    assert cur.fetchone()[0] == 450, "450 attachments should remain"
    cur.execute("SELECT count(*) FROM dynamic_fields")
    assert cur.fetchone()[0] == 150, "150 dynamic fields should remain"
    print("  ✓ Bulk deletion of 50 assets cleanly cascaded: 50% records remaining.")

    # Phase B: Delete remaining 50 assets individually in loop
    for a_id in asset_ids[50:]:
        cur.execute("DELETE FROM assets WHERE id = ?", (a_id,))
    conn.commit()

    # Verify ZERO orphans across all tables
    cur.execute("SELECT count(*) FROM assets")
    assert cur.fetchone()[0] == 0, "0 assets must remain"
    cur.execute("SELECT count(*) FROM lifecycle_events")
    orphan_events = cur.fetchone()[0]
    assert orphan_events == 0, f"Found {orphan_events} orphan lifecycle_events!"

    cur.execute("SELECT count(*) FROM attachments")
    orphan_attachments = cur.fetchone()[0]
    assert orphan_attachments == 0, f"Found {orphan_attachments} orphan attachments!"

    cur.execute("SELECT count(*) FROM dynamic_fields")
    orphan_fields = cur.fetchone()[0]
    assert orphan_fields == 0, f"Found {orphan_fields} orphan dynamic_fields!"

    conn.close()
    print("  ✅ PASS: 100 Assets CASCADE Delete Stress Test — Zero orphan records!")


def test_dual_foreign_key_cascade_isolation():
    print("▶ Running Dual Foreign Key Cascade Isolation Test...")
    conn = create_in_memory_db()
    cur = conn.cursor()

    asset_id = "asset_isolation_01"
    cur.execute("INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (asset_id, "Asset Test", None, "home", "house.fill", "007AFF", None, None, 1000, 1000))

    ev1 = "ev_01"
    ev2 = "ev_02"
    cur.execute("INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (ev1, asset_id, "Event 1", None, 5000, None, 0, 100.0, "RON", None, None, None, "-30", 1000))
    cur.execute("INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (ev2, asset_id, "Event 2", None, 6000, None, 0, 200.0, "RON", None, None, None, "-30", 1000))

    att_ev1 = "att_ev1"
    att_ev2 = "att_ev2"
    att_asset_only = "att_asset_only"
    cur.execute("INSERT INTO attachments VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (att_ev1, asset_id, ev1, "f1.pdf", "pdf", None, None, 1000))
    cur.execute("INSERT INTO attachments VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (att_ev2, asset_id, ev2, "f2.pdf", "pdf", None, None, 1000))
    cur.execute("INSERT INTO attachments VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (att_asset_only, asset_id, None, "f3.pdf", "pdf", None, None, 1000))
    conn.commit()

    # Delete ONLY event 1
    cur.execute("DELETE FROM lifecycle_events WHERE id = ?", (ev1,))
    conn.commit()

    # Assert:
    # 1. Event 1 is gone
    cur.execute("SELECT count(*) FROM lifecycle_events WHERE id = ?", (ev1,))
    assert cur.fetchone()[0] == 0
    # 2. Event 2 remains
    cur.execute("SELECT count(*) FROM lifecycle_events WHERE id = ?", (ev2,))
    assert cur.fetchone()[0] == 1
    # 3. att_ev1 is CASCADE-deleted via eventId FK
    cur.execute("SELECT count(*) FROM attachments WHERE id = ?", (att_ev1,))
    assert cur.fetchone()[0] == 0, "Attachment for event 1 must be deleted"
    # 4. att_ev2 and att_asset_only remain
    cur.execute("SELECT count(*) FROM attachments WHERE id = ?", (att_ev2,))
    assert cur.fetchone()[0] == 1, "Attachment for event 2 must remain"
    cur.execute("SELECT count(*) FROM attachments WHERE id = ?", (att_asset_only,))
    assert cur.fetchone()[0] == 1, "Asset-level attachment must remain"

    conn.close()
    print("  ✅ PASS: Dual Foreign Key Cascade Isolation verified.")


def test_type_converters_adversarial():
    print("▶ Running TypeConverter Adversarial Round-Trip Stress Tests...")
    conv = RoomConverters()

    # 1. Empty and None cases
    assert conv.from_int_list(None) is None
    assert conv.from_int_list([]) == ""
    assert conv.to_int_list(None) == []
    assert conv.to_int_list("") == []
    assert conv.to_int_list("   ") == []

    # 2. Single Elements
    for elem in [0, 1, -1, 30, -30, 2147483647, -2147483648]:
        serialized = conv.from_int_list([elem])
        deserialized = conv.to_int_list(serialized)
        assert deserialized == [elem], f"Mismatch for single element {elem}: got {deserialized}"

    # 3. Standard Negative & Mixed Offsets
    test_cases = [
        [-30, -7, -1, 0],
        [30, 7, 1, 0],
        [-365, -180, -90, -60, -30, -14, -7, -3, -1, 0],
        [0],
        [-1]
    ]
    for case in test_cases:
        s = conv.from_int_list(case)
        d = conv.to_int_list(s)
        assert d == case, f"Failed round-trip for {case}: got {d}"

    # 4. Whitespace and formatting resilience
    messy_string = "  -30  ,  -7 , -1 , 0 ,   14  "
    assert conv.to_int_list(messy_string) == [-30, -7, -1, 0, 14]

    # 5. Non-numeric tokens & overflow resilience (Kotlin toIntOrNull behavior)
    adversarial_string = "-30, foo, 99999999999999999999999999999999, -7, bar, , -1, NaN, 0"
    assert conv.to_int_list(adversarial_string) == [-30, -7, -1, 0], "Should prune invalid and overflowing values"

    # 6. Large List Stress Test (10,000 items)
    large_list = list(range(-5000, 5000))
    t0 = time.time()
    serialized_large = conv.from_int_list(large_list)
    deserialized_large = conv.to_int_list(serialized_large)
    duration = time.time() - t0
    assert deserialized_large == large_list, "10,000 element round trip must match exactly"
    print(f"  ✓ 10,000-element TypeConverter round-trip completed in {duration:.4f}s.")

    print("  ✅ PASS: TypeConverter Adversarial Tests completed successfully.")


def main():
    print("==================================================================")
    print("   ADVERSARIAL STRESS TEST: ANDROID ROOM CASCADE & CONVERTERS    ")
    print("==================================================================")
    start = time.time()
    try:
        test_100_assets_cascade_delete_stress()
        test_dual_foreign_key_cascade_isolation()
        test_type_converters_adversarial()
        duration = time.time() - start
        print("------------------------------------------------------------------")
        print(f"🎉 ALL ROOM DATABASE ADVERSARIAL STRESS TESTS PASSED! ({duration:.3f}s)")
        print("==================================================================")
        return 0
    except Exception as e:
        print(f"\n❌ ADVERSARIAL TEST FAILED: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
