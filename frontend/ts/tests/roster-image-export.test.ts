import {
    isRosterImageExportFormatState,
    rosterImageExportFormatStates,
} from "../generated/contracts";
import {
    parseRosterImageExportCellConfiguration,
    parseRosterImageExportConfiguration,
} from "../roster/image-export-configuration";
import { fitRosterExportText } from "../roster/image-export";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";

const validConfig = {
    imageExportFilename: "roster-front-bar-week-of-6-jan-print.png",
    imageExportStyle: "print",
    imageExportMimeType: "image/png",
    imageExportQualityPercent: 92,
    imageExportPixelRatio: 2,
    imageExportMinimumWidth: 920,
    imageExportMaximumWidth: 1240,
    imageExportIdleLabel: "Export PNG",
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

test("roster image export accepts only the generated PNG format and exact Haskell config", () => {
    assertEqual(isRosterImageExportFormatState(rosterImageExportFormatStates.png), true);
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
        parseRosterImageExportCellConfiguration('{"imageExportText":"09:00","imageExportEndEllipsis":false}'),
        { imageExportText: "09:00", imageExportEndEllipsis: false },
    );
    assertThrows(
        () => parseRosterImageExportCellConfiguration('{"imageExportText":"09:00","imageExportEndEllipsis":false,"kind":"time"}'),
        "Invalid RosterImageExportCell",
    );
});

test("roster image export applies deterministic width-aware end ellipsis only when Haskell enables it", () => {
    const measure = (value: string) => Array.from(value).length * 10;

    assertEqual(fitRosterExportText("Front of House Supervisor", 95, true, measure), "Front of…");
    assertEqual(fitRosterExportText("Front of House Supervisor", 95, false, measure), "Front of House Supervisor");
    assertEqual(fitRosterExportText("Floor", 95, true, measure), "Floor");
    assertEqual(fitRosterExportText("Floor", 5, true, measure), "");
});
