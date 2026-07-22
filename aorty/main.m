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

