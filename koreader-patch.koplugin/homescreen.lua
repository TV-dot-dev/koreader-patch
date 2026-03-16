--[[
    KOReader Patch — homescreen.lua

    Full-screen HomeScreen widget.  Layout (top→bottom):
        ┌─────────────────────────┐
        │  Status bar  (28 px)    │
        ├─────────────────────────┤
        │  Content area (flex)    │
        ├─────────────────────────┤
        │  Pager bar   (28 px)    │  shown only when a view has >1 page
        ├─────────────────────────┤
        │  Tab bar     (52 px)    │
        └─────────────────────────┘

    Views:  home · library · files · goals · more

    Design principle: only the six modules below are required at the top
    level; everything else is loaded lazily inside the functions that need
    it, wrapped in pcall, so a missing module degrades gracefully rather
    than crashing the whole screen.
--]]

-- ── Core requires (guaranteed present in every KOReader build) ────────────────
local InputContainer  = require("ui/widget/container/inputcontainer")
local FrameContainer  = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup   = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TextWidget      = require("ui/widget/textwidget")
local Button          = require("ui/widget/button")
local UIManager       = require("ui/uimanager")
local Device          = require("device")
local Screen          = Device.screen  -- Screen is Device.screen, not a standalone module
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local Blitbuffer      = require("ffi/blitbuffer")
local _               = require("gettext")

-- ── Lazy-load helpers ─────────────────────────────────────────────────────────
-- Call as:  local M = lazy("module/path")  → returns module or nil
local function lazy(mod)
    local ok, m = pcall(require, mod)
    return ok and m or nil
end

-- ── Colour palette ────────────────────────────────────────────────────────────
local C = {
    paper    = Blitbuffer.gray(0.96),
    surface  = Blitbuffer.COLOR_WHITE,
    border   = Blitbuffer.gray(0.80),
    tabBg    = Blitbuffer.gray(0.90),
    statusBg = Blitbuffer.gray(0.92),
    black    = Blitbuffer.COLOR_BLACK,
    dim      = Blitbuffer.gray(0.45),
}

-- ── Font helper ───────────────────────────────────────────────────────────────
local function F(size) return Font:getFace("cfont", size) end

-- ── Layout constants ──────────────────────────────────────────────────────────
local sw = Screen:getWidth()
local sh = Screen:getHeight()
local STATUS_H = Screen:scaleBySize(28)
local TAB_H    = Screen:scaleBySize(52)
local PAGER_H  = Screen:scaleBySize(28)
local PAD      = Screen:scaleBySize(14)
local ROW_H    = Screen:scaleBySize(44)
local DIV_H    = Screen:scaleBySize(1)

local TABS = {
    { id = "home",    label = "Home"    },
    { id = "library", label = "Library" },
    { id = "files",   label = "Files"   },
    { id = "goals",   label = "Goals"   },
    { id = "more",    label = "More"    },
}

-- ── Widget helpers ────────────────────────────────────────────────────────────

-- A thin horizontal rule.
local function divider(width)
    return FrameContainer:new{
        width      = width,
        height     = DIV_H,
        bordersize = 0,
        background = C.border,
    }
end

-- A left-padded text row (used instead of LeftContainer).
local function textRow(label, width, fsize, color)
    return FrameContainer:new{
        width      = width,
        height     = ROW_H,
        bordersize = 0,
        padding_left = PAD,
        background = C.paper,
        CenterContainer:new{
            dimen = Geom:new{ w = width - PAD, h = ROW_H },
            TextWidget:new{
                text    = label,
                face    = F(fsize or 13),
                fgcolor = color or C.black,
            },
        },
    }
end

-- ══════════════════════════════════════════════════════════════════════════════
--  HomeScreen class
-- ══════════════════════════════════════════════════════════════════════════════
local HomeScreen = InputContainer:extend{
    name              = "HomeScreen",
    covers_fullscreen = true,
    current_tab       = "home",
    tab_pages         = {},
}

