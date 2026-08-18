function restoreFigureFocus(parentFig)
%RESTOREFIGUREFOCUS Bring an app UI figure back after a dialog closes.
% Windows can activate another application when an independent MATLAB
% window or a legacy dialog is destroyed. Focus restoration is best-effort
% so a closing or already deleted parent never interrupts the UI callback.

if isempty(parentFig) || ~isscalar(parentFig) || ...
        ~isgraphics(parentFig, 'figure') || ...
        ~strcmp(parentFig.Visible, 'on')
    return;
end

try
    % Flush the dialog deletion before asking Windows to activate the app.
    drawnow;
    figure(parentFig);
catch
    % The parent can be deleted concurrently during application shutdown.
end
end
