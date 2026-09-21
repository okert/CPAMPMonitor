using System.Globalization;
using System.Text.Json.Nodes;

namespace CPAMP.MonitorCore;

public sealed class MonitorException(string message, int? status = null) : Exception(message)
{
    public int? Status { get; } = status;
}

public sealed record Configuration
{
    public string BaseUrl { get; init; } = "";
    public string Name { get; init; } = "CPAMP";
    public int Interval { get; init; } = 300;
    public int Warning { get; init; } = 20;
    public int Critical { get; init; } = 10;
    public bool Notifications { get; init; } = true;
    public HashSet<string> Excluded { get; init; } = [];
    public List<string> AccountOrder { get; init; } = [];
    public double MaxAge => Interval * 2 + 60;

    public static Uri NormalizeUrl(string input)
    {
        if (!Uri.TryCreate(input.Trim(), UriKind.Absolute, out var uri) ||
            uri.Scheme is not ("http" or "https") || string.IsNullOrEmpty(uri.Host) ||
            uri.UserInfo.Length != 0 || uri.Query.Length != 0 || uri.Fragment.Length != 0)
            throw new MonitorException("Enter a service URL without credentials, query parameters or fragments.");
        if (uri.Scheme == "http" && uri.Host.ToLowerInvariant() is not ("localhost" or "127.0.0.1" or "[::1]"))
            throw new MonitorException("Remote services must use HTTPS.");
        var builder = new UriBuilder(uri);
        var path = uri.AbsolutePath.TrimEnd('/');
        foreach (var suffix in new[] { "/management.html", "/v0/management", "/v1" })
            if (path.EndsWith(suffix, StringComparison.Ordinal)) { path = path[..^suffix.Length]; break; }
        builder.Path = path + "/";
        return builder.Uri;
    }

    public Configuration Validate()
    {
        if (Interval is < 60 or > 3600 || Critical < 1 || Warning > 99 || Critical >= Warning)
            throw new MonitorException("Refresh: 1-60 minutes. Thresholds: 1 <= critical < warning <= 99.");
        return this with { BaseUrl = NormalizeUrl(BaseUrl).AbsoluteUri, Name = Name.Trim() };
    }
}

public static class Json
{
    public static string Text(JsonNode? node) => node is JsonValue v ? v.ToString() : "";
    public static double? Number(JsonNode? node)
    {
        if (node is not JsonValue v || !double.TryParse(v.ToString(), NumberStyles.Float,
                CultureInfo.InvariantCulture, out var n) || !double.IsFinite(n)) return null;
        return n;
    }
    public static double? Percent(JsonNode? node) => Number(node) is >= 0 and <= 100 ? Number(node) : null;
    public static DateTimeOffset? Timestamp(JsonNode? node)
    {
        if (Number(node) is > 0 and < 100_000_000_000_000 and var n)
        {
            try { return DateTimeOffset.UnixEpoch.AddSeconds(n > 100_000_000_000 ? n / 1000 : n); }
            catch (ArgumentOutOfRangeException) { return null; }
        }
        return DateTimeOffset.TryParse(Text(node), CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal, out var date) ? date : null;
    }
    public static IEnumerable<JsonObject> Objects(JsonNode? node) =>
        node is JsonArray a ? a.OfType<JsonObject>() : [];
}

public sealed record Account(string Filename, string Provider, string AuthIndex, string Email,
    string Status, bool Disabled, string ProjectId, string AccountId, string Plan)
{
    public string Id => $"{Provider}:{Filename}:{AuthIndex}";
    public string Title => string.IsNullOrEmpty(Email) ? Filename : Email;
    public string ProviderName => Provider switch { "codex" => "Codex", "xai" => "Grok / xAI",
        "antigravity" => "Antigravity", "claude" => "Claude", _ => Provider };
    public static Account FromJson(JsonObject j)
    {
        var a = j["account"] as JsonObject;
        return new(Json.Text(j["name"]), Json.Text(j["provider"] ?? j["type"]).ToLowerInvariant(),
            Json.Text(j["auth_index"]), Json.Text(j["email"]), Json.Text(j["status"]),
            j["disabled"] is JsonValue d && d.TryGetValue<bool>(out var disabled) && disabled,
            Json.Text(j["project_id"]), Json.Text(a?["account_id"] ?? j["account_id"]),
            Json.Text(a?["plan_type"] ?? j["account_type"]));
    }
    public JsonObject Target()
    {
        var target = new JsonObject { ["row_key"] = Id, ["auth_file_snapshot"] = Filename,
            ["auth_provider_snapshot"] = Provider, ["auth_index"] = AuthIndex };
        if (AccountId.Length > 0) target["auth_account_id_snapshot"] = AccountId;
        if (ProjectId.Length > 0) target["auth_project_id_snapshot"] = ProjectId;
        return target;
    }
}

public sealed record QuotaWindow(string Id, string Title, double? Remaining, DateTimeOffset? Reset,
    DateTimeOffset Observed)
{
    public bool Fresh(DateTimeOffset now, double maxAge) => (now - Observed).TotalSeconds >= -60 &&
        (now - Observed).TotalSeconds <= maxAge && (Reset is null || Reset > now);
}
public sealed record QuotaResult(List<QuotaWindow> Windows, string Plan = "");

