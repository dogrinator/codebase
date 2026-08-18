function tests = testRecordingAnalysis
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(root));
testCase.TestData.previousFigureVisibility = ...
    get(groot, 'DefaultFigureVisible');
set(groot, 'DefaultFigureVisible', 'off');
end

function teardownOnce(testCase)
set(groot, 'DefaultFigureVisible', ...
    testCase.TestData.previousFigureVisibility);
close all force;
end

function testLoadsHdf5WithoutCameraBinary(testCase)
[folder, filename] = createRecording();
cleanup = onCleanup(@() removeFolder(folder));

validator = RecordingAnalysis(filename);

verifyEqual(testCase, validator.FilePath, fileattribName(filename));
verifyFalse(testCase, isfile(fullfile(folder, 'cam.bin')));
verifyEqual(testCase, validator.Recording.SchemaVersion, 1);
verifyEqual(testCase, validator.Recording.ActiveAxes, {'X', 'Y'});
verifyEqual(testCase, height(validator.Recording.X), 41);
verifyEqual(testCase, height(validator.Recording.Y), 41);
verifyEqual(testCase, height(validator.Recording.Camera), 41);
verifyEqual(testCase, validator.Recording.Test.X.preloadValue, 1);
verifyEqual(testCase, validator.Recording.Controller.Y.fKp, 1);
clear cleanup;
end

function testAnalysisReturnsKnownMetrics(testCase)
[folder, filename] = createRecording();
cleanup = onCleanup(@() removeFolder(folder));
validator = RecordingAnalysis(filename);

metrics = validator.analyze();

verifyEqual(testCase, metrics.Integrity.FileStatus, "completed");
verifyTrue(testCase, metrics.Integrity.CameraCountMatches);
verifyTrue(testCase, metrics.Integrity.XCountMatches);
verifyTrue(testCase, metrics.Integrity.YCountMatches);
verifyEqual(testCase, height(metrics.Axes), 2);
xAxis = metrics.Axes(metrics.Axes.Axis == "X", :);
verifyEqual(testCase, xAxis.SampleCount, 41);
verifyEqual(testCase, xAxis.BaselineForce, 0, 'AbsTol', 1e-12);
verifyEqual(testCase, xAxis.ForceMax, 2.08, 'AbsTol', 1e-12);
verifyGreaterThan(testCase, height(metrics.Phases), 2);

preload = metrics.Targets( ...
    metrics.Targets.Axis == "X" & ...
    metrics.Targets.Role == "Preload", :);
verifyEqual(testCase, height(preload), 1);
verifyTrue(testCase, preload.MetricsAvailable);
verifyEqual(testCase, preload.Target, 1);
verifyEqual(testCase, preload.Tolerance, 0.1);
verifyEqual(testCase, preload.ConfiguredHoldSeconds, 0.5);
verifyEqual(testCase, preload.TimeToFirstToleranceSeconds, ...
    0.2, 'AbsTol', 1e-12);
verifyEqual(testCase, preload.DirectionalOvershoot, ...
    0.05, 'AbsTol', 1e-12);
verifyGreaterThanOrEqual(testCase, ...
    preload.LongestContinuousInToleranceSeconds, 1.0);
verifyEmpty(testCase, metrics.Warnings);
clear cleanup;
end

function testPlotContainsRawTracesPhasesAndTargets(testCase)
[folder, filename] = createRecording();
cleanup = onCleanup(@() removeFolder(folder));
validator = RecordingAnalysis(filename);

fig = validator.plot();
figureCleanup = onCleanup(@() close(fig));
axesHandles = findall(fig, 'Type', 'axes');
lines = findall(fig, 'Type', 'line');
patches = findall(fig, 'Type', 'patch');

verifyEqual(testCase, numel(axesHandles), 2);
verifyGreaterThanOrEqual(testCase, numel(lines), 8);
verifyGreaterThan(testCase, numel(patches), 2);
displayNames = string(get(lines, 'DisplayName'));
verifyTrue(testCase, any(displayNames == "X axis"));
verifyTrue(testCase, any(displayNames == "Y axis"));
verifySubstring(testCase, fig.Name, 'Test validation');
clear figureCleanup cleanup;
end

