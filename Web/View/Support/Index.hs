module Web.View.Support.Index where

import Application.Helper.Controller (currentVenueOrNothing)
import Web.View.Prelude

data IndexView = IndexView
    { venues :: [Venue]
    , venue :: Venue
    , createdVenue :: Maybe Venue
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-xl-8">
                {renderCreatedVenueBanner createdVenue}
                <div class="app-panel">
                    <div class="app-panel-body">
                        <h1 class="h4 mb-2">Support</h1>
                        <p class="app-muted mb-4">
                            Switch the current venue context for founder support access. This changes the existing session venue and does not create a real venue membership.
                        </p>
                        <div class="border rounded p-3 bg-light-subtle mb-4">
                            <div class="small text-uppercase app-muted mb-1">Current support venue</div>
                            <div class="fw-semibold">
                                {maybe "No active venue selected" (.name) currentVenueOrNothing}
                            </div>
                        </div>
                        <form method="POST" action={SwitchSupportVenueAction} class="row g-3 align-items-end" data-disable-javascript-submission="true">
                            <div class="col-12 col-lg-9">
                                <label class="form-label" for="support-venue-id">Active venue</label>
                                <select id="support-venue-id" class="form-select" name="venueId">
                                    {forEach venues renderVenueOption}
                                </select>
                            </div>
                            <div class="col-12 col-lg-3">
                                <button class="btn btn-primary w-100" type="submit">Switch Venue</button>
                            </div>
                        </form>
                    </div>
                </div>
                <div class="app-panel mt-4">
                    <div class="app-panel-body">
                        <h2 class="h5 mb-2">Create Venue</h2>
                        <p class="app-muted mb-4">
                            Create a new active venue and apply the minimum Bepis schedule defaults. Customer invitations happen later, after any founder-side setup is complete.
                        </p>
                        <form method="POST" action={CreateSupportVenueAction} class="row g-3" data-disable-javascript-submission="true">
                            <div class="col-12">
                                <label class="form-label" for="support-create-venue-name">Venue name</label>
                                <input
                                    id="support-create-venue-name"
                                    class={classes [("form-control", True), ("is-invalid", hasVenueErrorFor venue "name")]}
                                    type="text"
                                    name="name"
                                    value={venue.name}
                                    required="required"
                                />
                                {renderVenueError venue "name"}
                            </div>
                            <div class="col-12 col-lg-6 d-flex align-items-end">
                                <button class="btn btn-primary w-100" type="submit">Create Venue</button>
                            </div>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    |]

renderVenueOption :: Venue -> Html
renderVenueOption venue = [hsx|
    <option value={venue.id} selected={Just venue.id == fmap (.id) currentVenueOrNothing}>
        {venue.name}
    </option>
|]

renderCreatedVenueBanner :: Maybe Venue -> Html
renderCreatedVenueBanner maybeVenue =
    case maybeVenue of
        Nothing -> mempty
        Just venue -> [hsx|
            <div class="alert alert-success d-flex flex-column flex-lg-row justify-content-between align-items-lg-center gap-3" role="alert">
                <div>
                    <div class="fw-semibold">Venue ready for founder setup</div>
                    <div>{venue.name} was created with minimum Bepis schedule defaults. You can switch into it now and invite users later.</div>
                </div>
                <form method="POST" action={SwitchSupportVenueAction} class="m-0">
                    <input type="hidden" name="venueId" value={tshow venue.id} />
                    <input type="hidden" name="next" value={pathTo SupportAction} />
                    <button class="btn btn-success" type="submit">Switch To This Venue</button>
                </form>
            </div>
        |]

renderVenueError :: Venue -> Text -> Html
renderVenueError venue fieldName =
    case lookup fieldName venue.meta.annotations of
        Just (TextViolation messageText) -> [hsx|<div class="invalid-feedback d-block">{messageText}</div>|]
        Just (HtmlViolation messageHtml) -> [hsx|<div class="invalid-feedback d-block">{messageHtml}</div>|]
        Nothing -> mempty

hasVenueErrorFor :: Venue -> Text -> Bool
hasVenueErrorFor venue fieldName = isJust (lookup fieldName venue.meta.annotations)
