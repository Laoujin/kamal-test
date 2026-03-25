var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => new { message = "Hello from paas-deploy!", environment = app.Environment.EnvironmentName });
app.MapGet("/health", () => Results.Ok());

app.Run();
