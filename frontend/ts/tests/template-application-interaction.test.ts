import { reduceTemplateApplicationSelection, type TemplateApplicationSelection } from "../roster/template-application-selection";
import { assertDeepEqual, test } from "./harness";

const idle: TemplateApplicationSelection = { kind: "idle" };

test("Day template click selection commits only through compatible day targets", () => {
    const selecting = reduceTemplateApplicationSelection(idle, { kind: "activate-card", templateId: "day-template", scale: "day" });
    assertDeepEqual(selecting, { kind: "selecting-day", templateId: "day-template" });
    assertDeepEqual(
        reduceTemplateApplicationSelection(selecting, { kind: "activate-day", targetKey: "day:monday" }),
        { kind: "commit", templateId: "day-template", targetKey: "day:monday" },
    );
});

test("Week template activation commits immediately to the viewed week", () => {
    assertDeepEqual(
        reduceTemplateApplicationSelection(idle, { kind: "activate-card", templateId: "week-template", scale: "week", weekTargetKey: "week:viewed" }),
        { kind: "commit", templateId: "week-template", targetKey: "week:viewed" },
    );
});

test("Day target mode cancels through invalid area, Escape, Cancel, or card reactivation", () => {
    const selecting: TemplateApplicationSelection = { kind: "selecting-day", templateId: "day-template" };
    assertDeepEqual(reduceTemplateApplicationSelection(selecting, { kind: "invalid-area" }), idle);
    assertDeepEqual(reduceTemplateApplicationSelection(selecting, { kind: "escape" }), idle);
    assertDeepEqual(reduceTemplateApplicationSelection(selecting, { kind: "cancel" }), idle);
    assertDeepEqual(reduceTemplateApplicationSelection(selecting, { kind: "activate-card", templateId: "day-template", scale: "day" }), idle);
});

test("Edit and Delete controls remain isolated from template activation", () => {
    const selecting: TemplateApplicationSelection = { kind: "selecting-day", templateId: "day-template" };
    assertDeepEqual(reduceTemplateApplicationSelection(selecting, { kind: "isolated-control" }), selecting);
    assertDeepEqual(reduceTemplateApplicationSelection(idle, { kind: "isolated-control" }), idle);
});
