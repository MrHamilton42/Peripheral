PERIPHERAL 0.11.6 - DEVELOPMENT PROTOTYPE / BETA
Retail test target: 12.1.5.70688, interface 120105.
Forever is the intended target; compatibility remains unverified.
No CurseForge approval or public release is implied by this proposed package.

NAME CHANGE / UPGRADING TO PERIPHERAL
Peripheral is the new name for Forever Workspace. Version 0.7.1 changes branding
and adds the project owner's supplied logo; it retains 0.7.0 functionality.
Keep the installation folder named ForeverWorkspace and the manifest named
ForeverWorkspace.toc. The visible addon title is Peripheral. Existing
ForeverWorkspaceDB SavedVariables, frame identifiers, FWS Center layout names
and configuration format 1 are deliberately unchanged to retain personal data.
Do not install a second copy under a Peripheral folder alongside the old one.
Use /peripheral or the existing /fws; both support the same subcommands.
Assets/Peripheral.svg is the supplied source; PNG and uncompressed TGA exports
are included for previews and the in-game logo. Configurator.html embeds its
logo and still works as one self-contained local page.

PRIMARY SETUP - WINDOWS HELPER 0.4.0
1. Install Peripheral and launch the separately distributed helper. Choose
   Retail, Main and the side strips, then click Start Peripheral.
2. On first setup, start or fully restart WoW to discover Peripheral - Windows
   Helper Bridge. Enable both addons, enter a character in standard Windowed
   mode, then click Start Peripheral again.
3. Check the preview and Keep preview within 30 seconds. Reload WoW if the
   helper sent a new layout, then /peripheral -> Apply trial -> Keep.
4. On later sessions with the same kept layout, Start Peripheral in Windows
   and Use saved layout in WoW. The addon still starts disabled. Close the
   helper or click Restore window to return the native window to its old bounds.

Changed monitors or strip widths require a new preview. Resend layout and JSON
fallback are under Advanced. Neither the helper nor HTML changes the main
addon's installed files. The helper uses its own bridge; the addon saves
configuration in SavedVariables. Initial bridge discovery is user-confirmed on
Retail; the streamlined path still needs a live retest.

[PERIPHERAL_HELPER_LINK]
Windows helper releases: https://github.com/MrHamilton42/Peripheral-Windows-Helper/releases
[/PERIPHERAL_HELPER_LINK]

FALLBACK SETUP - HTML / NO WINDOWS HELPER REQUIRED
1. Extract the ForeverWorkspace folder into WoW's Interface\AddOns folder.
   ForeverWorkspace.toc must be directly inside that folder. Start/restart the
   client so the new manifest and Configuration.lua are loaded.
2. In Explorer, open ForeverWorkspace\Configurator.html directly in Chrome or
   Edge. No server, Node.js, extension or helper installation is required.
3. Try Detect monitors, or enter monitor rectangles manually. The starting
   numbers are examples. Browser permission may be denied/unavailable for a
   local file; manual entry is always available.
4. Verify physical pixels against Windows Display settings. Browser rectangles
   are CSS/logical coordinates. Uniform per-screen DPR can provide candidate
   physical coordinates, but requires confirmation. Mixed-DPI detection leaves
   physical rectangles blank for manual entry. Browser zoom is not OS scaling.
5. Choose Main and one or both side screens. Set strip widths and work insets
   for taskbars. Check the footprint preview and confirm the physical values.
6. Copy configuration. If clipboard access fails, Select text then Ctrl+C.
   In WoW: /fws import, paste JSON, then Import / save only. This stores data in
   SavedVariables; it does not activate or write installed addon files.
7. In Graphics settings choose standard Windowed, then /fws align. Request
   window size if supported. Check the observed client size: a successful API
   call alone does not prove the engine accepted the requested span.
8. If the API is missing/capped, use normal window borders/Graphics settings to
   size the client area near the target. Cancel any API size trial and finish
   restoration BEFORE resizing manually. In /fws align, Fit current window can
   save a client within 256 pixels of the target width and up to 256 pixels
   shorter while keeping Main's full width. It adjusts outer padding/strips and
   bottom height. /fws fit performs the same action. Fit never resizes the native window
   or activates the viewport. Previous / working restores the prior geometry.
   The HTML Window border allowance offers explicit edge trims as an alternative.
   Manually move the window until the green Main left,
   right and top guides match the game monitor. Amber guides are a scaled
   preview while the size differs. Alt+Space, Move can help on Windows. Title bar
   and borders remain present without a helper; account for them in the position.
9. Apply trial -> Keep. Apply has a 20-second timeout. An alignment size request
   has a 30-second timeout until a viewport trial starts. Cancel / restore is
   always available. Center Blizzard HUD is optional after Keep.

CLIENT AREA / PHYSICAL POSITION
The target origin is the client area's desktop top-left. Title bar and borders
are outside it; don't size the outer window to the target client dimensions.
WoW and the browser cannot report the native WoW window's current desktop
position to this addon. The guides require visual/manual alignment. No measured
"move another N pixels" offset is available. Windows snapping/maximizing and the
client may cap window sizes. If the engine cannot produce the requested span,
do not Keep a mismatched layout; change geometry or use the optional helper.
Unused gaps inside the rectangular WoW window still cover desktop applications.

