# Peripheral text panel API v1

Peripheral 0.10.0 exposes `PeripheralAPI`. An addon can publish its own reference
data or a separate adapter can translate an existing addon’s public data.
Neither needs to edit Peripheral. The player enables the panel and owns its
side, stack position, height, font, and minimize state.

If your addon requires Peripheral, add `## Dependencies: ForeverWorkspace` to
its TOC. If your integration is optional, use `## OptionalDeps: ForeverWorkspace`
and check for the API before registering. `ForeverWorkspace` is the install
folder name retained for saved settings. Register once per UI session.

```lua
local api = PeripheralAPI
if not api or api.version ~= 1 then return end

local panel, reason = api.RegisterTextPanel({
    apiVersion = 1,
    id = "myaddon.progress",
    title = "My progress",
    defaultSide = "right",
})
if not panel then return end
panel:SetText("Objectives complete\n3 / 5")
```

- `RegisterTextPanel(definition)` returns a handle or `nil, reason`. IDs use
  `addon.panel` with lowercase ASCII letters, digits, hyphens and underscores
  (64 bytes max). Choose a stable namespace and ID; duplicates are rejected.
  Titles are single-line plain text (48 bytes max); `defaultSide` is `left` or
  `right`, defaulting to `right`. Up to 32 external panels may register.
- `handle:SetText(text)` replaces the latest value, returning `true` or
  `nil, reason`. Use plain UTF-8 text (4,096 bytes max, newlines permitted).
  Empty text shows a waiting message. Invalid text leaves the previous value.
  WoW markup and secret values are rejected. Publish from your normal data
  events. Text is buffered; visible panels redraw at most twice per second
  during normal updates, outside combat.
- `handle:IsVisible()` reports whether an expanded panel is currently shown.
  Use it to avoid expensive optional work, but still publish an initial value
  so a newly enabled panel has content.

New panels begin removed. In `/peripheral`, scroll the panel list if needed,
select the panel, then **Restore to sides → Apply trial → Keep**. Existing
preferences are retained by ID if the provider is disabled and later returns.
Late registration adds a settings entry outside combat; it never activates the
viewport or changes the applied layout by itself.

This API does not accept frames, scripts, click handlers, or protected actions.
Interactive window docking is a separate integration that needs frame ownership,
native behavior and restoration to be validated for the particular addon.

The project includes a separately installable `PeripheralExample` addon. Its
panel shows a world-entry count and demonstrates the same public registration
path as an independent provider. The API and example have mock-client coverage;
live Retail and Forever API tests are pending.
