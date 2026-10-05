# Studio notifications

Apply `add-studio-notifications.sql` once to the existing PostgreSQL database before deploying the API:

```sh
psql -X --set=ON_ERROR_STOP=1 --dbname="$DATABASE_URL" --file=backend/database/studio-notifications/add-studio-notifications.sql
```

Use the existing database deployment process and backup policy. This script is transactional and additive. It has not been applied by this implementation. Do not run the historical EF migration chain, which the API project excludes.

`Notifications.CustomerId` remains the customer associated with the event. A null `StudioId` identifies the existing customer feed; a non-null `StudioId` identifies a studio recipient. Customer and studio notifications have separate rows and read states. Existing rows retain their current meaning. There is no historical backfill.

New bookings save both recipient rows in the existing booking transaction. Customer booking messages save the message and studio notification in one SaveChanges transaction. Studio replies do not notify the same studio.

The authenticated Studio endpoints are `GET /api/studio/notifications`, `GET /api/studio/notifications/unread-count`, and `PATCH /api/studio/notifications/{id}/read`. They scope access to studios owned by the JWT user and validate the database role. Marking read is idempotent.

Open the existing studio header bell or `/studio/notifications`. The page displays customer name, Message/Booking type, details, local date/time, and read status. The page and bell poll every 30 seconds; the page also supports manual refresh. Notification times are stored in UTC.

Validation: `dotnet run --project backend/tests/BookingMessageChecks`, `dotnet run --project backend/tests/BookingCompletionChecks`, `npm run build`, and `node --test tests/studio-notifications.test.mjs` from the frontend folder. These backend checks use ephemeral SQLite, without accessing the application database. PostgreSQL schema deployment and the full booking-creation transaction still require deployment verification.
