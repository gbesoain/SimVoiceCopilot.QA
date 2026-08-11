using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Forms;
using SimVoiceCopilot.QA.Configuration;
using SimVoiceCopilot.QA.Infrastructure;

namespace SimVoiceCopilot.QA.Automation
{
    internal sealed class UiAutomationDriver
    {
        private readonly Process process;
        private readonly Logger logger;
        private AutomationElement mainWindow;

        public UiAutomationDriver(Process process, Logger logger)
        {
            this.process = process;
            this.logger = logger;
        }

        public AutomationElement WaitForMainWindow(UiSelectorConfiguration selector, TimeSpan timeout)
        {
            DateTime deadline = DateTime.Now.Add(timeout);
            Exception lastException = null;

            while (DateTime.Now < deadline)
            {
                try
                {
                    process.Refresh();
                    if (process.HasExited)
                    {
                        throw new InvalidOperationException("The application exited before its main window was ready.");
                    }

                    AutomationElement candidate = null;
                    if (process.MainWindowHandle != IntPtr.Zero)
                    {
                        candidate = AutomationElement.FromHandle(process.MainWindowHandle);
                    }

                    if (candidate == null)
                    {
                        candidate = FindTopLevelWindowByProcessId(process.Id, selector);
                    }

                    if (candidate != null)
                    {
                        mainWindow = candidate;
                        logger.Info("Main window found: " + SafeName(mainWindow));
                        return mainWindow;
                    }
                }
                catch (Exception ex)
                {
                    lastException = ex;
                }

                Thread.Sleep(250);
            }

            throw new TimeoutException(
                "The main window was not found within " + timeout.TotalSeconds.ToString("0") +
                " seconds. Last error: " + (lastException == null ? "none" : lastException.Message));
        }

        public AutomationElement FindElement(UiSelectorConfiguration selector, TimeSpan timeout)
        {
            EnsureMainWindow();
            DateTime deadline = DateTime.Now.Add(timeout);
            while (DateTime.Now < deadline)
            {
                AutomationElement result = FindElementAcrossProcess(selector);
                if (result != null)
                {
                    return result;
                }

                Thread.Sleep(200);
            }

            throw new TimeoutException("UI element not found: " + selector);
        }

        public void Activate(UiSelectorConfiguration selector, TimeSpan timeout)
        {
            AutomationElement element = FindElement(selector, timeout);
            ActivateWithModalTolerance(element, timeout);
        }

        public void Activate(AutomationElement element)
        {
            ActivateCore(element);
        }

        public string ReadValue(UiSelectorConfiguration selector, TimeSpan timeout)
        {
            AutomationElement element = FindElement(selector, timeout);
            object pattern;
            if (element.TryGetCurrentPattern(ValuePattern.Pattern, out pattern))
                return ((ValuePattern)pattern).Current.Value ?? string.Empty;

            // A WinForms Label can expose its fixed AccessibleName through UIA Name,
            // hiding the actual Text property. Read the native window text first so
            // localization and visible-state assertions validate what the user sees.
            string nativeText = TryReadNativeWindowText(element);
            if (!string.IsNullOrWhiteSpace(nativeText))
                return nativeText;

            return SafeProperty(delegate { return element.Current.Name; });
        }

        private static string TryReadNativeWindowText(AutomationElement element)
        {
            if (element == null)
                return string.Empty;

            try
            {
                int nativeHandle = element.Current.NativeWindowHandle;
                if (nativeHandle == 0)
                    return string.Empty;

                return NativeMethods.GetWindowTitle(new IntPtr(nativeHandle)) ?? string.Empty;
            }
            catch
            {
                return string.Empty;
            }
        }

        public bool IsEnabled(UiSelectorConfiguration selector, TimeSpan timeout)
        {
            AutomationElement element = FindElement(selector, timeout);
            try
            {
                return element.Current.IsEnabled;
            }
            catch
            {
                return false;
            }
        }

        public void SetTextAndCommit(
            UiSelectorConfiguration selector,
            string value,
            TimeSpan timeout)
        {
            AutomationElement element = FindElement(selector, timeout);
            string text = value ?? string.Empty;
            object pattern;

            if (element.TryGetCurrentPattern(ValuePattern.Pattern, out pattern))
            {
                ValuePattern valuePattern = (ValuePattern)pattern;
                if (valuePattern.Current.IsReadOnly)
                    throw new InvalidOperationException("The UI element is read-only: " + selector);

                valuePattern.SetValue(text);
                element.SetFocus();
                Thread.Sleep(150);
                SendKeys.SendWait("{ENTER}");
                return;
            }

            element.SetFocus();
            Thread.Sleep(100);
            SendKeys.SendWait("^a");
            SendKeys.SendWait(EscapeSendKeysText(text));
            SendKeys.SendWait("{ENTER}");
        }

