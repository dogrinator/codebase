function tests = testApplicationLifecycle
tests = functiontests(localfunctions);
end

function testMainIsSingleInstance(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
applicationKey = 'AortyApplicationView';
cleanup = onCleanup(@() closeApplication(applicationKey));

run(fullfile(root, 'main.m'));
firstView = getappdata(groot, applicationKey);
firstTimers = numel(timerfindall);

run(fullfile(root, 'main.m'));
secondView = getappdata(groot, applicationKey);
secondTimers = numel(timerfindall);

verifyTrue(testCase, isequal(firstView, secondView));
verifyEqual(testCase, secondTimers, firstTimers);
verifyEqual(testCase, firstView.controller.plcReadTimer.Period, 0.25);
verifyEqual(testCase, ...
    firstView.controller.settings.activeHwConfigName, 'default');
verifyEqual(testCase, ...
    firstView.controller.settings.activeAppConfigName, 'default');
verifyEqual(testCase, ...
    firstView.getTestConfiguration().schemaVersion, 2);
verifyEqual(testCase, AppInfo.POSITION_LIMITS_MM.X, [0, 50]);
verifyEqual(testCase, AppInfo.POSITION_LIMITS_MM.Y, [0, 50]);
applicationTimers = timerfindall;
if ~isempty(applicationTimers)
    stop(applicationTimers);
end

status = struct('powered', true, 'working', false, ...
    'stopped', true, 'homing', false, 'homed', true, ...
    'savedPositionValid', true, 'error', false, ...
    'errorCode', uint32(0), 'systemStatus', int16(0));
firstView.updateMachineStatus(struct('X', status, 'Y', status), true);
verifyEqual(testCase, firstView.systemStatusLabel.Text, '0 - Idle');
singleStatus = status;
singleStatus.systemStatus = int16(20);
firstView.updateMachineStatus( ...
    struct('X', status, 'Y', singleStatus), true);
verifyEqual(testCase, ...
    firstView.systemStatusLabel.Text, '20 - SingleTest');
cyclicStatus = status;
cyclicStatus.systemStatus = int16(21);
firstView.updateMachineStatus( ...
    struct('X', singleStatus, 'Y', cyclicStatus), true);
verifySubstring(testCase, firstView.systemStatusLabel.Text, ...
    'X 20 SingleTest | Y 21 CyclicTest');

root = fileparts(fileparts(mfilename('fullpath')));
currentPreset = jsondecode(fileread(fullfile( ...
    root, '.config', 'appConfig', 'default.json')));
firstView.testPanel.applyPreset(currentPreset);
verifyEqual(testCase, ...
    firstView.getTestConfiguration().system.axisMode, 'Both');
verifyEqual(testCase, firstView.machinePanel.sampleCountField.Value, 500);
positionLimitLines = findPositionLimitLines(firstView.fig);
verifyEqual(testCase, numel(positionLimitLines), 4);
verifyEqual(testCase, sort([positionLimitLines.Value]), [0, 0, 50, 50]);
verifyTrue(testCase, all(strcmp({positionLimitLines.Visible}, 'off')));
for index = 1:numel(positionLimitLines)
    verifyNotEmpty(testCase, positionLimitLines(index).Label);
end
referenceLines = findForceReferenceLines(firstView.fig);
verifyNotEmpty(testCase, referenceLines);
for index = 1:numel(referenceLines)
    verifyEmpty(testCase, referenceLines(index).Label);
end
verifyNotEmpty(testCase, findall(firstView.fig, 'Type', 'Patch'));
capturedUnload = findall(firstView.testPanel.tabs, ...
    'Text', 'Unload to captured start position');
verifyEqual(testCase, numel(capturedUnload), 1);
capturedUnload.Value = false;
capturedUnload.ValueChangedFcn(capturedUnload, []);
withUnloadReference = numel(findForceReferenceLines(firstView.fig));
capturedUnload.Value = true;
capturedUnload.ValueChangedFcn(capturedUnload, []);
withoutUnloadReference = numel(findForceReferenceLines(firstView.fig));
verifyGreaterThan(testCase, ...
    withUnloadReference, withoutUnloadReference);
firstView.machinePanel.sampleCountField.Value = 120;
firstView.machinePanel.sampleCountField.ValueChangedFcn( ...
    firstView.machinePanel.sampleCountField, []);
verifyEqual(testCase, firstView.machinePanel.sampleCountField.Value, 120);
firstView.machinePanel.modeDrop.Value = 'Displacement';
firstView.machinePanel.modeDrop.ValueChangedFcn( ...
    firstView.machinePanel.modeDrop, []);
verifyEmpty(testCase, findForceReferenceLines(firstView.fig));
positionLimitLines = findPositionLimitLines(firstView.fig);
verifyEqual(testCase, numel(positionLimitLines), 4);
verifyTrue(testCase, all(strcmp({positionLimitLines.Visible}, 'on')));
firstView.machinePanel.modeDrop.Value = 'Force';
firstView.machinePanel.modeDrop.ValueChangedFcn( ...
    firstView.machinePanel.modeDrop, []);
verifyNotEmpty(testCase, findForceReferenceLines(firstView.fig));
positionLimitLines = findPositionLimitLines(firstView.fig);
verifyEqual(testCase, numel(positionLimitLines), 4);
verifyTrue(testCase, all(strcmp({positionLimitLines.Visible}, 'off')));
firstView.machinePanel.modeDrop.Value = 'Displacement';
firstView.machinePanel.modeDrop.ValueChangedFcn( ...
    firstView.machinePanel.modeDrop, []);
verifyEqual(testCase, numel(findPositionLimitLines(firstView.fig)), 4);
firstView.machinePanel.modeDrop.Value = 'Force';
firstView.machinePanel.modeDrop.ValueChangedFcn( ...
    firstView.machinePanel.modeDrop, []);
verifyEqual(testCase, numel(findPositionLimitLines(firstView.fig)), 4);
batch = struct( ...
    'Force', struct('X', 1:200, 'Y', 201:400), ...
    'Displacement', struct('X', 401:600, 'Y', 601:800));
firstView.appendPlotData(batch, 0.01);
allHandles = findall(firstView.fig);
animated = allHandles(arrayfun(@(handle) ...
    isa(handle, 'matlab.graphics.animation.AnimatedLine'), allHandles));
verifyEqual(testCase, numel(animated), 4);
for index = 1:numel(animated)
    [xValues, yValues] = getpoints(animated(index));
    verifyEqual(testCase, numel(xValues), 120);
    verifyEqual(testCase, numel(yValues), 120);
end
firstView.machinePanel.sampleCountField.Value = 50;
firstView.machinePanel.sampleCountField.ValueChangedFcn( ...
    firstView.machinePanel.sampleCountField, []);
for index = 1:numel(animated)
    [xValues, ~] = getpoints(animated(index));
    verifyEqual(testCase, numel(xValues), 50);
end
firstView.openSettingsWindow();
verifyTrue(testCase, firstView.settingsWindow.isOpen());
firstView.settingsWindow.close();
legacyPreset = currentPreset;
legacyPreset.pre = rmfield(legacyPreset.pre, 'holdTime');
verifyError(testCase, ...
    @() firstView.testPanel.applyPreset(legacyPreset), ...
    'TestPreset:MissingField');
legacyPreset = currentPreset;
legacyPreset.pre = rmfield(legacyPreset.pre, 'forceTolerance');
verifyError(testCase, ...
    @() firstView.testPanel.applyPreset(legacyPreset), ...
    'TestPreset:MissingField');

firstView.setOperationActive(true);
verifyEqual(testCase, string(firstView.camSwitch.Enable), "off");
verifyEqual(testCase, string(firstView.plcSwitch.Enable), "off");
verifyEqual(testCase, string(firstView.settingsCamBtn.Enable), "off");
verifyEqual(testCase, string(firstView.postProcessButton.Enable), "off");
verifyEqual(testCase, ...
    string(firstView.machinePanel.powerButton.Enable), "off");
verifyEqual(testCase, ...
    string(firstView.machinePanel.stopButton.Enable), "on");
definitionControls = findall( ...
    firstView.testPanel.tabs, '-property', 'Enable');
for index = 1:numel(definitionControls)
    verifyEqual(testCase, ...
        string(definitionControls(index).Enable), "off");
end

firstView.setOperationActive(false);
verifyEqual(testCase, string(firstView.camSwitch.Enable), "on");
verifyEqual(testCase, string(firstView.settingsCamBtn.Enable), "on");
verifyEqual(testCase, ...
    string(firstView.machinePanel.powerButton.Enable), "on");
enabledAfterUnlock = false;
for index = 1:numel(definitionControls)
    if isvalid(definitionControls(index))
        enabledAfterUnlock = enabledAfterUnlock || ...
            strcmp(definitionControls(index).Enable, 'on');
    end
end
verifyTrue(testCase, enabledAfterUnlock);
clear cleanup;
end

function lines = findPositionLimitLines(fig)
lines = findall(fig, 'Type', 'ConstantLine', 'Tag', 'PositionLimit');
end

function lines = findForceReferenceLines(fig)
lines = findall(fig, 'Type', 'ConstantLine');
lines = lines(~strcmp({lines.Tag}, 'PositionLimit'));
end

function closeApplication(applicationKey)
if isappdata(groot, applicationKey)
    view = getappdata(groot, applicationKey);
    if ~isempty(view) && isvalid(view)
        view.shutdown();
    else
        rmappdata(groot, applicationKey);
    end
end
end
