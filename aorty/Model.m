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
        isRecording = true;    % If True = store data to testData
        recordIndex = 1;        % number of frames recived
    end
    
    methods
        function model = Model()
            model.tenzoX = 0;
            model.tenzoY = 0;
            model.cameraFrame = [];
        end
        
        %% save values
        function saveTenzoX(model,actualXval)
            model.tenzoX = sum(actualXval)/length(actualXval);
        end

        function saveTenzoY(model,actualYval)
            model.tenzoY = sum(actualYval)/length(actualYval);
        end

        function saveCameraFrame(model, frame)
            model.cameraFrame = frame; 
            
            if model.isRecording
                % 1. Príprava textu
                txt = sprintf('X: %.2f | Y: %.2f', model.tenzoX, model.tenzoY);
                
                % 2. Vloženie textu priamo do pixelov obrazu
                annotatedFrame = insertText(frame, [20 20], txt, ...
                    'FontSize', 18, ...
                    'TextColor', 'white', ...
                    'BoxOpacity', 0.4);
        
                % 3. Uloženie do TIFF súboru
                filename = "myMultipageFile.tiff";
                
                if model.recordIndex == 1 && exist(filename, "file")
                    delete(filename);
                end
    
                annotatedFrameG = rgb2gray(annotatedFrame);
                imwrite(annotatedFrameG, filename, "WriteMode", "append","Compression","packbits");
                
                model.recordIndex = model.recordIndex + 1;
            end
        end
    end
end