function testSingleAxisRecordingPlotsOnlyActiveAxis(testCase)
[folder, filename] = createRecording();
cleanup = onCleanup(@() removeFolder(folder));
h5writeatt(filename, '/settings/test', 'active_axes', 'X');
validator = RecordingAnalysis(filename);

fig = validator.plot();
figureCleanup = onCleanup(@() close(fig));
lines = findall(fig, 'Type', 'line');
displayNames = string(get(lines, 'DisplayName'));

verifyEqual(testCase, validator.Recording.ActiveAxes, {'X'});
verifyTrue(testCase, any(displayNames == "X axis"));
verifyFalse(testCase, any(displayNames == "Y axis"));
clear figureCleanup cleanup;
end

function testEmptyCameraRowsProduceMetricsWarning(testCase)
[folder, filename] = createRecording(false);
cleanup = onCleanup(@() removeFolder(folder));
validator = RecordingAnalysis(filename);

metrics = validator.analyze();
fig = validator.plot();
figureCleanup = onCleanup(@() close(fig));

verifyEmpty(testCase, metrics.Phases);
verifyTrue(testCase, any(contains( ...
    metrics.Warnings, 'Camera status rows')));
verifyFalse(testCase, any(metrics.Targets.MetricsAvailable));
verifyEqual(testCase, numel(findall(fig, 'Type', 'axes')), 2);
clear figureCleanup cleanup;
end

function testLegacyTimestampsAreRecovered(testCase)
[folder, filename] = createRecording();
cleanup = onCleanup(@() removeFolder(folder));
values = h5read(filename, '/plc/X/samples');
values(1, 4) = values(1, 3) - 0.01;
h5write(filename, '/plc/X/samples', values);

validator = RecordingAnalysis(filename);

verifyGreaterThanOrEqual(testCase, ...
    diff(validator.Recording.X.ElapsedSeconds), 0);
verifyEqual(testCase, validator.Recording.X.ElapsedSeconds', ...
    0:0.1:4, 'AbsTol', 1e-12);
verifyTrue(testCase, any(contains( ...
    validator.Recording.Warnings, 'X-axis timestamps')));
clear cleanup;
end

function testInterruptedAndMismatchedCountsAreReported(testCase)
[folder, filename] = createRecording();
cleanup = onCleanup(@() removeFolder(folder));
h5writeatt(filename, '/metadata', 'status', 'aborted');
h5writeatt(filename, '/metadata', 'x_sample_count', uint64(999));
h5writeatt(filename, '/metadata', 'sample_loss_detected', uint8(1));
h5writeatt(filename, '/metadata', 'x_dropped_sample_count', uint64(3));
validator = RecordingAnalysis(filename);

metrics = validator.analyze();

verifyEqual(testCase, metrics.Integrity.FileStatus, "aborted");
verifyFalse(testCase, metrics.Integrity.XCountMatches);
verifyTrue(testCase, metrics.Integrity.SampleLossDetected);
verifyTrue(testCase, any(contains(metrics.Warnings, 'aborted')));
verifyTrue(testCase, any(contains(metrics.Warnings, 'count is 999')));
verifyTrue(testCase, any(contains(metrics.Warnings, 'dropped PLC')));
clear cleanup;
end

function testVariableCycleTargetsAreNotGuessed(testCase)
[folder, filename] = createRecording();
cleanup = onCleanup(@() removeFolder(folder));
h5writeatt(filename, '/settings/test/X', 'loadValues', [1, 2]);
validator = RecordingAnalysis(filename);

metrics = validator.analyze();
xLoad = metrics.Targets( ...
    metrics.Targets.Axis == "X" & ...
    metrics.Targets.Role == "Load endpoint", :);

verifyEqual(testCase, height(xLoad), 2);
verifyTrue(testCase, all(xLoad.Ambiguous));
verifyFalse(testCase, any(xLoad.MetricsAvailable));
verifyTrue(testCase, all(isnan( ...
    xLoad.TimeToFirstToleranceSeconds)));
verifyTrue(testCase, any(contains( ...
    metrics.Warnings, 'variable per-cycle targets')));
clear cleanup;
end

