using System;
using System.Globalization;

namespace SimVoiceCopilot.QA.SimConnectOracle
{
    internal enum OracleMode
    {
        Probe,
        Snapshot,
        Watch,
        Assert,
        Wait
    }

    internal sealed class CommandLineOptions
    {
        public OracleMode Mode { get; private set; }
        public string OutputDirectory { get; private set; }
        public int TimeoutSeconds { get; private set; }
        public int DurationSeconds { get; private set; }
        public int IntervalMs { get; private set; }
        public string Variable { get; private set; }
        public string Expected { get; private set; }
        public double Tolerance { get; private set; }
        public bool AllowMenu { get; private set; }
        public bool ListVariables { get; private set; }
        public bool ShowHelp { get; private set; }

        private CommandLineOptions()
        {
            Mode = OracleMode.Probe;
            TimeoutSeconds = 30;
            DurationSeconds = 60;
            IntervalMs = 1000;
            Tolerance = 0;
        }

        public static CommandLineOptions Parse(string[] args)
        {
            CommandLineOptions options = new CommandLineOptions();
            for (int index = 0; index < args.Length; index++)
            {
                string current = args[index];
                switch (current.ToLowerInvariant())
                {
                    case "--mode":
                        OracleMode mode;
                        if (!Enum.TryParse(ReadValue(args, ref index, current), true, out mode))
                        {
                            throw new ArgumentException("--mode must be Probe, Snapshot, Watch, Assert, or Wait.");
                        }
                        options.Mode = mode;
                        break;
                    case "--output":
                        options.OutputDirectory = ReadValue(args, ref index, current);
                        break;
                    case "--timeout-seconds":
                        options.TimeoutSeconds = ParsePositiveInt(ReadValue(args, ref index, current), current);
                        break;
                    case "--duration-seconds":
                        options.DurationSeconds = ParsePositiveInt(ReadValue(args, ref index, current), current);
                        break;
                    case "--interval-ms":
                        options.IntervalMs = ParsePositiveInt(ReadValue(args, ref index, current), current);
                        break;
                    case "--variable":
                        options.Variable = ReadValue(args, ref index, current);
                        break;
                    case "--expected":
                        options.Expected = ReadValue(args, ref index, current);
                        break;
                    case "--tolerance":
                        double tolerance;
                        if (!double.TryParse(ReadValue(args, ref index, current), NumberStyles.Float, CultureInfo.InvariantCulture, out tolerance) || tolerance < 0)
                        {
                            throw new ArgumentException("--tolerance must be a non-negative number using '.' as decimal separator.");
                        }
                        options.Tolerance = tolerance;
                        break;
                    case "--allow-menu":
                        options.AllowMenu = true;
                        break;
                    case "--list-variables":
                        options.ListVariables = true;
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

            if ((options.Mode == OracleMode.Assert || options.Mode == OracleMode.Wait) &&
                (string.IsNullOrWhiteSpace(options.Variable) || options.Expected == null))
            {
                throw new ArgumentException("Assert and Wait modes require --variable and --expected.");
            }

            return options;
        }

        public static void PrintHelp()
        {
            Console.WriteLine("SimVoiceCopilot.QA.SimConnectOracle.exe [options]");
            Console.WriteLine();
            Console.WriteLine("  --mode <Probe|Snapshot|Watch|Assert|Wait>");
            Console.WriteLine("  --output <folder>");
            Console.WriteLine("  --timeout-seconds <number>");
            Console.WriteLine("  --duration-seconds <number>    Watch mode duration.");
            Console.WriteLine("  --interval-ms <number>         Watch/Wait polling interval.");
            Console.WriteLine("  --variable <name>              Assert/Wait variable.");
            Console.WriteLine("  --expected <value>             Assert/Wait expected value.");
            Console.WriteLine("  --tolerance <number>           Numeric tolerance.");
            Console.WriteLine("  --allow-menu                   Do not fail when MSFS is in its UI instead of an active flight.");
            Console.WriteLine("  --list-variables               Print supported variable names.");
            Console.WriteLine("  --help");
        }

        private static string ReadValue(string[] args, ref int index, string argument)
        {
            if (index + 1 >= args.Length) throw new ArgumentException("Missing value for " + argument);
            index++;
            return args[index];
        }

        private static int ParsePositiveInt(string text, string argument)
        {
            int value;
            if (!int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out value) || value < 1)
            {
                throw new ArgumentException(argument + " must be a positive integer.");
            }
            return value;
        }
    }
}
