# Login Item Helper Setup (macOS)

This project includes a minimal helper app that can be used as a Login Item for "Start at Login" functionality.

## 1) Create a new target
- In Xcode, add a new macOS App target.
- Name it `LoginItemHelper`.
- Set the bundle identifier to something like `com.yourcompany.YourApp-LoginItem`.
- Uncheck "Create Document-based app"; keep it simple.

## 2) Replace target files
- Replace the target's AppDelegate/App files with the files in the `LoginItemHelper/` folder:
  - `main.swift`
  - `HelperInfo.plist`
  - `Helper.entitlements`
- In the target's Build Settings:
  - Set `INFOPLIST_FILE` to `LoginItemHelper/HelperInfo.plist`.
  - Set `CODE_SIGN_ENTITLEMENTS` to `LoginItemHelper/Helper.entitlements`.

## 3) Configure sandbox and background mode
- Ensure the helper target is sandboxed and has no UI (LSBackgroundOnly and LSUIElement are set in the Info.plist).

## 4) Embed the helper in the main app
- In the main app target's Build Phases, add a "Copy Files" phase:
  - Destination: `Wrapper`
  - Subpath: `Library/LoginItems`
  - Add the `LoginItemHelper.app` product from the helper target.

## 5) Set the identifier in the main app
- In the main app target's Info.plist, add:
  - Key: `LoginItemBundleIdentifier`
  - Value: the helper's bundle identifier (e.g., `com.yourcompany.YourApp-LoginItem`).

## 6) Use SMAppService
- The `SettingsStore.apply()` method already calls:
  ```swift
  let service = SMAppService.loginItem(identifier: identifier)
  try service.register() // or unregister()
