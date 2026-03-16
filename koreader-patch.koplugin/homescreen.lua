-- homescreen.lua — KOReader Patch
-- Full-screen HomeScreen widget with tab navigation.
-- ALL layout computation deferred to init() — nothing runs at module load time
-- except require() calls for core KOReader modules.

local Button          = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer  = require("ui/widget/container/inputcontainer")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local _               = require("gettext")

local TABS = {
    { id = "home",    label = "Home"    },
    { id = "library", label = "Library" },
    { id = "files",   label = "Files"   },
    { id = "goals",   label = "Goals"   },
    { id = "more",    label = "More"    },
}

local function lazy(mod)
    local ok, m = pcall(require, mod)
    return ok and m or nil
end

-- ---------------------------------------------------------------------------
-- HomeScreen class
-- ---------------------------------------------------------------------------
local HomeScreen = InputContainer:extend{
    name              = "HomeScreen",
    covers_fullscreen = true,
    current_tab       = "home",
    tab_pages         = {},
}

function HomeScreen:init()
    local Screen = Device.screen
    local Blitbuffer = require("ffi/blitbuffer")

    -- Layout constants
    self._S = Screen
    self._BB = Blitbuffer
    self._C = {
        paper    = Blitbuffer.gray(0.96),
        surface  = Blitbuffer.COLOR_WHITE,
        border   = Blitbuffer.gray(0.80),
        tabBg    = Blitbuffer.gray(0.90),
        statusBg = Blitbuffer.gray(0.92),
        black    = Blitbuffer.COLOR_BLACK,
        dim      = Blitbuffer.gray(0.45),
    }
    self._STATUS_H = Screen:scaleBySize(28)
    self._TAB_H    = Screen:scaleBySize(52)
    self._PAGER_H  = Screen:scaleBySize(28)
    self._PAD      = Screen:scaleBySize(14)
    self._ROW_H    = Screen:scaleBySize(44)
    self._DIV_H    = Screen:scaleBySize(1)

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    self.dimen = Geom:new{ w = sw, h = sh }

    for _, t in ipairs(TABS) do
        self.tab_pages[t.id] = { page = 1, total = 1 }
    end

    self.key_events = { Back = { {"Back"}, action = "back" } }
    self:_build()
    UIManager:setDirty(self, "full")
end

function HomeScreen:_F(size)
    return Font:getFace("cfont", size)
end

function HomeScreen:_divider(width)
    return FrameContainer:new{
        width      = width,
        height     = self._DIV_H,
        bordersize = 0,
        background = self._C.border,
    }
end

function HomeScreen:onBack()
    UIManager:close(self)
    return true
end

function HomeScreen:switchTab(id)
    if id == "files" then
        UIManager:close(self)
        return
    end
    self.current_tab = id
    self.tab_pages[id].page = 1
    self:_build()
    UIManager:setDirty(self, "ui")
end

function HomeScreen:changePage(delta)
    local ps = self.tab_pages[self.current_tab]
    local np = ps.page + delta
    if np < 1 or np > ps.total then return end
    ps.page = np
    self:_build()
    UIManager:setDirty(self, "ui")
end