        public bool WaitForValue(
            UiSelectorConfiguration selector,
            Func<string, bool> predicate,
            TimeSpan timeout)
        {
            if (predicate == null)
                throw new ArgumentNullException("predicate");

            DateTime deadline = DateTime.UtcNow.Add(timeout);
            while (DateTime.UtcNow < deadline)
            {
                try
                {
                    string value = ReadValue(selector, TimeSpan.FromMilliseconds(750));
                    if (predicate(value ?? string.Empty))
                        return true;
                }
                catch
                {
                    // The control may be temporarily replaced while the checklist view changes.
                }

                Thread.Sleep(150);
            }

            return false;
        }

        private static string EscapeSendKeysText(string value)
        {
            if (string.IsNullOrEmpty(value))
                return string.Empty;

            return value
                .Replace("{", "{{}")
                .Replace("}", "{}}")
                .Replace("+", "{+}")
                .Replace("^", "{^}")
                .Replace("%", "{%}")
                .Replace("~", "{~}")
                .Replace("(", "{(}")
                .Replace(")", "{)}")
                .Replace("[", "{[}")
                .Replace("]", "{]}");
        }

        private void ActivateWithModalTolerance(AutomationElement element, TimeSpan timeout)
        {
            Exception activationError = null;
            ManualResetEvent completed = new ManualResetEvent(false);

            Thread activationThread = new Thread(delegate()
            {
                try
                {
                    ActivateCore(element);
                }
                catch (Exception ex)
                {
                    activationError = ex;
                }
                finally
                {
                    completed.Set();
                }
            });

            activationThread.IsBackground = true;
            activationThread.Name = "SimVoiceCopilot.QA.UiActivation";
            activationThread.SetApartmentState(ApartmentState.STA);
            activationThread.Start();

            int waitMs = (int)Math.Min(Math.Max(500, timeout.TotalMilliseconds), 2000);
            bool finished = completed.WaitOne(waitMs);
            if (finished)
            {
                completed.Dispose();
                if (activationError != null)
                {
                    throw new InvalidOperationException("UI element activation failed.", activationError);
                }

                return;
            }

            logger.Warn(
                "UI activation did not return within " + waitMs +
                " ms. Continuing because the control may have opened a modal WinForms window.");
        }

        private void ActivateCore(AutomationElement element)
        {
            if (element == null)
            {
                throw new ArgumentNullException("element");
            }

            try
            {
                object pattern;

                if (element.TryGetCurrentPattern(InvokePattern.Pattern, out pattern))
                {
                    ((InvokePattern)pattern).Invoke();
                    return;
                }

                if (element.TryGetCurrentPattern(SelectionItemPattern.Pattern, out pattern))
                {
                    ((SelectionItemPattern)pattern).Select();
                    return;
                }

                if (element.TryGetCurrentPattern(TogglePattern.Pattern, out pattern))
                {
                    ((TogglePattern)pattern).Toggle();
                    return;
                }

                if (element.TryGetCurrentPattern(ExpandCollapsePattern.Pattern, out pattern))
                {
                    ExpandCollapsePattern expand = (ExpandCollapsePattern)pattern;
                    if (expand.Current.ExpandCollapseState == ExpandCollapseState.Collapsed)
                    {
                        expand.Expand();
                    }
                    return;
                }

                if (TryNativeClick(element))
                {
                    return;
                }

                element.SetFocus();
                Thread.Sleep(100);
                SendKeys.SendWait("{ENTER}");
            }
            catch (ElementNotAvailableException ex)
            {
                throw new InvalidOperationException("The UI element became unavailable before activation.", ex);
            }
        }

        public HashSet<IntPtr> SnapshotVisibleProcessWindows()
        {
            return new HashSet<IntPtr>(FindVisibleProcessWindowHandles());
        }

