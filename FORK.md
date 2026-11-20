# PSScriptAnalyzer: patch branch for QUINDOS

This repository carries changes to [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)
that the QUINDOS test tier needs, until they are merged upstream. It is not a separate product.
Every change is meant for upstream, except the fork-only files listed below.

## Branches

| Branch | Content |
|---|---|
| `main` | Mirror of `PowerShell/PSScriptAnalyzer` `main`. Never commit here. |
| `upstream/<topic>` | One upstream pull request per branch, based on `main`. Each one has its regression tests and nothing fork-specific. Upstream writes `CHANGELOG.MD` at its release, so a topic does not change it. |
| `quindos` (default) | The upstream release tag that QUINDOS pins, + the commits of all `upstream/*` branches + fork-only commits. Releases are tagged here. |

`quindos` starts from a release tag, and not from `main`, because `main` holds rules that no
release has yet. A new rule that is on by default would give QUINDOS new findings with a pin that
only meant to fix a defect.

### Changes waiting for upstream

| Branch | Change | Upstream issue / PR |
|---|---|---|
| `upstream/exported-function-race` | `Helper.GetExportedFunction` resolves the parameters of `Export-ModuleMember` from its static parameter metadata, and no longer calls `CommandInfo.ResolveParameter`. That call runs on the runspace of the cached command, which the rule threads and the command lookups use at the same time, and it threw a `NullReferenceException`. A parameter name that matches no parameter, or more than one, is skipped and no longer throws. The test `Tests/Engine/GetExportedFunction.tests.ps1` starts 16 callers at one barrier while 16 threads look up commands. Based on `main` at `0151b9da`. | Issue [#1351](https://github.com/PowerShell/PSScriptAnalyzer/issues/1351), PR not filed yet |

Each commit on a topic branch ends its subject with its upstream issue, as `(#1351)`. When a pull
request merges, remove its branch from this table and from the update steps below.

Upstream [PR #2206](https://github.com/PowerShell/PSScriptAnalyzer/pull/2206) (open) rewrites the
`CommandInfoCache` with one locked runspace, and changes `GetExportedFunction` in the same way. This
fork takes only the change of `GetExportedFunction`. When #2206 merges, check whether the topic is
still needed.

### Fork-only files

- `FORK.md` (this file).
- `fork/New-PSScriptAnalyzerForkPackage.ps1`: builds the release zip and its `.sha256` file.
- `Prerelease` in `Engine/PSScriptAnalyzer.psd1`, so that a fork build does not pass for the
  gallery release of the same `ModuleVersion`.

## Updating from upstream

```bash
git fetch upstream --tags
git checkout main && git merge --ff-only upstream/main
for b in upstream/exported-function-race; do
  git rebase main "$b"
done
git push --force-with-lease origin main 'upstream/*'
```

`quindos` follows a release tag and not `main`. When QUINDOS moves to a new upstream release, build
`quindos` again on that tag:

```bash
git checkout -B quindos <new tag>
git cherry-pick <the commits of each upstream/* branch> <the fork-only commits>
git push --force-with-lease origin quindos
```

- If a commit of a topic is in the new tag already, drop it. When a topic is merged upstream,
  delete its branch and remove its row above.
- Consumers pin release zips (version + SHA-256), not branch commits, so rewriting `quindos`
  does not affect them.
- Exit: when no patches are left, pin the gallery release again and archive this repository.

## Releases

Tag `quindos` with `v<ModuleVersion>-quindos.<n>`, for example `v1.25.0-quindos.1`. Set
`Prerelease = 'quindos<n>'` in `Engine/PSScriptAnalyzer.psd1` in the same commit. Then, on a clean
checkout of the tag:

```powershell
git worktree add --detach <folder> v1.25.0-quindos.1
& <folder>/fork/New-PSScriptAnalyzerForkPackage.ps1 -Release quindos.1 -OutDir <dist folder>
```

The script refuses a checkout with changes, so give it an `-OutDir` outside the checkout. It writes
`PSScriptAnalyzer-<ModuleVersion>-quindos.<n>.zip` and its `.sha256` file. Attach both to a GitHub
prerelease of the tag. The zip holds the folder that the build writes to
`out/PSScriptAnalyzer/<ModuleVersion>`, at its root:

```
PSScriptAnalyzer.psd1, PSScriptAnalyzer.psm1, *.ps1xml   the module
*.dll                                                    the assemblies for Windows PowerShell 5.1
PSv7/                                                    the assemblies for PowerShell 7
Settings/, compatibility_profiles/, en-US/               the settings, the profiles, the help
LICENSE, README.md, SECURITY.md, ThirdPartyNotices.txt
```

That is the layout of the gallery package, without its NuGet files. The build is not
Authenticode-signed, unlike the gallery package, so a computer with the execution policy
`AllSigned` refuses it.

The build needs the .NET SDK that `global.json` names and platyPS 0.14.2
(`tools/installPSResources.ps1`). The script gives each zip entry the time of the commit, and it
writes the entries in ordinal order. Two builds of one commit with the same SDK and the same
PowerShell 7 therefore give the same SHA-256. Build the release on the commit of its tag, because
the time of another commit gives other bytes.

The workflow `ci-test.yml` starts on a push to `main` and on `workflow_dispatch`. Start it by hand
on a branch: `gh workflow run ci-test.yml --ref upstream/<topic>`.

## Checking a change

Build both editions, then run the tests that the change touches, and the whole suite before a
release:

```powershell
./build.ps1 -Configuration Release -All
./build.ps1 -Test                          # PowerShell 7
./build.ps1 -Test -WithPowerShell powershell.exe
```

Prove a fix of a race on the build without the fix too. The test of a race must fail there.
