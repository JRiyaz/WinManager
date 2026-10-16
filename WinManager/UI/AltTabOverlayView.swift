//
//  AltTabOverlayView.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import SwiftUI

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

struct AltTabOverlayView: View {
    let items: [SwitcherItem]
    let selectedIndex: Int
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        VStack(spacing: 12) {
                            Image(nsImage: item.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 72, height: 72)
                            
                            Text(item.name)
                                .font(.system(size: 13, weight: index == selectedIndex ? .semibold : .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 120)
                        }
                        .frame(width: 132, height: 142)
                        .background(index == selectedIndex ? Color.white.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(index == selectedIndex ? Color.white.opacity(0.45) : Color.clear, lineWidth: 1)
                        }
                        .id(item.id)
                    }
                }
                .padding(16)
            }
            .frame(height: 178)
            .background(VisualEffectView(material: .hudWindow).clipShape(RoundedRectangle(cornerRadius: 20)))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .onChange(of: selectedIndex) { _, newIndex in
                guard items.indices.contains(newIndex) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(items[newIndex].id, anchor: .center)
                }
            }
            .onAppear {
                guard items.indices.contains(selectedIndex) else { return }
                proxy.scrollTo(items[selectedIndex].id, anchor: .center)
            }
        }
    }
}