        public IntPtr WaitForSecondaryWindow(HashSet<IntPtr> baselineHandles, TimeSpan timeout)
        {
            EnsureMainWindow();
            DateTime deadline = DateTime.Now.Add(timeout);

            while (DateTime.Now < deadline)
            {
                IntPtr secondary = FindSecondaryWindowHandle(baselineHandles);
                if (secondary != IntPtr.Zero)
                {
                    logger.Info("Secondary window found through Win32 enumeration: " + DescribeWindowHandle(secondary));
                    return secondary;
                }

                Thread.Sleep(150);
            }

            throw new TimeoutException(
                "No new visible top-level window belonging to process PID " + process.Id +
                " appeared within " + timeout.TotalSeconds.ToString("0") + " seconds. " +
                "Current process windows: " + DescribeProcessWindows());
        }

        public int CloseSecondaryWindow(IntPtr windowHandle, TimeSpan timeout)
        {
            EnsureMainWindow();
            if (windowHandle == IntPtr.Zero)
            {
                return 0;
            }

            logger.Info("Closing secondary window: " + DescribeWindowHandle(windowHandle));
            DateTime deadline = DateTime.Now.Add(timeout);

            if (TryPostClose(windowHandle) &&
                WaitForWindowClosed(windowHandle, Remaining(deadline, TimeSpan.FromSeconds(3))))
            {
                CompleteSecondaryWindowClose(timeout);
                return 1;
            }

            if (TryWindowPatternClose(windowHandle) &&
                WaitForWindowClosed(windowHandle, Remaining(deadline, TimeSpan.FromSeconds(3))))
            {
                CompleteSecondaryWindowClose(timeout);
                return 1;
            }

            if (TryTitleBarClose(windowHandle) &&
                WaitForWindowClosed(windowHandle, Remaining(deadline, TimeSpan.FromSeconds(2))))
            {
                CompleteSecondaryWindowClose(timeout);
                return 1;
            }

            if (TryEscapeClose(windowHandle) &&
                WaitForWindowClosed(windowHandle, Remaining(deadline, TimeSpan.FromSeconds(2))))
            {
                CompleteSecondaryWindowClose(timeout);
                return 1;
            }

            throw new TimeoutException(
                "Secondary window did not close within " + timeout.TotalSeconds.ToString("0") +
                " seconds: " + DescribeWindowHandle(windowHandle));
        }

        public int CloseSecondaryWindows(TimeSpan timeout)
        {
            EnsureMainWindow();
            List<IntPtr> handles = FindSecondaryWindowHandles(null);
            int closed = 0;

            foreach (IntPtr handle in handles)
            {
                closed += CloseSecondaryWindow(handle, timeout);
            }

            return closed;
        }

        private void CompleteSecondaryWindowClose(TimeSpan timeout)
        {
            WaitForMainWindowEnabled(timeout);
            logger.Info("Secondary window closed successfully and the main window is enabled.");
        }

        private bool TryPostClose(IntPtr windowHandle)
        {
            try
            {
                bool posted = NativeMethods.PostMessage(
                    windowHandle,
                    NativeMethods.WmClose,
                    IntPtr.Zero,
                    IntPtr.Zero);

                if (posted)
                {
                    logger.Info("Posted WM_CLOSE to secondary window.");
                }

                return posted;
            }
            catch (Exception ex)
            {
                logger.Warn("WM_CLOSE failed: " + ex.Message);
                return false;
            }
        }

        private bool TryWindowPatternClose(IntPtr windowHandle)
        {
            try
            {
                AutomationElement window = AutomationElement.FromHandle(windowHandle);
                object pattern;
                if (window != null && window.TryGetCurrentPattern(WindowPattern.Pattern, out pattern))
                {
                    ((WindowPattern)pattern).Close();
                    logger.Info("Requested close through WindowPattern.");
                    return true;
                }
            }
            catch (Exception ex)
            {
                logger.Warn("WindowPattern.Close failed: " + ex.Message);
            }

            return false;
        }

        private bool TryTitleBarClose(IntPtr windowHandle)
        {
            try
            {
                AutomationElement window = AutomationElement.FromHandle(windowHandle);
                if (window == null)
                {
                    return false;
                }

                AutomationElement closeButton = window.FindFirst(
                    TreeScope.Descendants,
                    new PropertyCondition(
                        AutomationElement.AutomationIdProperty,
                        "Close"));

                if (closeButton == null)
                {
                    return false;
                }

                ActivateCore(closeButton);
                logger.Info("Activated the title-bar Close control.");
                return true;
            }
            catch (Exception ex)
            {
                logger.Warn("Close control fallback failed: " + ex.Message);
                return false;
            }
        }

