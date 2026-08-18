classdef FakeAdsClient < handle
    properties
        InterfaceVersion = uint32(6)
        SavedPositionValid = true
        Powered = true
        StatusPacketLength = 856
        StatusReadCounts = struct('X', 0, 'Y', 0)
        CreateCount = 0
        FailCreateAt = inf
        DeletedHandles = zeros(1, 0, 'int32')
        Writes = {}
        DeleteErrorMessage = ''
        AutoCheckpointOnPowerOff = false
    end

    properties (Access = private)
        NextHandle = int32(1)
        Symbols
        Values
        Statuses
    end

    methods
        function client = FakeAdsClient()
            client.Symbols = containers.Map('KeyType', 'int32', ...
                'ValueType', 'char');
            client.Values = containers.Map('KeyType', 'char', ...
                'ValueType', 'any');
            client.Statuses = struct( ...
                'X', client.defaultStatus(), ...
                'Y', client.defaultStatus());
        end

        function handle = CreateVariableHandle(client, symbol)
            client.CreateCount = client.CreateCount + 1;
            if client.CreateCount == client.FailCreateAt
                error('FakeAds:CreateHandle', ...
                    'Injected handle creation failure.');
            end
            handle = client.NextHandle;
            client.NextHandle = client.NextHandle + 1;
            client.Symbols(handle) = char(symbol);
        end

        function value = ReadAny(client, handle, varargin)
            symbol = client.Symbols(int32(handle));
            if isKey(client.Values, symbol)
                value = client.Values(symbol);
            else
                value = 0;
            end
        end

        function bytes = ReadStatusPacket(client, handle, ~)
            symbol = client.Symbols(int32(handle));
            if endsWith(symbol, 'X')
                axisName = 'X';
            elseif endsWith(symbol, 'Y')
                axisName = 'Y';
            else
                error('FakeAds:StatusSymbol', ...
                    'Status packet requested for non-status symbol %s.', symbol);
            end
            client.StatusReadCounts.(axisName) = ...
                client.StatusReadCounts.(axisName) + 1;
            status = client.Statuses.(axisName);
            status.interfaceVersion = client.InterfaceVersion;
            status.savedPositionValid = client.SavedPositionValid;
            status.powered = client.Powered;
            bytes = client.encodeStatus(status);
            if client.StatusPacketLength < numel(bytes)
                bytes = bytes(1:client.StatusPacketLength);
            elseif client.StatusPacketLength > numel(bytes)
                bytes(end + 1:client.StatusPacketLength) = uint8(0);
            end
        end

        function WriteAny(client, handle, value)
            symbol = client.Symbols(int32(handle));
            if isnumeric(value) || islogical(value)
                stored = value;
            else
                stored = double(value);
            end
            client.Values(symbol) = stored;
            client.Writes{end + 1} = struct( ...
                'symbol', symbol, 'value', stored);
            if client.AutoCheckpointOnPowerOff && ...
                    endsWith(symbol, '.bPower') && ~logical(stored)
                counterSymbol = ...
                    'MAIN.nPersistentPositionCheckpointCounter';
                if isKey(client.Values, counterSymbol)
                    counter = uint32(client.Values(counterSymbol));
                else
                    counter = uint32(0);
                end
                client.Values(counterSymbol) = counter + 1;
                client.Values('MAIN.bPersistentPositionSaved') = true;
                client.Values('MAIN.bPersistentPositionSaveBusy') = false;
                client.Values('MAIN.bPersistentPositionSaveError') = false;
                client.Values('MAIN.nPersistentPositionSaveErrorID') = ...
                    uint32(0);
            end
        end

        function setStatus(client, axisName, values)
            axisName = upper(char(axisName));
            status = client.Statuses.(axisName);
            names = fieldnames(values);
            for index = 1:numel(names)
                status.(names{index}) = values.(names{index});
            end
            client.Statuses.(axisName) = status;
        end

        function setSymbol(client, symbol, value)
            client.Values(char(symbol)) = value;
        end

        function value = getSymbol(client, symbol)
            value = client.Values(char(symbol));
        end

        function clearWrites(client)
            client.Writes = {};
        end

        function resetStatusReadCounts(client)
            client.StatusReadCounts = struct('X', 0, 'Y', 0);
        end

        function DeleteVariableHandle(client, handle)
            if ~isempty(client.DeleteErrorMessage)
                error('FakeAds:DeleteHandle', '%s', client.DeleteErrorMessage);
            end
            client.DeletedHandles(end + 1) = int32(handle);
        end

        function Disconnect(~)
        end

        function Dispose(~)
        end
    end

    methods (Access = private)
        function status = defaultStatus(~)
            status = struct( ...
                'positionBuffer', zeros(1, 50), ...
                'forceBuffer', zeros(1, 50), ...
                'bufferHead', int16(50), ...
                'sampleCounter', uint32(0), ...
                'operationCounter', uint32(0), ...
                'interfaceVersion', uint32(6), ...
                'tareOffset', 0, ...
                'position', 0, ...
                'working', false, ...
                'tareWorking', false, ...
                'error', false, ...
                'errorCode', uint32(0), ...
                'axisErrorID', uint32(0), ...
                'powered', true, ...
                'homing', false, ...
                'homed', false, ...
                'stopped', true, ...
                'savedPositionValid', true, ...
                'systemStatus', int16(0));
        end

        function bytes = encodeStatus(client, status)
            bytes = zeros(1, 856, 'uint8');
            bytes = client.put(bytes, 0, ...
                typecast(double(status.positionBuffer(:)'), 'uint8'));
            bytes = client.put(bytes, 400, ...
                typecast(double(status.forceBuffer(:)'), 'uint8'));
            bytes = client.put(bytes, 800, ...
                typecast(int16(status.bufferHead), 'uint8'));
            bytes = client.put(bytes, 804, ...
                typecast(uint32(status.sampleCounter), 'uint8'));
            bytes = client.put(bytes, 808, ...
                typecast(uint32(status.operationCounter), 'uint8'));
            bytes = client.put(bytes, 812, ...
                typecast(uint32(status.interfaceVersion), 'uint8'));
            bytes = client.put(bytes, 816, ...
                typecast(double(status.tareOffset), 'uint8'));
            bytes = client.put(bytes, 824, ...
                typecast(double(status.position), 'uint8'));
            bytes(833) = uint8(logical(status.working));
            bytes(834) = uint8(logical(status.tareWorking));
            bytes(835) = uint8(logical(status.error));
            bytes = client.put(bytes, 836, ...
                typecast(uint32(status.errorCode), 'uint8'));
            bytes = client.put(bytes, 840, ...
                typecast(uint32(status.axisErrorID), 'uint8'));
            bytes(845) = uint8(logical(status.powered));
            bytes(846) = uint8(logical(status.homing));
            bytes(847) = uint8(logical(status.homed));
            bytes(848) = uint8(logical(status.stopped));
            bytes(849) = uint8(logical(status.savedPositionValid));
            bytes = client.put(bytes, 850, ...
                typecast(int16(status.systemStatus), 'uint8'));
        end

        function bytes = put(~, bytes, byteOffset, value)
            first = byteOffset + 1;
            bytes(first:first + numel(value) - 1) = uint8(value);
        end
    end
end
