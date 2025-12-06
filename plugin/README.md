# Roblox Studio Plugin Installation

## Method 1: Auto-Install (Recommended)

1. Open Roblox Studio
2. Go to **Plugins** → **Plugins Folder**
3. Copy the entire `plugin` folder to the opened location
4. Restart Roblox Studio

## Method 2: Manual Install

1. Locate your Roblox Studio plugins directory:

   - **Windows**: `%LOCALAPPDATA%\Roblox\Plugins`
   - **macOS**: `~/Documents/Roblox/Plugins`

2. Copy `SuperStudioSync.lua` to the plugins directory

3. Restart Roblox Studio

## Usage

1. **Start the sync daemon** on your computer:

   ```bash
   npm run dev
   ```

2. In Roblox Studio, click the **"Toggle Sync"** button in the toolbar

3. The plugin will:

   - Scan all scripts in your game
   - Assign GUIDs to track instances
   - Send a full snapshot to the daemon
   - Begin live syncing

4. Edit scripts either in Studio or your local files - changes sync automatically!

## Troubleshooting

### Plugin not connecting

- Ensure the daemon is running (`npm run dev`)
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
    if desc:GetAttribute("StudioSyncGUID") then
        desc:SetAttribute("StudioSyncGUID", nil)
    end
end
```

## Features

- ✅ **Real-time sync**: Changes in Studio instantly update files
- ✅ **Bi-directional**: Edit files externally and see changes in Studio
- ✅ **Automatic GUID tracking**: Never manually manage instance IDs
- ✅ **Reconnect support**: Automatically reconnects if daemon restarts
- ✅ **Safe syncing**: Only syncs scripts, not the entire DataModel

## Limitations

⚠️ **Note**: Roblox Studio doesn't support native WebSockets. This plugin uses HttpService with a polling mechanism. For the best experience:

- Keep HttpService enabled
- The daemon must be running on localhost
- Network latency may cause slight delays

For production use, consider implementing a proper WebSocket library or Roblox-compatible transport layer.
