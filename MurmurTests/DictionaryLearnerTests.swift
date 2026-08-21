import XCTest
@testable import Murmur

final class DictionaryLearnerTests: XCTestCase {
    func testMidSentenceProperNounRepeatedEnoughIsSuggested() {
        let texts = [
            "Ship it to Trajekt today.",
            "The Trajekt demo went well.",
            "I told Trajekt about the change.",
        ]
        XCTAssertEqual(DictionaryLearner.suggestions(from: texts, knownWords: []), ["Trajekt"])
    }

    func testSentenceInitialCapitalsAreNotCounted() {
        let texts = [
            "Tomorrow we ship.",
            "Tomorrow is fine.",
            "Tomorrow works too.",
        ]
        XCTAssertEqual(DictionaryLearner.suggestions(from: texts, knownWords: []), [])
    }

    func testInternalCapitalWordsCountEvenAtSentenceStart() {
        let texts = [
            "GStack deploys are green.",
            "GStack needs a retry.",
            "GStack finished the sync.",
        ]
        XCTAssertEqual(DictionaryLearner.suggestions(from: texts, knownWords: []), ["GStack"])
    }

    func testKnownWordsAreExcludedCaseInsensitively() {
        let texts = [
            "Ping Trajekt about it.",
            "Ask Trajekt for access.",
            "Tell Trajekt we are done.",
        ]
        XCTAssertEqual(
            DictionaryLearner.suggestions(from: texts, knownWords: ["trajekt"]),
            []
        )
    }

    func testBelowThresholdIsExcluded() {
        let texts = ["Ping Trajekt now.", "Ask Trajekt later."]
        XCTAssertEqual(DictionaryLearner.suggestions(from: texts, knownWords: []), [])
    }

    func testCommonCalendarWordsAndPronounsAreExcluded() {
        let texts = [
            "See you Monday about the Trajekt sync.",
            "On Monday I will ping Trajekt again.",
            "Every Monday we review Trajekt metrics.",
        ]
        XCTAssertEqual(DictionaryLearner.suggestions(from: texts, knownWords: []), ["Trajekt"])
    }

    func testSortedByFrequencyThenAlphabetically() {
        let texts = [
            "Ask Zephyr and Trajekt.",
            "Ping Zephyr and Trajekt.",
            "Tell Zephyr and Trajekt.",
            "Also Zephyr again.",
        ]
        XCTAssertEqual(
            DictionaryLearner.suggestions(from: texts, knownWords: []),
            ["Zephyr", "Trajekt"]
        )
    }
}
