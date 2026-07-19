import { fuzzyIncludes, normalizeCandidateFilterQuery } from "../app-xero";
import { parseXeroCandidateFilterConfiguration } from "../xero-candidate-filter/configuration";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";

test("Xero candidate filtering parses one exact opaque projection", () => {
    assertDeepEqual(
        parseXeroCandidateFilterConfiguration('{"searchProjection":"venue custom ordinary 477"}'),
        { searchProjection: "venue custom ordinary 477" },
    );
    assertThrows(
        () => parseXeroCandidateFilterConfiguration('{}'),
        "Invalid XeroCandidateFilterConfig",
    );
    assertThrows(
        () => parseXeroCandidateFilterConfiguration('{"searchProjection":"","accountCode":"477"}'),
        "Invalid XeroCandidateFilterConfig",
    );
    assertThrows(
        () => parseXeroCandidateFilterConfiguration('{"searchProjection":"   "}'),
        "searchProjection must not be empty",
    );
});

test("Xero candidate filtering normalizes user queries before generic fuzzy matching", () => {
    assertEqual(normalizeCandidateFilterQuery("  VeNuE\t  Custom  "), "venue custom");
    assertEqual(fuzzyIncludes("venue custom ordinary 477", normalizeCandidateFilterQuery("VCO")), true);
    assertEqual(fuzzyIncludes("weekend penalty 599", normalizeCandidateFilterQuery("VCO")), false);
    assertEqual(fuzzyIncludes("ordinary earnings", normalizeCandidateFilterQuery("")), true);
});
