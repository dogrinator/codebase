classdef Model < handle
    % In this class i am saving all actual values from realtime to
    %  vectors / matrixes
    
    properties
        % Tenzo
        tenzoX = []
        tenzoY = []

        % Camera
        isRecording = false;     % If True = store data to testData
        recordIndex = 1;        % number of frames recived
        selectedFolder = 0      % folder in witch fotos will save
    end
    
    methods
        function model = Model()
        end
        
        %% save values
        function saveTenzoX(model,actualXval)
            model.tenzoX = sum(actualXval)/length(actualXval);
        end

        function saveTenzoY(model,actualYval)
            model.tenzoY = sum(actualYval)/length(actualYval);
        end

        function saveCameraFrame(model, frame)
            try
                if model.isRecording
                    
                    % 1. Prepare texts
                    txt = sprintf('X: %.5f | Y: %.5f', model.tenzoX, model.tenzoY);
                    filename = sprintf('/frame%d.tiff', model.recordIndex);
                    fullFileName = fullfile(model.selectedFolder, filename);

                    % Save time
                    timeStamp = datetime('now','Format','HH:mm:ss.SSS');
                    stimeStamp = string(timeStamp);
                    txtDesc = 'TimeStamp:' + stimeStamp + txt;
                    
                    % 2. Vloženie textu priamo do pixelov obrazu
                    annotatedFrame = insertText(frame, [20 20], txt, ...
                                                'FontSize', 18, ...
                                                'TextColor', 'white');
            
                    % 3. Uloženie do TIFF súboru
                    imwrite(annotatedFrame, fullFileName, "WriteMode", "overwrite",'ColorSpace','grayscale','Description',txtDesc);
                    
                    model.recordIndex = model.recordIndex + 1;
                end
            catch ME
                fprintf(app.fig, getReport(ME), 'Camera save frame Error');
            end
        end
    end
end
