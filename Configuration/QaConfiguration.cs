using System;
using System.Collections.Generic;
using System.IO;
using System.Xml.Serialization;

namespace SimVoiceCopilot.QA.Configuration
{
    [XmlRoot("QaConfiguration")]
    public sealed class QaConfiguration
    {
        public ApplicationConfiguration Application { get; set; }
        public ExecutionConfiguration Execution { get; set; }
        public UiSelectorConfiguration MainWindow { get; set; }
        public VoiceChecklistConfiguration VoiceChecklists { get; set; }

        [XmlArray("StartupActions")]
        [XmlArrayItem("Action")]
        public List<NavigationActionConfiguration> StartupActions { get; set; }

        [XmlArray("Navigation")]
        [XmlArrayItem("Panel")]
        public List<NavigationActionConfiguration> Navigation { get; set; }

        public UiSelectorConfiguration CloseAction { get; set; }

        public QaConfiguration()
        {
            Application = new ApplicationConfiguration();
            Execution = new ExecutionConfiguration();
            MainWindow = new UiSelectorConfiguration { Names = "SimVoice Copilot", ControlType = "Window" };
            VoiceChecklists = new VoiceChecklistConfiguration();
            StartupActions = new List<NavigationActionConfiguration>();
            Navigation = new List<NavigationActionConfiguration>();
            CloseAction = new UiSelectorConfiguration();
        }

        public static QaConfiguration Load(string path)
        {
            XmlSerializer serializer = new XmlSerializer(typeof(QaConfiguration));
            using (FileStream stream = File.OpenRead(path))
            {
                return (QaConfiguration)serializer.Deserialize(stream);
            }
        }

        internal void ApplyOverrides(CommandLineOptions options)
        {
            if (options.Cycles.HasValue)
            {
                Execution.Cycles = options.Cycles.Value;
            }

            if (options.CloseApplicationAtEnd.HasValue)
            {
                Execution.CloseApplicationAtEnd = options.CloseApplicationAtEnd.Value;
            }

            if (options.VoiceChecklistsEnabled.HasValue)
            {
                VoiceChecklists.Enabled = options.VoiceChecklistsEnabled.Value;
            }

            if (!string.IsNullOrWhiteSpace(options.VoiceChecklistSuite))
            {
                VoiceChecklists.Suite = options.VoiceChecklistSuite.Trim();
            }
        }

        public void ResolvePaths(string configDirectory)
        {
            if (string.IsNullOrWhiteSpace(Application.ExecutablePath))
            {
                return;
            }

            string expanded = Environment.ExpandEnvironmentVariables(Application.ExecutablePath);
            if (!Path.IsPathRooted(expanded))
            {
                expanded = Path.Combine(configDirectory, expanded);
            }

            Application.ExecutablePath = Path.GetFullPath(expanded);
        }

        public void Validate()
        {
            if (Application == null)
            {
                throw new InvalidOperationException("Application configuration is required.");
            }

            if (Execution == null)
            {
                throw new InvalidOperationException("Execution configuration is required.");
            }

            if (VoiceChecklists == null)
            {
                VoiceChecklists = new VoiceChecklistConfiguration();
            }

            if (string.IsNullOrWhiteSpace(Application.ProcessName))
            {
                throw new InvalidOperationException("Application.ProcessName is required.");
            }

            LaunchMode launchMode;
            if (!Enum.TryParse(Application.LaunchMode, true, out launchMode))
            {
                throw new InvalidOperationException("Application.LaunchMode must be Executable, PackagedApp, or AttachOnly.");
            }

            if (launchMode == LaunchMode.Executable && !File.Exists(Application.ExecutablePath))
            {
                throw new FileNotFoundException("SimVoice Copilot executable was not found.", Application.ExecutablePath);
            }

            if (launchMode == LaunchMode.PackagedApp && string.IsNullOrWhiteSpace(Application.PackagedAppId))
            {
                throw new InvalidOperationException("Application.PackagedAppId is required for PackagedApp launch mode.");
            }

            if (Execution.Cycles < 1)
            {
                throw new InvalidOperationException("Execution.Cycles must be at least 1.");
            }

            if (Application.StartupTimeoutSeconds < 1 || Application.ShutdownTimeoutSeconds < 1)
            {
                throw new InvalidOperationException("Startup and shutdown timeouts must be positive.");
            }

            if (VoiceChecklists.Enabled)
            {
                string suite = (VoiceChecklists.Suite ?? string.Empty).Trim();
                string[] supported = { "Auto", "SmokeEN", "CoreEN", "SmokeES", "CoreES" };
                if (!Array.Exists(supported, value => string.Equals(value, suite, StringComparison.OrdinalIgnoreCase)))
                {
                    throw new InvalidOperationException(
                        "VoiceChecklists.Suite must be Auto, SmokeEN, CoreEN, SmokeES, or CoreES.");
                }

                if (VoiceChecklists.BridgeTimeoutSeconds < 1 || VoiceChecklists.StepTimeoutSeconds < 1)
                {
                    throw new InvalidOperationException("Voice checklist QA timeouts must be positive.");
                }
            }
        }
    }


