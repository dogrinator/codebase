function tests = testPlcAds
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'model'));
addpath(fullfile(root, 'tests'));
testCase.TestData.root = root;
end

function testInterfaceVersionAcceptedAndRejected(testCase)
[plc, ~] = connectedPlc();
verifyTrue(testCase, plc.connected);

client = FakeAdsClient();
client.InterfaceVersion = uint32(99);
other = Plc(Model());
verifyError(testCase, @() other.connectClientForTesting(client), ...
    'PLC:InterfaceVersion');
end

function testAllFieldsPreparedBeforeDualExecuteAndArraysPadded(testCase)
[plc, client] = connectedPlc();
client.clearWrites();
commands = struct('X', command([1, 2], [0, 0]), ...
    'Y', command([3, 4], [0.5, 0.5]));
axes = plc.sendTestSequence(commands);
verifyEqual(testCase, axes, {'X', 'Y'});

symbols = cellfun(@(entry) entry.symbol, client.Writes, ...
    'UniformOutput', false);
verifyEqual(testCase, symbols(end - 1:end), ...
    {'MAIN.stMoveCommandX.bExecute', ...
    'MAIN.stMoveCommandY.bExecute'});
firstExecute = find(endsWith(symbols, '.bExecute'), 1);
verifyFalse(testCase, any(endsWith(symbols(1:firstExecute - 1), ...
    '.bExecute')));

xLoad = client.getSymbol('MAIN.stMoveCommandX.fLoadValues');
verifySize(testCase, xLoad, [1, 100]);
verifyEqual(testCase, xLoad(1:2), [1, 2]);
verifyEqual(testCase, xLoad(3:end), zeros(1, 98));
end

function testServicePulsesAndSettingsWrites(testCase)
[plc, client] = connectedPlc();
client.clearWrites();
plc.savePosition({'X', 'Y'});
plc.restorePosition({'X'}, struct('X', 2, 'Y', 2));
cfg = struct('fTenzoCons', 1, 'fTenzoOffset', 0, ...
    'fKp', 0.1, 'fKi', 0.01, 'fIntegralLimit', 1, ...
    'fForceTolerance', 0.1, 'fMaxVelocity', 2, 'fMaxForce', 20, ...
    'fForceReliefDistance', 1, 'fForceReliefVelocity', 1);
plc.writeAxisConfig(cfg, 'X');
symbols = cellfun(@(entry) entry.symbol, client.Writes, ...
    'UniformOutput', false);
verifyTrue(testCase, any(endsWith(symbols, 'bSavePosition')));
verifyTrue(testCase, any(endsWith(symbols, 'bRestorePosition')));
verifyTrue(testCase, any(endsWith(symbols, 'fRestoreVelocity')));
verifyTrue(testCase, any(endsWith(symbols, 'fForceReliefDistance')));
verifyTrue(testCase, any(endsWith(symbols, 'fForceReliefVelocity')));
end

function testCommandValidationBoundaries(testCase)
[plc, ~] = connectedPlc();
bad = command(zeros(1, 101), zeros(1, 101));
bad.cycleCount = 101;
verifyError(testCase, ...
    @() plc.sendTestSequence(struct('X', bad, 'Y', [])), ...
    'PLC:InvalidTestCommand');

bad = command(1, 0);
bad.testRate = NaN;
verifyError(testCase, ...
    @() plc.sendTestSequence(struct('X', bad, 'Y', [])), ...
    'PLC:InvalidTestCommand');

bad = command(1, 0);
bad.forceHoldTime = -1;
verifyError(testCase, ...
    @() plc.sendTestSequence(struct('X', bad, 'Y', [])), ...
    'PLC:InvalidTestCommand');

bad = command(1, 0);
bad.forceDropPercent = 100;
verifyError(testCase, ...
    @() plc.sendTestSequence(struct('X', bad, 'Y', [])), ...
    'PLC:InvalidTestCommand');
end

function testExpectedStaleHandleErrorIsSilentDuringDisconnect(testCase)
[plc, client] = connectedPlc();
client.DeleteErrorMessage = ...
    'Ads-Error 0x710 : Symbol could not be found.';
verifyWarningFree(testCase, @() plc.disconnectPLC());
verifyFalse(testCase, plc.connected);
verifyFalse(testCase, plc.disconnecting);
end

function testSavedPostRequiresSavedCoordinate(testCase)
client = FakeAdsClient();
client.SavedPositionValid = false;
plc = Plc(Model());
plc.connectClientForTesting(client);
value = command(1, 0);
value.postTestMode = 1;
verifyError(testCase, ...
    @() plc.sendTestSequence(struct('X', value, 'Y', [])), ...
    'PLC:NoSavedPosition');
end

function testPreloadOnlyAllowsZeroPreCycles(testCase)
[plc, ~] = connectedPlc();
value = command([], []);
value.preTestOnly = true;
value.preCycleCount = 0;
value.cycleCount = 0;
plc.sendTestSequence(struct('X', value, 'Y', []));
end

function testOperationCompletionAndPeerHalt(testCase)
[plc, client] = connectedPlc();
controller = Control(Model(), plc);
controller.activeTestAxes = {'X', 'Y'};
controller.operationStartCounters = ...
    struct('X', uint32(10), 'Y', uint32(20));
controller.testRunning = true;
statuses = struct( ...
    'X', operationStatus(false, false, 11, 0), ...
    'Y', operationStatus(false, false, 21, 0));
controller.processTestStatusForTesting(statuses);
verifyFalse(testCase, controller.testRunning);

client.clearWrites();
controller.activeTestAxes = {'X', 'Y'};
controller.operationStartCounters = ...
    struct('X', uint32(11), 'Y', uint32(21));
controller.testRunning = true;
statuses.X = operationStatus(false, true, 11, 2007);
statuses.Y = operationStatus(true, false, 21, 0);
controller.processTestStatusForTesting(statuses);
verifyFalse(testCase, controller.testRunning);
symbols = cellfun(@(entry) entry.symbol, client.Writes, ...
    'UniformOutput', false);
verifyTrue(testCase, any(strcmp(symbols, ...
    'MAIN.stMoveCommandY.bHalt')));
end

function [plc, client] = connectedPlc()
client = FakeAdsClient();
plc = Plc(Model());
plc.connectClientForTesting(client);
end

function value = command(loadValues, unloadValues)
value = struct( ...
    'includePreTest', true, 'preTestOnly', false, ...
    'preCycleCount', 1, 'preloadEnabled', true, ...
    'preloadValue', 0.5, 'preLoadValue', 2, ...
    'preUnloadValue', 0, 'preUnloadToStart', false, ...
    'preTestRate', 1, 'preTestHoldTime', 0, ...
    'testRate', 1, 'forceHoldTime', 0, ...
    'forceDropPercent', 10, 'forceDropThreshold', 1, ...
    'cycleCount', numel(loadValues), 'loadMode', 2, ...
    'loadValues', loadValues, 'unloadMode', 1, ...
    'unloadValues', unloadValues, 'stop1Mode', 1, ...
    'stop1Value', 0, 'stop2Mode', 0, 'stop2Value', 0, ...
    'postTestMode', 0);
end

function value = operationStatus(working, errorState, counter, errorCode)
value = struct('working', logical(working), 'error', logical(errorState), ...
    'operationCounter', uint32(counter), 'errorCode', uint32(errorCode), ...
    'axisErrorID', uint32(0));
end
