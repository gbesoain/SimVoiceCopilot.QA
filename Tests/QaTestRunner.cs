using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Automation;
using SimVoiceCopilot.QA.Automation;
using SimVoiceCopilot.QA.Configuration;
using SimVoiceCopilot.QA.Diagnostics;
using SimVoiceCopilot.QA.Infrastructure;
using SimVoiceCopilot.QA.Reporting;
using SimVoiceCopilot.QA.VoiceChecklists;

namespace SimVoiceCopilot.QA.Tests
{
    internal sealed class QaTestRunner
    {
        private readonly QaConfiguration configuration;
        private readonly QaReport report;
        private readonly string outputRoot;
        private readonly Logger logger;
        private readonly string screenshotsDirectory;
        private readonly ApplicationController applicationController;
        private Process process;
        private UiAutomationDriver ui;
        private ProcessMonitor monitor;
        private int screenshotSequence;

        public QaTestRunner(
            QaConfiguration configuration,
            QaReport report,
            string outputRoot,
            Logger logger)
        {
            this.configuration = configuration;
            this.report = report;
            this.outputRoot = outputRoot;
            this.logger = logger;
            screenshotsDirectory = Path.Combine(outputRoot, "screenshots");
            Directory.CreateDirectory(screenshotsDirectory);
            applicationController = new ApplicationController(configuration.Application, logger);
        }

        public bool Run(bool diagnoseUiOnly)
        {
            bool startupPassed = RunStartup();
            if (!startupPassed)
            {
                if (configuration.Execution.CloseApplicationAtEnd && process != null)
                {
                    applicationController.RequestShutdown(process);
                }

                Cleanup();
                return false;
            }

            if (diagnoseUiOnly)
            {
                RunUiDiagnosticOnly();
                Cleanup();
                return report.Tests.All(t => t.Passed || t.Skipped);
            }

            RunStartupActions();
            RunSingleInstanceRestoreRegression();
            RunVoiceChecklistSuite();
            RunNavigationSmoke();
            RunNavigationStress();
            EvaluateResourceGrowth();
            RunShutdown();
            Cleanup();

            return report.Tests.All(t => t.Passed || t.Skipped);
        }

        private bool RunStartup()
        {
            TestCaseResult test = BeginTest("Application startup");
            try
            {
                process = applicationController.StartOrAttach();
                report.ApplicationProcessId = process.Id;
                report.ApplicationVersion = GetApplicationVersion(process);

                monitor = new ProcessMonitor(
                    process,
                    configuration.Execution.MetricsIntervalMs,
                    report.Metrics,
                    logger);
                monitor.Start();

                ui = new UiAutomationDriver(process, logger);
                AutomationElement window = ui.WaitForMainWindow(
                    configuration.MainWindow,
                    TimeSpan.FromSeconds(configuration.Application.StartupTimeoutSeconds));

                AddStep(test, "Locate main window", null, true, ui.Describe(window), null);

                if (!CheckResponsive())
                {
                    throw new InvalidOperationException("The application process is not responding after startup.");
                }

                AddStep(test, "Verify initial responsiveness", null, true, "Process.Responding is true.", null);

                if (configuration.Execution.DumpUiTreeAtStartup)
                {
                    string treePath = Path.Combine(outputRoot, "ui-tree.txt");
                    ui.DumpTree(treePath, 8, 1500);
                    AddStep(test, "Dump UI Automation tree", null, true, treePath, null);
                }

                string startupScreenshot = CaptureScreenshot("startup");
                AddStep(test, "Capture startup evidence", null, true, startupScreenshot, startupScreenshot);

                EndTest(test, true, "Application started and exposed a responsive main window.", null);
                return true;
            }
            catch (Exception ex)
            {
                string screenshot = CaptureScreenshotSafe("startup-failure");
                AddStep(test, "Application startup", null, false, null, screenshot, ex);
                EndTest(test, false, "Application startup failed.", ex);
                return false;
            }
        }

        private void RunUiDiagnosticOnly()
        {
            TestCaseResult test = BeginTest("UI Automation diagnostic");
            try
            {
                string treePath = Path.Combine(outputRoot, "ui-tree-diagnostic.txt");
                ui.DumpTree(treePath, 12, 5000);
                string screenshot = CaptureScreenshot("ui-diagnostic");
                AddStep(test, "Export complete UI tree", null, true, treePath, screenshot);
                EndTest(test, true, "UI tree exported. Use it to configure stable AutomationId or Name selectors.", null);
            }
            catch (Exception ex)
            {
                AddStep(test, "Export complete UI tree", null, false, null, CaptureScreenshotSafe("ui-diagnostic-failure"), ex);
                EndTest(test, false, "UI diagnostic failed.", ex);
            }
        }

        private void RunStartupActions()
        {
            TestCaseResult test = BeginTest("Startup actions");
            if (configuration.StartupActions == null || configuration.StartupActions.Count == 0)
            {
                test.Skipped = true;
                EndTest(test, false, "No startup actions are configured.", null);
                return;
            }

            bool allPassed = true;
            foreach (NavigationActionConfiguration action in configuration.StartupActions)
            {
                bool passed = ExecuteAction(test, action, null, "Startup");
                allPassed &= passed;
                if (!passed)
                {
                    break;
                }
            }

            EndTest(
                test,
                allPassed,
                allPassed ? "All configured startup actions completed." : "One or more startup actions failed.",
                null);
        }

