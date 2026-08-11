using System;
using System.Runtime.InteropServices;
using System.Text;

namespace SimVoiceCopilot.QA.Infrastructure
{
    internal static class NativeMethods
    {
        internal delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        internal struct Rect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        internal static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsWindowEnabled(IntPtr hWnd);

        [DllImport("user32.dll")]
        internal static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetWindowRect(IntPtr hWnd, out Rect lpRect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll")]
        internal static extern void mouse_event(
            uint dwFlags,
            uint dx,
            uint dy,
            uint dwData,
            UIntPtr dwExtraInfo);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool PostMessage(
            IntPtr hWnd,
            uint msg,
            IntPtr wParam,
            IntPtr lParam);

        internal static string GetWindowTitle(IntPtr handle)
        {
            StringBuilder builder = new StringBuilder(1024);
            GetWindowText(handle, builder, builder.Capacity);
            return builder.ToString();
        }

        internal static string GetWindowClassName(IntPtr handle)
        {
            StringBuilder builder = new StringBuilder(512);
            GetClassName(handle, builder, builder.Capacity);
            return builder.ToString();
        }

        internal const int SwRestore = 9;
        internal const uint WmSysCommand = 0x0112;
        internal const int ScMinimize = 0xF020;
        internal const uint MouseEventLeftDown = 0x0002;
        internal const uint MouseEventLeftUp = 0x0004;
        internal const uint WmClose = 0x0010;
        internal const uint GwOwner = 4;
    }
}
