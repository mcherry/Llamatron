import XCTest
@testable import Llamatron

final class HTMLExtractorTests: XCTestCase {

    func testExtractsTitleAndStripsBoilerplate() {
        let html = """
        <html><head><title>My &amp; Page</title><style>.x{color:red}</style></head>
        <body><nav>menu menu</nav><script>evil()</script>
        <h1>Heading</h1><p>First paragraph.</p><p>Second line.</p>
        <footer>copyright notice</footer></body></html>
        """
        let result = HTMLExtractor.extract(html)
        XCTAssertEqual(result.title, "My & Page")
        XCTAssertTrue(result.text.contains("Heading"))
        XCTAssertTrue(result.text.contains("First paragraph."))
        XCTAssertTrue(result.text.contains("Second line."))
        XCTAssertFalse(result.text.contains("evil"))            // <script> removed
        XCTAssertFalse(result.text.contains("color:red"))       // <style> removed
        XCTAssertFalse(result.text.contains("menu menu"))       // <nav> removed
        XCTAssertFalse(result.text.contains("copyright"))       // <footer> removed
    }

    func testParagraphsBecomeSeparateLines() {
        let result = HTMLExtractor.extract("<p>One.</p><p>Two.</p>")
        XCTAssertEqual(result.text, "One.\nTwo.")
    }

    func testDecodesNamedAndNumericEntities() {
        XCTAssertEqual(HTMLExtractor.decodeEntities("A&#38;B &#x41; &lt;tag&gt;"), "A&B A <tag>")
    }
}

final class WebFetcherURLTests: XCTestCase {

    func testNormalizesAndDefaultsToHTTPS() {
        XCTAssertEqual(WebFetcher.normalizedURL("example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(WebFetcher.normalizedURL("  http://x.org/p  ")?.absoluteString, "http://x.org/p")
    }

    func testRejectsNonHTTPSchemes() {
        XCTAssertNil(WebFetcher.normalizedURL("file:///etc/passwd"))
        XCTAssertNil(WebFetcher.normalizedURL("data:text/html,hi"))
        XCTAssertNil(WebFetcher.normalizedURL("ftp://x.org"))
        XCTAssertNil(WebFetcher.normalizedURL(""))
    }
}
