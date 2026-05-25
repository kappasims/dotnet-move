---
name: restructure-native
description: Use when moving or restructuring a native C++ or C++/CLI project (.vcxproj) in a Visual Studio solution on Windows. Triggers on moving a .vcxproj folder, relocating a native library, or restructuring a mixed managed+native solution. Windows-only. For pure managed .csproj/.fsproj/.vbproj use the restructure-dotnet skill instead.
---

# Restructuring native / C++ projects (.vcxproj), Windows only

Native projects do not fit the dotnet-CLI delegation model that managed projects use.
`dotnet sln add/remove` can update solution membership for a `.vcxproj`, but the dotnet CLI
**cannot** reconcile how native projects actually link:

- `<AdditionalIncludeDirectories>` / `<AdditionalLibraryDirectories>` (often `..\` or `$(SolutionDir)`-relative)
- `<AdditionalDependencies>` (e.g. `Tarragon.lib`, resolved via the library dirs above)
- `<Import Project="..\shared\Tarragon.props" />` of shared `.props`/`.targets`
- `$(SolutionDir)`-relative `<OutDir>`/`<IntDir>` and PCH paths
- the paired `.vcxproj.filters`

C++/CLI is Windows-only (`<CLRSupport>`, `#pragma managed`, `<Windows.h>`), so this is gated.

## Use Move-NativeProject

`Import-Module DotnetMove` loads the native engine on Windows (install it first if needed; never
auto-install).

```powershell
Import-Module DotnetMove
Move-NativeProject -Project ./Aleppo/Aleppo.vcxproj -Destination ./native/Aleppo -WhatIf
```

It will: update `.sln`/`.slnx` membership via `dotnet sln`, move the folder (`git mv` when
tracked) including the paired `.vcxproj.filters`, and then **report every relative /
`$(SolutionDir)`-relative native setting** it could not safely rewrite. It does not silently
edit those MSBuild paths; the report (`UnreconciledSettings` on the result object, plus
warnings) tells you exactly what to verify or hand-fix afterward.

## After the move, always

- Fix each reported `AdditionalIncludeDirectories`/`AdditionalLibraryDirectories`/`Import`
  whose `..\` depth changed.
- Rebuild the native + C++/CLI projects in Visual Studio / MSBuild (not `dotnet build`).
- Confirm the `.vcxproj.filters` has no broken `..\` entries.

## The `git dotnetmv` verb (optional; ask first)

The same routing is also an opt-in git verb: `git dotnetmv <src> <dst> [--whatif]`. It needs a
one-time alias that `Register-DotnetMvGitAlias` writes to the user's git config. If you suggest
it or want to use it, prompt the user first and let them register it; do not edit their git
config for them. Never auto-install anything (git, the dotnet SDK, or these modules): if a
prerequisite is missing, tell the user the install command and let them run it.
