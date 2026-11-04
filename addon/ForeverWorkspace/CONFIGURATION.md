# Configuration format 1

The addon, local HTML page and optional helper share one data-only UTF-8 JSON
format. No pasted Lua is compiled or executed. Configuration is stored under
`ForeverWorkspaceDB.configuration`; derived geometry is calculated at load/import.

Required root fields:

| Field | Meaning |
| --- | --- |
| `format` | Exactly `ForeverWorkspace` |
| `schema` | Integer `1`; other versions are rejected |
| `units` | Exactly `physical-px` |
| `monitors` | Array of 2–12 monitor objects |
| `roles` | `main` monitor ID, optional `left` and `right` IDs |
| `strips` | Whole `left` and `right` percentages, each 15–70 |
| `respectWorkArea` | Boolean; clip reference content to monitor work areas |

Optional root fields: `source` (`manual`, `browser`, `helper`) and
`producerVersion` (numeric `major.minor.patch`), and
`canvasInsets: {left,right,top,bottom}`. Unknown fields are rejected.
Canvas insets are whole physical pixels: left/right -256 to 512, top/bottom
0 to 512. Negative horizontal values add outer padding inside the selected
monitor span. They adjust
the outer footprint without changing monitor measurements. Main must retain its
full physical width and at least 240 pixels of height; reference strips must
still satisfy the minimum dimensions. Vertical trimming can shorten Main.
The HTML page's optional Window border allowance outputs these same insets.
The helper's normal untrimmed output omits them; importing fresh helper output
replaces a previous fitted configuration with the requested full footprint.

Each monitor has a unique ASCII `id` (1–64 letters/digits/underscore/dot/hyphen),
physical integer `x`, `y`, `width`, `height`, an optional UTF-8 `label` up to 160
bytes, and optional `work: {x,y,width,height}` inside the monitor. Absent work
means its entire rectangle. X/Y bounds are -65536..65536; monitor width is
320..16384 and height 240..16384. Work dimensions are positive integers.

Roles must reference different existing monitors. Left must end before/equal
Main's left; Right must start after/equal Main's right. Each side must overlap
Main's vertical interval. This supports horizontal offset/unequal-height layouts,
not broader stacked topologies. At least one side is required. The resulting
canvas is limited to 32768 × 16384 and 134217728 pixels; usable strips need at
least 160 × 240 pixels. Per-panel layout/UI-scale limits can still reject a trial.

The native footprint bounds Main and the requested inner strips BEFORE work-area
clipping. Work-area clipping changes reference content, not the full Main view or
rectangular client footprint. Strip widths round positive halves upward.
Canvas insets are applied afterwards and clip Main/reference regions to the
adjusted footprint. This is explicit calibration, not relaxed size validation.
Fit current window in /fws align requires settled engine/canvas dimensions and
no owned size request awaiting restoration. It accepts width within 256 pixels
of target and height up to 256 pixels shorter, allocates horizontal trim/padding
proportionally to the outer margins, and trims the bottom. /fws fit opens
alignment and performs the same explicit action as the Fit current window button.
It preserves monitor coordinates and Main width, saves without activation or
native resizing, and retains the previous configuration for recovery. It does
not measure native desktop position: green guides still require visual alignment.

Parser limits: 64 KiB UTF-8, depth 12, 1500 values; duplicate keys, invalid UTF-8,
invalid escapes/surrogates, trailing content and non-finite numbers are rejected.
This format omits optional roles rather than accepting JSON null.

Browser screen coordinates are CSS/logical pixels. A uniform `ScreenDetailed`
per-screen DPR can provide a candidate common conversion; the user must verify
physical values. `window.devicePixelRatio` includes zoom and is not used as the
conversion factor. Mixed-DPI origins are not converted independently: physical
rectangles must be entered manually. The helper obtains physical rectangles in
a DPI-aware Win32 context. Coordinate-source metadata is informational, not proof
that a monitor still exists or a WoW window is correctly positioned.

Import validates and saves only while inactive/outside combat with restoration
complete. Apply/Keep is separate. Keep records `lastWorkingConfiguration` and
`lastWorkingGeometry`; invalid imports cannot replace current data. Existing
generated geometry can be retained once as `legacyGeometry` when still loaded.
Existing saved diagnostics can provide a bounded numeric fallback with an
explicit stale-snapshot notice. Missing original monitor sizes/origin are never
fabricated. No code writes personal configuration into the installed addon directory.
