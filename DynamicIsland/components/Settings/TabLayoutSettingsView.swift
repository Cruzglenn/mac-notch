/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Defaults
import AppKit

struct TabLayoutSettingsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @Default(.tabAlignments) var tabAlignments
    @State private var draggingTabID: String?
    
    var leftTabs: [TabModel] {
        tabManager.tabs.filter { (tabAlignments[$0.id] ?? .left) == .left }
    }
    
    var rightTabs: [TabModel] {
        tabManager.tabs.filter { (tabAlignments[$0.id] ?? .left) == .right }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Visual Tab Layout")
                    .font(.subheadline.bold())
                Spacer()
                Text("Drag icons to move")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            
            // Adaptive Visual representation
            ZStack {
                // Background "Menu Bar"
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .secondarySystemFill).opacity(0.4))
                    .frame(height: 60)
                
                HStack(spacing: 0) {
                    // Left Drop Zone - Scrollable
                    TabZoneView(tabs: leftTabs, alignment: .left, draggingTabID: $draggingTabID) { tabID in
                        moveTab(tabID, to: .left)
                    }
                    
                    // The "Notch" - Compact width
                    VStack {
                        Spacer(minLength: 0)
                        NotchShape()
                            .fill(Color.black)
                            .frame(width: 80, height: 24)
                            .overlay(
                                Text("NOTCH")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundColor(.gray.opacity(0.4))
                                    .padding(.top, 4)
                            )
                        Spacer(minLength: 0)
                    }
                    .frame(width: 90)
                    .zIndex(10)
                    
                    // Right Drop Zone - Scrollable
                    TabZoneView(tabs: rightTabs, alignment: .right, draggingTabID: $draggingTabID) { tabID in
                        moveTab(tabID, to: .right)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            if draggingTabID != nil {
                Text("Release to drop")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.accentColor)
                    .transition(.opacity)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func moveTab(_ tabID: String, to alignment: TabAlignment) {
        var updated = tabAlignments
        updated[tabID] = alignment
        tabAlignments = updated
    }
}

struct TabZoneView: View {
    let tabs: [TabModel]
    let alignment: TabAlignment
    @Binding var draggingTabID: String?
    let onDrop: (String) -> Void
    
    @State private var isTargeted = false
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if alignment == .right { Spacer(minLength: 0) }
                
                ForEach(tabs) { tab in
                    TabIconPreview(tab: tab)
                        .onDrag {
                            self.draggingTabID = tab.id
                            return NSItemProvider(object: tab.id as NSString)
                        }
                }
                
                if tabs.isEmpty {
                    Image(systemName: "plus.circle.dotted")
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.2))
                        .frame(width: 20, height: 20)
                }
                
                if alignment == .left { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 50)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.clear, style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                )
        )
        .onDrop(of: ["public.text"], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                if let tabID = string as? String {
                    DispatchQueue.main.async {
                        onDrop(tabID)
                        self.draggingTabID = nil
                    }
                }
            }
            return true
        }
    }
}

struct TabIconPreview: View {
    let tab: TabModel
    
    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: 22, height: 22)
                
                Image(systemName: tab.icon)
                    .font(.system(size: 10))
                    .foregroundColor(tab.accentColor ?? .white)
            }
            
            Text(tab.label)
                .font(.system(size: 6.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 28)
        .contentShape(Rectangle())
    }
}
