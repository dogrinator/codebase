function tests = testPlcContract
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.repo = fileparts(fileparts(fileparts( ...
    mfilename('fullpath'))));
testCase.TestData.plcRoot = fullfile(testCase.TestData.repo, ...
    'TwinCat', 'AortyPLC', 'main program');
end

function testDutAndMatlabSymbolsMatch(testCase)
repo = testCase.TestData.repo;
plcRoot = testCase.TestData.plcRoot;
commandDut = fileread(fullfile(plcRoot, 'DUTs', ...
    'ST_MoveCommand.TcDUT'));
statusDut = fileread(fullfile(plcRoot, 'DUTs', ...
    'ST_SystemStatus.TcDUT'));
plcSource = fileread(fullfile(repo, 'aorty', 'model', 'Plc.m'));
adsSource = fileread(fullfile( ...
    repo, 'aorty', 'model', 'plc', 'PlcAds.m'));
mainSource = fileread(fullfile(plcRoot, 'POUs', 'MAIN.TcPOU'));

requiredCommand = {'fMoveDistance', 'fMoveVelocity', 'fTargetForce', ...
    'fForceDuration', 'bRestorePosition', 'fRestoreVelocity', ...
    'bIncludePreTest', 'bPreTestOnly', 'nPreCycleCount', ...
    'bPreloadEnabled', 'fPreloadValue', 'fPreCycleLoadValue', ...
    'fPreUnloadValue', 'bPreUnloadToStart', 'fPreTestRate', ...
    'fPreTestForceTolerance', 'fPreloadHoldTime', ...
    'fPreCycleHoldTime', 'fTestRate', 'fSingleForceTolerance', ...
    'fSingleForceHoldTime', 'fCyclicForceTolerance', ...
    'fCyclicForceHoldTime', ...
    'nCycleCount', 'nLoadMode', 'fLoadValues', 'nUnloadMode', ...
    'fUnloadValues', 'nStop1Mode', 'fStop1Value', 'nStop2Mode', ...
    'fStop2Value', 'nPostTestMode'};
for index = 1:numel(requiredCommand)
    verifyNotEmpty(testCase, strfind(commandDut, requiredCommand{index}));
    verifyNotEmpty(testCase, strfind(adsSource, requiredCommand{index}));
end

verifyEmpty(testCase, strfind(plcSource, 'MAIN.st'));
verifyEmpty(testCase, strfind(plcSource, 'ReadAny'));
verifyEmpty(testCase, strfind(plcSource, 'WriteAny'));
verifyNotEmpty(testCase, strfind(plcSource, 'PlcAds'));
verifyNotEmpty(testCase, strfind(mainSource, 'bStartBiaxialTest'));
verifyNotEmpty(testCase, strfind(adsSource, 'MAIN.bStartBiaxialTest'));
verifyNotEmpty(testCase, strfind(plcSource, 'pulseBiaxialStart'));

requiredStatus = {'nInterfaceVersion', 'bSavedPositionValid', ...
    'nSystemStatus', 'nSampleCounter', 'nOperationCounter'};
for index = 1:numel(requiredStatus)
    verifyNotEmpty(testCase, strfind(statusDut, requiredStatus{index}));
end

removed = {'fDistances', 'fVelocities', 'nTotalSteps', 'fPreLoadValue', ...
    'fForceDropPercent', 'fForceDropThreshold'};
for index = 1:numel(removed)
    verifyEmpty(testCase, strfind(commandDut, removed{index}));
end
end

function testArrayBoundsAreFifty(testCase)
plcRoot = testCase.TestData.plcRoot;
commandDut = fileread(fullfile(plcRoot, 'DUTs', ...
    'ST_MoveCommand.TcDUT'));
statusDut = fileread(fullfile(plcRoot, 'DUTs', ...
    'ST_SystemStatus.TcDUT'));
for name = {'fLoadValues', 'fUnloadValues'}
    expression = [name{1}, ...
        '\s*:\s*ARRAY\s*\[1\.\.50\]\s*OF\s*LREAL'];
    verifyNotEmpty(testCase, regexp(commandDut, expression, 'once'));
end
for name = {'fPosBuffer', 'fTenzoBuffer'}
    expression = [name{1}, ...
        '\s*:\s*ARRAY\s*\[1\.\.50\]\s*OF\s*LREAL'];
    verifyNotEmpty(testCase, regexp(statusDut, expression, 'once'));
end
end

function testCriticalTypesVersionAndErrors(testCase)
plcRoot = testCase.TestData.plcRoot;
commandDut = fileread(fullfile(plcRoot, 'DUTs', ...
    'ST_MoveCommand.TcDUT'));
