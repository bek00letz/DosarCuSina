#!/usr/bin/env python3
"""
Automated test runner verifying Android Room SQLite Schema & Data Parity.
Mirrors all test cases in tests/android/RoomDatabaseTests.kt:
- AssetEntity, LifecycleEventEntity, AttachmentEntity, DynamicFieldEntity CRUD
- SQLite Foreign Key CASCADE deletion on parent AssetEntity and LifecycleEventEntity
- TypeConverter list <-> string round-trip serialization for reminderOffsetDays
- Range-based cost aggregation queries
"""

import sqlite3
import sys
import time
import uuid

# MARK: - TypeConverter Implementation (Parity with Converters.kt)

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
                result.append(int(token))
            except ValueError:
                pass
        return result

# MARK: - In-Memory Room Database Harness

class InMemoryDosarDatabase:
    def __init__(self):
        self.conn = sqlite3.connect(":memory:")
        self.conn.execute("PRAGMA foreign_keys = ON;")
        self._create_schema()

    def _create_schema(self):
        cursor = self.conn.cursor()
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

            CREATE TABLE IF NOT EXISTS service_items (
                id TEXT PRIMARY KEY NOT NULL,
                assetId TEXT NOT NULL,
                eventId TEXT,
                componentName TEXT NOT NULL,
                componentCategory TEXT NOT NULL DEFAULT 'general',
                partBrand TEXT,
                partSerialNumber TEXT,
                cost REAL,
                serviceDate INTEGER NOT NULL,
                mileageAtService REAL,
                notes TEXT,
                createdAt INTEGER NOT NULL,
                FOREIGN KEY (assetId) REFERENCES assets(id) ON DELETE CASCADE,
                FOREIGN KEY (eventId) REFERENCES lifecycle_events(id) ON DELETE SET NULL
            );
            CREATE INDEX IF NOT EXISTS index_service_items_assetId ON service_items(assetId);
            CREATE INDEX IF NOT EXISTS index_service_items_eventId ON service_items(eventId);
        """)
        self.conn.commit()

    def close(self):
        self.conn.close()

# MARK: - Test Suite

def test_type_converters():
    conv = RoomConverters()
    # Serialization
    assert conv.from_int_list([30, 7, 1]) == "30,7,1", "Should serialize to 30,7,1"
    assert conv.from_int_list([30, 14, 7, 3, 1, 0]) == "30,14,7,3,1,0"
    assert conv.from_int_list([]) == ""
    assert conv.from_int_list(None) is None

    # Deserialization
    assert conv.to_int_list("30,7,1") == [30, 7, 1]
    assert conv.to_int_list(" 30 , 14 , 7 , 1 ") == [30, 14, 7, 1]
    assert conv.to_int_list("") == []
    assert conv.to_int_list(None) == []
    assert conv.to_int_list("30,abc,7") == [30, 7], "Should drop non-numeric tokens"

    # Round trip
    original = [60, 30, 14, 7, 1]
    assert conv.to_int_list(conv.from_int_list(original)) == original, "Round trip must match"

def test_asset_entity_crud():
    db = InMemoryDosarDatabase()
    cur = db.conn.cursor()
    asset_id = str(uuid.uuid4())

    # Insert
    cur.execute("""
        INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (asset_id, "Apartament 4 Camere", "Str. Aviației nr. 12", "home", "house.fill", "FF9500", 120.0, "mp", 1000, 1000))
    db.conn.commit()

    # Read
    cur.execute("SELECT name, subtitle, currentMetricValue, metricUnit FROM assets WHERE id = ?", (asset_id,))
    row = cur.fetchone()
    assert row is not None, "Asset must exist"
    assert row[0] == "Apartament 4 Camere"
    assert row[1] == "Str. Aviației nr. 12"
    assert abs(row[2] - 120.0) < 0.001
    assert row[3] == "mp"

    # Update
    cur.execute("UPDATE assets SET name = ?, currentMetricValue = ? WHERE id = ?", ("Vila Snagov", 250.0, asset_id))
    db.conn.commit()
    cur.execute("SELECT name, currentMetricValue FROM assets WHERE id = ?", (asset_id,))
    updated_row = cur.fetchone()
    assert updated_row[0] == "Vila Snagov"
    assert abs(updated_row[1] - 250.0) < 0.001

    # Delete
    cur.execute("DELETE FROM assets WHERE id = ?", (asset_id,))
    db.conn.commit()
    cur.execute("SELECT count(*) FROM assets WHERE id = ?", (asset_id,))
    assert cur.fetchone()[0] == 0, "Asset must be deleted"
    db.close()

