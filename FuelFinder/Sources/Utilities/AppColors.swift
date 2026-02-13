//
//  AppColors.swift
//  FuelFinder
//
//  Centralized color system with full dark/light mode support
//  Sibling design system to TetraTrack — shared blue primary theme
//  with fuel-domain semantic colours
//

import SwiftUI
import UIKit

// MARK: - Adaptive Color Provider

struct AppColors {

    // MARK: - Primary Blue Theme Colors (shared with TetraTrack)

    /// Main brand blue — primary actions and key UI elements
    static var primary: Color {
        Color(light: .init(red: 0.15, green: 0.45, blue: 0.85),
              dark: .init(red: 0.35, green: 0.6, blue: 1.0))
    }

    /// Lighter blue for secondary elements
    static var secondary: Color {
        Color(light: .init(red: 0.4, green: 0.65, blue: 0.95),
              dark: .init(red: 0.5, green: 0.7, blue: 1.0))
    }

    /// Accent blue — brighter for highlights
    static var accent: Color {
        Color(light: .init(red: 0.0, green: 0.5, blue: 1.0),
              dark: .init(red: 0.3, green: 0.7, blue: 1.0))
    }

    /// Deep blue for contrast elements
    static var deep: Color {
        Color(light: .init(red: 0.1, green: 0.3, blue: 0.6),
              dark: .init(red: 0.25, green: 0.5, blue: 0.85))
    }

    /// Light blue for backgrounds and fills
    static var light: Color {
        Color(light: .init(red: 0.85, green: 0.92, blue: 1.0),
              dark: .init(red: 0.15, green: 0.25, blue: 0.4))
    }

    // MARK: - Fuel Price Tier Colors

    /// Cheapest price tier — green
    static var priceCheap: Color {
        Color(light: .init(red: 0.2, green: 0.7, blue: 0.4),
              dark: .init(red: 0.35, green: 0.85, blue: 0.5))
    }

    /// Middle price tier — amber
    static var priceMid: Color {
        Color(light: .init(red: 0.95, green: 0.65, blue: 0.15),
              dark: .init(red: 1.0, green: 0.75, blue: 0.35))
    }

    /// Expensive price tier — red
    static var priceExpensive: Color {
        Color(light: .init(red: 0.9, green: 0.25, blue: 0.25),
              dark: .init(red: 1.0, green: 0.4, blue: 0.4))
    }

    /// Returns colour for a price tier (0=cheap, 1=mid, 2=expensive)
    static func priceTier(_ tier: Int) -> Color {
        switch tier {
        case 0: return priceCheap
        case 1: return priceMid
        default: return priceExpensive
        }
    }

    // MARK: - Fuel Type Colors

    /// Unleaded fuel
    static var unleaded: Color {
        Color(light: .init(red: 0.2, green: 0.65, blue: 0.7),
              dark: .init(red: 0.35, green: 0.8, blue: 0.85))
    }

    /// Diesel fuel
    static var diesel: Color {
        Color(light: .init(red: 0.2, green: 0.5, blue: 0.9),
              dark: .init(red: 0.4, green: 0.65, blue: 1.0))
    }

    /// Super unleaded
    static var superUnleaded: Color {
        Color(light: .init(red: 0.45, green: 0.35, blue: 0.85),
              dark: .init(red: 0.6, green: 0.5, blue: 1.0))
    }

    /// Premium diesel
    static var premiumDiesel: Color {
        Color(light: .init(red: 0.3, green: 0.2, blue: 0.7),
              dark: .init(red: 0.5, green: 0.4, blue: 0.9))
    }

    /// Returns colour for a fuel type key
    static func fuelType(_ type: String) -> Color {
        switch type {
        case "unleaded": return unleaded
        case "diesel": return diesel
        case "superUnleaded": return superUnleaded
        case "premiumDiesel": return premiumDiesel
        default: return primary
        }
    }

    // MARK: - Brand Colors

