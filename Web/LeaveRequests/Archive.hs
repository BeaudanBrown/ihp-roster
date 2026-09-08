module Web.LeaveRequests.Archive
    ( ArchiveProjection (..)
    , ArchivePagination (..)
    , archivePageSize
    , projectLeaveArchive
    ) where

import Application.Helper.ControllerSupport (leaveRequestIsArchivedOn)
import Data.List (sortOn)
import Data.Ord (Down (..))
import Generated.Types
import IHP.Prelude

data ArchiveProjection = ArchiveProjection
    { archivePagination    :: ArchivePagination
    , archivedPageRequests :: [LeaveRequest]
    }

data ArchivePagination = ArchivePagination
    { archivePaginationCurrentPage :: Int
    , archivePaginationTotalPages  :: Int
    , archivePaginationTotalItems  :: Int
    }

archivePageSize :: Int
archivePageSize = 10

-- The caller supplies the existing archive clock. Stable end-date ordering
-- retains input order for ties; transport and URL selection stay with views.
projectLeaveArchive :: [LeaveRequest] -> Day -> Int -> ArchiveProjection
projectLeaveArchive requests today requestedPage =
    ArchiveProjection
        { archivePagination = ArchivePagination currentPage totalPages totalItems
        , archivedPageRequests = take archivePageSize (drop ((currentPage - 1) * archivePageSize) archivedRequests)
        }
    where
        archivedRequests = sortOn (Down . (.endDate)) (filter (leaveRequestIsArchivedOn today) requests)
        totalItems = length archivedRequests
        totalPages = max 1 ((totalItems + archivePageSize - 1) `div` archivePageSize)
        currentPage = min totalPages (max 1 requestedPage)
