# Sandblock Studio Plugin

This repository owns the final Sandblock plugin installed in Roblox Studio.
The current implementation includes the outbound MCP bridge, a Sandblock-
branded dock widget, and a native Luau component library with an interactive
Studio gallery. It also embeds the headless client adapter built from the
pinned `../sandblock-rojo` fork. Approved project/runtime selection and
automatic binding remain the next integration step.

## Studio UI

The toolbar button opens a `DockWidgetPluginGui`; opening the panel does not
start anything. The Runtime tab is one page: the selected project and how this
Studio place relates to it, the MCP bridge and Rojo sync rows, and a single
**Connect** button.

Connecting is project-first:

1. **Connect** with no project selected opens the picker.
2. The picker lists the projects registered in Sandblock Code, most relevant
   first, with their main place, Rojo project file, and whether that project is
   already being served — including by a Rojo someone started by hand, which is
   reused rather than duplicated. It lists nothing this plugin discovered by itself.
3. Choosing a project asks Sandblock Code to run the pinned Rojo build in that
   project's repository and returns the loopback port it was given.
4. The MCP bridge and the fork-owned Rojo session then connect together, and
   **Disconnect** stops both. Stopping the sync in Studio leaves the server
   running; Sandblock Code owns its lifecycle.

While a session is live the Rojo row shows how fresh the sync is — **Synced just
now**, then **12 seconds ago**, **2 minutes ago**, in Rojo's own wording — with
the project name and the number of instances the last patch touched. An
apparently healthy connection that quietly stopped syncing is visible that way
instead of staying green. The plugin also reports each connect, patch, and
disconnect to Sandblock Code, which keeps the project's sync history beside its
tool history.

The chosen project is remembered as an opaque runtime id, so reconnecting later
is one click. Before anything starts, the plugin compares the open place with
the project's `mainPlaceId` and refuses a mismatch instead of syncing a project
into the wrong place. The MCP connection first claims its gateway slot with an
immediate request, so its status does not wait for the first 25-second
long-poll response before showing **Connected**.

The Components tab renders the library at the same narrow width used by the
real plugin.

The Settings tab persists local connection overrides through Roblox plugin
settings. It exposes the MCP gateway URL, the Sandblock Code runtime URL, the
manual Rojo fallback URL, reconnect delay, two-way sync, fallback behavior,
payload validation, external script opening, and Rojo timing logs. Saving while
connected restarts both services with the new values; non-loopback endpoints are
rejected. The manual Rojo URL is used only when no project is selected and the
runtime service cannot be reached — a server someone started by hand.

`src/UI/Components.lua` is parent-agnostic and can mount its native
`GuiObject`s under a dock widget, `ScreenGui`, or another GUI container. It
rebuilds the useful visual vocabulary of the pinned Rojo plugin in Sandblock's
semantic tokens without copying Roact, Flipper, Rojo's red brand assets, or web
components.

| Rojo UI capability | Sandblock component |
| --- | --- |
| Bordered container and sliced surface | `Surface`, `BorderedContainer`, `SlicedImage` |
| Text and icon actions with touch feedback | `Button`, `TextButton`, `IconButton`, `ChoiceButton` |
| Text entry, search, select, and action menus | `TextInput`, `TextArea`, `SearchField`, `Dropdown`, `DropdownMenu` |
| Boolean, range, and exclusive selection | `Checkbox`, `Switch`, `Slider`, `RadioGroup` |
| Navigation and disclosure | `TabButton`, `Tabs`, `Accordion`, `Divider` |
| Header, tag, status, class icon, spinner | `Header`, `Tag`, `StatusBadge`, `ClassIcon`, `Spinner` |
| Feedback, loading, and empty states | `Alert`, `Progress`, `Skeleton`, `EmptyState` |
| Tooltips, notifications, and dialogs | `Tooltip`, `ToastHost`, `Modal` |
| Scrolling and virtualized lists | `ScrollView`, `ScrollingFrame`, `VirtualList` |
| Patch, string, and table visualization | `DiffPanel`, `PatchVisualizer`, `StringDiff`, `TableDiff` |
| Editable image wrapper | `EditableImage` |

