--[[
    KOReader Patch — main.lua
    Plugin entry point. Hooks into FileManager startup and registers
    menu items under the main KOReader menu.
--]]

local Plugin          = require("Plugin")
local UIManager       = require("ui/uimanager")
local LuaSettings     = require("luasettings")
local DataStorage     = require("datastorage")
local _               = require("gettext")

local KOReaderPatch = Plugin:extend{
    name         = "koreader-patch",
    fullname     = "KOReader Patch",
    description  = "Refined home screen with tab navigation",
    version      = 1,
    is_doc_only  = false,
}

-- ── init ─────────────────────────────────────────────────────────────────────
function KOReaderPatch:init()
    -- Persistent settings (stored in koreader/settings/koreader-patch.lua)
    self.settings = LuaSettings:open(
        DataStorage:getSettingsDir() .. "/koreader-patch.lua"
    )

    self.ui.menu:registerToMainMenu(self)

    -- Auto-show on startup only when the setting is on (default: on)
    if self:_autoshow() then
        UIManager:scheduleIn(0, function()
            self:showHomeScreen()
        end)
    end
end

-- ── Menu ─────────────────────────────────────────────────────────────────────
function KOReaderPatch:addToMainMenu(menu_items)
    menu_items.koreader_patch = {
        text = _("KOReader Patch"),
        sub_item_table = {
            {
                text     = _("Open Home Screen"),
                callback = function()
                    self:showHomeScreen()
                end,
            },
            {
                text           = _("Show Home Screen on startup"),
                checked_func   = function() return self:_autoshow() end,
                callback       = function()
                    self.settings:saveSetting("autoshow", not self:_autoshow())
                    self.settings:flush()
                end,
            },
        },
    }
end

-- ── Helpers ───────────────────────────────────────────────────────────────────
function KOReaderPatch:_autoshow()
    -- Default to true (on) when the setting has never been saved
    local v = self.settings:readSetting("autoshow")
    if v == nil then return true end
    return v
end

function KOReaderPatch:showHomeScreen()
    local HomeScreen = require("homescreen")
    UIManager:show(HomeScreen:new{
        plugin      = self,
        filemanager = self.ui,
    })
end

return KOReaderPatch
