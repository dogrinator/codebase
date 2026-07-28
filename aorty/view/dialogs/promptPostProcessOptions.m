function settings = promptPostProcessOptions(parent)
%PROMPTPOSTPROCESSOPTIONS Collects manual TIFF export settings.

settings = [];
parentPosition = parent.Position;
width = 430;
height = 190;
position = [ ...
    parentPosition(1) + (parentPosition(3) - width) / 2, ...
    parentPosition(2) + (parentPosition(4) - height) / 2, ...
    width, height];
dialog = uifigure( ...
    'Name', 'Post-process data', 'Position', position, ...
    'Resize', 'off', 'WindowStyle', 'modal');
dialog.CloseRequestFcn = @cancelDialog;

grid = uigridlayout(dialog, [3, 2]);
grid.RowHeight = {36, 36, 42};
grid.ColumnWidth = {'1x', 130};
grid.Padding = [14, 14, 14, 14];
grid.RowSpacing = 8;
grid.ColumnSpacing = 8;
uilabel(grid, 'Text', 'TIFF sampling period [s]');
periodField = uieditfield(grid, 'numeric', ...
    'Value', 0.1, 'Limits', [0, Inf], ...
    'ValueDisplayFormat', '%.3f');
includeCheck = uicheckbox(grid, ...
    'Text', 'Include pre-test and post-test', 'Value', false);
includeCheck.Layout.Row = 2;
includeCheck.Layout.Column = [1, 2];
cancelButton = uibutton(grid, 'Text', 'Cancel', ...
    'ButtonPushedFcn', @cancelDialog);
cancelButton.Layout.Row = 3;
cancelButton.Layout.Column = 1;
processButton = uibutton(grid, 'Text', 'Process', ...
    'FontWeight', 'bold', ...
    'BackgroundColor', [0.72, 0.88, 0.72], ...
    'ButtonPushedFcn', @acceptDialog);
processButton.Layout.Row = 3;
processButton.Layout.Column = 2;

uiwait(dialog);
if isvalid(dialog)
    delete(dialog);
end

    function acceptDialog(~, ~)
        settings = struct( ...
            'samplingPeriod', periodField.Value, ...
            'includePrePost', includeCheck.Value);
        uiresume(dialog);
    end

    function cancelDialog(~, ~)
        settings = [];
        uiresume(dialog);
    end
end
