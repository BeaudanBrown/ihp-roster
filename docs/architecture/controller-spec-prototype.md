# Typed Bepis ControllerSpec Prototype Decision

Ticket: `ir-djtt`

## Goal

Evaluate whether Bepis should move beyond `runBepis` inside normal IHP actions
toward a typed controller spec such as:

```haskell
sessionsControllerSpec :: BepisControllerSpec SessionsController

instance Controller SessionsController where
    beforeAction = runBepisBeforeAction sessionsControllerSpec
    action = runBepisControllerAction sessionsControllerSpec
```

## Prototype Shape Considered

A useful spec would need to capture:

- controller policy;
- each IHP action constructor;
- handler implementation;
- operation kind and expected response categories;
- runtime fact requirements when they are true safety invariants;
- architecture fact emission/provenance.

Sketch:

```haskell
sessionsControllerSpec = controllerSpec BepisPublicController
    [ pageAction NewSessionAction handleNewSession
    , mutationAction CreateSessionAction handleCreateSession
    , mutationAction DeleteSessionAction handleDeleteSession
    ]
```

## Ergonomic Issues

IHP action constructors are ordinary sum constructors with different field
shapes. A single `BepisControllerSpec controller` that dispatches all actions
would likely require GADTs, existentials, or typeclass wrappers to preserve
handler-specific fields. That is possible, but it is still more complex than the
current boundary:

```haskell
action currentAction@SomeAction { field } =
    runBepis currentAction BepisMutationAction do
        ...
```

The current pattern gives the important benefits without replacing IHP:

- IHP remains visibly in control of routing and dispatch;
- action source locations stay obvious;
- architecture scanners can detect typed-runner confidence;
- facts are emitted by helpers that actually perform effects;
- convention checks can enforce migrated controllers without a dispatcher.

## Decision

Defer typed `ControllerSpec` dispatch.

Do not introduce a dispatcher unless the current `runBepis` pattern shows
repeated boilerplate that cannot be solved with smaller helpers, or a future
feature needs a single typed manifest for controller actions that generated
contracts cannot provide.

## Revisit Trigger

Revisit `ControllerSpec` if a future implementation can prove it is simpler than
normal IHP actions plus `runBepis`, fact-emitting helpers, and deterministic
architecture gates. Prototype on one controller only and compare the diff before
adopting.
