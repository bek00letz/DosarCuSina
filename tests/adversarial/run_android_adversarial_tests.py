#!/usr/bin/env python3
"""
Empirical Adversarial Stress Harness for Android CadenceCalculator & RomanianUtilityParser.
Executes against exact Kotlin implementation logic and regex specifications.
"""

import math
import re
import sys
from datetime import datetime, timezone

total_tests = 0
passed_tests = 0
failed_tests = 0

def assert_test(condition, name):
    global total_tests, passed_tests, failed_tests
    total_tests += 1
    if condition:
        passed_tests += 1
        print(f"  \033[32m✔ PASS\033[0m [{total_tests}] {name}")
    else:
        failed_tests += 1
        print(f"  \033[31m✘ FAIL\033[0m [{total_tests}] {name}")

# MARK: - Android CadenceCalculator Emulation

class AndroidCadenceCalculator:
    @staticmethod
    def is_leap_year(year: int) -> bool:
        return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

    @staticmethod
    def calculate_next_due_date_days(from_timestamp_ms: int, cadence_days: int) -> int:
        # Java Calendar.add(Calendar.DAY_OF_YEAR, cadenceDays)
        # 1 day = 86_400_000 ms
        return from_timestamp_ms + cadence_days * 86_400_000

    @staticmethod
    def add_years_calendar(from_timestamp_ms: int, years: int) -> int:
        dt = datetime.fromtimestamp(from_timestamp_ms / 1000.0, tz=timezone.utc)
        target_year = dt.year + years
        # Java Calendar: if Feb 29 and target is non-leap, clamps to Feb 28
        target_month = dt.month
        target_day = dt.day
        if target_month == 2 and target_day == 29 and not AndroidCadenceCalculator.is_leap_year(target_year):
            target_day = 28
        res = dt.replace(year=target_year, month=target_month, day=target_day)
        return int(res.timestamp() * 1000)

    @staticmethod
    def project_telemetry_due_date(current_metric: float, target_metric: float, history: list, current_timestamp: int):
        remaining_metric = target_metric - current_metric
        if remaining_metric <= 0:
            return current_timestamp
        if len(history) < 2:
            return None

        sorted_h = sorted(history, key=lambda x: x[0])
        first = sorted_h[0]
        last = sorted_h[-1]

        delta_metric = last[1] - first[1]
        delta_days = (last[0] - first[0]) / (1000.0 * 60 * 60 * 24)

        if delta_days <= 0.0 or delta_metric <= 0.0:
            return None

        daily_burn_rate = delta_metric / delta_days
        estimated_days = round(remaining_metric / daily_burn_rate)

        return current_timestamp + (estimated_days * 86_400_000)

# MARK: - Android RomanianUtilityParser Emulation

class AndroidRomanianUtilityParser:
    PROVIDERS = {
        "DIGI": re.compile(r"\b(DIGI|RCS\s*&\s*RDS|RCS\s*RDS)\b", re.IGNORECASE),
        "PPC": re.compile(r"\b(PPC|ENEL|PPC\s+ENERGIE)\b", re.IGNORECASE),
        "HIDROELECTRICA": re.compile(r"\b(HIDROELECTRICA|SPEEH\s+HIDROELECTRICA)\b", re.IGNORECASE),
        "EON": re.compile(r"\b(E\.ON|EON)\b", re.IGNORECASE),
        "ENGIE": re.compile(r"\b(ENGIE|ENGIE\s+ROMANIA)\b", re.IGNORECASE),
        "ORANGE": re.compile(r"\b(ORANGE|ORANGE\s+ROMANIA)\b", re.IGNORECASE),
        "VODAFONE": re.compile(r"\b(VODAFONE|VODAFONE\s+ROMANIA)\b", re.IGNORECASE),
    }

    DIGI_CLIENT_CODE = re.compile(r"Cod\s+client[:\s]+([0-9]{7,10})", re.IGNORECASE)
    DIGI_DUE_DATE = re.compile(r"(?:Data\s+scadent[aă]|Scadent[aă])[:\s]+([0-9]{2}[./-][0-9]{2}[./-][0-9]{4})", re.IGNORECASE)
    DIGI_TOTAL = re.compile(r"Total\s+de\s+plat[aă][:\s]+([0-9.,]+)\s*(?:LEI|RON)", re.IGNORECASE)

    HIDRO_CLIENT_CODE = re.compile(r"Cod\s+client[:\s]+([0-9]{6,10})", re.IGNORECASE)
    HIDRO_TOTAL = re.compile(r"Total\s+de\s+achitat[:\s]+([0-9.,]+)\s*(?:LEI|RON)", re.IGNORECASE)
    # Note: No 1.8.0 or meter index pattern in Android parser!

    GENERIC_DATE = re.compile(r"(?:Data(?:\s+scadent[aă])?|Scaden[tț][aă])?[:\s]*\b(0?[1-9]|[12][0-9]|3[01])[./-](0?[1-9]|1[0-2])[./-](20[2-9][0-9])\b", re.IGNORECASE)
    GENERIC_TOTAL = re.compile(r"(?:Total|Suma|Achitat|Plat[aă])[:\s]+([0-9.,]+)\s*(?:LEI|RON)", re.IGNORECASE)

    @classmethod
    def identify(cls, text: str) -> str:
        for prov, pattern in cls.PROVIDERS.items():
            if pattern.search(text):
                return prov
        return "UNKNOWN"

    @classmethod
    def parse_amount(cls, raw: str) -> float:
        s = raw.strip()
        s = re.sub(r"(?i)LEI", "", s).replace("RON", "").strip()
        if "," in s and "." in s:
            s = s.replace(".", "").replace(",", ".")
        elif "," in s:
            s = s.replace(",", ".")
        try:
            return float(s)
        except ValueError:
            return None

