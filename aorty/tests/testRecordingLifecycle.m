function tests = testRecordingLifecycle
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(root));
addpath(fullfile(root, 'tests'));
testCase.TestData.root = root;
end

function testModelWritesSystemStatusRecordingContract(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));

model = Model();
model.selectedFolder = folder;
model.cameraFrameWidth = 2;
model.cameraFrameHeight = 2;
model.isRecording = true;
model.openFilesRec();
model.currentSystemStatus = int16(21);
model.saveCameraFrame(uint8([1, 2; 3, 4]), ...
    datetime(2026, 7, 30, 12, 0, 0));
sampleTime = datetime('now');
model.saveAxisSamples('X', sampleTime + milliseconds([0, 10]), ...
    [1, 2], [3, 4], [5, 6]);
model.saveAxisSamples('Y', sampleTime, 7, 8, 9);
model.isRecording = false;
model.finalizeRecording('completed', 'Completed');

recording = PostProcessor.readRecording(folder);
rows = recording.cameraRows;
verifyEqual(testCase, rows.SystemStatus, 21);
verifyEqual(testCase, dir(fullfile(folder, 'cam.bin')).bytes, 4);
verifyEqual(testCase, height(recording.dataX), 2);
verifyEqual(testCase, height(recording.dataY), 1);
verifyEqual(testCase, recording.dataX.Force, [1; 2]);
files = dir(folder);
files = files(~[files.isdir]);
verifyEqual(testCase, sort({files.name}), ...
    sort({'cam.bin', 'recording.h5'}));
clear cleanup;
end

