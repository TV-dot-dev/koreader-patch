-- main.lua — KOReader Patch
-- Plugin entry point.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager       = require("ui/uimanager")
local logger          = require("logger")
local _               = require("gettext")

local KOReaderPatch = WidgetContainer:new{
    name     = "koreader-patch",
    fullname = _("KOReader Patch"),
}

function KOReaderPatch:init()
    local ok, err = pcall(function()
        self.ui.menu:registerToMainMenu(self)
    end)
    if not ok then
        logger.warn("koreader-patch: menu registration failed:", tostring(err))
    end
end

function KOReaderPatch:addToMainMenu(menu_items)
    menu_items.koreader_patch = {
        text = _("KOReader Patch"),
        sub_item_table = {
            {
                text     = _("Open Home Screen"),
                callback = function() self:showHomeScreen() end,
            },
        },
    }
end

function KOReaderPatch:showHomeScreen()
    local ok, HomeScreen = pcall(require, "homescreen")
    if not ok then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = "Failed to load homescreen:\n\n" .. tostring(HomeScreen),
        })
        return
    end
    local ok2, err2 = pcall(function()
        UIManager:show(HomeScreen:new{
            plugin      = self,
            filemanager = self.ui,
        })
    end)
    if not ok2 then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = "Failed to show homescreen:\n\n" .. tostring(err2),
        })
    end
end

return KOReaderPatch
