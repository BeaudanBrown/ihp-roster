export type RosterStaffSortKey = "shifts" | "role" | "name" | string;
export type RosterStaffSortDirection = "ascending" | "descending";
export type RosterStaffSortData = {
    name?: string;
    assigned?: string;
    ideal?: string;
    role?: string;
};

export function rosterParseNumber(value: string | null | undefined): number {
    const parsed = Number.parseInt(value || "0", 10);
    return Number.isFinite(parsed) ? parsed : 0;
}

export function compareRosterStaffData(left: RosterStaffSortData, right: RosterStaffSortData, key: RosterStaffSortKey, direction: RosterStaffSortDirection): number {
    const directionMultiplier = direction === "descending" ? -1 : 1;
    const compareText = (leftValue: string, rightValue: string) => leftValue.localeCompare(rightValue, undefined, { sensitivity: "base" });
    const compareNumber = (leftValue: number, rightValue: number) => leftValue - rightValue;

    if (key === "shifts") {
        const assignedResult = compareNumber(rosterParseNumber(left.assigned), rosterParseNumber(right.assigned)) * directionMultiplier;
        if (assignedResult !== 0) return assignedResult;

        const idealResult = compareNumber(rosterParseNumber(left.ideal), rosterParseNumber(right.ideal)) * directionMultiplier;
        if (idealResult !== 0) return idealResult;

        return compareText(left.name || "", right.name || "");
    }

    if (key === "role") {
        const roleResult = compareText(left.role || "", right.role || "") * directionMultiplier;
        if (roleResult !== 0) return roleResult;

        return compareText(left.name || "", right.name || "");
    }

    return compareText(left.name || "", right.name || "") * directionMultiplier;
}
