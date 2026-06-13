clc
clf
clear vars
close all force;

tic
model = Model();
controler = Control(model);
toc

tic
view = View(controler);
toc
controler.startTimers(view);