function testConvenienceOpenReturnsAllOutputs(testCase)
[folder, filename] = createRecording();
cleanup = onCleanup(@() removeFolder(folder));

[metrics, fig, validator] = RecordingAnalysis.open(filename);
figureCleanup = onCleanup(@() close(fig));

verifyClass(testCase, validator, 'RecordingAnalysis');
verifyClass(testCase, metrics.Integrity, 'table');
verifyTrue(testCase, isgraphics(fig, 'figure'));
clear figureCleanup cleanup;
end

function testInvalidSchemaMissingDataAndNonfiniteSamples(testCase)
[folder1, filename1] = createRecording();
cleanup1 = onCleanup(@() removeFolder(folder1));
h5write(filename1, '/metadata/schema_version', uint32(2));
verifyError(testCase, @() RecordingAnalysis(filename1), ...
    'RecordingAnalysis:SchemaVersion');

folder2 = tempname;
mkdir(folder2);
cleanup2 = onCleanup(@() removeFolder(folder2));
filename2 = fullfile(folder2, 'recording.h5');
h5create(filename2, '/metadata/schema_version', [1, 1], ...
    'Datatype', 'uint32');
h5write(filename2, '/metadata/schema_version', uint32(1));
verifyError(testCase, @() RecordingAnalysis(filename2), ...
    'RecordingAnalysis:InvalidRecording');

[folder3, filename3] = createRecording();
cleanup3 = onCleanup(@() removeFolder(folder3));
values = h5read(filename3, '/plc/Y/samples');
values(2, 5) = NaN;
h5write(filename3, '/plc/Y/samples', values);
verifyError(testCase, @() RecordingAnalysis(filename3), ...
    'RecordingAnalysis:InvalidRecording');
clear cleanup3 cleanup2 cleanup1;
end

function [folder, filename] = createRecording(withCamera)
if nargin < 1
    withCamera = true;
end
folder = tempname;
mkdir(folder);
filename = fullfile(folder, 'recording.h5');
times = 0:0.1:4;
count = numel(times);

forceX = zeros(1, count);
pre = times > 0.5 & times < 2;
forceX(pre) = [0.5, 0.85, 0.95, 1.05, ...
    ones(1, sum(pre) - 4)];
cyclic = times >= 2;
xPattern = repmat([1.5, 1.9, 2.02, 2.08, 2.0, 1.98, 1.2], ...
    1, ceil(sum(cyclic) / 7));
forceX(cyclic) = xPattern(1:sum(cyclic));

forceY = zeros(1, count);
forceY(pre) = [0.1, 0.2, 0.28, 0.31, ...
    0.3 * ones(1, sum(pre) - 4)];
yPattern = repmat([0.4, 0.55, 0.61, 0.62, 0.6, 0.59, 0.3], ...
    1, ceil(sum(cyclic) / 7));
forceY(cyclic) = yPattern(1:sum(cyclic));
positionX = 48 - 0.2 * forceX;
positionY = 48 - 0.8 * forceY;

h5create(filename, '/metadata/schema_version', [1, 1], ...
    'Datatype', 'uint32');
h5write(filename, '/metadata/schema_version', uint32(1));
h5create(filename, '/camera/records', [3, Inf], ...
    'ChunkSize', [3, 64], 'Datatype', 'double');
h5create(filename, '/plc/X/samples', [4, count], ...
    'Datatype', 'double');
h5create(filename, '/plc/Y/samples', [4, count], ...
    'Datatype', 'double');
h5write(filename, '/plc/X/samples', ...
    [times; forceX; forceX + 0.2; positionX]);
h5write(filename, '/plc/Y/samples', ...
    [times; forceY; forceY - 0.1; positionY]);

statuses = zeros(1, count);
statuses(pre) = 10;
statuses(cyclic) = 21;
if withCamera
    h5write(filename, '/camera/records', ...
        [1:count; times; statuses], [1, 1], [3, count]);
    cameraCount = count;
else
    cameraCount = 0;
end

createMarker(filename, '/settings/plc/X/marker');
createMarker(filename, '/settings/plc/Y/marker');
createMarker(filename, '/settings/test/marker');
createMarker(filename, '/settings/test/X/marker');
createMarker(filename, '/settings/test/Y/marker');

