var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var env = Environment.GetEnvironmentVariable("HELLO_ENV") ?? "unknown";

app.MapGet("/", () => $"Hello World, {env}");
app.MapGet("/health", () => Results.Ok());

app.Run();
