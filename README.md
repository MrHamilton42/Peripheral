# Peripheral

Peripheral keeps the WoW world on one monitor and puts reference panels in
configurable strips on neighboring screens. It is a Retail development beta;
Forever is an intended test target.

On Windows, use the optional helper to place the game window. After keeping a
layout once, click **Start Peripheral** in the helper and **Use saved layout** in
WoW. The first connection may need one full WoW restart. A changed layout uses a
timed preview, followed by explicit confirmation.

<!-- PERIPHERAL_HELPER_LINK -->
[Get the Windows helper](https://github.com/MrHamilton42/Peripheral-Windows-Helper/releases)
<!-- /PERIPHERAL_HELPER_LINK -->

Without the helper, open `Configurator.html` in the installed `ForeverWorkspace`
folder. Detect or enter monitors, copy the configuration into `/peripheral import`,
then align the window and apply the trial. See [the setup guide](addon/ForeverWorkspace/README.txt).

The main addon is distributed separately from the helper. Developers can publish
optional text panels via the [provider API](addon/ForeverWorkspace/API.md).

Original code is [MIT licensed](addon/ForeverWorkspace/LICENSE.txt). The
[Peripheral logo has separate terms](addon/ForeverWorkspace/ARTWORK-NOTICE.txt).

See [the release guide](release/ADDON-RELEASE.md) for GitHub builds and CurseForge uploads.
