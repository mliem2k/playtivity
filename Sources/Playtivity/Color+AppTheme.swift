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

    static let appBackground = Color.hex("121212")
    static let appSurfaceRaised = Color.hex("181818")
    static let appSurfaceElevated = Color.hex("282828")
    static let appPrimary = Color.hex("1DB954")
    static let appPrimaryActive = Color.hex("1ED760")
    static let appTextPrimary = Color.hex("FFFFFF")
    static let appTextSecondary = Color.hex("A7A7A7")
    static let appTextSubdued = Color.hex("535353")
    static let appErrorRed = Color.hex("E91429")
    static let appDividerColor = Color.hex("282828")
}
