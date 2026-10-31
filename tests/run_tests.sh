#!/usr/bin/env bash
# ==============================================================================
#  Dosar cu Șină — Comprehensive Automated Test Suite Runner
#  Adheres to the Apple Craftsmanship & Polish Standard
# ==============================================================================
set -euo pipefail

# Text Formatting
BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
CYAN="\033[36m"
YELLOW="\033[33m"
RESET="\033[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="${REPO_ROOT}/tests"
CACHE_DIR="/tmp/dosarcusina_swift_cache"
BIN_DIR="${TESTS_DIR}/.bin"
mkdir -p "${CACHE_DIR}" "${BIN_DIR}"
trap "rm -rf '${BIN_DIR}' '${CACHE_DIR}'" EXIT

echo -e "${BOLD}${CYAN}==================================================================${RESET}"
echo -e "${BOLD}${CYAN}      DOSAR CU ȘINĂ — AUTOMATED MULTI-PLATFORM TEST RUNNER        ${RESET}"
echo -e "${BOLD}${CYAN}==================================================================${RESET}"
echo -e "Workspace: ${REPO_ROOT}"
echo -e "Date:      $(date -u +"%Y-%m-%dT%H:%M:%SZ")\n"

# ------------------------------------------------------------------------------
# 1. Compile & Execute iOS Swift Test Suites
# ------------------------------------------------------------------------------
echo -e "${BOLD}▶ [1/2] Compiling & Running iOS Swift Test Suites...${RESET}"
IOS_TEST_BIN="${BIN_DIR}/ios_tests"

swiftc -module-cache-path "${CACHE_DIR}" -Xfrontend -disable-sandbox -parse-as-library \
  -framework Foundation -framework UserNotifications -framework SwiftData -framework SwiftUI -framework WidgetKit \
  "${REPO_ROOT}/ios/DosarCuSina/Services/Cadence/CadenceCalculator.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/OCR/RomanianUtilityParser.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/LocalOCRService.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/Notifications/NotificationScheduler.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/AssetCategory.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/DynamicField.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/DocumentAttachment.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/Asset.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/LifecycleEvent.swift" \
  "${REPO_ROOT}/ios/DosarCuSinaWidgets/WidgetDataProvider.swift" \
  "${TESTS_DIR}/ios/TestHarness.swift" \
  "${TESTS_DIR}/ios/CadenceCalculatorTests.swift" \
  "${TESTS_DIR}/ios/RomanianUtilityParserTests.swift" \
  "${TESTS_DIR}/ios/NotificationSchedulerTests.swift" \
  "${TESTS_DIR}/ios/AdversarialTests.swift" \
  "${TESTS_DIR}/ios/TestRunner.swift" \
  -o "${IOS_TEST_BIN}"

# Execute iOS tests
"${IOS_TEST_BIN}"
echo ""

# ------------------------------------------------------------------------------
# 2. Execute Android Room SQLite & Data Mapping Test Suite
# ------------------------------------------------------------------------------
echo -e "${BOLD}▶ [2/2] Running Android Room SQLite & Parity Test Suite...${RESET}"
python3 "${TESTS_DIR}/android/run_room_tests.py"
python3 "${TESTS_DIR}/android/adversarial_room_stress_test.py"
echo ""

# ------------------------------------------------------------------------------
# Final Verification
# ------------------------------------------------------------------------------
echo -e "${BOLD}${GREEN}==================================================================${RESET}"
echo -e "${BOLD}${GREEN}        🎉 ALL MULTI-PLATFORM TEST SUITES PASSED (100%)           ${RESET}"
echo -e "${BOLD}${GREEN}==================================================================${RESET}"
exit 0