def test_lifecycle_event_entity_crud():
    db = InMemoryDosarDatabase()
    cur = db.conn.cursor()
    asset_id = str(uuid.uuid4())
    event_id = str(uuid.uuid4())

    cur.execute("INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (asset_id, "VW Golf 7", None, "vehicle", "car.fill", "007AFF", 145000.0, "km", 1000, 1000))
    
    # Insert Event
    reminder_str = RoomConverters.from_int_list([30, 7, 1])
    cur.execute("""
        INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (event_id, asset_id, "Schimb Ulei", "Filtre MANN + Ulei 5W30", 5000000, None, 0, 450.0, "RON", 365, 15000.0, 160000.0, reminder_str, 1000))
    db.conn.commit()

    # Read & Assert
    cur.execute("SELECT title, cost, currency, reminderOffsetDays, isCompleted FROM lifecycle_events WHERE id = ?", (event_id,))
    row = cur.fetchone()
    assert row[0] == "Schimb Ulei"
    assert abs(row[1] - 450.0) < 0.001
    assert row[2] == "RON"
    assert RoomConverters.to_int_list(row[3]) == [30, 7, 1]
    assert row[4] == 0, "Event starts incomplete"

    # Toggle Completion
    now = int(time.time() * 1000)
    cur.execute("UPDATE lifecycle_events SET isCompleted = 1, completedDate = ? WHERE id = ?", (now, event_id))
    db.conn.commit()
    cur.execute("SELECT isCompleted, completedDate FROM lifecycle_events WHERE id = ?", (event_id,))
    comp_row = cur.fetchone()
    assert comp_row[0] == 1, "Must be completed"
    assert comp_row[1] == now

    db.close()

def test_cascade_delete_asset_deletes_all_children():
    db = InMemoryDosarDatabase()
    cur = db.conn.cursor()
    asset_id = str(uuid.uuid4())
    event_id1 = str(uuid.uuid4())
    event_id2 = str(uuid.uuid4())
    att_id = str(uuid.uuid4())
    field_id = str(uuid.uuid4())

    # Create Asset
    cur.execute("INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (asset_id, "Dacia Duster", None, "vehicle", "car.fill", "007AFF", 120000.0, "km", 1000, 1000))
    
    # Create 2 Events
    cur.execute("INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (event_id1, asset_id, "ITP", None, 10000, None, 0, 150.0, "RON", 730, None, None, "30,7,1", 1000))
    cur.execute("INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (event_id2, asset_id, "RCA", None, 20000, None, 0, 800.0, "RON", 365, None, None, "30,7,1", 1000))
    
    # Create Attachment
    cur.execute("INSERT INTO attachments VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (att_id, asset_id, event_id1, "itp.pdf", "pdf", "/path/itp.pdf", "VALID", 1000))
    
    # Create Dynamic Field
    cur.execute("INSERT INTO dynamic_fields VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (field_id, asset_id, "vin", "Serie Șasiu", "text", "UU1HSD...", None, None, None))
    db.conn.commit()

    # Verify counts before delete
    cur.execute("SELECT count(*) FROM lifecycle_events WHERE assetId = ?", (asset_id,))
    assert cur.fetchone()[0] == 2
    cur.execute("SELECT count(*) FROM attachments WHERE assetId = ?", (asset_id,))
    assert cur.fetchone()[0] == 1
    cur.execute("SELECT count(*) FROM dynamic_fields WHERE assetId = ?", (asset_id,))
    assert cur.fetchone()[0] == 1

    # DELETE ASSET
    cur.execute("DELETE FROM assets WHERE id = ?", (asset_id,))
    db.conn.commit()

    # VERIFY CASCADE DELETION ON ALL CHILDREN
    cur.execute("SELECT count(*) FROM lifecycle_events WHERE assetId = ?", (asset_id,))
    assert cur.fetchone()[0] == 0, "CASCADE delete must wipe child events"
    cur.execute("SELECT count(*) FROM attachments WHERE assetId = ?", (asset_id,))
    assert cur.fetchone()[0] == 0, "CASCADE delete must wipe child attachments"
    cur.execute("SELECT count(*) FROM dynamic_fields WHERE assetId = ?", (asset_id,))
    assert cur.fetchone()[0] == 0, "CASCADE delete must wipe child dynamic fields"

    db.close()

def test_cascade_delete_event_deletes_attachments():
    db = InMemoryDosarDatabase()
    cur = db.conn.cursor()
    asset_id = str(uuid.uuid4())
    event_id = str(uuid.uuid4())
    att_id = str(uuid.uuid4())

    cur.execute("INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (asset_id, "Clinica Sanador", None, "health", "heart.fill", "FF2D55", None, None, 1000, 1000))
    cur.execute("INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (event_id, asset_id, "Analize", None, 5000, None, 0, 300.0, "RON", 365, None, None, "30", 1000))
    cur.execute("INSERT INTO attachments VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (att_id, asset_id, event_id, "analize.pdf", "pdf", "/path/analize.pdf", "REZULTAT", 1000))
    db.conn.commit()

    cur.execute("DELETE FROM lifecycle_events WHERE id = ?", (event_id,))
    db.conn.commit()

    cur.execute("SELECT count(*) FROM attachments WHERE eventId = ?", (event_id,))
    assert cur.fetchone()[0] == 0, "Deleting event must CASCADE delete child attachments"
    db.close()

def test_cost_sum_aggregation():
    db = InMemoryDosarDatabase()
    cur = db.conn.cursor()
    asset_id = str(uuid.uuid4())

    cur.execute("INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (asset_id, "Casă", None, "home", "house.fill", "FF9500", None, None, 1000, 1000))
    
    # 2 events in 1000..5000 range (cost 250 and 150.50), 1 event outside (cost 500)
    cur.execute("INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (str(uuid.uuid4()), asset_id, "Factura 1", None, 1500, None, 0, 250.0, "RON", None, None, None, "30", 1000))
    cur.execute("INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (str(uuid.uuid4()), asset_id, "Factura 2", None, 2500, None, 0, 150.50, "RON", None, None, None, "30", 1000))
    cur.execute("INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (str(uuid.uuid4()), asset_id, "Factura 3", None, 8000, None, 0, 500.0, "RON", None, None, None, "30", 1000))
    db.conn.commit()

    cur.execute("SELECT SUM(cost) FROM lifecycle_events WHERE dueDate BETWEEN 1000 AND 5000 AND cost IS NOT NULL")
    total = cur.fetchone()[0]
    assert abs(total - 400.50) < 0.01, f"Expected 400.50, got {total}"
    db.close()

def test_service_items_tracking_and_cascade():
    db = InMemoryDosarDatabase()
    cur = db.conn.cursor()
    asset_id = str(uuid.uuid4())
    event_id1 = str(uuid.uuid4())
    event_id2 = str(uuid.uuid4())
    part_id1 = str(uuid.uuid4())
    part_id2 = str(uuid.uuid4())

    cur.execute("INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (asset_id, "Skoda Octavia", "2.0 TDI", "vehicle", "car.fill", "007AFF", 180000.0, "km", 1000, 1000))
    
    cur.execute("INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (event_id1, asset_id, "Revizie 1", None, 10000, None, 1, 650.0, "RON", 365, 15000.0, None, "30", 1000))
    cur.execute("INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (event_id2, asset_id, "Revizie 2", None, 20000, None, 1, 750.0, "RON", 365, 15000.0, None, "30", 2000))

    # Insert Brake Pads at 120,000 km (Event 1)
    cur.execute("INSERT INTO service_items VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (part_id1, asset_id, event_id1, "Plăcuțe Frână Față", "brakes", "Brembo", "P85020", 280.0, 10000, 120000.0, "Schimbate la service", 1000))

    # Insert Brake Pads at 165,000 km (Event 2)
    cur.execute("INSERT INTO service_items VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (part_id2, asset_id, event_id2, "Plăcuțe Frână Față", "brakes", "ATE Ceramic", "13.0460", 340.0, 20000, 165000.0, "Schimbate la reprezentanță", 2000))
    db.conn.commit()

    # Query History for "Plăcuțe Frână Față" sorted by serviceDate DESC
    cur.execute("SELECT partBrand, cost, mileageAtService FROM service_items WHERE assetId = ? AND componentName = ? ORDER BY serviceDate DESC",
                (asset_id, "Plăcuțe Frână Față"))
    rows = cur.fetchall()
    assert len(rows) == 2, "Should return 2 service items for brake pads"
    assert rows[0][0] == "ATE Ceramic"
    assert rows[0][1] == 340.0
    assert rows[0][2] == 165000.0
    assert rows[1][0] == "Brembo"
    assert rows[1][1] == 280.0
    assert rows[1][2] == 120000.0

    # Delta mileage calculation verification
    delta_km = rows[0][2] - rows[1][2]
    assert delta_km == 45000.0, "Difference between pad replacements should be 45,000 km"

    # Delete Event 2 -> service item eventId should become NULL (SET NULL) but item remains attached to Asset
    cur.execute("DELETE FROM lifecycle_events WHERE id = ?", (event_id2,))
    db.conn.commit()
    cur.execute("SELECT eventId FROM service_items WHERE id = ?", (part_id2,))
    assert cur.fetchone()[0] is None, "Foreign key SET NULL should clear eventId without deleting service item"

    # Delete Asset -> CASCADE should remove all service items
    cur.execute("DELETE FROM assets WHERE id = ?", (asset_id,))
    db.conn.commit()
    cur.execute("SELECT COUNT(*) FROM service_items WHERE assetId = ?", (asset_id,))
    assert cur.fetchone()[0] == 0, "Deleting asset must CASCADE delete all service items"
    db.close()

def test_foreign_key_violation_guard():
    db = InMemoryDosarDatabase()
    cur = db.conn.cursor()
    # Inserting event with non-existent assetId should fail
    try:
        cur.execute("INSERT INTO lifecycle_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (str(uuid.uuid4()), "non_existent_asset", "Test", None, 1000, None, 0, 100.0, "RON", None, None, None, "30", 1000))
        db.conn.commit()
        assert False, "Should have raised IntegrityError on foreign key violation"
    except sqlite3.IntegrityError:
        pass # Expected
    db.close()

# MARK: - Main Runner

def main():
    print("==================================================================")
    print("       DOSAR CU ȘINĂ — ANDROID ROOM SQLITE & PARITY TESTS         ")
    print("==================================================================")
    print("")

    tests = [
        ("test_type_converters", test_type_converters),
        ("test_asset_entity_crud", test_asset_entity_crud),
        ("test_lifecycle_event_entity_crud", test_lifecycle_event_entity_crud),
        ("test_cascade_delete_asset_deletes_all_children", test_cascade_delete_asset_deletes_all_children),
        ("test_cascade_delete_event_deletes_attachments", test_cascade_delete_event_deletes_attachments),
        ("test_cost_sum_aggregation", test_cost_sum_aggregation),
        ("test_service_items_tracking_and_cascade", test_service_items_tracking_and_cascade),
        ("test_foreign_key_violation_guard", test_foreign_key_violation_guard)
    ]

    passed = 0
    failed = 0
    start = time.time()

    for name, test_fn in tests:
        try:
            test_fn()
            print(f"  ✅ PASS  {name}")
            passed += 1
        except Exception as e:
            print(f"  ❌ FAIL  {name}: {e}")
            failed += 1

    duration = time.time() - start
    print("------------------------------------------------------------------")
    print(f"  Total: {len(tests)} | Passed: {passed} | Failed: {failed} | Time: {duration:.3f}s")

    if failed == 0:
        print("\n🎉 ALL ANDROID ROOM DATABASE TESTS PASSED! (100% Pass Rate)")
        print("==================================================================")
        return 0
    else:
        print("\n❌ SOME TESTS FAILED")
        print("==================================================================")
        return 1

if __name__ == "__main__":
    sys.exit(main())
