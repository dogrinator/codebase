function tests = testPlcAds
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(root));
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
verifyFalse(testCase, other.connected);
end

function testCompleteStatusPacketIsDecoded(testCase)
[plc, client] = connectedPlc();
positionBuffer = 0.25 + (1:50);
forceBuffer = -50:-1;
client.setStatus('X', struct( ...
    'positionBuffer', positionBuffer, ...
    'forceBuffer', forceBuffer, ...
    'bufferHead', int16(17), ...
    'sampleCounter', uint32(123456), ...
    'operationCounter', uint32(987), ...
    'tareOffset', -2.5, ...
    'position', 42.75, ...
    'working', true, ...
    'tareWorking', true, ...
    'error', true, ...
    'errorCode', uint32(2101), ...
    'axisErrorID', uint32(hex2dec('89ABCDEF')), ...
    'homing', true, ...
    'homed', true, ...
    'stopped', false, ...
    'systemStatus', int16(21)));

statuses = plc.pollStatus();
status = statuses.X;
verifyEqual(testCase, status.positionBuffer, positionBuffer);
verifyEqual(testCase, status.forceBuffer, forceBuffer);
verifyEqual(testCase, status.bufferHead, int16(17));
verifyEqual(testCase, status.sampleCounter, uint32(123456));
verifyEqual(testCase, status.operationCounter, uint32(987));
verifyEqual(testCase, status.interfaceVersion, uint32(6));
verifyEqual(testCase, status.tareOffset, -2.5);
verifyEqual(testCase, status.position, 42.75);
verifyTrue(testCase, status.working);
verifyTrue(testCase, status.tareWorking);
verifyTrue(testCase, status.error);
verifyEqual(testCase, status.errorCode, uint32(2101));
verifyEqual(testCase, status.axisErrorID, uint32(hex2dec('89ABCDEF')));
verifyTrue(testCase, status.powered);
verifyTrue(testCase, status.homing);
verifyTrue(testCase, status.homed);
verifyFalse(testCase, status.stopped);
verifyTrue(testCase, status.savedPositionValid);
verifyEqual(testCase, status.systemStatus, int16(21));
end

function testPollStatusReadsOnePacketPerAxis(testCase)
[plc, client] = connectedPlc();
client.resetStatusReadCounts();
plc.pollStatus();
verifyEqual(testCase, client.StatusReadCounts, struct('X', 1, 'Y', 1));
end

function testMalformedStatusPacketIsRejected(testCase)
client = FakeAdsClient();
client.StatusPacketLength = 855;
plc = Plc(Model());
verifyError(testCase, @() plc.connectClientForTesting(client), ...
    'PLC:InvalidStatusPacket');
end

function testInvalidStatusHeadAndSystemStatusAreRejected(testCase)
[plc, client] = connectedPlc();
client.setStatus('X', struct('bufferHead', int16(0)));
verifyError(testCase, @() plc.pollStatus(), 'PLC:InvalidStatusPacket');

client.setStatus('X', struct('bufferHead', int16(50), ...
    'systemStatus', int16(99)));
verifyError(testCase, @() plc.pollStatus(), 'PLC:InvalidStatusPacket');
end

function testEveryVersionSixSystemStatusIsAccepted(testCase)
[plc, client] = connectedPlc();
valid = int16([0, 1, 2, 3, 4, 5, 6, 10, 11, 20, 21, 30]);
for value = valid
    client.setStatus('X', struct('systemStatus', value));
    statuses = plc.pollStatus();
    verifyEqual(testCase, statuses.X.systemStatus, value);
end
end

function testFifoUsesSinglePacketAndCircularCounters(testCase)
[plc, client] = connectedPlc();
positions = 1:50;
forces = 101:150;
client.setStatus('X', struct('positionBuffer', positions, ...
    'forceBuffer', forces, 'bufferHead', int16(10), ...
    'sampleCounter', uint32(10), 'tareOffset', 1.5));
client.setStatus('Y', struct('sampleCounter', uint32(10)));
plc.fifoProcess();

client.setStatus('X', struct('bufferHead', int16(13), ...
    'sampleCounter', uint32(13)));
client.setStatus('Y', struct('bufferHead', int16(13), ...
    'sampleCounter', uint32(13)));
client.resetStatusReadCounts();
[forceX, ~, untaredX, ~, posX] = plc.fifoProcess();
verifyEqual(testCase, forceX, forces(11:13));
verifyEqual(testCase, untaredX, forces(11:13) - 1.5);
verifyEqual(testCase, posX, positions(11:13));
verifyEqual(testCase, client.StatusReadCounts, struct('X', 1, 'Y', 1));
end

