# <span><img src="../logo.png" alt="Azul Logo" height="30"></span> Azul Companion Plugin

## Installation

### Method 1: Auto-Install (Recommended)

- Install the plugin automatically using the Roblox Plugin Marketplace: https://create.roblox.com/store/asset/79510309341601/Azul-Companion-Plugin

> [!WARNING]
> The manual methods don't receive automatic updates. You will need to repeat your preferred manual installation steps to update the plugin.

### Method 2: Manual Install via Place File

1. Download the source code from the [Azul Companion Plugin](https://www.roblox.com/games/132762411481199/Azul-Companion-Plugin) game: (3 dots -> "Download")
2. Open the downloaded `.rbxlx` or `.rbxl` file in Roblox Studio
3. Right-click the `AzulPlugin` folder in `ServerStorage` and select **"Save as Local Plugin"**
4. Restart Roblox Studio
5. The Azul icon should now appear in the toolbar

### Method 3: Raw Manual Install

This method involves manually adding the plugin scripts to Roblox Studio. Sadly, there is no streamlined way to "build" Roblox plugins (`.rbxm`/`.rbxmx` files) from source code, so you'll have to recreate the plugin structure manually:

1. Open Roblox Studio
2. Create a folder named "`AzulPlugin`" in `ServerStorage`
3. In this folder, recreate the 2 scripts found in the `/plugin` folder of this repository:
   - `AzulSync.luau`
   - `WebSocketClient.luau`
4. Right-click the `AzulPlugin` folder and select **"Save as Local Plugin"**
5. Restart Roblox Studio
6. The Azul icon should now appear in the toolbar

## Troubleshooting

### Plugin not connecting

- Ensure the daemon is running (run `azul`)
- Check that `HttpService` is enabled:
  - Go to **Home** → **Game Settings** → **Security**
  - Enable **"Allow HTTP Requests"**
- Verify firewall isn't blocking port 8080

### Scripts not syncing

- Click "Toggle Sync" to reconnect
- Check the Output window for error messages
- Restart both the daemon and Studio

### Clearing GUIDs

In the rare case where you're getting GUID conflicts, or simply don't wish to keep existing GUIDs, you can clear all `AzulSyncGUID` attributes by running the following code in the Command Bar:

```lua
-- Run this in the Command Bar
for _, desc in ipairs(game:GetDescendants()) do
    if desc:GetAttribute("AzulSyncGUID") then
        desc:SetAttribute("AzulSyncGUID", nil)
    end
end
```
