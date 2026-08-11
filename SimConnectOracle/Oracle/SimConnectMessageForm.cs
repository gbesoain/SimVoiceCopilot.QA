using System;
using System.Windows.Forms;

namespace SimVoiceCopilot.QA.SimConnectOracle.Oracle
{
    /// <summary>
    /// Message-only Win32 window used by the managed SimConnect wrapper.
    /// This type deliberately has no reference to Microsoft.FlightSimulator.SimConnect,
    /// so creating its HWND cannot trigger premature SimConnect assembly loading.
    /// </summary>
    internal sealed class SimConnectMessageWindow : NativeWindow, IDisposable
    {
        public const int WmUserSimConnect = 0x0402;
        private static readonly IntPtr HwndMessage = new IntPtr(-3);
        private Action receiveMessageAction;
        private bool disposed;

        public IntPtr WindowHandle
        {
            get { return Handle; }
        }

        public Action ReceiveMessageAction
        {
            get { return receiveMessageAction; }
            set { receiveMessageAction = value; }
        }

        public SimConnectMessageWindow()
        {
            CreateParams parameters = new CreateParams
            {
                Caption = "SimVoiceCopilot QA SimConnect Oracle Message Window",
                Parent = HwndMessage,
                Style = 0,
                ExStyle = 0
            };

            CreateHandle(parameters);
            if (Handle == IntPtr.Zero)
            {
                throw new InvalidOperationException("The SimConnect message-only window could not be created.");
            }
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == WmUserSimConnect)
            {
                Action callback = receiveMessageAction;
                if (callback != null)
                {
                    callback();
                }
            }

            base.WndProc(ref message);
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            receiveMessageAction = null;

            if (Handle != IntPtr.Zero)
            {
                DestroyHandle();
            }

            GC.SuppressFinalize(this);
        }
    }
}
