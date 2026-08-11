using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Windows.Forms;
using SimVoiceCopilot.QA.Infrastructure;

namespace SimVoiceCopilot.QA.Diagnostics
{
    internal static class ScreenshotService
    {
        public static string CaptureProcessWindow(Process process, string outputPath)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath));

            Rectangle bounds = GetProcessBounds(process);
            if (bounds.Width <= 0 || bounds.Height <= 0)
            {
                bounds = SystemInformation.VirtualScreen;
            }

            using (Bitmap bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb))
            using (Graphics graphics = Graphics.FromImage(bitmap))
            {
                graphics.CopyFromScreen(
                    bounds.Left,
                    bounds.Top,
                    0,
                    0,
                    bounds.Size,
                    CopyPixelOperation.SourceCopy);
                bitmap.Save(outputPath, ImageFormat.Png);
            }

            return outputPath;
        }

        private static Rectangle GetProcessBounds(Process process)
        {
            try
            {
                process.Refresh();
                if (process.MainWindowHandle == IntPtr.Zero)
                {
                    return Rectangle.Empty;
                }

                NativeMethods.Rect rect;
                if (!NativeMethods.GetWindowRect(process.MainWindowHandle, out rect))
                {
                    return Rectangle.Empty;
                }

                return Rectangle.FromLTRB(rect.Left, rect.Top, rect.Right, rect.Bottom);
            }
            catch
            {
                return Rectangle.Empty;
            }
        }
    }
}
