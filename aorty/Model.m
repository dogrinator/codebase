classdef Model < handle
    % In this class i am saving all actual values from realtime to
    %  vectors / matrixes
    
    properties
        % Tenzo
        tenzoX
        tenzoY

        % Camera
        cameraFrame
        testData                % A pre-allocated 4D array for when "Start Test" is pressed
        isRecording = false;    % If True = store data to testData
        recordIndex = 1;        % number of frames recived
    end
    
    methods
        function model = Model()
            model.tenzoX = [];
            model.tenzoY = [];
            model.cameraFrame = [];
        end
        
        %% save values
        function saveTenzoX(model,actualXval)
            model.tenzoX(:,end+1) = actualXval;
        end

        function saveTenzoY(model,actualYval)
            model.tenzoY(:,end+1) = actualYval;
        end

        function saveCameraFrame(model, frame)
            model.cameraFrame = frame;  % save 1 frame

            % If a test is running, save to the permanent storage
            if model.isRecording
                model.testData(:,:,model.recordIndex) = frame;
                model.recordIndex = model.recordIndex + 1;
            end
        end
    end
end

