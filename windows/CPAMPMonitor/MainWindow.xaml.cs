using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Windows;
using CPAMP.MonitorCore;

namespace CPAMP.Windows;

public partial class MainWindow : Window
{
    private readonly MonitorModel model;
    internal MainWindow(MonitorModel model)
    {
        InitializeComponent();
        this.model = model;
        model.Changed += Render;
        IsVisibleChanged += (_, _) => Render();
        Closing += HideOnClose;
        Render();
    }
    private void HideOnClose(object? sender, CancelEventArgs e) { e.Cancel = true; Hide(); }
    private void Render()
    {
        ConnectionName.Text = model.Config.Name;
        Status.Text = model.Status;
        Lowest.Text = model.Lowest is double n ? $"{n:0}%" : "--";
        ErrorText.Text = string.Join("\n", new[] { model.Error, model.HistoryError, model.StorageError }.Where(s => !string.IsNullOrEmpty(s)));
        EmptyText.Text = model.Config.BaseUrl.Length == 0 ? "No connection configured." :
            model.Accounts.Count == 0 && !model.Refreshing && model.Error is null ? "No accounts returned by the service." : "";
        RefreshButton.IsEnabled = !model.Refreshing && !model.Paused && model.Config.BaseUrl.Length > 0;
        DashboardButton.IsEnabled = model.Config.BaseUrl.Length > 0;
        PauseButton.Content = model.Paused ? "\uE768" : "\uE769";
        PauseButton.ToolTip = model.Paused ? "Resume" : "Pause";
        System.Windows.Automation.AutomationProperties.SetName(PauseButton, model.Paused ? "Resume" : "Pause");
        RefreshTime.Text = $"Updated: {model.LastRefresh?.ToLocalTime().ToString("HH:mm:ss") ?? "--"}    Next: {(model.Paused ? "Paused" : model.NextRefresh?.ToLocalTime().ToString("HH:mm:ss") ?? "--")}";
        if (!IsVisible) return;
        var now = DateTimeOffset.UtcNow;
        Rows.ItemsSource = model.Accounts.Select(row => new {
            Title = row.Account.Title,
            Subtitle = string.Join(" / ", new[] { row.Account.ProviderName, row.Plan,
                row.Account.Disabled ? "Disabled on server" : row.Enabled ? "Monitored" : "Not monitored" }.Where(s => s.Length > 0)),
            Opacity = row.Enabled ? 1.0 : 0.55,
            Error = row.Error ?? "",
            History = row.History is null ? "" : $"Requests {Format(Json.Number(row.History["total_requests"]))}   Tokens {Format(Json.Number(row.History["total_tokens"]))}   Success {Format(Json.Number(row.History["success_rate"]))}%   Cost ${Json.Number(row.History["total_cost"])?.ToString("0.00") ?? "--"}",
            Windows = row.Windows.Select(w => {
                var fresh = row.Enabled && row.Error is null && model.Error is null && !model.Paused && w.Fresh(now, model.Config.MaxAge);
                return new {
                    w.Title,
                    ValueText = fresh && w.Remaining.HasValue ? $"{w.Remaining:0}% remaining" : "Unavailable",
                    Value = fresh ? w.Remaining ?? 0 : 0,
                    Color = !fresh || !w.Remaining.HasValue ? "#888888" : w.Remaining <= model.Config.Critical ? "#C52B36" : w.Remaining <= model.Config.Warning ? "#B77900" : "#269957",
                    ResetText = w.Reset is DateTimeOffset reset ? $"Reset: {reset.ToLocalTime():g}" : "Reset time unavailable"
                };
            }).ToArray()
        }).ToArray();
    }
    private static string Format(double? n) => n?.ToString("N0") ?? "--";
    private async void Refresh_Click(object sender, RoutedEventArgs e) => await model.Refresh();
    private void Settings_Click(object sender, RoutedEventArgs e) => ((App)Application.Current).ShowSettings();
    private void Pause_Click(object sender, RoutedEventArgs e) => model.TogglePause();
    private void Quit_Click(object sender, RoutedEventArgs e) => Application.Current.Shutdown();
    private void Dashboard_Click(object sender, RoutedEventArgs e)
    {
        try { Process.Start(new ProcessStartInfo(new Uri(Configuration.NormalizeUrl(model.Config.BaseUrl), "management.html").AbsoluteUri) { UseShellExecute = true }); }
        catch { MessageBox.Show(this, "Could not open the service dashboard.", "CPAMP Monitor"); }
    }
}
