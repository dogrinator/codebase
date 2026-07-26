function tests = testSettingsPaths
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'model'));
testCase.TestData.originalFolder = pwd;
testCase.TestData.root = root;
end

function teardownOnce(testCase)
cd(testCase.TestData.originalFolder);
end

function testPathsDoNotDependOnCurrentFolder(testCase)
cd(tempdir);
model = Model();
settings = Settings(Plc(model), Camera(model));
verifyEqual(testCase, settings.appPath, ...
    fullfile(testCase.TestData.root, '.config', 'appConfig'));
verifyEqual(testCase, settings.hwPath, ...
    fullfile(testCase.TestData.root, '.config', 'hwConfig'));
verifyTrue(testCase, any(strcmp(settings.listAppConfigs(), 'default')));
settings.loadHwConfig('default');
for axis = {'xAxis', 'yAxis'}
    value = settings.hwConfig.plc.(axis{1});
    verifyEqual(testCase, value.fForceReliefDistance, 1.0);
    verifyEqual(testCase, value.fForceReliefVelocity, 1.0);
    verifyFalse(testCase, isfield(value, 'fMaxPosition'));
end
end
