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
CACHE_DIR="$(mktemp -d /tmp/dosarcusina_cache_XXXXXX)"
BIN_DIR="$(mktemp -d /tmp/dosarcusina_bin_XXXXXX)"
trap "rm -rf '${BIN_DIR}' '${CACHE_DIR}' 2>/dev/null || true" EXIT

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
UNIFIED_RUNNER="${BIN_DIR}/UnifiedTestRunner.swift"

cat << 'EOF' > "${UNIFIED_RUNNER}"
import Foundation

@main
struct UnifiedTestRunner {
    @MainActor
    static func main() async {
        print("==================================================================")
        print("          DOSAR CU ȘINĂ — iOS AUTOMATED TEST SUITES               ")
        print("==================================================================")
        print("")
        
        let startTotal = Date()
        var allResults: [TestSuiteResult] = []
        
        // 1. CadenceCalculatorTests
        print("▶ Running CadenceCalculatorTests...")
        let cadenceResult = CadenceCalculatorTests.runAll()
        allResults.append(cadenceResult)
        printSuiteSummary(cadenceResult)
        
        // 2. RomanianUtilityParserTests
        print("▶ Running RomanianUtilityParserTests...")
        let parserResult = RomanianUtilityParserTests.runAll()
        allResults.append(parserResult)
        printSuiteSummary(parserResult)
        
        // 3. NotificationSchedulerTests
        print("▶ Running NotificationSchedulerTests...")
        let notifResult = NotificationSchedulerTests.runAll()
        allResults.append(notifResult)
        printSuiteSummary(notifResult)
        
        // 4. AdversarialTests
        print("▶ Running AdversarialTests...")
        let adversarialResult = AdversarialTests.runAll()
        allResults.append(adversarialResult)
        printSuiteSummary(adversarialResult)
        
        // 5. ServiceItemAndComponentHistoryTests
        print("▶ Running ServiceItemAndComponentHistoryTests...")
        let serviceItemResult = ServiceItemAndComponentHistoryTests.runAll()
        allResults.append(serviceItemResult)
        printSuiteSummary(serviceItemResult)
        
        // 6. PlatformServicesAndIntegrationTests
        print("▶ Running PlatformServicesAndIntegrationTests...")
        let platformResult = PlatformServicesAndIntegrationTests.runAll()
        allResults.append(platformResult)
        printSuiteSummary(platformResult)
        
        // 7. BiometricVaultTests
        let bioStart = Date()
        let bioScores = await BiometricVaultTests.runAll()
        let bioDuration = Date().timeIntervalSince(bioStart)
        let bioResult = TestSuiteResult(suiteName: "BiometricVaultTests", passed: bioScores.passed, failed: bioScores.failed, failures: [], duration: bioDuration)
        allResults.append(bioResult)
        printSuiteSummary(bioResult)
        
        // 8. MeasurementLogAndDomainTests
        print("▶ Running MeasurementLogAndDomainTests...")
        let m3Result = MeasurementLogAndDomainTests.runAll()
        allResults.append(m3Result)
        printSuiteSummary(m3Result)
        
        // 9. IntakeAndRoutingTests
        print("▶ Running IntakeAndRoutingTests...")
        let intakeResult = IntakeAndRoutingTests.runAll()
        allResults.append(intakeResult)
        printSuiteSummary(intakeResult)
        
        // 10. PDFDossierGeneratorTests
        print("▶ Running PDFDossierGeneratorTests...")
        let pdfResult = PDFDossierGeneratorTests.runAll()
        allResults.append(pdfResult)
        printSuiteSummary(pdfResult)
        
        // 11. DossierArchiveServiceTests
        print("▶ Running DossierArchiveServiceTests...")
        let archiveResult = await DossierArchiveServiceTests.runAll()
        allResults.append(archiveResult)
        printSuiteSummary(archiveResult)
        
        // 12. FinancialPulseCalculatorTests
        print("▶ Running FinancialPulseCalculatorTests...")
        let financialResult = FinancialPulseCalculatorTests.runAll()
        allResults.append(financialResult)
        printSuiteSummary(financialResult)
        
        // 13. M4AdversarialArchiveAnalyticsTests
        print("▶ Running M4AdversarialArchiveAnalyticsTests...")
        let m4AdvResult = await M4AdversarialArchiveAnalyticsTests.runAll()
        allResults.append(m4AdvResult)
        printSuiteSummary(m4AdvResult)
        
        let totalDuration = Date().timeIntervalSince(startTotal)
        let totalPassed = allResults.reduce(0) { $0 + $1.passed }
        let totalFailed = allResults.reduce(0) { $0 + $1.failed }
        let totalTests = totalPassed + totalFailed
        
        print("==================================================================")
        print("                        TEST RESULTS SUMMARY                      ")
        print("==================================================================")
        for res in allResults {
            let status = res.isSuccess ? "✅ PASS" : "❌ FAIL"
            let timeStr = String(format: "%.3fs", res.duration)
            print("  \(status)  \(res.suiteName.padding(toLength: 32, withPad: " ", startingAt: 0)) (\(res.passed)/\(res.total) passed, \(timeStr))")
        }
        print("------------------------------------------------------------------")
        let totalTimeStr = String(format: "%.3fs", totalDuration)
        print("  Total Tests: \(totalTests) | Passed: \(totalPassed) | Failed: \(totalFailed) | Time: \(totalTimeStr)")
        
        if totalFailed > 0 {
            print("\n❌ FAILURES DETECTED:")
            for res in allResults {
                for failure in res.failures {
                    print("  • [\(res.suiteName)] \(failure.testName): \(failure.message)")
                    print("    at \(failure.file):\(failure.line)")
                }
            }
            print("==================================================================")
            exit(1)
        } else {
            print("\n🎉 ALL iOS TESTS PASSED SUCCESSFULLY! (100% Pass Rate)")
            print("==================================================================")
            exit(0)
        }
    }
    
