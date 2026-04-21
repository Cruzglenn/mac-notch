# Spec: Atoll Power Center (Battery Tab)

## 1. Overview
The "Power Center" is a dedicated tab within the Atoll Dynamic Island that provides a centralized view of battery status for the Mac and all connected Bluetooth peripherals. It focuses on high-quality visuals, real-time updates, and 100% consistency with existing Atoll animations.

## 2. User Experience
- **Access:** Users switch to the "Battery" tab via the existing Tab Bar in the expanded Notch.
- **Content:** A grid-based layout showing:
  - Internal Mac battery (with charging/plugged-in indicators).
  - Connected AirPods/Beats (using specific icons from `BluetoothAudioDeviceType`).
  - Other Bluetooth peripherals (Mouse, Keyboard, etc.).
- **Feedback:** Hovering over a device tile triggers a subtle scale/highlight effect. Clicking might open system Battery/Bluetooth settings (consistent with existing popover behaviors).

## 3. Technical Design

### 3.1 Data Sources
- **System Battery:** `MacBatteryManager.shared` (already exists).
- **Bluetooth Peripherals:** `BluetoothAudioManager.shared.connectedDevices` (already exists).
- **ViewModel:** `DynamicIslandViewModel` will manage the active tab state.

### 3.2 UI Components
- **`NotchBatteryView.swift`:**
  - Main container using `Group` and `transition(.opacity.combined(with: .blurReplace))`.
  - Layout: `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())])` to display device tiles.
- **`BatteryTileView.swift`:**
  - A small card with `RoundedRectangle` background (matching Atoll's `2c2c2e` style).
  - Displays SF Symbol, Name, and Percentage.
  - Integration with `BatteryView` (reusing the existing battery bar component).

### 3.3 Integration Points
- **`TabManager.swift` / `TabSelectionView.swift`:** Add a new `.battery` case to the tab enumeration.
- **`NotchHomeView.swift`:** Add a switch case to render `NotchBatteryView` when the battery tab is selected.
- **`DynamicIslandViewCoordinator.swift`:** Ensure sizing logic accounts for the battery grid height.

## 4. Animations & Styles
- **Transitions:** Must use `blurReplace` for content switching.
- **Feedback:** Use `Button+Bouncing` and `parallax3D()` modifiers on tiles.
- **Colors:** Green (>20% or charging), Yellow (Low Power Mode), Red (<20% & not charging).

## 5. Success Criteria
- [ ] Battery tab icon appears in the Notch tab bar.
- [ ] Selecting the tab shows Mac battery and at least one connected BT device (if any).
- [ ] Animations are fluid and match the Music/Calendar tabs.
- [ ] No regressions in Notch resizing logic.
