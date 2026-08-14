import XCTest

/// The catalog feeds the dictionary, tutor lessons, and collector prompts, so its integrity
/// matters in three places at once.
final class SignCatalogTests: XCTestCase {

    /// Bundle.main is the test runner in a unit-test process, so load from the test bundle.
    private func makeCatalog() -> SignCatalog {
        SignCatalog(bundle: Bundle(for: type(of: self)))
    }

    /// Decoding the bundled signs.json must work — a schema mistake silently degrades the
    /// app to the tiny fallback list, which is easy to miss.
    func testCatalogDecodes() {
        let catalog = makeCatalog()
        XCTAssertGreaterThan(catalog.entries.count, 3,
                             "Only the fallback list loaded — signs.json failed to decode or wasn't bundled")
    }

    func testGlossesAreUnique() {
        let glosses = makeCatalog().entries.map(\.gloss)
        XCTAssertEqual(Set(glosses).count, glosses.count, "duplicate glosses in catalog")
    }

    func testLookupByGloss() {
        let catalog = makeCatalog()
        XCTAssertNotNil(catalog.entry(for: "HELLO"))
        XCTAssertNil(catalog.entry(for: "NOT-A-REAL-SIGN"))
    }

    func testSearchMatchesGlossAndMeaning() {
        let catalog = makeCatalog()
        XCTAssertTrue(catalog.search("hello").contains { $0.gloss == "HELLO" })
        // "thank you" is the meaning; the gloss is hyphenated THANK-YOU.
        XCTAssertTrue(catalog.search("thank you").contains { $0.gloss == "THANK-YOU" })
    }

    func testEmptySearchReturnsEverything() {
        let catalog = makeCatalog()
        XCTAssertEqual(catalog.search("").count, catalog.entries.count)
    }

    func testLessonRespectsLimit() {
        let catalog = makeCatalog()
        XCTAssertLessThanOrEqual(catalog.lesson(for: .courtesy, limit: 2).count, 2)
    }

    /// Glosses must follow ASL convention (CAPS, hyphens not spaces) since they're also the
    /// model's class labels.
    func testGlossFormatting() {
        for entry in makeCatalog().entries {
            XCTAssertFalse(entry.gloss.contains(" "),
                           "\(entry.gloss) uses a space; multi-word glosses should be hyphenated")
            XCTAssertEqual(entry.gloss, entry.gloss.uppercased(),
                           "\(entry.gloss) should be uppercase")
        }
    }
}
