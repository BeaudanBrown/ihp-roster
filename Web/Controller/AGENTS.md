# Controller Guidelines

## Reference
Read `IHP/Guide/controller.markdown` before implementing controller logic.

## Creating a New Controller

Every controller requires changes in four places:

1. `Web/Types.hs` — define the controller type
2. `Web/Routes.hs` — add `instance AutoRoute MyController`
3. `Web/FrontController.hs` — add the import and `parseRoute @MyController`
4. `Web/Controller/My.hs` — implement the actions

Example:

```haskell
data PostsController
    = PostsAction
    | NewPostAction
    | ShowPostAction { postId :: !(Id Post) }
    | CreatePostAction
    | EditPostAction { postId :: !(Id Post) }
    | UpdatePostAction { postId :: !(Id Post) }
    | DeletePostAction { postId :: !(Id Post) }
    deriving (Eq, Show, Data)
```

## Common Patterns
- Always import `Web.Controller.Prelude`
- Use `param @Type "name"` for request parameters
- Use `fetch`, `fetchOne`, and `fetchOneOrNothing` for queries
- Redirect after successful mutations
- Render views with `render ViewName { .. }`
- Use builder functions for form validation and transformation
- Access the authenticated user through `currentUser` when auth is enabled

## State Transition Pattern
- For status changes with related side effects, wrap the update and its side effects in `withTransaction`

## Overlay Controller Pattern
- Prefer dedicated HTMX dialog-fragment actions for in-place workflows over `setModal` plus page navigation
- Typical shape:
  - GET action renders the dialog fragment
  - POST or PATCH action re-renders the dialog on validation failure
  - success returns only the updated page fragments and any out-of-band dialog or toast updates
- Keep `setModal` as a fallback when a workflow must support non-HTMX behavior
- Reuse the same form helper for initial dialog render and validation rerender
- Return the smallest updated fragment possible instead of full-page redirects
- Only one workflow dialog should be active at a time
