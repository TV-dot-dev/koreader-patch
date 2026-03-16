-- main.lua — KOReader Patch
-- Plugin entry point. Registers the plugin and shows a custom home screen.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager       = require("ui/uimanager")
local logger          = require("logger")
local _               = require("gettext")

local KOReaderPatch = WidgetContainer:new{
    name     = "koreader-patch",
    fullname = _("KOReader Patch"),
}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function KOReaderPatch:init()
    local ok, err = pcall(function()
        -- Skip if we're inside a book (ReaderUI context).
        if self.ui and self.ui.document then return end

        self.ui.menu:registerToMainMenu(self)

        -- Auto-show on startup (deferred so FileManager finishes init first)
        if self:_autoshow() then
            UIManager:scheduleIn(0, function()
                self:showHomeScreen()
            end)
        end
    end)
    if not ok then logger.err("koreader-patch: init failed:", tostring(err)) end
end

-- ---------------------------------------------------------------------------
-- Main menu entry
-- ---------------------------------------------------------------------------

function KOReaderPatch:addToMainMenu(menu_items)
    menu_items.koreader_patch = {
        text = _("KOReader Patch"),
        sub_item_table = {
            {
                text     = _("Open Home Screen"),
                callback = function() self:showHomeScreen() end,
            },
            {
                text         = _("Show Home Screen on startup"),
                checked_func = function() return self:_autoshow() end,
                callback     = function()
                    local s = self:_settings()
                    if s then
                        s:saveSetting("autoshow", not self:_autoshow())
                        s:flush()
                    end
                end,
            },
        },
    }
end

-- ---------------------------------------------------------------------------
-- Show home screen
-- ---------------------------------------------------------------------------

function KOReaderPatch:showHomeScreen()
    local ok, result = pcall(require, "homescreen")
    if not ok then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = "KOReader Patch — failed to load home screen:\n\n"
                   .. tostring(result),
        })
        return
    end
    UIManager:show(result:new{
        plugin      = self,
        filemanager = self.ui,
    })
end

-- ---------------------------------------------------------------------------
-- Persistent settings
-- ---------------------------------------------------------------------------

function KOReaderPatch:_settings()
    if self._s then return self._s end
    local ok1, LuaSettings = pcall(require, "luasettings")
    local ok2, DataStorage  = pcall(require, "datastorage")
    if ok1 and ok2 then
        self._s = LuaSettings:open(
            DataStorage:getSettingsDir() .. "/koreader-patch.lua"
        )
    end
    return self._s
end

function KOReaderPatch:_autoshow()
    local s = self:_settings()
    if not s then return true end
    local v = s:readSetting("autoshow")
    return (v == nil) and true or v
end

return KOReaderPatch