SETTINGS AND PANEL BEHAVIOR
/fws lists Party, Raid, Dungeon, Quests, Minimap, TomTom coordinates, Spoken narrator, Bags, Left dock, Right dock
and Setup / Import on the left;
the selected settings appear on the right. Side-panel Settings buttons select
the matching entry. Switching entries preserves unsaved edits.
- Quests and Party/Raid summaries use live Blizzard data with scrolling.
- On Retail, Dungeon reference lists bosses for your current dungeon or raid.
  Use Open full guide outside combat to open Blizzard's Adventure Guide on
  Main when it fits. Outside an instance, the guide opens on Dungeons.
  DungeonJournal on Forever is a separate integration still to be implemented.
- The spellbook, talents, character skills, professions and Collections
  windows stay within Main when they fit. Open them as usual after applying
  the viewport. Placement changes wait until combat ends.
- Spoken narrator is an optional side panel for the separately installed
  Spoken addon. Select Spoken narrator in /peripheral, choose Restore to
  sides, then Apply trial and Keep. The panel shows the current speaker,
  transcript and waiting count, with Pause / Resume and Skip. Spoken
  restarts the current line when resuming.
- External addons can register optional read-only text panels through
  PeripheralAPI v1. See API.md for the contract. The panel list scrolls when
  more panels are available. Providers do not control monitor placement.
- TomTom coordinates is an optional read-only panel, removed by default. Install
  TomTom separately and enable its coordinates feed in /tomtom > Data Feed
  Options. In /peripheral select TomTom coordinates > Restore to sides > Apply
  trial > Keep. Walk outdoors and check that the numbers update. The panel can
  be moved, resized or minimized with the existing settings. It does not move
  TomTom's arrow, write TomTom settings, or bundle TomTom or LibDataBroker.
  Feed names and setup were checked against TomTom v4.4.0-release, listed for
  Retail, Forever and Classic. The user confirmed the TomTom panel works on
  Retail 0.9.0; the 0.10.0 provider API and Forever still need live tests.
- Text size saves immediately, individually or with Apply to all.
- Height limits, Fill, Fit content and stack order use Apply trial -> Keep.
- Each panel can select Left or Right, start minimized, or be removed from the
  sides without deleting its preferences. These changes use Apply trial -> Keep.
- Left dock and Right dock each have nine anchors, 1-3 columns and a dock-width
  percentage. Anchors position the stack INSIDE the imported side strip, not
  anywhere on the physical monitor. Panels fill columns in row order; each
  column stacks independently. Narrow strips may only fit one column. Invalid
  layouts report the conflict and retain the previous kept workspace.
- After Keep, each header's - button collapses it to a name and + restore
  button. The choice is saved; combat requests wait until combat ends. Keep an
  active trial before using header minimize. A removed panel stays in /fws.
- Interactive Party moves the native standard party frames, preserving native
  targeting, menus and health/resource rendering. Native size and alignment are
  supported. Raid-style and interactive raid frames remain unimplemented.
- Party and Raid include Invite, Start raid and Ready buttons. Invite opens a
  name box and requires Send invite. Start raid converts an existing party; it
  cannot create a solo raid. Available actions depend on group permissions and
  client APIs, and are disabled in combat. Normal Blizzard confirmations remain.
- Minimap is optional and starts removed from the sides. Restore it in /fws,
  choose a side, then Apply trial -> Keep outside combat with Edit Mode closed.
  This moves the whole native MinimapCluster through the owned Edit Mode layout,
  retaining native controls and current scale. A strip/column must fit its native
  size and header; widen the strip or use fewer columns if rejected. Minimize
  hides the native cluster outside combat; restore expands it again. Removing
  the panel or Reset returns its owned placement. Independently moved anchors
  are preserved and may require manual recovery. Measurable HUD systems snapped
  to the minimap (including the Objective Tracker) are held on Main in the
  generated Edit Mode copy. Their original snaps return on undock, unless you
  move them independently. If a linked system cannot be measured, show it or
  unsnap it in Edit Mode before routing Minimap.
- Bags has an independent Apply and save: Main, Left strip, Right strip, or
  Blizzard placement. Above side panels handles native bags and their shared
  container even when an already-saved strip becomes too small for placement.
- Center Blizzard HUD also routes supported native quest/map windows to Main.
  Native Chat placement and third-party window adapters remain future work.
- Combat-sensitive writes wait until permitted. Interactive Party uses a fixed
  reserved slot/rail, as does the expanded Minimap. Reset/restoration preserves
  independent native edits.

