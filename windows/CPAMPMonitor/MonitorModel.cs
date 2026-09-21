using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Text.Json.Nodes;
using System.Windows.Threading;
using CPAMP.MonitorCore;

namespace CPAMP.Windows;

internal sealed class AccountState(Account account)
{
    public Account Account { get; set; } = account;
    public List<QuotaWindow> Windows { get; set; } = [];
    public string Plan { get; set; } = account.Plan;
    public string? Error { get; set; }
    public DateTimeOffset? RetryAfter { get; set; }
    public JsonObject? History { get; set; }
    public bool Enabled { get; set; }
}

internal sealed class MonitorModel : IDisposable
{
    public Configuration Config { get; private set; } = Storage.Load<Configuration>("settings");
    public List<AccountState> Accounts { get; private set; } = [];
    public bool Refreshing { get; private set; }
    public bool Paused { get; private set; }
    public string? Error { get; private set; }
    public string? HistoryError { get; private set; }
    public string? StorageError { get; private set; }
    public DateTimeOffset? LastRefresh { get; private set; }
    public DateTimeOffset? NextRefresh { get; private set; }
    public event Action? Changed;
    public Action<string, string, bool>? Notify;
    private AlertLedger ledger = Storage.Load<AlertLedger>("alerts");
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(15) };
    private CancellationTokenSource? request;
    private int generation;
    public double? Lowest => LowestFor(null);
    public double? DisplayLowest => LowestFor(Config.DisplayAccountId);
    public string DisplayLabel => Config.DisplayAccountId is null ? "All accounts minimum" :
        Accounts.FirstOrDefault(a => a.Account.Id == Config.DisplayAccountId)?.Account.Title ?? "Selected account";
    private double? LowestFor(string? accountId)
    {
        if (Paused || Error is not null) return null;
        var rows = Accounts.Where(a => a.Enabled && a.Error is null && (accountId is null || a.Account.Id == accountId));
        return QuotaWindow.MinimumFreshRemaining(rows.SelectMany(a => a.Windows), DateTimeOffset.UtcNow, Config.MaxAge);
    }
    public string Status => Paused ? "Paused" : Refreshing ? "Refreshing" : Config.BaseUrl.Length == 0 ? "Not connected" :
        Error is not null ? "Connection failed" : !Accounts.Any(a => a.Enabled) ? "No monitored accounts" :
        Accounts.Any(a => a.Enabled && (a.Error is not null || a.Windows.Count == 0 ||
            a.Windows.Any(w => !w.Fresh(DateTimeOffset.UtcNow, Config.MaxAge)))) ? "Some data unavailable" :
        Lowest <= Config.Critical ? "Quota critical" : Lowest <= Config.Warning ? "Quota low" : "Monitoring";
    public void Start()
    {
        StorageError = Storage.Warning;
        if (Config.BaseUrl.Length > 0)
            try { Config = Config.Validate(); } catch (MonitorException e) { Error = e.Message; Config = Config with { BaseUrl = "" }; }
        timer.Tick += (_, _) => { Changed?.Invoke(); if (!Paused && NextRefresh <= DateTimeOffset.UtcNow) _ = Refresh(); };
        timer.Start();
        _ = Refresh();
    }
    public void TogglePause()
    {
        Paused = !Paused;
        if (Paused) Cancel(); else _ = Refresh();
        Changed?.Invoke();
    }
    private void Cancel()
    {
        generation++;
        request?.Cancel();
        request = null;
        Refreshing = false;
    }
    public async Task Refresh()
    {
        if (Refreshing || Paused || Config.BaseUrl.Length == 0) return;
        Refreshing = true;
        var current = ++generation;
        using var cts = new CancellationTokenSource();
        request = cts;
        var token = cts.Token;
        Changed?.Invoke();
        try
        {
            var secret = Storage.ReadSecret(Config.BaseUrl);
            if (secret.Length == 0) throw new MonitorException("No management key saved for this address. Open Settings.");
            using var client = new ApiClient(Config.BaseUrl, secret);
            var remote = await client.Accounts(token);
            token.ThrowIfCancellationRequested();
            var old = Accounts.ToDictionary(a => a.Account.Id);
            Accounts = remote.OrderBy(a => { var i = Config.AccountOrder.IndexOf(a.Id); return i < 0 ? int.MaxValue : i; })
                .Select(a => {
                    var row = old.GetValueOrDefault(a.Id) ?? new(a);
                    row.Account = a;
                    row.Enabled = !a.Disabled && !Config.Excluded.Contains(a.Id);
                    return row;
                }).ToList();
            Error = null;
            foreach (var row in Accounts.Where(a => a.Enabled))
            {
                if (row.RetryAfter > DateTimeOffset.UtcNow) continue;
                try
                {
                    var quota = await client.Quota(row.Account, token);
                    token.ThrowIfCancellationRequested();
                    row.Windows = quota.Windows;
                    row.Plan = quota.Plan.Length == 0 ? row.Account.Plan : quota.Plan;
                    row.Error = null;
                    row.RetryAfter = null;
                    if (Config.Notifications)
                        foreach (var window in row.Windows)
                        {
                            var threshold = ledger.Evaluate(Config.BaseUrl + "|" + row.Account.Id + "|" + window.Id,
                                window, Config.Warning, Config.Critical, DateTimeOffset.UtcNow, Config.MaxAge);
                            if (threshold.HasValue) Notify?.Invoke(threshold == Config.Critical ? "Quota critical" : "Quota warning",
                                $"{row.Account.Title}: {window.Title} {window.Remaining:0}% remaining", threshold == Config.Critical);
                            // Preserve deduplication even if a later request is cancelled or the app exits.
                            if (threshold.HasValue) SaveLedger();
                        }
                }
                catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
                catch (Exception e)
                {
                    row.Error = ApiClient.SafeMessage(e);
                    if (e is MonitorException { Status: 429 }) row.RetryAfter = DateTimeOffset.UtcNow.AddMinutes(15);
                }
                Changed?.Invoke();
            }
            try
            {
                var history = await client.History(remote, token);
                token.ThrowIfCancellationRequested();
                foreach (var row in Accounts) row.History = history.GetValueOrDefault(row.Account.Id);
                HistoryError = null;
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
            catch { HistoryError = "Usage history is unavailable."; foreach (var row in Accounts) row.History = null; }
            SaveLedger();
            LastRefresh = DateTimeOffset.Now;
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (Exception e) { if (current == generation) Error = ApiClient.SafeMessage(e); }
        finally
        {
            if (current == generation)
            {
                request = null;
                Refreshing = false;
                NextRefresh = DateTimeOffset.Now.AddSeconds(Config.Interval);
                Changed?.Invoke();
            }
        }
    }
    private void SaveLedger()
    {
        try { Storage.Save("alerts", ledger); StorageError = null; }
        catch { StorageError = "Alert history could not be saved. Notifications may repeat after restart."; }
    }
    public void Save(Configuration config, string secret, bool startup)
    {
        config = config.Validate();
        if (secret.Length > 0) Storage.WriteSecret(config.BaseUrl, secret);
        if (Storage.ReadSecret(config.BaseUrl).Length == 0) throw new MonitorException("Enter a management key for this address.");
        Storage.SetStartup(startup);
        Storage.Save("settings", config);
        Cancel();
        if (Config.BaseUrl != config.BaseUrl) { Accounts = []; LastRefresh = null; HistoryError = null; }
        Config = config;
        Error = null;
        Paused = false;
        _ = Refresh();
    }
    public void Dispose() { timer.Stop(); Cancel(); }
}
