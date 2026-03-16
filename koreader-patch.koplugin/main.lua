--[[
    KOReader Patch — main.lua
    Plugin entry point. Uses WidgetContainer as the base class (safe across
    all KOReader versions). Hooks into FileManager startup and adds a
    "KOReader Patch" sub-menu to the main ☰ menu.
--]]

-- Resolve this plugin's directory from the source path of this file.
-- Used to loadfile() homescreen.lua without polluting global package.path.
local _plugin_dir = debug.getinfo(1, "S").source:match("^@?(.+)/[^/]*$") or "."

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
-- Cache the loaded HomeScreen class so we only loadfile() once.
local _HomeScreen

function KOReaderPatch:showHomeScreen()
    if not _HomeScreen then
        -- Use the plugin's own directory (self.path is set by KOReader, fall
        -- back to the path we resolved at load time).
        local dir = self.path or _plugin_dir
        local path = dir .. "/homescreen.lua"
        local chunk, load_err = loadfile(path)
        if not chunk then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = "KOReader Patch — cannot load homescreen.lua:\n\n"
                       .. tostring(load_err),
            })
            return
        end
        local ok, result = pcall(chunk)
        if not ok then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = "KOReader Patch — error in homescreen.lua:\n\n"
                       .. tostring(result),
            })
            return
        end
        _HomeScreen = result
    end
    UIManager:show(_HomeScreen:new{
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
