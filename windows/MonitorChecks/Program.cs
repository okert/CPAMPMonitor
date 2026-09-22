using System.Net;
using System.Text.Json.Nodes;
using CPAMP.MonitorCore;

var now = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
var checks = 0;
void Check(bool condition, string name)
{
    if (!condition) throw new Exception("FAIL " + name);
    Console.WriteLine("PASS " + name); checks++;
}
void Reject(Action action, string name)
{
    try { action(); } catch (MonitorException) { Check(true, name); return; }
    throw new Exception("FAIL " + name);
}
JsonObject Obj(string text) => JsonNode.Parse(text)!.AsObject();
QuotaResult Parse(string provider, string text) => QuotaParser.Parse(provider, Obj(text), now);
Check(Configuration.NormalizeUrl(" HTTPS://example.com/prefix/management.html ").AbsoluteUri == "https://example.com/prefix/", "URL normalization and path prefix");
foreach (var url in new[] { "http://example.com", "https://user:pass@example.com", "https://example.com?q=secret", "https://example.com/#x", "file:///tmp/a", "http://127.0.0.1.example.com" })
    Reject(() => Configuration.NormalizeUrl(url), "Reject unsafe URL " + url.Split(':')[0]);
Check(Configuration.NormalizeUrl("http://127.0.0.1:18317").IsLoopback, "Loopback HTTP");
Reject(() => new Configuration { BaseUrl = "https://example.com", Interval = 59 }.Validate(), "Refresh bounds");
Reject(() => new Configuration { BaseUrl = "https://example.com", Critical = 20, Warning = 20 }.Validate(), "Threshold ordering");
Check(Json.Number(JsonValue.Create(true)) is null && Json.Number(JsonValue.Create("NaN")) is null && Json.Number(null) is null, "Invalid numbers are missing");
Check(Json.Timestamp(JsonValue.Create(1767225600000L)) == now && Json.Timestamp(JsonValue.Create(1767225600L)) == now, "Seconds and milliseconds timestamps");
var codex = Parse("codex", """{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":20,"limit_window_seconds":18000,"reset_after_seconds":120},"secondary_window":{"used_percent":null}}} """);
Check(codex.Windows.Count == 2 && codex.Windows[0].Remaining == 80 && codex.Windows[1].Remaining is null && codex.Plan == "plus", "Codex windows and null semantics");
Check(codex.Windows[0].Reset == now.AddSeconds(120), "Relative reset time");
Reject(() => Parse("codex", """{"rate_limit":{"primary_window":{"used_percent":101}}} """), "Out of range percent rejected");
var extra = Parse("codex", """{"code_review_rate_limit":{"primary_window":{"used_percent":1}},"additional_rate_limits":[{"limit_name":"tool","rate_limit":{"primary_window":{"used_percent":2}}}]}""");
Check(extra.Windows.Count == 2 && extra.Windows.Select(w => w.Id).Distinct().Count() == 2, "Additional and review quotas");
var ag = Parse("antigravity", """{"groups":[{"displayName":"Gemini","buckets":[{"bucketId":"b","window":"weekly","remainingFraction":0.9},{"window":"daily","remaining_fraction":null}]}]}""");
Check(ag.Windows[0].Remaining == 90 && ag.Windows[1].Remaining is null, "Antigravity shared buckets");
Check(Parse("xai", """{"config":{"creditUsagePercent":100,"currentPeriod":{"type":"WEEKLY","end":"2026-01-02T00:00:00Z"}}}""").Windows[0].Remaining == 0, "xAI exhausted quota is zero");
Reject(() => Parse("xai", """{"config":{"balance":0}}"""), "xAI missing usage is not zero");
Check(Parse("claude", """{"five_hour":{"utilization":10},"seven_day":{"utilization":45}}""").Windows.Count == 2, "Claude OAuth windows");
Reject(() => Parse("unknown", "{}"), "Unsupported provider");
var window = new QuotaWindow("w", "Weekly", 9, now.AddMinutes(10), now);
Check(window.Fresh(now, 600) && !window.Fresh(now.AddMinutes(11), 10000) && !window.Fresh(now.AddMinutes(5), 60), "Freshness and reset expiration");
Check(!(window with { Observed = now.AddSeconds(61) }).Fresh(now, 600), "Future observations rejected");
Check(QuotaWindow.MinimumFreshRemaining(new[] { window, window with { Id = "lower", Remaining = 37 },
    window with { Id = "stale", Remaining = 5, Observed = now.AddHours(-1) } }, now, 600) == 9,
    "Minimum fresh quota for selected account");
Check(QuotaWindow.MinimumFreshRemaining(new[] { window with { Remaining = null } }, now, 600) is null,
    "Unavailable selected account is not zero");
