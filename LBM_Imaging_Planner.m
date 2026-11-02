function LBM_Imaging_Planner()
    % Internal properties
    maxResonantAmplitude = 576; % microns
    flytoTime = 3; % milliseconds
    objectiveResolution = 160; % microns per degree
    
    % Global graphical objects & State (Synced across tabs)
    hasRealImage = false;
    winROI = [];
    fovROI = [];
    scalebarLine = [];
    scalebarText = [];
    compassLines = gobjects(0);
    compassTexts = gobjects(0);
    
    % Create main figure
    fig = uifigure('Name', 'LBM Imaging Planner', 'Position', [100 100 950 700]);
    
    % Create main layout
    mainGrid = uigridlayout(fig, [1 2]);
    mainGrid.ColumnWidth = {'1.5x', '1x'}; 
    
    %% --- LEFT PANEL ---
    leftGrid = uigridlayout(mainGrid, [2 1]);
    leftGrid.RowHeight = {'1x', 80}; 
    
    % Add Axes
    ax = uiaxes(leftGrid);
    title(ax, 'Image View');
    imagesc(ax, peaks(50)); % Placeholder
    axis(ax, 'image');
    
    % Sub-grid for buttons beneath the axes
    btnGrid = uigridlayout(leftGrid, [2 3]);
    btnGrid.Padding = [0 0 0 0];
    btnGrid.RowHeight = {30, 40}; 
    btnGrid.ColumnWidth = {'1x', '1x', '1x'}; 
    
    % Visual Mode (WF / SI) Radio Buttons
    bgVisualMode = uibuttongroup(btnGrid, 'BorderType', 'none');
    bgVisualMode.Layout.Row = 1; 
    bgVisualMode.Layout.Column = 3;
    
    uilabel(bgVisualMode, 'Text', 'Orientation:', 'Position', [0 4 70 22]);
    rbWF = uiradiobutton(bgVisualMode, 'Text', 'WF', 'Position', [70 4 45 22]);
    rbSI = uiradiobutton(bgVisualMode, 'Text', 'SI', 'Position', [115 4 45 22]);
    bgVisualMode.SelectionChangedFcn = @(~,~) visualModeChanged();
    
    % Action Buttons
    btnLoad = uibutton(btnGrid, 'Text', 'Load Image...', 'ButtonPushedFcn', @loadImageCallback);
    btnLoad.Layout.Row = 2; 
    btnLoad.Layout.Column = 1;
    
    btnDefWin = uibutton(btnGrid, 'Text', 'Define Window', 'Enable', 'off', 'ButtonPushedFcn', @defineWindowCallback);
    btnDefWin.Layout.Row = 2; 
    btnDefWin.Layout.Column = 2;
    
    btnDrawFOV = uibutton(btnGrid, 'Text', 'Draw FOV', 'Enable', 'off', 'ButtonPushedFcn', @drawFOVCallback);
    btnDrawFOV.Layout.Row = 2; 
    btnDrawFOV.Layout.Column = 3;
    
    %% --- RIGHT PANEL (TABS) ---
    tabGroup = uitabgroup(mainGrid);
    tabGroup.SelectionChangedFcn = @(~, evt) tabChangedCallback(evt.OldValue, evt.NewValue); 
    
    tabLBM = uitab(tabGroup, 'Title', 'LBM');
    tabMeso = uitab(tabGroup, 'Title', 'mesoscope');
    
    % Populate both tabs and save their control handles & graphics state
    ctrlsLBM = populateTab(tabLBM, 'LBM');
    ctrlsMeso = populateTab(tabMeso, 'mesoscope');
    
    %% --- HELPER FUNCTION FOR TABS ---
    function ctrls = populateTab(targetTab, tabName)
        ctrls.stripeHandles = gobjects(0);
        
        if strcmp(tabName, 'LBM')
            ctrls.pixelsPerLine = 144; 
        else
            ctrls.pixelsPerLine = 512; % Default for Meso
        end
        
        % Unified grid layout
        tGrid = uigridlayout(targetTab, [7 1]);
        tGrid.RowHeight = {50, 70, 70, 60, 40, '1x', 40}; 
        
        % 1. Text boxes side-by-side
        boxGrid = uigridlayout(tGrid, [2 2]);
        boxGrid.Padding = [0 0 0 0]; 
        boxGrid.RowHeight = {'fit', 'fit'};
        
        uilabel(boxGrid, 'Text', 'Resonant Freq (Hz):');
        uilabel(boxGrid, 'Text', 'Window Size (mm):');
        
        ctrls.edtResFreq = uieditfield(boxGrid, 'numeric', 'Value', 12033, 'ValueDisplayFormat', '%.0f'); 
        ctrls.edtResFreq.ValueChangedFcn = @(~, ~) updateLimitsAndDraw(); 
        
        ctrls.edtWinSize = uieditfield(boxGrid, 'numeric', 'Value', 5);
        ctrls.edtWinSize.ValueChangedFcn = @(s, e) sharedWinSizeChanged(e.Value); 
        
        % 2. Pixel Size (Slider + Edit Box)
        pixGrid = uigridlayout(tGrid, [2 2]);
        pixGrid.Padding = [0 0 0 0];
        pixGrid.RowHeight = {'fit', 'fit'};
        pixGrid.ColumnWidth = {'1x', 60};
        
        lblPix = uilabel(pixGrid, 'Text', 'Pixel Size (microns):');
        lblPix.Layout.Column = [1 2];
        
        maxPixSize = maxResonantAmplitude / ctrls.pixelsPerLine; 
        
        ctrls.sldPix = uislider(pixGrid, 'Limits', [0.1 maxPixSize], 'Value', 1.0); 
        ctrls.edtPix = uieditfield(pixGrid, 'numeric', 'Limits', [0.1 maxPixSize], 'Value', 1.0);
        formatSlider(ctrls.sldPix);
        
        ctrls.sldPix.ValueChangingFcn = @(s,e) pixelSizeChanging(ctrls.edtPix, e.Value);
        ctrls.edtPix.ValueChangedFcn = @(s,e) pixelSizeChanged(ctrls.sldPix, e.Value);
        
        % 3. Frame Rate (Slider + Edit Box)
        frameGrid = uigridlayout(tGrid, [2 2]);
        frameGrid.Padding = [0 0 0 0];
        frameGrid.RowHeight = {'fit', 'fit'};
        frameGrid.ColumnWidth = {'1x', 60};
        
        lblFrame = uilabel(frameGrid, 'Text', 'Frame Rate:');
        lblFrame.Layout.Column = [1 2];
        
        ctrls.sldFrame = uislider(frameGrid, 'Limits', [0.01 500], 'Value', 30);
        ctrls.edtFrame = uieditfield(frameGrid, 'numeric', 'Limits', [0.01 500], 'Value', 30, 'ValueDisplayFormat', '%.2f');
        formatSlider(ctrls.sldFrame);
        
        ctrls.sldFrame.ValueChangedFcn = @(s,e) frameRateChanged(ctrls.edtFrame, e.Value);
        ctrls.edtFrame.ValueChangedFcn = @(s,e) frameRateChanged(ctrls.sldFrame, e.Value);
        
        % 4. FOV Coverage Mode (Radio Buttons)
        ctrls.bgFOV = uibuttongroup(tGrid, 'Title', 'FOV Stripe Coverage');
        ctrls.bgFOV.SelectionChangedFcn = @(~,~) updateLimitsAndDraw();
        
        ctrls.optOptimal = uiradiobutton(ctrls.bgFOV, 'Text', 'Optimal', 'Position', [10 10 80 22]);
        ctrls.optRect = uiradiobutton(ctrls.bgFOV, 'Text', 'Rectangular', 'Position', [100 10 100 22]);
        
        % 5. Pixels Per Line Parameter
        dropGrid = uigridlayout(tGrid, [1 2]);
        dropGrid.Padding = [0 0 0 0];
        dropGrid.ColumnWidth = {'fit', '1x'};
        uilabel(dropGrid, 'Text', 'Pixels Per Line:');
        
        if strcmp(tabName, 'mesoscope')
            ctrls.ddPixels = uidropdown(dropGrid, 'Items', {'2048', '1024', '512', '256', '128', '64'}, 'Value', '512');
            ctrls.ddPixels.ValueChangedFcn = @(s,e) pixelsPerLineChangedMeso(e.Value);
        else
            uilabel(dropGrid, 'Text', num2str(ctrls.pixelsPerLine));
        end
        
        % 6. Export to ScanImage Button (Bottom Right)
        exportGrid = uigridlayout(tGrid, [1 2]);
        exportGrid.Padding = [0 0 0 0];
        exportGrid.Layout.Row = length(tGrid.RowHeight);
        exportGrid.Layout.Column = 1;
        exportGrid.ColumnWidth = {'1x', '1x'}; 
        
        ctrls.btnExport = uibutton(exportGrid, 'Text', 'Export to *.roi file...', 'ButtonPushedFcn', @exportROICallback);
        ctrls.btnExport.Layout.Column = 2; 
    end

    function sharedWinSizeChanged(val)
        ctrlsLBM.edtWinSize.Value = val;
        ctrlsMeso.edtWinSize.Value = val;
        updateAxesAndScale();
    end

    function pixelsPerLineChangedMeso(valStr)
        val = str2double(valStr);
        ctrlsMeso.pixelsPerLine = val;
        
        maxPixSize = maxResonantAmplitude / val;
        ctrlsMeso.sldPix.Limits = [0.1 maxPixSize];
        ctrlsMeso.edtPix.Limits = [0.1 maxPixSize];
        
        if ctrlsMeso.sldPix.Value > maxPixSize
            ctrlsMeso.sldPix.Value = maxPixSize;
            ctrlsMeso.edtPix.Value = maxPixSize;
        end
        formatSlider(ctrlsMeso.sldPix);
        updateLimitsAndDraw();
    end

    function state = getActiveState()
        if strcmp(tabGroup.SelectedTab.Title, 'LBM')
            state = ctrlsLBM;
        else
            state = ctrlsMeso;
        end
    end

    function pixelSizeChanging(targetCtrl, val)
        targetCtrl.Value = val;
        drawStripes(true); 
    end

    function pixelSizeChanged(targetCtrl, val)
        targetCtrl.Value = val;
        drawStripes(true); 
    end

    function frameRateChanged(targetCtrl, val)
        targetCtrl.Value = val;
        updatePixForFPS(val, true); 
    end

    function updatePixForFPS(targetFps, updateFPSControl)
        if isempty(fovROI) || ~isvalid(fovROI) || isempty(winROI) || ~isvalid(winROI)
            return;
        end
        
        state = getActiveState();
        fovMode = state.bgFOV.SelectedObject.Text;
        newPix = findPixelSizeForFPS(targetFps, fovMode, state);
        
        state.sldPix.Value = newPix;
        state.edtPix.Value = newPix;
        
        drawStripes(updateFPSControl);
    end

    %% --- SLIDER FORMATTING LOGIC ---
    function formatSlider(sld)
        t = linspace(sld.Limits(1), sld.Limits(2), 5);
        sld.MajorTicks = t;
        
        lbls = arrayfun(@(x) sprintf('%.1f', x), t, 'UniformOutput', false);
        lbls = regexprep(lbls, '\.0$', '');
        
        sld.MajorTickLabels = lbls;
    end

    %% --- SCANIMAGE EXPORT LOGIC ---
    function exportROICallback(~, ~)
        if isempty(winROI) || ~isvalid(winROI) || isempty(fovROI) || ~isvalid(fovROI)
            uialert(fig, 'Please define Window and FOV first before exporting.', 'Export Error');
            return;
        end
        
        state = getActiveState();
        validStripes = state.stripeHandles(isvalid(state.stripeHandles));
        if isempty(validStripes)
            uialert(fig, 'No stripes generated to export.', 'Export Error');
            return;
        end
        
        [file, path] = uiputfile('*.roi', 'Save ScanImage ROI file');
        if isequal(file, 0), return; end
        fullPath = fullfile(path, file);
        
        winSize_mm = max(0.001, state.edtWinSize.Value);
        radiusInPixels = winROI.Radius;
        centerPx = winROI.Center; 
        pixelsPerMM = (2 * radiusInPixels) / winSize_mm;
        micronsPerPx = 1000 / pixelsPerMM;
        
        pixelsX = state.pixelsPerLine;
        pixSize_um = state.edtPix.Value;
        
        numRois = length(validStripes);
        coordList = zeros(numRois, 6); 
        
        for idx = 1:numRois
            pos = validStripes(idx).Position; 
            cx_px = pos(1) + pos(3)/2;
            cy_px = pos(2) + pos(4)/2;
            
            dx_px = cx_px - centerPx(1);
            dy_px = cy_px - centerPx(2);
            
            physical_X_um = dy_px * micronsPerPx;
            physical_Y_um = -dx_px * micronsPerPx;
            
            sizeX_um = pos(4) * micronsPerPx;
            sizeY_um_raw = pos(3) * micronsPerPx;
            
            pixelsY = max(2, round((sizeY_um_raw / sizeX_um) * pixelsX));
            if mod(pixelsY, 2) ~= 0
                pixelsY = pixelsY + 1;
            end
            sizeY_um_adjusted = pixelsY * pixSize_um;
            
            coordList(idx, 1) = physical_X_um / objectiveResolution;
            coordList(idx, 2) = physical_Y_um / objectiveResolution;
            coordList(idx, 3) = sizeX_um / objectiveResolution;
            coordList(idx, 4) = sizeY_um_adjusted / objectiveResolution;
            coordList(idx, 5) = 0; 
            coordList(idx, 6) = pixelsY;
        end
        
        try
            hRoiGroup = scanimage.mroi.RoiGroup();
            
            for idx = 1:numRois
                centerX   = coordList(idx, 1);
                centerY   = coordList(idx, 2);
                sizeX     = coordList(idx, 3);
                sizeY     = coordList(idx, 4);
                zDepth    = coordList(idx, 5);
                pixelsY   = coordList(idx, 6);
                
                hSf = scanimage.mroi.scanfield.fields.RotatedRectangle();
                hSf.centerXY = [centerX, centerY];
                hSf.sizeXY = [sizeX, sizeY];
                hSf.rotationDegrees = 0;
                
                hSf.pixelResolutionXY = [pixelsX, pixelsY]; 
                
                hRoi = scanimage.mroi.Roi();
                hRoi.add(zDepth, hSf); 
                
                hRoiGroup.add(hRoi);
            end
            
            hRoiGroup.saveToFile(fullPath);
            uialert(fig, 'Export to ScanImage successful.', 'Success');
            
        catch ME
            uialert(fig, sprintf('Failed to generate or save ScanImage ROI.\nEnsure ScanImage is in the MATLAB path.\n\nError: %s', ME.message), 'Export Error');
        end
    end

    %% --- TAB SWITCHING CACHE LOGIC ---
    function tabChangedCallback(oldTab, newTab)
        if strcmp(oldTab.Title, 'LBM'), oldState = ctrlsLBM; else, oldState = ctrlsMeso; end
        if strcmp(newTab.Title, 'LBM'), newState = ctrlsLBM; else, newState = ctrlsMeso; end
        
        validStripesOld = oldState.stripeHandles(isvalid(oldState.stripeHandles));
        if ~isempty(validStripesOld), set(validStripesOld, 'Visible', 'off'); end
        
        validStripesNew = newState.stripeHandles(isvalid(newState.stripeHandles));
        if ~isempty(validStripesNew), set(validStripesNew, 'Visible', 'on'); end
        
        updateAxesAndScale();
    end
    
    %% --- VISUAL MODE ROTATION LOGIC ---
    function visualModeChanged()
        if strcmp(bgVisualMode.SelectedObject.Text, 'WF')
            camup(ax, [0 -1 0]); 
        else
            camup(ax, [1 0 0]); 
        end
        updateAxesAndScale(); 
    end

    %% --- CALLBACK FUNCTIONS ---
    function loadImageCallback(~, ~)
        [fileName, pathName] = uigetfile({'*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp', 'Image Files'}, 'Select an Image');
        if isequal(fileName, 0), return; end
        
        fullFilePath = fullfile(pathName, fileName);
        try
            img = imread(fullFilePath);
        catch
            uialert(fig, 'Could not read the selected image file.', 'Error');
            return;
        end
        
        % Open preprocessing figure before cropping
        tempFig = figure('Name', 'Pre-process & Crop Image', 'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', 'CloseRequestFcn', @(~,~) closeTempFig());
        tempAx = axes('Parent', tempFig, 'Position', [0.05 0.2 0.9 0.75]);
        imshow(img, 'Parent', tempAx);
        title(tempAx, 'Rotate or Flip the image if needed, then click "Proceed to Crop"');
        
        uicontrol('Parent', tempFig, 'Style', 'pushbutton', 'String', 'Rotate 90° CCW', ...
            'Units', 'normalized', 'Position', [0.05 0.05 0.2 0.1], ...
            'Callback', @(~,~) rotateImg());
        uicontrol('Parent', tempFig, 'Style', 'pushbutton', 'String', 'Flip Horizontally', ...
            'Units', 'normalized', 'Position', [0.275 0.05 0.2 0.1], ...
            'Callback', @(~,~) flipHImg());
        uicontrol('Parent', tempFig, 'Style', 'pushbutton', 'String', 'Flip Vertically', ...
            'Units', 'normalized', 'Position', [0.5 0.05 0.2 0.1], ...
            'Callback', @(~,~) flipVImg());
        uicontrol('Parent', tempFig, 'Style', 'pushbutton', 'String', 'Proceed to Crop', ...
            'Units', 'normalized', 'Position', [0.725 0.05 0.225 0.1], ...
            'Callback', @(~,~) cropImg());
            
        croppedImg = [];
        uiwait(tempFig);
        
        if isempty(croppedImg)
            return; % Escaped/Closed without cropping
        end
        
        imshow(croppedImg, 'Parent', ax);
        title(ax, fileName, 'Interpreter', 'none');
        
        % Set global state to un-hide the compass
        hasRealImage = true;
        
        if ~isempty(winROI) && isvalid(winROI), delete(winROI); end
        if ~isempty(fovROI) && isvalid(fovROI), delete(fovROI); end
        if ~isempty(scalebarLine) && isvalid(scalebarLine), delete(scalebarLine); end
        if ~isempty(scalebarText) && isvalid(scalebarText), delete(scalebarText); end
        if ~isempty(compassLines), delete(compassLines(isvalid(compassLines))); end
        if ~isempty(compassTexts), delete(compassTexts(isvalid(compassTexts))); end
        
        winROI = []; fovROI = []; scalebarLine = []; scalebarText = [];
        compassLines = gobjects(0); compassTexts = gobjects(0);
        
        validStripesLBM = ctrlsLBM.stripeHandles(isvalid(ctrlsLBM.stripeHandles));
        if ~isempty(validStripesLBM), delete(validStripesLBM); end
        ctrlsLBM.stripeHandles = gobjects(0);
        
        validStripesMeso = ctrlsMeso.stripeHandles(isvalid(ctrlsMeso.stripeHandles));
        if ~isempty(validStripesMeso), delete(validStripesMeso); end
        ctrlsMeso.stripeHandles = gobjects(0);
        
        btnDefWin.Text = 'Define Window';
        btnDefWin.Enable = 'on';
        btnDrawFOV.Text = 'Draw FOV';
        btnDrawFOV.Enable = 'off'; 
        rbWF.Value = true;
        camup(ax, [0 -1 0]); 
        
        ax.XTickLabel = []; ax.YTickLabel = []; xlabel(ax, ''); ylabel(ax, '');
        
        % Draw compass over freshly loaded image instantly
        updateAxesAndScale();
        
        % --- Pre-processing Tool Callbacks ---
        function rotateImg()
            img = rot90(img);
            imshow(img, 'Parent', tempAx);
            title(tempAx, 'Rotate or Flip the image if needed, then click "Proceed to Crop"');
        end
        function flipHImg()
            img = fliplr(img);
            imshow(img, 'Parent', tempAx);
            title(tempAx, 'Rotate or Flip the image if needed, then click "Proceed to Crop"');
        end
        function flipVImg()
            img = flipud(img);
            imshow(img, 'Parent', tempAx);
            title(tempAx, 'Rotate or Flip the image if needed, then click "Proceed to Crop"');
        end
        function cropImg()
            title(tempAx, 'Draw a rectangle and double-click inside it to confirm crop');
            croppedImg = imcrop(tempAx);
            if ishandle(tempFig)
                uiresume(tempFig);
                delete(tempFig);
            end
        end
        function closeTempFig()
            uiresume(tempFig);
            delete(tempFig);
        end
    end

    %% --- DEFINE WINDOW LOGIC ---
    function defineWindowCallback(~, ~)
        if strcmp(btnDefWin.Text, 'Define Window')
            btnDefWin.Text = 'Edit Window';
            if ~isempty(winROI) && isvalid(winROI), delete(winROI); end
            
            winROI = drawcircle(ax, 'Label', 'Window', 'FaceAlpha', 0.2);
            addlistener(winROI, 'MovingROI', @(~,~) updateAxesAndScale());
            addlistener(winROI, 'ROIClicked', @winROIClicked);
            
            updateAxesAndScale();
        else
            if ~isempty(winROI) && isvalid(winROI)
                winROI.InteractionsAllowed = 'all';
                winROI.FaceAlpha = 0.2;
                winROI.Label = 'Window';
                
                if ~isempty(scalebarLine) && isvalid(scalebarLine), delete(scalebarLine); end
                if ~isempty(scalebarText) && isvalid(scalebarText), delete(scalebarText); end
            else
                winROI = drawcircle(ax, 'Label', 'Window', 'FaceAlpha', 0.2);
                addlistener(winROI, 'MovingROI', @(~,~) updateAxesAndScale());
                addlistener(winROI, 'ROIClicked', @winROIClicked);
                
                updateAxesAndScale();
            end
        end
    end

    function winROIClicked(src, evt)
        if strcmp(evt.SelectionType, 'double')
            src.InteractionsAllowed = 'none';
            src.FaceAlpha = 0; 
            src.Label = '';    
            
            btnDrawFOV.Enable = 'on';
            updateAxesAndScale();
        end
    end

    %% --- DYNAMIC SCALING, COMPASS & AXES LOGIC ---
    function updateAxesAndScale()
        drawCompass();
        
        if isempty(winROI) || ~isvalid(winROI)
            ax.XTickLabel = []; ax.YTickLabel = []; xlabel(ax, ''); ylabel(ax, '');
            if ~isempty(scalebarLine) && isvalid(scalebarLine), delete(scalebarLine); end
            if ~isempty(scalebarText) && isvalid(scalebarText), delete(scalebarText); end
            return;
        end
        
        state = getActiveState();
        winSize_mm = max(0.001, state.edtWinSize.Value);
        
        radiusInPixels = winROI.Radius;
        centerPx = winROI.Center; 
        pixelsPerMM = (2 * radiusInPixels) / winSize_mm;
        
        axis(ax, 'on');
        
        xlims = ax.XLim;
        minX_mm = (xlims(1) - centerPx(1)) / pixelsPerMM;
        maxX_mm = (xlims(2) - centerPx(1)) / pixelsPerMM;
        
        tickStepX = 1;
        if (maxX_mm - minX_mm) <= 3.5, tickStepX = 0.5; end
        if (maxX_mm - minX_mm) <= 1.5, tickStepX = 0.2; end
        
        ticksX_mm = ceil(minX_mm/tickStepX)*tickStepX : tickStepX : floor(maxX_mm/tickStepX)*tickStepX;
        ax.XTick = centerPx(1) + ticksX_mm * pixelsPerMM;
        
        ylims = ax.YLim;
        minY_mm = (ylims(1) - centerPx(2)) / pixelsPerMM;
        maxY_mm = (ylims(2) - centerPx(2)) / pixelsPerMM;
        
        tickStepY = 1;
        if (maxY_mm - minY_mm) <= 3.5, tickStepY = 0.5; end
        if (maxY_mm - minY_mm) <= 1.5, tickStepY = 0.2; end
        
        ticksY_mm = ceil(minY_mm/tickStepY)*tickStepY : tickStepY : floor(maxY_mm/tickStepY)*tickStepY;
        ax.YTick = centerPx(2) + ticksY_mm * pixelsPerMM;
        
        ax.XTickLabel = [];
        ax.YTickLabel = [];
        xlabel(ax, '');
        ylabel(ax, '');
        
        drawScalebar(pixelsPerMM);
        
        updateLimitsAndDraw();
    end

    function drawScalebar(pixelsPerMM)
        xlims = ax.XLim; ylims = ax.YLim;
        offset = diff(xlims) * 0.05; 
        
        if ~isempty(scalebarLine) && isvalid(scalebarLine), delete(scalebarLine); end
        if ~isempty(scalebarText) && isvalid(scalebarText), delete(scalebarText); end
        
        if strcmp(bgVisualMode.SelectedObject.Text, 'WF')
            xEnd = xlims(2) - offset;
            xStart = xEnd - pixelsPerMM;
            yPos = ylims(2) - offset;
            
            scalebarLine = line(ax, [xStart, xEnd], [yPos, yPos], 'Color', 'w', 'LineWidth', 3);
            scalebarText = text(ax, mean([xStart, xEnd]), yPos - (offset/3), '1 mm', ...
                'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
        else
            xPos = xlims(1) + offset;
            yEnd = ylims(2) - offset;
            yStart = yEnd - pixelsPerMM;
            
            scalebarLine = line(ax, [xPos, xPos], [yStart, yEnd], 'Color', 'w', 'LineWidth', 3);
            scalebarText = text(ax, xPos - (offset/1.5), mean([yStart, yEnd]), '1 mm', ...
                'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
        end
    end

    function drawCompass()
        if ~hasRealImage
            if ~isempty(compassLines), delete(compassLines(isvalid(compassLines))); end
            if ~isempty(compassTexts), delete(compassTexts(isvalid(compassTexts))); end
            return;
        end
        
        if ~isempty(compassLines), delete(compassLines(isvalid(compassLines))); end
        if ~isempty(compassTexts), delete(compassTexts(isvalid(compassTexts))); end
        
        xlims = ax.XLim; 
        ylims = ax.YLim;
        
        span = diff(xlims) * 0.08; 
        r = span / 2;
        h = r * 0.3; 
        pad = r * 0.5; 
        
        if strcmp(bgVisualMode.SelectedObject.Text, 'WF')
            cx = xlims(1) + span;
            cy = ylims(1) + span;
            
            l1 = line(ax, [cx-r, cx+r], [cy, cy], 'Color', 'w', 'LineWidth', 2);
            l2 = line(ax, [cx, cx], [cy-r, cy+r], 'Color', 'w', 'LineWidth', 2);
            
            h1 = line(ax, [cx-r+h, cx-r, cx-r+h], [cy-h, cy, cy+h], 'Color', 'w', 'LineWidth', 2); 
            h2 = line(ax, [cx+r-h, cx+r, cx+r-h], [cy-h, cy, cy+h], 'Color', 'w', 'LineWidth', 2); 
            h3 = line(ax, [cx-h, cx, cx+h], [cy-r+h, cy-r, cy-r+h], 'Color', 'w', 'LineWidth', 2); 
            h4 = line(ax, [cx-h, cx, cx+h], [cy+r-h, cy+r, cy+r-h], 'Color', 'w', 'LineWidth', 2); 
            
            compassLines = [l1, l2, h1, h2, h3, h4];
            
            tA = text(ax, cx, cy - r - pad, 'A', 'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
            tP = text(ax, cx, cy + r + pad, 'P', 'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
            tM = text(ax, cx - r - pad, cy, 'M', 'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
            tL = text(ax, cx + r + pad, cy, 'L', 'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
            
            compassTexts = [tA, tP, tM, tL];
        else
            cx = xlims(2) - span;
            cy = ylims(1) + span;
            
            l1 = line(ax, [cx-r, cx+r], [cy, cy], 'Color', 'w', 'LineWidth', 2);
            l2 = line(ax, [cx, cx], [cy-r, cy+r], 'Color', 'w', 'LineWidth', 2);
            
            h1 = line(ax, [cx-r+h, cx-r, cx-r+h], [cy-h, cy, cy+h], 'Color', 'w', 'LineWidth', 2);
            h2 = line(ax, [cx+r-h, cx+r, cx+r-h], [cy-h, cy, cy+h], 'Color', 'w', 'LineWidth', 2);
            h3 = line(ax, [cx-h, cx, cx+h], [cy-r+h, cy-r, cy-r+h], 'Color', 'w', 'LineWidth', 2);
            h4 = line(ax, [cx-h, cx, cx+h], [cy+r-h, cy+r, cy+r-h], 'Color', 'w', 'LineWidth', 2);
            
            compassLines = [l1, l2, h1, h2, h3, h4];
            
            tA = text(ax, cx, cy - r - pad, 'A', 'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
            tL = text(ax, cx + r + pad, cy, 'L', 'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
            tP = text(ax, cx, cy + r + pad, 'P', 'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
            tM = text(ax, cx - r - pad, cy, 'M', 'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
            
            compassTexts = [tA, tL, tP, tM];
        end
    end

    %% --- DRAW FOV LOGIC ---
    function drawFOVCallback(~, ~)
        if strcmp(btnDrawFOV.Text, 'Draw FOV')
            createNewFOV();
        else
            choice = uiconfirm(fig, 'Do you want to edit the existing FOV or create a new one?', 'Edit FOV', ...
                'Options', {'Edit Existing', 'Create New', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 3);
            
            switch choice
                case 'Edit Existing'
                    if ~isempty(fovROI) && isvalid(fovROI)
                        fovROI.InteractionsAllowed = 'all';
                        fovROI.FaceAlpha = 0.2;
                        fovROI.Label = 'FOV';
                    else
                        createNewFOV(); 
                    end
                case 'Create New'
                    createNewFOV();
                case 'Cancel'
                    return;
            end
        end
    end

    function createNewFOV()
        shape = uiconfirm(fig, 'Select FOV Shape:', 'Draw FOV', ...
            'Options', {'Rectangular', 'Elliptic', 'Freehand', 'Cancel'}, ...
            'DefaultOption', 1, 'CancelOption', 4);
            
        if strcmp(shape, 'Cancel'), return; end
        
        if ~isempty(fovROI) && isvalid(fovROI), delete(fovROI); end
        clearStripes();
        
        switch shape
            case 'Rectangular'
                fovROI = drawrectangle(ax, 'Label', 'FOV', 'FaceAlpha', 0.2);
            case 'Elliptic'
                fovROI = drawellipse(ax, 'Label', 'FOV', 'FaceAlpha', 0.2);
            case 'Freehand'
                fovROI = drawfreehand(ax, 'Label', 'FOV', 'FaceAlpha', 0.2);
        end
        
        btnDrawFOV.Text = 'Edit FOV';
        
        if ~isempty(fovROI)
            addlistener(fovROI, 'MovingROI', @(~,~) updateLimitsAndDraw());
            addlistener(fovROI, 'ROIClicked', @fovROIClicked);
            
            updateLimitsAndDraw(); 
        end
    end

    function fovROIClicked(src, evt)
        if strcmp(evt.SelectionType, 'double')
            src.InteractionsAllowed = 'none';
            src.FaceAlpha = 0; 
            src.Label = ''; 
        end
    end

    %% --- STRIPE & FRAME RATE CORE LOGIC ---
    function clearStripes()
        state = getActiveState();
        validStripes = state.stripeHandles(isvalid(state.stripeHandles));
        if ~isempty(validStripes), delete(validStripes); end
        
        if strcmp(tabGroup.SelectedTab.Title, 'LBM')
            ctrlsLBM.stripeHandles = gobjects(0);
        else
            ctrlsMeso.stripeHandles = gobjects(0);
        end
    end

    function [rects_px, fps] = calculateStripesAndFPS(pixSize_um, fovMode, state)
        rects_px = [];
        fps = 0;
        
        if isempty(fovROI) || ~isvalid(fovROI) || isempty(winROI) || ~isvalid(winROI)
            return;
        end
        
        winSize_mm = max(0.001, state.edtWinSize.Value);
        resFreq_Hz = state.edtResFreq.Value;
        
        radiusInPixels = winROI.Radius;
        pixelsPerMM = (2 * radiusInPixels) / winSize_mm;
        
        stripe_height_um = pixSize_um * state.pixelsPerLine;
        stripe_height_mm = stripe_height_um / 1000;
        stripe_height_px = stripe_height_mm * pixelsPerMM;
        
        if stripe_height_px < 1
            return; 
        end
        
        if isprop(fovROI, 'Vertices')
            pts = fovROI.Vertices;
        elseif isprop(fovROI, 'Position')
            pts = fovROI.Position;
        else
            return;
        end
        
        xmin = min(pts(:,1)); xmax = max(pts(:,1));
        ymin = min(pts(:,2)); ymax = max(pts(:,2));
        w = xmax - xmin; h = ymax - ymin;
        numStripes = ceil(h / stripe_height_px);
        
        linesPerSecond = 2 * resFreq_Hz;
        linesPerMM = 1000 / pixSize_um;
        timePerMM_sec = linesPerMM / linesPerSecond;
        
        flytoTime_sec_raw = flytoTime / 1000;
        resonantPeriod_sec = 1 / resFreq_Hz;
        flytoPeriods = ceil(flytoTime_sec_raw / resonantPeriod_sec);
        flytoTime_sec = flytoPeriods * resonantPeriod_sec;
        
        totalScanTime_sec = 0;
        
        if strcmp(fovMode, 'Optimal')
            stepX = max(1, w/200); 
            stepY = min(max(1, h/200), stripe_height_px / 3); 
            
            [X, Y] = meshgrid(xmin : stepX : xmax, ymin : stepY : ymax);
            inPoly = inpolygon(X, Y, pts(:,1), pts(:,2));
        end
        
        rects_px = zeros(numStripes, 4);
        validCount = 0;
        
        for i = 0:(numStripes-1)
            sy = ymin + i * stripe_height_px;
            stripe_w = 0;
            stripe_xmin = xmin;
            
            if strcmp(fovMode, 'Optimal')
                y_mask = (Y >= sy) & (Y <= (sy + stripe_height_px));
                in_stripe = inPoly & y_mask;
                
                if any(in_stripe(:))
                    X_in = X(in_stripe);
                    stripe_xmin = min(X_in);
                    stripe_xmax = max(X_in);
                    stripe_w = max(1, stripe_xmax - stripe_xmin); 
                end
            else
                stripe_w = w;
            end
            
            if stripe_w > 0
                stripe_w_um = (stripe_w / pixelsPerMM) * 1000;
                pixels_w = ceil(stripe_w_um / pixSize_um);
                
                if mod(pixels_w, 2) ~= 0
                    pixels_w = pixels_w + 1;
                end
                
                adjusted_stripe_w_um = pixels_w * pixSize_um;
                adjusted_stripe_w = (adjusted_stripe_w_um / 1000) * pixelsPerMM;
                
                extra_w = adjusted_stripe_w - stripe_w;
                stripe_xmin = stripe_xmin - (extra_w / 2);
                stripe_w = adjusted_stripe_w;
                
                validCount = validCount + 1;
                rects_px(validCount, :) = [stripe_xmin, sy, stripe_w, stripe_height_px];
                
                stripeLength_mm = stripe_w / pixelsPerMM;
                stripeTime_sec = (stripeLength_mm * timePerMM_sec) + flytoTime_sec;
                totalScanTime_sec = totalScanTime_sec + stripeTime_sec;
            end
        end
        
        rects_px = rects_px(1:validCount, :); 
        
        if totalScanTime_sec > 0
            fps = 1 / totalScanTime_sec;
        end
    end

    function newP = findPixelSizeForFPS(target_fps, fovMode, state)
        maxP = maxResonantAmplitude / state.pixelsPerLine;
        minP = 0.1;
        
        [~, minFps] = calculateStripesAndFPS(minP, fovMode, state);
        if target_fps <= minFps
            newP = minP;
            return;
        end
        
        [~, maxFps] = calculateStripesAndFPS(maxP, fovMode, state);
        if target_fps >= maxFps
            newP = maxP;
            return;
        end
        
        for iter = 1:12
            midP = (minP + maxP) / 2;
            [~, currentFps] = calculateStripesAndFPS(midP, fovMode, state);
            
            if currentFps < target_fps
                minP = midP; 
            else
                maxP = midP; 
            end
        end
        newP = maxP; 
    end

    function updateLimitsAndDraw()
        if isempty(fovROI) || ~isvalid(fovROI) || isempty(winROI) || ~isvalid(winROI)
            return;
        end
        
        state = getActiveState();
        maxPixSize = maxResonantAmplitude / state.pixelsPerLine;
        [~, maxFps] = calculateStripesAndFPS(maxPixSize, state.bgFOV.SelectedObject.Text, state);
        
        if maxFps > 0
            newMax = max(state.sldFrame.Limits(1) + 0.1, ceil(maxFps * 1.05));
            state.sldFrame.Limits(2) = newMax;
            state.edtFrame.Limits(2) = newMax;
            formatSlider(state.sldFrame);
        end
        
        drawStripes(true);
    end

    function drawStripes(updateFPS)
        if nargin < 1
            updateFPS = true;
        end
        
        clearStripes();
        state = getActiveState();
        
        pixSize_um = state.edtPix.Value;
        fovMode = state.bgFOV.SelectedObject.Text;
        
        [rects, fps] = calculateStripesAndFPS(pixSize_um, fovMode, state);
        
        hold(ax, 'on');
        newStripes = gobjects(size(rects, 1), 1);
        for i = 1:size(rects, 1)
            newStripes(i) = rectangle(ax, 'Position', rects(i,:), ...
                'EdgeColor', 'yellow', 'FaceColor', 'none', ...
                'LineWidth', 1, 'HitTest', 'off', 'PickableParts', 'none');
        end
        hold(ax, 'off');
        
        if strcmp(tabGroup.SelectedTab.Title, 'LBM')
            ctrlsLBM.stripeHandles = newStripes;
        else
            ctrlsMeso.stripeHandles = newStripes;
        end
        
        if updateFPS && fps > 0
            clampedFps = min(max(fps, state.sldFrame.Limits(1)), state.sldFrame.Limits(2));
            state.sldFrame.Value = clampedFps;
            state.edtFrame.Value = clampedFps;
        end
    end
end