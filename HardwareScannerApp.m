function HardwareScannerApp()
    % Main Figure Window
    fig = uifigure('Name', 'Hardware Scanner', 'Position', [100, 100, 1350, 680], ...
        'CloseRequestFcn', @onAppClose);
    
    % Hardware Object Handles & States
    stage = [];
    cam = [];
    isScanning = false;
    isPreviewing = false;
    
    % Data Logging Arrays & Structures
    sweepData = struct('Position', {}, 'Settings', {}, 'Frame', {});
    sweepHardwareInfo = struct();
    sweepSettingsDescriptions = struct();
    
    % Physical Coordinate Vectors for Live View
    xData = [];
    yData = [];
    
    % ==========================================
    % UI Components: Center Panel (Live View)
    % ==========================================
    axLive = uiaxes(fig, 'Position', [280, 130, 500, 500]);
    title(axLive, 'DataRay Live View');
    xlabel(axLive, 'X (\mum)');
    ylabel(axLive, 'Y (\mum)');
    axis(axLive, 'image');
    colormap(axLive, 'jet');
    colorbar(axLive);
    
    % Live View CLim Controls
    lblLiveCLim = uilabel(fig, 'Position', [280, 85, 80, 22], 'Text', 'Color Limits:');
    edtLiveCLimMin = uieditfield(fig, 'numeric', 'Position', [360, 85, 60, 22], ...
        'Value', 0, 'ValueDisplayFormat', '%.0f', 'ValueChangedFcn', @applyLiveCLim);
    edtLiveCLimMax = uieditfield(fig, 'numeric', 'Position', [430, 85, 60, 22], ...
        'Value', 4095, 'ValueDisplayFormat', '%.0f', 'ValueChangedFcn', @applyLiveCLim);
    
    % ==========================================
    % UI Components: Right Panel (Inspect View)
    % ==========================================
    axInspect = uiaxes(fig, 'Position', [810, 130, 500, 500]);
    title(axInspect, 'Saved Sweep Data');
    xlabel(axInspect, 'X (\mum)');
    ylabel(axInspect, 'Y (\mum)');
    axis(axInspect, 'image');
    colormap(axInspect, 'jet');
    colorbar(axInspect);
    
    % Inspection Slider
    sldInspect = uislider(fig, 'Position', [810, 110, 480, 3], 'Enable', 'off', ...
        'ValueChangingFcn', @(src, event) updateInspectPlot(round(event.Value)), ...
        'ValueChangedFcn', @(src, event) onInspectSliderChange(event.Value));
        
    % Lower Controls
    lblInspectCLim = uilabel(fig, 'Position', [810, 35, 80, 22], 'Text', 'Color Limits:');
    edtInspectCLimMin = uieditfield(fig, 'numeric', 'Position', [890, 35, 50, 22], ...
        'Value', 0, 'ValueDisplayFormat', '%.0f', 'ValueChangedFcn', @applyInspectCLim);
    edtInspectCLimMax = uieditfield(fig, 'numeric', 'Position', [950, 35, 50, 22], ...
        'Value', 4095, 'ValueDisplayFormat', '%.0f', 'ValueChangedFcn', @applyInspectCLim);
        
    btnSave = uibutton(fig, 'Position', [1030, 30, 130, 35], ...
        'Text', 'Save Data to .mat', 'Enable', 'off', 'ButtonPushedFcn', @saveSweepData);
        
    btnAnalyze = uibutton(fig, 'Position', [1170, 30, 130, 35], ...
        'Text', 'Analyze ...', 'Enable', 'off', 'ButtonPushedFcn', @analyzeData);
    
    % ==========================================
    % UI Components: Left Panel (Controls)
    % ==========================================
    btnConnectCam = uibutton(fig, 'Position', [30, 620, 220, 30], ...
        'Text', 'Connect Camera', 'ButtonPushedFcn', @toggleCamera);
        
    btnConnectStage = uibutton(fig, 'Position', [30, 580, 220, 30], ...
        'Text', 'Connect Stage', 'ButtonPushedFcn', @toggleStage);
        
    btnHomeStage = uibutton(fig, 'Position', [30, 540, 220, 30], ...
        'Text', 'Home Stage', 'Enable', 'off', 'ButtonPushedFcn', @homeStage);
        
    % Stage Position
    lblPosition = uilabel(fig, 'Position', [30, 510, 220, 20], 'Text', 'Stage Position (mm):');
    sldPosition = uislider(fig, 'Position', [30, 490, 140, 3], ...
        'Limits', [0, 200], 'Value', 0, 'Enable', 'off', ...
        'ValueChangedFcn', @(src, event) applyPosition(event.Value));
    edtPosition = uieditfield(fig, 'numeric', 'Position', [180, 480, 70, 22], ...
        'Limits', [0, 200], 'Value', 0, 'Enable', 'off', ...
        'ValueDisplayFormat', '%.2f', 'ValueChangedFcn', @(src, event) applyPosition(event.Value));
        
    % Camera Exposure
    lblExposure = uilabel(fig, 'Position', [30, 440, 220, 20], 'Text', 'Camera Exposure (us):');
    sldExposure = uislider(fig, 'Position', [30, 420, 140, 3], ...
        'Limits', [85, 100000], 'Value', 2000, 'Enable', 'off', ...
        'MajorTicks', [85, 100000], 'MinorTicks', [], 'MajorTickLabels', {'85', '100000'}, ...
        'ValueChangedFcn', @(src, event) applyExposure(event.Value));
    edtExposure = uieditfield(fig, 'numeric', 'Position', [180, 410, 70, 22], ...
        'Limits', [85, 100000], 'Value', 2000, 'Enable', 'off', ...
        'ValueDisplayFormat', '%.0f', 'ValueChangedFcn', @(src, event) applyExposure(event.Value));
        
    chkAutoExposure = uicheckbox(fig, 'Position', [30, 360, 220, 22], ...
        'Text', 'Auto Exposure', 'Value', false, 'Enable', 'off', ...
        'ValueChangedFcn', @toggleAutoExposure);
        
    % Live Preview Button
    btnPreview = uibutton(fig, 'state', 'Position', [30, 290, 220, 30], ...
        'Text', 'Live Preview: OFF', 'Enable', 'off', 'ValueChangedFcn', @togglePreview);
        
    % Sweep Parameters
    lblSweep = uilabel(fig, 'Position', [30, 250, 220, 20], 'Text', 'Sweep Parameters (mm):', 'FontWeight', 'bold');
    uilabel(fig, 'Position', [30, 225, 40, 22], 'Text', 'Start:');
    edtSweepStart = uieditfield(fig, 'numeric', 'Position', [70, 225, 50, 22], 'Value', 0, 'Limits', [0, 200], 'ValueDisplayFormat', '%.1f');
    uilabel(fig, 'Position', [130, 225, 30, 22], 'Text', 'End:');
    edtSweepEnd = uieditfield(fig, 'numeric', 'Position', [160, 225, 50, 22], 'Value', 20, 'Limits', [0, 200], 'ValueDisplayFormat', '%.1f');
    uilabel(fig, 'Position', [30, 195, 40, 22], 'Text', 'Step:');
    edtSweepStep = uieditfield(fig, 'numeric', 'Position', [70, 195, 50, 22], 'Value', 0.5, 'Limits', [0.001, 200], 'ValueDisplayFormat', '%.2f');
        
    btnStart = uibutton(fig, 'Position', [30, 140, 220, 40], ...
        'Text', 'Start Sweep', 'Enable', 'off', 'ButtonPushedFcn', @startSweep);
        
    lblStatus = uilabel(fig, 'Position', [30, 90, 220, 40], ...
        'Text', 'Status: Disconnected', 'WordWrap', 'on');
        
    % ==========================================
    % Callbacks & Core Logic
    % ==========================================
    
    function onAppClose(src, ~)
        src.Visible = 'off'; 
        isPreviewing = false;
        isScanning = false;
        pause(0.5);
        if ~isempty(cam), delete(cam); end
        if ~isempty(stage), delete(stage); end
        delete(src);
    end

    function toggleCamera(~, ~)
        if isScanning, return; end
        
        if isempty(cam)
            lblStatus.Text = 'Status: Connecting Camera...';
            drawnow;
            try
                cam = DataRayCamera('localhost', '18080');
                
                currentExp = cam.getSetting('i_exposure_time_us');
                sldExposure.Value = currentExp;
                edtExposure.Value = currentExp;
                
                pxSize = cam.getSetting('d_x_pixel_size_um');
                binning = cam.getSetting('i_binning');
                w = double(cam.getSetting('i_width'));
                h = double(cam.getSetting('i_height'));
                
                effPx = pxSize * double(binning);
                xData = linspace(-w/2, w/2, w) * effPx;
                yData = linspace(-h/2, h/2, h) * effPx;
                
                applyLiveCLim();
                applyInspectCLim();
                
                btnConnectCam.Text = 'Disconnect Camera';
                btnConnectCam.BackgroundColor = [0.8500, 0.3250, 0.0980];
                btnConnectCam.FontColor = [1 1 1];
                
                sldExposure.Enable = 'on';
                edtExposure.Enable = 'on';
                chkAutoExposure.Enable = 'on';
                btnPreview.Enable = 'on'; 
                
                checkReadyState();
                lblStatus.Text = 'Status: Camera Connected.';
            catch ME
                lblStatus.Text = sprintf('Camera Error: %s', ME.message);
            end
        else
            lblStatus.Text = 'Status: Disconnecting Camera...';
            drawnow;
            
            stopPreviewGracefully();
            delete(cam);
            cam = [];
            
            btnConnectCam.Text = 'Connect Camera';
            btnConnectCam.BackgroundColor = [0.96, 0.96, 0.96]; 
            btnConnectCam.FontColor = [0 0 0];
            
            sldExposure.Enable = 'off';
            edtExposure.Enable = 'off';
            chkAutoExposure.Enable = 'off';
            btnPreview.Enable = 'off';
            btnStart.Enable = 'off';
            
            cla(axLive);
            title(axLive, 'DataRay Live View');
            
            lblStatus.Text = 'Status: Camera Disconnected.';
        end
    end

    function toggleStage(~, ~)
        if isScanning, return; end
        
        if isempty(stage)
            lblStatus.Text = 'Status: Connecting Stage...';
            drawnow;
            try
                stage = ZaberStage("COM4");
                stage.setSpeed(5.0); 
                
                btnConnectStage.Text = 'Disconnect Stage';
                btnConnectStage.BackgroundColor = [0.8500, 0.3250, 0.0980]; 
                btnConnectStage.FontColor = [1 1 1];
                
                btnHomeStage.Enable = 'on';
                sldPosition.Enable = 'on';
                edtPosition.Enable = 'on';
                
                checkReadyState();
                lblStatus.Text = 'Status: Stage Connected.';
            catch ME
                lblStatus.Text = sprintf('Stage Error: %s', ME.message);
            end
        else
            lblStatus.Text = 'Status: Disconnecting Stage...';
            drawnow;
            
            delete(stage);
            stage = [];
            
            btnConnectStage.Text = 'Connect Stage';
            btnConnectStage.BackgroundColor = [0.96, 0.96, 0.96]; 
            btnConnectStage.FontColor = [0 0 0];
            
            btnHomeStage.Enable = 'off';
            sldPosition.Enable = 'off';
            edtPosition.Enable = 'off';
            btnStart.Enable = 'off';
            
            if ~isempty(cam)
                title(axLive, 'DataRay Live View');
            end
            
            lblStatus.Text = 'Status: Stage Disconnected.';
        end
    end

    function checkReadyState()
        if ~isempty(stage) && ~isempty(cam)
            btnStart.Enable = 'on';
        end
    end

    function homeStage(~, ~)
        if isempty(stage), return; end
        lblStatus.Text = 'Status: Homing Stage...';
        drawnow;
        stage.home();
        sldPosition.Value = 0; 
        edtPosition.Value = 0;
        lblStatus.Text = 'Status: Stage Homed.';
    end

    function applyPosition(target_mm)
        if isempty(stage) || isScanning, return; end
        lblStatus.Text = sprintf('Status: Moving to %.2f mm...', target_mm);
        drawnow;
        stage.moveAbsolute(target_mm);
        actual_mm = stage.getPosition();
        sldPosition.Value = actual_mm;
        edtPosition.Value = actual_mm;
        lblStatus.Text = sprintf('Status: Arrived at %.4f mm', actual_mm);
    end

    function applyLiveCLim(~, ~)
        minV = edtLiveCLimMin.Value;
        maxV = edtLiveCLimMax.Value;
        if maxV > minV, axLive.CLim = [minV, maxV]; end
    end

    function applyInspectCLim(~, ~)
        minV = edtInspectCLimMin.Value;
        maxV = edtInspectCLimMax.Value;
        if maxV > minV, axInspect.CLim = [minV, maxV]; end
    end

    function applyExposure(target_us)
        if isempty(cam) || isScanning, return; end
        wasPreviewing = stopPreviewGracefully();
        chkAutoExposure.Value = false;
        
        lblStatus.Text = 'Status: Reconnecting to apply exposure...';
        drawnow;
        try
            actual_us = cam.setExposureWithRestart(target_us);
            sldExposure.Value = actual_us;
            edtExposure.Value = actual_us;
            lblStatus.Text = sprintf('Status: Exposure forced to %d us', actual_us);
        catch ME
            lblStatus.Text = sprintf('Error: %s', ME.message);
        end
        resumePreviewIfNeeded(wasPreviewing);
    end

    function toggleAutoExposure(src, event)
        if isempty(cam) || isScanning, return; end
        wasPreviewing = stopPreviewGracefully();
        isAuto = event.Value;
        
        lblStatus.Text = 'Status: Reconnecting for Auto Exposure...';
        drawnow;
        try
            if isAuto
                actual_us = cam.setAutoExposureWithRestart(true);
                sldExposure.Value = actual_us;
                edtExposure.Value = actual_us;
                lblStatus.Text = 'Status: Auto Exposure ON.';
                sldExposure.Enable = 'off';
                edtExposure.Enable = 'off';
            else
                try curExp = cam.getSetting('i_exposure_time_us'); catch, curExp = sldExposure.Value; end
                actual_us = cam.setExposureWithRestart(curExp);
                sldExposure.Value = actual_us;
                edtExposure.Value = actual_us;
                lblStatus.Text = sprintf('Status: Auto Exposure OFF. Locked at %d us', actual_us);
                sldExposure.Enable = 'on';
                edtExposure.Enable = 'on';
            end
        catch ME
            lblStatus.Text = sprintf('Error: %s', ME.message);
        end
        resumePreviewIfNeeded(wasPreviewing);
    end

    function wasPreviewing = stopPreviewGracefully()
        wasPreviewing = isPreviewing;
        if isPreviewing
            isPreviewing = false;
            btnPreview.Value = false;
            btnPreview.Text = 'Live Preview: OFF';
            btnPreview.BackgroundColor = [0.96, 0.96, 0.96];
            pause(0.2); 
        end
    end

    function resumePreviewIfNeeded(wasPreviewing)
        if wasPreviewing
            btnPreview.Value = true;
            togglePreview(btnPreview, struct('Value', true));
        end
    end

    function togglePreview(src, event)
        if ~isvalid(src), return; end
        isPreviewing = event.Value;
        if isPreviewing
            src.Text = 'Live Preview: ON';
            src.BackgroundColor = [0.4660, 0.6740, 0.1880]; 
            btnStart.Enable = 'off'; 
            lblStatus.Text = 'Status: Live Preview Active';
            
            while isPreviewing && isvalid(fig)
                imgMatrix = cam.getFrame();
                if ~isvalid(fig), break; end 
                
                if ~isempty(imgMatrix)
                    hImg = findobj(axLive, 'Type', 'image');
                    if isempty(hImg)
                        imagesc(axLive, 'XData', xData, 'YData', yData, 'CData', imgMatrix);
                        axis(axLive, 'image');
                    else
                        hImg.CData = imgMatrix;
                    end
                    
                    if ~isempty(stage)
                        title(axLive, sprintf('Position: %.2f mm', sldPosition.Value));
                    else
                        title(axLive, 'DataRay Live View');
                    end
                    drawnow;
                    
                    if ~isvalid(fig) || ~isvalid(chkAutoExposure), break; end
                    
                    if chkAutoExposure.Value
                        try
                            curExp = cam.getSetting('i_exposure_time_us');
                            if isvalid(sldExposure)
                                sldExposure.Value = curExp;
                                edtExposure.Value = curExp;
                            end
                        catch
                        end
                    end
                else
                    pause(0.05); 
                end
            end
            
            if isvalid(fig)
                src.Text = 'Live Preview: OFF';
                src.BackgroundColor = [0.96, 0.96, 0.96]; 
                if ~isScanning && ~isempty(stage) && ~isempty(cam), btnStart.Enable = 'on'; end
                lblStatus.Text = 'Status: Live Preview Stopped.';
            end
        else
            src.Text = 'Live Preview: OFF';
            src.BackgroundColor = [0.96, 0.96, 0.96]; 
            if ~isScanning && ~isempty(stage) && ~isempty(cam), btnStart.Enable = 'on'; end
            lblStatus.Text = 'Status: Live Preview Stopped.';
        end
    end

    % ==========================================
    % Data Logging & Display Functions
    % ==========================================
    function onInspectSliderChange(val)
        val = round(val); 
        sldInspect.Value = val;
        updateInspectPlot(val);
    end

    function updateInspectPlot(idx)
        if isempty(sweepData) || idx < 1 || idx > length(sweepData), return; end
        
        imgMatrix = sweepData(idx).Frame;
        setts = sweepData(idx).Settings;
        pos = sweepData(idx).Position;
        
        pxSize = setts.d_x_pixel_size_um;
        binning = double(setts.i_binning);
        w = double(setts.i_width);
        h = double(setts.i_height);
        effPx = pxSize * binning;
        
        xIns = linspace(-w/2, w/2, w) * effPx;
        yIns = linspace(-h/2, h/2, h) * effPx;
        
        hImg = findobj(axInspect, 'Type', 'image');
        if isempty(hImg)
            imagesc(axInspect, 'XData', xIns, 'YData', yIns, 'CData', imgMatrix);
            axis(axInspect, 'image');
        else
            hImg.XData = xIns;
            hImg.YData = yIns;
            hImg.CData = imgMatrix;
        end
        title(axInspect, sprintf('Frame %d | Position: %.2f mm', idx, pos));
    end

    function saveSweepData(~, ~)
        if isempty(sweepData)
            uialert(fig, 'No data exists to save.', 'Save Error');
            return;
        end
        
        [file, path] = uiputfile('*.mat', 'Save Sweep Data');
        if ischar(file)
            % Create an independent, non-modal status window
            progFig = uifigure('Name', 'Saving Data...', 'Position', ...
                [fig.Position(1) + fig.Position(3)/2 - 150, ...
                 fig.Position(2) + fig.Position(4)/2 - 50, 300, 100], ...
                 'WindowStyle', 'normal', 'Resize', 'off');
                 
            uilabel(progFig, 'Text', 'Writing large sweep data to disk (v7.3 format). Please wait...', ...
                'Position', [20, 20, 260, 60], 'HorizontalAlignment', 'center', 'WordWrap', 'on');
                
            lblStatus.Text = 'Status: Saving data to disk...';
            drawnow; 
            
            try
                exportStruct = struct();
                exportStruct.sweepData = sweepData;
                exportStruct.hardwareInfo = sweepHardwareInfo;
                exportStruct.settingsDescriptions = sweepSettingsDescriptions;
                
                save(fullfile(path, file), '-struct', 'exportStruct', '-v7.3');
                lblStatus.Text = sprintf('Status: Saved to %s', file);
            catch ME
                lblStatus.Text = sprintf('Save Error: %s', ME.message);
            end
            
            % Clean up progress window and explicitly return focus to main GUI
            if isvalid(progFig)
                delete(progFig);
            end
            if isvalid(fig)
                figure(fig);
                drawnow;
            end
        else
            % User cancelled, restore focus
            if isvalid(fig)
                figure(fig);
                drawnow;
            end
        end
    end
    
    function analyzeData(~, ~)
        if isempty(sweepData)
            uialert(fig, 'No data exists to analyze. Run a sweep first.', 'Analysis Error');
            return;
        end
        % Call the standalone application file
        BeamAnalysisApp(sweepData, sweepHardwareInfo, sweepSettingsDescriptions);
    end

    function startSweep(~, ~)
        if isScanning 
            isScanning = false;
            btnStart.Text = 'Aborting...';
            btnStart.Enable = 'off';
            return;
        end
        
        sStart = edtSweepStart.Value;
        sEnd = edtSweepEnd.Value;
        sStep = edtSweepStep.Value;
        
        if sStep <= 0
            lblStatus.Text = 'Error: Step size must be greater than 0.';
            return;
        end
        if sStart > sEnd, sStep = -sStep; end
        
        isScanning = true;
        btnStart.Text = 'Stop Sweep';
        btnStart.BackgroundColor = [0.8500, 0.3250, 0.0980];
        
        btnConnectCam.Enable = 'off';
        btnConnectStage.Enable = 'off';
        btnHomeStage.Enable = 'off';
        btnPreview.Enable = 'off';
        sldPosition.Enable = 'off';
        edtPosition.Enable = 'off';
        sldExposure.Enable = 'off';
        edtExposure.Enable = 'off';
        chkAutoExposure.Enable = 'off';
        sldInspect.Enable = 'off';
        btnSave.Enable = 'off';
        btnAnalyze.Enable = 'off';
        
        sweepData = struct('Position', {}, 'Settings', {}, 'Frame', {});
        sweepHardwareInfo = struct();
        sweepSettingsDescriptions = struct();
        
        if ~isempty(cam)
            sweepHardwareInfo.CameraName = cam.DeviceName;
            sweepHardwareInfo.CameraID = cam.DeviceID;
            sweepHardwareInfo.CameraBaseURL = cam.BaseURL;
            sweepSettingsDescriptions = cam.getSettingsDescriptions();
        end
        if ~isempty(stage)
            sweepHardwareInfo.StageModel = 'Zaber X-LSM200A (ASCII)';
        end
        
        try
            for target_mm = sStart : sStep : sEnd
                if ~isvalid(fig) || ~isScanning, break; end 
                
                lblStatus.Text = sprintf('Status: Sweeping... Moving to %.1f mm', target_mm);
                drawnow;
                if ~isvalid(fig) || ~isScanning, break; end 
                
                stage.moveAbsolute(target_mm);
                actual_mm = stage.getPosition();
                
                if ~isvalid(fig) || ~isScanning, break; end
                
                sldPosition.Value = actual_mm;
                edtPosition.Value = actual_mm;
                
                imgMatrix = cam.getFrame();
                
                if ~isvalid(fig) || ~isScanning, break; end
                
                if ~isempty(imgMatrix)
                    hImgLive = findobj(axLive, 'Type', 'image');
                    if isempty(hImgLive)
                        imagesc(axLive, 'XData', xData, 'YData', yData, 'CData', imgMatrix);
                        axis(axLive, 'image');
                    else
                        hImgLive.CData = imgMatrix;
                    end
                    title(axLive, sprintf('Position: %.2f mm', actual_mm));
                    
                    idx = length(sweepData) + 1;
                    sweepData(idx).Position = actual_mm;
                    sweepData(idx).Settings = cam.getAllSettings();
                    sweepData(idx).Frame = imgMatrix;
                    
                    updateInspectPlot(idx);
                    drawnow;
                    
                    if ~isvalid(fig) || ~isvalid(chkAutoExposure) || ~isScanning, break; end
                    
                    if chkAutoExposure.Value
                        try
                            curExp = cam.getSetting('i_exposure_time_us');
                            sldExposure.Value = curExp;
                            edtExposure.Value = curExp;
                        catch
                        end
                    end
                end
            end
            
            if isvalid(fig)
                if ~isScanning
                    lblStatus.Text = 'Status: Sweep Aborted.';
                else
                    lblStatus.Text = 'Status: Sweep Complete.';
                end
            end
        catch ME
            if isvalid(fig)
                lblStatus.Text = sprintf('Error: %s', ME.message);
            end
        end
        
        if isvalid(fig)
            isScanning = false;
            btnStart.Text = 'Start Sweep';
            btnStart.BackgroundColor = [0.96, 0.96, 0.96]; 
            btnStart.Enable = 'on';
            
            btnConnectCam.Enable = 'on';
            btnConnectStage.Enable = 'on';
            btnHomeStage.Enable = 'on';
            btnPreview.Enable = 'on';
            sldPosition.Enable = 'on';
            edtPosition.Enable = 'on';
            chkAutoExposure.Enable = 'on';
            if ~chkAutoExposure.Value
                sldExposure.Enable = 'on';
                edtExposure.Enable = 'on';
            end
            
            N = length(sweepData);
            if N > 1
                sldInspect.Limits = [1, N];
                numTicks = min(5, N);
                tickIndices = round(linspace(1, N, numTicks));
                sldInspect.MajorTicks = tickIndices;
                
                tickLabels = cell(1, numTicks);
                for k = 1:numTicks
                    tickLabels{k} = sprintf('%.2f mm', sweepData(tickIndices(k)).Position);
                end
                sldInspect.MajorTickLabels = tickLabels;
                
                sldInspect.Value = N;
                sldInspect.Enable = 'on';
                btnSave.Enable = 'on';
                btnAnalyze.Enable = 'on';
            elseif N == 1
                sldInspect.Limits = [1, 2]; 
                sldInspect.Value = 1;
                sldInspect.Enable = 'off';
                btnSave.Enable = 'on';
                btnAnalyze.Enable = 'on';
            end
        end
    end
end