using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using CPAMP.MonitorCore;

namespace CPAMP.Windows;

public sealed class AccountChoice
{
    public required string Id { get; init; }
    public required string Title { get; init; }
    public required string Provider { get; init; }
    public bool Available { get; init; }
    public bool Enabled { get; set; }
}
public sealed class DisplayChoice
{
    public required string Id { get; init; }
    public required string Title { get; init; }
}
public partial class SettingsWindow : Window
{
    private readonly MonitorModel model;
    private readonly ObservableCollection<AccountChoice> choices = [];
    private readonly ObservableCollection<DisplayChoice> displayChoices = [];
    private string displayAccountId = "";
    private bool syncingDisplay;
    internal SettingsWindow(MonitorModel model)
    {
        InitializeComponent();
        this.model = model;
        var c = model.Config;
        displayAccountId = c.DisplayAccountId ?? "";
        ConnectionName.Text = c.Name; ServiceUrl.Text = c.BaseUrl;
        Interval.Text = (c.Interval / 60).ToString(); Warning.Text = c.Warning.ToString(); Critical.Text = c.Critical.ToString();
        Notifications.IsChecked = c.Notifications;
        try { Startup.IsChecked = Storage.StartupEnabled(); } catch { Message.Text = "Startup preference could not be read."; }
        Accounts.ItemsSource = choices;
        DisplayAccount.ItemsSource = displayChoices;
        SyncAccounts();
        model.Changed += SyncAccounts;
        Closed += (_, _) => model.Changed -= SyncAccounts;
    }
    private void SyncAccounts()
    {
        foreach (var row in model.Accounts)
            if (!choices.Any(c => c.Id == row.Account.Id)) choices.Add(new() {
                Id = row.Account.Id, Title = row.Account.Title,
                Provider = row.Account.ProviderName + (row.Account.Disabled ? " / Disabled on server" : ""),
                Available = !row.Account.Disabled, Enabled = row.Enabled });
        syncingDisplay = true;
        try
        {
            displayChoices.Clear();
            displayChoices.Add(new() { Id = "", Title = "All monitored accounts (minimum)" });
            foreach (var choice in choices)
                displayChoices.Add(new() { Id = choice.Id, Title = choice.Title + " (minimum)" });
            if (!string.IsNullOrEmpty(displayAccountId) && !displayChoices.Any(c => c.Id == displayAccountId))
                displayChoices.Add(new() { Id = displayAccountId, Title = "Selected account (currently unavailable)" });
            DisplayAccount.SelectedValue = displayAccountId;
        }
        finally { syncingDisplay = false; }
    }
    private void DisplayAccount_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!syncingDisplay && DisplayAccount.SelectedValue is string id) displayAccountId = id;
    }
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (!int.TryParse(Interval.Text, out var minutes) || !int.TryParse(Warning.Text, out var warning) ||
                !int.TryParse(Critical.Text, out var critical)) throw new MonitorException("Enter whole numbers for refresh and thresholds.");
            var excluded = model.Config.Excluded.ToHashSet();
            foreach (var choice in choices.Where(c => c.Available))
                if (choice.Enabled) excluded.Remove(choice.Id); else excluded.Add(choice.Id);
            var config = model.Config with { BaseUrl = ServiceUrl.Text, Name = ConnectionName.Text,
                Interval = checked(minutes * 60), Warning = warning, Critical = critical,
                Notifications = Notifications.IsChecked == true, Excluded = excluded,
                AccountOrder = choices.Select(c => c.Id).ToList(),
                DisplayAccountId = string.IsNullOrEmpty(displayAccountId) ? null : displayAccountId };
            model.Save(config, Secret.Password, Startup.IsChecked == true);
            Secret.Clear(); Close();
        }
        catch (Exception error) { Message.Text = ApiClient.SafeMessage(error); }
    }
    private void Move(int offset)
    {
        var index = Accounts.SelectedIndex;
        if (index < 0 || index + offset < 0 || index + offset >= choices.Count) return;
        choices.Move(index, index + offset); Accounts.SelectedIndex = index + offset;
    }
    private void Up_Click(object sender, RoutedEventArgs e) => Move(-1);
    private void Down_Click(object sender, RoutedEventArgs e) => Move(1);
    private void Test_Click(object sender, RoutedEventArgs e)
    {
        ((App)Application.Current).Notify("CPAMP Monitor", "Test notification. This is not a quota alert.");
        Message.Text = "Notification submitted to Windows. Visibility depends on system notification settings.";
    }
    private void Cancel_Click(object sender, RoutedEventArgs e) => Close();
}
