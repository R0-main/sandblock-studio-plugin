# Sandblock Studio Plugin

This repository owns the final Sandblock plugin installed in Roblox Studio.
The current implementation is the extracted outbound MCP bridge; the next
increment adds a Sandblock-branded dock widget, project/runtime selection, and
an adapter to the pinned Rojo client from `../sandblock-rojo`.

## Build

Install the pinned toolchain with Aftman, then build the plugin model:

```bash
aftman install
rojo build default.project.json -o build/SandblockStudioPlugin.rbxm
```

During local development, copy the output to Roblox Studio's local Plugins
folder or use Rojo's plugin build/install support.

## Ownership boundary

- Sandblock Code owns repository paths and running project metadata.
- This plugin receives approved runtime descriptors over loopback HTTP.
- The plugin validates the current `PlaceId` before selecting a runtime.
- The Rojo fork owns sync-engine changes; this repository owns Sandblock UI and
  MCP/Studio behavior.
