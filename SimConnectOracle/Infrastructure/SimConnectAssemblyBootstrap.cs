using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace SimVoiceCopilot.QA.SimConnectOracle.Infrastructure
{
    internal static class SimConnectAssemblyBootstrap
    {
        private const string SimConnectAssemblySimpleName = "Microsoft.FlightSimulator.SimConnect";
        private static bool initialized;
        private static string resolvedAssemblyPath;
        private static string initializationError;

        public static string ResolvedAssemblyPath { get { return resolvedAssemblyPath ?? string.Empty; } }
        public static string InitializationError { get { return initializationError ?? string.Empty; } }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool SetDllDirectory(string lpPathName);

        public static void Initialize()
        {
            if (initialized) return;
            initialized = true;
            AppDomain.CurrentDomain.AssemblyResolve += ResolveAssembly;

            try
            {
                string candidate = FindManagedAssembly();
                if (string.IsNullOrWhiteSpace(candidate))
                {
                    initializationError = "Microsoft.FlightSimulator.SimConnect.dll was not found beside the Oracle executable or in SIMVOICE_QA_SIMCONNECT_MANAGED.";
                    return;
                }

                candidate = Path.GetFullPath(candidate);
                string directory = Path.GetDirectoryName(candidate);
                if (!string.IsNullOrWhiteSpace(directory))
                {
                    SetDllDirectory(directory);
                }

                // Preload through LoadFrom so the CLR binds subsequent SimConnect references
                // to the exact runtime file selected by the PowerShell launcher.
                Assembly assembly = Assembly.LoadFrom(candidate);
                resolvedAssemblyPath = assembly.Location;
            }
            catch (Exception exception)
            {
                initializationError = exception.ToString();
            }
        }

        private static Assembly ResolveAssembly(object sender, ResolveEventArgs args)
        {
            AssemblyName requested;
            try
            {
                requested = new AssemblyName(args.Name);
            }
            catch
            {
                return null;
            }

            if (!string.Equals(requested.Name, SimConnectAssemblySimpleName, StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }

            string candidate = FindManagedAssembly();
            if (string.IsNullOrWhiteSpace(candidate) || !File.Exists(candidate))
            {
                return null;
            }

            try
            {
                Assembly assembly = Assembly.LoadFrom(candidate);
                resolvedAssemblyPath = assembly.Location;
                return assembly;
            }
            catch (Exception exception)
            {
                initializationError = exception.ToString();
                return null;
            }
        }

        private static string FindManagedAssembly()
        {
            List<string> candidates = new List<string>();
            string explicitPath = Environment.GetEnvironmentVariable("SIMVOICE_QA_SIMCONNECT_MANAGED");
            if (!string.IsNullOrWhiteSpace(explicitPath))
            {
                candidates.Add(Environment.ExpandEnvironmentVariables(explicitPath));
            }

            string executableDirectory = AppDomain.CurrentDomain.BaseDirectory;
            candidates.Add(Path.Combine(executableDirectory, "Microsoft.FlightSimulator.SimConnect.dll"));

            foreach (string candidate in candidates)
            {
                if (!string.IsNullOrWhiteSpace(candidate) && File.Exists(candidate))
                {
                    return candidate;
                }
            }

            return null;
        }
    }
}
