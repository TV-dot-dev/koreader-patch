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
--]]

local InputContainer  = require("ui/widget/container/inputcontainer")
local FrameContainer  = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ok_lc, LeftContainer = pcall(require, "ui/widget/container/leftcontainer")
if not ok_lc then LeftContainer = CenterContainer end  -- fallback if not present
local VerticalGroup   = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TextWidget      = require("ui/widget/textwidget")
local LineWidget      = require("ui/widget/linewidget")
local Button          = require("ui/widget/button")
local ProgressWidget  = require("ui/widget/progresswidget")
local UIManager       = require("ui/uimanager")
local Screen          = require("device/screen")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local ReadHistory     = require("readhistory")
local DocSettings     = require("docsettings")
local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then _, lfs = pcall(require, "lfs") end
local _               = require("gettext")

-- ── Colour helpers ───────────────────────────────────────────────────────────
-- Blitbuffer.gray(v): 0 = black, 1 = white
local C = {
    paper   = Blitbuffer.gray(0.96),   -- warm off-white background
    surface = Blitbuffer.COLOR_WHITE,
    border  = Blitbuffer.gray(0.80),
    tabBg   = Blitbuffer.gray(0.90),
    statusBg= Blitbuffer.gray(0.92),
    black   = Blitbuffer.COLOR_BLACK,
    dim     = Blitbuffer.gray(0.45),
}

-- ── Font helpers ─────────────────────────────────────────────────────────────
local function F(size)  return Font:getFace("cfont",   size) end
local function Fs(size) return Font:getFace("smallinfofont", size) end

-- ── Layout ───────────────────────────────────────────────────────────────────
local STATUS_H  = Screen:scaleBySize(28)
local TAB_H     = Screen:scaleBySize(52)
local PAGER_H   = Screen:scaleBySize(28)
local DIVIDER_H = Screen:scaleBySize(1)
local PAD       = Screen:scaleBySize(14)   -- horizontal page padding
local ROW_H     = Screen:scaleBySize(44)   -- standard touch-target row height

local TABS = {
    { id = "home",    label = "Home"    },
    { id = "library", label = "Library" },
    { id = "files",   label = "Files"   },
    { id = "goals",   label = "Goals"   },
    { id = "more",    label = "More"    },
}

-- ── HomeScreen class ─────────────────────────────────────────────────────────
local HomeScreen = InputContainer:extend{
    name             = "HomeScreen",
    covers_fullscreen = true,
    current_tab      = "home",
    -- per-tab page state  { page = n, total = n }
    tab_pages        = {},
}

-- ── init ─────────────────────────────────────────────────────────────────────
function HomeScreen:init()
    self.sw = Screen:getWidth()
    self.sh = Screen:getHeight()

    -- Reset per-tab page state
    for _, t in ipairs(TABS) do
        self.tab_pages[t.id] = { page = 1, total = 1 }
    end

    self.key_events = {
        Back = { {"Back"}, action = "back" },
    }

    -- Initial render (full e-ink refresh on open)
    self:_build()
    UIManager:setDirty(self, "full")
end

-- ── Back key ─────────────────────────────────────────────────────────────────
function HomeScreen:onBack()
    -- Files tab: just close, FileManager is underneath
    if self.current_tab == "files" then
        UIManager:close(self)
        return true
    end
    UIManager:close(self)
    return true
end

-- ── Tab switch ───────────────────────────────────────────────────────────────
function HomeScreen:switchTab(tab_id)
    if tab_id == "files" then
        UIManager:close(self)   -- reveal FileManager
        return
    end
    self.current_tab = tab_id
    self.tab_pages[tab_id].page = 1   -- reset to first page on tab change
    self:_build()
    UIManager:setDirty(self, "ui")
end

-- ── Page change ──────────────────────────────────────────────────────────────
function HomeScreen:changePage(delta)
    local ps = self.tab_pages[self.current_tab]
    local np = ps.page + delta
    if np < 1 or np > ps.total then return end
    ps.page = np
    self:_build()
    UIManager:setDirty(self, "ui")
end

