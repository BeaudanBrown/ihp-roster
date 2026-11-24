# Architecture Documentation Guidelines

Use this directory for durable cross-subsystem ownership and rationale. Cite
current source or subsystem contracts for implemented behavior; do not maintain
a parallel inventory or describe a source scan as a compiler guarantee.

Controller, frontend, and workflow guards live under `scripts/verification/`.
Extend them only for narrow executable policies with focused fixtures. See
[Controller Guidelines](../../Web/Controller/AGENTS.md) for the adopted
workflow dependency rules.
