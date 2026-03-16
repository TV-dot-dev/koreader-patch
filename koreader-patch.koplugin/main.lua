-- main.lua — KOReader Patch
-- Minimal test: show a fullscreen widget directly from main.lua.
-- No separate files, no external requires beyond core KOReader modules.

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
    local Blitbuffer      = require("ffi/blitbuffer")
    local Device          = require("device")
    local Screen          = Device.screen
    local Geom            = require("ui/geometry")
    local Font            = require("ui/font")
    local InputContainer  = require("ui/widget/container/inputcontainer")
    local FrameContainer  = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local TextWidget      = require("ui/widget/textwidget")
    local Button          = require("ui/widget/button")
    local VerticalGroup   = require("ui/widget/verticalgroup")

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()

    local widget = InputContainer:new{
        name              = "KPatchHome",
        covers_fullscreen = true,
        dimen             = Geom:new{ w = sw, h = sh },
    }

    -- Back button key event
    widget.key_events = { Back = { {"Back"}, action = "back" } }

    widget[1] = FrameContainer:new{
        width      = sw,
        height     = sh,
        bordersize = 0,
        padding    = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = sw, h = sh },
            VerticalGroup:new{
                align = "center",
                TextWidget:new{
                    text = "Hello from KOReader Patch!",
                    face = Font:getFace("cfont", 20),
                },
                Button:new{
                    text     = "Close",
                    callback = function()
                        UIManager:close(widget)
                    end,
                },
            },
        },
    }

    function widget:onBack()
        UIManager:close(self)
        return true
    end

    -- Swallow all taps so they don't pass through to file browser
    function widget:onTap() return true end
    function widget:onSwipe() return true end

    UIManager:show(widget)
    UIManager:setDirty(widget, "full")
end

return KOReaderPatch
