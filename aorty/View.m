classdef View < handle
    %VIEW Summary of this class goes here
    %   Detailed explanation goes here TODO

    properties
        % control and model class
        controler Control

        % UI
        fig
        mainGrid
        leftGrid

        % Camera UIS
        cameraPanel
        cameraAxes
        camSwitch
        settingsCamBtn
        camImageHandle

        % PLC UI
        plcPanel
        settingsPlcBtn
        plcSwitch
        modeDrop
        dynamicControlGroup

        % Tenzo
        tenzoPanel
        fxAxes
        fxLine
        fyAxes
        fyLine

        % Main control
        posX
        posY
        velX
        velY

        % Settings tab UI handles
        settingsFig
        configDrop
        camUI       % Struct to hold camera UI fields
        plcXUI      % Struct to hold PLC X UI fields
        plcYUI      % Struct to hold PLC Y UI fields

    end

    methods
        %% Main Init view function
        function app = View(controler)

            % init def of important classes
            app.controler = controler;

            % Init creation of main app
            app.fig = uifigure('Name','Aorty +++ premium', 'Position',[200 200 1000 600]);

            % Create grid
            app.mainGrid = uigridlayout(app.fig,[1 2]);
            app.mainGrid.ColumnWidth = {'1x','1x'};
            app.leftGrid = uigridlayout(app.mainGrid,[2 1]);
            app.leftGrid.RowHeight = {'1x','1x'};

            % create all mandatory UI blocks
            createCameraPanel(app)
            createTenzoPanel(app)
            createPLCpanel(app)

            % when closing app close all ports
            app.fig.CloseRequestFcn = @(src,event)app.shutdown();
        end

        %% Close app
        function shutdown(app)
            % to be shure that it is not ethernal loop
            app.fig.CloseRequestFcn = '';

            try
                % Try to close hardware com
                app.controler.plc.disconnectPLC();
                app.controler.camera.closeCam();
            catch
                % If fail objects dont exist anymore
            end

            % Stop timers if they still exist
            t = timerfindall;
            if ~isempty(t), stop(t); delete(t); end

            % Force fig to close
            delete(app.fig);

            % Finall close app
            delete(app);
        end

        %% Camera
        function createCameraPanel(app)
            % Panel
            app.cameraPanel = uipanel(app.leftGrid);

            grid = uigridlayout(app.cameraPanel,[2 1]);
            grid.RowHeight = {40,'1x'};

            % Top bar

            topGrid = uigridlayout(grid,[1 3]);
            topGrid.ColumnWidth = {'fit','1x','fit'};

            app.settingsCamBtn = uibutton(topGrid,'Text','HW settings', 'ButtonPushedFcn',@(src, event) app.openSettingsWindow());

            app.settingsCamBtn.Layout.Column = 2;

            app.camSwitch = uiswitch(topGrid,'slider');
            app.camSwitch.Items = {'OFF','ON'};
            app.camSwitch.Value = 'OFF';
            app.camSwitch.Layout.Column = 3;

            app.camSwitch.ValueChangedFcn = @(src,event)app.connectCameraCallback(src);

            % Camera preview

            app.cameraAxes = uiaxes(grid);
            % Create a dummy image once and store its handle
            app.camImageHandle = image(app.cameraAxes, zeros(1024, 1024, 'uint8'));
            app.cameraAxes.CLim = [0 255];
            colormap(app.cameraAxes, gray)
            axis(app.cameraAxes, 'off')
            axis(app.cameraAxes, 'image')

            % Hide the entire toolbar
            app.cameraAxes.Toolbar.Visible = 'off';

            % Disable mouse interactions (prevents accidental zooming/panning)
            app.cameraAxes.Interactions = [];

            % Optional: Remove the "ticks" and labels for a cleaner "Monitor" look
            app.cameraAxes.XTick = [];
            app.cameraAxes.YTick = [];
        end

        function connectCameraCallback(app,src)
            app.controler.camera.connectCamera(app,src)
        end

        %% Tenzo
        function app = createTenzoPanel(app)
            % Panel
            app.tenzoPanel = uipanel(app.leftGrid);
            app.tenzoPanel.Title = 'Tenzo';

            grid = uigridlayout(app.tenzoPanel,[1 2]);

            % Plots
            app.fxAxes = uiaxes(grid);
            title(app.fxAxes,'Fx')
            app.fxLine = animatedline(app.fxAxes, 'Color', [0.18 0.55 0.85], 'LineWidth', 1.2);

            app.fyAxes = uiaxes(grid);
            title(app.fyAxes,'Fy')
            app.fyLine = animatedline(app.fyAxes, 'Color', [0.18 0.55 0.85], 'LineWidth', 1.2);

        end

        %% PLC
        function createPLCpanel(app)
            % Main PLC Panel on the right side of the mainGrid
            app.plcPanel = uipanel(app.mainGrid);

            % Main Layout for the PLC Panel
            outerGrid = uigridlayout(app.plcPanel, [2 1]);
            outerGrid.RowHeight = {40, '1x'}; % Top Bar, Dynamic Area

            % --- 1. Top Bar (Tests dropdown & text & Connection) ---
            topGrid = uigridlayout(outerGrid, [1 2]);

            % Test dropdown
            app.modeDrop = uidropdown(topGrid, ...
                'Items', {'Manual Control','Constant Speed', 'Constant Force', 'G-Code Speed', 'G-Code Force'}, ...
                'ValueChangedFcn', @(src,event) app.updateTestUI(src.Value));

            % Connect switch
            app.plcSwitch = uiswitch(topGrid, 'slider', 'Items', {'OFF','ON'});
            app.plcSwitch.ValueChangedFcn = @(src,event) app.controler.plc.connectPLC(app,src);

            % --- 3. THE DYNAMIC AREA ---
            app.dynamicControlGroup = uigridlayout(outerGrid, [1 1]);

            % Initialize with Manual Mode
            app.updateTestUI('Manual Control');
        end

        % ========================================
        % ====== Dynamic Test control area =======
        % ========================================
        function updateTestUI(app, selectedMode)
            % Clear the previous dynamic buttons
            delete(app.dynamicControlGroup.Children);

            switch selectedMode
                case 'Manual Control'
                    % Create grid
                    g = uigridlayout(app.dynamicControlGroup, [8 2]);

                    % X axes control
                    uibutton(g, 'Text', 'Move X +', 'ButtonPushedFcn', @(s,e) app.controler.plc.SendCommands(1,  app.posX.Value, app.velX.Value, 0, 0));
                    uibutton(g, 'Text', 'Move X -', 'ButtonPushedFcn', @(s,e) app.controler.plc.SendCommands(1, -app.posX.Value, app.velX.Value, 0, 0));
                    uilabel(g, 'Text', 'Distance for X axis [mm]:');
                    app.posX = uieditfield(g, 'numeric', 'Value', 100);
                    uilabel(g, 'Text', 'Speed of X axis [m/s]:');
                    app.velX = uieditfield(g, 'numeric', 'Value', 10, 'Limits', [0, 200]);

                    % Y axes control TODO
                    uibutton(g, 'Text', 'Move Y +', 'ButtonPushedFcn', @(s,e) app.controler.plc.SendCommands(1, 0, 0,  app.posY.Value, app.velY.Value));
                    uibutton(g, 'Text', 'Move Y -', 'ButtonPushedFcn', @(s,e) app.controler.plc.SendCommands(1, 0, 0, -app.posY.Value, app.velY.Value));
                    uilabel(g, 'Text', 'Distance for Y axis [mm]:');
                    app.posY = uieditfield(g, 'numeric', 'Value', 100);
                    uilabel(g, 'Text', 'Speed of Y axis [m/s]:');
                    app.velY = uieditfield(g, 'numeric', 'Value', 10, 'Limits',[0, 200]);

                    % XY axes control TODO
                    uibutton(g, 'Text', 'Move XY +', 'ButtonPushedFcn', @(s,e) app.controler.plc.SendCommands(1,  app.posX.Value,app.velX.Value,  app.posY.Value, app.velY.Value));
                    uibutton(g, 'Text', 'Move XY -', 'ButtonPushedFcn', @(s,e) app.controler.plc.SendCommands(1, -app.posX.Value,app.velX.Value, -app.posY.Value, app.velY.Value));

                    % Auto-home TODO
                    uibutton(g, 'Text', 'Auto Home');

                    % Panic stop
                    pwrBtn = uibutton(g, 'state', 'Text', 'Stop', 'BackgroundColor', [1 0.7 0.7]);
                    pwrBtn.ValueChangedFcn = @(s,e) app.controler.panicStop(s);

                case 'Constant Speed'
                    % Create grid for setings
                    g = uigridlayout(app.dynamicControlGroup, [4 2]);

                    % X movement
                    uilabel(g, 'Text', 'Distance for X axis [mm]:');
                    app.posX = uieditfield(g, 'numeric', 'Value', 100);
                    uilabel(g, 'Text', 'Speed of X axis [m/s]:');
                    app.velX = uieditfield(g, 'numeric', 'Value', 10, 'Limits', [0, 200]);

                    % Y movement
                    uilabel(g, 'Text', 'Distance for Y axis [mm]:');
                    app.posY = uieditfield(g, 'numeric', 'Value', 100);
                    uilabel(g, 'Text', 'Speed of Y axis [m/s]:');
                    app.velY = uieditfield(g, 'numeric', 'Value', 100,'Limits',[0, 100]);

                    % Start test
                    uibutton(g, 'Text', 'Start Test', 'ButtonPushedFcn', @(s,e) app.controler.startTest(1, app.posX.Value,app.velX.Value, app.posY.Value, app.velY.Value));

                    % Panic stop
                    pwrBtn = uibutton(g, 'state', 'Text', 'Stop', 'BackgroundColor', [1 0.7 0.7]);
                    pwrBtn.ValueChangedFcn = @(s,e) app.controler.panicStop(s);

                case 'Constant Force'
                    % Create Grid
                    g = uigridlayout(app.dynamicControlGroup, [3 2]);

                    % X regulation
                    uilabel(g, 'Text', 'time for X axis [s]:');
                    app.posX = uieditfield(g, 'numeric', 'Value', 10, 'Limits',[0, inf]);
                    uilabel(g, 'Text', 'Target Force X (N):');
                    app.velX = uieditfield(g, 'numeric', 'Value', 10);

                    % Y regulation
                    uilabel(g, 'Text','time for Y axis [s]:');
                    app.posY = uieditfield(g, 'numeric', 'Value', 10, 'Limits',[0, inf]);
                    uilabel(g, 'Text', 'Target Force Y (N):');
                    app.velY = uieditfield(g, 'numeric', 'Value', 10);

                    % Start Test
                    uibutton(g, 'Text', 'Start Test', 'ButtonPushedFcn', @(s,e) app.controler.plc.startTest(2, app.posX.Value,app.velX.Value, app.posY.Value, app.velY.Value));

                    % Panic stop
                    pwrBtn = uibutton(g, 'state', 'Text', 'STOP', 'BackgroundColor', [1 0.7 0.7]);
                    pwrBtn.ValueChangedFcn = @(s,e) app.controler.panicStop(s);

                case 'G-Code Speed' %TODO
                    g = uigridlayout(app.dynamicControlGroup, [3 1]);
                    uibutton(g, 'Text', 'Load G-Code File');
                    uilistbox(g, 'Items', {'No file loaded...'});



                case 'G-Code Force' %TODO
                    g = uigridlayout(app.dynamicControlGroup, [3 1]);
                    uibutton(g, 'Text', 'Load G-Code File');
                    uilistbox(g, 'Items', {'No file loaded...'});
            end
        end

