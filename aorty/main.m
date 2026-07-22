% Add the MVC folders so classes can be found regardless of the current
% MATLAB working directory.
projectRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(projectRoot, 'model'));
addpath(fullfile(projectRoot, 'controller'));
addpath(fullfile(projectRoot, 'view'));

clc
clf
clear vars
close all force;

%% Load backend
tic
model = Model();
controler = Control(model);
toc

%% Load frontend
tic
view = View(controler);
toc

% Start timers
controler.startTimers(view);

