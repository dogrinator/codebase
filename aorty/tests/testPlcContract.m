function tests = testPlcContract
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.repo = fileparts(fileparts(fileparts( ...
    mfilename('fullpath'))));
end

function testDutAndMatlabSymbolsMatch(testCase)
repo = testCase.TestData.repo;
commandDut = fileread(fullfile(repo, 'MAINplc', 'DUTs', ...
    'ST_MoveCommand.TcDUT'));
statusDut = fileread(fullfile(repo, 'MAINplc', 'DUTs', ...
    'ST_SystemStatus.TcDUT'));
plcSource = fileread(fullfile(repo, 'aorty', 'model', 'Plc.m'));
requiredCommand = {'bRestorePosition', 'fRestoreVelocity', ...
    'bIncludePreTest', 'bPreTestOnly', 'nPreCycleCount', ...
    'bPreloadEnabled', 'fPreloadValue', 'fPreLoadValue', ...
    'fPreUnloadValue', 'bPreUnloadToStart', 'fPreTestRate', ...
    'fPreTestHoldTime', 'fTestRate', 'fForceHoldTime', ...
    'fForceDropPercent', 'fForceDropThreshold', ...
    'nCycleCount', 'nLoadMode', 'fLoadValues', 'nUnloadMode', ...
    'fUnloadValues', 'nStop1Mode', 'fStop1Value', 'nStop2Mode', ...
    'fStop2Value', 'nPostTestMode'};
for index = 1:numel(requiredCommand)
    verifyNotEmpty(testCase, strfind(commandDut, requiredCommand{index}));
    verifyNotEmpty(testCase, strfind(plcSource, requiredCommand{index}));
end
verifyNotEmpty(testCase, strfind(statusDut, 'nInterfaceVersion'));
verifyNotEmpty(testCase, strfind(statusDut, 'bSavedPositionValid'));
verifyEmpty(testCase, strfind(commandDut, 'nPreTestMode'));
verifyEmpty(testCase, strfind(commandDut, 'fPreTestValue'));
verifyEmpty(testCase, strfind(plcSource, 'fMaxPosition'));
end

function testArrayBoundsAreOneHundred(testCase)
repo = testCase.TestData.repo;
commandDut = fileread(fullfile(repo, 'MAINplc', 'DUTs', ...
    'ST_MoveCommand.TcDUT'));
arrays = {'fDistances', 'fVelocities', 'fLoadValues', 'fUnloadValues'};
for index = 1:numel(arrays)
    expression = [arrays{index}, ...
        '\s*:\s*ARRAY\s*\[1\.\.100\]\s*OF\s*LREAL'];
    verifyNotEmpty(testCase, regexp(commandDut, expression, 'once'));
end
end

function testCriticalDutTypesAndDefensiveErrors(testCase)
repo = testCase.TestData.repo;
commandDut = fileread(fullfile(repo, 'MAINplc', 'DUTs', ...
    'ST_MoveCommand.TcDUT'));
statusDut = fileread(fullfile(repo, 'MAINplc', 'DUTs', ...
    'ST_SystemStatus.TcDUT'));
movement = fileread(fullfile(repo, 'MAINplc', 'POUs', ...
    'fb_MovementControler.TcPOU'));
expected = {
    'bRestorePosition\s*:\s*BOOL'
    'fRestoreVelocity\s*:\s*LREAL'
    'nPreCycleCount\s*:\s*INT'
    'fPreTestHoldTime\s*:\s*LREAL'
    'fForceDropPercent\s*:\s*LREAL'
    'fForceDropThreshold\s*:\s*LREAL'
    'nCycleCount\s*:\s*INT'
    'nPostTestMode\s*:\s*INT'};
for index = 1:numel(expected)
    verifyNotEmpty(testCase, regexp(commandDut, expected{index}, 'once'));
end
verifyNotEmpty(testCase, regexp(statusDut, ...
    'nInterfaceVersion\s*:\s*UDINT\s*:=\s*3', 'once'));
verifyNotEmpty(testCase, regexp(statusDut, ...
    'bSavedPositionValid\s*:\s*BOOL', 'once'));
verifyNotEmpty(testCase, strfind(movement, 'nErrorCode := 2007'));
verifyNotEmpty(testCase, strfind(movement, 'nErrorCode := 2004'));
verifyNotEmpty(testCase, strfind(movement, 'nErrorCode := 2102'));
end
