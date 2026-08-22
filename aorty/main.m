function view = main(action)
% MAIN Start, focus, or safely restart the Aorty application.
%
%   main()          - Focuses the existing application or creates a new one.
%   main("restart") - Safely closes the existing application and creates
%                     a completely fresh instance. (usefull for dev)


% If no input use "start"
arguments
    action (1,1) string {mustBeMember(action, ["start", "restart"])} = "start"
end

% Add production code only. Tests provide their own path setup so fake
% hardware classes can never shadow application classes in normal use.
projectRoot = fileparts(mfilename("fullpath"));
productionFolders = {"controller", "model", "validation", "view"};
for folder = productionFolders
    addpath(genpath(fullfile(projectRoot, folder)));
end

% App key that is checked in reopening
applicationKey = "AortyApplicationView";
existingView = [];

% Check if app is running
if isappdata(groot, applicationKey)
    existingView = getappdata(groot, applicationKey);
end

applicationIsRunning = ...
    ~isempty(existingView) && ...
    isvalid(existingView) && ...
    ~isempty(existingView.fig) && ...
    isvalid(existingView.fig);

% Reconect to existing view
if applicationIsRunning
    if action == "start"
        figure(existingView.fig);
        view = existingView;
        return;
    end

    % Controlled restart: timers and hardware are shut down first.
    existingView.shutdown();
end

% Remove any stale registration left by an invalid instance.
if isappdata(groot, applicationKey)
    rmappdata(groot, applicationKey);
end

% Construct a completely fresh application.
model = Model();
controller = Control(model);
view = View(controller);

setappdata(groot, applicationKey, view);
controller.startTimers(view);

figure(view.fig);
end
