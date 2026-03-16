-- main.lua — KOReader Patch
-- Plugin entry point. Minimal version for debugging.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger          = require("logger")
local _               = require("gettext")

local KOReaderPatch = WidgetContainer:new{
    name     = "koreader-patch",
    fullname = _("KOReader Patch"),
}

function KOReaderPatch:init()
    logger.info("koreader-patch: init called")

    -- Register menu only — no auto-show, no homescreen loading.
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
                callback = function()
                    local UIManager = require("ui/uimanager")
                    local InfoMessage = require("ui/widget/infomessage")
                    UIManager:show(InfoMessage:new{
                        text = "KOReader Patch is alive!",
                    })
                end,
            },
        },
    }
end

return KOReaderPatch
