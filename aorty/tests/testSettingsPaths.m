function tests = testSettingsPaths
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(root));
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

function testOptionalCameraGainAndSafeConfigNames(testCase)
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
model = Model();
settings = Settings(Plc(model), Camera(model));
settings.hwPath = folder;
config = jsondecode(fileread(fullfile( ...
    testCase.TestData.root, '.config', 'hwConfig', 'default.json')));
config.camera = rmfield(config.camera, 'gainRaw');
writeJson(fullfile(folder, 'without_gain.json'), config);
settings.loadHwConfig('without_gain');
verifyFalse(testCase, isfield(settings.hwConfig.camera, 'gainRaw'));

settings.saveHwConfig('saved safely');
verifyTrue(testCase, isfile(fullfile(folder, 'saved safely.json')));
verifyEqual(testCase, jsondecode(fileread(fullfile( ...
    folder, 'saved safely.json'))), settings.hwConfig);
verifyError(testCase, @() settings.saveHwConfig('../escape'), ...
    'Settings:InvalidName');
verifyError(testCase, @() settings.loadHwConfig('folder/name'), ...
    'Settings:InvalidName');
clear cleanup;
end

function writeJson(filename, value)
fid = fopen(filename, 'w');
assert(fid ~= -1);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(value));
end