public static class QuotaParser
{
    public static QuotaResult Parse(string provider, JsonObject payload, DateTimeOffset now)
    {
        List<QuotaWindow> windows = [];
        var plan = "";
        void Add(string id, string title, double? remaining, DateTimeOffset? reset) =>
            windows.Add(new(id, title, remaining, reset, now));
        switch (provider)
        {
            case "codex":
                plan = Json.Text(payload["plan_type"]);
                List<(string Id, string Prefix, JsonObject Limit)> limits = [];
                if (payload["rate_limit"] is JsonObject main) limits.Add(("main", "", main));
                if (payload["code_review_rate_limit"] is JsonObject review) limits.Add(("review", "Code review ", review));
                var extraIndex = 0;
                foreach (var extra in Json.Objects(payload["additional_rate_limits"]))
                {
                    var name = Json.Text(extra["limit_name"] ?? extra["metered_feature"]);
                    if (extra["rate_limit"] is JsonObject rate)
                        limits.Add(("extra-" + (name.Length == 0 ? extraIndex.ToString() : name), name + " ", rate));
                    extraIndex++;
                }
                foreach (var (id, prefix, limit) in limits)
                    foreach (var key in new[] { "primary_window", "secondary_window" })
                    {
                        if (limit[key] is not JsonObject w) continue;
                        var duration = Json.Number(w["limit_window_seconds"]);
                        var label = duration == 604800 ? "Weekly" : duration.HasValue ? $"{duration / 3600:0} hours" : "Quota";
                        var reset = Json.Timestamp(w["reset_at"]);
                        if (reset is null && Json.Number(w["reset_after_seconds"]) is > 0 and < 315360000 and var seconds)
                            reset = now.AddSeconds(seconds);
                        Add(id + ":" + key, prefix + label, 100 - Json.Percent(w["used_percent"]), reset);
                    }
                break;
            case "antigravity":
                var gi = 0;
                foreach (var group in Json.Objects(payload["groups"]))
                {
                    var label = Json.Text(group["displayName"] ?? group["display_name"]);
                    var bi = 0;
                    foreach (var bucket in Json.Objects(group["buckets"]))
                    {
                        var period = Json.Text(bucket["window"]);
                        var fraction = Json.Number(bucket["remainingFraction"] ?? bucket["remaining_fraction"]);
                        var id = Json.Text(bucket["bucketId"] ?? bucket["bucket_id"]);
                        Add(id.Length == 0 ? $"{label}-{gi}-{period}-{bi}" : id,
                            $"{(label.Length == 0 ? $"Quota group {gi + 1}" : label)} {(period == "weekly" ? "Weekly" : period)}",
                            fraction is >= 0 and <= 1 ? fraction * 100 : null,
                            Json.Timestamp(bucket["resetTime"] ?? bucket["reset_time"]));
                        bi++;
                    }
                    gi++;
                }
                break;
            case "xai":
                var config = payload["config"] as JsonObject;
                var current = config?["currentPeriod"] as JsonObject;
                if (Json.Percent(config?["creditUsagePercent"]) is double used)
                    Add("billing", Json.Text(current?["type"]).Contains("WEEKLY") ? "Weekly" : "Billing period",
                        100 - used, Json.Timestamp(current?["end"] ?? config?["billingPeriodEnd"]));
                break;
            case "claude":
                foreach (var (key, value) in payload.OrderBy(p => p.Key))
                    if ((key.StartsWith("five_hour") || key.StartsWith("seven_day")) && value is JsonObject w)
                        Add(key, key == "five_hour" ? "5 hours" : key == "seven_day" ? "Weekly" : key,
                            100 - Json.Percent(w["utilization"]), Json.Timestamp(w["resets_at"]));
                break;
            default: throw new MonitorException("Live quota is not supported for this provider.");
        }
        if (!windows.Any(w => w.Remaining.HasValue))
            throw new MonitorException("No recognized quota returned. Unknown values are not treated as zero.");
        return new(windows, plan);
    }
}

public sealed class AlertEntry
{
    public DateTimeOffset? Reset { get; set; }
    public HashSet<int> Thresholds { get; set; } = [];
    public DateTimeOffset Touched { get; set; }
}
public sealed class AlertLedger
{
    public Dictionary<string, AlertEntry> Entries { get; set; } = [];
    public int? Evaluate(string key, QuotaWindow window, int warning, int critical,
        DateTimeOffset now, double maxAge)
    {
        if (!window.Fresh(now, maxAge) || window.Remaining is not double remaining) return null;
        if (!Entries.TryGetValue(key, out var entry)) entry = new() { Reset = window.Reset };
        if (entry.Reset is DateTimeOffset old && window.Reset is DateTimeOffset next &&
            (next - old).TotalSeconds > 120 && now >= old) entry.Thresholds.Clear();
        else if (entry.Reset is null && window.Reset is null && remaining > warning + 5) entry.Thresholds.Clear();
        entry.Reset = window.Reset;
        entry.Touched = now;
        int? threshold = remaining <= critical ? critical : remaining <= warning ? warning : null;
        var alert = threshold.HasValue && entry.Thresholds.Add(threshold.Value);
        if (alert && threshold == critical) entry.Thresholds.Add(warning);
        Entries[key] = entry;
        foreach (var stale in Entries.Where(p => (now - p.Value.Touched).TotalDays >= 90).Select(p => p.Key).ToArray())
            Entries.Remove(stale);
        return alert ? threshold : null;
    }
}
