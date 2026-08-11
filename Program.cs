using System;
using System.Collections.Generic;
using System.IO;
using SimVoiceCopilot.QA.Configuration;
using SimVoiceCopilot.QA.Infrastructure;
using SimVoiceCopilot.QA.Reporting;
using SimVoiceCopilot.QA.Tests;

namespace SimVoiceCopilot.QA
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            CommandLineOptions options;
            try
            {
                options = CommandLineOptions.Parse(args);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("Invalid arguments: " + ex.Message);
                CommandLineOptions.PrintHelp();
                return 2;
            }

            if (options.ShowHelp)
            {
                CommandLineOptions.PrintHelp();
                return 0;
            }

            string configPath = Path.GetFullPath(options.ConfigPath);
            if (!File.Exists(configPath))
            {
                Console.Error.WriteLine("Configuration file not found: " + configPath);
                return 2;
            }

            QaConfiguration configuration;
            try
            {
                configuration = QaConfiguration.Load(configPath);
                configuration.ApplyOverrides(options);
                configuration.ResolvePaths(Path.GetDirectoryName(configPath));
                configuration.Validate();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("Configuration error: " + ex.Message);
                return 2;
            }

            string timestamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");
            string outputRoot = options.OutputDirectory;
            if (string.IsNullOrWhiteSpace(outputRoot))
            {
                outputRoot = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "SimVoiceCopilot",
                    "QA",
                    "Runs",
                    "QA-" + timestamp);
            }

            outputRoot = Path.GetFullPath(Environment.ExpandEnvironmentVariables(outputRoot));
            Directory.CreateDirectory(outputRoot);

            using (Logger logger = new Logger(Path.Combine(outputRoot, "qa-run.log")))
            {
                logger.Info("SimVoice Copilot QA Phase 1");
                logger.Info("Configuration: " + configPath);
                logger.Info("Output: " + outputRoot);

                QaReport report = new QaReport
                {
                    RunId = "QA-" + timestamp,
                    StartedAtLocal = DateTimeOffset.Now,
                    MachineName = Environment.MachineName,
                    UserName = Environment.UserName,
                    OperatingSystem = Environment.OSVersion.ToString(),
                    FrameworkVersion = Environment.Version.ToString(),
                    ConfigurationPath = configPath,
                    OutputDirectory = outputRoot
                };

                int exitCode = 1;
                try
                {
                    QaTestRunner runner = new QaTestRunner(configuration, report, outputRoot, logger);
                    exitCode = runner.Run(options.DiagnoseUiOnly) ? 0 : 1;
                }
                catch (Exception ex)
                {
                    logger.Error("Unhandled QA runner failure.", ex);
                    report.FatalError = ex.ToString();
                    exitCode = 1;
                }
                finally
                {
                    report.FinishedAtLocal = DateTimeOffset.Now;
                    report.Success = exitCode == 0;

                    try
                    {
                        ReportWriter.WriteAll(report, outputRoot);
                        logger.Info("HTML report: " + Path.Combine(outputRoot, "report.html"));
                        logger.Info("JSON report: " + Path.Combine(outputRoot, "results.json"));
                    }
                    catch (Exception reportException)
                    {
                        logger.Error("Could not write one or more reports.", reportException);
                        exitCode = 1;
                    }
                }

                Console.WriteLine();
                Console.WriteLine(exitCode == 0 ? "QA RESULT: PASS" : "QA RESULT: FAIL");
                Console.WriteLine("Results: " + outputRoot);
                return exitCode;
            }
        }
    }

    internal sealed class CommandLineOptions
    {
        public string ConfigPath { get; private set; }
        public string OutputDirectory { get; private set; }
        public int? Cycles { get; private set; }
        public bool? CloseApplicationAtEnd { get; private set; }
        public bool DiagnoseUiOnly { get; private set; }
        public bool? VoiceChecklistsEnabled { get; private set; }
        public string VoiceChecklistSuite { get; private set; }
        public bool ShowHelp { get; private set; }

        private CommandLineOptions()
        {
            ConfigPath = "qa.config.xml";
        }

        public static CommandLineOptions Parse(string[] args)
        {
            CommandLineOptions options = new CommandLineOptions();
            for (int i = 0; i < args.Length; i++)
            {
                string current = args[i];
                switch (current.ToLowerInvariant())
                {
                    case "--config":
                        options.ConfigPath = ReadValue(args, ref i, current);
                        break;
                    case "--output":
                        options.OutputDirectory = ReadValue(args, ref i, current);
                        break;
                    case "--cycles":
                        int cycles;
                        if (!int.TryParse(ReadValue(args, ref i, current), out cycles) || cycles < 1)
                        {
                            throw new ArgumentException("--cycles must be a positive integer.");
                        }
                        options.Cycles = cycles;
                        break;
                    case "--no-close":
                        options.CloseApplicationAtEnd = false;
                        break;
                    case "--diagnose-ui":
                        options.DiagnoseUiOnly = true;
                        break;
                    case "--voice-checklists":
                        options.VoiceChecklistsEnabled = true;
                        break;
                    case "--checklist-suite":
                        options.VoiceChecklistsEnabled = true;
                        options.VoiceChecklistSuite = ReadValue(args, ref i, current);
                        break;
                    case "--help":
                    case "-h":
                    case "/?":
                        options.ShowHelp = true;
                        break;
                    default:
                        throw new ArgumentException("Unknown argument: " + current);
                }
            }

            return options;
        }

        public static void PrintHelp()
        {
            Console.WriteLine("SimVoiceCopilot.QA.exe [options]");
            Console.WriteLine();
            Console.WriteLine("  --config <path>     XML configuration file.");
            Console.WriteLine("  --output <path>     Output folder for reports and screenshots.");
            Console.WriteLine("  --cycles <number>   Override configured stress cycles.");
            Console.WriteLine("  --diagnose-ui       Launch/attach and only dump the UI Automation tree.");
            Console.WriteLine("  --voice-checklists  Run the Voice Checklists end-to-end suite.");
            Console.WriteLine("  --checklist-suite   Auto, SmokeEN, CoreEN, SmokeES, or CoreES.");
            Console.WriteLine("  --no-close          Leave SimVoice Copilot running after the test.");
            Console.WriteLine("  --help              Show this help.");
        }

        private static string ReadValue(string[] args, ref int index, string argument)
        {
            if (index + 1 >= args.Length)
            {
                throw new ArgumentException("Missing value for " + argument);
            }

            index++;
            return args[index];
        }
    }
}
