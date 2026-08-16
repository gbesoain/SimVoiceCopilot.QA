using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.FlightSimulator.SimConnect;
using SimVoiceCopilot.QA.SimConnectOracle.Infrastructure;

namespace SimVoiceCopilot.QA.SimConnectOracle.Oracle
{
    internal sealed class SimConnectOracleClient : IDisposable
    {
        private enum DataDefinitions
        {
            FlightState = 1
        }

        private enum DataRequests
        {
            FlightState = 1,
            SystemSim = 10,
            SystemDialogMode = 11,
            SystemAircraftLoaded = 12,
            SystemFlightLoaded = 13
        }

        private readonly OracleLogger logger;
        private readonly SimConnectMessageWindow messageWindow;
        private SimConnect simConnect;
        private bool openReceived;
        private bool quitReceived;
        private bool snapshotReceived;
        private SimConnectFlightData latestData;
        private SimConnectSystemState systemState;

        public string SimulatorApplication { get; private set; }
        public string LastSimConnectException { get; private set; }
        public bool IsConnected { get { return simConnect != null && openReceived && !quitReceived; } }

        public SimConnectOracleClient(OracleLogger logger)
        {
            this.logger = logger;
            messageWindow = new SimConnectMessageWindow();
            logger.Info("Created SimConnect message-only window: HWND=0x" + messageWindow.WindowHandle.ToInt64().ToString("X"));
        }

        public void Connect(TimeSpan timeout)
        {
            if (simConnect != null) return;

            logger.Info("Opening independent SimConnect client...");
            try
            {
                simConnect = new SimConnect(
                    "SimVoice Copilot QA SimConnect Oracle",
                    messageWindow.WindowHandle,
                    SimConnectMessageWindow.WmUserSimConnect,
                    null,
                    0);
            }
            catch (COMException exception)
            {
                throw new InvalidOperationException(
                    "Could not connect to Microsoft Flight Simulator through SimConnect. Start MSFS and load an active flight.",
                    exception);
            }

            messageWindow.ReceiveMessageAction = delegate
            {
                SimConnect current = simConnect;
                if (current != null) current.ReceiveMessage();
            };
            RegisterHandlers();
            DefineFlightData();

            PumpUntil(delegate { return openReceived; }, timeout, "SimConnect open acknowledgement");
            logger.Info("SimConnect connection established: " + SimulatorApplication);
        }

        public OracleSnapshot ReadSnapshot(TimeSpan timeout)
        {
            EnsureConnected();
            RequestSystemState(timeout);

            snapshotReceived = false;
            simConnect.RequestDataOnSimObject(
                DataRequests.FlightState,
                DataDefinitions.FlightState,
                SimConnect.SIMCONNECT_OBJECT_ID_USER,
                SIMCONNECT_PERIOD.ONCE,
                SIMCONNECT_DATA_REQUEST_FLAG.DEFAULT,
                0,
                0,
                0);

            PumpUntil(delegate { return snapshotReceived; }, timeout, "flight-state snapshot");
            return OracleSnapshot.From(latestData, systemState, SimulatorApplication);
        }

        public void PumpOnce()
        {
            Application.DoEvents();
            Thread.Sleep(10);
        }

        private void RegisterHandlers()
        {
            simConnect.OnRecvOpen += OnRecvOpen;
            simConnect.OnRecvQuit += OnRecvQuit;
            simConnect.OnRecvException += OnRecvException;
            simConnect.OnRecvSimobjectData += OnRecvSimobjectData;
            simConnect.OnRecvSystemState += OnRecvSystemState;
        }

