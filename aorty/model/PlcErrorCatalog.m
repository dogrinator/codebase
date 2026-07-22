classdef PlcErrorCatalog
    %PLCERRORCATALOG Translates PLC application and NC errors for the UI.

    methods (Static)
        % describe handles this operation.
        function message = describe(axisName, errorCode, axisErrorID)
            switch double(errorCode)
                case 1001, detail = 'Power function block error';
                case 1002, detail = 'Axis reset error';
                case 1003, detail = 'Controlled halt error';
                case 1004, detail = 'Lower-limit movement error';
                case 1005, detail = 'NC axis error';
                case 1006, detail = 'Upper end stop active during lower-limit movement';
                case 1007, detail = 'Lower-limit request conflicts with another operation';
                case 2001, detail = 'Unsupported movement mode';
                case 2002, detail = 'Invalid trajectory step count';
                case 2003, detail = 'Invalid displacement trajectory';
                case 2004, detail = 'Invalid constant-force trajectory';
                case 2005, detail = 'Invalid force-threshold trajectory';
                case 2007, detail = 'Invalid PLC safety configuration';
                case 2008, detail = 'Command conflicts with another operation';
                case 2009, detail = 'Invalid numeric command or configuration';
                case 2101, detail = 'Maximum force exceeded';
                case 2102, detail = 'Minimum position exceeded';
                case 2103, detail = 'Maximum position exceeded';
                case 2104, detail = 'Upper end stop reached';
                case 2105, detail = 'Lower end stop reached';
                case 2201, detail = 'Relative movement block 1 error';
                case 2202, detail = 'Relative movement block 2 error';
                case 2203, detail = 'Velocity movement error';
                case 2204, detail = 'Regulator halt error';
                case 2301, detail = 'Force target timeout';
                case 2302, detail = 'Force step timeout';
                case 2401, detail = 'Invalid Single Test command';
                case 2402, detail = 'Single test timeout';
                otherwise
                    detail = sprintf('Unknown PLC error %u', uint32(errorCode));
            end
            message = sprintf('%s axis: %s (NC: 0x%08X)', ...
                upper(char(axisName)), detail, uint32(axisErrorID));
        end

        % messagesForStatuses handles this operation.
        function messages = messagesForStatuses(statuses)
            messages = {};
            for axis = {'X', 'Y'}
                name = axis{1};
                if isfield(statuses, name) && ...
                        isfield(statuses.(name), 'error') && statuses.(name).error
                    messages{end+1} = PlcErrorCatalog.describe(name, ...
                        statuses.(name).errorCode, statuses.(name).axisErrorID); %#ok<AGROW>
                end
            end
        end
    end
end


