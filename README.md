# windows/regedit — Registry Editor

A module of the Windows 95 shell for the terminal desktop
([windows/shell](https://github.com/wippy-windows/windows) on
[windows/tui-desktop](https://github.com/wippy-windows/tui-desktop)): it adds
the **Registry Editor** to Start → Settings — a viewer of the runtime's
registry in the look of Windows 95 regedit.

On the left, a tree of namespaces split by dots and of the entries inside
them; on the right, `kind`, `meta.*` and `data.*` of the selected entry; at
the bottom, the path `Registry\a\b\name`. The [+] box, Enter and → expand,
← collapses or goes to the parent, the wheel and the scrollbar scroll; F5 (or
Registry → Refresh) rereads the registry. The tree, the table, the menu and
the status bar are the shell SDK's components; the module's own code is the
tree model.

**Read-only.** Changing an entry changes the running application, and that
belongs in a control panel under its own actor (the shell's FR-004 §3.4). The
window's policy `windows.regedit:window_scope` has `registry.get` and
`registry.find` but not `registry.apply`; the window has nothing to write
with.

**Only an administrator opens it.** The window shows every registry entry of
the runtime, so its entry names `requires: windows.admin`, and the base's
compositor asks the logged-on person's scope before opening it. An
application grants `windows.admin` to its administrators; a group whose
policy allows `*` has it already. Nothing else is asked of the application.

## Inside

- `windows.regedit:model` — the pure model: the tree from a list of entries
  (folders before entries, alphabetically), the visible rows for the
  expanded keys, the path, the fields of an entry on one line each.
- `windows.regedit:window` — the process on the shell's SDK
  (`windows.shell.sdk:app`): reads the registry once on opening, then on F5.
  Its picture `regedit` comes from the shell's catalog.
- `windows.regedit:window_scope` — its permissions: the process context,
  sending state to the compositor, reading the registry.

## Developing

```bash
make setup     # resolve the dependencies from the Hub (once, and after changing them)
make check     # the repository's invariants
make lint      # late locals, then wippy lint of this namespace and the harness
make test      # the harness in test/: the model, the window, a shot in test/shots/
make publish   # to the Hub, after `wippy auth login`
```

**A local build of the runtime fork is required**
([wippy-windows/runtime](https://github.com/wippy-windows/runtime), branch
`wippy-projects`): the shell declares the `gfx` module, which the release
runtime does not have, and `wippy` from PATH does not load the shell at all.
The Makefile's `WIPPY` names the build; override it with `make test WIPPY=…`.

The window SDK is documented in [docs/sdk.md](docs/sdk.md), a copy of the
shell's guide, and the skill for agents in
[skills/wippy-window-app/SKILL.md](skills/wippy-window-app/SKILL.md); the
rules of this repository are in [AGENTS.md](AGENTS.md).

Made from [the Windows module template](https://github.com/wippy-windows/module-template) for
modules of the Windows 95 shell. Repository:
https://github.com/wippy-windows/regedit. The Registry Editor was part of
`windows/shell` up to 0.1.1.

## Licence

MIT.
