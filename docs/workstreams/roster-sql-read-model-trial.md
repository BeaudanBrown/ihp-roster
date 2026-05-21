# Roster SQL Read-Model Trial

Status: active
Tickets: ir-xyzw, ir-f42m, ir-cf17, ir-kxch, ir-uybz, ir-f16h, ir-1jsi, ir-dk24, ir-bdvn

## Intent

Evaluate whether the roster surface projection cache can be replaced by fresh
database-near read models for the roster surface only. Keep the existing
projection code as rollback reference until the epic decides whether to keep a
SQL/direct path, keep projections, or run a temporary hybrid.

## Baseline: Current Projection Behavior

Captured by `ir-f42m` on 2026-05-21 with the then-current projection baseline test:

```bash
IHP_ROSTER_BASELINE_PRINT=1 bash ./bin/in-env hspec-test --match "Roster projection baseline"
```

The focused baseline fixture creates one venue/default roster group, one manager,
six eligible staff, a draft week with seven days, two rows per day, two slot
columns, 28 visible slots, one duplicate-assignment conflict on the first row,
and one mutable assignment for the actor-refresh path.

### Representative Results

| Scenario | Total | Dominant/profiled spans | Projection behavior |
| --- | ---: | --- | --- |
| Cold full-page roster load | 25.2 ms | `roster.projection.load` 7.7 ms; `roster.build_staff_option_states` 2.5 ms | `misses=1,loads=1` |
| Warm full-page roster load | 17.8 ms | `roster.projection.load` 0.2 ms | `hits=1` |
| Content fragment | 16.0 ms | `roster.projection.load` 0.3 ms | `hits=1` |
| Row fragment | 2.8 ms | `roster.projection.render_fragment` 0.2 ms | `hits=1` |
| Day fragment | 3.3 ms | `roster.projection.render_fragment` 0.2 ms | `hits=1` |
| Staff-panel fragment | 4.4 ms | `roster.projection.load` 0.2 ms | `hits=1` |
| Slot mutation actor response | 10.8 ms | `live_resources.invalidate` 0.1 ms; `live_updates.broadcast_invalidation` 0.0 ms | no projection read in actor response |
| Passive row refetch after mutation | 7.9 ms | `roster.projection.render_fragment` 5.5 ms; `roster.build_staff_option_states` 1.2 ms | `misses=1,loads=1` |

Raw `Server-Timing` sample:

```text
cold-page: app_total;dur=25.2, roster_ensure_week_exists;dur=0.1, roster_fetch_eligible_staff;dur=0.7, roster_fetch_assigned_staff;dur=0.4, roster_fetch_shift_types;dur=0.2, roster_build_staff_panel;dur=0.4, roster_build_staff_self_service_panel;dur=0.0, roster_build_staff_option_states;dur=2.5, roster_fetch_ordered_slot_names;dur=0.2, roster_build_slot_conflicts;dur=0.5, roster_projection_load;dur=7.7;desc="misses=1,loads=1"
warm-page: app_total;dur=17.8, roster_projection_load;dur=0.2;desc="hits=1"
content-fragment: app_total;dur=16.0, roster_projection_load;dur=0.3;desc="hits=1"
row-fragment: app_total;dur=2.8, roster_projection_render_fragment;dur=0.2;desc="hits=1"
day-fragment: app_total;dur=3.3, roster_projection_render_fragment;dur=0.2;desc="hits=1"
staff-panel: app_total;dur=4.4, roster_projection_load;dur=0.2;desc="hits=1"
slot-mutation: app_total;dur=10.8, live_updates_broadcast_invalidation;dur=0.0;desc="subscribers=0,fragments=2,refetch=2,coalesced=0,dropped=0", live_resources_invalidate;dur=0.1;desc="label=roster.slot.update touched=3 active_scopes=0 expanded=3 candidate_scopes=1 planning_scopes=1 targets=1 target_fragments=2 broadcasts=1 subscribers=0 total_ms=0.1 observe_ms=0.0 active_ms=0.0 expand_ms=0.0 candidate_ms=0.0 plan_ms=0.0 broadcast_ms=0.1"
passive-row-refetch: app_total;dur=7.9, roster_ensure_week_exists;dur=0.1, roster_fetch_eligible_staff;dur=0.7, roster_fetch_assigned_staff;dur=0.4, roster_fetch_shift_types;dur=0.2, roster_build_staff_panel;dur=0.3, roster_build_staff_self_service_panel;dur=0.0, roster_build_staff_option_states;dur=1.2, roster_fetch_ordered_slot_names;dur=0.2, roster_build_slot_conflicts;dur=0.5, roster_projection_render_fragment;dur=5.5;desc="misses=1,loads=1"
```

