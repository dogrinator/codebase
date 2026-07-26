classdef FakeAdsClient < handle
    properties
        InterfaceVersion = uint32(3)
        SavedPositionValid = true
        Powered = true
        Writes = {}
        DeleteErrorMessage = ''
    end

    properties (Access = private)
        NextHandle = int32(1)
        Symbols
        Values
    end

    methods
        function client = FakeAdsClient()
            client.Symbols = containers.Map('KeyType', 'int32', ...
                'ValueType', 'char');
            client.Values = containers.Map('KeyType', 'char', ...
                'ValueType', 'any');
        end

        function handle = CreateVariableHandle(client, symbol)
            handle = client.NextHandle;
            client.NextHandle = client.NextHandle + 1;
            client.Symbols(handle) = char(symbol);
        end

        function value = ReadAny(client, handle, varargin)
            symbol = client.Symbols(int32(handle));
            if isKey(client.Values, symbol)
                value = client.Values(symbol);
            elseif endsWith(symbol, 'nInterfaceVersion')
                value = client.InterfaceVersion;
            elseif endsWith(symbol, 'bPowered')
                value = client.Powered;
            elseif endsWith(symbol, 'bSavedPositionValid')
                value = client.SavedPositionValid;
            elseif contains(symbol, 'fTenzoBuffer') || ...
                    contains(symbol, 'fPosBuffer')
                value = zeros(1, 150);
            else
                value = 0;
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

        function DeleteVariableHandle(client, ~)
            if ~isempty(client.DeleteErrorMessage)
                error('FakeAds:DeleteHandle', '%s', client.DeleteErrorMessage);
            end
        end

        function Disconnect(~)
        end

        function Dispose(~)
        end
    end
end