function testFifoTracksDroppedSamples(testCase)
[plc, client] = connectedPlc();
client.setStatus('X', struct('sampleCounter', uint32(0)));
client.setStatus('Y', struct('sampleCounter', uint32(0)));
plc.fifoProcess();
client.setStatus('X', struct('sampleCounter', uint32(60), ...
    'bufferHead', int16(10), 'positionBuffer', 1:50, ...
    'forceBuffer', 101:150));
client.setStatus('Y', struct('sampleCounter', uint32(60), ...
    'bufferHead', int16(10)));
[forceX, ~, ~, ~, posX] = plc.fifoProcess();
verifyNumElements(testCase, forceX, 50);
verifyNumElements(testCase, posX, 50);
verifyEqual(testCase, plc.droppedSamples.X, 10);
verifyEqual(testCase, forceX, [111:150, 101:110]);
verifyEqual(testCase, posX, [11:50, 1:10]);
end

function testFifoCounterWraparound(testCase)
[plc, client] = connectedPlc();
client.setStatus('X', struct( ...
    'sampleCounter', uint32(4294967294), ...
    'bufferHead', int16(50)));
client.setStatus('Y', struct( ...
    'sampleCounter', uint32(4294967294), ...
    'bufferHead', int16(50)));
plc.fifoProcess();
client.setStatus('X', struct( ...
    'sampleCounter', uint32(1), ...
    'bufferHead', int16(3), ...
    'positionBuffer', 1:50, ...
    'forceBuffer', 101:150));
client.setStatus('Y', struct( ...
    'sampleCounter', uint32(1), ...
    'bufferHead', int16(3)));
[forceX, ~, ~, ~, posX] = plc.fifoProcess();
verifyEqual(testCase, forceX, 101:103);
verifyEqual(testCase, posX, 1:3);
verifyEqual(testCase, plc.droppedSamples.X, 0);
end

function testFifoPreservesPerAxisPacketsSplitByPlcScan(testCase)
[plc, client] = connectedPlc();
client.setStatus('X', struct('sampleCounter', uint32(0)));
client.setStatus('Y', struct('sampleCounter', uint32(0)));
plc.fifoProcess();

client.setStatus('X', struct( ...
    'sampleCounter', uint32(50), ...
    'bufferHead', int16(50), ...
    'positionBuffer', 1:50, ...
    'forceBuffer', 101:150));
client.setStatus('Y', struct( ...
    'sampleCounter', uint32(49), ...
    'bufferHead', int16(49), ...
    'positionBuffer', 51:100, ...
    'forceBuffer', 201:250));

[forceX, forceY, ~, ~, positionX, positionY] = plc.fifoProcess();
verifyEqual(testCase, forceX, 101:150);
verifyEqual(testCase, forceY, 201:249);
verifyEqual(testCase, positionX, 1:50);
verifyEqual(testCase, positionY, 51:99);
verifyEqual(testCase, numel(forceX), 50);
verifyEqual(testCase, numel(forceY), 49);
end

function testModeOneAndTwoUseCurrentScalarFields(testCase)
[plc, client] = connectedPlc();
client.clearWrites();
verifyTrue(testCase, plc.SendCommands(1, -5, 2, [], []));
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.stMoveCommandX.fMoveDistance'), -5);
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.stMoveCommandX.fMoveVelocity'), 2);

client.clearWrites();
verifyTrue(testCase, plc.SendCommands(2, [], [], 12.5, 3));
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.stMoveCommandY.fTargetForce'), 12.5);
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.stMoveCommandY.fForceDuration'), 3);
symbols = writtenSymbols(client);
verifyFalse(testCase, any(contains(symbols, 'fDistances')));
verifyFalse(testCase, any(contains(symbols, 'fVelocities')));
verifyFalse(testCase, any(contains(symbols, 'nTotalSteps')));
end

function testAllFieldsPreparedBeforeSharedBiaxialStartAndArraysPadded(testCase)
[plc, client] = connectedPlc();
client.clearWrites();
commands = struct('X', command([1, 2], [0, 0]), ...
    'Y', command([3, 4], [0.5, 0.5]));
