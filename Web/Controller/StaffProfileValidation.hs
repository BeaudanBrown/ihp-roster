module Web.Controller.StaffProfileValidation where

import Web.Controller.Prelude

buildRequiredPersonalProfileStaff :: (?context :: ControllerContext, ?request :: Request) => Staff -> Staff
buildRequiredPersonalProfileStaff staff =
    staff
        |> requireParam #firstName "firstName" "First name is required"
        |> requireParam #lastName "lastName" "Last name is required"
        |> requireParam #phone "phone" "Phone is required"
        |> requireParam #emergencyContactName "emergencyContactName" "Emergency contact name is required"
        |> requireParam #emergencyContactPhone "emergencyContactPhone" "Emergency contact phone is required"
        |> requireParam #idealShiftsPerWeek "idealShiftsPerWeek" "Ideal shifts per week is required"
        |> fill @'["firstName", "lastName", "preferredName", "phone", "emergencyContactName", "emergencyContactPhone", "idealShiftsPerWeek"]
        |> normalizeMaybeTextField #preferredName
        |> requiredBoundedTextField #firstName 80
        |> requiredBoundedTextField #lastName 80
        |> validateField #preferredName (validateMaybe (boundedText 80))
        |> requiredBoundedTextField #phone 80
        |> requiredBoundedTextField #emergencyContactName 120
        |> requiredBoundedTextField #emergencyContactPhone 80
        |> validateField #idealShiftsPerWeek (isInRange (0, 7))
