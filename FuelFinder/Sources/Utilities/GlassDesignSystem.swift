//
//  GlassDesignSystem.swift
//  FuelFinder
//
//  Liquid Glass Design System — shared with TetraTrack sibling app
//  Glass-first UI components: translucent materials, blur, soft shadows, fluid animations
//

import SwiftUI

// MARK: - Glass Material Levels

enum GlassMaterial {
    case ultraThin
    case thin
    case regular
    case thick
    case chromatic

    var color: Color {
        switch self {
        case .ultraThin: return AppColors.cardBackground
        case .thin: return AppColors.cardBackground
        case .regular: return AppColors.elevatedSurface
        case .thick: return AppColors.elevatedSurface
        case .chromatic: return AppColors.cardBackground
        }
    }
}

// MARK: - Glass Card View Modifier

struct GlassCard: ViewModifier {
    let material: GlassMaterial
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let borderWidth: CGFloat
    let padding: CGFloat

    /// Memoized border gradient — avoids recreating per render cycle.
    private static let borderGradient = LinearGradient(
        colors: [
            .white.opacity(0.3),
            .white.opacity(0.1),
            .clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    init(
        material: GlassMaterial = .regular,
        cornerRadius: CGFloat = CornerRadius.xl,
        shadowRadius: CGFloat = 10,
        borderWidth: CGFloat = BorderWidth.subtle,
        padding: CGFloat = Spacing.lg
    ) {
        self.material = material
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.borderWidth = borderWidth
        self.padding = padding
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(material.color)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Self.borderGradient, lineWidth: borderWidth)
            )
            .shadow(color: .black.opacity(0.08), radius: shadowRadius, x: 0, y: 4)
    }
}

// MARK: - Glass Button Style

struct GlassButtonStyle: ButtonStyle {
    let material: GlassMaterial
    let tint: Color

    init(material: GlassMaterial = .thin, tint: Color = AppColors.primary) {
        self.material = material
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .fill(material.color)
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .fill(tint.opacity(configuration.isPressed ? 0.2 : 0.1))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .stroke(tint.opacity(0.3), lineWidth: BorderWidth.subtle)
            )
            .shadow(color: tint.opacity(0.2), radius: configuration.isPressed ? 4 : 8, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Glass Stat Card

struct GlassStatCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(Opacity.mediumLight))
                    .frame(width: TapTarget.standard, height: TapTarget.standard)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .modifier(GlassCard(material: .thin, cornerRadius: CornerRadius.lg, shadowRadius: 6, padding: Spacing.lg))
    }
}

// MARK: - Glass Section Header

struct GlassSectionHeader: View {
    let title: String
    let icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(AppColors.primary)
            }
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal)
    }
}

// MARK: - Glass Chip

struct GlassChip: View {
    let text: String
    let icon: String?
    let color: Color

    init(_ text: String, icon: String? = nil, color: Color = AppColors.primary) {
        self.text = text
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption)
            }
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.sm)
        .background(color.opacity(0.12))
        .background(AppColors.cardBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.2), lineWidth: BorderWidth.subtle)
        )
    }
}

// MARK: - Fuel Price Badge

struct FuelPriceBadge: View {
    let price: String
    let tier: Int
    let size: BadgeSize

    enum BadgeSize {
        case small, medium, large

        var font: Font {
            switch self {
            case .small: return .caption2.weight(.bold)
            case .medium: return .caption.weight(.bold)
            case .large: return .subheadline.weight(.bold)
            }
        }

        var hPadding: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 8
            case .large: return 10
            }
        }

        var vPadding: CGFloat {
            switch self {
            case .small: return 2
            case .medium: return 4
            case .large: return 6
            }
        }
    }

    init(_ price: String, tier: Int, size: BadgeSize = .medium) {
        self.price = price
        self.tier = tier
        self.size = size
    }

    private var tierColor: Color { AppColors.priceTier(tier) }

    var body: some View {
        Text(price)
            .font(size.font)
            .padding(.horizontal, size.hPadding)
            .padding(.vertical, size.vPadding)
            .background(tierColor)
            .foregroundStyle(tier == 1 ? .black : .white)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
            .shadow(color: tierColor.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

// MARK: - View Extensions

extension View {
    func glassCard(
        material: GlassMaterial = .regular,
        cornerRadius: CGFloat = CornerRadius.xl,
        shadowRadius: CGFloat = 10
    ) -> some View {
        modifier(GlassCard(material: material, cornerRadius: cornerRadius, shadowRadius: shadowRadius))
    }

    func glassCard(
        material: GlassMaterial = .regular,
        cornerRadius: CGFloat = CornerRadius.xl,
        shadowRadius: CGFloat = 10,
        padding: CGFloat
    ) -> some View {
        modifier(GlassCard(material: material, cornerRadius: cornerRadius, shadowRadius: shadowRadius, padding: padding))
    }

    func glassList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppColors.cardBackground)
    }

    func glassPanel() -> some View {
        self
            .background(AppColors.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Glass Navigation Style

struct GlassNavigationStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(AppColors.cardBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func glassNavigation() -> some View {
        modifier(GlassNavigationStyle())
    }
}