statusDut = fileread(fullfile(plcRoot, 'DUTs', ...
    'ST_SystemStatus.TcDUT'));
movement = fileread(fullfile(plcRoot, 'POUs', ...
    'fb_MovementController.TcPOU'));
expected = {
    'fMoveDistance\s*:\s*LREAL'
    'fTargetForce\s*:\s*LREAL'
    'bRestorePosition\s*:\s*BOOL'
    'fRestoreVelocity\s*:\s*LREAL'
    'nPreCycleCount\s*:\s*INT'
    'fPreCycleLoadValue\s*:\s*LREAL'
    'fPreTestForceTolerance\s*:\s*LREAL'
    'fPreloadHoldTime\s*:\s*LREAL'
    'fPreCycleHoldTime\s*:\s*LREAL'
    'fSingleForceTolerance\s*:\s*LREAL'
    'fSingleForceHoldTime\s*:\s*LREAL'
    'fCyclicForceTolerance\s*:\s*LREAL'
    'fCyclicForceHoldTime\s*:\s*LREAL'
    'nCycleCount\s*:\s*INT'
    'nPostTestMode\s*:\s*INT'};
for index = 1:numel(expected)
    verifyNotEmpty(testCase, regexp(commandDut, expected{index}, 'once'));
end
verifyNotEmpty(testCase, regexp(statusDut, ...
    'nInterfaceVersion\s*:\s*UDINT\s*:=\s*6', 'once'));
verifyNotEmpty(testCase, regexp(statusDut, ...
    'nSystemStatus\s*:\s*INT\s*:=\s*0', 'once'));
verifyNotEmpty(testCase, strfind(movement, ...
    'ERROR_INVALID_CONFIGURATION : UDINT := 2007'));
verifyNotEmpty(testCase, strfind(movement, ...
    'ERROR_UNSUPPORTED_ENDPOINT : UDINT := 2003'));
verifyNotEmpty(testCase, strfind(movement, ...
    'ERROR_RELIEF_DIRECTION_UNKNOWN : UDINT := 2102'));
verifyNotEmpty(testCase, strfind(movement, 'SYNC_PRETEST_DONE'));
verifyNotEmpty(testCase, strfind(movement, 'SYNC_LOAD_DONE'));
verifyNotEmpty(testCase, strfind(movement, 'SYNC_UNLOAD_DONE'));
verifyNotEmpty(testCase, strfind(movement, 'SYNC_MAIN_DONE'));
verifyNotEmpty(testCase, strfind(movement, 'SYNC_POSTTEST_DONE'));
verifyNotEmpty(testCase, strfind(movement, ...
    'fEndpointHoldTime := stMoveCommand.fPreloadHoldTime'));
verifyNotEmpty(testCase, strfind(movement, ...
    'fEndpointHoldTime := stMoveCommand.fPreCycleHoldTime'));
verifyNotEmpty(testCase, strfind(movement, ...
    'fEndpointHoldTime := stMoveCommand.fSingleForceHoldTime'));
verifyNotEmpty(testCase, strfind(movement, ...
    'fEndpointHoldTime := stMoveCommand.fCyclicForceHoldTime'));
verifyNotEmpty(testCase, strfind(movement, ...
    'ABS(fEndpointCurrentError) <= fEndpointTolerance'));
verifyNotEmpty(testCase, strfind(movement, ...
    'ABS(fStop2CurrentError) <= stMoveCommand.fSingleForceTolerance'));
end

function testGeneratedTmcStatusLayout(testCase)
tmc = fileread(fullfile(testCase.TestData.plcRoot, ...
    'main program.tmc'));
verifyNotEmpty(testCase, regexp(tmc, ...
    '<Name>ST_SystemStatus</Name><BitSize>6848</BitSize>', 'once'));
offsets = {
    'fPosBuffer', 0
    'fTenzoBuffer', 3200
    'nBufferHead', 6400
    'nInterfaceVersion', 6496
    'nSystemStatus', 6800};
for index = 1:size(offsets, 1)
    expression = ['<Name>', offsets{index, 1}, '</Name>.*?', ...
        '<BitOffs>', num2str(offsets{index, 2}), '</BitOffs>'];
    verifyNotEmpty(testCase, regexp(tmc, expression, 'once'));
end
end

function testGeneratedTmcVerifierAcceptsQualifiedStartSymbol(testCase)
tmc = fullfile(testCase.TestData.plcRoot, 'main program.tmc');
verifyWarningFree(testCase, @() verifyGeneratedTmc(tmc));
end
