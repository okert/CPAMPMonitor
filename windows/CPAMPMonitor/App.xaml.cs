using System;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Threading;
using System.Drawing;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace CPAMP.Windows;

public partial class App : Application
{
    internal MonitorModel Model { get; } = new();
    private Forms.NotifyIcon? tray;
    private Icon? icon;
    private MainWindow? dashboard;
    private SettingsWindow? settings;
    private Mutex? mutex;
    private bool ownsMutex;
    private EventWaitHandle? showEvent;
    private RegisteredWaitHandle? showWait;
    private Forms.ToolStripMenuItem? pauseItem;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (e.Args.Contains("--smoke-test"))
        {
            var folder = e.Args.LastOrDefault() ?? "smoke-results";
            Shutdown(SmokeChecks.Run(Model, folder));
            return;
        }
        showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\CPAMPMonitor.Show");
        mutex = new Mutex(true, @"Local\CPAMPMonitor.Instance", out ownsMutex);
        if (!ownsMutex) { showEvent.Set(); Shutdown(); return; }
        showWait = ThreadPool.RegisterWaitForSingleObject(showEvent, (_, _) => Dispatcher.BeginInvoke(ShowDashboard), null, -1, false);
        icon = CreateIcon();
        tray = new Forms.NotifyIcon { Icon = icon, Text = "CPAMP Monitor", Visible = true };
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open CPAMP Monitor", null, (_, _) => ShowDashboard());
        menu.Items.Add("Refresh", null, (_, _) => _ = Model.Refresh());
        pauseItem = new Forms.ToolStripMenuItem("Pause", null, (_, _) => Model.TogglePause());
        menu.Items.Add(pauseItem);
        menu.Items.Add("Settings", null, (_, _) => ShowSettings());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => Shutdown());
        tray.ContextMenuStrip = menu;
        tray.MouseClick += (_, args) => { if (args.Button == Forms.MouseButtons.Left) ShowDashboard(); };
        tray.BalloonTipClicked += (_, _) => ShowDashboard();
        Model.Notify = Notify;
        Model.Changed += UpdateTray;
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
        Model.Start();
        UpdateTray();
        if (!e.Args.Contains("--background") || Model.Config.BaseUrl.Length == 0) ShowDashboard();
        if (Model.Config.BaseUrl.Length == 0) ShowSettings();
    }
    private void UpdateTray()
    {
        if (tray is null) return;
        var text = $"CPAMP Monitor | {Model.Status} | {Model.DisplayLabel}" +
            (Model.DisplayLowest is double n ? $" {n:0}%" : " unavailable");
        tray.Text = text.Length > 63 ? text[..63] : text;
        if (pauseItem is not null) pauseItem.Text = Model.Paused ? "Resume" : "Pause";
    }
    internal void Notify(string title, string body, bool critical = false)
    {
        tray?.ShowBalloonTip(10000, title, body, critical ? Forms.ToolTipIcon.Warning : Forms.ToolTipIcon.Info);
    }
    internal void ShowDashboard()
    {
        dashboard ??= new MainWindow(Model);
        dashboard.Show(); dashboard.WindowState = WindowState.Normal; dashboard.Activate();
    }
    internal void ShowSettings()
    {
        if (settings is not null) { settings.Activate(); return; }
        settings = new SettingsWindow(Model);
        settings.Closed += (_, _) => settings = null;
        settings.Show();
    }
    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Resume) Dispatcher.BeginInvoke(() => _ = Model.Refresh());
    }
    protected override void OnExit(ExitEventArgs e)
    {
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        Model.Dispose();
        showWait?.Unregister(null);
        showEvent?.Dispose();
        tray?.Dispose(); icon?.Dispose();
        if (ownsMutex) mutex?.ReleaseMutex();
        mutex?.Dispose();
        base.OnExit(e);
    }
    private static Icon CreateIcon()
    {
        using var bitmap = new Bitmap(32, 32);
        using var g = Graphics.FromImage(bitmap);
        g.Clear(Color.Transparent);
        using var blue = new SolidBrush(Color.FromArgb(0, 120, 215));
        g.FillRectangle(blue, 3, 14, 6, 14); g.FillRectangle(blue, 13, 4, 6, 24);
        g.FillRectangle(blue, 23, 9, 6, 19);
        var handle = bitmap.GetHicon();
        try { using var borrowed = Icon.FromHandle(handle); return (Icon)borrowed.Clone(); }
        finally { DestroyIcon(handle); }
    }
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr handle);
}