        private bool TryEscapeClose(IntPtr windowHandle)
        {
            try
            {
                NativeMethods.ShowWindowAsync(windowHandle, NativeMethods.SwRestore);
                NativeMethods.SetForegroundWindow(windowHandle);
                Thread.Sleep(100);
                SendKeys.SendWait("{ESC}");
                logger.Info("Sent ESC to secondary window.");
                return true;
            }
            catch (Exception ex)
            {
                logger.Warn("ESC fallback failed: " + ex.Message);
                return false;
            }
        }

        private static TimeSpan Remaining(DateTime deadline, TimeSpan maximum)
        {
            TimeSpan remaining = deadline - DateTime.Now;
            if (remaining <= TimeSpan.Zero)
            {
                return TimeSpan.FromMilliseconds(1);
            }

            return remaining < maximum ? remaining : maximum;
        }

        private bool WaitForWindowClosed(IntPtr windowHandle, TimeSpan timeout)
        {
            DateTime deadline = DateTime.Now.Add(timeout);
            while (DateTime.Now < deadline)
            {
                if (!NativeMethods.IsWindow(windowHandle) || !NativeMethods.IsWindowVisible(windowHandle))
                {
                    return true;
                }

                Thread.Sleep(150);
            }

            return !NativeMethods.IsWindow(windowHandle) || !NativeMethods.IsWindowVisible(windowHandle);
        }

        private void WaitForMainWindowEnabled(TimeSpan timeout)
        {
            int rawMainHandle = SafeInt(delegate { return mainWindow.Current.NativeWindowHandle; });
            IntPtr mainHandle = new IntPtr(rawMainHandle);
            if (mainHandle == IntPtr.Zero)
            {
                return;
            }

            DateTime deadline = DateTime.Now.Add(timeout);
            while (DateTime.Now < deadline)
            {
                if (NativeMethods.IsWindow(mainHandle) && NativeMethods.IsWindowEnabled(mainHandle))
                {
                    NativeMethods.ShowWindowAsync(mainHandle, NativeMethods.SwRestore);
                    NativeMethods.SetForegroundWindow(mainHandle);
                    return;
                }

                Thread.Sleep(100);
            }

            throw new TimeoutException("The main window did not become enabled after closing the modal window.");
        }

        private bool TryNativeClick(AutomationElement element)
        {
            try
            {
                string descriptionBeforeClick = Describe(element);
                System.Windows.Point point;
                try
                {
                    point = element.GetClickablePoint();
                }
                catch
                {
                    System.Windows.Rect rectangle = element.Current.BoundingRectangle;
                    if (rectangle.IsEmpty || rectangle.Width <= 1 || rectangle.Height <= 1)
                    {
                        return false;
                    }

                    point = new System.Windows.Point(
                        rectangle.Left + (rectangle.Width / 2.0),
                        rectangle.Top + (rectangle.Height / 2.0));
                }

                IntPtr mainHandle = new IntPtr(
                    SafeInt(delegate { return mainWindow.Current.NativeWindowHandle; }));
                if (mainHandle != IntPtr.Zero)
                {
                    NativeMethods.ShowWindowAsync(mainHandle, NativeMethods.SwRestore);
                    NativeMethods.SetForegroundWindow(mainHandle);
                }

                int x = Convert.ToInt32(Math.Round(point.X));
                int y = Convert.ToInt32(Math.Round(point.Y));
                if (!NativeMethods.SetCursorPos(x, y))
                {
                    return false;
                }

                Thread.Sleep(75);
                NativeMethods.mouse_event(
                    NativeMethods.MouseEventLeftDown,
                    0,
                    0,
                    0,
                    UIntPtr.Zero);
                Thread.Sleep(50);
                NativeMethods.mouse_event(
                    NativeMethods.MouseEventLeftUp,
                    0,
                    0,
                    0,
                    UIntPtr.Zero);

                logger.Info(
                    "Activated UI element with native mouse click: " +
                    descriptionBeforeClick);
                return true;
            }
            catch (Exception ex)
            {
                logger.Warn("Native mouse click fallback failed: " + ex.Message);
                return false;
            }
        }

        private IntPtr FindSecondaryWindowHandle(HashSet<IntPtr> baselineHandles)
        {
            List<IntPtr> handles = FindSecondaryWindowHandles(baselineHandles);
            return handles.Count == 0 ? IntPtr.Zero : handles[0];
        }

