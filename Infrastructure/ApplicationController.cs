using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using SimVoiceCopilot.QA.Configuration;

namespace SimVoiceCopilot.QA.Infrastructure
{
    internal sealed class ApplicationController
    {
        private readonly ApplicationConfiguration configuration;
        private readonly Logger logger;

        public ApplicationController(ApplicationConfiguration configuration, Logger logger)
        {
            this.configuration = configuration;
            this.logger = logger;
        }

        public Process StartOrAttach()
        {
            Process existing = FindNewestProcess();
            if (existing != null && configuration.AttachIfRunning)
            {
                logger.Info("Attached to existing process PID " + existing.Id + ".");
                Restore(existing);
                return existing;
            }

            LaunchMode launchMode = (LaunchMode)Enum.Parse(typeof(LaunchMode), configuration.LaunchMode, true);
            if (launchMode == LaunchMode.AttachOnly)
            {
                if (existing == null)
                {
                    throw new InvalidOperationException(
                        "AttachOnly was configured, but process '" + configuration.ProcessName + "' is not running.");
                }

                return existing;
            }

            DateTime launchStartedAt = DateTime.Now;
            if (launchMode == LaunchMode.Executable)
            {
                ProcessStartInfo startInfo = new ProcessStartInfo
                {
                    FileName = configuration.ExecutablePath,
                    Arguments = configuration.LaunchArguments ?? string.Empty,
                    UseShellExecute = true,
                    WorkingDirectory = ResolveWorkingDirectory()
                };

                logger.Info("Launching executable: " + startInfo.FileName);
                Process.Start(startInfo);
            }
            else
            {
                string shellTarget = "shell:AppsFolder\\" + configuration.PackagedAppId;
                logger.Info("Launching packaged app: " + shellTarget);
                Process.Start(new ProcessStartInfo
                {
                    FileName = "explorer.exe",
                    Arguments = shellTarget,
                    UseShellExecute = true
                });
            }

            Process process = WaitForProcess(launchStartedAt, TimeSpan.FromSeconds(configuration.StartupTimeoutSeconds));
            logger.Info("Process started. PID " + process.Id + ".");
            Restore(process);
            return process;
        }

        public void LaunchAdditionalInstance()
        {
            LaunchMode launchMode = (LaunchMode)Enum.Parse(typeof(LaunchMode), configuration.LaunchMode, true);
            if (launchMode == LaunchMode.AttachOnly)
            {
                throw new InvalidOperationException(
                    "The single-instance restore regression cannot launch an additional instance in AttachOnly mode.");
            }

            if (launchMode == LaunchMode.Executable)
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = configuration.ExecutablePath,
                    Arguments = configuration.LaunchArguments ?? string.Empty,
                    UseShellExecute = true,
                    WorkingDirectory = ResolveWorkingDirectory()
                });
                logger.Info("Launched an additional executable instance to request restoration of the existing window.");
                return;
            }

            string shellTarget = "shell:AppsFolder\\" + configuration.PackagedAppId;
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = shellTarget,
                UseShellExecute = true
            });
            logger.Info("Launched the packaged app again to request restoration of the existing window.");
        }

        public bool RequestShutdown(Process process)
        {
            if (process == null || HasExited(process))
            {
                return true;
            }

            try
            {
                logger.Info("Requesting application shutdown through the main window.");
                bool requested = process.CloseMainWindow();
                if (!requested)
                {
                    logger.Warn("CloseMainWindow returned false.");
                }
            }
            catch (Exception ex)
            {
                logger.Warn("CloseMainWindow failed: " + ex.Message);
            }

            return WaitForExit(process, TimeSpan.FromSeconds(configuration.ShutdownTimeoutSeconds));
        }

        public bool WaitForExit(Process process, TimeSpan timeout)
        {
            if (process == null || HasExited(process))
            {
                return true;
            }

            try
            {
                return process.WaitForExit((int)timeout.TotalMilliseconds);
            }
            catch
            {
                return HasExited(process);
            }
        }

        public void Cleanup(Process process, bool forceKill)
        {
            if (process == null || HasExited(process) || !forceKill)
            {
                return;
            }

            try
            {
                logger.Warn("Force-killing process PID " + process.Id + " during cleanup.");
                process.Kill();
                process.WaitForExit(5000);
            }
            catch (Exception ex)
            {
                logger.Warn("Cleanup kill failed: " + ex.Message);
            }
        }

        private Process WaitForProcess(DateTime launchStartedAt, TimeSpan timeout)
        {
            DateTime deadline = DateTime.Now.Add(timeout);
            while (DateTime.Now < deadline)
            {
                Process candidate = FindNewestProcess();
                if (candidate != null)
                {
                    try
                    {
                        if (candidate.StartTime >= launchStartedAt.AddSeconds(-2))
                        {
                            return candidate;
                        }
                    }
                    catch
                    {
                        return candidate;
                    }
                }

                Thread.Sleep(250);
            }

            throw new TimeoutException(
                "Process '" + configuration.ProcessName + "' did not start within " +
                timeout.TotalSeconds.ToString("0") + " seconds.");
        }

        private Process FindNewestProcess()
        {
            string processName = Path.GetFileNameWithoutExtension(configuration.ProcessName);
            return Process.GetProcessesByName(processName)
                .OrderByDescending(GetSafeStartTime)
                .FirstOrDefault();
        }

        private static DateTime GetSafeStartTime(Process process)
        {
            try
            {
                return process.StartTime;
            }
            catch
            {
                return DateTime.MinValue;
            }
        }

        private string ResolveWorkingDirectory()
        {
            if (!string.IsNullOrWhiteSpace(configuration.WorkingDirectory))
            {
                string value = Environment.ExpandEnvironmentVariables(configuration.WorkingDirectory);
                if (Directory.Exists(value))
                {
                    return value;
                }
            }

            return Path.GetDirectoryName(configuration.ExecutablePath);
        }

        private static void Restore(Process process)
        {
            try
            {
                process.Refresh();
                if (process.MainWindowHandle != IntPtr.Zero)
                {
                    NativeMethods.ShowWindowAsync(process.MainWindowHandle, NativeMethods.SwRestore);
                    NativeMethods.SetForegroundWindow(process.MainWindowHandle);
                }
            }
            catch
            {
            }
        }

        private static bool HasExited(Process process)
        {
            try
            {
                return process.HasExited;
            }
            catch
            {
                return true;
            }
        }
    }
}
