using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CPAMP.MonitorCore;

public sealed class ApiClient : IDisposable
{
    private readonly HttpClient http;
    private readonly Uri baseUrl;
    public ApiClient(string url, string secret, HttpMessageHandler? handler = null)
    {
        baseUrl = Configuration.NormalizeUrl(url);
        http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false });
        http.Timeout = TimeSpan.FromSeconds(50);
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", secret);
        http.DefaultRequestHeaders.Accept.Add(new("application/json"));
    }
    public async Task<JsonObject> Request(string path, JsonObject? body, CancellationToken token)
    {
        using var request = new HttpRequestMessage(body is null ? HttpMethod.Get : HttpMethod.Post, new Uri(baseUrl, path));
        if (body is not null) request.Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json");
        using var response = await http.SendAsync(request, token);
        var status = (int)response.StatusCode;
        if (!response.IsSuccessStatusCode)
            throw new MonitorException(status switch {
                401 or 403 => "Authentication failed. Check the management key.",
                >= 300 and < 400 => "Redirect refused. Enter the final HTTPS service URL.",
                429 => "Rate limited. Retry later.", _ => $"Service request failed (HTTP {status})." }, status);
        return JsonNode.Parse(await response.Content.ReadAsStringAsync(token)) as JsonObject
            ?? throw new MonitorException("The service did not return a JSON object.");
    }
    public async Task<List<Account>> Accounts(CancellationToken token)
    {
        var data = await Request("v0/management/auth-files", null, token);
        if (data["files"] is not JsonArray) throw new MonitorException("Incompatible account list response.");
        return Json.Objects(data["files"]).Select(Account.FromJson).DistinctBy(a => a.Id)
            .OrderBy(a => a.Provider).ThenBy(a => a.Title).ToList();
    }
    public async Task<Dictionary<string, JsonObject>> History(List<Account> accounts, CancellationToken token)
    {
        Dictionary<string, JsonObject> result = [];
        foreach (var batch in accounts.Chunk(200))
        {
            var data = await Request("v0/management/monitoring/account-history",
                new() { ["accounts"] = new JsonArray(batch.Select(a => (JsonNode)a.Target()).ToArray()) }, token);
            if (data["items"] is not JsonArray) throw new MonitorException("Incompatible history response.");
            foreach (var item in Json.Objects(data["items"])) result[Json.Text(item["row_key"])] = item;
        }
        return result;
    }
    public async Task<QuotaResult> Quota(Account account, CancellationToken token)
    {
        if (account.AuthIndex.Length == 0) throw new MonitorException("The account has no auth_index.");
        var headers = new JsonObject { ["Authorization"] = "Bearer $TOKEN$", ["Content-Type"] = "application/json" };
        var body = new JsonObject { ["authIndex"] = account.AuthIndex, ["method"] = "GET" };
        switch (account.Provider)
        {
            case "codex":
                body["url"] = "https://chatgpt.com/backend-api/wham/usage";
                headers["User-Agent"] = "codex-tui/0.149.1";
                if (account.AccountId.Length > 0) headers["Chatgpt-Account-Id"] = account.AccountId;
                break;
            case "antigravity":
                body["url"] = "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary";
                body["method"] = "POST";
                body["data"] = new JsonObject { ["project"] = account.ProjectId }.ToJsonString();
                headers["User-Agent"] = "antigravity/1.0.13";
                break;
            case "xai":
                body["url"] = "https://cli-chat-proxy.grok.com/v1/billing?format=credits";
                headers["x-xai-token-auth"] = "xai-grok-cli";
                headers["x-grok-client-version"] = "0.2.101";
                headers["User-Agent"] = "grok-pager/0.2.101 grok-shell/0.2.101 (windows; " +
                    System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant() + ")";
                break;
            case "claude":
                body["url"] = "https://api.anthropic.com/api/oauth/usage";
                headers["anthropic-beta"] = "oauth-2025-04-20";
                break;
            default: throw new MonitorException("Live quota is not supported for this provider.");
        }
        body["header"] = headers;
        var data = await Request("v0/management/api-call", body, token);
        var status = (int)(Json.Number(data["status_code"] ?? data["statusCode"]) ?? 0);
        if (status is < 200 or >= 300) throw new MonitorException(status == 429 ?
            "Quota rate limited. Retrying in 15 minutes." : $"Provider quota request failed (HTTP {status}).", status);
        var payload = data["body"] as JsonObject;
        if (payload is null && data["body"] is JsonValue raw && raw.TryGetValue<string>(out var text))
            payload = JsonNode.Parse(text) as JsonObject;
        return QuotaParser.Parse(account.Provider, payload ?? throw new MonitorException("Unrecognized quota response."), DateTimeOffset.UtcNow);
    }
    public static string SafeMessage(Exception error) => error switch {
        MonitorException e => e.Message,
        OperationCanceledException => "Request cancelled or timed out.",
        HttpRequestException => "Network connection failed. Check the service address and connection.",
        JsonException => "The response could not be parsed. Check the service version.",
        _ => "Operation failed. Check configuration and local storage permissions." };
    public void Dispose() => http.Dispose();
}