var displayConfig = new Configuration { DisplayAccountId = "codex:demo:1" };
displayConfig = displayConfig with { DisplayWindowId = "main:primary_window" };
var displayRoundTrip = System.Text.Json.JsonSerializer.Deserialize<Configuration>(System.Text.Json.JsonSerializer.Serialize(displayConfig))!;
Check(displayRoundTrip.DisplayAccountId == displayConfig.DisplayAccountId && displayRoundTrip.DisplayWindowId == displayConfig.DisplayWindowId,
    "Tray account and quota display settings round trip");
Check(QuotaWindow.MinimumFreshRemaining(new[] { window with { Id = "daily", Remaining = 70 },
    window with { Id = "weekly", Remaining = 40 } }, now, 600, "weekly") == 40,
    "Selected quota window minimum");
var ledger = new AlertLedger();
Check(ledger.Evaluate("a", window, 20, 10, now, 600) == 10, "Critical alert priority");
Check(ledger.Evaluate("a", window with { Remaining = 15 }, 20, 10, now, 600) is null, "Critical suppresses weaker alert");
var restored = System.Text.Json.JsonSerializer.Deserialize<AlertLedger>(System.Text.Json.JsonSerializer.Serialize(ledger))!;
Check(restored.Evaluate("a", window, 20, 10, now, 600) is null, "Persistent alert deduplication");
Check(ledger.Evaluate("stale", window, 20, 10, now.AddHours(1), 600) is null, "No stale alerts");
Check(ledger.Evaluate("a", window with { Reset = window.Reset!.Value.AddSeconds(30) }, 20, 10, now, 600) is null, "Reset jitter deduplicated");
var later = now.AddMinutes(11);
Check(ledger.Evaluate("a", window with { Reset = later.AddMinutes(10), Observed = later }, 20, 10, later, 600) == 10, "New cycle alerts again");
var account = Account.FromJson(Obj("""{"name":"test.json","provider":"Codex","auth_index":7,"account":{"account_id":"acct","plan_type":"plus"}}"""));
Check(account.Id == "codex:test.json:7" && Json.Text(account.Target()["auth_account_id_snapshot"]) == "acct", "Account identity and history target");

var handler = new RecordingHandler(_ => new(HttpStatusCode.OK) { Content = new StringContent("{\"files\":[]}") });
using (var client = new ApiClient("https://example.com/prefix", "test-key", handler))
{
    Check((await client.Accounts(default)).Count == 0, "Empty account list");
    Check(handler.LastUri == "https://example.com/prefix/v0/management/auth-files" && handler.Authorization == "Bearer test-key", "Request path and management authentication");
}
var quotaHandler = new RecordingHandler(_ => new(HttpStatusCode.OK) { Content = new StringContent("""{"status_code":200,"body":"{\"rate_limit\":{\"primary_window\":{\"used_percent\":25}}}"}""") });
using (var client = new ApiClient("https://example.com", "test-key", quotaHandler))
{
    Check((await client.Quota(account, default)).Windows[0].Remaining == 75, "String quota envelope");
    var body = Obj(quotaHandler.Body!);
    Check(Json.Text(body["header"]?["Authorization"]) == "Bearer $TOKEN$" && !quotaHandler.Body!.Contains("test-key"), "Provider token placeholder, no management key in forwarded body");
}
foreach (var status in new[] { 302, 401, 429 })
{
    using var client = new ApiClient("https://example.com", "test-key", new RecordingHandler(_ => new((HttpStatusCode)status) { Content = new StringContent("sensitive backend error") }));
    try { await client.Accounts(default); throw new Exception("Expected HTTP failure"); }
    catch (MonitorException e) { Check(e.Status == status && !e.Message.Contains("sensitive"), "Safe HTTP error " + status); }
}
using (var client = new ApiClient("https://example.com", "test-key", new RecordingHandler(_ => new(HttpStatusCode.OK) { Content = new StringContent("{\"status_code\":429}") })))
{
    try { await client.Quota(account, default); throw new Exception("Expected provider rate limit"); }
    catch (MonitorException e) { Check(e.Status == 429, "Provider rate limit preserved"); }
}
using (var cts = new CancellationTokenSource())
using (var client = new ApiClient("https://example.com", "test-key", new RecordingHandler(_ => new(HttpStatusCode.OK))))
{
    cts.Cancel();
    try { await client.Accounts(cts.Token); throw new Exception("Expected cancellation"); }
    catch (OperationCanceledException) { Check(true, "Request cancellation"); }
}
Console.WriteLine($"{checks} checks passed");

sealed class RecordingHandler(Func<HttpRequestMessage, HttpResponseMessage> response) : HttpMessageHandler
{
    public string? LastUri, Authorization, Body;
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        LastUri = request.RequestUri!.AbsoluteUri;
        Authorization = request.Headers.Authorization?.ToString();
        Body = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
        return response(request);
    }
}
