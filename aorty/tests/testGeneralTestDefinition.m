function tests = testGeneralTestDefinition
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'model'));
testCase.TestData.example = fullfile(root, 'examples', ...
    'general_test_example.json');
end

function testValidMixedModeDefinition(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
verifyEqual(testCase, definition.schemaVersion, 1);
verifyEqual(testCase, lower(definition.cyclic.loadMode), 'force');
verifyEqual(testCase, lower(definition.cyclic.unloadMode), 'displacement');
verifyNotEmpty(testCase, GeneralTestDefinition.summary(definition));
end

function testMalformedSchemaAndCounts(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.schemaVersion = 2;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:SchemaVersion');

definition.schemaVersion = 1;
definition.cyclic.loadValues.x = zeros(1, 101);
definition.cyclic.unloadValues.x = zeros(1, 101);
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidCycles');
end

function testNaNRateAndInvalidCamera(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.preTest.rate.x = NaN;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidNumber');

definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.camera.period = 0;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidCamera');
end
