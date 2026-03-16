--[[
    KOReader Patch — main.lua
    Plugin entry point. Uses WidgetContainer as the base class (safe across
    all KOReader versions). Hooks into FileManager startup and adds a
    "KOReader Patch" sub-menu to the main ☰ menu.
--]]

-- ── Package path: ensure homescreen.lua can always be found ───────────────────
-- KOReader's async scheduler can lose the plugin dir from package.path, so we
-- pin it explicitly using the path of *this* file.
local _src = debug.getinfo(1, "S").source
local _dir = _src:match("^@?(.+)/[^/]*$") or "."
if not package.path:find(_dir, 1, true) then
    package.path = _dir .. "/?.lua;" .. package.path
end

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager       = require("ui/uimanager")
local _               = require("gettext")

local KOReaderPatch = WidgetContainer:extend{
    name     = "koreader-patch",
    fullname = "KOReader Patch",
}

-- ── init ─────────────────────────────────────────────────────────────────────
function KOReaderPatch:init()
    -- Guard: only run once.
    if self._ready then return end
    self._ready = true

    -- Only run in the FileManager context.
    -- ReaderUI always has self.ui.document (the open book object).
    -- FileManager never has it. This is the most reliable way to distinguish
    -- the two contexts — more reliable than checking for file_chooser, which
    -- may not be assigned yet when plugins are initialised.
    if not self.ui then return end
    if self.ui.document then return end  -- we're inside a book, skip
    if not self.ui.menu   then return end  -- no menu to attach to, skip

    self.ui.menu:registerToMainMenu(self)

    -- Auto-show on startup (deferred so FileManager finishes its own init first)
    UIManager:scheduleIn(0, function()
        if self:_autoshow() then
            self:showHomeScreen()
        end
    end)
end

-- ── Main menu entry ───────────────────────────────────────────────────────────
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

-- ── Show home screen ──────────────────────────────────────────────────────────
function KOReaderPatch:showHomeScreen()
    -- Use pcall so any error in homescreen.lua surfaces as a readable message
    -- rather than silently crashing.
    local ok, result = pcall(require, "homescreen")
    if not ok then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = "KOReader Patch — failed to load home screen:\n\n" .. tostring(result),
        })
        return
    end
    UIManager:show(result:new{
        plugin      = self,
        filemanager = self.ui,
    })
end

-- ── Persistent settings ───────────────────────────────────────────────────────
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
