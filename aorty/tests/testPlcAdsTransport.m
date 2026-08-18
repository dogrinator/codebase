function tests = testPlcAdsTransport
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(root));
addpath(fullfile(root, 'tests'));
end

function testReleaseDeletesEveryOwnedHandle(testCase)
client = FakeAdsClient();
ads = PlcAds(client);
ads.initialize(true);
created = client.CreateCount;
ads.releaseHandles();
verifyEqual(testCase, numel(client.DeletedHandles), created);
verifyEqual(testCase, numel(unique(client.DeletedHandles)), created);
end

function testPartialInitializationCleansCreatedHandles(testCase)
client = FakeAdsClient();
client.FailCreateAt = 7;
ads = PlcAds(client);
verifyError(testCase, @() ads.initialize(true), ...
    'FakeAds:CreateHandle');
verifyEqual(testCase, numel(client.DeletedHandles), 6);
verifyEqual(testCase, numel(unique(client.DeletedHandles)), 6);
end

function testPersistentCheckpointDiagnostics(testCase)
client = FakeAdsClient();
ads = PlcAds(client);
ads.initialize(true);
client.setSymbol('MAIN.bPersistentPositionSaved', true);
client.setSymbol('MAIN.bPersistentPositionSaveBusy', false);
client.setSymbol('MAIN.bPersistentPositionSaveError', true);
client.setSymbol('MAIN.nPersistentPositionSaveErrorID', uint32(16));
client.setSymbol('MAIN.nPersistentPositionCheckpointCounter', uint32(7));

state = ads.readPersistentPositionCheckpoint();
verifyTrue(testCase, state.saved);
verifyFalse(testCase, state.busy);
verifyTrue(testCase, state.error);
verifyEqual(testCase, state.errorID, uint32(16));
verifyEqual(testCase, state.counter, uint32(7));
end

function testPowerOffWaitsForFreshPersistentCheckpoint(testCase)
client = FakeAdsClient();
client.AutoCheckpointOnPowerOff = true;
client.setStatus('X', struct('homed', true));
plc = Plc(RecordingSession());
plc.connectClientForTesting(client);
cleanup = onCleanup(@() plc.disconnectPLC());

plc.setPower({'X'}, false);
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.nPersistentPositionCheckpointCounter'), uint32(1));
clear cleanup;
end

function testFailedFacadeInitializationStaysDisconnected(testCase)
client = FakeAdsClient();
client.FailCreateAt = 5;
plc = Plc(RecordingSession());
verifyError(testCase, @() plc.connectClientForTesting(client), ...
    'FakeAds:CreateHandle');
verifyFalse(testCase, plc.connected);
verifyFalse(testCase, plc.disconnecting);
verifyEqual(testCase, numel(client.DeletedHandles), 4);
end

function testStreamingResetClearsCountersAndDrops(testCase)
client = FakeAdsClient();
ads = PlcAds(client);
ads.initialize(true);
client.setStatus('X', struct('sampleCounter', uint32(0)));
ads.readAxisSnapshot('X');
client.setStatus('X', struct('sampleCounter', uint32(60), ...
    'bufferHead', int16(10)));
ads.readAxisSnapshot('X');
verifyEqual(testCase, ads.droppedSamples.X, 10);

ads.resetStreamingState();
verifyEqual(testCase, ads.droppedSamples, struct('X', 0, 'Y', 0));
verifyEqual(testCase, ads.restartCounts, struct('X', 0, 'Y', 0));
client.setStatus('X', struct('sampleCounter', uint32(65)));
[forceData, positionData] = ads.readAxisSnapshot('X');
verifyEmpty(testCase, forceData);
verifyEmpty(testCase, positionData);
end

function testCounterResetIsReportedAsRestart(testCase)
client = FakeAdsClient();
ads = PlcAds(client);
ads.initialize(true);
client.setStatus('X', struct('sampleCounter', uint32(100)));
ads.readAxisSnapshot('X');
client.setStatus('X', struct('sampleCounter', uint32(0)));
[forceData, positionData] = ads.readAxisSnapshot('X');
verifyEmpty(testCase, forceData);
verifyEmpty(testCase, positionData);
verifyEqual(testCase, ads.restartCounts.X, 1);
end
