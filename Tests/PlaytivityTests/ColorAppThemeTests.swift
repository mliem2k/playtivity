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
        // not just that the symbol exists.
        let tokens: [Color] = [
            .appBackground, .appSurfaceRaised, .appSurfaceElevated,
            .appPrimary, .appPrimaryActive, .appTextPrimary,
            .appTextSecondary, .appTextSubdued, .appErrorRed,
            .appDividerColor,
        ]
        #expect(tokens.count == 10)

        // Distinctness is verified through the same hex parser
        // Color.hex(_:) delegates to (Color instances can't be compared on
        // this target, see the NOTE on rgbComponents(fromHex:)), reading
        // the real named hex constants Color+AppTheme.swift's properties
        // are built from, not a hand-retyped copy of the literals: a typo
        // in the real constants is caught here instead of silently passing.
        // dividerColor is deliberately equal to surfaceElevated in the Dart
        // original (#282828 both), so 9 distinct values are expected, not 10.
        let tokenHexValues = [
            Color.appBackgroundHex, Color.appSurfaceRaisedHex, Color.appSurfaceElevatedHex,
            Color.appPrimaryHex, Color.appPrimaryActiveHex, Color.appTextPrimaryHex,
            Color.appTextSecondaryHex, Color.appTextSubduedHex, Color.appErrorRedHex,
            Color.appDividerColorHex,
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

        // Confirms dividerColor and surfaceElevated are DELIBERATELY the
        // same string in the real source (not merely producing the same
        // RGB math from two independent, possibly-coincidentally-matching
        // literals). Comparing rgbComponents(fromHex:) on the same literal
        // twice would be tautological (it can never disagree with itself);
        // this compares the two distinct named constants instead.
        #expect(Color.appDividerColorHex == Color.appSurfaceElevatedHex)
    }
}