commands.X.preTestForceTolerance = 0.11;
commands.X.preloadHoldTime = 0.12;
commands.X.preCycleHoldTime = 0.13;
commands.X.singleForceTolerance = 0.14;
commands.X.singleForceHoldTime = 0.15;
commands.X.cyclicForceTolerance = 0.16;
commands.X.cyclicForceHoldTime = 0.17;
axes = plc.sendTestSequence(commands);
verifyEqual(testCase, axes, {'X', 'Y'});

symbols = writtenSymbols(client);
verifyEqual(testCase, symbols{end}, 'MAIN.bStartBiaxialTest');
verifyFalse(testCase, any(endsWith(symbols, '.bExecute')));

xLoad = client.getSymbol('MAIN.stMoveCommandX.fLoadValues');
verifySize(testCase, xLoad, [1, 50]);
verifyEqual(testCase, xLoad(1:2), [1, 2]);
verifyEqual(testCase, xLoad(3:end), zeros(1, 48));
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.stMoveCommandX.fPreCycleLoadValue'), 2);
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.stMoveCommandX.fPreTestForceTolerance'), 0.11);
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.stMoveCommandX.fPreloadHoldTime'), 0.12);
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.stMoveCommandX.fPreCycleHoldTime'), 0.13);
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.stMoveCommandX.fSingleForceTolerance'), 0.14);
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.stMoveCommandX.fSingleForceHoldTime'), 0.15);
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.stMoveCommandX.fCyclicForceTolerance'), 0.16);
verifyEqual(testCase, client.getSymbol( ...
    'MAIN.stMoveCommandX.fCyclicForceHoldTime'), 0.17);
end

function testSingleAxisTestRetainsIndividualExecute(testCase)
[plc, client] = connectedPlc();
client.clearWrites();
plc.sendTestSequence(struct('X', command([1, 2], [0, 0]), 'Y', []));
symbols = writtenSymbols(client);
verifyEqual(testCase, symbols{end}, 'MAIN.stMoveCommandX.bExecute');
verifyFalse(testCase, any(strcmp(symbols, 'MAIN.bStartBiaxialTest')));
end

function testIncompatibleBiaxialCommandsAreRejectedBeforeWrites(testCase)
[plc, client] = connectedPlc();
commandX = command([1, 2], [0, 0]);
commandY = command(3, 0);
client.clearWrites();
verifyError(testCase, @() plc.sendTestSequence( ...
    struct('X', commandX, 'Y', commandY)), ...
    'PLC:InvalidBiaxialCommand');
verifyEmpty(testCase, client.Writes);
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
symbols = writtenSymbols(client);
verifyTrue(testCase, any(endsWith(symbols, 'bSavePosition')));
verifyTrue(testCase, any(endsWith(symbols, 'bRestorePosition')));
verifyTrue(testCase, any(endsWith(symbols, 'fRestoreVelocity')));
verifyTrue(testCase, any(endsWith(symbols, 'fForceReliefDistance')));
verifyTrue(testCase, any(endsWith(symbols, 'fForceReliefVelocity')));
end

function testBothAxisServicesValidateBeforeWriting(testCase)
[plc, client] = connectedPlc();
client.setStatus('Y', struct('working', true));
client.clearWrites();

verifyError(testCase, @() plc.tare({'X', 'Y'}), ...
    'PLC:AxisUnavailable');
verifyEmpty(testCase, client.Writes);

client.clearWrites();
verifyError(testCase, @() plc.moveToLowerLimit({'X', 'Y'}), ...
    'PLC:AxisUnavailable');
verifyEmpty(testCase, client.Writes);
end

function testBothAxisSettingsValidateBeforeWriting(testCase)
[plc, client] = connectedPlc();
model = Model();
camera = Camera(model);
settings = Settings(plc, camera);
valid = struct('fTenzoCons', 1, 'fTenzoOffset', 0, ...
    'fKp', 0.1, 'fKi', 0.01, 'fIntegralLimit', 1, ...
    'fForceTolerance', 0.1, 'fMaxVelocity', 2, 'fMaxForce', 20, ...
    'fForceReliefDistance', 1, 'fForceReliefVelocity', 1);
invalid = valid;
invalid.fMaxForce = 0;
settings.hwConfig = struct('plc', struct( ...
    'xAxis', valid, 'yAxis', invalid));
client.clearWrites();

verifyError(testCase, @() settings.applyPlcConfig(), ...
    'PLC:InvalidConfiguration');
verifyEmpty(testCase, client.Writes);
end

