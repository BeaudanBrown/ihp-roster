# Application Guidelines

## Schema (`Application/Schema.sql`)
This file is the source of truth for database models. Read `IHP/Guide/database.markdown`.

- Edit `Application/Schema.sql` to add or modify tables
- IHP generates `build/Generated/Types.hs` from the schema
- Use `snake_case` for table and column names
- Table names should be plural
- Keep the standard `id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL`
- Prefer `created_at` and `updated_at` timestamp columns on mutable tables

After editing the schema:
1. Run `direnv exec . regen-types`
2. Run `make db` while the dev server and database are available

Without `make db`, the app can typecheck but still fail at runtime with missing relations.

To confirm the schema is applied:

```bash
psql -h "$PWD/build/db" app -c "\dt"
```

## Helpers
- `Application/Helper/Controller.hs` contains helpers available in all controllers
- `Application/Helper/View.hs` contains helpers available in all views
- Both are re-exported by the controller and view preludes

For request-scoped business context, resolve it once in `Web/FrontController.initContext`, store it with `putContext`, and read it later from frozen context instead of re-querying in views.

Keep reusable overlay helpers in `Application/Helper/View.hs`:
- shared dialog and toast mount ids
- declarative overlay config and button types
- renderers for workflow dialogs, modal fallbacks, and toast notifications

Prefer declarative config records over callback-heavy view builders.

Shared form helpers should usually render fields and the `<form>` wrapper only. Put save/cancel controls in shared overlay footers so the same form body can be reused across dialog and page-modal flows.

## Database Queries
Read `IHP/Guide/querybuilder.markdown`. Common patterns:

```haskell
posts <- query @Post |> fetch

post <- query @Post
    |> filterWhere (#id, postId)
    |> fetchOne

newRecord @Post
    |> set #title "Hello"
    |> createRecord

post
    |> set #title "Updated"
    |> updateRecord

deleteRecord post
```