        private void DefineFlightData()
        {
            simConnect.AddToDataDefinition(DataDefinitions.FlightState, "TITLE", null, SIMCONNECT_DATATYPE.STRING256, 0, SimConnect.SIMCONNECT_UNUSED);
            simConnect.AddToDataDefinition(DataDefinitions.FlightState, "ATC MODEL", null, SIMCONNECT_DATATYPE.STRING128, 0, SimConnect.SIMCONNECT_UNUSED);
            AddFloat64("SIM ON GROUND", "Bool");
            AddFloat64("PLANE ALTITUDE", "feet");
            AddFloat64("INDICATED ALTITUDE", "feet");
            AddFloat64("PLANE HEADING DEGREES MAGNETIC", "degrees");
            AddFloat64("AUTOPILOT AVAILABLE", "Bool");
            AddFloat64("AUTOPILOT MASTER", "Bool");
            AddFloat64("AUTOPILOT HEADING LOCK", "Bool");
            AddFloat64("AUTOPILOT HEADING LOCK DIR", "degrees");
            AddFloat64("AUTOPILOT ALTITUDE LOCK", "Bool");
            AddFloat64("AUTOPILOT ALTITUDE LOCK VAR", "feet");
            AddFloat64("AUTOPILOT VERTICAL HOLD", "Bool");
            AddFloat64("AUTOPILOT VERTICAL HOLD VAR", "feet per minute");

            // HF36-R14 functional gate: independent radio truth from MSFS.
            // Request MHz so the Oracle compares the human-visible frequency
            // rather than any BCD/event encoding used internally.
            AddFloat64("COM ACTIVE FREQUENCY:1", "MHz");
            AddFloat64("COM STANDBY FREQUENCY:1", "MHz");
            AddFloat64("COM ACTIVE FREQUENCY:2", "MHz");
            AddFloat64("COM STANDBY FREQUENCY:2", "MHz");
            AddFloat64("NAV ACTIVE FREQUENCY:1", "MHz");
            AddFloat64("NAV STANDBY FREQUENCY:1", "MHz");
            AddFloat64("NAV ACTIVE FREQUENCY:2", "MHz");
            AddFloat64("NAV STANDBY FREQUENCY:2", "MHz");

            simConnect.AddToDataDefinition(DataDefinitions.FlightState, "TRANSPONDER CODE:1", "BCO16", SIMCONNECT_DATATYPE.INT32, 0, SimConnect.SIMCONNECT_UNUSED);
            AddFloat64("BRAKE PARKING POSITION", "Bool");
            AddFloat64("GEAR HANDLE POSITION", "percent over 100");
            AddFloat64("FLAPS HANDLE INDEX", "number");
            AddFloat64("FUEL TOTAL QUANTITY", "gallons");
            AddFloat64("AMBIENT WIND DIRECTION", "degrees");
            AddFloat64("AMBIENT WIND VELOCITY", "knots");
            AddFloat64("GROUND VELOCITY", "knots");
            AddFloat64("SIMULATION RATE", "number");
            AddFloat64("VERTICAL SPEED", "feet per minute");
            AddFloat64("AIRSPEED INDICATED", "knots");
            AddFloat64("AIRSPEED TRUE", "knots");
            AddFloat64("AMBIENT TEMPERATURE", "celsius");
            AddFloat64("PLANE ALT ABOVE GROUND", "feet");
            AddFloat64("GENERAL ENG RPM:1", "rpm");
            AddFloat64("GENERAL ENG RPM:2", "rpm");
            AddFloat64("FUEL TANK LEFT MAIN QUANTITY", "gallons");
            AddFloat64("FUEL TANK RIGHT MAIN QUANTITY", "gallons");
            AddFloat64("LIGHT LANDING", "Bool");
            AddFloat64("LIGHT BEACON", "Bool");
            AddFloat64("LIGHT NAV", "Bool");
            AddFloat64("LIGHT TAXI", "Bool");
            AddFloat64("LIGHT STROBE", "Bool");
            AddFloat64("ELECTRICAL MASTER BATTERY", "Bool");
            AddFloat64("AVIONICS MASTER SWITCH", "Bool");

            simConnect.RegisterDataDefineStruct<SimConnectFlightData>(DataDefinitions.FlightState);
        }

