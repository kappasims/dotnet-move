---
name: restructure-dotnet
description: Use when moving, relocating, or restructuring managed .NET projects: moving a .csproj/.fsproj/.vbproj folder, reorganizing solution layout, or extracting a project into its own assembly. Triggers on "move this project", "restructure", "reorganize the solution", "extract into its own folder/assembly". Do not hand-edit .sln/.slnx/.csproj. For PowerShell modules/scripts use restructure-powershell; for native C++/.vcxproj use restructure-native.
---

# Restructuring managed .NET repos (cross-platform)

These cmdlets are **cross-platform** (PowerShell 7 on Windows/Linux/macOS); they rely only
on the dotnet CLI and git. For native C++ (`.vcxproj`), which is Windows-only, see the
`restructure-native` skill (`Move-DotnetProject` deliberately refuses `.vcxproj`). For moving
PowerShell modules/scripts, see the `restructure-powershell` skill.

**Rule: never hand-edit `.sln`, `.slnx`, or `.csproj`/`.fsproj`/`.vbproj` to move things.**
Relative paths and solution GUIDs drift out of sync when typed by hand. Delegate every
path/GUID change to first-party tooling.

Use the installed `DotnetMove` module (`Import-Module DotnetMove`). If it is not installed, point
the user to the project's install steps and let them run them; never auto-install.

## Analyze/audit first (read-only)

To understand a repo before touching it, use these; do not parse solution/project files by hand:

- `Test-SolutionConsistency` - projects whose membership diverges across solutions (`-Debug` for
  the full solution/project matrix). To resolve a reported divergence, add the project where it is
  missing with `dotnet sln <solution> add <project>` (DotnetMove does not add membership for you).
- `Repair-SolutionReferences` (no flags) - report dangling solution entries / `<ProjectReference>`s.
- `Find-PathReference` - build/CI/hook scripts that hardcode a path no move reconciles.
- `Resolve-MoveEngine` - which engine a given path classifies to.
- `Get-DotnetMoveCapability` - whether git and dotnet are present, plus the platform.

These are the right tools when the task is "audit" or "sync the solutions", not only when moving.

## Moving a .NET project

```powershell
Import-Module DotnetMove
# Always dry-run first:
Move-DotnetProject -Project ./src/Tarragon/Tarragon.csproj -Destination ./libs/Tarragon -WhatIf
# Then for real:
Move-DotnetProject -Project ./src/Tarragon/Tarragon.csproj -Destination ./libs/Tarragon
```

This reconciles: solution membership (`dotnet sln add/remove`, works on `.sln` and `.slnx`),
consumer `<ProjectReference>`s, and the project's own references, then runs `dotnet build`.

## Inspecting and repairing (no move)

These work on an existing repo without moving anything. Inspect first, then repair if needed.

```powershell
Test-SolutionConsistency  -RepoRoot .          # projects whose solution membership diverges
Repair-SolutionReferences -RepoRoot .          # report dangling entries (relocatable / missing / ambiguous)
Repair-SolutionReferences -RepoRoot . -Fix     # re-point dangling entries at the project's new location
Repair-SolutionReferences -RepoRoot . -Prune   # remove entries whose project is gone for good
Find-PathReference -Path ./src/Tarragon/Tarragon.csproj  # build/CI/hook scripts that hardcode the path (report-only)
```

`-Fix` relocates; it does not delete. Removal is only `-Prune`, and only for entries whose
project cannot be found anywhere. Both honor `-WhatIf`.

## If you must do it without the module

Use the raw CLI, never a text editor:
- `dotnet sln <sln> remove <oldProj>` → move dir → `dotnet sln <sln> add <newProj>`
- `dotnet remove <consumer> reference <proj>` → `dotnet add <consumer> reference <proj>`
- `dotnet sln migrate` converts `.sln` → `.slnx`

## Known limits (warn the user; do not silently "fix")

- `Directory.Build.props/.targets` inheritance changes when folder depth changes.
- Hardcoded project paths in CI YAML / scripts.

## The `git dotnetmv` verb (optional; ask first)

The same routing is also an opt-in git verb: `git dotnetmv <src> <dst> [--whatif]`. It needs a
one-time alias that `Register-DotnetMvGitAlias` writes to the user's git config. If you suggest
it or want to use it, prompt the user first and let them register it; do not edit their git
config for them. Never auto-install anything (git, the dotnet SDK, or these modules): if a
prerequisite is missing, tell the user the install command and let them run it.