## Observations

- Cold projection loads are dominated by building the projection snapshot; within the visible spans, `roster.projection.load` and `roster.build_staff_option_states` are the largest costs.
- Warm page and fragment reads mostly pay cache lookup plus render work; row and staff-panel fragments are cheap when the viewer/scope/version entry is warm.
- Slot mutation actor responses enqueue fragment refresh instructions and live-resource invalidations, but do not render the projection in the actor response.
- Passive viewers pay a fresh projection load when they refetch after an invalidating mutation and their viewer/scope/version entry is cold.
- Full-page totals include render/layout work that is not separately spanned; warm full-page total can exceed cold in small local samples despite cache hits.

## Known Limitations

- Timings are from the local Hspec/mock controller environment, not a browser or production-like server process.
- The baseline fixture is intentionally medium-sized; it does not cover very large rosters, multiple roster groups, staff self-service-only viewers, or live published staff masking.
- `Server-Timing` covers existing `profileActionSpan` spans only. HSX rendering, layout, and some controller/setup work are visible only in `app_total`.
- Projection cache stats are process-local and viewer/scope/version keyed, so repeated focused test runs should be interpreted as shape evidence, not persistent cache-capacity evidence.

## Current Trial Integration

`ir-f16h` switched `currentRosterReadModelBackend` to `DirectRosterReadModel` on the
trial branch. Controller and live-fragment call sites still use
`fetchVisibleRosterReadModel` / `renderVisibleRosterReadModelFragment`, so rollback
is a single seam constructor change and the projection implementation remains in
place.

Focused integration coverage now asserts that full-page, content fragment, day
section fragment, row fragment, staff panel, and passive mutation refetch paths
render without `roster_projection_*` `Server-Timing` spans.

## Direct Fragment Tuning

`ir-bdvn` narrowed the direct fragment path before projection cleanup. Staff-panel
fragment GETs now build only panel entries and skip staff option-state and
conflict builders. Row fragment GETs still compute staff option states and
conflicts with week-wide facts for parity, but emit option states and conflicts
only for the requested row. Day section fragment GETs keep week-wide assignment
and conflict facts for parity, but emit option states and conflicts only for the
requested day. This materially reduces the repeated direct read-model work that
previously made warm row/day/staff-panel fragments slower than projection-cache
hits, while keeping the rollback seam and projection code intact.

Representative local post-tuning sample from the same focused fixture:

| Scenario | Direct total | Relevant direct spans | Projection baseline |
| --- | ---: | --- | ---: |
| Row fragment | 11.9 ms | option states 1.8 ms; conflicts 2.5 ms | 2.8 ms warm hit |
| Day fragment | 12.0 ms | option states 2.0 ms; conflicts 2.4 ms | 3.3 ms warm hit |
| Staff-panel fragment | 8.2 ms | staff panel 0.5 ms; skips option/conflict builders | 4.4 ms warm hit |
| Passive row refetch | 13.8 ms | option states 2.8 ms; conflicts 3.0 ms | 7.9 ms cold/miss sample |

Warm row/day/staff-panel direct reads are still slower than projection-cache hits
in this fixture, but the largest repeated builders now operate on the requested
fragment scope instead of producing week-wide render payloads. The remaining cost
is accepted for the trial because it preserves no cross-request cache state;
projection rollback should remain until larger-roster measurements confirm this
trade-off.

## Living Docs To Update If Adopted

- `Web/RosterWeeks/RenderData.hs` module-level/seam comments once the direct read path exists.
- `Application/Helper/LiveUpdate.SPEC.md` if roster live-fragment refresh semantics change.
- Roster controller or view specs if the projection cache stops being the canonical roster read path.
