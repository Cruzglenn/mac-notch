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

import AtollExtensionKit
import SwiftUI
import Defaults

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews
    let experienceID: String?
    let accentColor: Color?

    init(label: String, icon: String, view: NotchViews, experienceID: String? = nil, accentColor: Color? = nil) {
        self.id = experienceID.map { "extension-\($0)" } ?? "system-\(view)-\(label)"
        self.label = label
        self.icon = icon
        self.view = view
        self.experienceID = experienceID
        self.accentColor = accentColor
    }
}

class TabManager: ObservableObject {
    static let shared = TabManager()
    
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    
    private init() {}
    
    var tabs: [TabModel] {
        var tabsArray: [TabModel] = []

        if homeTabVisible {
            tabsArray.append(TabModel(label: "Home", icon: "house.fill", view: .home))
        }

        if Defaults[.dynamicShelf] {
            tabsArray.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        
        if Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] == .tab {
            tabsArray.append(TabModel(label: "Timer", icon: "timer", view: .timer))
        }

        if Defaults[.enableStatsFeature] {
            tabsArray.append(TabModel(label: "Stats", icon: "chart.xyaxis.line", view: .stats))
        }

        if Defaults[.enableNotes] || (Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .separateTab) {
            let label = Defaults[.enableNotes] ? "Notes" : "Clipboard"
            let icon = Defaults[.enableNotes] ? "note.text" : "doc.on.clipboard"
            tabsArray.append(TabModel(label: label, icon: icon, view: .notes))
        }
        if Defaults[.enableTerminalFeature] {
            tabsArray.append(TabModel(label: "Terminal", icon: "apple.terminal", view: .terminal))
        }
        if Defaults[.enableAIAssistantFeature] {
            tabsArray.append(TabModel(label: "AI Assistant", icon: "apple.intelligence", view: .aiAssistant))
        }
        if Defaults[.enableMessengerFeature] {
            tabsArray.append(TabModel(label: "Messenger", icon: "bubble.left.fill", view: .messenger))
        }
        
        if extensionTabsEnabled {
            for payload in extensionTabPayloads {
                guard let tab = payload.descriptor.tab else { continue }
                let accent = payload.descriptor.accentColor.swiftUIColor
                let iconName = tab.iconSymbolName ?? "puzzlepiece.extension"
                tabsArray.append(
                    TabModel(
                        label: tab.title,
                        icon: iconName,
                        view: .extensionExperience,
                        experienceID: payload.descriptor.id,
                        accentColor: accent
                    )
                )
            }
        }
        return tabsArray
    }
    
    private var extensionTabsEnabled: Bool {
        Defaults[.enableThirdPartyExtensions] && Defaults[.enableExtensionNotchExperiences] && Defaults[.enableExtensionNotchTabs]
    }

    private var extensionTabPayloads: [ExtensionNotchExperiencePayload] {
        extensionNotchExperienceManager.activeExperiences.filter { $0.descriptor.tab != nil }
    }

    private var homeTabVisible: Bool {
        if Defaults[.enableMinimalisticUI] {
            return true
        }
        return Defaults[.showStandardMediaControls] || Defaults[.showCalendar] || Defaults[.showMirror]
    }
}
