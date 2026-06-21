export type RosterOverviewSummary = {
    hasDetails: boolean;
    isClosed: boolean;
    label: string;
    leave: string;
    assigned: string;
    hours: string;
    summary: string;
    weekLabel: string;
    url: string;
};

export function rosterOverviewSummaryFromDayDataset(dataset: DOMStringMap): RosterOverviewSummary {
    const hasDetails = dataset.weekOverviewDetails === "true";
    const isClosed = dataset.weekOverviewClosed === "true";

    return {
        hasDetails,
        isClosed,
        label: dataset.weekOverviewLabel || "",
        leave: hasDetails ? (dataset.weekOverviewLeave || "0") : "—",
        assigned: hasDetails ? (dataset.weekOverviewAssigned || "0") : "—",
        hours: hasDetails ? (dataset.weekOverviewHours || "0h") : "—",
        summary: dataset.weekOverviewSummary || "",
        weekLabel: `In ${dataset.weekOverviewWeekLabel || ""}`,
        url: dataset.weekOverviewUrl || "",
    };
}
