using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;

namespace SimVoiceCopilot.QA.SimConnectOracle.Oracle
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi, Pack = 1)]
    internal struct SimConnectFlightData
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string Title;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string AtcModel;

        public double SimOnGround;
        public double PlaneAltitudeFeet;
        public double IndicatedAltitudeFeet;
        public double PlaneHeadingMagneticDegrees;
        public double AutopilotAvailable;
        public double AutopilotMaster;
        public double AutopilotHeadingLock;
        public double AutopilotHeadingLockDirDegrees;
        public double AutopilotAltitudeLock;
        public double AutopilotAltitudeLockVarFeet;
        public double AutopilotVerticalHold;
        public double AutopilotVerticalHoldVarFpm;
        public double Com1ActiveFrequencyMHz;
        public double Com1StandbyFrequencyMHz;
        public double Com2ActiveFrequencyMHz;
        public double Com2StandbyFrequencyMHz;
        public double Nav1ActiveFrequencyMHz;
        public double Nav1StandbyFrequencyMHz;
        public double Nav2ActiveFrequencyMHz;
        public double Nav2StandbyFrequencyMHz;
        public uint TransponderCodeBcd16;
        public double ParkingBrake;
        public double GearHandlePosition;
        public double FlapsHandleIndex;
        public double FuelTotalQuantityGallons;
        public double AmbientWindDirectionDegrees;
        public double AmbientWindVelocityKnots;
        public double GroundVelocityKnots;
        public double SimulationRate;
        public double ActualVerticalSpeedFpm;
        public double IndicatedAirspeedKnots;
        public double TrueAirspeedKnots;
        public double AmbientTemperatureCelsius;
        public double AircraftAglFeet;
        public double GeneralEngineRpm1;
        public double GeneralEngineRpm2;
        public double FuelLeftMainGallons;
        public double FuelRightMainGallons;
        public double LandingLight;
        public double BeaconLight;
        public double NavLight;
        public double TaxiLight;
        public double StrobeLight;
        public double MasterBattery;
        public double AvionicsMaster;
    }

    public sealed class OracleSnapshot
    {
        public DateTimeOffset TimestampLocal { get; set; }
        public bool Connected { get; set; }
        public bool FlightActive { get; set; }
        public int DialogMode { get; set; }
        public string SimulatorApplication { get; set; }
        public string AircraftLoadedPath { get; set; }
        public string FlightLoadedPath { get; set; }
        public string AircraftTitle { get; set; }
        public string AtcModel { get; set; }
        public bool OnGround { get; set; }
        public double PlaneAltitudeFeet { get; set; }
        public double IndicatedAltitudeFeet { get; set; }
        public double PlaneHeadingMagneticDegrees { get; set; }
        public bool AutopilotAvailable { get; set; }
        public bool AutopilotMaster { get; set; }
        public bool HeadingHold { get; set; }
        public double HeadingBugDegrees { get; set; }
        public bool AltitudeHold { get; set; }
        public double SelectedAltitudeFeet { get; set; }
        public bool VerticalSpeedHold { get; set; }
        public double SelectedVerticalSpeedFpm { get; set; }
        public double Com1ActiveFrequencyMHz { get; set; }
        public double Com1StandbyFrequencyMHz { get; set; }
        public double Com2ActiveFrequencyMHz { get; set; }
        public double Com2StandbyFrequencyMHz { get; set; }
        public double Nav1ActiveFrequencyMHz { get; set; }
        public double Nav1StandbyFrequencyMHz { get; set; }
        public double Nav2ActiveFrequencyMHz { get; set; }
        public double Nav2StandbyFrequencyMHz { get; set; }
        public uint TransponderRawBcd16 { get; set; }
        public int TransponderCode { get; set; }
        public bool ParkingBrake { get; set; }
        public double GearHandlePosition { get; set; }
        public double FlapsHandleIndex { get; set; }
        public double FuelTotalQuantityGallons { get; set; }
        public double WindDirectionDegrees { get; set; }
        public double WindSpeedKnots { get; set; }
        public double GroundSpeedKnots { get; set; }
        public double SimulationRate { get; set; }
        public double ActualVerticalSpeedFpm { get; set; }
        public double IndicatedAirspeedKnots { get; set; }
        public double TrueAirspeedKnots { get; set; }
        public double AmbientTemperatureCelsius { get; set; }
        public double AircraftAglFeet { get; set; }
        public double GeneralEngineRpm1 { get; set; }
        public double GeneralEngineRpm2 { get; set; }
        public double FuelLeftMainGallons { get; set; }
        public double FuelRightMainGallons { get; set; }
        public bool LandingLight { get; set; }
        public bool BeaconLight { get; set; }
        public bool NavLight { get; set; }
        public bool TaxiLight { get; set; }
        public bool StrobeLight { get; set; }
        public bool MasterBattery { get; set; }
        public bool AvionicsMaster { get; set; }

        internal static OracleSnapshot From(
            SimConnectFlightData data,
            SimConnectSystemState state,
            string simulatorApplication)
        {
            return new OracleSnapshot
            {
                TimestampLocal = DateTimeOffset.Now,
                Connected = true,
                FlightActive = state.SimState == 1,
                DialogMode = state.DialogMode,
                SimulatorApplication = simulatorApplication ?? string.Empty,
                AircraftLoadedPath = state.AircraftLoadedPath ?? string.Empty,
                FlightLoadedPath = state.FlightLoadedPath ?? string.Empty,
                AircraftTitle = data.Title ?? string.Empty,
                AtcModel = data.AtcModel ?? string.Empty,
                OnGround = ToBool(data.SimOnGround),
                PlaneAltitudeFeet = data.PlaneAltitudeFeet,
                IndicatedAltitudeFeet = data.IndicatedAltitudeFeet,
                PlaneHeadingMagneticDegrees = NormalizeHeading(data.PlaneHeadingMagneticDegrees),
                AutopilotAvailable = ToBool(data.AutopilotAvailable),
                AutopilotMaster = ToBool(data.AutopilotMaster),
                HeadingHold = ToBool(data.AutopilotHeadingLock),
                HeadingBugDegrees = NormalizeHeading(data.AutopilotHeadingLockDirDegrees),
                AltitudeHold = ToBool(data.AutopilotAltitudeLock),
                SelectedAltitudeFeet = data.AutopilotAltitudeLockVarFeet,
                VerticalSpeedHold = ToBool(data.AutopilotVerticalHold),
                SelectedVerticalSpeedFpm = data.AutopilotVerticalHoldVarFpm,
                Com1ActiveFrequencyMHz = data.Com1ActiveFrequencyMHz,
                Com1StandbyFrequencyMHz = data.Com1StandbyFrequencyMHz,
                Com2ActiveFrequencyMHz = data.Com2ActiveFrequencyMHz,
                Com2StandbyFrequencyMHz = data.Com2StandbyFrequencyMHz,
                Nav1ActiveFrequencyMHz = data.Nav1ActiveFrequencyMHz,
                Nav1StandbyFrequencyMHz = data.Nav1StandbyFrequencyMHz,
                Nav2ActiveFrequencyMHz = data.Nav2ActiveFrequencyMHz,
                Nav2StandbyFrequencyMHz = data.Nav2StandbyFrequencyMHz,
                TransponderRawBcd16 = data.TransponderCodeBcd16,
                TransponderCode = DecodeBcd16(data.TransponderCodeBcd16),
                ParkingBrake = ToBool(data.ParkingBrake),
                GearHandlePosition = data.GearHandlePosition,
                FlapsHandleIndex = data.FlapsHandleIndex,
                FuelTotalQuantityGallons = data.FuelTotalQuantityGallons,
                WindDirectionDegrees = NormalizeHeading(data.AmbientWindDirectionDegrees),
                WindSpeedKnots = data.AmbientWindVelocityKnots,
                GroundSpeedKnots = data.GroundVelocityKnots,
                SimulationRate = data.SimulationRate,
                ActualVerticalSpeedFpm = data.ActualVerticalSpeedFpm,
                IndicatedAirspeedKnots = data.IndicatedAirspeedKnots,
                TrueAirspeedKnots = data.TrueAirspeedKnots,
                AmbientTemperatureCelsius = data.AmbientTemperatureCelsius,
                AircraftAglFeet = data.AircraftAglFeet,
                GeneralEngineRpm1 = data.GeneralEngineRpm1,
                GeneralEngineRpm2 = data.GeneralEngineRpm2,
                FuelLeftMainGallons = data.FuelLeftMainGallons,
                FuelRightMainGallons = data.FuelRightMainGallons,
                LandingLight = ToBool(data.LandingLight),
                BeaconLight = ToBool(data.BeaconLight),
                NavLight = ToBool(data.NavLight),
                TaxiLight = ToBool(data.TaxiLight),
                StrobeLight = ToBool(data.StrobeLight),
                MasterBattery = ToBool(data.MasterBattery),
                AvionicsMaster = ToBool(data.AvionicsMaster)
            };
        }

        public IDictionary<string, object> ToVariableDictionary()
        {
            return new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase)
            {
                { "Connected", Connected },
                { "FlightActive", FlightActive },
                { "DialogMode", DialogMode },
                { "SimulatorApplication", SimulatorApplication },
                { "AircraftLoadedPath", AircraftLoadedPath },
                { "FlightLoadedPath", FlightLoadedPath },
                { "AircraftTitle", AircraftTitle },
                { "AtcModel", AtcModel },
                { "OnGround", OnGround },
                { "PlaneAltitude", PlaneAltitudeFeet },
                { "IndicatedAltitude", IndicatedAltitudeFeet },
                { "PlaneHeading", PlaneHeadingMagneticDegrees },
                { "AutopilotAvailable", AutopilotAvailable },
                { "AutopilotMaster", AutopilotMaster },
                { "HeadingHold", HeadingHold },
                { "HeadingBug", HeadingBugDegrees },
                { "AltitudeHold", AltitudeHold },
                { "SelectedAltitude", SelectedAltitudeFeet },
                { "VerticalSpeedHold", VerticalSpeedHold },
                { "SelectedVerticalSpeed", SelectedVerticalSpeedFpm },
                { "Com1Active", Com1ActiveFrequencyMHz },
                { "Com1Standby", Com1StandbyFrequencyMHz },
                { "Com2Active", Com2ActiveFrequencyMHz },
                { "Com2Standby", Com2StandbyFrequencyMHz },
                { "Nav1Active", Nav1ActiveFrequencyMHz },
                { "Nav1Standby", Nav1StandbyFrequencyMHz },
                { "Nav2Active", Nav2ActiveFrequencyMHz },
                { "Nav2Standby", Nav2StandbyFrequencyMHz },
                { "Transponder", TransponderCode },
                { "TransponderRawBcd16", TransponderRawBcd16 },
                { "ParkingBrake", ParkingBrake },
                { "GearHandle", GearHandlePosition },
                { "FlapsHandleIndex", FlapsHandleIndex },
                { "FuelGallons", FuelTotalQuantityGallons },
                { "WindDirection", WindDirectionDegrees },
                { "WindSpeed", WindSpeedKnots },
                { "GroundSpeed", GroundSpeedKnots },
                { "SimulationRate", SimulationRate },
                { "ActualVerticalSpeed", ActualVerticalSpeedFpm },
                { "IndicatedAirspeed", IndicatedAirspeedKnots },
                { "TrueAirspeed", TrueAirspeedKnots },
                { "AmbientTemperature", AmbientTemperatureCelsius },
                { "AircraftAgl", AircraftAglFeet },
                { "EngineRpm1", GeneralEngineRpm1 },
                { "EngineRpm2", GeneralEngineRpm2 },
                { "FuelLeftMain", FuelLeftMainGallons },
                { "FuelRightMain", FuelRightMainGallons },
                { "LandingLight", LandingLight },
                { "BeaconLight", BeaconLight },
                { "NavLight", NavLight },
                { "TaxiLight", TaxiLight },
                { "StrobeLight", StrobeLight },
                { "MasterBattery", MasterBattery },
                { "AvionicsMaster", AvionicsMaster }
            };
        }

        public string ToConsoleText()
        {
            return string.Join(Environment.NewLine, new[]
            {
                "Simulator          : " + SimulatorApplication,
                "Flight active      : " + FlightActive,
                "Dialog mode        : " + DialogMode,
                "Aircraft title     : " + AircraftTitle,
                "ATC model          : " + AtcModel,
                "On ground          : " + OnGround,
                "Plane altitude     : " + PlaneAltitudeFeet.ToString("F1", CultureInfo.InvariantCulture) + " ft",
                "Indicated altitude : " + IndicatedAltitudeFeet.ToString("F1", CultureInfo.InvariantCulture) + " ft",
                "Plane heading      : " + PlaneHeadingMagneticDegrees.ToString("F1", CultureInfo.InvariantCulture) + " deg",
                "Heading bug        : " + HeadingBugDegrees.ToString("F1", CultureInfo.InvariantCulture) + " deg",
                "Selected altitude  : " + SelectedAltitudeFeet.ToString("F1", CultureInfo.InvariantCulture) + " ft",
                "Selected VS        : " + SelectedVerticalSpeedFpm.ToString("F1", CultureInfo.InvariantCulture) + " ft/min",
                "COM1 active/standby: " + Com1ActiveFrequencyMHz.ToString("F3", CultureInfo.InvariantCulture) + " / " + Com1StandbyFrequencyMHz.ToString("F3", CultureInfo.InvariantCulture) + " MHz",
                "COM2 active/standby: " + Com2ActiveFrequencyMHz.ToString("F3", CultureInfo.InvariantCulture) + " / " + Com2StandbyFrequencyMHz.ToString("F3", CultureInfo.InvariantCulture) + " MHz",
                "NAV1 active/standby: " + Nav1ActiveFrequencyMHz.ToString("F3", CultureInfo.InvariantCulture) + " / " + Nav1StandbyFrequencyMHz.ToString("F3", CultureInfo.InvariantCulture) + " MHz",
                "NAV2 active/standby: " + Nav2ActiveFrequencyMHz.ToString("F3", CultureInfo.InvariantCulture) + " / " + Nav2StandbyFrequencyMHz.ToString("F3", CultureInfo.InvariantCulture) + " MHz",
                "Transponder        : " + TransponderCode.ToString("0000", CultureInfo.InvariantCulture),
                "Autopilot available: " + AutopilotAvailable,
                "Autopilot master   : " + AutopilotMaster,
                "Heading hold       : " + HeadingHold,
                "Altitude hold      : " + AltitudeHold,
                "VS hold            : " + VerticalSpeedHold,
                "Parking brake      : " + ParkingBrake,
                "Gear handle        : " + GearHandlePosition.ToString("F3", CultureInfo.InvariantCulture),
                "Flaps index        : " + FlapsHandleIndex.ToString("F0", CultureInfo.InvariantCulture),
                "Fuel total         : " + FuelTotalQuantityGallons.ToString("F2", CultureInfo.InvariantCulture) + " gal",
                "Wind               : " + WindDirectionDegrees.ToString("F0", CultureInfo.InvariantCulture) + " deg / " + WindSpeedKnots.ToString("F1", CultureInfo.InvariantCulture) + " kt",
                "Ground speed       : " + GroundSpeedKnots.ToString("F1", CultureInfo.InvariantCulture) + " kt",
                "Simulation rate    : " + SimulationRate.ToString("F2", CultureInfo.InvariantCulture),
                "Actual VS          : " + ActualVerticalSpeedFpm.ToString("F1", CultureInfo.InvariantCulture) + " ft/min",
                "Indicated airspeed : " + IndicatedAirspeedKnots.ToString("F1", CultureInfo.InvariantCulture) + " kt",
                "True airspeed      : " + TrueAirspeedKnots.ToString("F1", CultureInfo.InvariantCulture) + " kt",
                "Ambient temp       : " + AmbientTemperatureCelsius.ToString("F1", CultureInfo.InvariantCulture) + " C",
                "Aircraft AGL       : " + AircraftAglFeet.ToString("F1", CultureInfo.InvariantCulture) + " ft",
                "Engine RPM 1       : " + GeneralEngineRpm1.ToString("F0", CultureInfo.InvariantCulture),
                "Engine RPM 2       : " + GeneralEngineRpm2.ToString("F0", CultureInfo.InvariantCulture),
                "Fuel left/right    : " + FuelLeftMainGallons.ToString("F2", CultureInfo.InvariantCulture) + " / " + FuelRightMainGallons.ToString("F2", CultureInfo.InvariantCulture) + " gal",
                "Lights L/B/N/T/S   : " + LandingLight + "/" + BeaconLight + "/" + NavLight + "/" + TaxiLight + "/" + StrobeLight,
                "Battery/avionics   : " + MasterBattery + "/" + AvionicsMaster
            });
        }

        internal static double NormalizeHeading(double value)
        {
            double normalized = value % 360.0;
            if (normalized < 0) normalized += 360.0;
            if (Math.Abs(normalized - 360.0) < 0.0001) normalized = 0.0;
            return normalized;
        }

        private static bool ToBool(double value)
        {
            return Math.Abs(value) > 0.5;
        }

        private static int DecodeBcd16(uint raw)
        {
            return (int)(((raw >> 12) & 0xF) * 1000
                         + ((raw >> 8) & 0xF) * 100
                         + ((raw >> 4) & 0xF) * 10
                         + (raw & 0xF));
        }
    }

    internal sealed class SimConnectSystemState
    {
        public int SimState { get; set; }
        public int DialogMode { get; set; }
        public string AircraftLoadedPath { get; set; }
        public string FlightLoadedPath { get; set; }
        public bool SimReceived { get; set; }
        public bool DialogModeReceived { get; set; }
        public bool AircraftLoadedReceived { get; set; }
        public bool FlightLoadedReceived { get; set; }

        public bool IsComplete
        {
            get
            {
                return SimReceived && DialogModeReceived && AircraftLoadedReceived && FlightLoadedReceived;
            }
        }
    }
}
