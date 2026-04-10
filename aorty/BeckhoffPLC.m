classdef BeckhoffPLC < handle
    properties
        client
        timerObj
        dllPath char
        netId char
        port double = 851

        % PLC symbol names
        symX char = 'MAIN.posX'
        symY char = 'MAIN.posY'
        symForce char = 'MAIN.force'
        symStatus char = 'MAIN.status'

        % ADS handles
        hX double = NaN
        hY double = NaN
        hForce double = NaN
        hStatus double = NaN

        isConnected logical = false
        app
    end

    methods
        function obj = BeckhoffPLC(app, dllPath, netId, port)
            obj.app = app;
            obj.dllPath = dllPath;
            obj.netId = char(netId);

            if nargin >= 4 && ~isempty(port)
                obj.port = port;
            end

            obj.loadDll();
        end

        function loadDll(obj)
            persistent dllLoaded
            if isempty(dllLoaded)
                NET.addAssembly(obj.dllPath);
                dllLoaded = true;
            end
            import TwinCAT.Ads.*
        end

        function start(obj)
            import TwinCAT.Ads.*

            if obj.isConnected
                return;
            end

            obj.loadDll();

            % Connect to PLC
            obj.client = TcAdsClient();
            obj.client.Connect(obj.netId, obj.port);

            % Create handles once
            obj.hX = obj.client.CreateVariableHandle(obj.symX);
            obj.hY = obj.client.CreateVariableHandle(obj.symY);
            obj.hForce = obj.client.CreateVariableHandle(obj.symForce);
            obj.hStatus = obj.client.CreateVariableHandle(obj.symStatus);

            % Start periodic polling
            obj.timerObj = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', 0.1, ...          % 100 ms
                'BusyMode', 'drop', ...
                'TimerFcn', @(~,~)obj.pollPLC());

            start(obj.timerObj);

            obj.isConnected = true;
            disp("PLC connected and polling started");
        end

        function pollPLC(obj)
            if ~obj.isConnected || isempty(obj.client)
                return;
            end

            try
                import TwinCAT.Ads.*

                % Read values by handle
                x = obj.client.ReadAny(obj.hX, System.Single(0).GetType);
                y = obj.client.ReadAny(obj.hY, System.Single(0).GetType);
                f = obj.client.ReadAny(obj.hForce, System.Single(0).GetType);
                s = obj.client.ReadAny(obj.hStatus, System.Int32(0).GetType);

                % Convert to MATLAB types
                x = double(x);
                y = double(y);
                f = double(f);
                s = double(s);

                % Example GUI update
                if ~isempty(obj.app) && isprop(obj.app, 'StatusLabel')
                    obj.app.StatusLabel.Text = sprintf('X=%.3f  Y=%.3f  F=%.3f  S=%d', x, y, f, s);
                end

                % Example console debug
                fprintf('PLC: X=%.3f Y=%.3f F=%.3f S=%d\n', x, y, f, s);

            catch ME
                disp("PLC poll error: " + string(ME.message));
            end
        end

        function writeForce(obj, value)
            if ~obj.isConnected || isempty(obj.client)
                return;
            end
            obj.client.WriteAny(obj.hForce, single(value));
        end

        function stop(obj)
            try
                if ~isempty(obj.timerObj) && isvalid(obj.timerObj)
                    stop(obj.timerObj);
                    delete(obj.timerObj);
                end
            catch
            end
            obj.timerObj = [];

            try
                if ~isempty(obj.client)
                    if ~isnan(obj.hX), obj.client.DeleteVariableHandle(obj.hX); end
                    if ~isnan(obj.hY), obj.client.DeleteVariableHandle(obj.hY); end
                    if ~isnan(obj.hForce), obj.client.DeleteVariableHandle(obj.hForce); end
                    if ~isnan(obj.hStatus), obj.client.DeleteVariableHandle(obj.hStatus); end

                    obj.client.Disconnect();
                    obj.client.Dispose();
                end
            catch ME
                disp("PLC disconnect error: " + string(ME.message));
            end

            obj.client = [];
            obj.hX = NaN;
            obj.hY = NaN;
            obj.hForce = NaN;
            obj.hStatus = NaN;
            obj.isConnected = false;

            disp("PLC disconnected");
        end
    end
end