    public sealed class VoiceChecklistConfiguration
    {
        public bool Enabled { get; set; }
        public string Suite { get; set; }
        public string PipeName { get; set; }
        public string FixtureFile { get; set; }
        public int BridgeTimeoutSeconds { get; set; }
        public int StepTimeoutSeconds { get; set; }
        public int PostCommandWaitMs { get; set; }
        public bool PreserveFixture { get; set; }

        public VoiceChecklistConfiguration()
        {
            Enabled = false;
            Suite = "Auto";
            PipeName = "SimVoiceCopilot.QA.InternalAudio.v1";
            FixtureFile = @"VoiceChecklists\Fixtures\SimVoice-QA-Voice-Checklist.xml";
            BridgeTimeoutSeconds = 60;
            StepTimeoutSeconds = 30;
            PostCommandWaitMs = 500;
            PreserveFixture = false;
        }
    }

    public enum LaunchMode
    {
        Executable,
        PackagedApp,
        AttachOnly
    }

    public sealed class ApplicationConfiguration
    {
        public string LaunchMode { get; set; }
        public string ExecutablePath { get; set; }
        public string LaunchArguments { get; set; }
        public string WorkingDirectory { get; set; }
        public string PackagedAppId { get; set; }
        public string ProcessName { get; set; }
        public bool AttachIfRunning { get; set; }
        public int StartupTimeoutSeconds { get; set; }
        public int ShutdownTimeoutSeconds { get; set; }

        public ApplicationConfiguration()
        {
            LaunchMode = "Executable";
            ProcessName = "SimVoiceCopilotApp";
            AttachIfRunning = true;
            StartupTimeoutSeconds = 45;
            ShutdownTimeoutSeconds = 15;
        }
    }

    public sealed class ExecutionConfiguration
    {
        public int Cycles { get; set; }
        public int ElementTimeoutSeconds { get; set; }
        public int DelayAfterActionMs { get; set; }
        public int ResponsivenessRetries { get; set; }
        public int ResponsivenessRetryDelayMs { get; set; }
        public int MetricsIntervalMs { get; set; }
        public bool CaptureScreenshotOnEveryStep { get; set; }
        public bool CaptureScreenshotOnFailure { get; set; }
        public bool DumpUiTreeAtStartup { get; set; }
        public bool TestSingleInstanceRestore { get; set; }
        public bool CloseApplicationAtEnd { get; set; }
        public bool ForceKillOnCleanup { get; set; }
        public double MaxWorkingSetGrowthMb { get; set; }
        public int MaxHandleGrowth { get; set; }
        public int MaxThreadGrowth { get; set; }

        public ExecutionConfiguration()
        {
            Cycles = 25;
            ElementTimeoutSeconds = 10;
            DelayAfterActionMs = 700;
            ResponsivenessRetries = 3;
            ResponsivenessRetryDelayMs = 1000;
            MetricsIntervalMs = 1000;
            CaptureScreenshotOnEveryStep = false;
            CaptureScreenshotOnFailure = true;
            DumpUiTreeAtStartup = true;
            TestSingleInstanceRestore = true;
            CloseApplicationAtEnd = true;
            ForceKillOnCleanup = false;
            MaxWorkingSetGrowthMb = 150;
            MaxHandleGrowth = 250;
            MaxThreadGrowth = 40;
        }
    }

    public class UiSelectorConfiguration
    {
        [XmlAttribute]
        public string AutomationId { get; set; }

        [XmlAttribute]
        public string Names { get; set; }

        [XmlAttribute]
        public string ControlType { get; set; }

        [XmlAttribute]
        public int TimeoutSeconds { get; set; }

        public UiSelectorConfiguration()
        {
            TimeoutSeconds = 0;
        }

        public bool IsEmpty()
        {
            return string.IsNullOrWhiteSpace(AutomationId) && string.IsNullOrWhiteSpace(Names);
        }

        public override string ToString()
        {
            return "AutomationId='" + (AutomationId ?? string.Empty) +
                   "', Names='" + (Names ?? string.Empty) +
                   "', ControlType='" + (ControlType ?? string.Empty) + "'";
        }
    }

    public sealed class NavigationActionConfiguration : UiSelectorConfiguration
    {
        [XmlAttribute]
        public string Name { get; set; }

        [XmlAttribute]
        public bool ExpectSecondaryWindow { get; set; }

        [XmlAttribute]
        public bool AutoCloseSecondaryWindow { get; set; }

        [XmlElement("ExpectedVisible")]
        public UiSelectorConfiguration ExpectedVisible { get; set; }

        [XmlElement("Close")]
        public UiSelectorConfiguration Close { get; set; }

        public NavigationActionConfiguration()
        {
            ExpectSecondaryWindow = false;
            AutoCloseSecondaryWindow = true;
            ExpectedVisible = new UiSelectorConfiguration();
            Close = new UiSelectorConfiguration();
        }
    }
}