h5writeatt(filename, '/metadata', 'start_time', ...
    '2026-08-06 18:54:12.503');
h5writeatt(filename, '/metadata', 'status', 'completed');
h5writeatt(filename, '/metadata', 'plc_interval_seconds', 0.1);
h5writeatt(filename, '/metadata', 'camera_record_count', uint64(cameraCount));
h5writeatt(filename, '/metadata', 'x_sample_count', uint64(count));
h5writeatt(filename, '/metadata', 'y_sample_count', uint64(count));
h5writeatt(filename, '/metadata', 'x_dropped_sample_count', uint64(0));
h5writeatt(filename, '/metadata', 'y_dropped_sample_count', uint64(0));
h5writeatt(filename, '/metadata', 'sample_loss_detected', uint8(0));
h5writeatt(filename, '/metadata', 'plc_restart_detected', uint8(0));
h5writeatt(filename, '/camera', 'width', 64);
h5writeatt(filename, '/camera', 'height', 64);
h5writeatt(filename, '/settings/test', 'test_kind', 'cyclic');
h5writeatt(filename, '/settings/test', 'active_axes', 'X,Y');

writeController(filename, 'X', 2.5);
writeController(filename, 'Y', 0.9);
writeCommand(filename, 'X', 1, 2, 0.05);
writeCommand(filename, 'Y', 0.3, 0.6, 0.02);
end

function writeController(filename, axisName, maxForce)
path = ['/settings/plc/', axisName];
h5writeatt(filename, path, 'fKp', 1);
h5writeatt(filename, path, 'fKi', 0.1);
h5writeatt(filename, path, 'fIntegralLimit', 10);
h5writeatt(filename, path, 'fForceTolerance', 0.1);
h5writeatt(filename, path, 'fMaxForce', maxForce);
end

function writeCommand(filename, axisName, preload, cyclicLoad, tolerance)
path = ['/settings/test/', axisName];
h5writeatt(filename, path, 'includePreTest', uint8(1));
h5writeatt(filename, path, 'preTestOnly', uint8(0));
h5writeatt(filename, path, 'preCycleCount', int32(0));
h5writeatt(filename, path, 'preloadEnabled', uint8(1));
h5writeatt(filename, path, 'preloadValue', preload);
h5writeatt(filename, path, 'preCycleLoadValue', cyclicLoad);
h5writeatt(filename, path, 'preUnloadValue', 0);
h5writeatt(filename, path, 'preUnloadToStart', uint8(1));
h5writeatt(filename, path, 'preTestForceTolerance', tolerance * 2);
h5writeatt(filename, path, 'preloadHoldTime', 0.5);
h5writeatt(filename, path, 'preCycleHoldTime', 0.5);
h5writeatt(filename, path, 'cycleCount', int32(2));
h5writeatt(filename, path, 'loadMode', int32(2));
h5writeatt(filename, path, 'loadValues', [cyclicLoad, cyclicLoad]);
h5writeatt(filename, path, 'unloadMode', int32(1));
h5writeatt(filename, path, 'unloadValues', [0, 0]);
h5writeatt(filename, path, 'cyclicForceTolerance', tolerance);
h5writeatt(filename, path, 'cyclicForceHoldTime', 1);
h5writeatt(filename, path, 'stop1Mode', int32(1));
h5writeatt(filename, path, 'stop1Value', 0);
h5writeatt(filename, path, 'stop2Mode', int32(0));
h5writeatt(filename, path, 'stop2Value', 0);
h5writeatt(filename, path, 'singleForceTolerance', tolerance);
h5writeatt(filename, path, 'singleForceHoldTime', 0);
h5writeatt(filename, path, 'postTestMode', int32(0));
end

function createMarker(filename, path)
h5create(filename, path, [1, 1], 'Datatype', 'uint8');
h5write(filename, path, uint8(1));
end

function name = fileattribName(filename)
[ok, attributes] = fileattrib(filename);
assert(ok);
name = attributes.Name;
end

function removeFolder(folder)
if isfolder(folder)
    rmdir(folder, 's');
end
end