-- ══════════════════════════════════════════════════════════════════════════════
--  BUILD  (assembles the full widget tree into self[1])
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_build()
    local sw, sh = self.sw, self.sh
    local ps     = self.tab_pages[self.current_tab]

    -- decide whether pager bar is visible this render
    local show_pager = (ps.total > 1)
    local content_h  = sh - STATUS_H - TAB_H - (show_pager and PAGER_H or 0)

    local layout = VerticalGroup:new{ align = "left" }
    table.insert(layout, self:_statusBar(sw))
    table.insert(layout, self:_content(sw, content_h))
    if show_pager then
        table.insert(layout, self:_pagerBar(sw))
    end
    table.insert(layout, self:_tabBar(sw))

    self[1] = FrameContainer:new{
        width     = sw,
        height    = sh,
        bordersize = 0,
        padding   = 0,
        background = C.paper,
        layout,
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
end

-- ══════════════════════════════════════════════════════════════════════════════
--  STATUS BAR
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_statusBar(sw)
    local time_str = os.date("%H:%M")
    local date_str = os.date("%a %d %b")
    local batt_str = ""
    if Device:hasBattery() then
        batt_str = "  ·  " .. Device:getPowerDevice():getCapacity() .. "%"
    end
    local label = time_str .. "  ·  " .. date_str .. batt_str

    return FrameContainer:new{
        width     = sw,
        height    = STATUS_H,
        bordersize = 0,
        padding   = 0,
        background = C.statusBg,
        CenterContainer:new{
            dimen = Geom:new{ w = sw, h = STATUS_H },
            TextWidget:new{
                text    = label,
                face    = F(11),
                fgcolor = C.dim,
            },
        },
    }
end

-- ══════════════════════════════════════════════════════════════════════════════
--  CONTENT AREA  — routes to the correct view builder
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_content(sw, h)
    local builders = {
        home    = self._homeView,
        library = self._libraryView,
        goals   = self._goalsView,
        more    = self._moreView,
    }
    local builder = builders[self.current_tab] or self._homeView
    local inner   = builder(self, sw - PAD * 2, h)

    return FrameContainer:new{
        width     = sw,
        height    = h,
        bordersize = 0,
        padding_left  = PAD,
        padding_right = PAD,
        padding_top   = PAD,
        padding_bottom = 0,
        background = C.paper,
        inner,
    }
end

-- ══════════════════════════════════════════════════════════════════════════════
--  PAGER BAR
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_pagerBar(sw)
    local ps = self.tab_pages[self.current_tab]
    return FrameContainer:new{
        width     = sw,
        height    = PAGER_H,
        bordersize = 0,
        padding   = 0,
        background = C.tabBg,
        HorizontalGroup:new{
            align = "center",
            Button:new{
                text      = "← Prev",
                width     = math.floor(sw / 3),
                height    = PAGER_H,
                bordersize = 0,
                margin    = 0,
                padding   = 0,
                background = C.tabBg,
                enabled   = ps.page > 1,
                callback  = function() self:changePage(-1) end,
            },
            CenterContainer:new{
                dimen = Geom:new{ w = math.floor(sw / 3), h = PAGER_H },
                TextWidget:new{
                    text    = ps.page .. " / " .. ps.total,
                    face    = F(11),
                    fgcolor = C.dim,
                },
            },
            Button:new{
                text      = "Next →",
                width     = math.floor(sw / 3),
                height    = PAGER_H,
                bordersize = 0,
                margin    = 0,
                padding   = 0,
                background = C.tabBg,
                enabled   = ps.page < ps.total,
                callback  = function() self:changePage(1) end,
            },
        },
    }
end

-- ══════════════════════════════════════════════════════════════════════════════
--  TAB BAR
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_tabBar(sw)
    local tab_w = math.floor(sw / #TABS)
    local row   = HorizontalGroup:new{ align = "left" }

    for _, tab in ipairs(TABS) do
        local active = (tab.id == self.current_tab)
            or (tab.id == "files" and self.current_tab == "files")
        local btn = Button:new{
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
        }
        table.insert(row, btn)
    end

    return FrameContainer:new{
        width     = sw,
        height    = TAB_H,
        bordersize = 0,
        padding   = 0,
        background = C.tabBg,
        -- top border line
        VerticalGroup:new{
            align = "left",
            LineWidget:new{ dimen = Geom:new{ w = sw, h = DIVIDER_H }, background = C.border },
            row,
        },
    }
end

-- ══════════════════════════════════════════════════════════════════════════════
--  VIEW: HOME
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_homeView(w, h)
    local vg = VerticalGroup:new{ align = "left" }

    -- Greeting + date
    local hour = tonumber(os.date("%H"))
    local greeting = hour < 12 and "Good morning." or hour < 18 and "Good afternoon." or "Good evening."

    table.insert(vg, TextWidget:new{
        text    = greeting,
        face    = Font:getFace("tfont", Screen:scaleBySize(18)),
        fgcolor = C.black,
        bold    = false,
    })
    table.insert(vg, TextWidget:new{
        text    = os.date("%A, %d %B %Y"),
        face    = F(12),
        fgcolor = C.dim,
    })
    table.insert(vg, LineWidget:new{
        dimen      = Geom:new{ w = w, h = DIVIDER_H },
        background = C.border,
        margin_top = Screen:scaleBySize(10),
    })

    -- Currently reading (most recent history entry)
    ReadHistory:reload()
    local hist = ReadHistory.hist or {}

    if hist[1] then
        local item  = hist[1]
        local title = item.text or "Unknown title"

        -- Try to get reading progress from DocSettings
        local pct = 0
        if item.file and lfs.attributes(item.file, "mode") == "file" then
            local ok, ds = pcall(DocSettings.open, DocSettings, item.file)
            if ok and ds then
                pct = math.floor((ds:readSetting("percent_finished") or 0) * 100)
            end
        end

        table.insert(vg, FrameContainer:new{
            width     = w,
            bordersize = DIVIDER_H,
            border_color = C.border,
            background = C.surface,
            padding   = Screen:scaleBySize(10),
            margin_top = Screen:scaleBySize(10),
            VerticalGroup:new{
                align = "left",
                TextWidget:new{
                    text    = "Currently reading",
                    face    = F(10),
                    fgcolor = C.dim,
                },
                TextWidget:new{
                    text    = title,
                    face    = F(14),
                    fgcolor = C.black,
                    bold    = true,
                    max_width = w - Screen:scaleBySize(20),
                },
                ProgressWidget:new{
                    width    = w - Screen:scaleBySize(20),
                    height   = Screen:scaleBySize(4),
                    percentage = pct / 100,
                    margin_top = Screen:scaleBySize(6),
                    ticks    = nil,
                },
                TextWidget:new{
                    text    = pct .. "% complete",
                    face    = F(11),
                    fgcolor = C.dim,
                },
                Button:new{
                    text      = "Continue reading",
                    width     = w - Screen:scaleBySize(20),
                    height    = ROW_H,
                    bordersize = DIVIDER_H,
                    border_color = C.border,
                    background = C.paper,
                    margin_top = Screen:scaleBySize(8),
                    callback  = function()
                        if item.file then
                            UIManager:close(self)
                            local ReaderUI = require("apps/reader/readerui")
                            ReaderUI:showReader(item.file)
                        end
                    end,
                },
            },
        })
    else
        table.insert(vg, FrameContainer:new{
            width  = w,
            bordersize = DIVIDER_H,
            border_color = C.border,
            background = C.surface,
            padding = Screen:scaleBySize(16),
            margin_top = Screen:scaleBySize(10),
            CenterContainer:new{
                dimen = Geom:new{ w = w - Screen:scaleBySize(32), h = Screen:scaleBySize(60) },
                TextWidget:new{
                    text    = "No books opened yet.\nBrowse Files to get started.",
                    face    = F(13),
                    fgcolor = C.dim,
                },
            },
        })
    end

    -- Recent books (up to 4, below the current card)
    if #hist > 1 then
        table.insert(vg, TextWidget:new{
            text       = "Recent",
            face       = F(10),
            fgcolor    = C.dim,
            margin_top = Screen:scaleBySize(12),
        })
        for i = 2, math.min(#hist, 5) do
            local item = hist[i]
            table.insert(vg, Button:new{
                text      = item.text or "Unknown",
                width     = w,
                height    = ROW_H,
                bordersize = 0,
                margin    = 0,
                padding   = 0,
                background = C.paper,
                text_font_face = "cfont",
                text_font_size = Screen:scaleBySize(13),
                align     = "left",
                callback  = function()
                    if item.file then
                        UIManager:close(self)
                        local ReaderUI = require("apps/reader/readerui")
                        ReaderUI:showReader(item.file)
                    end
                end,
            })
            table.insert(vg, LineWidget:new{
                dimen      = Geom:new{ w = w, h = DIVIDER_H },
                background = C.border,
            })
        end
    end

    return vg
end

-- ══════════════════════════════════════════════════════════════════════════════
--  VIEW: LIBRARY
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_libraryView(w, h)
    ReadHistory:reload()
    local hist = ReadHistory.hist or {}

    -- How many rows fit per page?
    local rows_per_page = math.floor((h - PAD) / ROW_H)
    if rows_per_page < 1 then rows_per_page = 1 end

    local ps     = self.tab_pages["library"]
    ps.total     = math.max(1, math.ceil(#hist / rows_per_page))
    local offset = (ps.page - 1) * rows_per_page

    local vg = VerticalGroup:new{ align = "left" }

    -- Section heading
    table.insert(vg, TextWidget:new{
        text    = "Library  —  " .. #hist .. " books",
        face    = F(12),
        fgcolor = C.dim,
    })
    table.insert(vg, LineWidget:new{
        dimen      = Geom:new{ w = w, h = DIVIDER_H },
        background = C.border,
        margin_top = Screen:scaleBySize(6),
    })

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

    for i = offset + 1, math.min(offset + rows_per_page, #hist) do
        local item = hist[i]
        local pct  = 0
        if item.file and lfs.attributes(item.file, "mode") == "file" then
            local ok, ds = pcall(DocSettings.open, DocSettings, item.file)
            if ok and ds then
                pct = math.floor((ds:readSetting("percent_finished") or 0) * 100)
            end
        end

        table.insert(vg, Button:new{
            text      = (item.text or "Unknown") .. "  [" .. pct .. "%]",
            width     = w,
            height    = ROW_H,
            bordersize = 0,
            margin    = 0,
            padding   = 0,
            background = C.paper,
            text_font_face = "cfont",
            text_font_size = Screen:scaleBySize(13),
            align     = "left",
            callback  = function()
                if item.file then
                    UIManager:close(self)
                    local ReaderUI = require("apps/reader/readerui")
                    ReaderUI:showReader(item.file)
                end
            end,
        })
        table.insert(vg, LineWidget:new{
            dimen      = Geom:new{ w = w, h = DIVIDER_H },
            background = C.border,
        })
    end

    return vg
end

-- ══════════════════════════════════════════════════════════════════════════════
--  VIEW: GOALS
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_goalsView(w, h)
    local vg = VerticalGroup:new{ align = "left" }

    table.insert(vg, TextWidget:new{
        text    = "Reading Goals",
        face    = F(16),
        fgcolor = C.black,
        bold    = true,
    })
    table.insert(vg, LineWidget:new{
        dimen      = Geom:new{ w = w, h = DIVIDER_H },
        background = C.border,
        margin_top = Screen:scaleBySize(8),
    })

    -- Pull stats from the Statistics plugin database if available.
    -- Falls back to ReadHistory count otherwise.
    local books_total = #(ReadHistory.hist or {})

    -- Books read this year (crude: history items opened this year)
    local this_year   = tonumber(os.date("%Y"))
    local books_year  = 0
    for _, item in ipairs(ReadHistory.hist or {}) do
        if item.time and os.date("%Y", item.time) == tostring(this_year) then
            books_year = books_year + 1
        end
    end

    -- Simple stat cards
    local stats = {
        { label = "Books in library",       value = tostring(books_total) },
        { label = "Opened this year",        value = tostring(books_year)  },
        { label = "Daily goal",              value = "30 min"              },  -- placeholder
        { label = "Current streak",          value = "—"                   },  -- placeholder
    }

    for _, s in ipairs(stats) do
        table.insert(vg, FrameContainer:new{
            width      = w,
            height     = ROW_H,
            bordersize = 0,
            padding    = 0,
            background = C.paper,
            HorizontalGroup:new{
                align = "center",
                LeftContainer:new{
                    dimen = Geom:new{ w = math.floor(w * 2 / 3), h = ROW_H },
                    TextWidget:new{
                        text    = s.label,
                        face    = F(13),
                        fgcolor = C.black,
                    },
                },
                CenterContainer:new{
                    dimen = Geom:new{ w = math.floor(w / 3), h = ROW_H },
                    TextWidget:new{
                        text    = s.value,
                        face    = F(14),
                        fgcolor = C.black,
                        bold    = true,
                    },
                },
            },
        })
        table.insert(vg, LineWidget:new{
            dimen      = Geom:new{ w = w, h = DIVIDER_H },
            background = C.border,
        })
    end

    -- Note about Statistics plugin
    table.insert(vg, TextWidget:new{
        text    = "Detailed stats available when the\nStatistics plugin is enabled.",
        face    = F(11),
        fgcolor = C.dim,
        margin_top = Screen:scaleBySize(14),
    })

    return vg
end

-- ══════════════════════════════════════════════════════════════════════════════
--  VIEW: MORE
-- ══════════════════════════════════════════════════════════════════════════════
function HomeScreen:_moreView(w, h)
    local vg = VerticalGroup:new{ align = "left" }

    table.insert(vg, TextWidget:new{
        text    = "More",
        face    = F(16),
        fgcolor = C.black,
        bold    = true,
    })
    table.insert(vg, LineWidget:new{
        dimen      = Geom:new{ w = w, h = DIVIDER_H },
        background = C.border,
        margin_top = Screen:scaleBySize(8),
    })

    local rows_per_page = math.floor((h - Screen:scaleBySize(50)) / ROW_H)
    if rows_per_page < 1 then rows_per_page = 1 end

    -- All the menu entries
    local entries = {
        -- Tools
        { label = "Search",              section = "Tools",    action = function() self:_openSearch()         end },
        { label = "OPDS Browser",        section = "Tools",    action = function() self:_openOPDS()           end },
        { label = "Book Map",            section = "Tools",    action = function() self:_openBookMap()        end },
        { label = "Dictionary",          section = "Tools",    action = function() self:_openDictionary()     end },
        -- Sync
        { label = "KOSync Settings",     section = "Sync",     action = function() self:_openKOSync()         end },
        -- Settings
        { label = "Reader Settings",     section = "Settings", action = function() self:_openReaderSettings() end },
        { label = "Device Settings",     section = "Settings", action = function() self:_openDeviceSettings() end },
        { label = "Plugins",             section = "Settings", action = function() self:_openPlugins()        end },
        -- About
        { label = "About KOReader",      section = "About",    action = function() self:_openAbout()          end },
    }

    local ps     = self.tab_pages["more"]
    ps.total     = math.max(1, math.ceil(#entries / rows_per_page))
    local offset = (ps.page - 1) * rows_per_page

    for i = offset + 1, math.min(offset + rows_per_page, #entries) do
        local entry = entries[i]
        table.insert(vg, Button:new{
            text      = entry.label,
            width     = w,
            height    = ROW_H,
            bordersize = 0,
            margin    = 0,
            padding   = 0,
            background = C.paper,
            text_font_face = "cfont",
            text_font_size = Screen:scaleBySize(13),
            align     = "left",
            callback  = entry.action,
        })
        table.insert(vg, LineWidget:new{
            dimen      = Geom:new{ w = w, h = DIVIDER_H },
            background = C.border,
        })
    end

    return vg
end

-- ══════════════════════════════════════════════════════════════════════════════
--  ACTION HELPERS  (open existing KOReader screens / plugins)
-- ══════════════════════════════════════════════════════════════════════════════

function HomeScreen:_openSearch()
    -- FileManager has a built-in search; close home and trigger it.
    if self.filemanager and self.filemanager.file_search then
        UIManager:close(self)
        self.filemanager:file_search(self.filemanager.path)
    end
end

function HomeScreen:_openOPDS()
    local ok, OPDSBrowser = pcall(require, "apps/filemanager/filemanageropds")
    if ok and OPDSBrowser then
        UIManager:close(self)
        UIManager:show(OPDSBrowser:new{})
    end
end

function HomeScreen:_openBookMap()
    -- Book map is only available inside the reader; show info if not in reader.
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        text = "Book Map is available inside the reader.\nOpen a book first.",
    })
end

function HomeScreen:_openDictionary()
    local ok, DictQuickLookup = pcall(require, "ui/widget/dictquicklookup")
    if ok then
        -- Show a simple info instead of a blank lookup
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = "Dictionary lookup is available while reading.\nHighlight a word to look it up.",
        })
    end
end

function HomeScreen:_openKOSync()
    -- Try to open KOSync plugin settings directly.
    local ok, KOSync = pcall(require, "plugins/kosync.koplugin/main")
    if ok and KOSync and KOSync.kosync_settings then
        UIManager:close(self)
        KOSync:kosync_settings()
    else
        -- Fallback: tell user where to find it
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = "KOSync Settings:\nMain Menu → Tools → KOSync",
        })
    end
end

function HomeScreen:_openReaderSettings()
    UIManager:close(self)
    if self.filemanager then
        self.filemanager:onShowConfigWidget()
    end
end

function HomeScreen:_openDeviceSettings()
    UIManager:close(self)
    if self.filemanager then
        -- Trigger the main menu which contains device settings
        self.filemanager:tapMenuItem("filemanager_menu")
    end
end

function HomeScreen:_openPlugins()
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        text = "Plugins:\nMain Menu → Tools → More tools → Plugin management",
    })
end

function HomeScreen:_openAbout()
    local ok, AboutKOReader = pcall(require, "ui/widget/about")
    if ok then
        UIManager:show(AboutKOReader:new{})
    end
end

return HomeScreen