        private List<IntPtr> FindSecondaryWindowHandles(HashSet<IntPtr> baselineHandles)
        {
            List<IntPtr> result = new List<IntPtr>();
            int rawMainHandle = SafeInt(delegate { return mainWindow.Current.NativeWindowHandle; });
            IntPtr mainHandle = new IntPtr(rawMainHandle);

            foreach (IntPtr handle in FindVisibleProcessWindowHandles())
            {
                if (handle == IntPtr.Zero || handle == mainHandle)
                {
                    continue;
                }

                if (baselineHandles != null && baselineHandles.Contains(handle))
                {
                    continue;
                }

                result.Add(handle);
            }

            if (result.Count == 0 && baselineHandles != null)
            {
                // Fallback for a form that existed hidden and was made visible by ShowDialog().
                // Only accept windows owned by the main form to avoid mistaking helper windows for dialogs.
                foreach (IntPtr handle in FindVisibleProcessWindowHandles())
                {
                    if (handle != IntPtr.Zero &&
                        handle != mainHandle &&
                        NativeMethods.GetWindow(handle, NativeMethods.GwOwner) == mainHandle)
                    {
                        result.Add(handle);
                    }
                }
            }

            return result;
        }

        private List<IntPtr> FindVisibleProcessWindowHandles()
        {
            List<IntPtr> result = new List<IntPtr>();

            NativeMethods.EnumWindows(delegate(IntPtr handle, IntPtr parameter)
            {
                uint windowProcessId;
                NativeMethods.GetWindowThreadProcessId(handle, out windowProcessId);
                if (windowProcessId != (uint)process.Id)
                {
                    return true;
                }

                if (!NativeMethods.IsWindowVisible(handle))
                {
                    return true;
                }

                NativeMethods.Rect rectangle;
                if (NativeMethods.GetWindowRect(handle, out rectangle))
                {
                    int width = rectangle.Right - rectangle.Left;
                    int height = rectangle.Bottom - rectangle.Top;
                    if (width <= 1 || height <= 1)
                    {
                        return true;
                    }
                }

                result.Add(handle);
                return true;
            }, IntPtr.Zero);

            return result;
        }

        private string DescribeProcessWindows()
        {
            List<IntPtr> handles = FindVisibleProcessWindowHandles();
            if (handles.Count == 0)
            {
                return "none";
            }

            StringBuilder builder = new StringBuilder();
            for (int i = 0; i < handles.Count; i++)
            {
                if (i > 0)
                {
                    builder.Append(" | ");
                }

                builder.Append(DescribeWindowHandle(handles[i]));
            }

            return builder.ToString();
        }

        private static string DescribeWindowHandle(IntPtr handle)
        {
            if (handle == IntPtr.Zero)
            {
                return "HWND=0";
            }

            string title = NativeMethods.GetWindowTitle(handle);
            string className = NativeMethods.GetWindowClassName(handle);
            IntPtr owner = NativeMethods.GetWindow(handle, NativeMethods.GwOwner);

            return string.Format(
                CultureInfo.InvariantCulture,
                "HWND=0x{0:X}, Title='{1}', Class='{2}', Visible={3}, Enabled={4}, Owner=0x{5:X}",
                handle.ToInt64(),
                title,
                className,
                NativeMethods.IsWindowVisible(handle),
                NativeMethods.IsWindowEnabled(handle),
                owner.ToInt64());
        }

        public bool Exists(UiSelectorConfiguration selector, TimeSpan timeout)
        {
            try
            {
                return FindElement(selector, timeout) != null;
            }
            catch
            {
                return false;
            }
        }

        public string DumpTree(string outputPath, int maxDepth, int maxElements)
        {
            EnsureMainWindow();
            StringBuilder builder = new StringBuilder();
            int count = 0;
            DumpElement(mainWindow, builder, 0, maxDepth, maxElements, ref count);
            File.WriteAllText(outputPath, builder.ToString(), Encoding.UTF8);
            return outputPath;
        }

        public string Describe(AutomationElement element)
        {
            if (element == null)
            {
                return "(null)";
            }

            return string.Format(
                CultureInfo.InvariantCulture,
                "Name='{0}', AutomationId='{1}', ControlType='{2}', Enabled={3}, Offscreen={4}",
                SafeProperty(delegate { return element.Current.Name; }),
                SafeProperty(delegate { return element.Current.AutomationId; }),
                SafeProperty(delegate { return element.Current.ControlType.ProgrammaticName; }),
                SafeBool(delegate { return element.Current.IsEnabled; }),
                SafeBool(delegate { return element.Current.IsOffscreen; }));
        }

