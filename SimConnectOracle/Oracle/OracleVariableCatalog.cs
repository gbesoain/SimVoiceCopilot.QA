using System;
using System.Collections.Generic;
using System.Globalization;

namespace SimVoiceCopilot.QA.SimConnectOracle.Oracle
{
    internal static class OracleVariableCatalog
    {
        private static readonly HashSet<string> AngularVariables = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "HeadingBug",
            "PlaneHeading",
            "WindDirection"
        };

        public static readonly string[] Names =
        {
            "Connected",
            "FlightActive",
            "DialogMode",
            "SimulatorApplication",
            "AircraftLoadedPath",
            "FlightLoadedPath",
            "AircraftTitle",
            "AtcModel",
            "OnGround",
            "PlaneAltitude",
            "IndicatedAltitude",
            "PlaneHeading",
            "AutopilotAvailable",
            "AutopilotMaster",
            "HeadingHold",
            "HeadingBug",
            "AltitudeHold",
            "SelectedAltitude",
            "VerticalSpeedHold",
            "SelectedVerticalSpeed",
            "Transponder",
            "TransponderRawBcd16",
            "ParkingBrake",
            "GearHandle",
            "FlapsHandleIndex",
            "FuelGallons",
            "WindDirection",
            "WindSpeed",
            "GroundSpeed",
            "SimulationRate",
            "ActualVerticalSpeed",
            "IndicatedAirspeed",
            "TrueAirspeed",
            "AmbientTemperature",
            "AircraftAgl",
            "EngineRpm1",
            "EngineRpm2",
            "FuelLeftMain",
            "FuelRightMain",
            "LandingLight",
            "BeaconLight",
            "NavLight",
            "TaxiLight",
            "StrobeLight",
            "MasterBattery",
            "AvionicsMaster"
        };

        public static OracleAssertionResult Assert(
            OracleSnapshot snapshot,
            string variable,
            string expectedText,
            double tolerance)
        {
            if (snapshot == null) throw new ArgumentNullException("snapshot");
            if (string.IsNullOrWhiteSpace(variable)) throw new ArgumentException("Variable is required.");

            object observed;
            if (!snapshot.ToVariableDictionary().TryGetValue(variable, out observed))
            {
                throw new ArgumentException("Unknown Oracle variable: " + variable);
            }

            OracleAssertionResult result = new OracleAssertionResult
            {
                Variable = variable,
                Expected = expectedText,
                Observed = Convert.ToString(observed, CultureInfo.InvariantCulture),
                Tolerance = tolerance
            };

            if (observed is bool)
            {
                bool expectedBool;
                if (!TryParseBoolean(expectedText, out expectedBool))
                {
                    throw new ArgumentException("Expected value for " + variable + " must be true/false or 1/0.");
                }

                result.Passed = (bool)observed == expectedBool;
                result.Difference = result.Passed ? 0 : 1;
            }
            else if (observed is string)
            {
                string expectedString = expectedText ?? string.Empty;
                result.Passed = string.Equals((string)observed, expectedString, StringComparison.OrdinalIgnoreCase);
                result.Difference = result.Passed ? 0 : 1;
            }
            else
            {
                double observedNumber = Convert.ToDouble(observed, CultureInfo.InvariantCulture);
                double expectedNumber;
                if (!double.TryParse(expectedText, NumberStyles.Float, CultureInfo.InvariantCulture, out expectedNumber))
                {
                    throw new ArgumentException("Expected value for " + variable + " must be numeric and use '.' as decimal separator.");
                }

                double difference = AngularVariables.Contains(variable)
                    ? AngularDifference(observedNumber, expectedNumber)
                    : Math.Abs(observedNumber - expectedNumber);

                result.Difference = difference;
                result.Passed = difference <= tolerance;
            }

            result.Message = result.Passed
                ? "Observed value is within the configured tolerance."
                : "Observed value does not match the expected value.";

            return result;
        }

        private static bool TryParseBoolean(string text, out bool value)
        {
            if (bool.TryParse(text, out value)) return true;
            if (string.Equals(text, "1", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(text, "on", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(text, "yes", StringComparison.OrdinalIgnoreCase))
            {
                value = true;
                return true;
            }

            if (string.Equals(text, "0", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(text, "off", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(text, "no", StringComparison.OrdinalIgnoreCase))
            {
                value = false;
                return true;
            }

            value = false;
            return false;
        }

        private static double AngularDifference(double observed, double expected)
        {
            double a = OracleSnapshot.NormalizeHeading(observed);
            double b = OracleSnapshot.NormalizeHeading(expected);
            double difference = Math.Abs(a - b);
            return Math.Min(difference, 360.0 - difference);
        }
    }

    public sealed class OracleAssertionResult
    {
        public string Variable { get; set; }
        public string Expected { get; set; }
        public string Observed { get; set; }
        public double Tolerance { get; set; }
        public double Difference { get; set; }
        public bool Passed { get; set; }
        public string Message { get; set; }
    }
}
