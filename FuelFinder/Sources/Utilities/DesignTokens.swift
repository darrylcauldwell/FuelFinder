//
//  DesignTokens.swift
//  FuelFinder
//
//  Centralized design tokens — shared scale with TetraTrack sibling app
//

import SwiftUI

// MARK: - Spacing Scale

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let jumbo: CGFloat = 32
}

// MARK: - Corner Radius Scale

enum CornerRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let pill: CGFloat = 9999
}

// MARK: - Tap Target Sizes

enum TapTarget {
    static let standard: CGFloat = 44
    static let comfortable: CGFloat = 60
    static let large: CGFloat = 80
}

// MARK: - Shadow Scale

enum Shadow {
    static let subtle = ShadowConfig(color: .black.opacity(0.06), radius: 4, y: 2)
    static let medium = ShadowConfig(color: .black.opacity(0.08), radius: 8, y: 4)
    static let prominent = ShadowConfig(color: .black.opacity(0.12), radius: 12, y: 6)
    static let glass = ShadowConfig(color: .black.opacity(0.08), radius: 10, y: 4)
}

struct ShadowConfig {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
    var x: CGFloat = 0
}

// MARK: - Typography Scale

enum Typography {
    static let largeTitle: Font = .largeTitle
    static let title: Font = .title
    static let title2: Font = .title2
    static let title3: Font = .title3
    static let headline: Font = .headline
    static let body: Font = .body
    static let subheadline: Font = .subheadline
    static let caption: Font = .caption
    static let caption2: Font = .caption2
}

// MARK: - Border Width

enum BorderWidth {
    static let subtle: CGFloat = 0.5
    static let standard: CGFloat = 1
    static let emphasis: CGFloat = 2
}

// MARK: - Opacity Scale

enum Opacity {
    static let ultraLight: Double = 0.05
    static let light: Double = 0.1
    static let mediumLight: Double = 0.15
    static let medium: Double = 0.2
    static let mediumHeavy: Double = 0.3
    static let heavy: Double = 0.4
}

// MARK: - Animation Durations

enum AnimationDuration {
    static let fast: Double = 0.15
    static let standard: Double = 0.25
    static let slow: Double = 0.35
}

// MARK: - View Modifiers

extension View {
    func standardShadow(_ config: ShadowConfig = Shadow.medium) -> some View {
        self.shadow(color: config.color, radius: config.radius, x: config.x, y: config.y)
    }

    func minimumTapTarget(_ size: CGFloat = TapTarget.standard) -> some View {
        self.frame(minWidth: size, minHeight: size)
    }

    func standardCard() -> some View {
        self
            .padding(Spacing.lg)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    }
}

// MARK: - Primary Action Button Style

struct PrimaryActionButtonStyle: ButtonStyle {
    let color: Color

    init(color: Color = AppColors.primary) {
        self.color = color
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(Spacing.lg)
            .background(configuration.isPressed ? color.opacity(0.8) : color)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: AnimationDuration.fast), value: configuration.isPressed)
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Adaptive Layout

enum AdaptiveLayout {
    static func columns(for sizeClass: UserInterfaceSizeClass?) -> Int {
        switch sizeClass {
        case .regular: return 2
        default: return 1
        }
    }

    static let maxContentWidth: CGFloat = 700
    static let idealCardWidth: CGFloat = 320
}

struct AdaptiveGrid<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let spacing: CGFloat
    let content: () -> Content

    init(spacing: CGFloat = Spacing.lg, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        let columns = AdaptiveLayout.columns(for: horizontalSizeClass)

        if columns > 1 {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
                spacing: spacing
            ) {
                content()
            }
        } else {
            VStack(spacing: spacing) {
                content()
            }
        }
    }
}

// MARK: - Dynamic Type Support

struct ScaledFont: ViewModifier {
    @ScaledMetric var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, relativeTo textStyle: Font.TextStyle = .body) {
        self._size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, relativeTo: textStyle))
    }
}

// MARK: - Accessibility Helpers

extension View {
    func accessibleButton(_ label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }

    func accessibleStatus(_ status: String, description: String) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(status): \(description)")
    }
}

// MARK: - Accessible Status Indicator

struct AccessibleStatusIndicator: View {
    let status: StatusType
    let size: Size

    enum StatusType {
        case connected, disconnected, syncing, error, warning, success, inactive, stale

        var icon: String {
            switch self {
            case .connected: return "checkmark.circle.fill"
            case .disconnected: return "xmark.circle.fill"
            case .syncing: return "arrow.triangle.2.circlepath"
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .inactive: return "circle"
            case .stale: return "clock.badge.exclamationmark"
            }
        }

        var color: Color {
            switch self {
            case .connected, .success: return AppColors.active
            case .disconnected, .inactive: return AppColors.inactive
            case .syncing: return AppColors.primary
            case .error: return AppColors.error
            case .warning, .stale: return AppColors.warning
            }
        }

        var label: String {
            switch self {
            case .connected: return "Connected"
            case .disconnected: return "Disconnected"
            case .syncing: return "Syncing"
            case .error: return "Error"
            case .warning: return "Warning"
            case .success: return "Success"
            case .inactive: return "Inactive"
            case .stale: return "Data may be outdated"
            }
        }
    }

    enum Size {
        case small, medium, large

        var iconSize: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 16
            case .large: return 20
            }
        }

        var font: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            case .large: return .subheadline
            }
        }
    }

    init(_ status: StatusType, size: Size = .medium) {
        self.status = status
        self.size = size
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: status.icon)
                .font(.system(size: size.iconSize))
                .foregroundStyle(status.color)

            Text(status.label)
                .font(size.font)
                .foregroundStyle(status.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.label)")
    }
}
