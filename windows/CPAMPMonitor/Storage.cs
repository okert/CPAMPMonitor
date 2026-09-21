using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Security.Cryptography;
using CPAMP.MonitorCore;
using Microsoft.Win32;

namespace CPAMP.Windows;

internal static class Storage
{
    private static readonly string Root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CPAMPMonitor");
    public static string? Warning { get; private set; }
    public static T Load<T>(string name) where T : new()
    {
        var path = Path.Combine(Root, name + ".json");
        if (!File.Exists(path)) return new();
        try { return JsonSerializer.Deserialize<T>(File.ReadAllText(path)) ?? new(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
        { Warning = "Saved settings could not be read. Check local storage before saving changes."; return new(); }
    }
    public static void Save<T>(string name, T value)
    {
        Directory.CreateDirectory(Root);
        var path = Path.Combine(Root, name + ".json");
        var temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temp, path, true);
    }

    public static bool StartupEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        return key?.GetValue("CPAMPMonitor") is string;
    }
    public static void SetStartup(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled)
        {
            var path = Environment.ProcessPath ?? throw new MonitorException("Application path unavailable.");
            if (!Path.GetFileName(path).Equals("CPAMPMonitor.exe", StringComparison.OrdinalIgnoreCase))
                throw new MonitorException("Run the published CPAMPMonitor.exe before enabling startup.");
            key.SetValue("CPAMPMonitor", $"\"{path}\" --background");
        }
        else key.DeleteValue("CPAMPMonitor", false);
    }

    private static string Target(string url) => "CPAMPMonitor:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(url)));

    public static string ReadSecret(string url)
    {
        if (!CredRead(Target(url), 1, 0, out var pointer))
        {
            if (Marshal.GetLastWin32Error() == 1168) return "";
            throw new MonitorException("Windows Credential Manager could not read the management key.");
        }
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(pointer);
            return Marshal.PtrToStringUni(credential.Blob, (int)credential.BlobSize / 2) ?? "";
        }
        finally { CredFree(pointer); }
    }
    public static void WriteSecret(string url, string secret)
    {
        if (Encoding.Unicode.GetByteCount(secret) > 2560) throw new MonitorException("Management key is too long for Credential Manager.");
        var pointer = Marshal.StringToCoTaskMemUni(secret);
        try
        {
            var credential = new Credential { Type = 1, Target = Target(url), Blob = pointer,
                BlobSize = (uint)Encoding.Unicode.GetByteCount(secret), Persist = 2, UserName = "CPAMPMonitor" };
            if (!CredWrite(ref credential, 0)) throw new MonitorException("Windows Credential Manager could not save the management key.");
        }
        finally { Marshal.ZeroFreeCoTaskMemUnicode(pointer); }
    }
    internal static void DeleteSecret(string url)
    {
        if (!CredDelete(Target(url), 1, 0) && Marshal.GetLastWin32Error() != 1168)
            throw new MonitorException("Windows Credential Manager could not delete the key.");
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public uint Flags, Type;
        public string Target;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint BlobSize;
        public IntPtr Blob;
        public uint Persist, AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string UserName;
    }
    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredRead(string target, uint type, int flags, out IntPtr credential);
    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredWrite(ref Credential credential, uint flags);
    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredDelete(string target, uint type, uint flags);
    [DllImport("advapi32.dll")] private static extern void CredFree(IntPtr buffer);
}