        private AutomationElement FindTopLevelWindowByProcessId(int processId, UiSelectorConfiguration selector)
        {
            Condition processCondition = new PropertyCondition(AutomationElement.ProcessIdProperty, processId);
            AutomationElementCollection windows = AutomationElement.RootElement.FindAll(TreeScope.Children, processCondition);
            for (int i = 0; i < windows.Count; i++)
            {
                AutomationElement window = windows[i];
                if (Matches(window, selector))
                {
                    return window;
                }
            }

            return windows.Count > 0 ? windows[0] : null;
        }

        private AutomationElement FindElementAcrossProcess(UiSelectorConfiguration selector)
        {
            AutomationElement result = FindElementOnce(mainWindow, selector);
            if (result != null)
            {
                return result;
            }

            Condition processCondition = new PropertyCondition(AutomationElement.ProcessIdProperty, process.Id);
            AutomationElementCollection windows = AutomationElement.RootElement.FindAll(
                TreeScope.Children,
                processCondition);

            for (int i = 0; i < windows.Count; i++)
            {
                AutomationElement window = windows[i];
                if (Matches(window, selector))
                {
                    return window;
                }

                if (!AutomationElement.Equals(window, mainWindow))
                {
                    result = FindElementOnce(window, selector);
                    if (result != null)
                    {
                        return result;
                    }
                }
            }

            return null;
        }

        private AutomationElement FindElementOnce(AutomationElement root, UiSelectorConfiguration selector)
        {
            if (root == null || selector == null || selector.IsEmpty())
            {
                return null;
            }

            ControlType expectedType = ResolveControlType(selector.ControlType);

            if (!string.IsNullOrWhiteSpace(selector.AutomationId))
            {
                Condition condition = new PropertyCondition(
                    AutomationElement.AutomationIdProperty,
                    selector.AutomationId.Trim());

                AutomationElement byId = root.FindFirst(TreeScope.Descendants, condition);
                if (byId != null && MatchesControlType(byId, expectedType))
                {
                    return byId;
                }
            }

            foreach (string name in SplitNames(selector.Names))
            {
                Condition condition = new PropertyCondition(AutomationElement.NameProperty, name);
                AutomationElement byName = root.FindFirst(TreeScope.Descendants, condition);
                if (byName != null && MatchesControlType(byName, expectedType))
                {
                    return byName;
                }
            }

            return null;
        }

        private static bool Matches(AutomationElement element, UiSelectorConfiguration selector)
        {
            if (selector == null || selector.IsEmpty())
            {
                return true;
            }

            ControlType expectedType = ResolveControlType(selector.ControlType);
            if (!MatchesControlType(element, expectedType))
            {
                return false;
            }

            string automationId = SafeProperty(delegate { return element.Current.AutomationId; });
            if (!string.IsNullOrWhiteSpace(selector.AutomationId) &&
                string.Equals(automationId, selector.AutomationId.Trim(), StringComparison.Ordinal))
            {
                return true;
            }

            string currentName = SafeName(element);
            foreach (string name in SplitNames(selector.Names))
            {
                if (string.Equals(currentName, name, StringComparison.CurrentCulture))
                {
                    return true;
                }
            }

            return string.IsNullOrWhiteSpace(selector.AutomationId) &&
                   string.IsNullOrWhiteSpace(selector.Names);
        }

        private static bool MatchesControlType(AutomationElement element, ControlType expectedType)
        {
            if (expectedType == null)
            {
                return true;
            }

            try
            {
                return element.Current.ControlType == expectedType;
            }
            catch
            {
                return false;
            }
        }

        private static ControlType ResolveControlType(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return null;
            }

