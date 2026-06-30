# Typed Bepis ControllerSpec Prototype Decision

Ticket: `ir-djtt`

## Goal

Evaluate whether Bepis should move beyond per-action wrappers toward a typed
controller spec such as:

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
- action kind and response kinds;
- optional mutation spec;
- architecture fact emission/provenance.

Sketch:

```haskell
sessionsControllerSpec = controllerSpec BepisPublicController
    [ pageAction "NewSessionAction" NewSessionAction handleNewSession
    , mutationAction "CreateSessionAction" CreateSessionAction bepisCurrentUserMutationSpec handleCreateSession
    , mutationAction "DeleteSessionAction" DeleteSessionAction bepisCurrentUserMutationSpec handleDeleteSession
    ]
```

## Ergonomic Issues

IHP action constructors are ordinary sum constructors with different field
shapes. A single `BepisControllerSpec controller` that dispatches all actions
would likely require GADTs, existentials, or typeclass wrappers to preserve
handler-specific fields. That is possible, but it makes the first migration
substantially more complex than the current wrapper pattern:

```haskell
action SomeAction { field } =
    bepisMutationAction "SomeAction" someSpec do
        ...
```

The wrapper pattern already gives the most important near-term benefits:

- IHP remains visibly in control of routing and dispatch;
- action source locations stay obvious;
- architecture scanners can detect typed-wrapper confidence;
- mutation specs are present on behavior paths;
- convention checks can enforce migrated controllers without a dispatcher.

## Decision

Defer typed `ControllerSpec` dispatch.

Do not introduce a dispatcher until at least two more controllers are migrated
with the wrapper pattern and the pain is concrete. The next useful step is not a
GADT dispatcher; it is better wrapper ergonomics and convention enforcement:

- small named mutation specs;
- optional response wrappers where they add value;
- architecture facts from wrappers/specs;
- failing checks for migrated controllers.

## Revisit Trigger

Revisit `ControllerSpec` if wrapper-per-action migration shows repeated
boilerplate that cannot be solved with smaller helpers, or if a future feature
needs a single typed manifest for controller actions that the scanner cannot
reliably derive from source.

If revisited, prototype on `SessionsController` only and compare the diff
against the current migrated wrapper implementation before adopting.
