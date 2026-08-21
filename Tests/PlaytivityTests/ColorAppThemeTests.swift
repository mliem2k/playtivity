import Testing
import SwiftUI
@testable import Playtivity

struct ColorAppThemeTests {
    @Test func hexParserParsesRGBComponentsCorrectly() {
        // Color has no public component accessor in SwiftUI, and on this
        // Skip target Color has no usable structural `==`/`description`
        // either (see the NOTE on Color.rgbComponents(fromHex:)), so the
        // hex parser is tested directly against known numeric input/output
        // pairs instead of through Color equality.
        let parsed = Color.rgbComponents(fromHex: "1DB954")
        #expect(parsed.r == 29)
        #expect(parsed.g == 185)
        #expect(parsed.b == 84)

        let different = Color.rgbComponents(fromHex: "1ED760")
        #expect(different.r == 30)
        #expect(different.g == 215)
        #expect(different.b == 96)
    }

    @Test func allTenTokensAreDistinctColors() {
        // Touch all ten real static properties: each is a top-level `let`
        // evaluated at load time, so this proves every one actually
        // resolves (parses its hex, constructs a Color) without crashing,
        // not just that the symbols exist.
        let tokens: [Color] = [
            .appBackground, .appSurfaceRaised, .appSurfaceElevated,
            .appPrimary, .appPrimaryActive, .appTextPrimary,
            .appTextSecondary, .appTextSubdued, .appErrorRed,
            .appDividerColor,
        ]
        #expect(tokens.count == 10)

        // Distinctness itself is verified through the same hex parser
        // Color.hex(_:) delegates to (Color instances can't be compared on
        // this target, see the NOTE above). These are the exact 10 hex
        // literals Color+AppTheme.swift uses for the 10 tokens above, in
        // the same order. dividerColor is deliberately equal to
        // surfaceElevated in the Dart original (#282828 both), so 9
        // distinct values are expected, not 10.
        let tokenHexValues = [
            "121212", "181818", "282828",
            "1DB954", "1ED760", "FFFFFF",
            "A7A7A7", "535353", "E91429",
            "282828",
        ]
        // NOTE: a plain `for` loop rather than `.map { hex -> String in ... }`:
        // that typed-return trailing closure form mis-transpiles its
        // parameter type to a bare `*` on Skip's Kotlin target ("Syntax
        // error: Type expected"), matching TOTPGenerator.swift's existing
        // preference for loops over closures for this class of issue.
        var descriptions: [String] = []
        for hex in tokenHexValues {
            let c = Color.rgbComponents(fromHex: hex)
            descriptions.append("\(c.r),\(c.g),\(c.b)")
        }
        #expect(Set(descriptions).count == 9)

        let divider = Color.rgbComponents(fromHex: "282828")
        let elevated = Color.rgbComponents(fromHex: "282828")
        // NOTE: three separate #expect calls rather than one `&&`-chained
        // expression: Skip's #expect macro mis-splits a chain of multiple
        // `==` comparisons joined by `&&`, transpiling it into a 2-argument
        // expectEqual(...) call that pairs the wrong operands (the last
        // `==`'s right-hand side becomes the "expected" argument and
        // everything else, including a bare non-Boolean `divider.b`, is
        // jammed into "actual"), a Kotlin compile error ("Condition type
        // mismatch: inferred type is 'Int' but 'Boolean' was expected").
        #expect(divider.r == elevated.r)
        #expect(divider.g == elevated.g)
        #expect(divider.b == elevated.b)
    }
}