    /// Station brand accent colour
    static func brand(_ name: String) -> Color {
        switch name.lowercased() {
        case "shell": return Color(light: .init(red: 0.95, green: 0.75, blue: 0.1), dark: .init(red: 1.0, green: 0.82, blue: 0.2))
        case "bp": return Color(light: .init(red: 0.0, green: 0.6, blue: 0.3), dark: .init(red: 0.2, green: 0.75, blue: 0.45))
        case "esso": return Color(light: .init(red: 0.85, green: 0.15, blue: 0.15), dark: .init(red: 1.0, green: 0.35, blue: 0.35))
        case "texaco": return Color(light: .init(red: 0.9, green: 0.2, blue: 0.2), dark: .init(red: 1.0, green: 0.4, blue: 0.4))
        default: return primary
        }
    }

    // MARK: - Status Colors (shared with TetraTrack)

    /// Active/Success — green
    static var active: Color {
        Color(light: .init(red: 0.2, green: 0.7, blue: 0.4),
              dark: .init(red: 0.35, green: 0.85, blue: 0.5))
    }

    /// Inactive — blue-gray
    static var inactive: Color {
        Color(light: .init(red: 0.5, green: 0.55, blue: 0.65),
              dark: .init(red: 0.45, green: 0.5, blue: 0.6))
    }

    /// Warning — amber
    static var warning: Color {
        Color(light: .init(red: 0.95, green: 0.65, blue: 0.15),
              dark: .init(red: 1.0, green: 0.75, blue: 0.35))
    }

    /// Error — red
    static var error: Color {
        Color(light: .init(red: 0.9, green: 0.25, blue: 0.25),
              dark: .init(red: 1.0, green: 0.4, blue: 0.4))
    }

    static var success: Color { active }
    static var destructive: Color { error }

    // MARK: - Surface Colors (shared with TetraTrack)

    /// Card background — subtle blue tint
    static var cardBackground: Color {
        Color(light: .init(red: 0.94, green: 0.96, blue: 0.99),
              dark: .init(red: 0.12, green: 0.14, blue: 0.18))
    }

    /// Elevated surface — lighter blue tint
    static var elevatedSurface: Color {
        Color(light: .init(red: 0.97, green: 0.98, blue: 1.0),
              dark: .init(red: 0.16, green: 0.18, blue: 0.22))
    }

    // MARK: - Route Colors

    /// Route polyline colour
    static var routeLine: Color { primary }

    /// Selected station highlight
    static var stationSelected: Color { accent }

    /// Detour route overlay
    static var detourLine: Color { secondary }

    // MARK: - Stale Data

    /// Stale data banner background
    static var staleBanner: Color { warning }

    // MARK: - Neutral

    static var neutralGray: Color {
        Color(light: .init(red: 0.55, green: 0.55, blue: 0.6),
              dark: .init(red: 0.5, green: 0.5, blue: 0.55))
    }
}

// MARK: - Color Extension for Light/Dark

extension Color {
    /// Creates a color that adapts to light and dark mode
    init(light: Color.Resolved, dark: Color.Resolved) {
        self.init(UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(
                    red: CGFloat(dark.red),
                    green: CGFloat(dark.green),
                    blue: CGFloat(dark.blue),
                    alpha: CGFloat(dark.opacity)
                )
            } else {
                return UIColor(
                    red: CGFloat(light.red),
                    green: CGFloat(light.green),
                    blue: CGFloat(light.blue),
                    alpha: CGFloat(light.opacity)
                )
            }
        })
    }
}

// MARK: - ShapeStyle Extension

extension ShapeStyle where Self == Color {
    static var appPrimary: Color { AppColors.primary }
    static var appCardBackground: Color { AppColors.cardBackground }
    static var appPriceCheap: Color { AppColors.priceCheap }
    static var appPriceMid: Color { AppColors.priceMid }
    static var appPriceExpensive: Color { AppColors.priceExpensive }
}