function HomeScreen:init()
    for _, t in ipairs(TABS) do
        self.tab_pages[t.id] = { page = 1, total = 1 }
    end
    self.key_events = { Back = { {"Back"}, action = "back" } }
    self:_build()
    UIManager:setDirty(self, "full")
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
    local ps         = self.tab_pages[self.current_tab]
    local show_pager = ps.total > 1
    local content_h  = sh - STATUS_H - TAB_H - (show_pager and PAGER_H or 0)

    local layout = VerticalGroup:new{ align = "left" }
    table.insert(layout, self:_statusBar())
    table.insert(layout, self:_contentArea(content_h))
    if show_pager then
        table.insert(layout, self:_pagerBar())
    end
    table.insert(layout, self:_tabBar())

    self[1] = FrameContainer:new{
        width      = sw,
        height     = sh,
        bordersize = 0,
        padding    = 0,
        background = C.paper,
        layout,
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
end

-- ── Status bar ────────────────────────────────────────────────────────────────
function HomeScreen:_statusBar()
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
        height     = STATUS_H,
        bordersize = 0,
        padding    = 0,
        background = C.statusBg,
        CenterContainer:new{
            dimen = Geom:new{ w = sw, h = STATUS_H },
            TextWidget:new{
                text    = time .. "  ·  " .. date .. batt,
                face    = F(11),
                fgcolor = C.dim,
            },
        },
    }
end

