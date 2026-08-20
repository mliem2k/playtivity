import SwiftUI

/// Port of `/tmp/ref_state_display_widget.dart`'s reusable auth-required/error/empty state
/// layout: an icon, a title, an optional subtitle, and up to two action buttons. Matches the Dart
/// original's named-constructor shape (`.empty`, `.error`, `.authRequired`) as static factory
/// functions, since Swift has no factory-constructor syntax. Only the three factories the task
/// brief names are ported (`.empty`, `.error`, `.authRequired`); the Dart original's `.loading`
/// and `.custom` variants are not referenced anywhere in this phase's scope
/// (`ActivitiesScreen` has its own thin top progress indicator, not `StateDisplayWidget.loading`)
/// and are deliberately not ported.
///
/// No `AppTheme`/Material-icon port exists in this codebase; SF Symbols are used in place of the
/// Dart original's `Icons.*` glyphs (a purely visual substitution, no correctness risk), and plain
/// system-standard SwiftUI colors stand in for the Dart theme's named color tokens, matching
/// `AlbumArtView`/`AvatarView`'s same precedent.
struct StateDisplayView: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let buttonText: String?
    let onAction: (() -> Void)?
    let secondaryButtonText: String?
    let onSecondaryAction: (() -> Void)?

    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        buttonText: String? = nil,
        onAction: (() -> Void)? = nil,
        secondaryButtonText: String? = nil,
        onSecondaryAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.buttonText = buttonText
        self.onAction = onAction
        self.secondaryButtonText = secondaryButtonText
        self.onSecondaryAction = onSecondaryAction
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundStyle(Color.secondary)
            }
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            if let buttonText, let onAction {
                Button(buttonText, action: onAction)
            }
            if let secondaryButtonText, let onSecondaryAction {
                Button(secondaryButtonText, action: onSecondaryAction)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    /// Port of `StateDisplayWidget.empty` (ref_state_display_widget.dart:37-52).
    static func empty(
        title: String,
        subtitle: String? = nil,
        icon: String = "music.note",
        buttonText: String = "Refresh",
        onAction: (() -> Void)? = nil
    ) -> StateDisplayView {
        StateDisplayView(icon: icon, title: title, subtitle: subtitle, buttonText: buttonText, onAction: onAction)
    }

    /// Port of `StateDisplayWidget.error` (ref_state_display_widget.dart:54-73).
    static func error(
        title: String,
        error: String,
        icon: String = "exclamationmark.triangle",
        buttonText: String = "Try again",
        onAction: (() -> Void)? = nil,
        secondaryButtonText: String? = nil,
        onSecondaryAction: (() -> Void)? = nil
    ) -> StateDisplayView {
        StateDisplayView(
            icon: icon, title: title, subtitle: error, buttonText: buttonText, onAction: onAction,
            secondaryButtonText: secondaryButtonText, onSecondaryAction: onSecondaryAction
        )
    }

    /// Port of `StateDisplayWidget.authRequired` (ref_state_display_widget.dart:75-93).
    static func authRequired(
        title: String = "Authentication Required",
        subtitle: String = "Please log in to continue",
        buttonText: String = "Login",
        onAction: (() -> Void)? = nil,
        secondaryButtonText: String? = nil,
        onSecondaryAction: (() -> Void)? = nil
    ) -> StateDisplayView {
        StateDisplayView(
            icon: "lock", title: title, subtitle: subtitle, buttonText: buttonText, onAction: onAction,
            secondaryButtonText: secondaryButtonText, onSecondaryAction: onSecondaryAction
        )
    }
}