        private void AddFloat64(string variable, string units)
        {
            simConnect.AddToDataDefinition(
                DataDefinitions.FlightState,
                variable,
                units,
                SIMCONNECT_DATATYPE.FLOAT64,
                0,
                SimConnect.SIMCONNECT_UNUSED);
        }

        private void RequestSystemState(TimeSpan timeout)
        {
            systemState = new SimConnectSystemState();
            simConnect.RequestSystemState(DataRequests.SystemSim, "Sim");
            simConnect.RequestSystemState(DataRequests.SystemDialogMode, "DialogMode");
            simConnect.RequestSystemState(DataRequests.SystemAircraftLoaded, "AircraftLoaded");
            simConnect.RequestSystemState(DataRequests.SystemFlightLoaded, "FlightLoaded");
            PumpUntil(delegate { return systemState.IsComplete; }, timeout, "MSFS system-state response");
        }

        private void PumpUntil(Func<bool> predicate, TimeSpan timeout, string operation)
        {
            DateTime deadline = DateTime.UtcNow.Add(timeout);
            while (!predicate())
            {
                if (quitReceived)
                {
                    throw new InvalidOperationException("Microsoft Flight Simulator closed the SimConnect connection.");
                }

                if (DateTime.UtcNow >= deadline)
                {
                    throw new TimeoutException("Timed out waiting for " + operation + ".");
                }

                PumpOnce();
            }
        }

        private void EnsureConnected()
        {
            if (!IsConnected)
            {
                throw new InvalidOperationException("The SimConnect Oracle is not connected.");
            }
        }

        private void OnRecvOpen(SimConnect sender, SIMCONNECT_RECV_OPEN data)
        {
            SimulatorApplication = data.szApplicationName ?? "Microsoft Flight Simulator";
            openReceived = true;
        }

        private void OnRecvQuit(SimConnect sender, SIMCONNECT_RECV data)
        {
            quitReceived = true;
            logger.Warn("Microsoft Flight Simulator sent the SimConnect quit notification.");
        }

        private void OnRecvException(SimConnect sender, SIMCONNECT_RECV_EXCEPTION data)
        {
            SIMCONNECT_EXCEPTION exceptionCode = (SIMCONNECT_EXCEPTION)data.dwException;
            LastSimConnectException = exceptionCode.ToString();
            logger.Error("SimConnect exception: " + LastSimConnectException);
        }

        private void OnRecvSimobjectData(SimConnect sender, SIMCONNECT_RECV_SIMOBJECT_DATA data)
        {
            if (data.dwRequestID != (uint)DataRequests.FlightState || data.dwData == null || data.dwData.Length == 0)
            {
                return;
            }

            latestData = (SimConnectFlightData)data.dwData[0];
            snapshotReceived = true;
        }

        private void OnRecvSystemState(SimConnect sender, SIMCONNECT_RECV_SYSTEM_STATE data)
        {
            DataRequests request = (DataRequests)data.dwRequestID;
            switch (request)
            {
                case DataRequests.SystemSim:
                    systemState.SimState = (int)data.dwInteger;
                    systemState.SimReceived = true;
                    break;
                case DataRequests.SystemDialogMode:
                    systemState.DialogMode = (int)data.dwInteger;
                    systemState.DialogModeReceived = true;
                    break;
                case DataRequests.SystemAircraftLoaded:
                    systemState.AircraftLoadedPath = data.szString ?? string.Empty;
                    systemState.AircraftLoadedReceived = true;
                    break;
                case DataRequests.SystemFlightLoaded:
                    systemState.FlightLoadedPath = data.szString ?? string.Empty;
                    systemState.FlightLoadedReceived = true;
                    break;
            }
        }

        public void Dispose()
        {
            messageWindow.ReceiveMessageAction = null;
            if (simConnect != null)
            {
                try
                {
                    simConnect.Dispose();
                }
                catch
                {
                    // Best-effort cleanup.
                }
                simConnect = null;
            }

            messageWindow.Dispose();
        }
    }
}