-- ── Content area (routes to view builders) ────────────────────────────────────
function HomeScreen:_contentArea(h)
    local inner_w = sw - PAD * 2
    local view
    if     self.current_tab == "home"    then view = self:_homeView(inner_w, h)
    elseif self.current_tab == "library" then view = self:_libraryView(inner_w, h)
    elseif self.current_tab == "goals"   then view = self:_goalsView(inner_w, h)
    elseif self.current_tab == "more"    then view = self:_moreView(inner_w, h)
    else   view = TextWidget:new{ text = "", face = F(12) }
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
function HomeScreen:_pagerBar()
    local ps   = self.tab_pages[self.current_tab]
    local col3 = math.floor(sw / 3)

    return FrameContainer:new{
        width      = sw,
        height     = PAGER_H,
        bordersize = 0,
        padding    = 0,
        background = C.tabBg,
        HorizontalGroup:new{
            align = "center",
            Button:new{
                text       = "← Prev",
                width      = col3,
                height     = PAGER_H,
                bordersize = 0,
                margin     = 0,
                padding    = 0,
                background = C.tabBg,
                enabled    = ps.page > 1,
                callback   = function() self:changePage(-1) end,
            },
            CenterContainer:new{
                dimen = Geom:new{ w = col3, h = PAGER_H },
                TextWidget:new{
                    text    = ps.page .. " / " .. ps.total,
                    face    = F(11),
                    fgcolor = C.dim,
                },
            },
            Button:new{
                text       = "Next →",
                width      = col3,
                height     = PAGER_H,
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
function HomeScreen:_tabBar()
    local tab_w = math.floor(sw / #TABS)
    local row   = HorizontalGroup:new{ align = "left" }
    for _, tab in ipairs(TABS) do
        local active = (tab.id == self.current_tab)
        table.insert(row, Button:new{
            text           = tab.label,
            width          = tab_w,
            height         = TAB_H,
            margin         = 0,
            bordersize     = 0,
            padding        = 0,
            background     = active and C.surface or C.tabBg,
            text_font_face = "cfont",
            text_font_size = Screen:scaleBySize(12),
            text_font_bold = active,
            callback       = function() self:switchTab(tab.id) end,
        })
    end
    return FrameContainer:new{
        width      = sw,
        height     = TAB_H,
        bordersize = 0,
        padding    = 0,
        background = C.tabBg,
        VerticalGroup:new{
            align = "left",
            divider(sw),
            row,
        },
    }
end

-- ══════════════════════════════════════════════════════════════════════════════
--  VIEW: HOME
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_homeView(w, h)
    local vg = VerticalGroup:new{ align = "left" }

    -- Greeting
    local hour = tonumber(os.date("%H"))
    local greeting = hour < 12 and "Good morning."
                  or hour < 18 and "Good afternoon."
                  or                "Good evening."
    table.insert(vg, TextWidget:new{
        text    = greeting,
        face    = Font:getFace("tfont", Screen:scaleBySize(18)),
        fgcolor = C.black,
    })
    table.insert(vg, TextWidget:new{
        text    = os.date("%A, %d %B %Y"),
        face    = F(12),
        fgcolor = C.dim,
    })
    table.insert(vg, divider(w))

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

        -- Try to read progress from DocSettings
        local DocSettings = lazy("docsettings")
        if DocSettings and item.file then
            pcall(function()
                local ds = DocSettings:open(item.file)
                if ds then
                    pct = math.floor((ds:readSetting("percent_finished") or 0) * 100)
                end
            end)
        end

        -- Book card
        table.insert(vg, FrameContainer:new{
            width        = w,
            bordersize   = DIV_H,
            border_color = C.border,
            background   = C.surface,
            padding      = Screen:scaleBySize(10),
            VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = "Currently reading", face = F(10), fgcolor = C.dim },
                TextWidget:new{
                    text      = title,
                    face      = F(14),
                    fgcolor   = C.black,
                    bold      = true,
                    max_width = w - Screen:scaleBySize(20),
                },
                TextWidget:new{
                    text    = pct .. "% complete",
                    face    = F(11),
                    fgcolor = C.dim,
                },
                Button:new{
                    text       = "Continue reading",
                    width      = w - Screen:scaleBySize(20),
                    height     = ROW_H,
                    bordersize = DIV_H,
                    background = C.paper,
                    callback   = function()
                        if item.file then
                            UIManager:close(self)
                            local ok, ReaderUI = pcall(require, "apps/reader/readerui")
                            if ok then ReaderUI:showReader(item.file) end
                        end
                    end,
                },
            },
        })
    else
        table.insert(vg, CenterContainer:new{
            dimen = Geom:new{ w = w, h = Screen:scaleBySize(80) },
            TextWidget:new{
                text    = "No books opened yet.  Browse Files to start.",
                face    = F(13),
                fgcolor = C.dim,
            },
        })
    end

    -- Recent list
    if #hist > 1 then
        table.insert(vg, TextWidget:new{
            text    = "Recent",
            face    = F(10),
            fgcolor = C.dim,
        })
        for i = 2, math.min(#hist, 5) do
            local item = hist[i]
            table.insert(vg, Button:new{
                text           = item.text or "Unknown",
                width          = w,
                height         = ROW_H,
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
                        local ok, ReaderUI = pcall(require, "apps/reader/readerui")
                        if ok then ReaderUI:showReader(item.file) end
                    end
                end,
            })
            table.insert(vg, divider(w))
        end
    end

    return vg
end

-- ══════════════════════════════════════════════════════════════════════════════
--  VIEW: LIBRARY
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_libraryView(w, h)
    local ReadHistory = lazy("readhistory")
    local hist = {}
    if ReadHistory then
        pcall(function() ReadHistory:reload() end)
        hist = ReadHistory.hist or {}
    end

    local rows_pp = math.max(1, math.floor((h - PAD) / ROW_H))
    local ps      = self.tab_pages["library"]
    ps.total      = math.max(1, math.ceil(#hist / rows_pp))
    local offset  = (ps.page - 1) * rows_pp

    local vg = VerticalGroup:new{ align = "left" }
    table.insert(vg, TextWidget:new{
        text    = "Library  —  " .. #hist .. " books",
        face    = F(12),
        fgcolor = C.dim,
    })
    table.insert(vg, divider(w))

    if #hist == 0 then
        table.insert(vg, CenterContainer:new{
            dimen = Geom:new{ w = w, h = h - Screen:scaleBySize(40) },
            TextWidget:new{
                text    = "Your library is empty.\nOpen a book via Files to get started.",
                face    = F(13),
                fgcolor = C.dim,
            },
        })
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
        table.insert(vg, Button:new{
            text           = (item.text or "Unknown") .. "  [" .. pct .. "%]",
            width          = w,
            height         = ROW_H,
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
                    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
                    if ok then ReaderUI:showReader(item.file) end
                end
            end,
        })
        table.insert(vg, divider(w))
    end
    return vg
end

-- ══════════════════════════════════════════════════════════════════════════════
--  VIEW: GOALS
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_goalsView(w, h)
    local vg = VerticalGroup:new{ align = "left" }

    table.insert(vg, TextWidget:new{ text = "Reading Goals", face = F(16), fgcolor = C.black, bold = true })
    table.insert(vg, divider(w))

    local ReadHistory = lazy("readhistory")
    local hist        = {}
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
        table.insert(vg, FrameContainer:new{
            width      = w,
            height     = ROW_H,
            bordersize = 0,
            padding    = 0,
            background = C.paper,
            HorizontalGroup:new{
                align = "center",
                FrameContainer:new{
                    width        = col_a,
                    height       = ROW_H,
                    bordersize   = 0,
                    padding_left = PAD,
                    CenterContainer:new{
                        dimen = Geom:new{ w = col_a - PAD, h = ROW_H },
                        TextWidget:new{ text = s.label, face = F(13), fgcolor = C.black },
                    },
                },
                CenterContainer:new{
                    dimen = Geom:new{ w = col_b, h = ROW_H },
                    TextWidget:new{ text = s.value, face = F(14), fgcolor = C.black, bold = true },
                },
            },
        })
        table.insert(vg, divider(w))
    end

    table.insert(vg, TextWidget:new{
        text    = "Enable the Statistics plugin for detailed data.",
        face    = F(11),
        fgcolor = C.dim,
    })
    return vg
end

-- ══════════════════════════════════════════════════════════════════════════════
--  VIEW: MORE
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_moreView(w, h)
    local vg = VerticalGroup:new{ align = "left" }
    table.insert(vg, TextWidget:new{ text = "More", face = F(16), fgcolor = C.black, bold = true })
    table.insert(vg, divider(w))

    local entries = {
        { label = "OPDS Browser",       action = function() self:_act_opds()       end },
        { label = "KOSync Settings",    action = function() self:_act_kosync()     end },
        { label = "Statistics",         action = function() self:_act_stats()      end },
        { label = "Search",             action = function() self:_act_search()     end },
        { label = "Reader Settings",    action = function() self:_act_settings()   end },
        { label = "Plugins",            action = function() self:_act_plugins()    end },
        { label = "About KOReader",     action = function() self:_act_about()      end },
    }

    local rows_pp = math.max(1, math.floor((h - Screen:scaleBySize(50)) / ROW_H))
    local ps      = self.tab_pages["more"]
    ps.total      = math.max(1, math.ceil(#entries / rows_pp))
    local offset  = (ps.page - 1) * rows_pp

    for i = offset + 1, math.min(offset + rows_pp, #entries) do
        local e = entries[i]
        table.insert(vg, Button:new{
            text           = e.label,
            width          = w,
            height         = ROW_H,
            bordersize     = 0,
            margin         = 0,
            padding        = 0,
            background     = C.paper,
            text_font_face = "cfont",
            text_font_size = Screen:scaleBySize(13),
            align          = "left",
            callback       = e.action,
        })
        table.insert(vg, divider(w))
    end
    return vg
end

-- ── More-tab actions ──────────────────────────────────────────────────────────
local function info(msg)
    local ok, IM = pcall(require, "ui/widget/infomessage")
    if ok then UIManager:show(IM:new{ text = msg }) end
end

function HomeScreen:_act_opds()
    local ok, OB = pcall(require, "apps/filemanager/filemanageropds")
    if ok and OB then
        UIManager:close(self)
        UIManager:show(OB:new{})
    else
        info("OPDS Browser not available on this build.")
    end
end

function HomeScreen:_act_kosync()
    local ok, KS = pcall(require, "plugins/kosync.koplugin/main")
    if ok and KS and KS.kosync_settings then
        KS:kosync_settings()
    else
        info("KOSync Settings:\nMain Menu → Tools → KOSync")
    end
end

function HomeScreen:_act_stats()
    local ok, St = pcall(require, "plugins/statistics.koplugin/main")
    if ok and St and St.viewStats then
        St:viewStats()
    else
        info("Statistics:\nMain Menu → Tools → Statistics")
    end
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
    if self.filemanager and self.filemanager.onShowConfigWidget then
        self.filemanager:onShowConfigWidget()
    end
end

function HomeScreen:_act_plugins()
    info("Plugins:\nMain Menu → Tools → More tools → Plugin management")
end

function HomeScreen:_act_about()
    local ok, AB = pcall(require, "ui/widget/about")
    if ok then UIManager:show(AB:new{})
    else info("About:\nMain Menu → Help → About KOReader") end
end

return HomeScreen
