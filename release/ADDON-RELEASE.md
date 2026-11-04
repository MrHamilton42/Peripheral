# Peripheral addon releases

In GitHub Actions, run **Build Peripheral addon** to produce an addon ZIP for
review. The artifact contains the output of `scripts/package.ps1 -CurseForgeReview`.
The packager ships only the addon and its offline configurator.

For each version, update the addon version in `package.json` and
`addon/ForeverWorkspace/ForeverWorkspace.toc`, `Core.lua`, and `README.txt`.
Add `release/CHANGELOG-vX.Y.Z.md`. Push the matching `vX.Y.Z` tag to trigger a
build. The workflow checks the version and release notes before packaging.

After creating the CurseForge project, set these GitHub Actions repository
variables:

- `CURSEFORGE_PROJECT_ID` — the numeric ID of the Peripheral project.
- `CURSEFORGE_GAME_VERSION_ID` — the CurseForge version ID for the tested Retail
  client. Use the WoW version listing from the upload API.
- `CURSEFORGE_UPLOAD_ENABLED` — set to `true` when ready to send tagged builds for review.

Store the CurseForge author upload token as the Actions secret
`CURSEFORGE_API_TOKEN`. With those settings in place, a matching version tag
submits the ZIP as a beta and requests manual release after moderation. A manual
workflow run only builds the artifact. Use the addon repository as the
CurseForge **Source** URL.

The Windows helper has its own releases linked from the GitHub README.

[CurseForge Upload API](https://support.curseforge.com/support/solutions/articles/9000197321)
