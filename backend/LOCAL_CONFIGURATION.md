# Local API configuration

Shared `PhotographyBooking.Api/appsettings*.json` files contain no credentials.
In Development, the API optionally reads
`PhotographyBooking.Api/appsettings.Development.local.json`. This file is ignored
by Git and excluded from build/publish copying. Keep it private; it is plaintext
local storage, not an encrypted secret store.

The existing local database connection and development JWT key have been moved
there. No database changes are needed. For a new checkout, create the local file
with your own development values using this placeholder-only shape:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=<host>;Port=<port>;Database=<database>;Username=<username>;Password=<password>"
  },
  "Jwt": {
    "Key": "<unique-development-signing-key-at-least-32-bytes>"
  }
}
```

Configuration priority, lowest to highest:

1. Shared appsettings JSON, including the environment-specific file.
2. The optional local JSON file, only in Development.
3. Existing ASP.NET Core development user secrets.
4. Environment variables, including `ConnectionStrings__DefaultConnection` and `Jwt__Key`.
5. Command-line configuration.

`Jwt:Issuer` and `Jwt:Audience` remain in shared development settings. The existing
user-secrets ID and development admin configuration are unchanged. The backend
does not automatically load `.env`; its `.env.example` is a template for setting
environment variables. Never place real secrets in an example file.

Production does not load the local development file. Supply deployment credentials
through the deployment environment or its secret store; no production secrets
are included here.

From the repository root, verification without database access:

```powershell
git check-ignore backend/PhotographyBooking.Api/appsettings.Development.local.json
git ls-files -- backend/PhotographyBooking.Api/appsettings.Development.local.json
dotnet build backend/PhotographyBooking.Api/PhotographyBooking.Api.csproj --no-restore
```

The first command should show the local filename; the second should print nothing.
Do not print the local file or use `dotnet user-secrets list` in shared logs.
Starting the API runs the existing development admin seeder and can write to the
database, so it is not a read-only verification step.

The current HEAD already contains a database credential and a JWT signing key.
Cleaning the working tree does not remove them from Git history. Rotate those
exposed credentials separately; this change neither rewrites history nor changes
database credentials.
