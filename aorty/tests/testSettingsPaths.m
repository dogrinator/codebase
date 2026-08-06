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
verifyEqual(testCase, settings.activeHwConfigName, 'default');
for axis = {'xAxis', 'yAxis'}
    value = settings.hwConfig.plc.(axis{1});
    verifyEqual(testCase, value.fForceReliefDistance, 1.0);
    verifyEqual(testCase, value.fForceReliefVelocity, 1.0);
    verifyFalse(testCase, isfield(value, 'fMaxPosition'));
end
end

function testLegacyApplicationPresetMigration(testCase)
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@() rmdir(folder, 's'));
model = Model();
settings = Settings(Plc(model), Camera(model));
settings.loadHwConfig('default');
settings.appPath = folder;

current = jsondecode(fileread(fullfile( ...
    testCase.TestData.root, '.config', 'appConfig', 'default.json')));
legacy = rmfield(current, 'schemaVersion');
legacyTolerance = current.pre.forceTolerance;
for axis = {'x', 'y'}
    field = axis{1};
    maxForce = settings.hwConfig.plc.([field, 'Axis']).fMaxForce;
    legacyTolerance.(field) = ...
        current.pre.forceTolerance.(field) * maxForce / 100;
    legacy.single.forceTolerance.(field) = ...
        current.single.forceTolerance.(field) * maxForce / 100;
    legacy.cyclic.forceTolerance.(field) = ...
        current.cyclic.forceTolerance.(field) * maxForce / 100;
end
legacy.pre.cyclicForceTolerance = legacyTolerance;
legacy.pre.preload.forceTolerance = legacyTolerance;
legacy.pre = rmfield(legacy.pre, 'forceTolerance');
writeJson(fullfile(folder, 'legacy.json'), legacy);

settings.loadAppConfig('legacy');
verifyEqual(testCase, settings.appConfig.schemaVersion, 2);
verifyEqual(testCase, settings.appConfig.pre.forceTolerance, ...
    current.pre.forceTolerance, 'AbsTol', 1e-12);
verifyFalse(testCase, ...
    isfield(settings.appConfig.pre, 'cyclicForceTolerance'));
verifyFalse(testCase, ...
    isfield(settings.appConfig.pre.preload, 'forceTolerance'));
settings.saveAppConfig('migrated');
saved = jsondecode(fileread(fullfile(folder, 'migrated.json')));
verifyEqual(testCase, saved.schemaVersion, 2);

legacy.pre.preload.forceTolerance.x = ...
    legacy.pre.preload.forceTolerance.x + 0.01;
writeJson(fullfile(folder, 'mismatch.json'), legacy);
verifyError(testCase, @() settings.loadAppConfig('mismatch'), ...
    'TestPreset:LegacyToleranceMismatch');
clear cleanup;
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

function testSelectedCameraProfileIsApplied(testCase)
model = Model();
camera = Camera(model);
camera.cameraSrc = FakeCameraSource();
settings = Settings(Plc(model), camera);
settings.loadHwConfig('default');
settings.applyCameraConfig();

verifyEqual(testCase, camera.cameraSrc.ExposureTimeAbs, ...
    settings.hwConfig.camera.exposureTimeAbs);
verifyEqual(testCase, camera.cameraSrc.GainRaw, ...
    settings.hwConfig.camera.gainRaw);
verifyEqual(testCase, camera.cameraSrc.AcquisitionFrameRateAbs, ...
    settings.hwConfig.camera.acquisitionFrameRateAbs);
verifyEqual(testCase, camera.cameraSrc.AcquisitionFrameRateEnable, 'True');
end

function writeJson(filename, value)
fid = fopen(filename, 'w');
assert(fid ~= -1);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(value));
end
