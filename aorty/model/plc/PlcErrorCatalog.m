classdef PlcErrorCatalog
    % PlcErrorCatalog - Converts PLC error codes into operator messages.
    %                 - Translates PLC application and NC errors for the UI.

    methods (Static)
        function message = describe(axisName, errorCode, axisErrorID)
            switch double(errorCode)
                case 1001, detail = 'Power function block error';
                case 1002, detail = 'Axis reset error';
                case 1003, detail = 'Controlled halt error';
                case 1004, detail = 'Homing function block error';
                case 1005, detail = 'NC axis error';
                case 1006, detail = 'Both physical end stops are active';
                case 1008, detail = 'Post-home park movement error';
                case 1011, detail = 'Homing timeout';
                case 1012, detail = 'Post-home park timeout';
                case 1013, detail = 'Upper end stop active during post-home park';
                case 1014, detail = 'Lower end stop active when homing completed';
                case 2001, detail = 'Unsupported movement mode';
                case 2002, detail = 'Saved-position return requested without a saved position';
                case 2003, detail = 'Unsupported endpoint or criterion mode';
                case 2005, detail = 'Unsupported post-test mode';
                case 2006, detail = 'Execute requested while axis power is off';
                case 2007, detail = 'Invalid command count, value, or PLC setting';
                case 2008, detail = 'Command conflicts with another operation';
                case 2009, detail = 'Invalid numeric command or configuration';
                case 2010, detail = 'Biaxial commands are unavailable or incompatible';
                case 2101, detail = 'Maximum force reached; relief movement completed';
                case 2102, detail = 'Maximum force reached; relief direction unknown';
                case 2201, detail = 'Relative movement block 1 error';
                case 2203, detail = 'Velocity movement error';
                otherwise
                    detail = sprintf('Unknown PLC error %u', uint32(errorCode));
            end
            message = sprintf('%s axis: %s (NC: 0x%08X)', ...
                upper(char(axisName)), detail, uint32(axisErrorID));
        end

        function messages = messagesForStatuses(statuses)
            messages = {};
            for axis = {'X', 'Y'}
                name = axis{1};
                if isfield(statuses, name) && ...
                        isfield(statuses.(name), 'error') && statuses.(name).error
                    messages{end+1} = PlcErrorCatalog.describe(name, ...
                        statuses.(name).errorCode, statuses.(name).axisErrorID);
                end
            end
        end
    end
end


