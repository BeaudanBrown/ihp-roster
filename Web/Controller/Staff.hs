module Web.Controller.Staff where

import Application.Helper.RosterGroups (fetchCurrentVenueDefaultRosterGroup)
import Application.Helper.View (appendQueryParams)
import Web.Controller.Prelude
import Web.Controller.RosterWeeks (broadcastRosterWeekInvalidation,
                                   buildRosterContentFragmentRef,
                                   respondWithRosterContentOob)
import Web.View.Staff.Edit

instance Controller StaffController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenue
        ensureProfileCompleted
        ensureManagerRole

    action EditStaffAction { staffId } = do
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        let weekOffset = paramOrDefault @Int 0 "weekOffset"
        let maybeRosterGroupId = paramOrNothing "rosterGroupId"
        if isHtmxRequest
            then respondHtml (renderStaffEditModalFragment staff weekOffset maybeRosterGroupId)
            else render EditView { .. }

    action UpdateStaffAction { staffId } = do
        staff <- fetch staffId
        ensureRecordInCurrentVenue staff.venueId
        let weekOffset = paramOrDefault @Int 0 "weekOffset"
        let maybeRosterGroupId = paramOrNothing "rosterGroupId"
        staff
            |> buildStaff
            |> ifValid \case
                Left staff -> do
                    if isHtmxRequest
                        then respondHtml (renderStaffEditModalFragment staff weekOffset maybeRosterGroupId)
                        else render EditView { .. }
                Right staff -> do
                    staff <- staff |> updateRecord
                    if isHtmxRequest
                        then do
                            rosterGroupId <- case maybeRosterGroupId of
                                Just rosterGroupId -> pure rosterGroupId
                                Nothing -> (.id) <$> fetchCurrentVenueDefaultRosterGroup
                            broadcastRosterWeekInvalidation
                                rosterGroupId
                                weekOffset
                                [buildRosterContentFragmentRef rosterGroupId weekOffset]
                            respondWithRosterContentOob rosterGroupId weekOffset
                        else do
                            setSuccessMessage "Staff member updated"
                            redirectToPath $
                                maybe
                                    (pathTo ShowRosterWeekAction { weekOffset })
                                    (\rosterGroupId -> appendQueryParams (pathTo ShowRosterWeekAction { weekOffset }) [("rosterGroupId", tshow rosterGroupId)])
                                    maybeRosterGroupId

buildStaff staff = staff
    |> fill @'["firstName", "lastName", "idealShiftsPerWeek", "isActive"]
    |> validateField #firstName nonEmpty
    |> validateField #lastName nonEmpty
