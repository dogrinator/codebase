% Add the complete application tree so extracted support components are
% available regardless of the current MATLAB working directory.
projectRoot = fileparts(mfilename('fullpath'));
addpath(genpath(projectRoot));

% Keep one application instance per MATLAB session. Force-closing the old
% figure would bypass View.shutdown and leave its timers and hardware alive.
applicationKey = 'AortyApplicationView';
existingView = [];
if isappdata(groot, applicationKey)
    existingView = getappdata(groot, applicationKey);
end

if ~isempty(existingView) && isvalid(existingView) && ...
        ~isempty(existingView.fig) && isvalid(existingView.fig)
    figure(existingView.fig);
else
    if isappdata(groot, applicationKey)
        rmappdata(groot, applicationKey);
    end
    model = Model();
    controler = Control(model);
    view = View(controler);
    setappdata(groot, applicationKey, view);
    controler.startTimers(view);
end
