function tests = testPostProcessor
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(root));
testCase.TestData.root = root;
end

function testSystemStatusSelectionAndSamplingRestart(testCase)
base = datetime(2026, 7, 28, 12, 0, 0);
timestamps = base + seconds((0:7)' .* 0.05);
statuses = [10; 10; 20; 20; 30; 30; 21; 21];
cameraRows = table((1:8)', timestamps, statuses, ...
    'VariableNames', {'Index', 'Timestamp', 'SystemStatus'});

mainRows = PostProcessor.selectFrameRows(cameraRows, 0.1, 'main-test');
verifyEqual(testCase, mainRows, [3; 7]);

completeRows = PostProcessor.selectFrameRows( ...
    cameraRows, 0.1, 'complete-test');
verifyEqual(testCase, completeRows, [1; 3; 5; 7]);

allMainRows = PostProcessor.selectFrameRows(cameraRows, 0, 'main-test');
verifyEqual(testCase, allMainRows, [3; 4; 7; 8]);
end

function testIdleFramesAreExcludedFromAllRecordedScope(testCase)
base = datetime(2026, 7, 28, 12, 0, 0);
cameraRows = table((1:5)', base + milliseconds((0:4)' * 10), ...
    [0; 10; 0; 20; 30], ...
    'VariableNames', {'Index', 'Timestamp', 'SystemStatus'});

rows = PostProcessor.selectFrameRows( ...
    cameraRows, 0, 'all-recorded');

verifyEqual(testCase, rows, [2; 4; 5]);
end

function testCoverageMaskIsAppliedBeforeIntervalSampling(testCase)
base = datetime(2026, 7, 28, 12, 0, 0);
cameraRows = table((1:8)', base + seconds((0:7)' .* 0.05), ...
    repmat(20, 8, 1), ...
    'VariableNames', {'Index', 'Timestamp', 'SystemStatus'});
coverage = [false; false; true; true; true; true; true; true];

rows = PostProcessor.selectFrameRows( ...
    cameraRows, 0.1, 'main-test', coverage);

verifyEqual(testCase, rows, [3; 5; 7]);
end

function testModelRecordsEveryFrameWithLatestSystemStatus(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));

model = Model();
model.selectedFolder = folder;
model.cameraFrameWidth = 2;
model.cameraFrameHeight = 2;
model.isRecording = true;
model.openFilesRec();

statuses = struct( ...
    'X', struct('systemStatus', int16(10)), ...
    'Y', struct('systemStatus', int16(30)));
model.updateSystemStatus(statuses, {'X'});
model.saveCameraFrame(uint8([1, 2; 3, 4]), ...
    datetime(2026, 7, 28, 12, 0, 0));
model.updateSystemStatus(statuses, {'Y'});
model.saveCameraFrame(uint8([5, 6; 7, 8]), ...
    datetime(2026, 7, 28, 12, 0, 0) + milliseconds(50));
model.updateSystemStatus(statuses, {'X', 'Y'});
model.saveCameraFrame(uint8([9, 10; 11, 12]), ...
    datetime(2026, 7, 28, 12, 0, 0) + milliseconds(100));
sampleTime = datetime('now');
model.saveAxisSamples('X', sampleTime, 1, 2, 3);
model.saveAxisSamples('Y', sampleTime, 4, 5, 6);
model.isRecording = false;
model.finalizeRecording('completed', 'Completed');

rows = PostProcessor.readRecording(folder).cameraRows;
verifyEqual(testCase, rows.Index, [1; 2; 3]);
verifyEqual(testCase, rows.SystemStatus, [10; 30; 10]);
info = dir(fullfile(folder, 'cam.bin'));
verifyEqual(testCase, info.bytes, 12);
end