    private static func printSuiteSummary(_ result: TestSuiteResult) {
        if result.isSuccess {
            print("  ✅ All \(result.passed) tests passed in \(String(format: "%.3f", result.duration))s\n")
        } else {
            print("  ❌ \(result.failed) of \(result.total) tests failed in \(String(format: "%.3f", result.duration))s\n")
            for f in result.failures {
                print("     FAIL: \(f.testName) -> \(f.message)")
            }
            print("")
        }
    }
}
EOF

swiftc -module-cache-path "${CACHE_DIR}" -Xfrontend -disable-sandbox -parse-as-library \
  -framework Foundation -framework UserNotifications -framework SwiftData -framework SwiftUI \
  -framework WidgetKit -framework EventKit -framework Contacts -framework LocalAuthentication \
  -framework CryptoKit -framework PDFKit -framework Charts -lz \
  "${REPO_ROOT}/ios/DosarCuSina/Services/Cadence/CadenceCalculator.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/OCR/RomanianUtilityParser.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/LocalOCRService.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/Notifications/NotificationScheduler.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/RomanianProviders.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/Calendar/CalendarSyncService.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/Sync/WidgetDataSyncService.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/Security/BiometricVaultManager.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/PDF/PDFDossierGenerator.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/Archive/DosarZipEngine.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/Archive/DossierArchiveModels.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/Archive/DossierArchiveService.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Services/Analytics/FinancialPulseCalculator.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Views/Components/ContactPickerButton.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/StarterTemplate.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/AssetCategory.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/DynamicField.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/DocumentAttachment.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/ServiceItem.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/MeasurementLog.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/Asset.swift" \
  "${REPO_ROOT}/ios/DosarCuSina/Models/LifecycleEvent.swift" \
  "${REPO_ROOT}/ios/DosarCuSinaWidgets/WidgetDataProvider.swift" \
  "${TESTS_DIR}/ios/TestHarness.swift" \
  "${TESTS_DIR}/ios/CadenceCalculatorTests.swift" \
  "${TESTS_DIR}/ios/RomanianUtilityParserTests.swift" \
  "${TESTS_DIR}/ios/NotificationSchedulerTests.swift" \
  "${TESTS_DIR}/ios/AdversarialTests.swift" \
  "${TESTS_DIR}/ios/ServiceItemAndComponentHistoryTests.swift" \
  "${TESTS_DIR}/ios/PlatformServicesAndIntegrationTests.swift" \
  "${TESTS_DIR}/ios/BiometricVaultTests.swift" \
  "${TESTS_DIR}/ios/MeasurementLogAndDomainTests.swift" \
  "${TESTS_DIR}/ios/IntakeAndRoutingTests.swift" \
  "${TESTS_DIR}/ios/PDFDossierGeneratorTests.swift" \
  "${TESTS_DIR}/ios/DossierArchiveServiceTests.swift" \
  "${TESTS_DIR}/ios/FinancialPulseCalculatorTests.swift" \
  "${TESTS_DIR}/ios/M4AdversarialArchiveAnalyticsTests.swift" \
  "${UNIFIED_RUNNER}" \
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
