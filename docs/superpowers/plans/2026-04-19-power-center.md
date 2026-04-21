# Power Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a dedicated "Battery" tab (Power Center) in the Atoll Dynamic Island to show real-time battery levels for Mac and Bluetooth devices using a grid-based UI.

**Architecture:** 
- Add `.battery` to `NotchViews` and `TabManager`.
- Create `NotchBatteryView.swift` and `BatteryTileView.swift` for the UI.
- Integrate with `BatteryStatusViewModel` and `BluetoothAudioManager`.
- Update `ContentView` to render the new view and handle sizing.

**Tech Stack:** SwiftUI, Combine, Defaults (for settings).

---

### Task 1: Update Infrastructure & State

**Files:**
- Modify: `DynamicIsland/enums/generic.swift`
- Modify: `DynamicIsland/models/Constants.swift`
- Modify: `DynamicIsland/DynamicIslandViewCoordinator.swift`
- Modify: `DynamicIsland/managers/TabManager.swift`

- [ ] **Step 1: Add `.battery` to `NotchViews` enum**
```swift
// DynamicIsland/enums/generic.swift
public enum NotchViews {
    // ... existing
    case battery // Add this
}
```

- [ ] **Step 2: Add `enableBatteryTab` to Defaults**
```swift
// DynamicIsland/models/Constants.swift
extension Defaults.Keys {
    static let enableBatteryTab = Key<Bool>("enableBatteryTab", default: true)
}
```

- [ ] **Step 3: Update `TabOrder` in Coordinator**
```swift
// DynamicIsland/DynamicIslandViewCoordinator.swift
private static let tabOrder: [NotchViews] = [.home, .shelf, .battery, .timer, .stats, ...]
```

- [ ] **Step 4: Register Battery Tab in `TabManager`**
```swift
// DynamicIsland/managers/TabManager.swift
if Defaults[.enableBatteryTab] {
    tabsArray.append(TabModel(label: "Battery", icon: "battery.100.bolt", view: .battery))
}
```

- [ ] **Step 5: Commit infrastructure changes**
```bash
git add DynamicIsland/enums/generic.swift DynamicIsland/models/Constants.swift DynamicIsland/DynamicIslandViewCoordinator.swift DynamicIsland/managers/TabManager.swift
git commit -m "chore: add battery tab infrastructure"
```

---

### Task 2: Create Battery Tile Component

**Files:**
- Create: `DynamicIsland/components/Notch/BatteryTileView.swift`

- [ ] **Step 1: Implement `BatteryTileView`**
Create a reusable tile that shows icon, name, and percentage. Reuse `BatteryView` from `DynamicIslandBattery.swift`. Use `parallax3D()` and `bouncingButton()` for consistency.

- [ ] **Step 2: Commit Tile component**
```bash
git add DynamicIsland/components/Notch/BatteryTileView.swift
git commit -m "feat: add BatteryTileView component"
```

---

### Task 3: Create Main Battery Tab View

**Files:**
- Create: `DynamicIsland/components/Notch/NotchBatteryView.swift`

- [ ] **Step 1: Implement `NotchBatteryView`**
Create a view that observes `BatteryStatusViewModel` and `BluetoothAudioManager`. Use `LazyVGrid` to display tiles. Handle the "MacBook" tile and loop through `bluetoothAudioManager.connectedDevices`.

- [ ] **Step 2: Commit Battery view**
```bash
git add DynamicIsland/components/Notch/NotchBatteryView.swift
git commit -m "feat: add NotchBatteryView container"
```

---

### Task 4: Integrate into ContentView & Sizing

**Files:**
- Modify: `DynamicIsland/ContentView.swift`

- [ ] **Step 1: Add `.battery` case to View Switcher**
```swift
// Inside switch coordinator.currentView
case .battery:
    NotchBatteryView()
```

- [ ] **Step 2: Add sizing logic for Battery tab**
Ensure `dynamicNotchSize` returns a height that fits the grid (approx 220-250pt).

- [ ] **Step 3: Commit integration**
```bash
git add DynamicIsland/ContentView.swift
git commit -m "feat: integrate battery tab into ContentView"
```

---

### Task 5: Verification & Cleanup

- [ ] **Step 1: Verify on Mac**
Open the notch, switch to the new Battery tab. Verify Mac and Bluetooth devices show up.
- [ ] **Step 2: Verify Animations**
Check if switching to/from Battery tab uses `blurReplace` and correct sizing animation.
