% Add the MVC folders so classes can be found regardless of the current
% MATLAB working directory.
projectRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(projectRoot, 'model'));
addpath(fullfile(projectRoot, 'controller'));
addpath(fullfile(projectRoot, 'view'));

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
