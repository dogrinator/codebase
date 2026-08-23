function tests = testApplicationLifecycle
tests = functiontests(localfunctions);
end

function testMainIsSingleInstance(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
applicationKey = 'AortyApplicationView';
cleanup = onCleanup(@() closeApplication(applicationKey));

run(fullfile(root, 'main.m'));
firstView = getappdata(groot, applicationKey);
firstTimers = [firstView.controller.plcReadTimer, ...
    firstView.controller.displayTimer];

run(fullfile(root, 'main.m'));
secondView = getappdata(groot, applicationKey);
secondTimers = [secondView.controller.plcReadTimer, ...
    secondView.controller.displayTimer];

verifyTrue(testCase, isequal(firstView, secondView));
verifyTrue(testCase, all(arrayfun(@(index) ...
    isequal(secondTimers(index), firstTimers(index)), 1:2)));
verifyEqual(testCase, firstView.controller.plcReadTimer.Period, 0.25);
verifyEqual(testCase, ...
    firstView.controller.settings.activeHwConfigName, 'default');
verifyEqual(testCase, ...
    firstView.controller.settings.activeAppConfigName, 'default');
verifyEqual(testCase, ...
    firstView.getTestConfiguration().schemaVersion, 2);
applicationTimers = [firstView.controller.plcReadTimer, ...
    firstView.controller.displayTimer];
for timerObject = applicationTimers
    if isvalid(timerObject)
        stop(timerObject);
    end
end

status = struct('powered', true, 'working', false, ...
    'stopped', true, 'homing', false, 'homed', true, ...
    'savedPositionValid', true, 'error', false, ...
    'errorCode', uint32(0), 'systemStatus', int16(0));
firstView.updateMachineStatus(struct('X', status, 'Y', status), true);
verifyEqual(testCase, firstView.systemStatusLabel.Text, '0 - Idle');
singleRun = findall(firstView.testPanel.tabs, ...
    'Text', 'RUN SINGLE TEST');
verifyEqual(testCase, string(singleRun.Enable), "on");
unreferenced = status;
unreferenced.homed = false;
firstView.updateMachineStatus( ...
    struct('X', unreferenced, 'Y', unreferenced), true);
verifyEqual(testCase, string(singleRun.Enable), "off");
unpowered = status;
unpowered.powered = false;
firstView.updateMachineStatus( ...
    struct('X', unpowered, 'Y', unpowered), true);
verifyEqual(testCase, string(singleRun.Enable), "off");
firstView.updateMachineStatus(struct('X', status, 'Y', status), true);
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
cyclicCycles = findall(firstView.fig, 'Tag', 'CyclicCycleCount');
preCycles = findall(firstView.fig, 'Tag', 'PreCycleCount');
verifyTrue(testCase, isa(cyclicCycles, ...
    'matlab.ui.control.NumericEditField'));
verifyTrue(testCase, isa(preCycles, ...
    'matlab.ui.control.NumericEditField'));
verifyEqual(testCase, cyclicCycles.Limits, [1, 50]);
verifyEqual(testCase, preCycles.Limits, [1, 50]);
verifyEqual(testCase, string(cyclicCycles.RoundFractionalValues), "on");
verifyEqual(testCase, string(preCycles.RoundFractionalValues), "on");

manualSpeedX = findall(firstView.fig, 'Tag', 'ManualSpeedX');
manualSpeedY = findall(firstView.fig, 'Tag', 'ManualSpeedY');
verifyEqual(testCase, manualSpeedX.Limits, [0, 5]);
verifyEqual(testCase, manualSpeedY.Limits, [0, 5]);
singlePrimaryX = findall(firstView.fig, 'Tag', 'SinglePrimaryX');
singlePrimaryY = findall(firstView.fig, 'Tag', 'SinglePrimaryY');
verifyEqual(testCase, singlePrimaryX.Limits, [-2.5, 2.5]);
verifyEqual(testCase, singlePrimaryY.Limits, [-0.9, 0.9]);
verifyEqual(testCase, ...
    string(findall(firstView.fig, 'Tag', 'SinglePrimaryUnit').Text), "N");

cyclicLoadMode = findall(firstView.fig, 'Tag', 'CyclicLoadMode');
cyclicLoadUnit = findall(firstView.fig, 'Tag', 'CyclicLoadUnit');
loadBefore = firstView.getTestConfiguration().cyclic.load;
verifyEqual(testCase, string(cyclicLoadUnit.Text), "mm");
cyclicLoadMode.Value = 'Force';
cyclicLoadMode.ValueChangedFcn(cyclicLoadMode, []);
verifyEqual(testCase, string(cyclicLoadUnit.Text), "N");
verifyEqual(testCase, firstView.getTestConfiguration().cyclic.load, loadBefore);
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
firstView.machinePanel.modeDrop.Value = 'Force';
firstView.machinePanel.modeDrop.ValueChangedFcn( ...
    firstView.machinePanel.modeDrop, []);
verifyNotEmpty(testCase, findForceReferenceLines(firstView.fig));
batch = struct( ...
    'Force', struct('X', -1:-1:-200, 'Y', -201:-1:-400), ...
    'Displacement', struct('X', 401:600, 'Y', 601:800));
firstView.appendPlotData(batch, 0.01);
verifyEqual(testCase, findall(firstView.fig, ...
    'Tag', 'MaximumForceX').Value, -200);
verifyEqual(testCase, findall(firstView.fig, ...
    'Tag', 'MaximumForceY').Value, -400);
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
fpsField = findall(firstView.settingsWindow.fig, ...
    'Tag', 'Hardware-acquisitionFrameRateAbs');
reliefX = findall(firstView.settingsWindow.fig, ...
    'Tag', 'Hardware-fForceReliefVelocity');
verifyEqual(testCase, fpsField.Limits, [0, 60]);
verifyEqual(testCase, numel(reliefX), 2);
for index = 1:numel(reliefX)
    verifyEqual(testCase, reliefX(index).Limits, [0, 5]);
end
firstView.settingsWindow.close();
firstView.reportApplicationAlert('Recording', 'Disk write failed.');
firstView.updateErrorStatus(false, '');
verifyTrue(testCase, firstView.applicationAlert.active);
verifyEqual(testCase, firstView.machinePanel.errorButton.Text, ...
    'APP ALERT / ACK');
firstView.acknowledgeApplicationAlert();
verifyFalse(testCase, firstView.applicationAlert.active);
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

function lines = findForceReferenceLines(fig)
lines = findall(fig, 'Type', 'ConstantLine');
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