`Slider` uses Studio's native `UIDragDetector` pointer capture and keeps mouse
or touch movement until release, even after it leaves the whole component.
`Dropdown` and `DropdownMenu` portal their open menu
to the dock's top GUI layer so scrolling surfaces cannot cover or clip it.
Prominent `Button` instances can use `Appearance = "Tactile"`, which adds a
stationary lower-z-index depth element; only the button face moves down while
pressed.

The canonical Sandblock colors, typography, spacing, radii, and health states
live in `src/UI/Theme.lua`. The anchor accent is `#f6c944`.

The toolbar and dock header use the uploaded Sandblock app icon configured as
`PluginIcon` in `src/Config.lua` (`rbxassetid://82545901411321`).

Roblox-hosted Sandblock Studios media is available from `src/UI/Assets.lua`.
Consumers use stable names such as `Assets.Brand.Mark.White`,
`Assets.Brand.WordmarkCompact.Yellow`, or
`Assets.Illustrations.Audience.VideoGame` instead of scattering numeric asset
IDs through UI code. The exact transparent upload inputs and pending upload
state live under `assets/roblox/`.

## Hot reload in Studio

Roblox only exposes the real `plugin` object to an installed plugin, so code in
`ReplicatedStorage` cannot be a complete plugin by itself. Development uses a
small, stable loader installed once; the full Sandblock plugin is then synced
to `ReplicatedStorage.SandblockStudioPlugin` and restarted on every source-tree
change without restarting Studio.

Build and install the loader once:

```bash
aftman install
rojo build dev-loader.project.json -o build/SandblockStudioDevLoader.rbxm
```

Then, for normal development, serve the real plugin tree:

```bash
rojo serve dev.project.json
```

Connect the standard Rojo Studio plugin to the server. It will sync `src/` into
`ReplicatedStorage.SandblockStudioPlugin`; the loader clones that tree to avoid
Roblox's `require` cache, keeps one stable toolbar and dock shell, destroys the
previous mounted Sandblock session, and starts the fresh `Main` module with its
retained plugin context. The source instance's `HotReloadRevision` and
`HotReloadState` attributes expose the current reload status in Studio.

The standard Rojo plugin is only the development bootstrap that synchronizes
the Sandblock plugin's own source tree. Keep it connected for self-hosted hot
reload: replacing the source tree intentionally restarts the embedded session.
For a game project, the final Sandblock plugin uses its unified
**Connect services** action and the vendored fork adapter.

Only loader changes require rebuilding/reloading the local loader plugin. UI,
bridge, handler, configuration, and entry-module changes hot reload through
Rojo.

## Production build

Install the pinned toolchain with Aftman, then build the plugin model:

```bash
aftman install
rojo build default.project.json -o build/SandblockStudioPlugin.rbxm
```

Install this full model only for production-like verification. Open
**Sandblock** from the Plugins toolbar and inspect both tabs at narrow and wide
dock sizes.

## Pinned Rojo adapter

`vendor/rojo/SandblockRojoAdapter.rbxm` is generated from
`../sandblock-rojo/sandblock-adapter.project.json`. The model contains the
headless protocol and reconciliation modules, not upstream Rojo product UI.
Its MPL-2.0 license and provenance notice are preserved beside the artifact.

Regenerate the adapter after a reviewed fork change:

```bash
rojo build ../sandblock-rojo/sandblock-adapter.project.json \
  -o vendor/rojo/SandblockRojoAdapter.rbxm
```

Compatibility is currently pinned to Rojo `7.7.0-rc.1`, protocol `5`.

## Ownership boundary

- Sandblock Code owns repository paths and running project metadata. It also
  owns the Rojo process: this plugin asks for a project by opaque id and gets a
  loopback URL back, never a path and never a port it picked itself.
- This plugin receives approved runtime descriptors over loopback HTTP from the
  runtime service (default `http://127.0.0.1:3071`, requests marked with the
  `X-Sandblock-Runtime` header).
- The plugin validates the current `PlaceId` before starting a runtime.
- The Rojo fork owns sync-engine changes; this repository owns Sandblock UI and
  MCP/Studio behavior.
