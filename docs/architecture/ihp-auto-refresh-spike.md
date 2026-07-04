# IHP Auto Refresh Reuse Spike

Ticket: `ir-aa9q`

## Question

Can Bepis reuse IHP Auto Refresh table tracking to reduce manual live-surface
dependency declarations while preserving Bepis scope, authorization, and
fragment-refetch semantics?

## Sources Checked

- `../ihp/Guide/auto-refresh.markdown`
- `../ihp/ihp/IHP/AutoRefresh.hs`
- `../ihp/ihp/data/static/ihp-auto-refresh.js`
- Current Bepis live surface and invalidation code under `Application/Helper/LiveSurface*`,
  `Application/Helper/SurfaceResource.hs`, and `Web/SurfaceInvalidation.hs`.

## Finding

IHP Auto Refresh is page/action oriented:

1. it tracks table reads while running an action;
2. database changes notify relevant table dependencies;
3. the original action is rerun;
4. the browser receives a rendered HTML response;
5. the client morphs `document.body` with the new body.

That mechanism is useful for simple whole-page freshness, but it is not a direct
replacement for Bepis live surfaces. Bepis collaborative pages require:

- venue/support-mode authorization before subscription and fragment fetch;
- logical scopes such as venue, roster week, roster group, profile, and viewer
  context rather than table names alone;
- fragment-level refetch and focus-protection semantics;
- actor-response and passive-viewer paths that can intentionally differ;
- typed generated frontend contracts for live-update messages and fragment
  metadata.

## Reuse Decision

Do not adopt IHP Auto Refresh's full document-body morphing path for Bepis
collaborative surfaces.

Potentially reusable idea: table-read tracking could become an advisory signal
for broad data dependencies, especially for low-risk live fragments where manual
`liveFragmentDependsOn` declarations are noisy. If reused, it should feed Bepis
facts/dependency hints, not bypass Bepis scopes or registry authorization.

## Prototype Shape If Revisited

A future spike could prototype a helper shaped like:

```haskell
trackedBepisLiveFragment surface scope render = do
    -- run render under an IHP-style table read tracker
    -- collect table dependencies as advisory facts
    -- still authorize through Bepis surface/scope registry
    -- still return/refetch only the typed fragment target
    render
```

The result should be treated as dependency evidence:

```text
typed live surface declaration
  + explicit Bepis scope
  + optional tracked table reads
  -> architecture facts / warnings / missing-dependency suggestions
```

It should not become:

```text
table read -> automatic websocket authorization or whole-page morph
```

## Acceptance Conclusion

IHP Auto Refresh can inspire or potentially supply table dependency signals, but
Bepis keeps its domain/surface/viewer scopes and authorized fragment-refetch
transport. No implementation change is recommended until a future ticket needs
advisory table-read dependency discovery.
