# Roblox image assets

These transparent PNGs are Roblox-ready derivatives of the canonical Sandblock
Studios files in `../../../../sandblock-ui/assets/`. The source files remain
owned by `sandblock-ui`; this directory preserves the exact upload inputs for
the native Studio renderer.

The Roblox IDs accepted on 2026-08-21 live in `src/UI/Assets.lua`, which is the
plugin's single source of truth for runtime asset references. Ten brand variants
and ten audience illustrations are currently available.

Roblox rejected the remaining decorative and process illustrations after the
first 20 uploads with HTTP 403 `User is moderated`. Their PNG inputs remain in
`illustrations/`, and their stable names are listed under `PendingUploads` in
`src/UI/Assets.lua` so a later authorized upload can complete the registry
without regenerating them.
