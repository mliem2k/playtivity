import SwiftUI

extension Color {
    // NOTE: this is a static factory, not `init(hex:)`. Skip's Kotlin
    // transpile rejects an extension-added initializer on a type defined in
    // another module ("cannot add additional constructors" to a foreign
    // Kotlin type) since `Color` lives in SkipUI, not this module. A static
    // factory method has no such restriction.
    //
    // Hex parsing mirrors TOTPGenerator.hexDigitValue/hexToBytes rather than
    // Scanner or Int(_:radix:): Scanner.scanHexInt64 is "not yet available in
    // Skip"; UInt64 bit-shifting fails Kotlin's transpile ("Cast required...
    // avoid unsigned types in favor of signed types"); and Int(_:radix:)
    // transpiles to a bare `Int()` Kotlin constructor call with no radix
    // parameter, also a hard error. ASCII-code arithmetic on individual
    // Characters (already proven in this codebase) sidesteps all three.
    private static func hexDigitValue(_ c: Character) -> Int {
        let v = Int(c.asciiValue!)
        if v >= 48 && v <= 57 {
            return v - 48
        } else if v >= 97 && v <= 102 {
            return v - 97 + 10
        } else if v >= 65 && v <= 70 {
            return v - 65 + 10
        } else {
            return 0
        }
    }

    // Exposed (not private) so tests can assert the hex parser's numeric
    // output directly. SwiftUI's `Color` has no public component accessor,
    // and on this Skip target `Color` also has no usable structural `==` or
    // `description`: verified empirically, `==` compared two Colors built
    // from the identical hex string as unequal on the Kotlin/JVM transpile
    // (looks like reference-based equality with no custom equals()), and
    // `.description` returned 10 distinct values for the 10 tokens instead
    // of the expected 9, even though 2 of them share a hex value. Color-level
    // equality is therefore not usable for testing the parser or token
    // distinctness on this target; test the numeric parse instead.
    static func rgbComponents(fromHex hex: String) -> (r: Int, g: Int, b: Int) {
        let chars: [Character] = hex.map { $0 }
        let r = hexDigitValue(chars[0]) * 16 + hexDigitValue(chars[1])
        let g = hexDigitValue(chars[2]) * 16 + hexDigitValue(chars[3])
        let b = hexDigitValue(chars[4]) * 16 + hexDigitValue(chars[5])
        return (r, g, b)
    }

    static func hex(_ hex: String) -> Color {
        let c = rgbComponents(fromHex: hex)
        return Color(red: Double(c.r) / 255.0, green: Double(c.g) / 255.0, blue: Double(c.b) / 255.0)
    }

    // Named hex constants, not private: these are the actual source of
    // truth the ten static properties below are built from, and tests
    // reference these same constants directly (rather than a hand-retyped
    // copy of the literals) so a typo here is caught by the test suite
    // instead of silently passing it.
    static let appBackgroundHex = "121212"
    static let appSurfaceRaisedHex = "181818"
    static let appSurfaceElevatedHex = "282828"
    static let appPrimaryHex = "1DB954"
    static let appPrimaryActiveHex = "1ED760"
    static let appTextPrimaryHex = "FFFFFF"
    static let appTextSecondaryHex = "A7A7A7"
    static let appTextSubduedHex = "535353"
    static let appErrorRedHex = "E91429"
    // Deliberately equal to appSurfaceElevatedHex, matching the Dart original.
    static let appDividerColorHex = "282828"

    // NOTE: `Color.` is required on the constant references below, not just
    // on `hex(...)` itself. Skip transpiles a `static let` extension
    // property on a foreign type (Color lives in SkipUI) into a Kotlin
    // top-level extension property on Color.Companion, backed by a
    // top-level `private val` whose initializer has NO implicit receiver.
    // A bare reference to a sibling constant (e.g. `appBackgroundHex`
    // instead of `Color.appBackgroundHex`) resolves fine in Swift (implicit
    // Self) and in Kotlin function bodies (which do carry an implicit
    // Color.Companion receiver), but fails as "Unresolved reference" here.
    static let appBackground = Color.hex(Color.appBackgroundHex)
    static let appSurfaceRaised = Color.hex(Color.appSurfaceRaisedHex)
    static let appSurfaceElevated = Color.hex(Color.appSurfaceElevatedHex)
    static let appPrimary = Color.hex(Color.appPrimaryHex)
    static let appPrimaryActive = Color.hex(Color.appPrimaryActiveHex)
    static let appTextPrimary = Color.hex(Color.appTextPrimaryHex)
    static let appTextSecondary = Color.hex(Color.appTextSecondaryHex)
    static let appTextSubdued = Color.hex(Color.appTextSubduedHex)
    static let appErrorRed = Color.hex(Color.appErrorRedHex)
    static let appDividerColor = Color.hex(Color.appDividerColorHex)
}
