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

function testPublishedPositionUsesDisplayCoordinateOnly(testCase)
plcRoot = testCase.TestData.plcRoot;
buffer = fileread(fullfile(plcRoot, 'POUs', ...
    'fb_StatusBuffer.TcPOU'));
publisher = fileread(fullfile(plcRoot, 'POUs', ...
    'fb_AxisStatusPublisher.TcPOU'));
movement = fileread(fullfile(plcRoot, 'POUs', ...
    'fb_MovementController.TcPOU'));

verifyNotEmpty(testCase, strfind(buffer, ...
    'fPosBuffer[nNextHead] := 50.0 - fActPosition'));
verifyNotEmpty(testCase, strfind(publisher, ...
    'fActPosition := 50.0 - fActPosition'));
verifyEmpty(testCase, strfind(movement, '50.0 - fActPosition'));
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
verifyNotEmpty(testCase, strfind(movement, ...
    'FORCE_REG_MIN_SPEED_FRACTION : LREAL := 0.01'));
verifyNotEmpty(testCase, strfind(movement, ...
    sprintf(['fForceRegMaxVelocity *\n', ...
    '\t\t\tFORCE_REG_MIN_SPEED_FRACTION'])));
end

function testPersistentAxisReferenceRestoreContract(testCase)
plcRoot = testCase.TestData.plcRoot;
persistentGvl = fileread(fullfile(plcRoot, 'GVLs', ...
    'GVL_Persistent.TcGVL'));
project = fileread(fullfile(plcRoot, 'main program.plcproj'));
main = fileread(fullfile(plcRoot, 'POUs', 'MAIN.TcPOU'));
safety = fileread(fullfile(plcRoot, 'POUs', 'fb_safety.TcPOU'));
safetyState = fileread(fullfile(plcRoot, 'DUTs', ...
    'E_SafetyState.TcDUT'));

verifyNotEmpty(testCase, regexp(persistentGvl, ...
    'VAR_GLOBAL\s+PERSISTENT', 'once'));
for symbol = {'fLastPositionX', 'fLastPositionY', ...
        'bLastPositionValidX', 'bLastPositionValidY'}
    verifyNotEmpty(testCase, strfind(persistentGvl, symbol{1}));
    verifyNotEmpty(testCase, strfind(main, ...
        ['GVL_Persistent.', symbol{1}]));
end
verifyNotEmpty(testCase, strfind(project, ...
    'GVLs\GVL_Persistent.TcGVL'));
verifyNotEmpty(testCase, strfind(project, 'Tc2_Utilities'));
verifyNotEmpty(testCase, strfind(safetyState, 'RestoreReference'));
verifyNotEmpty(testCase, strfind(safetyState, 'VerifyReference'));
verifyNotEmpty(testCase, strfind(safety, 'MC_Direct'));
verifyNotEmpty(testCase, strfind(safety, ...
    'REFERENCE_RESTORE_TOLERANCE'));
verifyNotEmpty(testCase, strfind(main, ...
    'NOT fbSafetyX.bHomed OR stSystemStatusX.bTarWorking'));
verifyNotEmpty(testCase, strfind(main, ...
    'NOT fbSafetyY.bHomed OR stSystemStatusY.bTarWorking'));
verifyNotEmpty(testCase, strfind(main, 'FB_WritePersistentData'));
verifyNotEmpty(testCase, strfind(main, ...
    'TwinCAT_SystemInfoVarList._AppInfo.AdsPort'));
verifyNotEmpty(testCase, strfind(main, 'SPDM_VAR_BOOST'));
verifyNotEmpty(testCase, strfind(main, 'ftPowerRequestX.Q'));
verifyNotEmpty(testCase, strfind(main, 'ftPowerRequestY.Q'));
verifyNotEmpty(testCase, strfind(main, ...
    'bPersistentPositionSaveError'));
verifyNotEmpty(testCase, strfind(main, ...
    'nPersistentPositionCheckpointCounter'));
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