PERSISTENCE / RECOVERY
Login/reload always starts disabled, retaining saved geometry and preferences.
After Keep, zoning preserves the applied workspace. Actual canvas/UI-scale
changes disable stale placement. Imported geometry cannot replace an active
viewport: Reset/cancel and finish pending restoration first.
Invalid import retains prior data. Previous / working in Setup / Import restores
the last kept or previous geometry, without activating it. Keep records a working
configuration independently of temporary viewport state.
/fws reset restores the viewport and owned HUD/window/bag changes. Restore game
size reverses a requested engine size. The addon cannot restore a manual desktop
move because its original desktop position is unavailable. Alignment guides do
not capture the mouse; Cancel hides them and reverses owned trial changes.
Use /fws diag for actual canvas dimensions, requested/observed game size, native
bag layers and routing status. Recovery data stays saved if a restore fails.

DISPLAY CHANGES
The HTML page invalidates output on detected screen changes. Redetect or verify
manual values again. Monitor labels/list numbers are not durable Windows IDs.
The addon cannot enumerate Windows displays. A monitor disappearing with the
same reported client size cannot be detected automatically. After rearranging,
disconnecting or rescaling displays, cancel/reset, regenerate and align again.
The optional helper can watch actual Win32 display/work-area changes and restore
its native window span when they occur.

UPDATING FROM 0.5.x
Back up SavedVariables and the old generated Geometry.lua before replacing
files. The new code can cache a legacy FW.Geometry table in SavedVariables once
IF that old file is still loaded on its first run. It doesn't invent missing
physical monitor dimensions/desktop origin from an old partial-strip export.
If an updater already replaced the file, a bounded numeric geometry snapshot can
also be recovered from an existing saved /fws diag result. It is marked as
potentially stale and requires alignment verification or a fresh import; missing
desktop origins/whole-monitor dimensions are not invented. Without either data
source, create/import fresh JSON or recover your backup. Panel preferences remain
in ForeverWorkspaceDB throughout.
After the first 0.6 import/migration, replacing addon files preserves personal
geometry and panel preferences in SavedVariables. Do not delete those settings.
Normal setup/import never rewrites Geometry.lua or any CurseForge-managed file.

WINDOWS HELPER / OPTIONAL COMPANION
The Windows companion is distributed separately. Advanced offers JSON export
and native window recovery. See the primary setup steps above.

VERIFICATION LIMITS
0.8.0 helper bridge: automated tests exercise actual generated Lua 5.1 syntax,
strict JSON ingestion, UTF-8/injection-like labels, duplicate handoff IDs,
invalid input, preservation of manual fallback/settings, atomic replacement,
locked-file recovery and refusal to overwrite unrelated files. A hidden helper
UI preview was inspected. No real WoW client files were written and no game
window was operated in this update. First discovery, enablement, reload handoff
and the complete helper path still need live verification.
0.7.0 added routing/removal, dock anchors/columns/width, minimized panels, group
actions and the native Minimap adapter. These additions have automated mock
coverage and have NOT been tested live. The user chose to test later; no live
game window, reload, group conversion, invitation or ready check was operated
for those preparations. Earlier full Retail evidence is through 0.6.2; the user's
later 0.7.1 screenshot confirms the branded settings display and a stale manual
geometry mismatch while using the helper. Test new controls,
native interaction, combat deferral and reset/reload before relying on them.
Automated tests cover strict JSON, geometry agreement across the HTML/Lua/helper,
fresh no-helper setup, invalid import/recovery, alignment sizing/cancel/timeout,
disabled reload, saved preferences, and existing quest/Party/bag/zoning behavior.
The user confirmed file:// monitor permission prompts and successful monitor
lists in Chrome and Edge. Denied permission and clipboard fallbacks are still
simulated tests. No browser-tool protocol restriction was bypassed.
Live Retail 0.6 accepted valid JSON without activating, rejected invalid data,
and left all nine installed file hashes unchanged. It displayed alignment
guides, but the API request for a 2496x1080 span left the actual client at
1904x824. Manual resizing reached 2489x1061, but another API request shrank it
back. The size trial timed out safely. Version 0.6.2 adds explicit Fit current
window for such near-target manual dimensions and preserves a newer manual size
as a new request's recovery baseline. These changes have automated coverage;
the live fit reached 2494x1061 with a 1920x1061 Main view and green guides.
Apply and its timeout were observed live without a native resize. The fitted
configuration survived reload, with activation disabled. The user confirmed
0.6.2 Apply -> Keep stays active with side panels visible. Nine installed addon
file hashes remained unchanged through these tests. The small width-overshoot
case is automated-test covered rather than separately live verified.
An API call returning without an error is not proof that a span is supported.
Physical vertical positioning/title-bar clearance still requires user visual
verification. Full 0.6 quest/Party/bag/zoning/combat regression, monitor changes,
cold login and browser denial/copy fallback remain additional live checks.
Prior live 0.5 features are
user-confirmed; mock tests do not establish client or Forever compatibility.
See the project-level verification report for remaining first-user/update checks.

LICENSE / THIRD-PARTY INTEGRATIONS
Original Peripheral code is MIT licensed; see LICENSE.txt. The supplied logo
and its exports have separate terms in ARTWORK-NOTICE.txt. No
third-party addon code, library or assets are bundled. Blizzard textures are
referenced through the game. Offhand is not a dependency/code source.
DungeonJournal by ExehnTV (/dj) is an intended independent optional integration;
its files/data/assets are not included and its adapter is not implemented.
