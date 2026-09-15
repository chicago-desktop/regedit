-- The Registry Editor window: the registry entry the Start menu reads (the
-- Settings folder, windows.admin, the shell's picture) and its read-only
-- policy; the SDK tree's expander box and keys, scrolling, the menu, the
-- whole registry from an empty filter; and a shot (test/shots/regedit.png)
-- drawn by the shell's own renderer.
local test = require("test")
local gfx = require("gfx")
local fs = require("fs")
local registry = require("registry")
local ui = require("ui")
local render = require("render")
local rasters = require("rasters")
local images = require("images")
local reg_model = require("reg_model")
local regedit = require("regedit_window")

local CELL = {w = 10, h = 20}

local records = {
    {id = "app:db", kind = "db.sql.sqlite", meta = {comment = "database"}, data = {file = ":memory:"}},
    {id = "windows.shell.theme:chrome", kind = "library.lua", meta = {comment = "theme"},
        data = {source = "file://chrome.lua", modules = {"tty"}}},
    {id = "windows.shell.theme:pixels", kind = "library.lua", meta = {}, data = {}},
    {id = "windows.shell:shell", kind = "process.lua", meta = {title = "Shell"}, data = {}},
    {id = "app.desktop:window_calc", kind = "process.lua", meta = {type = "tui_desktop.window"}, data = {}},
}

local function entry_of(id: string): (any, any)
    local entry: any = assert(registry.get(id))
    local data: any = type(entry.data) == "table" and entry.data or entry
    local meta: any = type(entry.meta) == "table" and entry.meta or {}
    return data, meta
end

-- Titles and ids of the menu bar items from the window tree.
local function menu_of(tree: any): (string, string, boolean)
    local titles, ids, disabled = {}, {}, false
    for _, child in ipairs(tree.children or {}) do
        if child.kind == "menu" then
            for _, entry in ipairs(child.entries) do
                titles[#titles + 1] = tostring(entry.title)
                for _, item in ipairs(entry.items or {}) do
                    if not item.separator then ids[#ids + 1] = tostring(item.id) end
                    if item.disabled then disabled = true end
                end
            end
        end
    end
    return table.concat(titles, " "), table.concat(ids, " "), disabled
end

-- The label with this text in the plan and its width: a sheet title cut down
-- to one cell shows as a single letter.
local function label_width(plan: any, text: string): integer
    for _, item in ipairs(plan.items) do
        if item.node.kind == "label" and item.node.text == text then return math.tointeger(item.rect.w) or 0 end
    end
    return 0
end

local function face_font(): any
    local files = assert(fs.get("app:system_fonts"))
    return assert(gfx.font(assert(files:readfile("LiberationSans-Regular.ttf")), {size = 13, smooth = true}))
end

local function define_tests()
    test.describe("Registry Editor window", function()
        test.it("is a Settings window on the shell SDK, for windows.admin only, with the shell's picture", function()
            local _, meta = entry_of("windows.regedit:window")
            test.eq(table.concat({meta.type, meta.title, meta.group, meta.image, meta.window_type,
                meta.pixel_render, meta.pixel_state}, "|"),
                "tui_desktop.window|Registry Editor|Settings|regedit|app|"
                    .. "windows.shell.sdk:render|windows.regedit:window")
            -- An entry without the field opens for everyone, silently: the
            -- compositor asks the logged-on person's scope only when it is named.
            test.eq(meta.requires, "windows.admin")
            for _, size in ipairs({32, 16}) do
                local picture, why = images.get("regedit", size)
                test.not_nil(picture, "regedit@" .. tostring(size) .. ": " .. tostring(why))
            end
        end)

        test.it("reads the registry and cannot change it", function()
            local data = entry_of("windows.regedit:window")
            local security: any = data.security or {}
            test.eq(table.concat(security.policies or {}, ","), "windows.regedit:window_scope")
            local scope = entry_of("windows.regedit:window_scope")
            local actions: any = {}
            for _, action in ipairs(scope.policy.actions) do actions[action] = true end
            test.is_true(actions["registry.find"] and actions["registry.get"] or false, "reads the registry")
            for _, forbidden in ipairs({"registry.apply", "process.spawn", "exec.run"}) do
                test.is_nil(actions[forbidden], forbidden .. " is not the viewer's")
            end
        end)

        test.it("the expander box and the keys of the SDK tree expand, move and keep the selection", function()
            local state = regedit.session(records, nil)
            local context = {width = 78, height = 22, close = function() end}
            test.eq(#state.rows, 3)
            local function plan_now()
                return ui.plan(regedit.definition.view(state, context), 78, 22, ui.interaction())
            end
            local plan = plan_now()
            local tree = plan.by_id.tree
            -- Row 2 is "app" at depth 1; the expander box is in the expander
            -- column of depth 1.
            local columns = ui.tree_columns(1)
            local interaction = ui.interaction()
            local toggled = ui.event(plan, interaction, {type = "mouse", action = "press", button = "left",
                x = tree.rect.x + columns.expander, y = tree.rect.y + 1})
            test.eq(toggled.type, "toggle")
            regedit.definition.update(state, toggled, context)
            test.is_true(state.expanded["app"], "the expander box expanded app")
            test.eq(state.selected, "", "the expander box does not change the selection")
            plan = plan_now()
            local picked = ui.event(plan, interaction, {type = "mouse", action = "press", button = "left",
                x = tree.rect.x + 10, y = tree.rect.y + 4})
            test.eq(picked.type, "select")
            regedit.definition.update(state, picked, context)
            test.eq(state.selected, "windows")
            interaction.focus = "tree"
            local function key(name)
                plan = plan_now()
                local action = ui.event(plan, interaction, {type = "key", action = "press", key_type = name, key = name})
                if action then regedit.definition.update(state, action, context) end
            end
            key("right")
            test.is_true(state.expanded["windows"], "right on a collapsed one — expand")
            key("right")
            test.eq(state.selected, "windows.shell", "right on an expanded one — to the first child")
            key("right")
            test.is_true(state.expanded["windows.shell"])
            key("left")
            test.is_nil(state.expanded["windows.shell"], "left on an expanded one — collapse")
            key("left")
            test.eq(state.selected, "windows", "left on a collapsed one — to the parent")
            key("end")
            test.eq(state.selected, "windows.shell", "end — the last visible row")
            local tree_view = regedit.definition.view(state, context)
            test.eq(tree_view.children[3].fields[1].text, "Registry\\windows\\shell")
        end)

        test.it("a long tree scrolls and keeps the selection on screen", function()
            local many = {}
            for index = 1, 60 do many[index] = {id = "ns" .. string.format("%02d", index) .. ":x", kind = "k", meta = {}, data = {}} end
            local state = regedit.session(many, nil)
            local context = {width = 78, height = 22, close = function() end}
            test.eq(#state.rows, 61)
            local interaction = ui.interaction()
            interaction.focus = "tree"
            for _ = 1, 40 do
                local plan = ui.plan(regedit.definition.view(state, context), 78, 22, interaction)
                local action = ui.event(plan, interaction, {type = "key", action = "press", key_type = "down", key = "down"})
                regedit.definition.update(state, action, context)
            end
            test.eq(state.selected, "ns40")
            local plan = ui.plan(regedit.definition.view(state, context), 78, 22, interaction)
            local tree = plan.by_id.tree
            local lines = tree.page
            test.eq(interaction.offsets.tree, 41 - lines, "the selection is on the last row of the screen")
            ui.event(plan, interaction, {type = "mouse", action = "wheel", button = "wheel_down", x = tree.rect.x + 2, y = tree.rect.y + 2})
            test.eq(interaction.offsets.tree, 41 - lines + 3)
            plan = ui.plan(regedit.definition.view(state, context), 78, 22, interaction)
            ui.event(plan, interaction, {type = "mouse", action = "press", button = "left",
                x = tree.rect.x + tree.rect.w - 1, y = tree.rect.y})
            test.eq(interaction.offsets.tree, 41 - lines + 2, "the scrollbar arrow — by one row")
            -- The window was stretched: the offset was clamped to the new height.
            plan = ui.plan(regedit.definition.view(state, {width = 100, height = 40}), 100, 40, interaction)
            test.is_true(interaction.offsets.tree <= 61 - plan.by_id.tree.page, "the offset is clamped to the new height")
        end)

        test.it("the menu has no permanently disabled items, and each remaining one does something", function()
            local state = regedit.session(records, nil)
            local closed = 0
            local context = {width = 78, height = 22, close = function() closed = closed + 1 end}
            local titles, ids, disabled = menu_of(regedit.definition.view(state, context))
            test.eq(titles, "Registry View Help", "no \"Edit\" with a disabled Copy Path")
            test.eq(ids, "refresh exit refresh about")
            test.is_false(disabled)

            regedit.definition.update(state, {type = "activate", id = "refresh", menu = "bar"}, context)
            test.is_true(state.count > #records, "Refresh reread the registry: " .. tostring(state.count))

            regedit.definition.update(state, {type = "activate", id = "about", menu = "bar"}, context)
            test.is_true(state.about)
            local plan = ui.plan(regedit.definition.view(state, context), 78, 22, ui.interaction())
            test.not_nil(plan.by_id.about_ok, "the sheet has \"OK\"")
            test.is_true(label_width(plan, "Registry Editor") >= #"Registry Editor", "the sheet title is visible whole")
            regedit.definition.update(state, {type = "key", key_type = "esc", key = "esc"}, context)
            test.is_false(state.about, "Esc closes the sheet")
            test.eq(closed, 0, "and not the window")
            regedit.definition.update(state, {type = "activate", id = "about"}, context)
            regedit.definition.update(state, {type = "activate", id = "about_ok"}, context)
            test.is_false(state.about, "\"OK\" closes the sheet")

            regedit.definition.update(state, {type = "activate", id = "exit", menu = "bar"}, context)
            test.eq(closed, 1, "Exit closes the window")
        end)

        test.it("an empty filter returns the whole registry, and the tree is built from it", function()
            -- The provider reads the registry exactly this way; if an empty
            -- filter one day comes to mean "nothing", the window will show an
            -- empty tree and call it the registry.
            local found, err = registry.find({})
            test.is_nil(err)
            test.is_true(#found > 30, "the harness has more than thirty entries, found " .. tostring(#found))
            local root = reg_model.build(found)
            local own = reg_model.find(root, "windows.regedit:window")
            test.not_nil(own, "the viewer's own entry must be found in the tree")
            test.eq(own.record.kind, "process.lua")
        end)

        test.it("draws a tree with expanded branches and an entry with fields into test/shots/regedit.png", function()
            local sample = {
                {id = "app:db", kind = "db.sql.sqlite", meta = {comment = "Stand database"}, data = {file = ".wippy/app.db"}},
                {id = "app:api", kind = "http.router", meta = {}, data = {prefix = "/api/v1"}},
                {id = "app.desktop:window_calc", kind = "process.lua", meta = {type = "tui_desktop.window", title = "Calculator"}, data = {}},
                {id = "windows.shell.theme:chrome", kind = "library.lua", meta = {comment = "Cell theme"}, data = {source = "file://chrome.lua", modules = {"tty"}}},
                {id = "windows.shell.theme:pixels", kind = "library.lua", meta = {comment = "Pixel primitives"}, data = {source = "file://pixels.lua"}},
                {id = "windows.shell.theme:palette", kind = "library.lua", meta = {}, data = {}},
                {id = "windows.shell:shell", kind = "process.lua", meta = {title = "Windows 95 shell"}, data = {method = "main", modules = {"gfx", "tty"}}},
                {id = "windows.shell:terminal", kind = "terminal.host", meta = {}, data = {hide_logs = true}},
                {id = "wippy.security:process", kind = "security.group", meta = {}, data = {}},
            }
            local session = regedit.session(sample, nil)
            for _, key in ipairs({"", "windows", "windows.shell", "windows.shell.theme"}) do
                session.expanded[key] = true
            end
            session.rows = reg_model.flatten(session.root, session.expanded)
            session.selected = "windows.shell.theme:chrome"
            local context = {width = 78, height = 22, close = function() end}
            local tree = regedit.definition.view(session, context)
            test.is_nil(ui.problem(tree))
            local store = rasters.store()
            store.begin()
            local placed = assert(render.placement({id = "regedit", state_revision = 1, content_state = {sdk = 1, revision = 1,
                ui = tree, interaction = ui.interaction()}}, {x = 1, y = 1, cols = 78, rows = 22},
                CELL, {face = face_font()}, store))
            assert(assert(fs.get("app:shots")):writefile("regedit.png", assert(placed.raster:encode("png"))))
            test.eq(placed.cols .. "x" .. placed.rows, "78x22")
        end)
    end)
end

local run_cases = test.run_cases(define_tests)
return {run = function(options) return run_cases(options) end}
