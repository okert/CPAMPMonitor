using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CPAMP.MonitorCore;

namespace CPAMP.Windows;

internal static class SmokeChecks
{
    internal static int Run(MonitorModel model, string folder)
    {
        Directory.CreateDirectory(folder);
        var credentialId = $"https://smoke-{Guid.NewGuid():N}.invalid/";
        try
        {
            Storage.WriteSecret(credentialId, "synthetic-smoke-key");
            if (Storage.ReadSecret(credentialId) != "synthetic-smoke-key") throw new InvalidOperationException("Credential round trip failed.");
            Storage.DeleteSecret(credentialId);
            if (Storage.ReadSecret(credentialId).Length != 0) throw new InvalidOperationException("Credential deletion failed.");
            var account = new Account("demo.json", "codex", "demo", "demo@example.com", "active", false, "", "", "Plus");
            model.Accounts.Add(new(account) { Enabled = true, Windows = [
                new("five-hour", "5 hours", 82, DateTimeOffset.UtcNow.AddHours(4), DateTimeOffset.UtcNow),
                new("weekly", "Weekly", 67, DateTimeOffset.UtcNow.AddDays(5), DateTimeOffset.UtcNow)] });
            var main = new MainWindow(model);
            Capture(main, Path.Combine(folder, "dashboard.png"));
            var settings = new SettingsWindow(model);
            Capture(settings, Path.Combine(folder, "settings.png"));
            settings.Close(); main.Hide();
            File.WriteAllText(Path.Combine(folder, "result.txt"),
                "PASS Credential Manager write/read/delete\nPASS WPF dashboard and settings rendering\n" +
                "Architecture: " + System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture + "\n" +
                "Interactive tray, notifications, startup and live service checks still require a real Windows session.\n");
            return 0;
        }
        catch (Exception error)
        {
            File.WriteAllText(Path.Combine(folder, "result.txt"), error.ToString());
            return 1;
        }
        finally { Storage.DeleteSecret(credentialId); }
    }
    private static void Capture(Window window, string path)
    {
        window.Show();
        window.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)window.ActualWidth, (int)window.ActualHeight, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(window);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
    }
}