        private void RunSingleInstanceRestoreRegression()
        {
            TestCaseResult test = BeginTest("Tray and single-instance restore regression");
            if (!configuration.Execution.TestSingleInstanceRestore)
            {
                test.Skipped = true;
                EndTest(test, false, "Single-instance restoration test was disabled by configuration.", null);
                return;
            }

            if (string.Equals(configuration.Application.LaunchMode, "AttachOnly", StringComparison.OrdinalIgnoreCase))
            {
                test.Skipped = true;
                EndTest(test, false, "AttachOnly mode cannot launch the app again to test restoration.", null);
                return;
            }

            try
            {
                process.Refresh();
                IntPtr originalHandle = process.MainWindowHandle;
                if (originalHandle == IntPtr.Zero || !NativeMethods.IsWindow(originalHandle))
                    throw new InvalidOperationException("The main window handle was unavailable before the restore regression.");

                bool minimizePosted = NativeMethods.PostMessage(
                    originalHandle,
                    NativeMethods.WmSysCommand,
                    new IntPtr(NativeMethods.ScMinimize),
                    IntPtr.Zero);
                if (!minimizePosted)
                    throw new InvalidOperationException("WM_SYSCOMMAND/SC_MINIMIZE could not be posted to the main window.");

                bool hidden = WaitUntil(
                    () => !NativeMethods.IsWindowVisible(originalHandle) || NativeMethods.IsIconic(originalHandle),
                    TimeSpan.FromSeconds(8),
                    100);
                if (!hidden)
                    throw new TimeoutException("The main window did not minimize/hide in the notification area.");

                AddStep(
                    test,
                    "Minimize and hide the main window",
                    null,
                    true,
                    "The original window became hidden or iconic while the process remained alive.",
                    null);

                if (!CheckResponsive())
                    throw new InvalidOperationException("The application process stopped responding while hidden.");

                applicationController.LaunchAdditionalInstance();

                IntPtr restoredHandle = IntPtr.Zero;
                bool restored = WaitUntil(
                    () =>
                    {
                        process.Refresh();
                        restoredHandle = process.MainWindowHandle;
                        return restoredHandle != IntPtr.Zero &&
                               NativeMethods.IsWindow(restoredHandle) &&
                               NativeMethods.IsWindowVisible(restoredHandle) &&
                               !NativeMethods.IsIconic(restoredHandle);
                    },
                    TimeSpan.FromSeconds(configuration.Application.StartupTimeoutSeconds),
                    150);

                if (!restored)
                    throw new TimeoutException(
                        "Launching SimVoice Copilot again did not restore the already-running hidden window.");

                NativeMethods.SetForegroundWindow(restoredHandle);
                ui = new UiAutomationDriver(process, logger);
                AutomationElement window = ui.WaitForMainWindow(
                    configuration.MainWindow,
                    TimeSpan.FromSeconds(configuration.Execution.ElementTimeoutSeconds));

                if (!CheckResponsive())
                    throw new InvalidOperationException("The restored main window was not responsive.");

                string screenshot = CaptureScreenshot("single-instance-restored");
                AddStep(
                    test,
                    "Launch again and restore existing instance",
                    null,
                    true,
                    "The same process exposed a visible, normal and responsive main window: " + ui.Describe(window),
                    screenshot,
                    null);

                string applicationProcessName =
                    Path.GetFileNameWithoutExtension(configuration.Application.ProcessName);
                WaitUntil(
                    () => Process.GetProcessesByName(applicationProcessName).Length == 1,
                    TimeSpan.FromSeconds(5),
                    200);
                int appProcessCount = Process.GetProcessesByName(applicationProcessName).Length;
                bool oneInstance = appProcessCount == 1;
                AddStep(
                    test,
                    "Verify single running application process",
                    null,
                    oneInstance,
                    "Detected SimVoice Copilot process count: " + appProcessCount + ".",
                    null);

                EndTest(
                    test,
                    oneInstance,
                    oneInstance
                        ? "Hidden-window restoration and single-instance behavior passed."
                        : "The window restored, but more than one application process remained running.",
                    null);
            }
            catch (Exception ex)
            {
                try
                {
                    process.Refresh();
                    IntPtr handle = process.MainWindowHandle;
                    if (handle != IntPtr.Zero)
                    {
                        NativeMethods.ShowWindowAsync(handle, NativeMethods.SwRestore);
                        NativeMethods.SetForegroundWindow(handle);
                    }
                }
                catch { }

                AddStep(
                    test,
                    "Restore hidden application window",
                    null,
                    false,
                    null,
                    CaptureScreenshotSafe("single-instance-restore-failure"),
                    ex);
                EndTest(test, false, "Tray/single-instance restoration regression failed.", ex);
            }
        }

        private static bool WaitUntil(Func<bool> condition, TimeSpan timeout, int intervalMs)
        {
            DateTime deadline = DateTime.UtcNow.Add(timeout);
            do
            {
                try
                {
                    if (condition())
                        return true;
                }
                catch
                {
                    // Transient window-handle/process refresh races are retried.
                }

                Thread.Sleep(Math.Max(25, intervalMs));
            } while (DateTime.UtcNow < deadline);

            return false;
        }

