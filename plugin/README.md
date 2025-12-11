# <span><img src="../logo.png" alt="Azul Logo" height="30"></span> Azul Companion Plugin

## Installation

### Method 1: Auto-Install (Recommended)

- Install the plugin automatically using the Roblox Plugin Marketplace: https://create.roblox.com/store/asset/79510309341601/Azul-Companion-Plugin

### Method 2: Manual Install

1. Open Roblox Studio
2. Go to **Plugins** → **Plugins Folder**
3. Copy the entire `plugin` folder to the opened location
4. Restart Roblox Studio

## Troubleshooting

### Plugin not connecting

- Ensure the daemon is running (run `azul`)
- Check that HttpService is enabled:
  - Go to **Home** → **Game Settings** → **Security**
  - Enable **"Allow HTTP Requests"**
- Verify firewall isn't blocking port 8080

### Scripts not syncing

- Click "Toggle Sync" to reconnect
- Check the Output window for error messages
- Restart both the daemon and Studio

### GUID conflicts

If you're getting GUID conflicts, clear all GUIDs:

```lua
-- Run this in the Command Bar
for _, desc in ipairs(game:GetDescendants()) do
    if desc:GetAttribute("AzulSyncGUID") then
        desc:SetAttribute("AzulSyncGUID", nil)
    end
end
```
