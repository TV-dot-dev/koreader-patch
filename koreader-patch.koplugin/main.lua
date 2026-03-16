--[[
    KOReader Patch — main.lua
    Plugin entry point. Hooks into FileManager startup and registers
    a "Home Screen" menu item under the main KOReader menu.
--]]

local Plugin     = require("Plugin")
local UIManager  = require("ui/uimanager")
local _          = require("gettext")

local KOReaderPatch = Plugin:extend{
    name         = "koreader-patch",
    fullname     = "KOReader Patch",
    description  = "Refined home screen with tab navigation",
    version      = 1,
    is_doc_only  = false,   -- runs in both FileManager and Reader contexts
}

-- Called once when the plugin loads in FileManager context.
function KOReaderPatch:init()
    -- Register menu item so the user can re-open the home screen at any time.
    self.ui.menu:registerToMainMenu(self)

    -- Show the home screen automatically on first startup.
    -- scheduleIn(0) defers until after FileManager finishes its own init().
    UIManager:scheduleIn(0, function()
        self:showHomeScreen()
    end)
end

-- Adds "Home Screen" to KOReader's main ☰ menu.
function KOReaderPatch:addToMainMenu(menu_items)
    menu_items.koreader_patch_home = {
        text     = _("Home Screen"),
        callback = function()
            self:showHomeScreen()
        end,
    }
end

-- Lazily creates and shows the HomeScreen widget.
function KOReaderPatch:showHomeScreen()
    -- Always create fresh so data (history, stats) is current.
    local HomeScreen = require("homescreen")
    local screen = HomeScreen:new{
        plugin     = self,
        filemanager = self.ui,
    }
    UIManager:show(screen)
end

return KOReaderPatch
