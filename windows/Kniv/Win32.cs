using System.Runtime.InteropServices;

namespace Kniv;

/// Sneltoets (RegisterHotKey) en systeemvak-icoon (Shell_NotifyIcon) op het venster van het hoofdscherm.
/// Een verborgen WinUI-venster houdt zijn HWND, dus dit blijft werken als Kniv in het systeemvak zit.
static class Win32
{
    const int WM_HOTKEY = 0x0312, WM_APP_TRAY = 0x8001, WM_LBUTTONUP = 0x0202, WM_RBUTTONUP = 0x0205, WM_CONTEXTMENU = 0x007B;
    const uint MOD_SHIFT = 0x4, MOD_WIN = 0x8, MOD_NOREPEAT = 0x4000, VK_K = 0x4B;
    const uint NIM_ADD = 0, NIM_DELETE = 2, NIF_MESSAGE = 1, NIF_ICON = 2, NIF_TIP = 4;
    const uint TPM_RETURNCMD = 0x100, TPM_RIGHTBUTTON = 0x2, MF_STRING = 0, MF_SEPARATOR = 0x800;

    delegate IntPtr SubclassProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, UIntPtr id, UIntPtr data);
    static SubclassProc? _proc;   // vasthouden, anders ruimt de GC hem op
    static IntPtr _hwnd, _icoon;
    static uint _taskbarCreated;

    public static Action? Sneltoets, Openen, Snelvenster, Afsluiten;

    public static void Start(IntPtr hwnd)
    {
        _hwnd = hwnd;
        _proc = Proc;
        SetWindowSubclass(hwnd, _proc, 1, 0);
        _taskbarCreated = RegisterWindowMessage("TaskbarCreated");
        _icoon = LoadImage(IntPtr.Zero, Path.Combine(AppContext.BaseDirectory, "kniv.ico"), 1 /*IMAGE_ICON*/,
            GetSystemMetrics(49), GetSystemMetrics(50), 0x10 /*LR_LOADFROMFILE*/);
        VoegIcoonToe();
    }

    /// Geeft false als Win+Shift+K al door iets anders bezet is.
    public static bool RegistreerSneltoets() => RegisterHotKey(_hwnd, 1, MOD_WIN | MOD_SHIFT | MOD_NOREPEAT, VK_K);

    public static void Stop()
    {
        UnregisterHotKey(_hwnd, 1);
        var d = Data();
        Shell_NotifyIcon(NIM_DELETE, ref d);
    }

    static NOTIFYICONDATA Data() => new()
    {
        cbSize = (uint)Marshal.SizeOf<NOTIFYICONDATA>(), hWnd = _hwnd, uID = 1,
        uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP, uCallbackMessage = WM_APP_TRAY, hIcon = _icoon,
        szTip = "Kniv (Win+Shift+K)",
    };

    static void VoegIcoonToe() { var d = Data(); Shell_NotifyIcon(NIM_ADD, ref d); }

    static IntPtr Proc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, UIntPtr id, UIntPtr data)
    {
        if (msg == WM_HOTKEY && wParam == 1) { Veilig(Sneltoets); return IntPtr.Zero; }
        if (msg == _taskbarCreated) VoegIcoonToe();  // Verkenner herstart: icoon terugzetten
        if (msg == WM_APP_TRAY)
        {
            var muis = (int)lParam & 0xFFFF;
            if (muis == WM_LBUTTONUP) Veilig(Openen);
            else if (muis is WM_RBUTTONUP or WM_CONTEXTMENU) Veilig(Menu);
            return IntPtr.Zero;
        }
        return DefSubclassProc(hWnd, msg, wParam, lParam);
    }

    /// Een exception die uit de WndProc ontsnapt, beëindigt het hele proces.
    static void Veilig(Action? a)
    {
        try { a?.Invoke(); } catch (Exception e) { App.Log(e); }
    }

    static void Menu()
    {
        var menu = CreatePopupMenu();
        AppendMenu(menu, MF_STRING, 1, "Openen");
        AppendMenu(menu, MF_STRING, 2, "Snelvenster\tWin+Shift+K");
        AppendMenu(menu, MF_SEPARATOR, 0, null);
        AppendMenu(menu, MF_STRING, 3, "Afsluiten");
        GetCursorPos(out var p);
        SetForegroundWindow(_hwnd);   // anders sluit het menu niet als je ernaast klikt
        var keus = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, p.X, p.Y, 0, _hwnd, IntPtr.Zero);
        DestroyMenu(menu);
        (keus switch { 1 => Openen, 2 => Snelvenster, 3 => Afsluiten, _ => null })?.Invoke();
    }

    public static void NaarVoren(IntPtr hwnd) { ShowWindow(hwnd, 9 /*SW_RESTORE*/); SetForegroundWindow(hwnd); }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct NOTIFYICONDATA
    {
        public uint cbSize; public IntPtr hWnd; public uint uID, uFlags, uCallbackMessage; public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public uint dwState, dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public uint uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public uint dwInfoFlags; public Guid guidItem; public IntPtr hBalloonIcon;
    }
    struct POINT { public int X, Y; }

    [DllImport("comctl32.dll")] static extern bool SetWindowSubclass(IntPtr h, SubclassProc p, UIntPtr id, UIntPtr data);
    [DllImport("comctl32.dll")] static extern IntPtr DefSubclassProc(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint RegisterWindowMessage(string s);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr LoadImage(IntPtr inst, string name, uint type, int cx, int cy, uint load);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern bool Shell_NotifyIcon(uint msg, ref NOTIFYICONDATA d);
    [DllImport("user32.dll")] static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool AppendMenu(IntPtr m, uint flags, UIntPtr id, string? item);
    [DllImport("user32.dll")] static extern bool DestroyMenu(IntPtr m);
    [DllImport("user32.dll")] static extern int TrackPopupMenu(IntPtr m, uint flags, int x, int y, int r, IntPtr h, IntPtr rect);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
}