# MARK: - SUITE: ANDROID ADVERSARIAL STRESS TESTS

def run_android_adversarial_suite():
    print("\n\033[1m=== ANDROID CADENCE & OCR ADVERSARIAL STRESS SUITE ===\033[0m")

    # 1. Leap year identification
    assert_test(AndroidCadenceCalculator.is_leap_year(2000), "Android isLeapYear(2000) is True")
    assert_test(AndroidCadenceCalculator.is_leap_year(2024), "Android isLeapYear(2024) is True")
    assert_test(AndroidCadenceCalculator.is_leap_year(2400), "Android isLeapYear(2400) is True")
    assert_test(not AndroidCadenceCalculator.is_leap_year(1900), "Android isLeapYear(1900) is False")
    assert_test(not AndroidCadenceCalculator.is_leap_year(2100), "Android isLeapYear(2100) is False")
    assert_test(not AndroidCadenceCalculator.is_leap_year(2025), "Android isLeapYear(2025) is False")

    # 2. Leap year annual rollover Feb 29, 2024 + 1 to 5 years via addYears
    feb29_2024_ms = int(datetime(2024, 2, 29, 12, 0, tzinfo=timezone.utc).timestamp() * 1000)
    
    p1 = AndroidCadenceCalculator.add_years_calendar(feb29_2024_ms, 1)
    d1 = datetime.fromtimestamp(p1 / 1000.0, tz=timezone.utc)
    assert_test(d1.year == 2025 and d1.month == 2 and d1.day == 28, f"Feb 29, 2024 + 1 year = 2025-02-28 (got {d1.strftime('%Y-%m-%d')})")

    p4 = AndroidCadenceCalculator.add_years_calendar(feb29_2024_ms, 4)
    d4 = datetime.fromtimestamp(p4 / 1000.0, tz=timezone.utc)
    assert_test(d4.year == 2028 and d4.month == 2 and d4.day == 29, f"Feb 29, 2024 + 4 years = 2028-02-29 (got {d4.strftime('%Y-%m-%d')})")

    # 3. BUT test calculateNextDueDate with cadenceDays = 365 vs 366 (annual heuristic missing in Android):
    next_365 = AndroidCadenceCalculator.calculate_next_due_date_days(feb29_2024_ms, 365)
    d_365 = datetime.fromtimestamp(next_365 / 1000.0, tz=timezone.utc)
    # In 2024 (366-day leap year), adding 365 days lands on Feb 28, 2025
    assert_test(d_365.year == 2025 and d_365.month == 2 and d_365.day == 28, f"cadenceDays 365 lands on {d_365.strftime('%Y-%m-%d')}")

    # Adding 366 days in Android:
    next_366 = AndroidCadenceCalculator.calculate_next_due_date_days(feb29_2024_ms, 366)
    d_366 = datetime.fromtimestamp(next_366 / 1000.0, tz=timezone.utc)
    # Adversarial check: iOS treats 366 as annual recurrence heuristic (Feb 28). Does Android?
    # In Android it lands on March 1!
    print(f"  [INFO] Android cadenceDays 366 from Feb 29, 2024 lands on: {d_366.strftime('%Y-%m-%d')}")
    assert_test(d_366.month == 2 and d_366.day == 28, f"Android cadenceDays 366 preserves Feb 28 anniversary (got {d_366.strftime('%Y-%m-%d')})")

    # 4. Telemetry projection: Rollback between intermediate points
    now = 1700000000000
    intermittent_rollback = [
        (now, 100000.0),
        (now + 10 * 86400000, 110000.0),
        (now + 20 * 86400000, 105000.0), # Rollback!
        (now + 30 * 86400000, 112000.0)  # Overall delta is +12,000, but intermediate rollback occurred
    ]
    proj_rollback = AndroidCadenceCalculator.project_telemetry_due_date(
        current_metric=112000.0,
        target_metric=120000.0,
        history=intermittent_rollback,
        current_timestamp=now + 30 * 86400000
    )
    # In Android, it compares ONLY first and last!
    # If first < last, Android blindly computes burn rate and does NOT detect rollback anomaly!
    assert_test(proj_rollback is None, f"Android detects intermediate odometer rollback (got {proj_rollback})")

    # 5. Telemetry projection: Fractional day rounding to 0
    # remainingMetric = 10 km, burnRate = 100 km/day -> remaining / rate = 0.1 days
    rapid_burn_history = [
        (now, 10000.0),
        (now + 1 * 86400000, 10100.0) # 100 km / day
    ]
    proj_fractional = AndroidCadenceCalculator.project_telemetry_due_date(
        current_metric=10100.0,
        target_metric=10110.0, # 10 km remaining
        history=rapid_burn_history,
        current_timestamp=now + 1 * 86400000
    )
    # In Android: round(0.1) == 0 -> returns current_timestamp!
    # Target is not exceeded, but returned current_timestamp (0 days remaining)
    expected_future = now + 1 * 86400000 + 86400000 # at least 1 day in future
    assert_test(proj_fractional > (now + 1 * 86400000), f"Android guards against 0-day rounding for unexceeded target (got diff {(proj_fractional - (now + 86400000))/86400000} days)")

    # 6. OCR: Hidroelectrica active energy (1.8.0)
    hidro_text = """
    SPEEH HIDROELECTRICA S.A.
    Cod client: 748291
    Factura nr: 2026094812
    1.8.0 Energie activa: 4892.5
    Data scadenta: 25.11.2026
    Total de achitat: 395,20 LEI
    """
    prov = AndroidRomanianUtilityParser.identify(hidro_text)
    assert_test(prov == "HIDROELECTRICA", f"Android identifies HIDROELECTRICA (got {prov})")
    # Does Android parse 1.8.0 meter index? In Android code, meterIndex is NEVER parsed for Hidroelectrica!
    has_hidro_meter_regex = hasattr(AndroidRomanianUtilityParser, "HIDRO_ACTIVE_ENERGY") or "1.8.0" in hidro_text
    # Check Android implementation in source:
    with open("android/app/src/main/java/com/dosarcusina/ocr/RomanianUtilityParser.kt") as f:
        src = f.read()
    assert_test("1.8.0" in src, "Android RomanianUtilityParser.kt extracts 1.8.0 active energy index")

    # 7. OCR: Written month names (e.g. 15 noiembrie 2026)
    written_date_text = "Data scadenta: 15 noiembrie 2026"
    m_written = AndroidRomanianUtilityParser.DIGI_DUE_DATE.search(written_date_text) or AndroidRomanianUtilityParser.GENERIC_DATE.search(written_date_text)
    assert_test(m_written is not None, f"Android regex parses written Romanian month names (got {m_written})")

    # 8. Single digit day/month: "5.5.2026"
    single_digit_date = "Scadenta: 5.5.2026 Total de plata: 100 LEI"
    m_single = AndroidRomanianUtilityParser.DIGI_DUE_DATE.search(single_digit_date)
    assert_test(m_single is not None, f"Android DIGI_DUE_DATE regex matches single-digit day/month '5.5.2026' (got {m_single})")

    # 9. Amount with space thousand separator: "14 502,30 LEI"
    amt_space = AndroidRomanianUtilityParser.parse_amount("14 502,30 LEI")
    assert_test(amt_space == 14502.30, f"Android parses amount with space separator '14 502,30 LEI' (got {amt_space})")

    print(f"\nRESULTS: Total: {total_tests} | Passed: {passed_tests} | Failed: {failed_tests}")

if __name__ == "__main__":
    run_android_adversarial_suite()