function testExistingRecordingIsNotOverwritten(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
filename = fullfile(folder, 'recording.h5');
fid = fopen(filename, 'w');
assert(fid ~= -1);
fprintf(fid, 'existing data');
fclose(fid);

model = Model();
model.selectedFolder = folder;
model.isRecording = true;
verifyError(testCase, @() model.openFilesRec(), ...
    'Model:RecordingFilesExist');
verifyEqual(testCase, fileread(filename), 'existing data');
verifyFalse(testCase, model.filesOpen);
clear cleanup;
end

function testAxisFieldsMustMatchButAxesMayDiffer(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
model = Model();
model.selectedFolder = folder;
model.openFilesRec();
model.isRecording = true;
verifyError(testCase, @() model.saveAxisSamples( ...
    'X', datetime('now') + milliseconds([0, 10]), ...
    [1, 2], 3, [4, 5]), ...
    'Model:RecordingVectorLength');
sampleTime = datetime('now');
model.saveAxisSamples('X', sampleTime + milliseconds([0, 10]), ...
    [1, 2], [3, 4], [5, 6]);
model.saveAxisSamples('Y', sampleTime, 7, 8, 9);
model.isRecording = false;
model.finalizeRecording('aborted', 'Test complete');
verifySize(testCase, h5read(fullfile( ...
    folder, 'recording.h5'), '/plc/X/samples'), [4, 2]);
verifySize(testCase, h5read(fullfile( ...
    folder, 'recording.h5'), '/plc/Y/samples'), [4, 1]);
clear cleanup;
end

function testRuntimeSettingsAndCommandsAreRecorded(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
[controler, client, command] = connectedController(testCase.TestData.root);
client.setSymbol('MAIN.stSettingsX.fTenzoCons', 0.123);
client.setSymbol('MAIN.stSettingsY.fMaxForce', 45);
controler.recordingFolderSelector = @() folder;
controler.startTestForTesting( ...
    struct('X', command, 'Y', []), postSettings(), true, 'pre');
controler.safeAbort('Header test');

filename = fullfile(folder, 'recording.h5');
verifyEqual(testCase, h5readatt( ...
    filename, '/settings/plc/X', 'fTenzoCons'), 0.123);
verifyEqual(testCase, h5readatt( ...
    filename, '/settings/plc/Y', 'fMaxForce'), 45);
verifyEqual(testCase, char(h5readatt( ...
    filename, '/settings/test', 'test_kind')), 'pre');
verifyEqual(testCase, h5readatt( ...
    filename, '/settings/test/X', 'preTestOnly'), uint8(1));
verifyEqual(testCase, h5readatt( ...
    filename, '/camera', 'connected'), uint8(0));
clear cleanup;
end

function testUncheckedPreTestSkipsFolderAndFilesOnCompletion(testCase)
oldFolder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(oldFolder));
sentinel = fullfile(oldFolder, 'previous.txt');
fid = fopen(sentinel, 'w');
assert(fid ~= -1);
fprintf(fid, 'previous recording');
fclose(fid);

[controler, ~, command] = connectedController(testCase.TestData.root);
controler.model.selectedFolder = oldFolder;
controler.recordingFolderSelector = @failFolderPrompt;
controler.startTestForTesting( ...
    struct('X', command, 'Y', []), postSettings(), false);
verifyTrue(testCase, controler.testRunning);
verifyFalse(testCase, controler.model.isRecording);
verifyFalse(testCase, controler.model.filesOpen);

status = completionStatus();
controler.processTestStatusForTesting(struct('X', status));
verifyFalse(testCase, controler.testRunning);
verifyEqual(testCase, fileread(sentinel), 'previous recording');
clear cleanup;
end

function testUncheckedPreTestAbortAndStartupFailureStayFileless(testCase)
[controler, ~, command] = connectedController(testCase.TestData.root);
controler.recordingFolderSelector = @failFolderPrompt;
controler.startTestForTesting( ...
    struct('X', command, 'Y', []), postSettings(), false);
controler.safeAbort('Operator abort');
verifyFalse(testCase, controler.testRunning);
verifyFalse(testCase, controler.model.filesOpen);
verifyEqual(testCase, controler.model.currentSystemStatus, int16(0));

[controler, client, command] = connectedController(testCase.TestData.root);
bad = command;
bad.singleForceHoldTime = -1;
client.clearWrites();
verifyError(testCase, @() controler.startTestForTesting( ...
    struct('X', bad, 'Y', []), postSettings(), false), ...
    'PLC:InvalidTestCommand');
verifyFalse(testCase, controler.testRunning);
verifyFalse(testCase, controler.model.filesOpen);
verifyEqual(testCase, controler.model.currentSystemStatus, int16(0));
end

function testCheckedPreTestPromptsAndCompletesRecording(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
[controler, ~, command] = connectedController(testCase.TestData.root);
controler.recordingFolderSelector = @() folder;
controler.startTestForTesting( ...
    struct('X', command, 'Y', []), postSettings(), true);
verifyTrue(testCase, controler.model.isRecording);
verifyTrue(testCase, controler.model.filesOpen);
verifyTrue(testCase, isfile(fullfile(folder, 'recording.h5')));
verifyTrue(testCase, isfile(fullfile(folder, 'cam.bin')));

status = completionStatus();
controler.processTestStatusForTesting(struct('X', status));
verifyFalse(testCase, controler.testRunning);
verifyFalse(testCase, controler.model.isRecording);
verifyFalse(testCase, controler.model.filesOpen);
recordingStatus = strtrim(char(h5readatt( ...
    fullfile(folder, 'recording.h5'), '/metadata', 'status')));
verifyEqual(testCase, recordingStatus, 'completed');
clear cleanup;
end

function testAcquisitionTimestampsArePreserved(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
model = Model();
model.selectedFolder = folder;
model.openFilesRec();
model.isRecording = true;
base = datetime('now');
model.saveAxisSamples('X', base + milliseconds([0, 125]), ...
    [1, 2], [3, 4], [5, 6]);
model.isRecording = false;
model.finalizeRecording('completed', 'Completed');
values = h5read(fullfile(folder, 'recording.h5'), ...
    '/plc/X/samples');
verifyEqual(testCase, diff(values(1, :)), 0.125, ...
    'AbsTol', 1e-6);
clear cleanup;
end

function testRecordingMetadataReportsIntegrityLoss(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
model = Model();
model.selectedFolder = folder;
model.openFilesRec();
model.recordingDroppedSamples = struct('X', 3, 'Y', 1);
model.recordingRestartDetected = true;
model.finalizeRecording('aborted', 'Integrity failure');
filename = fullfile(folder, 'recording.h5');
verifyEqual(testCase, h5readatt(filename, '/metadata', ...
    'x_dropped_sample_count'), uint64(3));
verifyEqual(testCase, h5readatt(filename, '/metadata', ...
    'y_dropped_sample_count'), uint64(1));
verifyEqual(testCase, h5readatt(filename, '/metadata', ...
    'sample_loss_detected'), uint8(1));
verifyEqual(testCase, h5readatt(filename, '/metadata', ...
    'plc_restart_detected'), uint8(1));
verifyEqual(testCase, h5readatt(filename, '/metadata', ...
    'status_resolution_seconds'), 0.25);
verifyEqual(testCase, char(h5readatt(filename, '/metadata', ...
    'application_version')), AppInfo.VERSION);
clear cleanup;
end

function testStaleSamplesAreClearedBeforeOperation(testCase)
[controler, ~, command] = connectedController(testCase.TestData.root);
base = datetime('now');
controler.samples.append(1, 2, 3, 4, 5, 6, base, base);
controler.recordingFolderSelector = @failFolderPrompt;
controler.startTestForTesting( ...
    struct('X', command, 'Y', []), postSettings(), false);
verifyEmpty(testCase, controler.samples.forceX);
verifyEmpty(testCase, controler.samples.timestampY);
controler.safeAbort('Test cleanup');
end

function testUnexpectedOperationCounterAborts(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
[controler, client, command] = ...
    connectedController(testCase.TestData.root);
client.setStatus('X', struct('operationCounter', uint32(5)));
controler.recordingFolderSelector = @() folder;
controler.startTestForTesting( ...
    struct('X', command, 'Y', []), postSettings(), true);
status = completionStatus();
status.operationCounter = uint32(0);
controler.processTestStatusForTesting(struct('X', status));
verifyFalse(testCase, controler.testRunning);
verifyEqual(testCase, strtrim(char(h5readatt( ...
    fullfile(folder, 'recording.h5'), '/metadata', 'status'))), ...
    'aborted');
verifySubstring(testCase, strtrim(char(h5readatt( ...
    fullfile(folder, 'recording.h5'), '/metadata', 'reason'))), ...
    'changed unexpectedly');
clear cleanup;
end

function testOperationCounterWrapCompletes(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
[controler, client, command] = ...
    connectedController(testCase.TestData.root);
client.setStatus('X', struct( ...
    'operationCounter', intmax('uint32')));
controler.recordingFolderSelector = @() folder;
controler.startTestForTesting( ...
    struct('X', command, 'Y', []), postSettings(), true);
status = completionStatus();
status.operationCounter = uint32(0);
controler.processTestStatusForTesting(struct('X', status));
verifyEqual(testCase, strtrim(char(h5readatt( ...
    fullfile(folder, 'recording.h5'), '/metadata', 'status'))), ...
    'completed');
clear cleanup;
end

function testDroppedSamplesAbortActiveRecording(testCase)
folder = makeTemporaryFolder();
cleanup = onCleanup(@() removeTemporaryFolder(folder));
[controler, client, command] = ...
    connectedController(testCase.TestData.root);
controler.recordingFolderSelector = @() folder;
controler.startTestForTesting( ...
    struct('X', command, 'Y', []), postSettings(), true);
client.setStatus('X', struct('sampleCounter', uint32(0)));
client.setStatus('Y', struct('sampleCounter', uint32(0)));
controler.readCallback();
client.setStatus('X', struct( ...
    'sampleCounter', uint32(60), 'bufferHead', int16(10)));
client.setStatus('Y', struct( ...
    'sampleCounter', uint32(60), 'bufferHead', int16(10)));
controler.readCallback();
verifyFalse(testCase, controler.testRunning);
filename = fullfile(folder, 'recording.h5');
verifyEqual(testCase, strtrim(char(h5readatt( ...
    filename, '/metadata', 'status'))), 'aborted');
verifyEqual(testCase, h5readatt(filename, '/metadata', ...
    'x_dropped_sample_count'), uint64(10));
verifyEqual(testCase, h5readatt(filename, '/metadata', ...
    'sample_loss_detected'), uint8(1));
clear cleanup;
end

function [controler, client, command] = connectedController(~)
client = FakeAdsClient();
plc = Plc(Model());
plc.connectClientForTesting(client);
model = plc.model;
controler = Control(model, plc);
settings = Settings(plc, Camera(model));
settings.loadAppConfig('default');
commands = TestCommandBuilder.fromPreset(settings.appConfig, 'pre');
command = commands.X;
end

function status = completionStatus()
status = struct('working', false, 'error', false, ...
    'operationCounter', uint32(1), 'errorCode', uint32(0), ...
    'axisErrorID', uint32(0));
end

function value = postSettings()
value = struct('enabled', false, ...
    'samplingPeriod', 0, 'includePrePost', true);
end

function folder = failFolderPrompt()
folder = 0; %#ok<NASGU>
error('Test:UnexpectedFolderPrompt', ...
    'A folder selector was called for a non-recorded pre-test.');
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
