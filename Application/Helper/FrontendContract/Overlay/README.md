# OverlayAction Contracts

`OverlayAction` is the generated contract lane for app-owned HTMX request
initiators whose lifecycle belongs to a global overlay mount rather than a
mounted `FrontendSurface`.

Use it for:

- dialog launchers, such as opening the feedback dialog
- dialog-local step transitions, such as next/back/retry in a wizard
- dialog submits, including validation rerenders into the same dialog mount
- overlay-local controls that load or replace dialog content

Do not use it for ordinary page links, lazy surface fragment loads, live-update
refetches, response OOB extras by themselves, arbitrary global HTMX, or mounted
`FrontendSurface` request initiators. Surface-owned request initiators stay in
`SurfaceAction`.

## Declaration

Declare actions in `Application.Helper.FrontendContract.Overlay`:

```haskell
data OpenFeedbackDialog
data SubmitFeedback
data FeedbackTypeField
data ContentField

type OverlayContract =
    Global Overlay
        '[ OverlayAction OpenFeedbackDialog
            '[]
            '[ OverlayHtmxMethod 'OverlayGet
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             ]
         , OverlayAction SubmitFeedback
            '[ Field FeedbackTypeField 'WireText
             , Field ContentField 'WireText
             ]
            '[ OverlayHtmxMethod 'OverlayPost
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             ]
         ]
```

The DSL owns browser-visible request metadata and submitted field names. Haskell
still owns route/path construction.

## Rendering

Prefer typed marker lookup over raw action-name lookup:

```haskell
applyOverlayActionAttrs
    (overlayActionByMarker @OpenFeedbackDialog)
    OverlayActionRoute
        { overlayActionRouteUrl = pathTo NewFeedbackAction
        , overlayActionRouteFields = []
        , overlayActionRouteCustomHtmx = []
        , overlayActionRouteStandardUrl = Nothing
        , overlayActionRouteExtraAttrs = [("type", "button")]
        }
    buttonHtml
```

For forms:

```haskell
renderOverlayActionForm
    (overlayActionByMarker @SubmitFeedback)
    OverlayActionRoute
        { overlayActionRouteUrl = pathTo CreateFeedbackAction
        , overlayActionRouteFields = []
        , overlayActionRouteCustomHtmx = []
        , overlayActionRouteStandardUrl = Nothing
        , overlayActionRouteExtraAttrs = [("id", feedbackFormId)]
        }
    (renderFeedbackFormFields feedbackItem)
```

`overlayActionRouteFields` is for hidden route/context fields added by the
helper. Ordinary form controls still live in the form body; their names must
match the generated action field names.

## Response rules

Validation failures may return the dialog fragment again into the shared dialog
mount. Successful overlay-only actions may return direct overlay HTML. Successful
business mutations should clear/close the dialog and may emit requester-only
extras such as toasts.

When the mutation changes business DOM owned by a migrated live surface, do not
return authoritative business fragments OOB from the overlay response. Trigger
actor-local/passive invalidation for the relevant surface instead. OOB remains
appropriate for dialog clears, toasts, validation-local content, and other
requester-only extras.

## Guardrails

Migrated overlay callsites are opt-in guarded in
`Config/nix/scripts/frontend/surface-guardrails`. Add migrated view files to the
guardrail list when converting more overlay workflows so they cannot regress to
handwritten `hx-*` request metadata or raw `overlayActionByName` lookup.
