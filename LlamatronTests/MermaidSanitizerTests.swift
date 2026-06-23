import XCTest
@testable import Llamatron

final class MermaidSanitizerTests: XCTestCase {

    func testQuotesLabelWithParentheses() {
        // The exact failure the user hit: unquoted parentheses in a node label.
        let src = "graph TD\n A --> D[Use melee weapon (knife, bat, etc.)]"
        let fixed = MermaidSanitizer.repair(src)
        XCTAssertEqual(fixed,
                       "graph TD\n A --> D[\"Use melee weapon (knife, bat, etc.)\"]")
    }

    func testLeavesCleanLabelsUntouched() {
        let src = "graph TD\n A[Start] --> B[Stop]"
        XCTAssertEqual(MermaidSanitizer.repair(src), src)
    }

    func testLeavesAlreadyQuotedLabelUntouched() {
        let src = "graph TD\n A[\"Use (knife)\"] --> B[End]"
        XCTAssertEqual(MermaidSanitizer.repair(src), src)
    }

    func testNonFlowchartReturnedUnchanged() {
        // A sequence diagram must not be altered even though it contains parentheses.
        let src = "sequenceDiagram\n Alice->>John: Hello (hi) there"
        XCTAssertEqual(MermaidSanitizer.repair(src), src)
    }

    func testRoundNodeWithBracket() {
        let src = "graph LR\n A(Config [beta]) --> B"
        XCTAssertEqual(MermaidSanitizer.repair(src),
                       "graph LR\n A(\"Config [beta]\") --> B")
    }

    func testSubroutineShapePreserved() {
        // `[[ ]]` must be matched as a unit, not as a `[` with inner `[text`.
        let src = "graph TD\n A[[Step (one)]] --> B"
        XCTAssertEqual(MermaidSanitizer.repair(src),
                       "graph TD\n A[[\"Step (one)\"]] --> B")
    }

    func testRhombusWithParens() {
        let src = "graph TD\n A{Decision (yes/no)} --> B"
        XCTAssertEqual(MermaidSanitizer.repair(src),
                       "graph TD\n A{\"Decision (yes/no)\"} --> B")
    }

    func testFlowchartKeywordAlsoRepaired() {
        let src = "flowchart LR\n A[Pick (x)] --> B"
        XCTAssertEqual(MermaidSanitizer.repair(src),
                       "flowchart LR\n A[\"Pick (x)\"] --> B")
    }

    func testEscapesEmbeddedQuotes() {
        let src = "graph TD\n A[Say \"hi\" (now)] --> B"
        XCTAssertEqual(MermaidSanitizer.repair(src),
                       "graph TD\n A[\"Say #quot;hi#quot; (now)\"] --> B")
    }

    func testPlainPunctuationNotQuoted() {
        // Colons, commas, dots, hyphens are valid unquoted; don't needlessly quote.
        let src = "graph TD\n A[Time: 5pm, ok-go] --> B"
        XCTAssertEqual(MermaidSanitizer.repair(src), src)
    }

    func testLeadingDirectiveStillDetectsFlowchart() {
        let src = "%%{init: {'theme':'dark'}}%%\ngraph TD\n A[x (y)] --> B"
        XCTAssertEqual(MermaidSanitizer.repair(src),
                       "%%{init: {'theme':'dark'}}%%\ngraph TD\n A[\"x (y)\"] --> B")
    }
}
