function tests = testCameraLifecycle
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(root));
end

function testStopFailureStillDeletesAndClearsState(testCase)
[camera, hardware, probe] = connectedFakeCamera();
hardware.FailStop = true;
warningState = warning('off', 'Camera:StopFailed');
cleanup = onCleanup(@() warning(warningState));

camera.closeCam();

verifyTrue(testCase, probe.StopAttempted);
verifyTrue(testCase, probe.DeleteAttempted);
verifyEmpty(testCase, camera.cameraHW);
verifyEmpty(testCase, camera.cameraSrc);
verifyFalse(testCase, camera.connected);
clear cleanup;
end

function testDeleteFailureStillClearsState(testCase)
[camera, hardware, probe] = connectedFakeCamera();
hardware.FailDelete = true;
warningState = warning('off', 'Camera:DeleteFailed');
cleanup = onCleanup(@() warning(warningState));

camera.closeCam();

verifyTrue(testCase, probe.StopAttempted);
verifyTrue(testCase, probe.DeleteAttempted);
verifyEmpty(testCase, camera.cameraHW);
verifyEmpty(testCase, camera.cameraSrc);
verifyFalse(testCase, camera.connected);
clear cleanup;
end

function [camera, hardware, probe] = connectedFakeCamera()
camera = Camera(Model());
probe = FakeCameraCleanupProbe();
hardware = FakeCameraHardware();
hardware.Probe = probe;
camera.cameraHW = hardware;
camera.cameraSrc = FakeCameraSource();
camera.latestFrame = ones(2);
camera.connected = true;
end
