import Foundation

@main
struct TestRunner {
    static func main() {
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
        
        // 4. AdversarialTests (Empirical Notification, Widget & Concentric Geometry Tests)
        print("▶ Running AdversarialTests...")
        let adversarialResult = AdversarialTests.runAll()
        allResults.append(adversarialResult)
        printSuiteSummary(adversarialResult)
        
        // 5. ServiceItemAndComponentHistoryTests (Granular Parts, Delta Km/Cost, Romanian Insurance)
        print("▶ Running ServiceItemAndComponentHistoryTests...")
        let serviceItemResult = ServiceItemAndComponentHistoryTests.runAll()
        allResults.append(serviceItemResult)
        printSuiteSummary(serviceItemResult)
        
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
