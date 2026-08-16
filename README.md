# Sandblock Studio Plugin

This repository owns the final Sandblock plugin installed in Roblox Studio.
The current implementation includes the outbound MCP bridge, a Sandblock-
branded dock widget, and a native Luau component library with an interactive
Studio gallery. It also embeds the headless client adapter built from the
pinned `../sandblock-rojo` fork. Approved project/runtime selection and
automatic binding remain the next integration step.

## Studio UI

The toolbar button opens a `DockWidgetPluginGui`; opening the panel does not
start the bridge automatically. The Runtime tab shows the current Studio place,
MCP health, the pinned Rojo client/protocol, live sync state, and manual
recovery actions. One **Connect services** action starts both the MCP bridge and
the fork-owned Rojo session; disconnecting stops both together. It does not
create a second Rojo UI. The MCP connection first claims its gateway slot with
an immediate request, so its status does not wait for the first 25-second
long-poll response before showing **Connected**.
The Components tab renders the library at the same narrow width used by the
real plugin.

The Settings tab persists local connection overrides through Roblox plugin
settings. It exposes the MCP and Rojo loopback URLs, reconnect delay, two-way
sync, fallback behavior, payload validation, external script opening, and Rojo
timing logs. Saving while connected restarts both services with the new values;
non-loopback endpoints are rejected.

`src/UI/Components.lua` is parent-agnostic and can mount its native
`GuiObject`s under a dock widget, `ScreenGui`, or another GUI container. It
rebuilds the useful visual vocabulary of the pinned Rojo plugin in Sandblock's
semantic tokens without copying Roact, Flipper, Rojo's red brand assets, or web
components.

| Rojo UI capability | Sandblock component |
| --- | --- |
| Bordered container and sliced surface | `Surface`, `BorderedContainer`, `SlicedImage` |
| Text and icon actions with touch feedback | `Button`, `TextButton`, `IconButton` |
| Checkbox, dropdown, and text entry | `Checkbox`, `Dropdown`, `TextInput` |
| Header, tag, status, class icon, spinner | `Header`, `Tag`, `StatusBadge`, `ClassIcon`, `Spinner` |
| Tooltips and notifications | `Tooltip`, `ToastHost`, `Modal` |
| Scrolling and virtualized lists | `ScrollView`, `ScrollingFrame`, `VirtualList` |
| Patch, string, and table visualization | `DiffPanel`, `PatchVisualizer`, `StringDiff`, `TableDiff` |
| Editable image wrapper | `EditableImage` |

The canonical Sandblock colors, typography, spacing, radii, and health states
live in `src/UI/Theme.lua`. The anchor accent is `#f6c944`.

The toolbar and dock header use the uploaded Sandblock app icon configured as
`PluginIcon` in `src/Config.lua` (`rbxassetid://82545901411321`).

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

- Sandblock Code owns repository paths and running project metadata.
- This plugin receives approved runtime descriptors over loopback HTTP.
- The plugin validates the current `PlaceId` before selecting a runtime.
- The Rojo fork owns sync-engine changes; this repository owns Sandblock UI and
  MCP/Studio behavior.