-- ── Build ─────────────────────────────────────────────────────────────────────
function HomeScreen:_build()
    local Screen = self._S
    local C = self._C
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local ps = self.tab_pages[self.current_tab]
    local show_pager = ps.total > 1
    local content_h  = sh - self._STATUS_H - self._TAB_H
                       - (show_pager and self._PAGER_H or 0)

    local layout = VerticalGroup:new{ align = "left" }
    layout[#layout+1] = self:_statusBar(sw)
    layout[#layout+1] = self:_contentArea(sw, content_h)
    if show_pager then
        layout[#layout+1] = self:_pagerBar(sw)
    end
    layout[#layout+1] = self:_tabBar(sw)

    self[1] = FrameContainer:new{
        width      = sw,
        height     = sh,
        bordersize = 0,
        padding    = 0,
        background = C.paper,
        layout,
    }
end

-- ── Status bar ────────────────────────────────────────────────────────────────
function HomeScreen:_statusBar(sw)
    local C = self._C
    local time = os.date("%H:%M")
    local date = os.date("%a %d %b")
    local batt = ""
    if Device:hasBattery() then
        local ok, pd = pcall(function() return Device:getPowerDevice() end)
        if ok and pd then
            local ok2, cap = pcall(function() return pd:getCapacity() end)
            if ok2 then batt = "  ·  " .. cap .. "%" end
        end
    end

    return FrameContainer:new{
        width      = sw,
        height     = self._STATUS_H,
        bordersize = 0,
        padding    = 0,
        background = C.statusBg,
        CenterContainer:new{
            dimen = Geom:new{ w = sw, h = self._STATUS_H },
            TextWidget:new{
                text    = time .. "  ·  " .. date .. batt,
                face    = self:_F(11),
                fgcolor = C.dim,
            },
        },
    }
end

-- ── Content area ──────────────────────────────────────────────────────────────
function HomeScreen:_contentArea(sw, h)
    local C = self._C
    local PAD = self._PAD
    local inner_w = sw - PAD * 2
    local view
    if     self.current_tab == "home"    then view = self:_homeView(inner_w, h)
    elseif self.current_tab == "library" then view = self:_libraryView(inner_w, h)
    elseif self.current_tab == "goals"   then view = self:_goalsView(inner_w, h)
    elseif self.current_tab == "more"    then view = self:_moreView(inner_w, h)
    else   view = TextWidget:new{ text = "", face = self:_F(12) }
    end

    return FrameContainer:new{
        width          = sw,
        height         = h,
        bordersize     = 0,
        padding_left   = PAD,
        padding_right  = PAD,
        padding_top    = PAD,
        padding_bottom = 0,
        background     = C.paper,
        view,
    }
end

-- ── Pager bar ─────────────────────────────────────────────────────────────────
function HomeScreen:_pagerBar(sw)
    local C = self._C
    local ps   = self.tab_pages[self.current_tab]
    local col3 = math.floor(sw / 3)

    return FrameContainer:new{
        width      = sw,
        height     = self._PAGER_H,
        bordersize = 0,
        padding    = 0,
        background = C.tabBg,
        HorizontalGroup:new{
            align = "center",
            Button:new{
                text       = "← Prev",
                width      = col3,
                height     = self._PAGER_H,
                bordersize = 0,
                margin     = 0,
                padding    = 0,
                background = C.tabBg,
                enabled    = ps.page > 1,
                callback   = function() self:changePage(-1) end,
            },
            CenterContainer:new{
                dimen = Geom:new{ w = col3, h = self._PAGER_H },
                TextWidget:new{
                    text    = ps.page .. " / " .. ps.total,
                    face    = self:_F(11),
                    fgcolor = C.dim,
                },
            },
            Button:new{
                text       = "Next →",
                width      = col3,
                height     = self._PAGER_H,
                bordersize = 0,
                margin     = 0,
                padding    = 0,
                background = C.tabBg,
                enabled    = ps.page < ps.total,
                callback   = function() self:changePage(1) end,
            },
        },
    }
end

-- ── Tab bar ───────────────────────────────────────────────────────────────────
function HomeScreen:_tabBar(sw)
    local Screen = self._S
    local C = self._C
    local tab_w = math.floor(sw / #TABS)
    local row   = HorizontalGroup:new{ align = "left" }
    for _, tab in ipairs(TABS) do
        local active = (tab.id == self.current_tab)
        row[#row+1] = Button:new{
            text           = tab.label,
            width          = tab_w,
            height         = self._TAB_H,
            margin         = 0,
            bordersize     = 0,
            padding        = 0,
            background     = active and C.surface or C.tabBg,
            text_font_face = "cfont",
            text_font_size = Screen:scaleBySize(12),
            text_font_bold = active,
            callback       = function() self:switchTab(tab.id) end,
        }
    end
    return FrameContainer:new{
        width      = sw,
        height     = self._TAB_H,
        bordersize = 0,
        padding    = 0,
        background = C.tabBg,
        VerticalGroup:new{
            align = "left",
            self:_divider(sw),
            row,
        },
    }
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  VIEW: HOME
-- ═══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_homeView(w, h)
    local Screen = self._S
    local C = self._C
    local vg = VerticalGroup:new{ align = "left" }

    -- Greeting
    local hour = tonumber(os.date("%H"))
    local greeting = hour < 12 and "Good morning."
                  or hour < 18 and "Good afternoon."
                  or                "Good evening."
    vg[#vg+1] = TextWidget:new{
        text    = greeting,
        face    = Font:getFace("tfont", Screen:scaleBySize(18)),
        fgcolor = C.black,
    }
    vg[#vg+1] = TextWidget:new{
        text    = os.date("%A, %d %B %Y"),
        face    = self:_F(12),
        fgcolor = C.dim,
    }
    vg[#vg+1] = self:_divider(w)

    -- Currently reading
    local ReadHistory = lazy("readhistory")
    local hist = {}
    if ReadHistory then
        pcall(function() ReadHistory:reload() end)
        hist = ReadHistory.hist or {}
    end

    if hist[1] then
        local item  = hist[1]
        local title = item.text or "Unknown title"
        local pct   = 0

        local DocSettings = lazy("docsettings")
        if DocSettings and item.file then
            pcall(function()
                local ds = DocSettings:open(item.file)
                if ds then
                    pct = math.floor((ds:readSetting("percent_finished") or 0) * 100)
                end
            end)
        end

        vg[#vg+1] = FrameContainer:new{
            width        = w,
            bordersize   = self._DIV_H,
            border_color = C.border,
            background   = C.surface,
            padding      = Screen:scaleBySize(10),
            VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = "Currently reading", face = self:_F(10), fgcolor = C.dim },
                TextWidget:new{
                    text      = title,
                    face      = self:_F(14),
                    fgcolor   = C.black,
                    bold      = true,
                    max_width = w - Screen:scaleBySize(20),
                },
                TextWidget:new{
                    text    = pct .. "% complete",
                    face    = self:_F(11),
                    fgcolor = C.dim,
                },
                Button:new{
                    text       = "Continue reading",
                    width      = w - Screen:scaleBySize(20),
                    height     = self._ROW_H,
                    bordersize = self._DIV_H,
                    background = C.paper,
                    callback   = function()
                        if item.file then
                            UIManager:close(self)
                            local ReaderUI = package.loaded["apps/reader/readerui"]
                                or require("apps/reader/readerui")
                            ReaderUI:showReader(item.file)
                        end
                    end,
                },
            },
        }
    else
        vg[#vg+1] = CenterContainer:new{
            dimen = Geom:new{ w = w, h = Screen:scaleBySize(80) },
            TextWidget:new{
                text    = "No books opened yet.  Browse Files to start.",
                face    = self:_F(13),
                fgcolor = C.dim,
            },
        }
    end

    -- Recent list
    if #hist > 1 then
        vg[#vg+1] = TextWidget:new{
            text    = "Recent",
            face    = self:_F(10),
            fgcolor = C.dim,
        }
        for i = 2, math.min(#hist, 5) do
            local item = hist[i]
            vg[#vg+1] = Button:new{
                text           = item.text or "Unknown",
                width          = w,
                height         = self._ROW_H,
                bordersize     = 0,
                margin         = 0,
                padding        = 0,
                background     = C.paper,
                text_font_face = "cfont",
                text_font_size = Screen:scaleBySize(13),
                align          = "left",
                callback       = function()
                    if item.file then
                        UIManager:close(self)
                        local ReaderUI = package.loaded["apps/reader/readerui"]
                            or require("apps/reader/readerui")
                        ReaderUI:showReader(item.file)
                    end
                end,
            }
            vg[#vg+1] = self:_divider(w)
        end
    end

    return vg
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  VIEW: LIBRARY
-- ═══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_libraryView(w, h)
    local Screen = self._S
    local C = self._C
    local ReadHistory = lazy("readhistory")
    local hist = {}
    if ReadHistory then
        pcall(function() ReadHistory:reload() end)
        hist = ReadHistory.hist or {}
    end

    local rows_pp = math.max(1, math.floor((h - self._PAD) / self._ROW_H))
    local ps      = self.tab_pages["library"]
    ps.total      = math.max(1, math.ceil(#hist / rows_pp))
    local offset  = (ps.page - 1) * rows_pp

    local vg = VerticalGroup:new{ align = "left" }
    vg[#vg+1] = TextWidget:new{
        text    = "Library  —  " .. #hist .. " books",
        face    = self:_F(12),
        fgcolor = C.dim,
    }
    vg[#vg+1] = self:_divider(w)

    if #hist == 0 then
        vg[#vg+1] = CenterContainer:new{
            dimen = Geom:new{ w = w, h = h - Screen:scaleBySize(40) },
            TextWidget:new{
                text    = "Your library is empty.\nOpen a book via Files to get started.",
                face    = self:_F(13),
                fgcolor = C.dim,
            },
        }
        return vg
    end

    local DocSettings = lazy("docsettings")
    for i = offset + 1, math.min(offset + rows_pp, #hist) do
        local item = hist[i]
        local pct  = 0
        if DocSettings and item.file then
            pcall(function()
                local ds = DocSettings:open(item.file)
                if ds then
                    pct = math.floor((ds:readSetting("percent_finished") or 0) * 100)
                end
            end)
        end
        vg[#vg+1] = Button:new{
            text           = (item.text or "Unknown") .. "  [" .. pct .. "%]",
            width          = w,
            height         = self._ROW_H,
            bordersize     = 0,
            margin         = 0,
            padding        = 0,
            background     = C.paper,
            text_font_face = "cfont",
            text_font_size = Screen:scaleBySize(13),
            align          = "left",
            callback       = function()
                if item.file then
                    UIManager:close(self)
                    local ReaderUI = package.loaded["apps/reader/readerui"]
                        or require("apps/reader/readerui")
                    ReaderUI:showReader(item.file)
                end
            end,
        }
        vg[#vg+1] = self:_divider(w)
    end
    return vg
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  VIEW: GOALS
-- ═══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_goalsView(w, h)
    local C = self._C
    local vg = VerticalGroup:new{ align = "left" }

    vg[#vg+1] = TextWidget:new{ text = "Reading Goals", face = self:_F(16), fgcolor = C.black, bold = true }
    vg[#vg+1] = self:_divider(w)

    local ReadHistory = lazy("readhistory")
    local hist = {}
    if ReadHistory then
        pcall(function() ReadHistory:reload() end)
        hist = ReadHistory.hist or {}
    end

    local total     = #hist
    local this_year = tostring(os.date("%Y"))
    local yr_count  = 0
    for _, item in ipairs(hist) do
        if item.time and os.date("%Y", item.time) == this_year then
            yr_count = yr_count + 1
        end
    end

    local stats = {
        { label = "Books in library",  value = tostring(total)    },
        { label = "Opened this year",  value = tostring(yr_count) },
        { label = "Daily goal",        value = "30 min"           },
        { label = "Current streak",    value = "—"                },
    }

    local col_a = math.floor(w * 2 / 3)
    local col_b = w - col_a
    for _, s in ipairs(stats) do
        vg[#vg+1] = FrameContainer:new{
            width      = w,
            height     = self._ROW_H,
            bordersize = 0,
            padding    = 0,
            background = C.paper,
            HorizontalGroup:new{
                align = "center",
                FrameContainer:new{
                    width        = col_a,
                    height       = self._ROW_H,
                    bordersize   = 0,
                    padding_left = self._PAD,
                    CenterContainer:new{
                        dimen = Geom:new{ w = col_a - self._PAD, h = self._ROW_H },
                        TextWidget:new{ text = s.label, face = self:_F(13), fgcolor = C.black },
                    },
                },
                CenterContainer:new{
                    dimen = Geom:new{ w = col_b, h = self._ROW_H },
                    TextWidget:new{ text = s.value, face = self:_F(14), fgcolor = C.black, bold = true },
                },
            },
        }
        vg[#vg+1] = self:_divider(w)
    end

    vg[#vg+1] = TextWidget:new{
        text    = "Enable the Statistics plugin for detailed data.",
        face    = self:_F(11),
        fgcolor = C.dim,
    }
    return vg
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  VIEW: MORE
-- ═══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_moreView(w, h)
    local Screen = self._S
    local C = self._C
    local vg = VerticalGroup:new{ align = "left" }
    vg[#vg+1] = TextWidget:new{ text = "More", face = self:_F(16), fgcolor = C.black, bold = true }
    vg[#vg+1] = self:_divider(w)

    local entries = {
        { label = "OPDS Browser",       action = function() self:_act_opds()     end },
        { label = "KOSync Settings",    action = function() self:_act_kosync()   end },
        { label = "Statistics",         action = function() self:_act_stats()    end },
        { label = "Search",             action = function() self:_act_search()   end },
        { label = "Reader Settings",    action = function() self:_act_settings() end },
        { label = "Plugins",            action = function() self:_act_plugins()  end },
        { label = "About KOReader",     action = function() self:_act_about()    end },
    }

    local rows_pp = math.max(1, math.floor((h - Screen:scaleBySize(50)) / self._ROW_H))
    local ps      = self.tab_pages["more"]
    ps.total      = math.max(1, math.ceil(#entries / rows_pp))
    local offset  = (ps.page - 1) * rows_pp

    for i = offset + 1, math.min(offset + rows_pp, #entries) do
        local e = entries[i]
        vg[#vg+1] = Button:new{
            text           = e.label,
            width          = w,
            height         = self._ROW_H,
            bordersize     = 0,
            margin         = 0,
            padding        = 0,
            background     = C.paper,
            text_font_face = "cfont",
            text_font_size = Screen:scaleBySize(13),
            align          = "left",
            callback       = e.action,
        }
        vg[#vg+1] = self:_divider(w)
    end
    return vg
end

-- ── More-tab actions ──────────────────────────────────────────────────────────
local function info(msg)
    local ok, IM = pcall(require, "ui/widget/infomessage")
    if ok then UIManager:show(IM:new{ text = msg }) end
end

function HomeScreen:_act_opds()
    info("OPDS Browser:\nMain Menu → OPDS catalog")
end

function HomeScreen:_act_kosync()
    info("KOSync Settings:\nMain Menu → Tools → KOSync")
end

function HomeScreen:_act_stats()
    info("Statistics:\nMain Menu → Tools → Statistics")
end

function HomeScreen:_act_search()
    if self.filemanager and self.filemanager.file_search then
        UIManager:close(self)
        self.filemanager:file_search(self.filemanager.path)
    else
        info("Search:\nMain Menu → Search")
    end
end

function HomeScreen:_act_settings()
    UIManager:close(self)
end

function HomeScreen:_act_plugins()
    info("Plugins:\nMain Menu → Tools → More tools → Plugin management")
end

function HomeScreen:_act_about()
    info("About:\nMain Menu → Help → About KOReader")
end

return HomeScreen
