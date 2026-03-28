module Web.View.Support.Index where

import Application.Helper.Controller (currentVenueOrNothing)
import Web.View.Prelude

data IndexView = IndexView
    { venues :: [Venue]
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        <div class="row justify-content-center">
            <div class="col-12 col-xl-8">
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
            </div>
        </div>
    |]

renderVenueOption :: Venue -> Html
renderVenueOption venue = [hsx|
    <option value={venue.id} selected={Just venue.id == fmap (.id) currentVenueOrNothing}>
        {venue.name}
    </option>
|]