function testSelectedHardwareProfileWritesBothAxes(testCase)
[plc, client] = connectedPlc();
settings = Settings(plc, Camera(plc.model));
settings.loadHwConfig('default');
client.clearWrites();

settings.applyPlcConfig();

symbols = writtenSymbols(client);
verifyTrue(testCase, any(contains(symbols, ...
    'MAIN.stSettingsX.fMaxForce')));
verifyTrue(testCase, any(contains(symbols, ...
    'MAIN.stSettingsY.fMaxForce')));
end

function testCommandValidationBoundaries(testCase)
[plc, client] = connectedPlc();
bad = command(zeros(1, 51), zeros(1, 51));
bad.cycleCount = 51;
client.clearWrites();
verifyError(testCase, ...
    @() plc.sendTestSequence(struct('X', bad, 'Y', [])), ...
    'PLC:InvalidTestCommand');
verifyEmpty(testCase, client.Writes);

bad = command(1, 0);
bad.testRate = NaN;
verifyError(testCase, ...
    @() plc.sendTestSequence(struct('X', bad, 'Y', [])), ...
    'PLC:InvalidTestCommand');

bad = command(1, 0);
bad.singleForceHoldTime = -1;
verifyError(testCase, ...
    @() plc.sendTestSequence(struct('X', bad, 'Y', [])), ...
    'PLC:InvalidTestCommand');
end

function testDeprecatedCommandFieldsAreRejected(testCase)
[plc, client] = connectedPlc();
deprecated = {'preLoadValue', 'forceDropPercent', 'forceDropThreshold', ...
    'preTestHoldTime', 'forceHoldTime'};
for index = 1:numel(deprecated)
    bad = command(1, 0);
    bad.(deprecated{index}) = 1;
    client.clearWrites();
    verifyError(testCase, ...
        @() plc.sendTestSequence(struct('X', bad, 'Y', [])), ...
        'PLC:DeprecatedCommandField');
    verifyEmpty(testCase, client.Writes);
end
end

function testExpectedStaleHandleErrorIsSilentDuringDisconnect(testCase)
[plc, client] = connectedPlc();
client.DeleteErrorMessage = ...
    'Ads-Error 0x710 : Symbol could not be found.';
verifyWarningFree(testCase, @() plc.disconnectPLC());
verifyFalse(testCase, plc.connected);
verifyFalse(testCase, plc.disconnecting);
end

function testDisconnectPowersOffBothAxes(testCase)
[plc, client] = connectedPlc();
client.clearWrites();

plc.disconnectPLC();

symbols = writtenSymbols(client);
powerWrites = endsWith(symbols, '.bPower');
verifyEqual(testCase, symbols(powerWrites), { ...
    'MAIN.stMoveCommandX.bPower', ...
    'MAIN.stMoveCommandY.bPower'});
verifyEqual(testCase, cellfun( ...
    @(entry) logical(entry.value), client.Writes(powerWrites)), ...
    [false, false]);
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
verifyWarningFree(testCase, ...
    @() plc.sendTestSequence(struct('X', value, 'Y', [])));
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
symbols = writtenSymbols(client);
verifyTrue(testCase, any(strcmp(symbols, ...
    'MAIN.stMoveCommandY.bHalt')));
end

function testObsoleteErrorCodesAreUnknown(testCase)
verifySubstring(testCase, PlcErrorCatalog.describe('X', 2004, 0), ...
    'Unknown PLC error 2004');
verifySubstring(testCase, PlcErrorCatalog.describe('Y', 2202, 0), ...
    'Unknown PLC error 2202');
end

function testPersistentReferenceErrorsAreDecoded(testCase)
verifySubstring(testCase, PlcErrorCatalog.describe('X', 1016, 0), ...
    'reference restore timed out');
verifySubstring(testCase, PlcErrorCatalog.describe('Y', 1017, 0), ...
    'reference is invalid');
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
    'preloadValue', 0.5, 'preCycleLoadValue', 2, ...
    'preUnloadValue', 0, 'preUnloadToStart', false, ...
    'preTestRate', 1, 'preTestForceTolerance', 0.1, ...
    'preloadHoldTime', 0, 'preCycleHoldTime', 0, ...
    'testRate', 1, 'singleForceTolerance', 0.1, ...
    'singleForceHoldTime', 0, 'cyclicForceTolerance', 0.1, ...
    'cyclicForceHoldTime', 0, ...
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

function symbols = writtenSymbols(client)
symbols = cellfun(@(entry) entry.symbol, client.Writes, ...
    'UniformOutput', false);
end