        private void RunVoiceChecklistSuite()
        {
            TestCaseResult test = BeginTest("Voice Checklists end-to-end suite");
            VoiceChecklistConfiguration checklistConfiguration = configuration.VoiceChecklists;
            if (checklistConfiguration == null || !checklistConfiguration.Enabled)
            {
                test.Skipped = true;
                EndTest(test, false, "Voice Checklists QA was not enabled.", null);
                return;
            }

            string deployedFixture = null;
            string deployedFixtureBackup = null;
            bool deployedFixtureExisted = false;
            try
            {
                string fixturePath = Environment.ExpandEnvironmentVariables(
                    checklistConfiguration.FixtureFile ?? string.Empty);
                if (!Path.IsPathRooted(fixturePath))
                {
                    string configDirectory = Path.GetDirectoryName(report.ConfigurationPath) ?? Environment.CurrentDirectory;
                    fixturePath = Path.GetFullPath(Path.Combine(configDirectory, fixturePath));
                }

                if (!File.Exists(fixturePath))
                    throw new FileNotFoundException("Voice Checklist QA fixture was not found.", fixturePath);

                string importedDirectory = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "SimVoiceCopilot",
                    "Checklists");
                Directory.CreateDirectory(importedDirectory);
                deployedFixture = Path.Combine(importedDirectory, "SimVoice-QA-Voice-Checklist.xml");
                deployedFixtureExisted = File.Exists(deployedFixture);
                if (deployedFixtureExisted)
                {
                    deployedFixtureBackup = Path.Combine(outputRoot, "preserved-SimVoice-QA-Voice-Checklist.xml");
                    File.Copy(deployedFixture, deployedFixtureBackup, true);
                }
                File.Copy(fixturePath, deployedFixture, true);
                AddStep(
                    test,
                    "Deploy deterministic checklist fixture",
                    null,
                    true,
                    deployedFixture,
                    null);

                var bridge = new InternalAudioBridgeClient(checklistConfiguration.PipeName);
                BridgeResponse ready = bridge.WaitUntilReady(
                    TimeSpan.FromSeconds(checklistConfiguration.BridgeTimeoutSeconds));
                if (!ready.Success)
                    throw new InvalidOperationException("Internal Audio QA bridge is not ready: " + ready.Error);

                string suite = ResolveChecklistSuite(checklistConfiguration.Suite, ready.VoiceLanguage);
                bool spanish = suite.EndsWith("ES", StringComparison.OrdinalIgnoreCase);
                string requiredPrefix = spanish ? "es" : "en";
                if (string.IsNullOrWhiteSpace(ready.VoiceLanguage) ||
                    !ready.VoiceLanguage.StartsWith(requiredPrefix, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException(
                        "Voice checklist suite '" + suite + "' requires " +
                        (spanish ? "Spanish" : "English") +
                        ", but the app voice-recognition language is '" +
                        (ready.VoiceLanguage ?? string.Empty) + "'.");
                }

                ChecklistBridgeSnapshot initialSnapshot = ready.GetChecklistSnapshot();
                if (initialSnapshot == null)
                {
                    throw new InvalidOperationException(
                        "The installed app does not expose checklist diagnostics. " +
                        "Build and install the private MSIX with SIMVOICE_QA_INTERNAL_AUDIO enabled.");
                }

                AddStep(
                    test,
                    "Connect to Internal Audio QA bridge",
                    null,
                    true,
                    "Suite=" + suite + "; VoiceLanguage=" + ready.VoiceLanguage +
                    "; AppVersion=" + ready.AppVersion + "; " + initialSnapshot,
                    null);

                string language = ready.VoiceLanguage;
                int timeoutMs = checklistConfiguration.StepTimeoutSeconds * 1000;
                int postWaitMs = checklistConfiguration.PostCommandWaitMs;

                BridgeResponse reset = bridge.ResetState(timeoutMs);
                if (!reset.Success)
                    throw new InvalidOperationException("Internal Audio QA state reset failed: " + reset.Error);
                AddStep(test, "Reset residual voice and speech state", null, true, "Internal Audio QA state is clean.", null);

                TimeSpan elementTimeout = TimeSpan.FromSeconds(configuration.Execution.ElementTimeoutSeconds);
                UiSelectorConfiguration checklistTab = Selector("btnPestanaChecklist", "Checklist", "Button");
                UiSelectorConfiguration scanButton = Selector("btnChecklistScan", "Scan checklists|Buscar checklists|Scan|Buscar", "Button");
                UiSelectorConfiguration statusLabel = Selector("lblChecklistSelectionStatus", string.Empty, "Text");
                UiSelectorConfiguration sourceCombo = Selector("cboChecklistSource", string.Empty, "ComboBox");
                UiSelectorConfiguration startButton = Selector("btnChecklistStart", "Start checklist|Iniciar checklist", "Button");
                UiSelectorConfiguration currentItemLabel = Selector("lblChecklistCurrentItem", string.Empty, "Text");
                UiSelectorConfiguration cancelOrNewButton = Selector("btnChecklistCancelOrNew", "Cancel|Cancelar|New|Nueva|Continue|Continuar", "Button");

                ui.Activate(checklistTab, elementTimeout);
                Thread.Sleep(configuration.Execution.DelayAfterActionMs);
                EnsureChecklistSelectionState(
                    bridge,
                    initialSnapshot,
                    cancelOrNewButton,
                    scanButton,
                    spanish,
                    language,
                    timeoutMs,
                    postWaitMs,
                    checklistConfiguration.StepTimeoutSeconds,
                    elementTimeout);
                AddStep(test, "Normalize checklist UI to selection state", null, true, "Checklist selection controls are available.", null);

                ui.Activate(scanButton, elementTimeout);
                Thread.Sleep(250);

                bool scanCompleted = WaitUntil(
                    () =>
                    {
                        string status = ui.ReadValue(statusLabel, TimeSpan.FromMilliseconds(750));
                        bool notLoading = !string.IsNullOrWhiteSpace(status) &&
                                          status.IndexOf("scanning", StringComparison.OrdinalIgnoreCase) < 0 &&
                                          status.IndexOf("buscando", StringComparison.OrdinalIgnoreCase) < 0;
                        return notLoading && ui.IsEnabled(sourceCombo, TimeSpan.FromMilliseconds(750));
                    },
                    TimeSpan.FromSeconds(checklistConfiguration.StepTimeoutSeconds),
                    200);
                if (!scanCompleted)
                    throw new TimeoutException("Checklist scan did not complete or the source selector remained disabled.");

                ui.SetTextAndCommit(sourceCombo, "Simvoice QA Voice Checklist", elementTimeout);
                bool startEnabled = WaitUntil(
                    () => ui.IsEnabled(startButton, TimeSpan.FromMilliseconds(750)),
                    TimeSpan.FromSeconds(checklistConfiguration.StepTimeoutSeconds),
                    200);
                if (!startEnabled)
                {
                    throw new InvalidOperationException(
                        "The deterministic QA checklist was not selected or the Start checklist button remained disabled.");
                }

                string expectedSelectionStatus = spanish
                    ? "Importada · 2 listas · 10 elementos"
                    : "Imported · 2 lists · 10 items";
                string actualSelectionStatus = string.Empty;
                bool localizedSelectionStatus = WaitUntil(
                    () =>
                    {
                        actualSelectionStatus = ui.ReadValue(
                            statusLabel,
                            TimeSpan.FromMilliseconds(750));
                        return string.Equals(
                            (actualSelectionStatus ?? string.Empty).Trim(),
                            expectedSelectionStatus,
                            StringComparison.OrdinalIgnoreCase);
                    },
                    TimeSpan.FromSeconds(checklistConfiguration.StepTimeoutSeconds),
                    150);
                if (!localizedSelectionStatus)
                {
                    throw new InvalidOperationException(
                        "The visible imported checklist status is not correctly localized. Expected='" +
                        expectedSelectionStatus + "'; Actual='" +
                        (actualSelectionStatus ?? string.Empty) + "'.");
                }
                AddStep(
                    test,
                    "Verify localized imported checklist status",
                    null,
                    true,
                    actualSelectionStatus,
                    null);

                string selectionScreenshot = CaptureScreenshot("voice-checklist-selected");
                AddStep(
                    test,
                    "Scan and select deterministic checklist",
                    null,
                    true,
                    "Selected source: Simvoice QA Voice Checklist",
                    selectionScreenshot,
                    null);

                ui.Activate(startButton, elementTimeout);
                ChecklistBridgeSnapshot running = WaitForChecklistSnapshot(
                    bridge,
                    snapshot => IsState(snapshot, "Running") &&
                                string.Equals(snapshot.ChecklistName, "QA Voice Flow", StringComparison.OrdinalIgnoreCase) &&
                                snapshot.CurrentActionableNumber == 1,
                    checklistConfiguration.StepTimeoutSeconds);
                string startedScreenshot = CaptureScreenshot("voice-checklist-running");
                AddStep(test, "Start checklist from the UI", null, true, running.ToString(), startedScreenshot, null);

                string uiCurrent = ui.ReadValue(currentItemLabel, elementTimeout);
                if (string.IsNullOrWhiteSpace(uiCurrent))
                    throw new InvalidOperationException("The checklist current-item label is empty after starting the session.");
                AddStep(test, "Verify visible current checklist item", null, true, uiCurrent, null);

                ChecklistBridgeSnapshot repeated = InjectAndWait(
                    bridge,
                    spanish ? "repetir elemento" : "repeat item",
                    language,
                    timeoutMs,
                    postWaitMs,
                    snapshot => IsState(snapshot, "Running") && snapshot.CurrentActionableNumber == 1 && snapshot.CompletedItems == 0);
                AddStep(test, "Repeat current item by voice", null, true, repeated.ToString(), null);

                ChecklistBridgeSnapshot paused = InjectAndWait(
                    bridge,
                    spanish ? "pausar lista" : "pause checklist",
                    language,
                    timeoutMs,
                    postWaitMs,
                    snapshot => IsState(snapshot, "Paused") && snapshot.CurrentActionableNumber == 1);
                AddStep(test, "Pause checklist by voice", null, true, paused.ToString(), null);

                string pausedConfirmation = spanish ? "hecho" : "checked";
                ChecklistBridgeSnapshot stillPaused = InjectAndWait(
                    bridge,
                    pausedConfirmation,
                    language,
                    timeoutMs,
                    postWaitMs,
                    snapshot => IsState(snapshot, "Paused") && snapshot.CurrentActionableNumber == 1 && snapshot.CompletedItems == 0);
                AddStep(
                    test,
                    "Reject confirmation while paused",
                    null,
                    true,
                    "Confirmation did not advance the paused checklist. " + stillPaused,
                    null);

                ChecklistBridgeSnapshot resumed = InjectAndWait(
                    bridge,
                    spanish ? "continuar lista" : "resume checklist",
                    language,
                    timeoutMs,
                    postWaitMs,
                    snapshot => IsState(snapshot, "Running") && snapshot.CurrentActionableNumber == 1);
                AddStep(test, "Resume checklist by voice", null, true, resumed.ToString(), null);

                string[] confirmations = BuildConfirmationSequence(suite);
                string firstExpectedResponse = string.IsNullOrWhiteSpace(resumed.CurrentAction)
                    ? confirmations[0]
                    : resumed.CurrentAction;
                ChecklistBridgeSnapshot afterFirst = InjectAndWait(
                    bridge,
                    firstExpectedResponse,
                    language,
                    timeoutMs,
                    postWaitMs,
                    snapshot => IsState(snapshot, "Running") && snapshot.CurrentActionableNumber == 2 && snapshot.CompletedItems == 1);
                AddStep(
                    test,
                    "Confirm first item with the checklist expected response",
                    null,
                    true,
                    firstExpectedResponse + " => " + afterFirst,
                    null);

                ChecklistBridgeSnapshot skipped = InjectAndWait(
                    bridge,
                    spanish ? "omitir elemento" : "skip item",
                    language,
                    timeoutMs,
                    postWaitMs,
                    snapshot => IsState(snapshot, "Running") && snapshot.CurrentActionableNumber == 3 && snapshot.SkippedItems == 1);
                AddStep(test, "Skip item by voice", null, true, skipped.ToString(), null);

                ChecklistBridgeSnapshot previous = InjectAndWait(
                    bridge,
                    spanish ? "elemento anterior" : "previous item",
                    language,
                    timeoutMs,
                    postWaitMs,
                    snapshot => IsState(snapshot, "Running") && snapshot.CurrentActionableNumber == 2 && snapshot.SkippedItems == 0);
                AddStep(test, "Return to previous item by voice", null, true, previous.ToString(), null);

                ChecklistBridgeSnapshot afterSecond = InjectAndWait(
                    bridge,
                    confirmations[1],
                    language,
                    timeoutMs,
                    postWaitMs,
                    snapshot => IsState(snapshot, "Running") && snapshot.CurrentActionableNumber == 3 && snapshot.CompletedItems == 2);
                AddStep(test, "Confirm returned item by voice", null, true, confirmations[1] + " => " + afterSecond, null);

                ChecklistBridgeSnapshot beforeNormalCommand = bridge.GetStatus(timeoutMs).GetChecklistSnapshot();
                string normalCommand = spanish
                    ? "ajustar rumbo a dos uno cero"
                    : "set heading bug to two one zero";
                BridgeResponse normalResponse = bridge.Inject(
                    normalCommand,
                    language,
                    timeoutMs,
                    postWaitMs,
                    0);
                if (!normalResponse.Success)
                    throw new InvalidOperationException("Normal simulator command injection failed: " + normalResponse.Error);

                ChecklistBridgeSnapshot afterNormalCommand = normalResponse.GetChecklistSnapshot();
                if (afterNormalCommand == null || beforeNormalCommand == null ||
                    afterNormalCommand.CurrentActionableNumber != beforeNormalCommand.CurrentActionableNumber ||
                    afterNormalCommand.CompletedItems != beforeNormalCommand.CompletedItems ||
                    afterNormalCommand.SkippedItems != beforeNormalCommand.SkippedItems ||
                    !string.Equals(afterNormalCommand.State, beforeNormalCommand.State, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException(
                        "A normal simulator command changed the checklist session. Before=" +
                        beforeNormalCommand + "; After=" + afterNormalCommand);
                }
                AddStep(
                    test,
                    "Keep normal simulator commands outside checklist intent handling",
                    null,
                    true,
                    "Recognized='" + (normalResponse.RecognizedText ?? string.Empty) +
                    "'; checklist unchanged: " + afterNormalCommand,
                    null);

                ChecklistBridgeSnapshot snapshotAfterConfirmation = afterSecond;
                for (int i = 2; i < confirmations.Length; i++)
                {
                    int expectedCompleted = i + 1;
                    bool finalConfirmation = i == confirmations.Length - 1;
                    bool usePrintedExpectedResponse = string.Equals(
                        snapshotAfterConfirmation.CurrentAction,
                        "Set",
                        StringComparison.OrdinalIgnoreCase);
                    string confirmationPhrase = usePrintedExpectedResponse
                        ? snapshotAfterConfirmation.CurrentAction
                        : confirmations[i];

                    snapshotAfterConfirmation = InjectAndWait(
                        bridge,
                        confirmationPhrase,
                        language,
                        timeoutMs,
                        postWaitMs,
                        snapshot => finalConfirmation
                            ? IsState(snapshot, "Completed") && snapshot.CompletedItems == confirmations.Length
                            : IsState(snapshot, "Running") && snapshot.CompletedItems == expectedCompleted &&
                              snapshot.CurrentActionableNumber == expectedCompleted + 1);
                    AddStep(
                        test,
                        usePrintedExpectedResponse
                            ? "Checklist expected response: " + confirmationPhrase
                            : "Confirmation phrase: " + confirmationPhrase,
                        null,
                        true,
                        snapshotAfterConfirmation.ToString(),
                        null);
                }

                string completedScreenshot = CaptureScreenshot("voice-checklist-completed");
                AddStep(
                    test,
                    "Complete checklist with configured and item-specific confirmation vocabulary",
                    null,
                    true,
                    snapshotAfterConfirmation.ToString(),
                    completedScreenshot,
                    null);

                ChecklistBridgeSnapshot nextChecklist = InjectAndWait(
                    bridge,
                    spanish ? "siguiente lista" : "next checklist",
                    language,
                    timeoutMs,
                    postWaitMs,
                    snapshot => IsState(snapshot, "Running") &&
                                string.Equals(snapshot.ChecklistName, "QA Next Checklist", StringComparison.OrdinalIgnoreCase) &&
                                snapshot.CurrentActionableNumber == 1);
                AddStep(test, "Start next checklist by voice", null, true, nextChecklist.ToString(), null);

                string nextExpectedResponse = string.IsNullOrWhiteSpace(nextChecklist.CurrentAction)
                    ? (spanish ? "comprobado" : "checked")
                    : nextChecklist.CurrentAction;
                ChecklistBridgeSnapshot nextChecklistAdvanced = InjectAndWait(
                    bridge,
                    nextExpectedResponse,
                    language,
                    timeoutMs,
                    postWaitMs,
                    snapshot => IsState(snapshot, "Running") &&
                                string.Equals(snapshot.ChecklistName, "QA Next Checklist", StringComparison.OrdinalIgnoreCase) &&
                                snapshot.CurrentActionableNumber == 2 &&
                                snapshot.CompletedItems == 1);
                AddStep(
                    test,
                    "Confirm next-list item with its printed expected response",
                    null,
                    true,
                    nextExpectedResponse + " => " + nextChecklistAdvanced,
                    null);

                ChecklistSyncBridgeSnapshot syncSnapshot = bridge.GetStatus(timeoutMs).GetChecklistSyncSnapshot();
                AddStep(
                    test,
                    "Capture aircraft synchronization diagnostics",
                    null,
                    syncSnapshot != null,
                    syncSnapshot == null ? "Checklist sync diagnostics were unavailable." : syncSnapshot.ToString(),
                    null);
                if (syncSnapshot == null)
                    throw new InvalidOperationException("Checklist aircraft synchronization diagnostics were unavailable.");

                ChecklistBridgeSnapshot cancelled = InjectAndWait(
                    bridge,
                    spanish ? "cancelar lista" : "cancel checklist",
                    language,
                    timeoutMs,
                    postWaitMs,
                    snapshot => IsState(snapshot, "Cancelled"));
                BridgeResponse speechIdle = bridge.WaitForSpeechIdle(timeoutMs);
                if (!speechIdle.Success)
                    throw new InvalidOperationException("Speech did not become idle after checklist cancellation: " + speechIdle.Error);

                string cancelledScreenshot = CaptureScreenshot("voice-checklist-cancelled");
                AddStep(
                    test,
                    "Cancel checklist and stop speech",
                    null,
                    true,
                    cancelled.ToString(),
                    cancelledScreenshot,
                    null);

                EndTest(
                    test,
                    true,
                    "Voice Checklists suite " + suite +
                    " passed: UI start, internal-audio recognition, confirmations, pause/resume, " +
                    "repeat, skip, previous, normal-command isolation, next checklist, cancellation and diagnostics.",
                    null);
            }
            catch (Exception ex)
            {
                AddStep(
                    test,
                    "Voice Checklists end-to-end execution",
                    null,
                    false,
                    null,
                    CaptureScreenshotSafe("voice-checklists-failure"),
                    ex);
                EndTest(test, false, "Voice Checklists end-to-end suite failed.", ex);
            }
            finally
            {
                if (!string.IsNullOrWhiteSpace(deployedFixture))
                {
                    try
                    {
                        if (deployedFixtureExisted &&
                            !string.IsNullOrWhiteSpace(deployedFixtureBackup) &&
                            File.Exists(deployedFixtureBackup))
                        {
                            File.Copy(deployedFixtureBackup, deployedFixture, true);
                            File.Delete(deployedFixtureBackup);
                        }
                        else if (checklistConfiguration == null || !checklistConfiguration.PreserveFixture)
                        {
                            File.Delete(deployedFixture);
                        }
                    }
                    catch (Exception cleanupException)
                    {
                        logger.Warn("Voice Checklist fixture cleanup failed: " + cleanupException.Message);
                    }
                }
            }
        }


        private void EnsureChecklistSelectionState(
            InternalAudioBridgeClient bridge,
            ChecklistBridgeSnapshot initialSnapshot,
            UiSelectorConfiguration cancelOrNewButton,
            UiSelectorConfiguration scanButton,
            bool spanish,
            string language,
            int timeoutMs,
            int postCommandWaitMs,
            int timeoutSeconds,
            TimeSpan elementTimeout)
        {
            ChecklistBridgeSnapshot snapshot = initialSnapshot;
            if (snapshot != null &&
                (IsState(snapshot, "Running") || IsState(snapshot, "Paused")))
            {
                snapshot = InjectAndWait(
                    bridge,
                    spanish ? "cancelar lista" : "cancel checklist",
                    language,
                    timeoutMs,
                    postCommandWaitMs,
                    value => IsState(value, "Cancelled"));
            }
            else if (snapshot != null && IsState(snapshot, "Completed"))
            {
                ui.Activate(cancelOrNewButton, elementTimeout);
                Thread.Sleep(Math.Max(250, configuration.Execution.DelayAfterActionMs));

                BridgeResponse status = bridge.GetStatus(timeoutMs);
                if (!status.Success)
                    throw new InvalidOperationException("Checklist status failed while returning to selection: " + status.Error);

                snapshot = status.GetChecklistSnapshot();
                if (snapshot != null &&
                    (IsState(snapshot, "Running") || IsState(snapshot, "Paused")))
                {
                    snapshot = InjectAndWait(
                        bridge,
                        spanish ? "cancelar lista" : "cancel checklist",
                        language,
                        timeoutMs,
                        postCommandWaitMs,
                        value => IsState(value, "Cancelled"));
                }
            }

            bool selectionAvailable = WaitUntil(
                () => ui.IsEnabled(scanButton, TimeSpan.FromMilliseconds(750)),
                TimeSpan.FromSeconds(Math.Max(3, timeoutSeconds)),
                150);
            if (!selectionAvailable)
            {
                throw new TimeoutException(
                    "Voice Checklist selection controls did not become available. Last snapshot: " +
                    (snapshot == null ? "(null)" : snapshot.ToString()));
            }
        }

        private ChecklistBridgeSnapshot InjectAndWait(
            InternalAudioBridgeClient bridge,
            string phrase,
            string language,
            int timeoutMs,
            int postCommandWaitMs,
            Func<ChecklistBridgeSnapshot, bool> expected)
        {
            BridgeResponse idle = bridge.WaitForSpeechIdle(timeoutMs);
            if (!idle.Success)
                throw new InvalidOperationException("Speech was not idle before injecting '" + phrase + "': " + idle.Error);

            BridgeResponse response = bridge.Inject(
                phrase,
                language,
                timeoutMs,
                postCommandWaitMs,
                0);
            if (!response.Success)
            {
                throw new InvalidOperationException(
                    "Internal audio injection failed for '" + phrase + "': " + response.Error);
            }

            ChecklistBridgeSnapshot immediate = response.GetChecklistSnapshot();
            if (immediate != null && expected(immediate))
            {
                logger.Info(
                    "Checklist voice phrase '" + phrase + "' recognized as '" +
                    (response.RecognizedText ?? string.Empty) + "'. " + immediate);
                return immediate;
            }

            ChecklistBridgeSnapshot waited = WaitForChecklistSnapshot(
                bridge,
                expected,
                Math.Max(3, timeoutMs / 1000));
            logger.Info(
                "Checklist voice phrase '" + phrase + "' recognized as '" +
                (response.RecognizedText ?? string.Empty) + "'. " + waited);
            return waited;
        }

        private static ChecklistBridgeSnapshot WaitForChecklistSnapshot(
            InternalAudioBridgeClient bridge,
            Func<ChecklistBridgeSnapshot, bool> expected,
            int timeoutSeconds)
        {
            DateTime deadline = DateTime.UtcNow.AddSeconds(Math.Max(1, timeoutSeconds));
            ChecklistBridgeSnapshot last = null;
            while (DateTime.UtcNow < deadline)
            {
                BridgeResponse status = bridge.GetStatus(3000);
                if (!status.Success)
                    throw new InvalidOperationException("Checklist status request failed: " + status.Error);

                last = status.GetChecklistSnapshot();
                if (last != null && expected(last))
                    return last;

                Thread.Sleep(200);
            }

            throw new TimeoutException(
                "Checklist state did not reach the expected condition. Last snapshot: " +
                (last == null ? "none" : last.ToString()));
        }

        private static bool IsState(ChecklistBridgeSnapshot snapshot, string state)
        {
            return snapshot != null &&
                   string.Equals(snapshot.State, state, StringComparison.OrdinalIgnoreCase);
        }

        private static string ResolveChecklistSuite(string configuredSuite, string voiceLanguage)
        {
            string suite = string.IsNullOrWhiteSpace(configuredSuite) ? "Auto" : configuredSuite.Trim();
            if (!string.Equals(suite, "Auto", StringComparison.OrdinalIgnoreCase))
                return suite;

            return !string.IsNullOrWhiteSpace(voiceLanguage) &&
                   voiceLanguage.StartsWith("es", StringComparison.OrdinalIgnoreCase)
                ? "CoreES"
                : "CoreEN";
        }

        private static string[] BuildConfirmationSequence(string suite)
        {
            bool spanish = suite.EndsWith("ES", StringComparison.OrdinalIgnoreCase);
            bool smoke = suite.StartsWith("Smoke", StringComparison.OrdinalIgnoreCase);

            if (spanish)
            {
                return smoke
                    ? new[] { "hecho", "entendido", "hecho", "entendido", "hecho", "entendido", "hecho", "entendido" }
                    : new[] { "comprobado", "hecho", "entendido", "listo", "completado", "confirmado", "ok", "hecho" };
            }

            return smoke
                ? new[] { "checked", "roger", "checked", "roger", "checked", "roger", "checked", "roger" }
                : new[] { "checked", "check", "done", "roger", "completed", "confirmed", "checked", "done" };
        }

        private static UiSelectorConfiguration Selector(string automationId, string names, string controlType)
        {
            return new UiSelectorConfiguration
            {
                AutomationId = automationId,
                Names = names,
                ControlType = controlType
            };
        }

        private void RunNavigationSmoke()
        {
            TestCaseResult test = BeginTest("Navigation smoke test");
            if (configuration.Navigation == null || configuration.Navigation.Count == 0)
            {
                test.Skipped = true;
                EndTest(test, false, "No navigation panels are configured.", null);
                return;
            }

            bool allPassed = true;
            foreach (NavigationActionConfiguration action in configuration.Navigation)
            {
                bool passed = ExecuteAction(test, action, null, "Smoke");
                allPassed &= passed;
            }

            EndTest(
                test,
                allPassed,
                allPassed ? "Every configured panel opened successfully." : "At least one configured panel failed.",
                null);
        }

        private void RunNavigationStress()
        {
            TestCaseResult test = BeginTest("Navigation stability loop");
            if (configuration.Navigation == null || configuration.Navigation.Count == 0)
            {
                test.Skipped = true;
                EndTest(test, false, "No navigation panels are configured.", null);
                return;
            }

            ProcessMetricSample before = monitor.TakeSnapshot("stress-before");
            bool allPassed = true;

            for (int cycle = 1; cycle <= configuration.Execution.Cycles; cycle++)
            {
                logger.Info("Starting QA navigation cycle " + cycle + " of " + configuration.Execution.Cycles + ".");
                foreach (NavigationActionConfiguration action in configuration.Navigation)
                {
                    bool passed = ExecuteAction(test, action, cycle, "Stress");
                    allPassed &= passed;
                    if (!passed)
                    {
                        logger.Warn("Stopping stress loop after failure in cycle " + cycle + ".");
                        break;
                    }
                }

                if (!allPassed)
                {
                    break;
                }
            }

            ProcessMetricSample after = monitor.TakeSnapshot("stress-after");
            CalculateResourceDelta(before, after);

            EndTest(
                test,
                allPassed,
                allPassed
                    ? configuration.Execution.Cycles + " navigation cycles completed without a detected hang or crash."
                    : "The navigation stress loop stopped after a failure.",
                null);
        }

        private void EvaluateResourceGrowth()
        {
            TestCaseResult test = BeginTest("Resource growth thresholds");
            ResourceDeltaSummary delta = report.ResourceDelta;

            bool passed =
                delta.WorkingSetGrowthMb <= configuration.Execution.MaxWorkingSetGrowthMb &&
                delta.HandleGrowth <= configuration.Execution.MaxHandleGrowth &&
                delta.ThreadGrowth <= configuration.Execution.MaxThreadGrowth;

            delta.WithinConfiguredThresholds = passed;
            delta.Message = string.Format(
                "Working set {0:+0.00;-0.00;0.00} MB (max {1:0.00}); handles {2:+0;-0;0} (max {3}); threads {4:+0;-0;0} (max {5}).",
                delta.WorkingSetGrowthMb,
                configuration.Execution.MaxWorkingSetGrowthMb,
                delta.HandleGrowth,
                configuration.Execution.MaxHandleGrowth,
                delta.ThreadGrowth,
                configuration.Execution.MaxThreadGrowth);

            AddStep(test, "Evaluate configured resource thresholds", null, passed, delta.Message, null);
            EndTest(test, passed, delta.Message, null);
        }

        private void RunShutdown()
        {
            TestCaseResult test = BeginTest("Application shutdown");
            if (!configuration.Execution.CloseApplicationAtEnd)
            {
                test.Skipped = true;
                EndTest(test, false, "Application shutdown was disabled by configuration or command line.", null);
                return;
            }

            try
            {
                bool requestedByUi = false;
                if (configuration.CloseAction != null && !configuration.CloseAction.IsEmpty())
                {
                    try
                    {
                        ui.Activate(
                            configuration.CloseAction,
                            TimeSpan.FromSeconds(GetSelectorTimeout(configuration.CloseAction)));
                        requestedByUi = true;
                        AddStep(test, "Invoke configured close action", null, true, "Close control invoked.", null);
                    }
                    catch (Exception closeActionException)
                    {
                        AddStep(
                            test,
                            "Invoke configured close action",
                            null,
                            false,
                            "Falling back to CloseMainWindow.",
                            CaptureScreenshotSafe("close-action-failure"),
                            closeActionException);
                    }
                }

                bool exited;
                if (requestedByUi)
                {
                    exited = applicationController.WaitForExit(
                        process,
                        TimeSpan.FromSeconds(configuration.Application.ShutdownTimeoutSeconds));
                }
                else
                {
                    exited = applicationController.RequestShutdown(process);
                }

                if (!exited)
                {
                    throw new TimeoutException(
                        "The main window closed or received a close request, but process PID " +
                        process.Id + " remained running after " +
                        configuration.Application.ShutdownTimeoutSeconds + " seconds.");
                }

                AddStep(test, "Verify process termination", null, true, "Process exited completely.", null);
                EndTest(test, true, "Application closed and disappeared from Task Manager.", null);
            }
            catch (Exception ex)
            {
                AddStep(test, "Verify process termination", null, false, null, CaptureScreenshotSafe("shutdown-failure"), ex);
                EndTest(test, false, "Application shutdown verification failed.", ex);
            }
        }

        private bool ExecuteAction(
            TestCaseResult test,
            NavigationActionConfiguration action,
            int? cycle,
            string phase)
        {
            string actionName = string.IsNullOrWhiteSpace(action.Name)
                ? action.ToString()
                : action.Name;

            DateTimeOffset started = DateTimeOffset.Now;
            try
            {
                if (!CheckResponsive())
                {
                    throw new InvalidOperationException(
                        "The application was not responding before activating '" + actionName + "'.");
                }

                HashSet<IntPtr> windowBaseline = action.ExpectSecondaryWindow
                    ? ui.SnapshotVisibleProcessWindows()
                    : null;

                ui.Activate(action, TimeSpan.FromSeconds(GetSelectorTimeout(action)));
                Thread.Sleep(configuration.Execution.DelayAfterActionMs);

                IntPtr secondaryWindow = IntPtr.Zero;
                if (action.ExpectSecondaryWindow)
                {
                    secondaryWindow = ui.WaitForSecondaryWindow(
                        windowBaseline,
                        TimeSpan.FromSeconds(GetSelectorTimeout(action)));
                }

                if (action.ExpectedVisible != null && !action.ExpectedVisible.IsEmpty())
                {
                    ui.FindElement(
                        action.ExpectedVisible,
                        TimeSpan.FromSeconds(GetSelectorTimeout(action.ExpectedVisible)));
                }

                if (!CheckResponsive())
                {
                    throw new InvalidOperationException(
                        "The application stopped responding after activating '" + actionName + "'.");
                }

                string screenshot = null;
                if (configuration.Execution.CaptureScreenshotOnEveryStep)
                {
                    screenshot = CaptureScreenshot(
                        phase.ToLowerInvariant() + "-" +
                        (cycle.HasValue ? cycle.Value.ToString("000") + "-" : string.Empty) +
                        SanitizeFileName(actionName));
                }

                int closedSecondaryWindows = 0;
                if (action.Close != null && !action.Close.IsEmpty())
                {
                    ui.Activate(action.Close, TimeSpan.FromSeconds(GetSelectorTimeout(action.Close)));
                    Thread.Sleep(configuration.Execution.DelayAfterActionMs);
                }
                else if (action.AutoCloseSecondaryWindow && secondaryWindow != IntPtr.Zero)
                {
                    closedSecondaryWindows = ui.CloseSecondaryWindow(
                        secondaryWindow,
                        TimeSpan.FromSeconds(GetSelectorTimeout(action)));
                    if (closedSecondaryWindows > 0)
                    {
                        Thread.Sleep(configuration.Execution.DelayAfterActionMs);
                    }
                }

                if (action.ExpectSecondaryWindow &&
                    secondaryWindow != IntPtr.Zero &&
                    action.AutoCloseSecondaryWindow &&
                    closedSecondaryWindows < 1 &&
                    (action.Close == null || action.Close.IsEmpty()))
                {
                    throw new InvalidOperationException(
                        "A secondary window opened for '" + actionName +
                        "', but the QA runner did not close it.");
                }

                if (!CheckResponsive())
                {
                    throw new InvalidOperationException(
                        "The application stopped responding after completing '" + actionName + "'.");
                }

                string completionMessage = action.ExpectSecondaryWindow
                    ? "Control activated, a secondary window opened and was closed, and the application remained responsive."
                    : "Control activated and the application remained responsive.";

                AddStep(
                    test,
                    phase + ": " + actionName,
                    cycle,
                    true,
                    completionMessage,
                    screenshot,
                    null,
                    started);

                return true;
            }
            catch (Exception ex)
            {
                string screenshot = configuration.Execution.CaptureScreenshotOnFailure
                    ? CaptureScreenshotSafe(
                        phase.ToLowerInvariant() + "-" +
                        (cycle.HasValue ? cycle.Value.ToString("000") + "-" : string.Empty) +
                        SanitizeFileName(actionName) + "-failure")
                    : null;

                AddStep(test, phase + ": " + actionName, cycle, false, null, screenshot, ex, started);
                logger.Error("QA action failed: " + actionName, ex);
                return false;
            }
        }

        private bool CheckResponsive()
        {
            for (int attempt = 1; attempt <= configuration.Execution.ResponsivenessRetries; attempt++)
            {
                try
                {
                    process.Refresh();
                    if (process.HasExited)
                    {
                        return false;
                    }

                    if (process.Responding)
                    {
                        return true;
                    }
                }
                catch
                {
                    return false;
                }

                Thread.Sleep(configuration.Execution.ResponsivenessRetryDelayMs);
            }

            return false;
        }

        private void CalculateResourceDelta(ProcessMetricSample before, ProcessMetricSample after)
        {
            report.ResourceDelta = new ResourceDeltaSummary
            {
                WorkingSetGrowthMb = Math.Round(after.WorkingSetMb - before.WorkingSetMb, 2),
                PrivateMemoryGrowthMb = Math.Round(after.PrivateMemoryMb - before.PrivateMemoryMb, 2),
                HandleGrowth = after.HandleCount - before.HandleCount,
                ThreadGrowth = after.ThreadCount - before.ThreadCount
            };
        }

        private int GetSelectorTimeout(UiSelectorConfiguration selector)
        {
            return selector != null && selector.TimeoutSeconds > 0
                ? selector.TimeoutSeconds
                : configuration.Execution.ElementTimeoutSeconds;
        }

        private string CaptureScreenshot(string name)
        {
            string path = Path.Combine(
                screenshotsDirectory,
                (++screenshotSequence).ToString("0000") + "-" + SanitizeFileName(name) + ".png");
            return ScreenshotService.CaptureProcessWindow(process, path);
        }

        private string CaptureScreenshotSafe(string name)
        {
            try
            {
                if (process == null)
                {
                    return null;
                }

                return CaptureScreenshot(name);
            }
            catch (Exception ex)
            {
                logger.Warn("Screenshot capture failed: " + ex.Message);
                return null;
            }
        }

        private TestCaseResult BeginTest(string name)
        {
            TestCaseResult result = new TestCaseResult
            {
                Name = name,
                StartedAtLocal = DateTimeOffset.Now
            };
            report.Tests.Add(result);
            logger.Info("TEST START: " + name);
            return result;
        }

        private void EndTest(TestCaseResult test, bool passed, string message, Exception exception)
        {
            test.Passed = passed && !test.Skipped;
            test.Message = message;
            test.Error = exception == null ? null : exception.ToString();
            test.FinishedAtLocal = DateTimeOffset.Now;

            logger.Info(
                "TEST END: " + test.Name + " => " +
                (test.Skipped ? "SKIPPED" : (test.Passed ? "PASS" : "FAIL")) +
                ". " + message);
        }

        private void AddStep(
            TestCaseResult test,
            string name,
            int? cycle,
            bool passed,
            string message,
            string screenshot,
            Exception exception = null,
            DateTimeOffset? startedAt = null)
        {
            test.Steps.Add(new TestStepResult
            {
                Sequence = test.Steps.Count + 1,
                Name = name,
                Cycle = cycle,
                StartedAtLocal = startedAt ?? DateTimeOffset.Now,
                FinishedAtLocal = DateTimeOffset.Now,
                Passed = passed,
                Message = message,
                Error = exception == null ? null : exception.ToString(),
                ScreenshotPath = screenshot
            });
        }

        private static string GetApplicationVersion(Process process)
        {
            try
            {
                string fileName = process.MainModule.FileName;
                return FileVersionInfo.GetVersionInfo(fileName).FileVersion;
            }
            catch
            {
                return string.Empty;
            }
        }

        private static string SanitizeFileName(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return "unnamed";
            }

            char[] invalid = Path.GetInvalidFileNameChars();
            char[] chars = value.ToCharArray();
            for (int i = 0; i < chars.Length; i++)
            {
                if (invalid.Contains(chars[i]) || char.IsWhiteSpace(chars[i]))
                {
                    chars[i] = '-';
                }
            }

            return new string(chars).Trim('-').ToLowerInvariant();
        }

        private void Cleanup()
        {
            try
            {
                if (monitor != null)
                {
                    monitor.Stop();
                }
            }
            finally
            {
                applicationController.Cleanup(process, configuration.Execution.ForceKillOnCleanup);
                if (monitor != null)
                {
                    monitor.Dispose();
                }
            }
        }
    }
}
