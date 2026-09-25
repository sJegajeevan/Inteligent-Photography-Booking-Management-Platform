using System.Text;
using System.Security.Claims;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using PhotographyBooking.Api.Data;

var builder = WebApplication.CreateBuilder(args);

if (builder.Environment.IsDevelopment())
{
    // Local credentials override shared JSON, but not user secrets, environment or CLI.
    var developmentJson = builder.Configuration.Sources
        .OfType<Microsoft.Extensions.Configuration.Json.JsonConfigurationSource>()
        .Single(source => source.Path == "appsettings.Development.json");
    builder.Configuration.Sources.Insert(
        builder.Configuration.Sources.IndexOf(developmentJson) + 1,
        new Microsoft.Extensions.Configuration.Json.JsonConfigurationSource
        {
            FileProvider = builder.Environment.ContentRootFileProvider,
            Path = "appsettings.Development.local.json",
            Optional = true,
            ReloadOnChange = true
        });
}

// Database
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("DefaultConnection")
    ));

// Controllers
builder.Services.AddControllers();
builder.Services.AddSingleton<PhotographyBooking.Api.Services.DistanceService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.StudioDiscoveryService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.BookingSlotValidationService>();
builder.Services.AddSingleton<TimeProvider>(TimeProvider.System);
builder.Services.AddScoped<PhotographyBooking.Api.Services.SchedulingCandidateService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.RecommendationValidationService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.FinalRecommendationValidationService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.AiWorkflowApprovalService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.CanonicalProposalService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.AiWorkflowPublicationService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.AiWorkflowService>();
builder.Services.AddSingleton(PhotographyBooking.Api.Services.PythonWorkflowOptions.FromEnvironment());
builder.Services.AddHttpClient<PhotographyBooking.Api.Services.InternalPythonWorkflowClient>(client =>
    client.Timeout = Timeout.InfiniteTimeSpan)
    .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false, UseProxy = false })
    .RemoveAllLoggers();
builder.Services.AddScoped<PhotographyBooking.Api.Services.AiWorkflowExecutionService>();
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("CustomerChangePassword", context => RateLimitPartition.GetFixedWindowLimiter(
        context.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "anonymous",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 5,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0,
            AutoReplenishment = true
        }));
});
builder.Services.AddScoped<PhotographyBooking.Api.Services.StudioService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.StudioPortfolioService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.StudioServicesCrudService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.StudioAvailabilityService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.PhotographyPackageService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.PackageAddonService>();
builder.Services.AddScoped<PhotographyBooking.Api.Services.PackagePriceCalculationService>();
var jwtSection = builder.Configuration.GetSection("Jwt");
var jwtKey = jwtSection["Key"] ?? throw new InvalidOperationException("Jwt:Key is required.");
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options => options.TokenValidationParameters = new TokenValidationParameters
{
    ValidateIssuer = true, ValidIssuer = jwtSection["Issuer"], ValidateAudience = true, ValidAudience = jwtSection["Audience"],
    ValidateIssuerSigningKey = true, IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)), ValidateLifetime = true, ClockSkew = TimeSpan.FromMinutes(1)
});

// Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

if (builder.Environment.IsDevelopment())
{
    builder.Services.AddCors(options => options.AddPolicy("FlutterDevelopment", policy =>
        policy.SetIsOriginAllowed(origin =>
                Uri.TryCreate(origin, UriKind.Absolute, out var uri) &&
                (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps) &&
                (uri.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase) || uri.Host == "127.0.0.1"))
            .AllowAnyMethod()
            .AllowAnyHeader()));
}

var app = builder.Build();

// Schema changes are deployment-only. See ../database/reconciliation/README.md.
// Never run the archived legacy migrations or schema/data SQL at application startup.

if (app.Environment.IsDevelopment())
{
    await PhotographyBooking.Api.Services.DevelopmentAdminSeeder.ProvisionAsync(
        app.Services,
        app.Configuration,
        app.Logger);
}

// Development
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

if (!app.Environment.IsDevelopment())
{
    app.UseHttpsRedirection();
}

app.UseRouting();

if (app.Environment.IsDevelopment())
{
    app.UseCors("FlutterDevelopment");
}

app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();
app.UseStaticFiles();

app.MapControllers();

app.Run();
