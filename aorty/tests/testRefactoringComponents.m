function tests = testRefactoringComponents
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(root));
testCase.TestData.root = root;
end

function testPresetCommandBuilderMatchesCurrentContract(testCase)
model = Model();
settings = Settings(Plc(model), Camera(model));
settings.loadHwConfig('default');
settings.loadAppConfig('default');
settings.hwConfig.plc.xAxis.fMaxForce = 10;
settings.hwConfig.plc.yAxis.fMaxForce = 20;
settings.appConfig.single.forceTolerance.x = 5;
settings.appConfig.single.forceTolerance.y = 5;

single = TestCommandBuilder.fromPreset( ...
    settings.appConfig, 'single', settings.hwConfig);
verifyNotEmpty(testCase, single.X);
verifyNotEmpty(testCase, single.Y);
expectedPrimaryMode = 1 + ...
    strcmpi(settings.appConfig.single.primaryMode, 'Force');
verifyEqual(testCase, single.X.stop1Mode, expectedPrimaryMode);
verifyEqual(testCase, single.X.testRate, ...
    settings.appConfig.single.rate.x);
verifyEqual(testCase, single.X.singleForceTolerance, ...
    0.5);
verifyEqual(testCase, single.Y.singleForceTolerance, ...
    1.0);
verifyEqual(testCase, single.Y.singleForceHoldTime, ...
    settings.appConfig.single.holdTime.y);

cyclic = TestCommandBuilder.fromPreset( ...
    settings.appConfig, 'cyclic', settings.hwConfig);
verifyEqual(testCase, cyclic.X.cycleCount, ...
    settings.appConfig.cyclic.cycles);
verifyEqual(testCase, numel(cyclic.X.loadValues), ...
    settings.appConfig.cyclic.cycles);
verifyEqual(testCase, cyclic.X.cyclicForceTolerance, ...
    settings.appConfig.cyclic.forceTolerance.x * 0.1);
verifyEqual(testCase, cyclic.Y.cyclicForceHoldTime, ...
    settings.appConfig.cyclic.holdTime.y);

config = settings.appConfig;
config.pre.forceTolerance.x = 101;
verifyError(testCase, ...
    @() TestCommandBuilder.fromPreset( ...
    config, 'pre', settings.hwConfig), ...
    'Control:InvalidTolerancePercent');
end

function testGeneralCommandBuilder(testCase)
filename = fullfile(testCase.TestData.root, ...
    'examples', 'general_test_example.json');
definition = GeneralTestDefinition.load(filename);
commands = TestCommandBuilder.fromGeneral(definition);
verifyEqual(testCase, commands.X.cycleCount, 3);
verifyEqual(testCase, commands.Y.cycleCount, 3);
verifyEqual(testCase, commands.X.postTestMode, 2);
end

function testAcquisitionBufferAppendSnapshotAndClear(testCase)
buffer = AcquisitionBuffer();
base = datetime('now');
buffer.append([1, 2], 3, [4, 5], 6, [7, 8], 9, ...
    base + milliseconds([0, 10]), base);
batch = buffer.plotBatch();
verifyEqual(testCase, batch.Force.X, [1, 2]);
verifyEqual(testCase, batch.Force.Y, 3);
verifyEqual(testCase, batch.Displacement.X, [7, 8]);
verifyEqual(testCase, batch.Displacement.Y, 9);
buffer.clear();
verifyEmpty(testCase, buffer.forceX);
verifyEmpty(testCase, buffer.positionY);
verifyEmpty(testCase, buffer.timestampX);
end

function testForceReferenceBuilderPreTest(testCase)
model = Model();
settings = Settings(Plc(model), Camera(model));
settings.loadHwConfig('default');
settings.loadAppConfig('default');
config = settings.appConfig;
config.pre.preload.enabled = true;
config.pre.cyclic = true;
config.pre.unloadToStart = false;
config.pre.preload.value.x = 12;
config.pre.load.x = 8;
config.pre.unload.x = 2;
config.pre.forceTolerance.x = 2;

preview = PlotReferenceBuilder.build( ...
    'Pre-test', config, 'X only', settings.hwConfig);
verifyEqual(testCase, preview.testType, 'pre');
verifyEqual(testCase, numel(preview.X), 3);
verifyEmpty(testCase, preview.Y);
verifyEqual(testCase, {preview.X.label}, ...
    {'Initial preload', 'Pre-cycle load', 'Pre-cycle unload'});
verifyEqual(testCase, [preview.X.target], [12, 8, 2]);
expectedTolerance = ...
    config.pre.forceTolerance.x * ...
    settings.hwConfig.plc.xAxis.fMaxForce / 100;
verifyEqual(testCase, [preview.X.tolerance], ...
    repmat(expectedTolerance, 1, 3));
verifyEqual(testCase, [preview.X.tolerancePercent], [2, 2, 2]);

config.pre.unloadToStart = true;
preview = PlotReferenceBuilder.build( ...
    'Pre-test', config, 'Both', settings.hwConfig);
verifyEqual(testCase, numel(preview.X), 2);
verifyEqual(testCase, numel(preview.Y), 2);
end

function testForceReferenceBuilderMixedModesAndGrouping(testCase)
model = Model();
settings = Settings(Plc(model), Camera(model));
settings.loadHwConfig('default');
settings.loadAppConfig('default');
config = settings.appConfig;
config.single.primaryMode = 'Displacement';
config.single.secondaryMode = 'Force';
config.single.secondary.x = 15;
config.single.forceTolerance.x = 2.5;

preview = PlotReferenceBuilder.build( ...
    'Single test', config, 'X only', settings.hwConfig);
verifyEqual(testCase, numel(preview.X), 1);
verifyEqual(testCase, preview.X.label, 'Secondary endpoint');
verifyEqual(testCase, preview.X.target, 15);
verifyEqual(testCase, preview.X.tolerance, ...
    config.single.forceTolerance.x * ...
    settings.hwConfig.plc.xAxis.fMaxForce / 100);
verifyEqual(testCase, preview.X.tolerancePercent, 2.5);

entries = [preview.X, preview.X];
entries(2).label = 'Second name';
grouped = PlotReferenceBuilder.group(entries);
verifyEqual(testCase, numel(grouped), 1);
verifyEqual(testCase, grouped.label, ...
    'Secondary endpoint / Second name');

preview = PlotReferenceBuilder.build( ...
    'General test', config, 'Both', settings.hwConfig);
verifyEmpty(testCase, preview.testType);
verifyEmpty(testCase, preview.X);
verifyEmpty(testCase, preview.Y);
end

function testStrictHardwareConfigDoesNotInsertDefaults(testCase)
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
model = Model();
settings = Settings(Plc(model), Camera(model));
settings.hwPath = folder;
config = jsondecode(fileread(fullfile( ...
    testCase.TestData.root, '.config', 'hwConfig', 'default.json')));
config.plc.xAxis = rmfield(config.plc.xAxis, ...
    'fForceReliefVelocity');
writeJson(fullfile(folder, 'invalid.json'), config);

verifyError(testCase, @() settings.loadHwConfig('invalid'), ...
    'PLC:InvalidConfiguration');
verifyEmpty(testCase, settings.hwConfig);
clear cleanup;
end

function writeJson(filename, value)
fid = fopen(filename, 'w');
assert(fid ~= -1);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(value));
end
