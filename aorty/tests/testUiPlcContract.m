function tests = testUiPlcContract
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.root = fileparts(fileparts(mfilename('fullpath')));
end

function testControllerBuildsOnlyVersionSixFields(testCase)
root = testCase.TestData.root;
source = fileread(fullfile(root, 'test_definition', ...
    'TestCommandBuilder.m'));
verifyNotEmpty(testCase, strfind(source, ...
    'command.preCycleLoadValue = pre.load.(field)'));
verifyNotEmpty(testCase, strfind(source, ...
    '''preloadValue'', 0, ''preCycleLoadValue'', 0'));
verifyEmpty(testCase, strfind(source, 'command.preLoadValue'));
verifyEmpty(testCase, strfind(source, 'command.forceDropPercent'));
verifyEmpty(testCase, strfind(source, 'command.forceDropThreshold'));
verifyNotEmpty(testCase, strfind(source, ...
    'command.preTestForceTolerance'));
verifyNotEmpty(testCase, strfind(source, ...
    'command.singleForceHoldTime'));
verifyNotEmpty(testCase, strfind(source, ...
    'command.cyclicForceHoldTime'));
end

function testRemovedControlsAndNewUiElements(testCase)
root = testCase.TestData.root;
panelSource = fileread(fullfile(root, 'ui', 'TestPanel.m'));
tabsSource = fileread(fullfile(root, 'ui', 'components', ...
    'TestDefinitionTabs.m'));
factorySource = fileread(fullfile(root, 'ui', 'components', ...
    'TestControlFactory.m'));
viewSource = fileread(fullfile(root, 'ui', 'View.m'));
machineSource = fileread(fullfile(root, 'ui', 'MachinePanel.m'));
dialogSource = fileread(fullfile(root, 'ui', 'dialogs', ...
    'promptPostProcessOptions.m'));
testUiSource = [panelSource, tabsSource, factorySource];

verifyEmpty(testCase, strfind(testUiSource, 'Arm above force'));
verifyEmpty(testCase, strfind(testUiSource, '''Force drop'''));
verifyNotEmpty(testCase, strfind(testUiSource, ...
    '''Pre-cycle load force'''));
verifyNotEmpty(testCase, strfind(testUiSource, ...
    '''Initial preload force'''));
verifyNotEmpty(testCase, strfind(tabsSource, ...
    '''Force tolerance'', 1, ''[%]'''));
verifyNotEmpty(testCase, strfind(tabsSource, ...
    '''General settings'''));
verifyNotEmpty(testCase, strfind(tabsSource, ...
    '''Preload'''));
verifyNotEmpty(testCase, strfind(tabsSource, ...
    '''Precycle'''));
verifyNotEmpty(testCase, strfind(tabsSource, ...
    '''Primary endpoint hold time'''));
verifyNotEmpty(testCase, strfind(tabsSource, ...
    '''Load/unload endpoint hold time'''));
verifyNotEmpty(testCase, strfind(testUiSource, ...
    '''ItemsData'', cycleValues'));
verifyNotEmpty(testCase, strfind(testUiSource, ...
    'getForceReferencePreview'));
verifyNotEmpty(testCase, strfind(testUiSource, ...
    '''Sampling period'''));
verifyNotEmpty(testCase, strfind(testUiSource, ...
    '''Include pre-test and post-test'''));
verifyEmpty(testCase, strfind(testUiSource, ...
    'controls.pre.cameraPeriod'));

verifyNotEmpty(testCase, strfind(viewSource, ...
    '''Text'', ''Post-process data'''));
verifyNotEmpty(testCase, strfind(viewSource, ...
    'runManualPostProcessing'));
verifyNotEmpty(testCase, strfind(dialogSource, ...
    '''Value'', 0.1, ''Limits'', [0, Inf]'));
verifyNotEmpty(testCase, strfind(viewSource, ...
    'updateSystemStatusIndicator'));
verifyNotEmpty(testCase, strfind(machineSource, ...
    'updateForceReferenceLines'));
verifyNotEmpty(testCase, strfind(machineSource, ...
    'absolute NC axis'));
verifyNotEmpty(testCase, strfind(machineSource, ...
    '''Samples shown'''));
verifyNotEmpty(testCase, strfind(machineSource, ...
    'updateHoverInspector'));
end

function testTrackedConfigurationsUseCurrentContract(testCase)
root = testCase.TestData.root;
files = {
    fullfile(root, 'configuration', 'profiles', ...
        'application', 'default.json')
    fullfile(root, 'configuration', 'profiles', ...
        'application', 'new_test.json')
    fullfile(root, 'examples', 'general_test_example.json')};
for index = 1:numel(files)
    text = fileread(files{index});
    verifyEmpty(testCase, strfind(text, 'forceDrop'));
    verifyEmpty(testCase, strfind(text, 'failureThreshold'));
end

for index = 1:2
    preset = jsondecode(fileread(files{index}));
    verifyEqual(testCase, preset.schemaVersion, 2);
    verifyGreaterThanOrEqual(testCase, preset.pre.cycles, 1);
    verifyLessThanOrEqual(testCase, preset.pre.cycles, 50);
    verifyGreaterThanOrEqual(testCase, preset.cyclic.cycles, 1);
    verifyLessThanOrEqual(testCase, preset.cyclic.cycles, 50);
    verifyFalse(testCase, isfield(preset.pre, 'cameraPeriod'));
    verifyFalse(testCase, isfield(preset.single, 'cameraPeriod'));
    verifyFalse(testCase, isfield(preset.cyclic, 'cameraPeriod'));
    verifyTrue(testCase, islogical(preset.pre.record) && ...
        isscalar(preset.pre.record));
    verifyEqual(testCase, ...
        sort(fieldnames(preset.pre.forceTolerance)), ...
        sort({'lock'; 'x'; 'y'}));
    verifyFalse(testCase, isfield(preset.pre, 'cyclicForceTolerance'));
    verifyFalse(testCase, ...
        isfield(preset.pre.preload, 'forceTolerance'));
    verifyTrue(testCase, isfield(preset.single, 'postProcess'));
    verifyTrue(testCase, isfield(preset.cyclic, 'postProcess'));
    verifyEqual(testCase, sort(fieldnames(preset.single.postProcess)), ...
        sort({'enabled'; 'includePrePost'; 'samplingPeriod'}));
    verifyEqual(testCase, sort(fieldnames(preset.cyclic.postProcess)), ...
        sort({'enabled'; 'includePrePost'; 'samplingPeriod'}));
end

general = jsondecode(fileread(files{3}));
verifyEqual(testCase, general.schemaVersion, 2);
verifyEqual(testCase, sort(fieldnames(general.cyclic.forceTolerance)), ...
    sort({'x'; 'y'}));
verifyEqual(testCase, sort(fieldnames(general.camera)), ...
    sort({'includePrePost'; 'postProcessEnabled'; 'samplingPeriod'}));
end

function testCameraAcquisitionHasNoSoftwareSamplingGate(testCase)
root = testCase.TestData.root;
cameraSource = fileread(fullfile(root, 'hardware', 'Camera.m'));
controllerSource = fileread(fullfile(root, 'application', 'Control.m'));
viewSource = fileread(fullfile(root, 'ui', 'View.m'));
verifyEmpty(testCase, strfind(cameraSource, 'recordingPeriod'));
verifyEmpty(testCase, strfind(cameraSource, 'lastRecordingTime'));
verifyNotEmpty(testCase, strfind(cameraSource, ...
    'camera.recordingSession.saveCameraFrame(frame, timeStamp)'));
verifyNotEmpty(testCase, strfind(viewSource, ...
    'settings.applyCameraConfig()'));
verifyNotEmpty(testCase, strfind(viewSource, ...
    'settings.applyPlcConfig()'));
verifyNotEmpty(testCase, strfind(viewSource, ...
    'loadStartupDefaults'));
verifyNotEmpty(testCase, strfind(controllerSource, ...
    'config.single.postProcess, true'));
verifyNotEmpty(testCase, strfind(controllerSource, ...
    'config.cyclic.postProcess, true'));
verifyNotEmpty(testCase, strfind(controllerSource, ...
    'if postSettings.enabled && isempty(flushError)'));
verifyNotEmpty(testCase, strfind(controllerSource, ...
    '''outputFolder'', fullfile('));
end

function testDialogsRestoreOwningWindowFocus(testCase)
root = testCase.TestData.root;
files = {
    fullfile(root, 'ui', 'SettingsWindow.m')
    fullfile(root, 'ui', 'TestPanel.m')
    fullfile(root, 'ui', 'View.m')
    fullfile(root, 'ui', 'components', 'TestDefinitionTabs.m')
    fullfile(root, 'ui', 'dialogs', 'promptPostProcessOptions.m')
    fullfile(root, 'application', 'Control.m')};

for index = 1:numel(files)
    source = fileread(files{index});
    verifyNotEmpty(testCase, strfind(source, 'restoreFigureFocus('), ...
        sprintf('Missing focus restoration in %s.', files{index}));
end

helper = fileread(fullfile(root, 'ui', 'support', ...
    'restoreFigureFocus.m'));
verifyNotEmpty(testCase, strfind(helper, 'drawnow'));
verifyNotEmpty(testCase, strfind(helper, 'figure(parentFig)'));
end

function testHardwareSettingsFieldsAreScrollable(testCase)
source = fileread(fullfile(testCase.TestData.root, ...
    'ui', 'SettingsWindow.m'));
verifyNotEmpty(testCase, strfind(source, "grid.Scrollable = 'on';"));
end
