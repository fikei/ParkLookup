//
//  ViewExtensions.swift
//  SFParkingZoneFinder
//
//  Created by Claude
//

import SwiftUI

// MARK: - Developer Mode Text Selection

extension View {
    /// Enables text selection when developer mode is active
    /// Allows copying any text in the app for debugging purposes
    func developerTextSelection() -> some View {
        self.modifier(DeveloperTextSelectionModifier())
    }
}

struct DeveloperTextSelectionModifier: ViewModifier {
    @ObservedObject private var devSettings = DeveloperSettings.shared

    func body(content: Content) -> some View {
        if devSettings.developerModeUnlocked {
            content
                .textSelection(.enabled)
        } else {
            content
        }
    }
}
