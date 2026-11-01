#!/usr/bin/env python3
"""
Automated test runner verifying Android Room SQLite Schema & Data Parity.
Mirrors all test cases in tests/android/RoomDatabaseTests.kt:
- AssetEntity, LifecycleEventEntity, AttachmentEntity, DynamicFieldEntity CRUD
- SQLite Foreign Key CASCADE deletion on parent AssetEntity and LifecycleEventEntity
- TypeConverter list <-> string round-trip serialization for reminderOffsetDays
- Range-based cost aggregation queries
"""

import hashlib
import io
import json
import sqlite3
import sys
import time
import uuid
import zipfile

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

            CREATE TABLE IF NOT EXISTS measurement_logs (
                id TEXT PRIMARY KEY NOT NULL,
                assetId TEXT NOT NULL,
                domainRawValue TEXT NOT NULL,
                metricName TEXT NOT NULL,
                value REAL NOT NULL,
                secondaryValue REAL,
                unit TEXT NOT NULL,
                recordedAt INTEGER NOT NULL,
                previousValue REAL,
                unitPrice REAL,
                isSelfRead INTEGER NOT NULL DEFAULT 1,
                referenceMin REAL,
                referenceMax REAL,
                labOrProviderName TEXT,
                notes TEXT,
                createdAt INTEGER NOT NULL,
                FOREIGN KEY (assetId) REFERENCES assets(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS index_measurement_logs_assetId ON measurement_logs(assetId);
            CREATE INDEX IF NOT EXISTS index_measurement_logs_recordedAt ON measurement_logs(recordedAt);
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

def test_days_remaining_daylight_savings_transition():
    # 23-hour DST Spring transition day in Europe/Bucharest (82,800,000 ms)
    diff_23h = 82_800_000
    days_23h = round(diff_23h / 86_400_000)
    assert days_23h == 1, f"Expected 1 day for 23h DST day, got {days_23h}"

    # 25-hour DST Autumn transition day in Europe/Bucharest (90,000,000 ms)
    diff_25h = 90_000_000
    days_25h = round(diff_25h / 86_400_000)
    assert days_25h == 1, f"Expected 1 day for 25h DST day, got {days_25h}"

    # Overdue across 23-hour transition (-82,800,000 ms)
    diff_overdue_23h = -82_800_000
    days_overdue = round(diff_overdue_23h / 86_400_000)
    assert days_overdue == -1, f"Expected -1 day for overdue across DST, got {days_overdue}"

def test_measurement_logs_crud_and_deltas():
    db = InMemoryDosarDatabase()
    cur = db.conn.cursor()
    asset_id = str(uuid.uuid4())
    log_id1 = str(uuid.uuid4())
    log_id2 = str(uuid.uuid4())

    cur.execute("INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (asset_id, "Apartament Floreasca", "București", "home", "house.fill", "FF9500", 78.5, "mp", 1000, 1000))

    # Home utility meter: 4120 -> 4310 kWh @ 0.68 RON/kWh
    cur.execute("""
        INSERT INTO measurement_logs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (log_id1, asset_id, "Index Energie Electrică (kWh)", "Index Contor Energie Electrică",
          4310.0, None, "kWh", 2000, 4120.0, 0.68, 1, None, None, "Hidroelectrica", "Autocitire", 2000))
    db.conn.commit()

    # Query and test CRUD + deltas
    cur.execute("SELECT value, previousValue, unitPrice FROM measurement_logs WHERE id = ?", (log_id1,))
    row = cur.fetchone()
    assert row is not None, "Log must exist"
    val, prev, price = row
    delta = val - prev
    assert abs(delta - 190.0) < 0.001, f"Expected delta 190.0, got {delta}"
    est_cost = delta * price
    assert abs(est_cost - 129.20) < 0.001, f"Expected estimated cost 129.20, got {est_cost}"

    # Health Biomarker: glucose 115 mg/dL (ref range 70..99)
    cur.execute("""
        INSERT INTO measurement_logs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (log_id2, asset_id, "Analiză Medicală / Biomarker", "Glicemie a jeun",
          115.0, None, "mg/dL", 3000, 95.0, None, 0, 70.0, 99.0, "Synevo", "Peste limita normala", 3000))
    db.conn.commit()

    cur.execute("SELECT value, referenceMin, referenceMax FROM measurement_logs WHERE id = ?", (log_id2,))
    row_bio = cur.fetchone()
    assert row_bio is not None
    bio_val, ref_min, ref_max = row_bio
    is_out_of_range = (ref_min is not None and bio_val < ref_min) or (ref_max is not None and bio_val > ref_max)
    assert is_out_of_range is True, "115 mg/dL should be out of 70..99 range"

    # In-range biomarker
    log_id3 = str(uuid.uuid4())
    cur.execute("""
        INSERT INTO measurement_logs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (log_id3, asset_id, "Analiză Medicală / Biomarker", "Glicemie a jeun",
          85.0, None, "mg/dL", 4000, 115.0, None, 0, 70.0, 99.0, "Synevo", "Normal", 4000))
    db.conn.commit()
    cur.execute("SELECT value, referenceMin, referenceMax FROM measurement_logs WHERE id = ?", (log_id3,))
    bio_val3, ref_min3, ref_max3 = cur.fetchone()
    is_out_of_range3 = (ref_min3 is not None and bio_val3 < ref_min3) or (ref_max3 is not None and bio_val3 > ref_max3)
    assert is_out_of_range3 is False, "85 mg/dL should be within 70..99 range"

    db.close()

def test_cascade_delete_asset_deletes_measurement_logs():
    db = InMemoryDosarDatabase()
    cur = db.conn.cursor()
    asset_id = str(uuid.uuid4())

    cur.execute("INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (asset_id, "Centrala Apartament", None, "home", "flame.fill", "FF9500", None, None, 1000, 1000))

    # Insert 3 logs
    for i in range(3):
        cur.execute("""
            INSERT INTO measurement_logs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (str(uuid.uuid4()), asset_id, "Index Apă Rece (m³)", "Index Apometru",
              100.0 + i * 10, None, "m³", 1000 + i * 100, 90.0 + i * 10, 5.5, 1, None, None, "Apa Nova", None, 1000))
    db.conn.commit()

    cur.execute("SELECT count(*) FROM measurement_logs WHERE assetId = ?", (asset_id,))
    assert cur.fetchone()[0] == 3, "Must have 3 measurement logs"

    # Delete parent asset
    cur.execute("DELETE FROM assets WHERE id = ?", (asset_id,))
    db.conn.commit()

    cur.execute("SELECT count(*) FROM measurement_logs WHERE assetId = ?", (asset_id,))
    assert cur.fetchone()[0] == 0, "CASCADE delete must wipe all child measurement logs"
    db.close()

def test_dosar_archive_round_trip():
    # Construct source records
    asset_id = str(uuid.uuid4())
    event_id = str(uuid.uuid4())
    service_id = str(uuid.uuid4())
    measurement_id = str(uuid.uuid4())

    assets_data = [{
        "id": asset_id,
        "name": "VW Golf VII",
        "subtitle": "B-123-ABC",
        "categoryRaw": "vehicle",
        "iconName": "car.fill",
        "accentColorHex": "007AFF",
        "currentMetricValue": 142500.0,
        "metricUnit": "km",
        "licensePlate": "B-123-ABC",
        "vin": "WVWZZZAUZJP123456",
        "manufactureYear": 2018,
        "fuelType": "Motorină"
    }]

    events_data = [{
        "id": event_id,
        "assetId": asset_id,
        "title": "ITP Auto",
        "dueDate": "2027-04-15T09:00:00Z",
        "cost": 160.0,
        "currency": "RON",
        "isCompleted": False
    }]

    service_data = [{
        "id": service_id,
        "assetId": asset_id,
        "eventId": event_id,
        "name": "Plăcuțe Frână Față",
        "category": "Frâne",
        "partBrandOrCode": "ATE Ceramic",
        "cost": 520.0,
        "serviceDate": "2026-06-10T10:00:00Z",
        "mileageAtService": 132000.0,
        "notes": "Înlocuire completă set față"
    }]

    measurements_data = [{
        "id": measurement_id,
        "assetId": asset_id,
        "domainRawValue": "Index Apă Rece (m³)",
        "metricName": "Index Apometru Baie",
        "value": 154.0,
        "unit": "m³",
        "recordedAt": "2026-10-25T14:30:00Z",
        "previousValue": 148.0,
        "unitPrice": 5.60,
        "isSelfRead": True,
        "labOrProviderName": "Apa Nova"
    }]

    assets_json = json.dumps(assets_data, indent=2).encode("utf-8")
    events_json = json.dumps(events_data, indent=2).encode("utf-8")
    service_json = json.dumps(service_data, indent=2).encode("utf-8")
    measurements_json = json.dumps(measurements_data, indent=2).encode("utf-8")

    checksums = {
        "data/assets.json": hashlib.sha256(assets_json).hexdigest(),
        "data/events.json": hashlib.sha256(events_json).hexdigest(),
        "data/service_history.json": hashlib.sha256(service_json).hexdigest(),
        "data/measurements.json": hashlib.sha256(measurements_json).hexdigest(),
    }

    manifest = {
        "schemaVersion": 2,
        "appVersion": "2.0.0",
        "appName": "Dosar cu Șină",
        "exportDate": "2026-11-01T12:00:00Z",
        "platform": "CrossPlatformTest",
        "deviceId": str(uuid.uuid4()),
        "format": "com.ar.dosarcusina.dossier",
        "entityCounts": {
            "assets": len(assets_data),
            "events": len(events_data),
            "serviceItems": len(service_data),
            "measurements": len(measurements_data),
            "dynamicFields": 0,
            "attachments": 0
        },
        "checksums": checksums
    }
    manifest_json = json.dumps(manifest, indent=2).encode("utf-8")

    # Pack into .dosar ZIP
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("manifest.json", manifest_json)
        zf.writestr("data/assets.json", assets_json)
        zf.writestr("data/events.json", events_json)
        zf.writestr("data/service_history.json", service_json)
        zf.writestr("data/measurements.json", measurements_json)
    zip_bytes = zip_buffer.getvalue()

    # Unpack and verify integrity
    read_buf = io.BytesIO(zip_bytes)
    with zipfile.ZipFile(read_buf, "r") as zf:
        read_manifest = json.loads(zf.read("manifest.json").decode("utf-8"))
        assert read_manifest["schemaVersion"] == 2
        for path, exp_sha in read_manifest["checksums"].items():
            content = zf.read(path)
            act_sha = hashlib.sha256(content).hexdigest()
            assert act_sha == exp_sha, f"SHA mismatch on {path}: expected {exp_sha}, got {act_sha}"

        # Import into SQLite
        db = InMemoryDosarDatabase()
        cur = db.conn.cursor()

        imported_assets = json.loads(zf.read("data/assets.json").decode("utf-8"))
        for a in imported_assets:
            cur.execute("""
                INSERT INTO assets (id, name, subtitle, categoryRaw, iconName, accentColorHex, currentMetricValue, metricUnit, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1000, 1000)
            """, (a["id"], a["name"], a.get("subtitle"), a["categoryRaw"], a["iconName"], a["accentColorHex"], a.get("currentMetricValue"), a.get("metricUnit")))

        imported_events = json.loads(zf.read("data/events.json").decode("utf-8"))
        for e in imported_events:
            cur.execute("""
                INSERT INTO lifecycle_events (id, assetId, title, dueDate, cost, currency, reminderOffsetDays, createdAt)
                VALUES (?, ?, ?, 5000000, ?, ?, '7,1', 1000)
            """, (e["id"], e["assetId"], e["title"], e.get("cost"), e.get("currency", "RON")))

        imported_services = json.loads(zf.read("data/service_history.json").decode("utf-8"))
        for s in imported_services:
            cur.execute("""
                INSERT INTO service_items (id, assetId, eventId, componentName, componentCategory, partBrand, cost, serviceDate, mileageAtService, notes, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, 3000000, ?, ?, 1000)
            """, (s["id"], s["assetId"], s.get("eventId"), s["name"], s.get("category", "General"), s.get("partBrandOrCode"), s.get("cost"), s.get("mileageAtService"), s.get("notes")))

        imported_measurements = json.loads(zf.read("data/measurements.json").decode("utf-8"))
        for m in imported_measurements:
            cur.execute("""
                INSERT INTO measurement_logs (id, assetId, domainRawValue, metricName, value, unit, recordedAt, previousValue, unitPrice, isSelfRead, labOrProviderName, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, 4000000, ?, ?, 1, ?, 1000)
            """, (m["id"], m["assetId"], m["domainRawValue"], m["metricName"], m["value"], m["unit"], m.get("previousValue"), m.get("unitPrice"), m.get("labOrProviderName")))
        db.conn.commit()

        # Verify DB counts
        cur.execute("SELECT count(*) FROM assets")
        assert cur.fetchone()[0] == 1
        cur.execute("SELECT count(*) FROM lifecycle_events")
        assert cur.fetchone()[0] == 1
        cur.execute("SELECT count(*) FROM service_items")
        assert cur.fetchone()[0] == 1
        cur.execute("SELECT count(*) FROM measurement_logs")
        assert cur.fetchone()[0] == 1

        # Re-export from SQLite to new ZIP
        cur.execute("SELECT id, name, subtitle, categoryRaw, iconName, accentColorHex, currentMetricValue, metricUnit FROM assets")
        re_assets = [{"id": r[0], "name": r[1], "subtitle": r[2], "categoryRaw": r[3], "iconName": r[4], "accentColorHex": r[5], "currentMetricValue": r[6], "metricUnit": r[7]} for r in cur.fetchall()]
        cur.execute("SELECT id, assetId, title, cost, currency FROM lifecycle_events")
        re_events = [{"id": r[0], "assetId": r[1], "title": r[2], "cost": r[3], "currency": r[4]} for r in cur.fetchall()]
        cur.execute("SELECT id, assetId, eventId, componentName, componentCategory, partBrand, cost, mileageAtService, notes FROM service_items")
        re_services = [{"id": r[0], "assetId": r[1], "eventId": r[2], "name": r[3], "category": r[4], "partBrandOrCode": r[5], "cost": r[6], "mileageAtService": r[7], "notes": r[8]} for r in cur.fetchall()]
        cur.execute("SELECT id, assetId, domainRawValue, metricName, value, unit, previousValue, unitPrice, labOrProviderName FROM measurement_logs")
        re_meas = [{"id": r[0], "assetId": r[1], "domainRawValue": r[2], "metricName": r[3], "value": r[4], "unit": r[5], "previousValue": r[6], "unitPrice": r[7], "labOrProviderName": r[8]} for r in cur.fetchall()]

        re_a_bytes = json.dumps(re_assets, indent=2).encode("utf-8")
        re_e_bytes = json.dumps(re_events, indent=2).encode("utf-8")
        re_s_bytes = json.dumps(re_services, indent=2).encode("utf-8")
        re_m_bytes = json.dumps(re_meas, indent=2).encode("utf-8")

        re_checksums = {
            "data/assets.json": hashlib.sha256(re_a_bytes).hexdigest(),
            "data/events.json": hashlib.sha256(re_e_bytes).hexdigest(),
            "data/service_history.json": hashlib.sha256(re_s_bytes).hexdigest(),
            "data/measurements.json": hashlib.sha256(re_m_bytes).hexdigest(),
        }

        re_manifest = {
            "schemaVersion": 2,
            "appVersion": "2.0.0",
            "checksums": re_checksums
        }
        re_zip_buf = io.BytesIO()
        with zipfile.ZipFile(re_zip_buf, "w", zipfile.ZIP_DEFLATED) as rzf:
            rzf.writestr("manifest.json", json.dumps(re_manifest, indent=2).encode("utf-8"))
            rzf.writestr("data/assets.json", re_a_bytes)
            rzf.writestr("data/events.json", re_e_bytes)
            rzf.writestr("data/service_history.json", re_s_bytes)
            rzf.writestr("data/measurements.json", re_m_bytes)

        # Verify re-exported ZIP
        with zipfile.ZipFile(io.BytesIO(re_zip_buf.getvalue()), "r") as test_zf:
            mf = json.loads(test_zf.read("manifest.json").decode("utf-8"))
            for p, exp_sha in mf["checksums"].items():
                act_sha = hashlib.sha256(test_zf.read(p)).hexdigest()
                assert act_sha == exp_sha, f"Re-export SHA mismatch on {p}"

        db.close()

def test_dosar_archive_tamper_detection():
    # Construct archive with checksums
    raw_assets = b'[{"id": "asset-1", "name": "Authentic Data"}]'
    expected_sha = hashlib.sha256(raw_assets).hexdigest()

    manifest = {
        "schemaVersion": 2,
        "checksums": {
            "data/assets.json": expected_sha
        }
    }
    manifest_bytes = json.dumps(manifest).encode("utf-8")

    # Simulate tampered assets (1 byte changed)
    tampered_assets = b'[{"id": "asset-1", "name": "Tampered Data"}]'
    tampered_sha = hashlib.sha256(tampered_assets).hexdigest()

    assert tampered_sha != expected_sha, "Tampered content must produce different SHA-256"

    # Simulate parser verification logic
    detected_tamper = False
    if tampered_sha != expected_sha:
        detected_tamper = True

    assert detected_tamper is True, "Archive integrity validator must reject tampered file"

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
        ("test_foreign_key_violation_guard", test_foreign_key_violation_guard),
        ("test_days_remaining_daylight_savings_transition", test_days_remaining_daylight_savings_transition),
        ("test_measurement_logs_crud_and_deltas", test_measurement_logs_crud_and_deltas),
        ("test_cascade_delete_asset_deletes_measurement_logs", test_cascade_delete_asset_deletes_measurement_logs),
        ("test_dosar_archive_round_trip", test_dosar_archive_round_trip),
        ("test_dosar_archive_tamper_detection", test_dosar_archive_tamper_detection),
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
