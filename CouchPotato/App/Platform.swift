import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

extension View {
    /// Inline navigation titles on iPhone/iPad; a no-op on the Mac.
    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder func largeTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }
}

enum Device {
    static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
}
