//
//  AltTabOverlayView.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import SwiftUI

// Bridges Apple's native glass blur into SwiftUI
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct AltTabOverlayView: View {
    let items: [SwitcherItem]
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 16) {
                    Image(nsImage: item.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 84, height: 84)
                        // Slight pop effect for the selected app
                        .scaleEffect(index == selectedIndex ? 1.05 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: selectedIndex)
                    
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        // Native pill highlight behind text
                        .background(index == selectedIndex ? Color.white.opacity(0.25) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .frame(width: 140, height: 160)
                // Highlight block behind the whole icon
                .background(index == selectedIndex ? Color.white.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(24)
        // Native HUD glass background
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 24))
        )
        // Wraps layout if too many apps are open
        .frame(maxWidth: NSScreen.main?.visibleFrame.width ?? 800)
    }
}
