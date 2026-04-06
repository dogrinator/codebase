classdef View < handle
    %VIEW Summary of this class goes here
    %   Detailed explanation goes here TODO
    
    properties
        % control and model class 
        controler

        % UI
        fig
        mainGrid
        leftGrid
        
        % Camera UI
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
        FxAxes
        FyAxes

    end
    
    methods
        %% Main Init view function
        function app = View(controler)

            % init def of important classes
            app.controler = controler;

            % Init creation of main app
            app.fig = uifigure('Name','Aorty +++ premium',...
                               'Position',[200 200 1000 600]);
            
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
            app.controler.closeCam()
            app.controler.disconnectPLC()
            delete(app.fig)
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
            
            app.settingsCamBtn = uibutton(topGrid,'Text','Camera',...
                'ButtonPushedFcn',@(src,event)app.cameraSettingsCallback());
            
            app.settingsCamBtn.Layout.Column = 2;
            
            app.camSwitch = uiswitch(topGrid,'slider');
            app.camSwitch.Items = {'OFF','ON'};
            app.camSwitch.Value = 'OFF';
            app.camSwitch.Layout.Column = 3;
            
            app.camSwitch.ValueChangedFcn = @(src,event)app.connectCameraCallback(src);
            
            % Camera preview
            
            app.cameraAxes = uiaxes(grid);
            % Create a dummy image once and store its handle
            app.camImageHandle = imagesc(app.cameraAxes, zeros(1024, 1024, 'uint8')); 
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
            app.controler.connectCamera(app,src)
        end
        
        function cameraSettingsCallback(app)
            if isempty(app.controler.cam), return; end
            src = getselectedsource(app.controler.cam);
            
            settingsFig = uifigure('Name', 'Camera Hardware Settings', 'Position', [500 500 350 200]);
            g = uigridlayout(settingsFig, [3 2]);
            
            % Exposure - Most important for motion blur
            uilabel(g, 'Text', 'Exposure (us):');
            ef = uieditfield(g, 'numeric', 'Value', src.ExposureTimeAbs);
            ef.ValueChangedFcn = @(s,e) app.setattr(src, 'ExposureTimeAbs', s.Value);
            
            % Gain - Use if the image is too dark even with high exposure
            uilabel(g, 'Text', 'Gain:');
            gn = uieditfield(g, 'numeric', 'Value', src.GainRaw);
            gn.ValueChangedFcn = @(s,e) app.setattr(src, 'GainRaw', s.Value);
            
            % Frame Rate Control
            uilabel(g, 'Text', 'Acquisition Frame Rate:');
            fr = uieditfield(g, 'numeric', 'Value', src.AcquisitionFrameRateAbs);
            fr.ValueChangedFcn = @(s,e) app.setattr(src, 'AcquisitionFrameRateAbs', s.Value);
        end
        
        % Helper to handle errors if setting is out of range
        function setattr(obj, prop, val)
            try 
                obj.(prop) = val; 
            catch
                % warning (TODO)
            end
        end

        %% Tenzo
        function app = createTenzoPanel(app)
            % Panel
            app.tenzoPanel = uipanel(app.leftGrid);
            app.tenzoPanel.Title = 'Tenzo';
            
            grid = uigridlayout(app.tenzoPanel,[1 2]);
            
            % Plots
            app.FxAxes = uiaxes(grid);
            title(app.FxAxes,'Fx')
            
            app.FyAxes = uiaxes(grid);
            title(app.FyAxes,'Fy')
        
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
                'Items', {'Manual Control', 'Constant Force', 'Oscillation', 'G-Code Speed'}, ...
                'ValueChangedFcn', @(src,event) app.updateTestUI(src.Value));

            % Connect switch
            app.plcSwitch = uiswitch(topGrid, 'slider', 'Items', {'OFF','ON'});
            app.plcSwitch.ValueChangedFcn = @(src,event) app.controler.connectPLC(app,src);
        
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
            
            % === TODO === %
            switch selectedMode
                case 'Manual Control'
                    % Create a 2x2 grid for Manual Buttons
                    g = uigridlayout(app.dynamicControlGroup, [3 2]);
                    uibutton(g, 'Text', 'Move X +', 'ButtonPushedFcn', @(s,e) app.controler.plcMove('X', 1));
                    uibutton(g, 'Text', 'Move X -', 'ButtonPushedFcn', @(s,e) app.controler.plcMove('X', -1));
                    uibutton(g, 'Text', 'Move Y +', 'ButtonPushedFcn', @(s,e) app.controler.plcMove('Y', 1));
                    uibutton(g, 'Text', 'Move Y -', 'ButtonPushedFcn', @(s,e) app.controler.plcMove('Y', -1));
                    uibutton(g, 'Text', 'ENABLE MOTORS', 'BackgroundColor', [0.8 1 0.8]);
        
                case 'Constant Force'
                    g = uigridlayout(app.dynamicControlGroup, [2 2]);
                    uilabel(g, 'Text', 'Target Force (N):');
                    uieditfield(g, 'numeric', 'Value', 10);
                    uibutton(g, 'Text', 'START PID CONTROL');
                    
                case 'G-Code Speed'
                    g = uigridlayout(app.dynamicControlGroup, [2 1]);
                    uibutton(g, 'Text', 'Load G-Code File', 'Icon', 'file');
                    uilistbox(g, 'Items', {'No file loaded...'});
            end
        end
    end
end
