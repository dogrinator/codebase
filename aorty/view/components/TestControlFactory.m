classdef TestControlFactory
    %TESTCONTROLFACTORY Creates the repeated controls used by test tabs.

    methods (Static)
        function grid = formGrid(tab, rows)
            grid = uigridlayout(tab, [rows + 1, 5]);
            grid.ColumnWidth = {190, '1x', '1x', 80, 72};
            grid.RowHeight = repmat({34}, 1, rows + 1);
            grid.Padding = [10, 10, 10, 10];
            grid.RowSpacing = 5;
            uilabel(grid, 'Text', 'Parameter', 'FontWeight', 'bold');
            uilabel(grid, 'Text', 'X', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            uilabel(grid, 'Text', 'Y', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            uilabel(grid, 'Text', 'Unit', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            uilabel(grid, 'Text', 'Lock', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
        end

        function controls = axisRow(grid, row, text, value, unit, changed)
            TestControlFactory.label(grid, row, 1, text, '');
            controls.x = uieditfield(grid, 'numeric', 'Value', value);
            controls.x.Layout.Row = row;
            controls.x.Layout.Column = 2;
            controls.y = uieditfield(grid, 'numeric', 'Value', value);
            controls.y.Layout.Row = row;
            controls.y.Layout.Column = 3;
            TestControlFactory.label(grid, row, 4, unit, 'center');
            controls.lock = uibutton(grid, 'state', 'Text', 'XY', ...
                'Value', true);
            controls.lock.Layout.Row = row;
            controls.lock.Layout.Column = 5;
            controls.x.ValueChangedFcn = @(src, ~) ...
                TestControlFactory.syncPair( ...
                    src, controls.y, controls.lock, changed);
            controls.y.ValueChangedFcn = @(src, ~) ...
                TestControlFactory.syncPair( ...
                    src, controls.x, controls.lock, changed);
            controls.lock.ValueChangedFcn = @(src, ~) ...
                TestControlFactory.syncLock( ...
                    src, controls.x, controls.y, changed);
        end

        function control = cycleRow(grid, row, text, value, unit)
            TestControlFactory.label(grid, row, 1, text, '');
            cycleValues = 1:50;
            control = uidropdown(grid, ...
                'Items', cellstr(string(cycleValues)), ...
                'ItemsData', cycleValues, 'Value', value);
            control.Layout.Row = row;
            control.Layout.Column = [2, 3];
            TestControlFactory.label(grid, row, 4, unit, 'center');
        end

        function control = checkRow(grid, row, text, value)
            control = uicheckbox(grid, 'Text', text, 'Value', value);
            control.Layout.Row = row;
            control.Layout.Column = [1, 4];
        end

        function controls = optionalRow( ...
                grid, row, text, value, unit, changed)
            controls.enabled = uicheckbox(grid, ...
                'Text', text, 'Value', false);
            controls.enabled.Layout.Row = row;
            controls.enabled.Layout.Column = 1;
            controls.value = uieditfield(grid, 'numeric', ...
                'Value', value, 'Enable', 'off');
            controls.value.Layout.Row = row;
            controls.value.Layout.Column = [2, 3];
            TestControlFactory.label(grid, row, 4, unit, 'center');
            controls.enabled.ValueChangedFcn = @(~, ~) changed();
        end

        function controls = optionalAxisRow( ...
                grid, row, text, value, unit, changed)
            controls.enabled = uicheckbox(grid, ...
                'Text', text, 'Value', false);
            controls.enabled.Layout.Row = row;
            controls.enabled.Layout.Column = 1;
            controls.value.x = uieditfield(grid, ...
                'numeric', 'Value', value);
            controls.value.x.Layout.Row = row;
            controls.value.x.Layout.Column = 2;
            controls.value.y = uieditfield(grid, ...
                'numeric', 'Value', value);
            controls.value.y.Layout.Row = row;
            controls.value.y.Layout.Column = 3;
            TestControlFactory.label(grid, row, 4, unit, 'center');
            controls.value.lock = uibutton(grid, 'state', ...
                'Text', 'XY', 'Value', true);
            controls.value.lock.Layout.Row = row;
            controls.value.lock.Layout.Column = 5;
            controls.value.x.ValueChangedFcn = @(src, ~) ...
                TestControlFactory.syncPair( ...
                    src, controls.value.y, controls.value.lock, changed);
            controls.value.y.ValueChangedFcn = @(src, ~) ...
                TestControlFactory.syncPair( ...
                    src, controls.value.x, controls.value.lock, changed);
            controls.value.lock.ValueChangedFcn = @(src, ~) ...
                TestControlFactory.syncLock( ...
                    src, controls.value.x, controls.value.y, changed);
            controls.enabled.ValueChangedFcn = @(~, ~) changed();
        end

        function control = dropRow(grid, row, text, items)
            TestControlFactory.label(grid, row, 1, text, '');
            control = uidropdown(grid, 'Items', items);
            control.Layout.Row = row;
            control.Layout.Column = [2, 4];
        end

        function control = textRow(grid, row, text, value)
            TestControlFactory.label(grid, row, 1, text, '');
            control = uieditfield(grid, 'text', 'Value', value, ...
                'Editable', 'off');
            control.Layout.Row = row;
            control.Layout.Column = [2, 4];
        end

        function button = runButton(grid, row, text, callback)
            button = uibutton(grid, 'Text', text, ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.72, 0.88, 0.72], ...
                'ButtonPushedFcn', callback);
            button.Layout.Row = row;
            button.Layout.Column = [1, 5];
        end
    end

    methods (Static, Access = private)
        function label(grid, row, column, text, alignment)
            control = uilabel(grid, 'Text', text);
            control.Layout.Row = row;
            control.Layout.Column = column;
            if ~isempty(alignment)
                control.HorizontalAlignment = alignment;
            end
        end

        function syncPair(source, target, lock, changed)
            if lock.Value
                target.Value = source.Value;
            end
            changed();
        end

        function syncLock(lock, xField, yField, changed)
            if lock.Value
                yField.Value = xField.Value;
            end
            changed();
        end
    end
end