function testLegacyCsvRecordingsAreRejected(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
filename = fullfile(folder, 'legacy_recording.csv');
fid = fopen(filename, 'w');
assert(fid ~= -1);
fileCleanup = onCleanup(@() fclose(fid));
fprintf(fid, 'Index,Timestamp,SystemStatus\n');
fprintf(fid, '1,12:00:00.000,20\n');
clear fileCleanup

verifyError(testCase, ...
    @() PostProcessor.readRecording(folder), ...
    'PostProcessor:MissingRecording');
end

function testManualScopeAndUniqueOutput(testCase)
folder = createSyntheticRecording();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
output = fullfile(folder, 'processed_frames_manual_20260728_120000_000');
result = PostProcessor.processData(folder, struct( ...
    'samplingPeriod', 0, ...
    'phaseScope', 'main-test', ...
    'outputFolder', output));

verifyEqual(testCase, result.outputFolder, output);
verifyEqual(testCase, result.exportedFrameCount, 2);
files = dir(fullfile(output, 'processed_frame_*.tiff'));
verifyEqual(testCase, {files.name}', ...
    {'processed_frame_0001.tiff'; 'processed_frame_0002.tiff'});
end

function testTiffUsesLegacyBaslerHeader(testCase)
folder = createSyntheticRecording();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
output = fullfile(folder, 'processed_frames');
result = PostProcessor.processData(folder, struct( ...
    'samplingPeriod', 0, ...
    'phaseScope', 'complete-test', ...
    'outputFolder', output));
verifyEqual(testCase, result.exportedFrameCount, 6);

firstFile = fullfile(output, 'processed_frame_0001.tiff');
secondFile = fullfile(output, 'processed_frame_0002.tiff');
verifyTrue(testCase, isfile(firstFile));
verifyTrue(testCase, isfile(secondFile));

cameraRows = PostProcessor.readRecording(folder).cameraRows;
baseTime = cameraRows.Timestamp(1);
baseTimeStr = char(string(baseTime, 'dd.MM.yyyy HH:mm:ss'));
delta = cameraRows.Timestamp(1) - baseTime;
delta.Format = 'hh:mm:ss.SSS';
expectedDescription = sprintf([ ...
    'Batch:%s|Profile:Profile : TestBasler.pro|', ...
    'Base:%s|Delta:%s|Index:%05d|', ...
    'TenzoX:%.2f [N] (%.2f [N])|TenzoY:%.2f [N] (%.2f [N])|', ...
    'Thermo:0 [', char(176), 'C]|StepX:%.2f [mm]|StepY:%.2f [mm]'], ...
    folder, baseTimeStr, char(delta), 1, ...
    10, 11, 20, 21, 1.25, 2.5);

fid = fopen(firstFile, 'rb', 'ieee-le');
assert(fid ~= -1);
fileCleanup = onCleanup(@() fclose(fid));
verifyEqual(testCase, char(fread(fid, 2, '*uint8').'), 'II');
verifyEqual(testCase, fread(fid, 1, '*uint16'), uint16(42));
verifyEqual(testCase, fread(fid, 1, '*uint32'), uint32(8));
entryCount = fread(fid, 1, '*uint16');
verifyEqual(testCase, entryCount, uint16(13));
tags = zeros(double(entryCount), 1, 'uint16');
types = zeros(double(entryCount), 1, 'uint16');
counts = zeros(double(entryCount), 1, 'uint32');
values = zeros(double(entryCount), 1, 'uint32');
for index = 1:double(entryCount)
    tags(index) = fread(fid, 1, '*uint16');
    types(index) = fread(fid, 1, '*uint16');
    counts(index) = fread(fid, 1, '*uint32');
    values(index) = fread(fid, 1, '*uint32');
end
verifyEqual(testCase, tags', uint16([ ...
    256, 257, 258, 259, 262, 270, 273, ...
    277, 278, 279, 282, 283, 296]));
verifyEqual(testCase, types(tags == 273), uint16(4));
verifyEqual(testCase, counts(tags == 273), uint32(1));
verifyEqual(testCase, values(tags == 270), uint32(256));
verifyEqual(testCase, values(tags == 273), uint32(1024));
verifyEqual(testCase, values(tags == 279), uint32(64 * 64));
verifyEqual(testCase, fread(fid, 1, '*uint32'), uint32(0));
fseek(fid, 256, 'bof');
headerDescription = char(fread(fid, 768, '*uint8').');
terminator = find(headerDescription == char(0), 1);
verifyNotEmpty(testCase, terminator);
verifyEqual(testCase, headerDescription(1:terminator - 1), ...
    expectedDescription);
clear fileCleanup

fileInfo = dir(firstFile);
verifyEqual(testCase, fileInfo.bytes, 1024 + 64 * 64);
metadata = imfinfo(firstFile);
verifyEqual(testCase, metadata.Width, 64);
verifyEqual(testCase, metadata.Height, 64);
verifyEqual(testCase, metadata.BitDepth, 8);
verifyEqual(testCase, metadata.ColorType, 'grayscale');
verifyEqual(testCase, metadata.Compression, 'Uncompressed');

rawFrame = reshape(uint8(mod(1:4096, 256)), 64, 64);
expectedOverlay = insertText(rawFrame, [20 20], ...
    'X: 10.00000 | Y: 20.00000', ...
    'FontSize', 18, 'TextColor', 'white', 'BoxOpacity', 0.5);
verifyEqual(testCase, imread(firstFile), rgb2gray(expectedOverlay));

secondHeader = readLegacyDescription(secondFile);
verifyNotEmpty(testCase, regexp(secondHeader, ...
    '\|Delta:00:00:00\.050\|Index:00002\|', 'once'));
end

function testLegacyTiffRejectsInvalidDimensionsAndDescription(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
filename = fullfile(folder, 'invalid.tiff');

verifyError(testCase, @() PostProcessor.writeLegacyTiff( ...
    filename, zeros(0, 1, 'uint8'), 'Description'), ...
    'PostProcessor:TiffDimensions');
verifyFalse(testCase, isfile(filename));

verifyError(testCase, @() PostProcessor.writeLegacyTiff( ...
    filename, zeros(1, 65536, 'uint8'), 'Description'), ...
    'PostProcessor:TiffDimensions');
verifyFalse(testCase, isfile(filename));

verifyError(testCase, @() PostProcessor.writeLegacyTiff( ...
    filename, uint8(0), repmat('A', 1, 768)), ...
    'PostProcessor:TiffDescription');
verifyFalse(testCase, isfile(filename));
clear cleanup;
end

function testIncompleteCameraBinaryRecoversCompletePairs(testCase)
folder = createSyntheticRecording();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
filename = fullfile(folder, 'cam.bin');
fid = fopen(filename, 'wb');
assert(fid ~= -1);
fwrite(fid, zeros(1, 64 * 64 * 6 - 1, 'uint8'), 'uint8');
fclose(fid);
output = fullfile(folder, 'processed_frames');

verifyWarning(testCase, @() PostProcessor.processData(folder, struct( ...
    'samplingPeriod', 0, 'phaseScope', 'complete-test', ...
    'outputFolder', output)), 'PostProcessor:RecoveredCameraTail');
clear cleanup;
end

function testElapsedTimestampsCrossMidnight(testCase)
folder = createSyntheticRecording();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
filename = fullfile(folder, 'recording.h5');
h5writeatt(filename, '/metadata', 'start_time', ...
    '2026-07-28 23:59:59.900');
h5write(filename, '/camera/records', ...
    [0, 0.2, 0.3, 0.4, 0.5, 0.6], [2, 1], [1, 6]);
rows = PostProcessor.readRecording(folder).cameraRows;
verifyEqual(testCase, seconds(rows.Timestamp(2) - rows.Timestamp(1)), ...
    0.2, 'AbsTol', 1e-9);
end

function testRecordingStartPreservesAcquisitionDate(testCase)
folder = createSyntheticRecording();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
filename = fullfile(folder, 'recording.h5');
h5writeatt(filename, '/metadata', 'start_time', ...
    '2026-07-28 12:00:00.000');
rows = PostProcessor.readRecording(folder).cameraRows;
verifyEqual(testCase, dateshift(rows.Timestamp(1), 'start', 'day'), ...
    datetime(2026, 7, 28));
end

function testExistingTiffOutputIsRejected(testCase)
folder = createSyntheticRecording();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
output = fullfile(folder, 'processed_frames');
mkdir(output);
imwrite(uint8(0), fullfile(output, 'processed_frame_0001.tiff'));

verifyError(testCase, @() PostProcessor.processData(folder, struct( ...
    'samplingPeriod', 0, 'phaseScope', 'complete-test', ...
    'outputFolder', output)), 'PostProcessor:OutputNotEmpty');
end

function testNoCameraRecordingIsReportedAsSkipped(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
model = Model();
model.selectedFolder = folder;
model.openFilesRec();
model.isRecording = true;
sampleTime = datetime('now');
model.saveAxisSamples('X', sampleTime, 1, 2, 3);
model.saveAxisSamples('Y', sampleTime, 4, 5, 6);
model.isRecording = false;
model.finalizeRecording('completed', 'Completed');
output = fullfile(folder, 'processed_frames');
lastwarn('');
result = PostProcessor.processData(folder, struct( ...
    'samplingPeriod', 0, 'phaseScope', 'complete-test', ...
    'outputFolder', output));
[~, warningId] = lastwarn;
verifyEqual(testCase, warningId, 'PostProcessor:NoCameraFrames');
verifyEqual(testCase, result.status, 'skipped');
verifyEqual(testCase, result.exportedFrameCount, 0);
verifyFalse(testCase, isfolder(output));
clear cleanup;
end

function testEarlyPhaseFramesAreSkippedInsteadOfUsingFirstPlcSample(testCase)
folder = createTimelineRecording( ...
    0:100:700, repmat(10, 1, 8), 500:10:700, 500:10:700);
cleanup = onCleanup(@() removeTemporaryFolder(folder));
output = fullfile(folder, 'processed_frames');

lastwarn('');
result = PostProcessor.processData(folder, struct( ...
    'samplingPeriod', 0, 'phaseScope', 'complete-test', ...
    'outputFolder', output));
[~, warningId] = lastwarn;

verifyEqual(testCase, warningId, ...
    'PostProcessor:SkippedOutOfRangeFrames');
verifyEqual(testCase, result.exportedFrameCount, 3);
files = dir(fullfile(output, 'processed_frame_*.tiff'));
verifyNumElements(testCase, files, 3);
description = readLegacyDescription(fullfile( ...
    output, 'processed_frame_0001.tiff'));
verifySubstring(testCase, description, 'Index:00006');
verifySubstring(testCase, description, 'TenzoX:1500.00 [N]');
clear cleanup;
end

function testLatePhaseFramesAreSkipped(testCase)
folder = createTimelineRecording( ...
    500:100:900, repmat(20, 1, 5), 500:10:700, 500:10:700);
cleanup = onCleanup(@() removeTemporaryFolder(folder));
output = fullfile(folder, 'processed_frames');

lastwarn('');
result = PostProcessor.processData(folder, struct( ...
    'samplingPeriod', 0, 'phaseScope', 'main-test', ...
    'outputFolder', output));
[~, warningId] = lastwarn;

verifyEqual(testCase, warningId, ...
    'PostProcessor:SkippedOutOfRangeFrames');
verifyEqual(testCase, result.exportedFrameCount, 3);
verifySubstring(testCase, result.message, '0 early, 2 late');
clear cleanup;
end

function testCompletelyNonOverlappingRecordingIsSkipped(testCase)
folder = createTimelineRecording( ...
    0:100:300, repmat(10, 1, 4), 500:10:700, 500:10:700);
cleanup = onCleanup(@() removeTemporaryFolder(folder));
output = fullfile(folder, 'processed_frames');

lastwarn('');
result = PostProcessor.processData(folder, struct( ...
    'samplingPeriod', 0, 'phaseScope', 'complete-test', ...
    'outputFolder', output));
[~, warningId] = lastwarn;

verifyEqual(testCase, warningId, ...
    'PostProcessor:SkippedOutOfRangeFrames');
verifyEqual(testCase, result.status, 'skipped');
verifyEqual(testCase, result.exportedFrameCount, 0);
verifyFalse(testCase, isfolder(output));
clear cleanup;
end

function testNearestSampleRejectsTimestampOutsideCoverage(testCase)
base = datetime(2026, 7, 28, 12, 0, 0);
data = table(base + milliseconds([0; 10]), [1; 2], [3; 4], [5; 6], ...
    'VariableNames', {'Timestamp', 'Force', 'UntaredForce', 'Position'});

verifyError(testCase, @() PostProcessor.nearestSample( ...
    data, base - milliseconds(1)), ...
    'PostProcessor:TimestampOutsidePlcCoverage');
verifyError(testCase, @() PostProcessor.nearestSample( ...
    data, base + milliseconds(11)), ...
    'PostProcessor:TimestampOutsidePlcCoverage');
verifyEqual(testCase, PostProcessor.nearestSample( ...
    data, base + milliseconds(9)).Force, 2);
end

function testOverlappingPlcBatchesAreRecoveredChronologically(testCase)
base = datetime(2026, 7, 28, 12, 0, 0);
values = [ ...
    0, 0.01, 0.009, 0.02; ...
    10, 20, 30, 40; ...
    11, 21, 31, 41; ...
    12, 22, 32, 42];

verifyWarning(testCase, ...
    @() PostProcessor.sampleTable(values, base, 'X', 0.01), ...
    'PostProcessor:RecoveredTimestampOrder');
data = PostProcessor.sampleTable(values, base, 'X', 0.01);

verifyGreaterThanOrEqual(testCase, seconds(diff(data.Timestamp)), 0);
verifyEqual(testCase, seconds(data.Timestamp - base)', ...
    [0, 0.01, 0.02, 0.03], 'AbsTol', 1e-12);
verifyEqual(testCase, data.Force', [10, 20, 30, 40]);
end

function folder = createSyntheticRecording()
folder = makeTemporaryFolder();
model = Model();
model.selectedFolder = folder;
model.cameraFrameWidth = 64;
model.cameraFrameHeight = 64;
model.openFilesRec();
model.isRecording = true;
baseTime = datetime('now');
sampleOffsets = 0:10:300;
model.saveAxisSamples('X', ...
    baseTime + milliseconds(sampleOffsets), ...
    repmat(10, size(sampleOffsets)), ...
    repmat(11, size(sampleOffsets)), ...
    repmat(1.25, size(sampleOffsets)));
model.saveAxisSamples('Y', ...
    baseTime + milliseconds(sampleOffsets), ...
    repmat(20, size(sampleOffsets)), ...
    repmat(21, size(sampleOffsets)), ...
    repmat(2.5, size(sampleOffsets)));
statuses = [10, 11, 20, 21, 30, 10];
for index = 1:6
    frame = reshape(uint8(mod((1:4096) + index - 1, 256)), 64, 64);
    model.currentSystemStatus = int16(statuses(index));
    model.saveCameraFrame(frame, ...
        baseTime + milliseconds((index - 1) * 50));
end
model.isRecording = false;
model.finalizeRecording('completed', 'Completed');
end

function folder = createTimelineRecording(cameraOffsets, statuses, xOffsets, yOffsets)
folder = makeTemporaryFolder();
model = Model();
model.selectedFolder = folder;
model.cameraFrameWidth = 64;
model.cameraFrameHeight = 64;
model.openFilesRec();
model.isRecording = true;
baseTime = datetime('now');

model.saveAxisSamples('X', baseTime + milliseconds(xOffsets), ...
    1000 + xOffsets, 2000 + xOffsets, 3000 + xOffsets);
model.saveAxisSamples('Y', baseTime + milliseconds(yOffsets), ...
    4000 + yOffsets, 5000 + yOffsets, 6000 + yOffsets);
for index = 1:numel(cameraOffsets)
    frame = repmat(uint8(index), 64, 64);
    model.currentSystemStatus = int16(statuses(index));
    model.saveCameraFrame(frame, ...
        baseTime + milliseconds(cameraOffsets(index)));
end
model.isRecording = false;
model.finalizeRecording('completed', 'Completed');
end

function description = readLegacyDescription(filename)
fid = fopen(filename, 'rb');
assert(fid ~= -1);
cleanup = onCleanup(@() fclose(fid));
fseek(fid, 256, 'bof');
bytes = fread(fid, 768, '*uint8');
terminator = find(bytes == 0, 1);
assert(~isempty(terminator));
description = char(bytes(1:terminator - 1).');
end

function folder = makeTemporaryFolder()
folder = tempname;
mkdir(folder);
end

function removeTemporaryFolder(folder)
if isfolder(folder)
    rmdir(folder, 's');
end
end