%% Settings Window
        function openSettingsWindow(app)
            % Prevent opening multiple copies of the window
            if ~isempty(app.settingsFig) && isvalid(app.settingsFig)
                figure(app.settingsFig);
                return;
            end

            % Try loading 'default' settings at startup using your Settings class
            try
                app.controler.settings.loadHwConfig('default');
            catch
                disp('Could not load default.json automatically. Initializing fallback structure.');
                % Exact structure match fallback based on your default.json
                app.controler.settings.hwConfig = struct(...
                    'plc', struct(...
                        'xAxis', struct('fTenzoCons',0.01, 'fKp',10, 'fKi',0.1, 'fIntegralLimit',10, 'fForceTolerance',0.1, 'fMaxVelocity',100, 'fMaxForce',10, 'fMaxPosition',0.1), ...
                        'yAxis', struct('fTenzoCons',0.01, 'fKp',10, 'fKi',0.1, 'fIntegralLimit',10, 'fForceTolerance',0.1, 'fMaxVelocity',100, 'fMaxForce',10, 'fMaxPosition',0.1)), ...
                    'camera', struct('exposureTimeAbs',10000, 'gainRaw',300, 'acquisitionFrameRateAbs',15));
            end

            % Create floating window centered on screen
            app.settingsFig = uifigure('Name', 'Hardware Configuration Manager', 'Position', [350, 200, 460, 520], 'WindowStyle', 'normal');
            
            % Main vertical layout
            mainGridSettings = uigridlayout(app.settingsFig, [3, 1]);
            mainGridSettings.RowHeight = {50, '1x', 45};

            % --- Top Bar: Configuration File Switching / Creating ---
            topGrid = uigridlayout(mainGridSettings, [1, 4]);
            topGrid.ColumnWidth = {'1x', 65, 65, 80};

            % Configuration Dropdown populated from your class method
            app.configDrop = uidropdown(topGrid, 'Items', app.controler.settings.listHwConfigs());
            if ismember('default', app.configDrop.Items)
                app.configDrop.Value = 'default';
            end

            uibutton(topGrid, 'Text', 'Load', 'ButtonPushedFcn', @(~,~) loadSelectedConfig());
            uibutton(topGrid, 'Text', 'Save', 'ButtonPushedFcn', @(~,~) saveCurrentConfig());
            uibutton(topGrid, 'Text', 'Save As', 'ButtonPushedFcn', @(~,~) saveAsNewConfig());

            % --- Middle Tab Group ---
            tabGroup = uitabgroup(mainGridSettings);
            
            % 1. Camera Settings Tab
            camTab = uitab(tabGroup, 'Title', 'Camera Settings');
            camGrid = uigridlayout(camTab, [4, 2]);
            camGrid.RowHeight = {30, 30, 30, '1x'};
            app.camUI.exposure               = createField(camGrid, 'Exposure Time (us):');
            app.camUI.gainRaw                = createField(camGrid, 'Gain Raw:');
            app.camUI.acquisitionFrameRateAbs = createField(camGrid, 'Acquisition Frame Rate (FPS):');

            % 2. PLC X-Axis Tab
            plcxTab = uitab(tabGroup, 'Title', 'PLC X-Axis');
            plcxGrid = uigridlayout(plcxTab, [9, 2]);
            app.plcXUI = createPlcFields(plcxGrid);

            % 3. PLC Y-Axis Tab
            plcyTab = uitab(tabGroup, 'Title', 'PLC Y-Axis');
            plcyGrid = uigridlayout(plcyTab, [9, 2]);
            app.plcYUI = createPlcFields(plcyGrid);

            % --- Bottom Layout Action Buttons ---
            botGrid = uigridlayout(mainGridSettings, [1, 2]);
            botGrid.ColumnWidth = {'1x', '1x'};
            uibutton(botGrid, 'Text', 'Apply Settings', 'BackgroundColor', [0.4 0.9 0.4], 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) applyAllSettings());
            uibutton(botGrid, 'Text', 'Close Window', 'ButtonPushedFcn', @(~,~) delete(app.settingsFig));

            % Pre-populate UI fields with data from loaded JSON
            refreshUI();

            %% --- Internal Framework UI Utilities ---

            function fieldMap = createPlcFields(parentGrid)
                parentGrid.RowHeight = repmat({30}, 1, 9);
                fieldMap.fTenzoCons      = createField(parentGrid, 'Tenzo Constant:');
                fieldMap.fKp             = createField(parentGrid, 'Kp (Proportional):');
                fieldMap.fKi             = createField(parentGrid, 'Ki (Integral):');
                fieldMap.fIntegralLimit  = createField(parentGrid, 'Integral Limit:');
                fieldMap.fForceTolerance = createField(parentGrid, 'Force Tolerance:');
                fieldMap.fMaxVelocity    = createField(parentGrid, 'Max Velocity:');
                fieldMap.fMaxForce       = createField(parentGrid, 'Max Force:');
                fieldMap.fMaxPosition    = createField(parentGrid, 'Max Position:');
            end

            function editFld = createField(parent, labelText)
                uilabel(parent, 'Text', labelText, 'HorizontalAlignment', 'right');
                editFld = uieditfield(parent, 'numeric', 'Value', 0);
            end

            function refreshUI()
                % Pulls structural data from config class variable and populates UI fields
                cfg = app.controler.settings.hwConfig;
                if isempty(cfg), return; end
                
                app.camUI.exposure.Value               = cfg.camera.exposureTimeAbs;
                app.camUI.gainRaw.Value                = cfg.camera.gainRaw;
                app.camUI.acquisitionFrameRateAbs.Value = cfg.camera.acquisitionFrameRateAbs;

                pushPlcFields(app.plcXUI, cfg.plc.xAxis);
                pushPlcFields(app.plcYUI, cfg.plc.yAxis);
            end

            function pushPlcFields(uiStruct, dataStruct)
                uiStruct.fTenzoCons.Value      = dataStruct.fTenzoCons;
                uiStruct.fKp.Value             = dataStruct.fKp;
                uiStruct.fKi.Value             = dataStruct.fKi;
                uiStruct.fIntegralLimit.Value  = dataStruct.fIntegralLimit;
                uiStruct.fForceTolerance.Value = dataStruct.fForceTolerance;
                uiStruct.fMaxVelocity.Value    = dataStruct.fMaxVelocity;
                uiStruct.fMaxForce.Value       = dataStruct.fMaxForce;
                uiStruct.fMaxPosition.Value    = dataStruct.fMaxPosition;
            end

            function gatherUIValuesToStruct()
                % Captures input values written in the UI textfields back to the settings class memory
                cfg = app.controler.settings.hwConfig;
                
                cfg.camera.exposureTimeAbs         = app.camUI.exposure.Value;
                cfg.camera.gainRaw                 = app.camUI.gainRaw.Value;
                cfg.camera.acquisitionFrameRateAbs = app.camUI.acquisitionFrameRateAbs.Value;

                cfg.plc.xAxis = pullPlcFields(app.plcXUI);
                cfg.plc.yAxis = pullPlcFields(app.plcYUI);
                
                app.controler.settings.hwConfig = cfg;
            end

            function outPlcStruct = pullPlcFields(uiStruct)
                outPlcStruct.fTenzoCons      = uiStruct.fTenzoCons.Value;
                outPlcStruct.fKp             = uiStruct.fKp.Value;
                outPlcStruct.fKi             = uiStruct.fKi.Value;
                outPlcStruct.fIntegralLimit  = uiStruct.fIntegralLimit.Value;
                outPlcStruct.fForceTolerance = uiStruct.fForceTolerance.Value;
                outPlcStruct.fMaxVelocity    = uiStruct.fMaxVelocity.Value;
                outPlcStruct.fMaxForce       = uiStruct.fMaxForce.Value;
                outPlcStruct.fMaxPosition    = uiStruct.fMaxPosition.Value;
            end

            %% --- Action Callbacks ---

            function loadSelectedConfig()
                filename = app.configDrop.Value;
                try
                    app.controler.settings.loadHwConfig(filename);
                    refreshUI();
                    disp(['Configuration [', filename, '] successfully loaded.']);
                catch ME
                    uialert(app.settingsFig, ME.message, 'Configuration Load Error');
                end
            end

            function saveCurrentConfig()
                gatherUIValuesToStruct();
                filename = app.configDrop.Value;
                try
                    app.controler.settings.saveHwConfig(filename);
                    disp(['Configuration [', filename, '] updated and saved.']);
                catch ME
                    uialert(app.settingsFig, ME.message, 'Configuration Save Error');
                end
            end

            function saveAsNewConfig()
                gatherUIValuesToStruct();
                answer = inputdlg('Enter new configuration filename:', 'Create New Config File', [1 50], {'custom_config'});
                if isempty(answer) || isempty(answer{1}), return; end 
                
                filename = answer{1};
                try
                    app.controler.settings.saveHwConfig(filename);
                    % Re-fetch filesystem contents to populate new file inside dropdown selection
                    app.configDrop.Items = app.controler.settings.listHwConfigs();
                    app.configDrop.Value = filename;
                    disp(['New configuration file [', filename, '.json] created.']);
                catch ME
                    uialert(app.settingsFig, ME.message, 'Create Config Error');
                end
            end

            function applyAllSettings()
                gatherUIValuesToStruct();
                
                % Call underlying system implementation framework engines
                app.controler.settings.applyCameraConfig();
                app.controler.settings.applyPlcConfig();
                
                uialert(app.settingsFig, 'All system configuration values applied successfully!', 'Success', 'Icon', 'success');
            end
        end

    end
end
