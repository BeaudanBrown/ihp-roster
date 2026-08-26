module Test.CompileFail.XeroEmployeeIdRawConstruction where

import Application.Xero.EmployeeId (XeroEmployeeId)

-- Provider ids must enter through the domain parser; the constructor is private.
rawEmployeeId = XeroEmployeeId "employee-a"
