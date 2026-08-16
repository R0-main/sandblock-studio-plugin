# Sandblock Rojo adapter

`SandblockRojoAdapter.rbxm` is generated from the sibling `sandblock-rojo`
repository at the pinned Rojo `7.7.0-rc.1` baseline. It exposes protocol version
5 through `Plugin.SandblockAdapter` and intentionally contains no Rojo product
UI entry point.

Regenerate it from the workspace with:

```bash
cd sandblock-studio-plugin
rojo build ../sandblock-rojo/sandblock-adapter.project.json \
  -o vendor/rojo/SandblockRojoAdapter.rbxm
```

The upstream and forked sources are licensed under the Mozilla Public License
2.0. The corresponding license is preserved in `LICENSE.txt` beside the
generated model.