            switch (value.Trim().ToLowerInvariant())
            {
                case "button": return ControlType.Button;
                case "calendar": return ControlType.Calendar;
                case "checkbox": return ControlType.CheckBox;
                case "combobox": return ControlType.ComboBox;
                case "custom": return ControlType.Custom;
                case "datagrid": return ControlType.DataGrid;
                case "dataitem": return ControlType.DataItem;
                case "document": return ControlType.Document;
                case "edit": return ControlType.Edit;
                case "group": return ControlType.Group;
                case "header": return ControlType.Header;
                case "headeritem": return ControlType.HeaderItem;
                case "hyperlink": return ControlType.Hyperlink;
                case "image": return ControlType.Image;
                case "list": return ControlType.List;
                case "listitem": return ControlType.ListItem;
                case "menu": return ControlType.Menu;
                case "menubar": return ControlType.MenuBar;
                case "menuitem": return ControlType.MenuItem;
                case "pane": return ControlType.Pane;
                case "progressbar": return ControlType.ProgressBar;
                case "radiobutton": return ControlType.RadioButton;
                case "scrollbar": return ControlType.ScrollBar;
                case "separator": return ControlType.Separator;
                case "slider": return ControlType.Slider;
                case "spinner": return ControlType.Spinner;
                case "splitbutton": return ControlType.SplitButton;
                case "statusbar": return ControlType.StatusBar;
                case "tab": return ControlType.Tab;
                case "tabitem": return ControlType.TabItem;
                case "table": return ControlType.Table;
                case "text": return ControlType.Text;
                case "thumb": return ControlType.Thumb;
                case "titlebar": return ControlType.TitleBar;
                case "toolbar": return ControlType.ToolBar;
                case "tree": return ControlType.Tree;
                case "treeitem": return ControlType.TreeItem;
                case "window": return ControlType.Window;
                default:
                    throw new InvalidOperationException("Unsupported UI Automation control type: " + value);
            }
        }

        private static IEnumerable<string> SplitNames(string names)
        {
            if (string.IsNullOrWhiteSpace(names))
            {
                yield break;
            }

            string[] parts = names.Split(new[] { '|' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (string part in parts)
            {
                string trimmed = part.Trim();
                if (trimmed.Length > 0)
                {
                    yield return trimmed;
                }
            }
        }

        private static void DumpElement(
            AutomationElement element,
            StringBuilder builder,
            int depth,
            int maxDepth,
            int maxElements,
            ref int count)
        {
            if (element == null || count >= maxElements || depth > maxDepth)
            {
                return;
            }

            count++;
            builder.Append(new string(' ', depth * 2));
            builder.AppendLine(string.Format(
                CultureInfo.InvariantCulture,
                "[{0}] Name=\"{1}\" AutomationId=\"{2}\" Class=\"{3}\" Enabled={4} Offscreen={5}",
                SafeProperty(delegate { return element.Current.ControlType.ProgrammaticName; }),
                Escape(SafeProperty(delegate { return element.Current.Name; })),
                Escape(SafeProperty(delegate { return element.Current.AutomationId; })),
                Escape(SafeProperty(delegate { return element.Current.ClassName; })),
                SafeBool(delegate { return element.Current.IsEnabled; }),
                SafeBool(delegate { return element.Current.IsOffscreen; })));

            if (depth >= maxDepth)
            {
                return;
            }

            AutomationElement child = null;
            try
            {
                child = TreeWalker.RawViewWalker.GetFirstChild(element);
            }
            catch
            {
                return;
            }

            while (child != null && count < maxElements)
            {
                DumpElement(child, builder, depth + 1, maxDepth, maxElements, ref count);
                try
                {
                    child = TreeWalker.RawViewWalker.GetNextSibling(child);
                }
                catch
                {
                    break;
                }
            }
        }

        private void EnsureMainWindow()
        {
            if (mainWindow == null)
            {
                throw new InvalidOperationException("The main window has not been initialized.");
            }
        }

        private static string SafeName(AutomationElement element)
        {
            return SafeProperty(delegate { return element.Current.Name; });
        }

        private static string SafeProperty(Func<string> getter)
        {
            try
            {
                return getter() ?? string.Empty;
            }
            catch
            {
                return "<unavailable>";
            }
        }

        private static int SafeInt(Func<int> getter)
        {
            try
            {
                return getter();
            }
            catch
            {
                return 0;
            }
        }

        private static bool SafeBoolValue(Func<bool> getter)
        {
            try
            {
                return getter();
            }
            catch
            {
                return false;
            }
        }

        private static string SafeBool(Func<bool> getter)
        {
            try
            {
                return getter().ToString();
            }
            catch
            {
                return "<unavailable>";
            }
        }

        private static string Escape(string value)
        {
            return (value ?? string.Empty).Replace("\r", " ").Replace("\n", " ").Replace("\"", "'");
        }
    }
}
