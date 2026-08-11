using System;
using System.Globalization;
using System.IO;
using System.Threading;
using System.Reflection;
using System.Runtime.CompilerServices;
using SimVoiceCopilot.QA.SimConnectOracle.Infrastructure;
using SimVoiceCopilot.QA.SimConnectOracle.Oracle;
using SimVoiceCopilot.QA.SimConnectOracle.Reporting;

namespace SimVoiceCopilot.QA.SimConnectOracle
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            // Must run before any SimConnect-dependent type is instantiated.
            SimConnectAssemblyBootstrap.Initialize();
            return RunMain(args);
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static int RunMain(string[] args)
        {
            CommandLineOptions options;
            try
            {
                options = CommandLineOptions.Parse(args);
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine("Invalid arguments: " + exception.Message);
                CommandLineOptions.PrintHelp();
                return 2;
            }

            if (options.ShowHelp)
            {
                CommandLineOptions.PrintHelp();
                return 0;
            }

            if (options.ListVariables)
            {
                foreach (string name in OracleVariableCatalog.Names) Console.WriteLine(name);
                return 0;
            }

            string timestamp = DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
            string outputDirectory = options.OutputDirectory;
            if (string.IsNullOrWhiteSpace(outputDirectory))
            {
                outputDirectory = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "SimVoiceCopilot",
                    "QA",
                    "FlightOracle",
                    "ORACLE-" + timestamp + "-" + options.Mode);
            }

            outputDirectory = Path.GetFullPath(Environment.ExpandEnvironmentVariables(outputDirectory));
            Directory.CreateDirectory(outputDirectory);

            OracleReport report = new OracleReport
            {
                RunId = "ORACLE-" + timestamp,
                Mode = options.Mode.ToString(),
                StartedAtLocal = DateTimeOffset.Now,
                MachineName = Environment.MachineName,
                UserName = Environment.UserName,
                OperatingSystem = Environment.OSVersion.ToString(),
                FrameworkVersion = Environment.Version.ToString(),
                OutputDirectory = outputDirectory,
                Variable = options.Variable,
                Expected = options.Expected,
                Tolerance = options.Tolerance
            };

            int exitCode = 1;
            using (OracleLogger logger = new OracleLogger(Path.Combine(outputDirectory, "oracle-run.log")))
            {
                logger.Info("SimVoice Copilot QA Phase 2.1.1 — SimConnect Oracle");
                logger.Info("Mode: " + options.Mode);
                logger.Info("Output: " + outputDirectory);
                logger.Info("Process architecture: " + (Environment.Is64BitProcess ? "x64" : "x86"));
                logger.Info("Executable directory: " + AppDomain.CurrentDomain.BaseDirectory);
                logger.Info("SimConnect managed assembly: " +
                    (string.IsNullOrWhiteSpace(SimConnectAssemblyBootstrap.ResolvedAssemblyPath)
                        ? "NOT PRELOADED"
                        : SimConnectAssemblyBootstrap.ResolvedAssemblyPath));

                if (!string.IsNullOrWhiteSpace(SimConnectAssemblyBootstrap.InitializationError))
                {
                    logger.Warn("SimConnect bootstrap diagnostic: " + SimConnectAssemblyBootstrap.InitializationError);
                }

                try
                {
                    using (SimConnectOracleClient client = new SimConnectOracleClient(logger))
                    {
                        TimeSpan requestTimeout = TimeSpan.FromSeconds(options.TimeoutSeconds);
                        client.Connect(requestTimeout);

                        switch (options.Mode)
                        {
                            case OracleMode.Probe:
                                exitCode = RunProbe(client, options, report, logger, requestTimeout);
                                break;
                            case OracleMode.Snapshot:
                                exitCode = RunSnapshot(client, options, report, logger, requestTimeout);
                                break;
                            case OracleMode.Watch:
                                exitCode = RunWatch(client, options, report, logger, requestTimeout);
                                break;
                            case OracleMode.Assert:
                                exitCode = RunAssert(client, options, report, logger, requestTimeout);
                                break;
                            case OracleMode.Wait:
                                exitCode = RunWait(client, options, report, logger, requestTimeout);
                                break;
                            default:
                                throw new InvalidOperationException("Unsupported mode: " + options.Mode);
                        }
                    }
                }
                catch (Exception exception)
                {
                    report.Error = exception.ToString();
                    report.Message = exception.Message;
                    logger.Error("SimConnect Oracle failed.", exception);
                    exitCode = 1;
                }
                finally
                {
                    report.FinishedAtLocal = DateTimeOffset.Now;
                    report.Success = exitCode == 0;
                    try
                    {
                        OracleReportWriter.WriteAll(report, outputDirectory);
                        logger.Info("HTML report: " + Path.Combine(outputDirectory, "oracle-report.html"));
                        logger.Info("JSON report: " + Path.Combine(outputDirectory, "oracle-report.json"));
                        logger.Info("CSV snapshots: " + Path.Combine(outputDirectory, "oracle-snapshots.csv"));
                    }
                    catch (Exception reportException)
                    {
                        logger.Error("Could not write Oracle reports.", reportException);
                        exitCode = 1;
                    }
                }
            }

            Console.WriteLine();
            Console.WriteLine(exitCode == 0 ? "ORACLE RESULT: PASS" : "ORACLE RESULT: FAIL");
            Console.WriteLine("Results: " + outputDirectory);
            return exitCode;
        }

        private static int RunProbe(
            SimConnectOracleClient client,
            CommandLineOptions options,
            OracleReport report,
            OracleLogger logger,
            TimeSpan timeout)
        {
            OracleSnapshot snapshot = client.ReadSnapshot(timeout);
            report.Snapshots.Add(snapshot);
            logger.Info(Environment.NewLine + snapshot.ToConsoleText());

            if (!options.AllowMenu && !snapshot.FlightActive)
            {
                report.Message = "SimConnect is connected, but MSFS is in its UI and no active flight is under user control.";
                logger.Error(report.Message);
                return 1;
            }

            if (string.IsNullOrWhiteSpace(snapshot.AircraftTitle))
            {
                report.Message = "SimConnect responded, but the user aircraft title is empty.";
                logger.Error(report.Message);
                return 1;
            }

            report.Message = "SimConnect connected and returned a valid user-aircraft snapshot.";
            logger.Info(report.Message);
            return 0;
        }

        private static int RunSnapshot(
            SimConnectOracleClient client,
            CommandLineOptions options,
            OracleReport report,
            OracleLogger logger,
            TimeSpan timeout)
        {
            OracleSnapshot snapshot = client.ReadSnapshot(timeout);
            report.Snapshots.Add(snapshot);
            logger.Info(Environment.NewLine + snapshot.ToConsoleText());

            if (!options.AllowMenu && !snapshot.FlightActive)
            {
                report.Message = "Snapshot was read, but MSFS does not currently have an active flight.";
                return 1;
            }

            report.Message = "One complete SimConnect snapshot was captured.";
            return 0;
        }

        private static int RunWatch(
            SimConnectOracleClient client,
            CommandLineOptions options,
            OracleReport report,
            OracleLogger logger,
            TimeSpan timeout)
        {
            DateTime deadline = DateTime.UtcNow.AddSeconds(options.DurationSeconds);
            while (DateTime.UtcNow < deadline)
            {
                OracleSnapshot snapshot = client.ReadSnapshot(timeout);
                report.Snapshots.Add(snapshot);
                logger.Info(string.Format(
                    CultureInfo.InvariantCulture,
                    "Snapshot {0}: flight={1}, headingBug={2:F1}, altitude={3:F0}, vs={4:F0}, xpdr={5:0000}",
                    report.Snapshots.Count,
                    snapshot.FlightActive,
                    snapshot.HeadingBugDegrees,
                    snapshot.SelectedAltitudeFeet,
                    snapshot.SelectedVerticalSpeedFpm,
                    snapshot.TransponderCode));

                if (!options.AllowMenu && !snapshot.FlightActive)
                {
                    report.Message = "MSFS left the active flight during Watch mode.";
                    return 1;
                }

                Thread.Sleep(options.IntervalMs);
            }

            report.Message = report.Snapshots.Count + " SimConnect snapshots captured without losing the active flight.";
            return 0;
        }

        private static int RunAssert(
            SimConnectOracleClient client,
            CommandLineOptions options,
            OracleReport report,
            OracleLogger logger,
            TimeSpan timeout)
        {
            OracleSnapshot snapshot = client.ReadSnapshot(timeout);
            report.Snapshots.Add(snapshot);
            if (!options.AllowMenu && !snapshot.FlightActive)
            {
                report.Message = "MSFS does not currently have an active flight.";
                return 1;
            }

            OracleAssertionResult assertion = OracleVariableCatalog.Assert(snapshot, options.Variable, options.Expected, options.Tolerance);
            report.Assertion = assertion;
            report.Message = assertion.Message;
            logger.Info(string.Format(
                CultureInfo.InvariantCulture,
                "ASSERT {0}: expected={1}, observed={2}, tolerance={3}, difference={4} => {5}",
                assertion.Variable,
                assertion.Expected,
                assertion.Observed,
                assertion.Tolerance,
                assertion.Difference,
                assertion.Passed ? "PASS" : "FAIL"));
            return assertion.Passed ? 0 : 1;
        }

        private static int RunWait(
            SimConnectOracleClient client,
            CommandLineOptions options,
            OracleReport report,
            OracleLogger logger,
            TimeSpan requestTimeout)
        {
            DateTime deadline = DateTime.UtcNow.AddSeconds(options.TimeoutSeconds);
            OracleAssertionResult latestAssertion = null;

            while (DateTime.UtcNow < deadline)
            {
                OracleSnapshot snapshot = client.ReadSnapshot(requestTimeout);
                report.Snapshots.Add(snapshot);

                if (!options.AllowMenu && !snapshot.FlightActive)
                {
                    report.Message = "MSFS left the active flight while waiting for the expected value.";
                    return 1;
                }

                latestAssertion = OracleVariableCatalog.Assert(snapshot, options.Variable, options.Expected, options.Tolerance);
                report.Assertion = latestAssertion;
                logger.Info(string.Format(
                    CultureInfo.InvariantCulture,
                    "WAIT {0}: observed={1}, expected={2}, difference={3}",
                    latestAssertion.Variable,
                    latestAssertion.Observed,
                    latestAssertion.Expected,
                    latestAssertion.Difference));

                if (latestAssertion.Passed)
                {
                    report.Message = "Expected value was observed before the timeout.";
                    return 0;
                }

                Thread.Sleep(options.IntervalMs);
            }

            report.Message = "Timed out before the expected value was observed.";
            return 1;
        }
    }
}
