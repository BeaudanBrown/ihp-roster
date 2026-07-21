import {
    isRosterImageExportFormatState,
    rosterImageExportFormatStates,
} from "../generated/contracts";
import {
    parseRosterImageExportCellConfiguration,
    parseRosterImageExportConfiguration,
} from "../roster/image-export-configuration";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";

const validConfig = {
    imageExportFilename: "roster-front-bar-week-of-6-jan.jpg",
    imageExportMimeType: "image/jpeg",
    imageExportQualityPercent: 92,
    imageExportPixelRatio: 2,
    imageExportMinimumWidth: 920,
    imageExportMaximumWidth: 1240,
    imageExportIdleLabel: "Export JPG",
    imageExportPreparingLabel: "Preparing...",
    imageExportDownloadedLabel: "Downloaded",
    imageExportFailedLabel: "Export failed",
    imageExportFailureMessage: "Roster export failed. Please try again.",
    imageExportMissingProjectionMessage: "Could not find the current roster grid.",
    imageExportCloneFailureMessage: "Could not clone the current roster grid.",
    imageExportRenderFailureMessage: "Failed to render roster export image.",
    imageExportCanvasFailureMessage: "Failed to initialize roster export canvas.",
    imageExportEncodingFailureMessage: "Failed to encode roster export image.",
};

test("roster image export accepts only the generated JPG format and exact Haskell config", () => {
    assertEqual(isRosterImageExportFormatState(rosterImageExportFormatStates.jpg), true);
    assertEqual(isRosterImageExportFormatState("png"), false);
    assertDeepEqual(parseRosterImageExportConfiguration(JSON.stringify(validConfig)), validConfig);
    assertThrows(
        () => parseRosterImageExportConfiguration(JSON.stringify({ ...validConfig, extension: "jpg" })),
        "Invalid RosterImageExportConfig",
    );
});

test("roster image export rejects invalid format policy and parses exact cell text", () => {
    assertThrows(
        () => parseRosterImageExportConfiguration(JSON.stringify({ ...validConfig, imageExportQualityPercent: 101 })),
        "quality percent",
    );
    assertThrows(
        () => parseRosterImageExportConfiguration(JSON.stringify({ ...validConfig, imageExportMinimumWidth: 1300 })),
        "width range",
    );
    assertDeepEqual(
        parseRosterImageExportCellConfiguration('{"imageExportText":"09:00"}'),
        { imageExportText: "09:00" },
    );
    assertThrows(
        () => parseRosterImageExportCellConfiguration('{"imageExportText":"09:00","kind":"time"}'),
        "Invalid RosterImageExportCell",
    );
});
