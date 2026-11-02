import Foundation

var failures = 0
var tests = 0
struct TestFailure: Error {}
func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { failures += 1; print("FAIL \(file):\(line)") }
}
func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { expectTrue(!value, file: file, line: line) }
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { failures += 1; print("FAIL \(file):\(line): expected \(expected), got \(actual)") }
}
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { expectTrue(value == nil, file: file, line: line) }
func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw TestFailure() }; return value }
func test(_ name: String, _ body: () throws -> Void) {
    tests += 1
    let before = failures
    do { try body() } catch { failures += 1; print("FAIL \(name): \(error)") }
    print("\(before == failures ? "PASS" : "FAIL") \(name)")
}
let suite = CompletionTests()
test("exact placeholder background color", testUniformBackgroundPreservesExactColor)
test("reject ambiguous placeholder backgrounds", testAmbiguousBackgroundIsNotReplacedWithAnAverage)
test("placeholder mask stays inside input", testMaskStaysInsideTheInputAndCoversThePlaceholderLine)
test("rendered mask exact pixels and caret at 1x/2x", testRenderedMaskUsesExactSampleAndPreservesCaretTransparency)
test("event query without AX document", suite.testEventQueryTracksTypingWithoutAnAccessibilityDocument)
test("event query replacement boundaries", suite.testEventQueryCannotDeleteBeforeInvocationOrAcceptNonPrefixReplacement)
test("event query Unicode and no-op", suite.testEventQueryPreservesUnicodeBoundariesAndHandlesNoOpAcceptance)
test("prefix ranking", suite.testPrefixOutranksNewerSubstringAndRecencyBreaksTies)
test("empty query recency", suite.testEmptyQueryUsesRecencyRatherThanPinStatus)
test("UTF16 query range", suite.testSessionReplacesOnlyNewQueryAndUnderstandsUTF16Ranges)
test("backspace and caret guards", suite.testBackspaceWithinQueryIsAllowedButMovingCaretOrEditingEarlierTextCancels)
test("selection and range rejection", suite.testPreexistingSelectionsAndInvalidRangesAreRejected)
test("normalization changes outside query", suite.testNormalizationChangesOutsideQueryAreRejected)
let history = HistoryTests()
test("SQLite reopen and Unicode", history.testPersistsUnicodeAndSQLCharactersAcrossReopen)
test("deduplication and pin", history.testRecopyPromotesWithoutDuplicatingOrLosingPin)
test("retention, delete and clear", history.testRetentionPreservesPinnedAndDeleteAndClearAreDurable)
test("history bounds and capture rejection", history.testRejectsEmptyAndOversizeAndNullTextAndBoundsUnpinnedHistory)
test("keyboard mode boundaries", testSessionKeyPolicy)
test("clipboard confidentiality policy", testConfidentialClipboardPolicy)
test("real pasteboard capture pipeline", testRealPasteboardCapture)
test("capture defaults and invocation routing", testCaptureAccessAndInvocationDefaults)
test("pasteboard transaction preserves newer copies", testPasteboardLeasePreservesNewUserCopiesAndRichTypes)
test("clipboard change before write", testPasteboardChangeBeforeWriteIsNotOverwritten)
print("\(tests) tests, \(failures) failures")
exit(failures == 0 ? 0 : 1)
