-- The registry viewer's model, pure: the tree from a list of entries, the
-- visible rows, the path as regedit writes it, and the fields of an entry.
-- The records are examples; the namespaces are the shell's because they are
-- the ones a person sees first.
local test = require("test")
local reg_model = require("reg_model")

local records = {
    {id = "app:db", kind = "db.sql.sqlite", meta = {comment = "database"}, data = {file = ":memory:"}},
    {id = "chicago.shell.theme:chrome", kind = "library.lua", meta = {comment = "theme"},
        data = {source = "file://chrome.lua", modules = {"tty"}}},
    {id = "chicago.shell.theme:pixels", kind = "library.lua", meta = {}, data = {}},
    {id = "chicago.shell:shell", kind = "process.lua", meta = {title = "Shell"}, data = {}},
    {id = "app.desktop:window_calc", kind = "process.lua", meta = {type = "tui_desktop.window"}, data = {}},
}

local function define_tests()
    test.describe("registry viewer model", function()
        test.it("lays namespaces out by dots, folders before entries", function()
            local root = reg_model.build(records)
            test.eq(#root.children, 2, "two root namespaces: app and chicago")
            test.eq(root.children[1].label, "app")
            local app = root.children[1]
            test.eq(app.children[1].kind, "folder", "the desktop folder comes before the db entry")
            test.eq(app.children[1].label, "desktop")
            test.eq(app.children[2].label, "db")
            local windows = reg_model.find(root, "chicago.shell")
            test.not_nil(windows)
            test.eq(#windows.children, 2, "the shell folder and the shell entry side by side")
            test.eq(windows.children[1].kind, "folder")
            test.eq(windows.children[2].key, "chicago.shell:shell")
        end)

        test.it("visible rows depend on the expanded keys, the path is written as in regedit", function()
            local root = reg_model.build(records)
            local expanded: any = {}
            expanded[""] = true
            local rows = reg_model.flatten(root, expanded)
            test.eq(#rows, 3, "the root and two namespaces")
            test.eq(rows[2].depth, 1)
            test.is_true(rows[2].has_children)
            test.is_false(rows[2].expanded)
            expanded["chicago"] = true
            expanded["chicago.shell"] = true
            rows = reg_model.flatten(root, expanded)
            test.eq(rows[#rows].label, "shell")
            test.eq(rows[#rows].kind, "entry")
            test.is_false(rows[#rows].trail[#rows[#rows].trail], "the last sibling — the line does not go down")
            test.eq(reg_model.path("chicago.shell.theme:chrome"), "Registry\\chicago\\shell\\theme\\chrome")
            test.eq(reg_model.path(""), "Registry")
            test.eq(reg_model.parent_key("chicago.shell.theme:chrome"), "chicago.shell.theme")
            test.eq(reg_model.parent_key("chicago.shell"), "chicago")
            test.eq(reg_model.parent_key("app"), "")
        end)

        test.it("entry fields — kind, meta and data alphabetically, tables on one line", function()
            local root = reg_model.build(records)
            local node = reg_model.find(root, "chicago.shell.theme:chrome")
            local values = reg_model.values(node, function(v) return "{json}" end)
            test.eq(values[1].name, "kind")
            test.eq(values[1].data, "library.lua")
            test.eq(values[2].name, "meta.comment")
            test.eq(values[2].data, "\"theme\"")
            test.eq(values[3].name, "data.modules")
            test.eq(values[3].data, "{json}", "a table is encoded by whatever was given")
            test.eq(values[4].name, "data.source")
            local folder = reg_model.values(reg_model.find(root, "app"), nil)
            test.eq(folder[1].name, "(Default)")
            test.eq(folder[2].data, "2")
            test.eq(reg_model.stringify("first\nsecond", nil), "\"first…\"", "a source is shown by its first line")
        end)
    end)
end

local run_cases = test.run_cases(define_tests)
return {run = function(options) return run_cases(options) end}
