function BeamAnalysisApp(initialData, initialHwInfo, initialDesc)
    % BEAMANALYSISAPP Standalone GUI for analyzing DataRay sweep files.
    % Can be called directly from HardwareScannerApp or launched independently.

    % Main Figure 
    anaFig = uifigure('Name', 'Beam Analysis Module', 'Position', [50, 150, 1480, 700], ...
                      'WindowKeyPressFcn', @handleKeyPress);
    
    % Memory Structures & Caches
    bData = [];
    hwInfo = struct();
    desc = struct();
    mipImage = []; 
    filteredVol = []; 
    loaded_mipImage_Lin = []; % Holds background image when loading results without raw data
    
    % Global Exposure Correction Factors
    globalBg = 0;
    globalExpMax = 1;
    
    % Partitioned Foci State Variables (Raw vs Exposure Corrected)
    fociRawLin = struct('FrameIdx', {}, 'Z', {}, 'X', {}, 'Y', {}, 'Intensity', {}, 'C', {}, 'E', {}, 'IsManual', {}, 'Z_disp', {}, 'EnergyCurve', {});
    fociRawSq  = struct('FrameIdx', {}, 'Z', {}, 'X', {}, 'Y', {}, 'Intensity', {}, 'C', {}, 'E', {}, 'IsManual', {}, 'Z_disp', {}, 'EnergyCurve', {});
    fociExpLin = struct('FrameIdx', {}, 'Z', {}, 'X', {}, 'Y', {}, 'Intensity', {}, 'C', {}, 'E', {}, 'IsManual', {}, 'Z_disp', {}, 'EnergyCurve', {});
    fociExpSq  = struct('FrameIdx', {}, 'Z', {}, 'X', {}, 'Y', {}, 'Intensity', {}, 'C', {}, 'E', {}, 'IsManual', {}, 'Z_disp', {}, 'EnergyCurve', {});
    
    activeFociSource = 'Linear'; % 'Linear' or 'Squared'
    activeFocusIdx = []; % Tracks the currently selected focal point
    
    % Cached Sweep Metrics 
    cacheRawLin = struct('I', [], 'C', [], 'E', [], 'X', [], 'Y', [], 'IsMulti', []);
    cacheRawSq  = struct('I', [], 'C', [], 'E', [], 'X', [], 'Y', [], 'IsMulti', []);
    cacheExpLin = struct('I', [], 'C', [], 'E', [], 'X', [], 'Y', [], 'IsMulti', []);
    cacheExpSq  = struct('I', [], 'C', [], 'E', [], 'X', [], 'Y', [], 'IsMulti', []);
    
    Z_cache = [];
    xVec_cache = [];
    yVec_cache = [];
    
    if nargin >= 1 && ~isempty(initialData)
        bData = initialData;
        if nargin >= 2, hwInfo = initialHwInfo; end
        if nargin >= 3, desc = initialDesc; end
    end
    
    % ==========================================
    % UI Components: Left Panel (View & Navigation)
    % ==========================================
    
    lblFilename = uilabel(anaFig, 'Position', [50, 670, 500, 22], ...
        'Text', 'Loaded File: None', 'FontWeight', 'bold');
    
    axAna = uiaxes(anaFig, 'Position', [50, 210, 500, 460]);
    title(axAna, 'No Data Loaded');
    axis(axAna, 'image');
    colormap(axAna, 'jet');
    colorbar(axAna);
    
    chkExpCorr = uicheckbox(anaFig, 'Position', [50, 205, 150, 25], ...
        'Text', 'Exposure Correction', 'Enable', 'off', ...
        'ValueChangedFcn', @toggleExpCorr);
    
    chkFilter3D = uicheckbox(anaFig, 'Position', [50, 180, 130, 25], ...
        'Text', '3D Gaussian Filter', 'Enable', 'off', ...
        'ValueChangedFcn', @toggleFilter);
        
    lblSigmaXY = uilabel(anaFig, 'Position', [190, 180, 45, 25], 'Text', 'XY σ:');
    edtSigmaXY = uieditfield(anaFig, 'numeric', 'Position', [235, 180, 45, 25], ...
        'Value', 2, 'Limits', [0.1, 100], 'ValueDisplayFormat', '%.1f', ...
        'Enable', 'off', 'ValueChangedFcn', @changeSigma);
        
    lblSigmaZ = uilabel(anaFig, 'Position', [295, 180, 80, 25], 'Text', 'Z σ (frames):');
    edtSigmaZ = uieditfield(anaFig, 'numeric', 'Position', [375, 180, 45, 25], ...
        'Value', 2, 'Limits', [0.1, 100], 'ValueDisplayFormat', '%.1f', ...
        'Enable', 'off', 'ValueChangedFcn', @changeSigma);
        
    chkViewSquared = uicheckbox(anaFig, 'Position', [50, 150, 150, 25], ...
        'Text', 'View Intensity Squared', 'Enable', 'off', ...
        'ValueChangedFcn', @toggleViewSquared);

    chkMIP = uicheckbox(anaFig, 'Position', [205, 150, 115, 25], ...
        'Text', 'Max Projection', 'Enable', 'off', ...
        'ValueChangedFcn', @toggleMIP);
        
    chkLockAxes = uicheckbox(anaFig, 'Position', [325, 150, 80, 25], ...
        'Text', 'Lock Axes');
        
    chkLockZoom = uicheckbox(anaFig, 'Position', [410, 150, 85, 25], ...
        'Text', 'Lock Zoom');

    sldAna = uislider(anaFig, 'Position', [50, 120, 500, 3], 'Enable', 'off', ...
        'ValueChangingFcn', @(src, event) updateAnaPlot(round(event.Value)), ...
        'ValueChangedFcn', @(src, event) snapAnaSlider(event.Value));
        
    btnPrev10 = uibutton(anaFig, 'Position', [50, 60, 30, 25], 'Text', '<<', ...
        'Enable', 'off', 'ButtonPushedFcn', @(~,~) moveFrame(-10));
    btnPrev = uibutton(anaFig, 'Position', [85, 60, 30, 25], 'Text', '<', ...
        'Enable', 'off', 'ButtonPushedFcn', @(~,~) moveFrame(-1));
    btnNext = uibutton(anaFig, 'Position', [120, 60, 30, 25], 'Text', '>', ...
        'Enable', 'off', 'ButtonPushedFcn', @(~,~) moveFrame(1));
    btnNext10 = uibutton(anaFig, 'Position', [155, 60, 30, 25], 'Text', '>>', ...
        'Enable', 'off', 'ButtonPushedFcn', @(~,~) moveFrame(10));
    
    lblFrame = uilabel(anaFig, 'Position', [195, 60, 45, 25], 'Text', 'Frame:');
    edtFrame = uieditfield(anaFig, 'numeric', 'Position', [240, 60, 50, 25], ...
        'Value', 1, 'ValueDisplayFormat', '%.0f', 'Enable', 'off', ...
        'ValueChangedFcn', @jumpToFrame);
        
    lblPos = uilabel(anaFig, 'Position', [300, 60, 60, 25], 'Text', 'Pos (mm):');
    edtPos = uieditfield(anaFig, 'numeric', 'Position', [360, 60, 60, 25], ...
        'Value', 0, 'ValueDisplayFormat', '%.2f', 'Enable', 'off', ...
        'ValueChangedFcn', @jumpToPos);

    lblAnaCLim = uilabel(anaFig, 'Position', [50, 10, 80, 22], 'Text', 'Color Limits:');
    edtAnaCLimMin = uieditfield(anaFig, 'numeric', 'Position', [130, 10, 50, 22], ...
        'Value', 0, 'ValueDisplayFormat', '%.3f', 'ValueChangedFcn', @applyAnaCLim);
    edtAnaCLimMax = uieditfield(anaFig, 'numeric', 'Position', [190, 10, 50, 22], ...
        'Value', 65535, 'ValueDisplayFormat', '%.3f', 'ValueChangedFcn', @applyAnaCLim);
        
    btnAnalyzeFoci = uibutton(anaFig, 'Position', [260, 10, 145, 30], ...
        'Text', 'Analyze Focal Points', 'Enable', 'off', 'ButtonPushedFcn', @findFocalPoints);
        
    btnLoad = uibutton(anaFig, 'Position', [415, 10, 145, 30], ...
        'Text', 'Load Raw .mat', 'ButtonPushedFcn', @loadDiskData);

    % ==========================================
    % UI Components: Center/Right Panel (Analytics)
    % ==========================================
    
    bgPlotMode = uibuttongroup(anaFig, 'Position', [600, 655, 320, 35], ...
        'SelectionChangedFcn', @(~, ~) updateFociPlots());
    uiradiobutton(bgPlotMode, 'Position', [10, 7, 75, 22], 'Text', 'Peak Int.', 'Tag', 'Int');
    uiradiobutton(bgPlotMode, 'Position', [85, 7, 95, 22], 'Text', 'Compactness', 'Tag', 'Comp');
    uiradiobutton(bgPlotMode, 'Position', [180, 7, 70, 22], 'Text', 'Ellipticity', 'Tag', 'Ellip');
    uiradiobutton(bgPlotMode, 'Position', [250, 7, 70, 22], 'Text', '3D Cloud', 'Tag', '3D');

    axIntensityZ = uiaxes(anaFig, 'Position', [600, 375, 660, 275]);
    title(axIntensityZ, 'Z-Profile & Focal Planes');
    xlabel(axIntensityZ, 'Stage Position Z (mm)');
    ylabel(axIntensityZ, 'Peak Intensity');
    grid(axIntensityZ, 'on');
    
    axFociXY = uiaxes(anaFig, 'Position', [600, 60, 320, 280]);
    title(axFociXY, 'XY Focal Mapping (Cropped)');
    xlabel(axFociXY, 'X (\mum)');
    ylabel(axFociXY, 'Y (\mum)');
    axis(axFociXY, 'image');
    colormap(axFociXY, 'jet');
    colorbar(axFociXY);
    
    bgThirdPlotMode = uibuttongroup(anaFig, 'Position', [940, 345, 225, 25], ...
        'SelectionChangedFcn', @(~, ~) updateThirdPlot());
    uiradiobutton(bgThirdPlotMode, 'Position', [5, 2, 60, 22], 'Text', 'Energy', 'Tag', 'E');
    uiradiobutton(bgThirdPlotMode, 'Position', [65, 2, 50, 22], 'Text', 'X-Pos', 'Tag', 'X');
    uiradiobutton(bgThirdPlotMode, 'Position', [115, 2, 50, 22], 'Text', 'Y-Pos', 'Tag', 'Y');
    uiradiobutton(bgThirdPlotMode, 'Position', [165, 2, 50, 22], 'Text', 'Z-Pos', 'Tag', 'Z');
    
    chkDiffPos = uicheckbox(anaFig, 'Position', [1175, 345, 90, 25], ...
        'Text', ['Show ', char(916)], 'Enable', 'off', ...
        'ValueChangedFcn', @(~, ~) updateThirdPlot());
    
    axThirdPlot = uiaxes(anaFig, 'Position', [940, 60, 320, 280]);
    title(axThirdPlot, 'Energy Integral (50\mum Dia)');
    xlabel(axThirdPlot, '\Delta Z from Focus (mm)');
    ylabel(axThirdPlot, 'Normalized Energy');
    grid(axThirdPlot, 'on');
    
    btnSaveResults = uibutton(anaFig, 'Position', [940, 15, 155, 30], ...
        'Text', 'Save Results', 'Enable', 'off', 'ButtonPushedFcn', @saveAnalyticsResults);
    btnLoadResults = uibutton(anaFig, 'Position', [1105, 15, 155, 30], ...
        'Text', 'Load Results', 'ButtonPushedFcn', @loadAnalyticsResults);

    % ==========================================
    % UI Components: Far Right Panel (Listbox)
    % ==========================================
    
    lblFociSource = uilabel(anaFig, 'Position', [1280, 665, 180, 22], ...
        'Text', 'Analysis Source:', 'FontWeight', 'bold');
    bgFociSource = uibuttongroup(anaFig, 'Position', [1280, 635, 180, 30], ...
        'SelectionChangedFcn', @switchFociSource);
    uiradiobutton(bgFociSource, 'Position', [10, 5, 80, 22], 'Text', 'Linear', 'Tag', 'Linear');
    uiradiobutton(bgFociSource, 'Position', [90, 5, 80, 22], 'Text', 'Squared', 'Tag', 'Squared');
    
    lblFociList = uilabel(anaFig, 'Position', [1280, 610, 180, 22], ...
        'Text', 'Detected Foci:', 'FontWeight', 'bold');
    lstFoci = uilistbox(anaFig, 'Position', [1280, 135, 180, 470], ...
        'ValueChangedFcn', @(src, evt) listboxSelectionChanged(src));
    
    btnAddFocus = uibutton(anaFig, 'Position', [1280, 95, 180, 30], ...
        'Text', 'Add Current Frame', 'ButtonPushedFcn', @addCurrentFocus, 'Enable', 'off');
    btnMoveFocus = uibutton(anaFig, 'Position', [1280, 55, 180, 30], ...
        'Text', 'Move Focus to Current', 'ButtonPushedFcn', @moveFocusToCurrent, 'Enable', 'off');
    btnRemoveFocus = uibutton(anaFig, 'Position', [1280, 15, 180, 30], ...
        'Text', 'Remove Selected Focus', 'ButtonPushedFcn', @removeFocus, 'Enable', 'off');

    % Bind initial click handlers
    axIntensityZ.ButtonDownFcn = @(src, evt) handlePlotClick(evt, 'Z');
    axFociXY.ButtonDownFcn = @(src, evt) handlePlotClick(evt, 'XY');

    % Initialize UI if data was injected directly from memory
    if ~isempty(bData)
        lblFilename.Text = 'Loaded File: Unsaved Session (From Hardware Scanner App)';
        setupAnalysisUI();
    end
    
    % ==========================================
    % Callbacks & Logic
    % ==========================================

    function ext = extractExpTime(idx)
        ext = 1;
        if isempty(bData) || idx < 1 || idx > length(bData), return; end
        setts = bData(idx).Settings;
        if isfield(setts, 'i_exposure_time_us')
            ext = double(setts.i_exposure_time_us);
        elseif isfield(setts, 'd_exposure_time_ms')
            ext = double(setts.d_exposure_time_ms) * 1000;
        elseif isfield(setts, 'f_exposure_ms')
            ext = double(setts.f_exposure_ms) * 1000;
        else
            fn = fieldnames(setts);
            for k=1:length(fn)
                if contains(lower(fn{k}), 'exposure')
                    ext = double(setts.(fn{k}));
                    break;
                end
            end
        end
        if ext <= 0, ext = 1; end
    end

    function initExposureFactors()
        if isempty(bData), return; end
        
        % 1. Global background floor (same value across all frames)
        gBg = single(inf);
        for k = 1:length(bData)
            gBg = min(gBg, min(single(bData(k).Frame(:))));
        end
        globalBg = gBg;
        
        % 2. Global exposure max across dataset
        gMax = single(-inf);
        for k = 1:length(bData)
            img = single(bData(k).Frame) - globalBg;
            img(img < 0) = 0; % Clip negatives to 0 via float subtraction
            img = img / extractExpTime(k);
            gMax = max(gMax, max(img(:)));
        end
        if gMax <= 0, gMax = 1; end
        globalExpMax = gMax;
    end

    function img = fetchBaseFrame(idx, applyExp)
        % Core function enforcing baseline exposure math order
        img = single(bData(idx).Frame);
        if applyExp
            img = img - globalBg;
            img(img < 0) = 0;
            img = (img / extractExpTime(idx)) / globalExpMax;
        end
    end
    
    function [fd, c] = getActiveData()
        if chkExpCorr.Value
            if strcmp(activeFociSource, 'Linear')
                fd = fociExpLin; c = cacheExpLin;
            else
                fd = fociExpSq;  c = cacheExpSq;
            end
        else
            if strcmp(activeFociSource, 'Linear')
                fd = fociRawLin; c = cacheRawLin;
            else
                fd = fociRawSq;  c = cacheRawSq;
            end
        end
    end
    
    function saveActiveData(fd)
        if chkExpCorr.Value
            if strcmp(activeFociSource, 'Linear')
                fociExpLin = fd;
            else
                fociExpSq = fd;
            end
        else
            if strcmp(activeFociSource, 'Linear')
                fociRawLin = fd;
            else
                fociRawSq = fd;
            end
        end
    end

    function toggleExpCorr(~, ~)
        if isempty(bData), return; end
        
        % Auto adjust CLim Max when switching
        edtAnaCLimMin.Value = 0;
        if chkExpCorr.Value
            edtAnaCLimMax.Value = 1; % 1^2 is still 1 for squared mode
        else
            if chkViewSquared.Value
                edtAnaCLimMax.Value = 65535^2;
            else
                edtAnaCLimMax.Value = 65535;
            end
        end
        applyAnaCLim();
        
        filteredVol = [];
        mipImage = [];
        if chkFilter3D.Value, apply3DFilter(); end
        
        activeFocusIdx = [];
        updateFociPlots();
        updateAnaPlot(round(sldAna.Value));
    end

    function switchFociSource(~, event)
        activeFociSource = event.NewValue.Tag;
        activeFocusIdx = []; 
        updateFociPlots();
        updateAnaPlot(round(sldAna.Value));
    end

    function listboxSelectionChanged(src)
        val = src.Value;
        if isnumeric(val) && ~isempty(val)
            jumpToFocus(val);
        end
    end
    
    function [X, Y, I, C, E, isMulti] = computeMetricsCore(img, xVec, yVec)
        w = size(img, 2); h = size(img, 1);
        maxVal = max(img(:));
        I = maxVal;
        
        [~, maxLinIdx] = max(img(:));
        [r, c] = ind2sub([h, w], maxLinIdx);
        
        % Check for secondary beam interference
        hwMask = 25; 
        r1M = max(1, r-hwMask); r2M = min(h, r+hwMask);
        c1M = max(1, c-hwMask); c2M = min(w, c+hwMask);
        maskedImg = img;
        maskedImg(r1M:r2M, c1M:c2M) = 0;
        isMulti = max(maskedImg(:)) > 0.6 * maxVal;
        
        hw = 15; 
        r1 = max(1, r-hw); r2 = min(h, r+hw);
        c1 = max(1, c-hw); c2 = min(w, c+hw);
        patch = img(r1:r2, c1:c2);
        bg = min(patch(:)); 
        patch = patch - bg;
        mass = sum(patch(:));
        
        if mass <= 0
            C = NaN; E = NaN; X = NaN; Y = NaN;
        else
            [Xg, Yg] = meshgrid(c1:c2, r1:r2);
            Xg_flat = Xg(:); Yg_flat = Yg(:); patch_flat = patch(:);
            
            c_com = sum(Xg_flat .* patch_flat) / mass;
            r_com = sum(Yg_flat .* patch_flat) / mass;
            
            X = interp1(1:w, xVec, c_com);
            Y = interp1(1:h, yVec, r_com);
            
            x_diff = Xg_flat - c_com;
            y_diff = Yg_flat - r_com;
            mu20 = sum((x_diff.^2) .* patch_flat) / mass;
            mu02 = sum((y_diff.^2) .* patch_flat) / mass;
            mu11 = sum((x_diff .* y_diff) .* patch_flat) / mass;
            
            trace_val = mu20 + mu02;
            diff_term = sqrt((mu20 - mu02)^2 + 4*mu11^2);
            lambda1 = 0.5 * (trace_val + diff_term);
            lambda2 = 0.5 * (trace_val - diff_term);
            
            if lambda2 <= 0
                C = NaN; E = NaN;
            else
                E = sqrt(lambda1 / lambda2);
                C = lambda1 + lambda2;
            end
        end
    end
    
    function buildAnalyticsCache(showDialog)
        if ~isempty(cacheRawLin.I) && length(cacheRawLin.I) == length(bData)
            return; 
        end
        if isempty(bData), return; end
        
        N = length(bData);
        Z_cache = [bData.Position];
        
        cacheRawLin = struct('I', zeros(1,N), 'C', zeros(1,N), 'E', zeros(1,N), 'X', zeros(1,N), 'Y', zeros(1,N), 'IsMulti', false(1,N));
        cacheRawSq  = struct('I', zeros(1,N), 'C', zeros(1,N), 'E', zeros(1,N), 'X', zeros(1,N), 'Y', zeros(1,N), 'IsMulti', false(1,N));
        cacheExpLin = struct('I', zeros(1,N), 'C', zeros(1,N), 'E', zeros(1,N), 'X', zeros(1,N), 'Y', zeros(1,N), 'IsMulti', false(1,N));
        cacheExpSq  = struct('I', zeros(1,N), 'C', zeros(1,N), 'E', zeros(1,N), 'X', zeros(1,N), 'Y', zeros(1,N), 'IsMulti', false(1,N));
        
        setts = bData(1).Settings;
        pxSize = setts.d_x_pixel_size_um;
        bin = double(setts.i_binning);
        w = double(setts.i_width);
        h = double(setts.i_height);
        effPx = pxSize * bin;
        xVec_cache = linspace(-w/2, w/2, w) * effPx;
        yVec_cache = linspace(-h/2, h/2, h) * effPx;
        
        d = [];
        if showDialog
            d = uiprogressdlg(anaFig, 'Title', 'Computing Metrics', ...
                'Message', 'Extracting beam parameters across all analytical pipelines...');
        end
        
        for idx = 1:N
            % --- RAW PIPELINE ---
            imgRawRaw = fetchBaseFrame(idx, false);
            imgRawLin = imgaussfilt(imgRawRaw, 0.5);
            imgRawSq = imgRawLin.^2;
            
            if max(imgRawLin(:)) < 100
                cacheRawLin.I(idx) = max(imgRawLin(:));
                cacheRawLin.C(idx) = NaN; cacheRawLin.E(idx) = NaN;
                cacheRawLin.X(idx) = NaN; cacheRawLin.Y(idx) = NaN; cacheRawLin.IsMulti(idx) = false;
            else
                [X, Y, I, C, E, isM] = computeMetricsCore(imgRawLin, xVec_cache, yVec_cache);
                cacheRawLin.X(idx) = X; cacheRawLin.Y(idx) = Y; cacheRawLin.I(idx) = I;
                cacheRawLin.C(idx) = C; cacheRawLin.E(idx) = E; cacheRawLin.IsMulti(idx) = isM;
            end
            
            if max(imgRawSq(:)) < 10000
                cacheRawSq.I(idx) = max(imgRawSq(:));
                cacheRawSq.C(idx) = NaN; cacheRawSq.E(idx) = NaN;
                cacheRawSq.X(idx) = NaN; cacheRawSq.Y(idx) = NaN; cacheRawSq.IsMulti(idx) = false;
            else
                [X, Y, I, C, E, isM] = computeMetricsCore(imgRawSq, xVec_cache, yVec_cache);
                cacheRawSq.X(idx) = X; cacheRawSq.Y(idx) = Y; cacheRawSq.I(idx) = I;
                cacheRawSq.C(idx) = C; cacheRawSq.E(idx) = E; cacheRawSq.IsMulti(idx) = isM;
            end
            
            % --- EXPOSURE CORRECTED PIPELINE ---
            imgExpRaw = fetchBaseFrame(idx, true);
            imgExpLin = imgaussfilt(imgExpRaw, 0.5);
            imgExpSq = imgExpLin.^2;
            
            if max(imgExpLin(:)) < 0.01 % Scaled threshold for normalized [0,1] space
                cacheExpLin.I(idx) = max(imgExpLin(:));
                cacheExpLin.C(idx) = NaN; cacheExpLin.E(idx) = NaN;
                cacheExpLin.X(idx) = NaN; cacheExpLin.Y(idx) = NaN; cacheExpLin.IsMulti(idx) = false;
            else
                [X, Y, I, C, E, isM] = computeMetricsCore(imgExpLin, xVec_cache, yVec_cache);
                cacheExpLin.X(idx) = X; cacheExpLin.Y(idx) = Y; cacheExpLin.I(idx) = I;
                cacheExpLin.C(idx) = C; cacheExpLin.E(idx) = E; cacheExpLin.IsMulti(idx) = isM;
            end
            
            if max(imgExpSq(:)) < 0.0001
                cacheExpSq.I(idx) = max(imgExpSq(:));
                cacheExpSq.C(idx) = NaN; cacheExpSq.E(idx) = NaN;
                cacheExpSq.X(idx) = NaN; cacheExpSq.Y(idx) = NaN; cacheExpSq.IsMulti(idx) = false;
            else
                [X, Y, I, C, E, isM] = computeMetricsCore(imgExpSq, xVec_cache, yVec_cache);
                cacheExpSq.X(idx) = X; cacheExpSq.Y(idx) = Y; cacheExpSq.I(idx) = I;
                cacheExpSq.C(idx) = C; cacheExpSq.E(idx) = E; cacheExpSq.IsMulti(idx) = isM;
            end
            
            if ~isempty(d), d.Value = idx / N; end
        end
        if ~isempty(d), close(d); end
        
        btnSaveResults.Enable = 'on';
    end

    function mip = computeLinearMIP()
        if isempty(bData), mip = []; return; end
        if chkFilter3D.Value && ~isempty(filteredVol)
            mip = max(filteredVol, [], 3);
        else
            mip = fetchBaseFrame(1, chkExpCorr.Value);
            for k = 2:length(bData)
                tmp = fetchBaseFrame(k, chkExpCorr.Value);
                mip = max(mip, tmp);
            end
        end
    end

    function saveAnalyticsResults(~, ~)
        [f, p] = uiputfile('AnalysisResults.mat', 'Save Results');
        if ischar(f)
            res = struct();
            res.fociRawLin = fociRawLin;
            res.fociRawSq = fociRawSq;
            res.fociExpLin = fociExpLin;
            res.fociExpSq = fociExpSq;
            
            res.cacheRawLin = cacheRawLin;
            res.cacheRawSq = cacheRawSq;
            res.cacheExpLin = cacheExpLin;
            res.cacheExpSq = cacheExpSq;
            
            res.Z_cache = Z_cache;
            res.xVec_cache = xVec_cache;
            res.yVec_cache = yVec_cache;
            res.activeFociSource = activeFociSource;
            res.originalFile = lblFilename.Text;
            res.mipImage_Lin = computeLinearMIP();
            
            save(fullfile(p, f), 'res');
            uialert(anaFig, 'Analysis results successfully saved.', 'Saved');
        end
    end

    function loadAnalyticsResults(~, ~)
        hasRaw = ~isempty(bData);
        keepRaw = false;
        if hasRaw
            sel = uiconfirm(anaFig, 'Raw sweep data is currently loaded. Do you want to keep it or discard it?', ...
                'Keep Raw Data?', 'Options', {'Keep Raw Data', 'Discard Raw Data'}, 'DefaultOption', 1);
            keepRaw = strcmp(sel, 'Keep Raw Data');
        end

        [f, p] = uigetfile('*.mat', 'Select Analysis Results');
        if ischar(f)
            try
                loadedData = load(fullfile(p, f));
                if isfield(loadedData, 'res')
                    res = loadedData.res;
                    
                    if ~keepRaw
                        bData = []; % Dump raw data
                    end
                    
                    fociRawLin = res.fociRawLin;
                    fociRawSq = res.fociRawSq;
                    fociExpLin = res.fociExpLin;
                    fociExpSq = res.fociExpSq;
                    
                    cacheRawLin = res.cacheRawLin;
                    cacheRawSq = res.cacheRawSq;
                    cacheExpLin = res.cacheExpLin;
                    cacheExpSq = res.cacheExpSq;
                    
                    Z_cache = res.Z_cache;
                    xVec_cache = res.xVec_cache;
                    yVec_cache = res.yVec_cache;
                    activeFociSource = res.activeFociSource;
                    lblFilename.Text = res.originalFile;
                    loaded_mipImage_Lin = res.mipImage_Lin;
                    
                    if isempty(bData)
                        sldAna.Enable = 'off'; btnPrev10.Enable = 'off'; btnPrev.Enable = 'off';
                        btnNext.Enable = 'off'; btnNext10.Enable = 'off'; edtFrame.Enable = 'off';
                        edtPos.Enable = 'off'; chkMIP.Enable = 'off'; chkFilter3D.Enable = 'off'; chkExpCorr.Enable = 'off';
                        edtSigmaXY.Enable = 'off'; edtSigmaZ.Enable = 'off'; btnAnalyzeFoci.Enable = 'off';
                        btnAddFocus.Enable = 'off'; btnMoveFocus.Enable = 'off';
                        
                        cla(axAna); title(axAna, 'No Raw Data Available (Results Mode)');
                    else
                        setupAnalysisUI(false); 
                    end
                    
                    if strcmp(activeFociSource, 'Linear')
                        bgFociSource.SelectedObject = bgFociSource.Children(2);
                    else
                        bgFociSource.SelectedObject = bgFociSource.Children(1);
                    end
                    
                    activeFocusIdx = [];
                    updateFociPlots();
                    
                    msg = 'Analytics loaded.';
                    if isempty(bData)
                        msg = [msg ' The inspection viewport is disabled as raw data is not present.'];
                    end
                    uialert(anaFig, msg, 'Loaded');
                else
                    uialert(anaFig, 'Invalid results file format.', 'Load Error');
                end
            catch ME
                uialert(anaFig, sprintf('Error loading file: %s', ME.message), 'Load Error');
            end
        end
    end

    function [z_disp_sorted, e_curve_sorted] = calculateEnergyCurve(fZ, fIdx, isSq, c)
        valid_frames = find(abs(Z_cache - fZ) <= 4.0);
        z_disp_raw = Z_cache(valid_frames) - fZ;
        e_curve_raw = zeros(size(valid_frames));
        
        for k = 1:length(valid_frames)
            frIdx = valid_frames(k);
            cX = c.X(frIdx);
            cY = c.Y(frIdx);
            
            if isnan(cX) || isnan(cY)
                e_curve_raw(k) = 0; continue;
            end
            
            x_idx = find(abs(xVec_cache - cX) <= 30);
            y_idx = find(abs(yVec_cache - cY) <= 30);
            
            if isempty(x_idx) || isempty(y_idx)
                e_curve_raw(k) = 0; continue;
            end
            
            x_sub = xVec_cache(x_idx);
            y_sub = yVec_cache(y_idx);
            [Xg, Yg] = meshgrid(x_sub, y_sub);
            mask = (Xg - cX).^2 + (Yg - cY).^2 <= 25^2;
            
            img = fetchBaseFrame(frIdx, chkExpCorr.Value);
            img = imgaussfilt(img, 0.5);
            if isSq, img = img.^2; end
            
            patch = img(y_idx, x_idx);
            e_curve_raw(k) = sum(patch(mask));
        end
        
        idx0 = find(valid_frames == fIdx, 1);
        if ~isempty(idx0) && e_curve_raw(idx0) > 0
            e_curve_raw = e_curve_raw / e_curve_raw(idx0);
        elseif max(e_curve_raw) > 0
            e_curve_raw = e_curve_raw / max(e_curve_raw);
        end
        
        [z_disp_sorted, sortIdx] = sort(z_disp_raw);
        e_curve_sorted = e_curve_raw(sortIdx);
    end

    function addCurrentFocus(~, ~)
        if isempty(bData), return; end
        buildAnalyticsCache(true);
        [fd, c] = getActiveData();
        
        idx = round(sldAna.Value);
        if isnan(c.C(idx)) || isnan(c.E(idx))
            uialert(anaFig, 'Frame signal too weak or undefined to add as focus.', 'Invalid Frame');
            return;
        end
        
        isSq = strcmp(activeFociSource, 'Squared');
        [zd, ec] = calculateEnergyCurve(Z_cache(idx), idx, isSq, c);
        
        newFocus = struct('FrameIdx', idx, 'Z', Z_cache(idx), ...
            'X', c.X(idx), 'Y', c.Y(idx), ...
            'Intensity', c.I(idx), 'C', c.C(idx), 'E', c.E(idx), ...
            'IsManual', true, 'Z_disp', zd, 'EnergyCurve', ec);
            
        if isempty(fd)
            fd = newFocus;
        else
            existingIdx = find([fd.FrameIdx] == idx, 1);
            if ~isempty(existingIdx)
                fd(existingIdx) = newFocus;
            else
                fd(end+1) = newFocus;
            end
        end
        
        % Sort by strict FrameIdx (left-to-right slider order)
        [~, sortIdx] = sort([fd.FrameIdx]);
        fd = fd(sortIdx);
        
        activeFocusIdx = find([fd.FrameIdx] == idx, 1);
        saveActiveData(fd);
        updateFociPlots();
        updateAnaPlot(idx);
    end
    
    function moveFocusToCurrent(~, ~)
        if isempty(bData) || isempty(activeFocusIdx)
            return;
        end
        [fd, c] = getActiveData();
        if activeFocusIdx < 1 || activeFocusIdx > length(fd), return; end
        
        buildAnalyticsCache(true);
        idx = round(sldAna.Value);
        
        if isnan(c.C(idx)) || isnan(c.E(idx))
            uialert(anaFig, 'Target frame signal too weak or undefined.', 'Invalid Frame');
            return;
        end
        
        existingIdx = find([fd.FrameIdx] == idx);
        existingIdx = existingIdx(existingIdx ~= activeFocusIdx); 
        
        if ~isempty(existingIdx)
            fd(existingIdx(1)).IsManual = true;
            fd(activeFocusIdx) = [];
        else
            isSq = strcmp(activeFociSource, 'Squared');
            [zd, ec] = calculateEnergyCurve(Z_cache(idx), idx, isSq, c);
            
            fd(activeFocusIdx).FrameIdx = idx;
            fd(activeFocusIdx).Z = Z_cache(idx);
            fd(activeFocusIdx).X = c.X(idx);
            fd(activeFocusIdx).Y = c.Y(idx);
            fd(activeFocusIdx).Intensity = c.I(idx);
            fd(activeFocusIdx).C = c.C(idx);
            fd(activeFocusIdx).E = c.E(idx);
            fd(activeFocusIdx).IsManual = true; 
            fd(activeFocusIdx).Z_disp = zd;
            fd(activeFocusIdx).EnergyCurve = ec;
        end
        
        [~, sortIdx] = sort([fd.FrameIdx]);
        fd = fd(sortIdx);
        activeFocusIdx = find([fd.FrameIdx] == idx, 1);
        
        saveActiveData(fd);
        updateFociPlots();
        updateAnaPlot(idx);
    end
    
    function updatedFoci = performFocalDetection(currentFoci, c, I_threshold, isSq)
        N = length(c.I);
        prominenceThresh = max(c.I) * 0.05;
        isPeak = islocalmax(c.I, 'MinProminence', prominenceThresh);
        peakIndicesRaw = find(isPeak & c.I > I_threshold); 
        
        if ~isempty(currentFoci)
            manualFoci = currentFoci([currentFoci.IsManual]);
        else
            manualFoci = struct('FrameIdx', {}, 'Z', {}, 'X', {}, 'Y', {}, 'Intensity', {}, 'C', {}, 'E', {}, 'IsManual', {}, 'Z_disp', {}, 'EnergyCurve', {});
        end
        
        tempAutoFoci = struct('FrameIdx', {}, 'Z', {}, 'X', {}, 'Y', {}, 'Intensity', {}, 'C', {}, 'E', {}, 'IsManual', {}, 'Z_disp', {}, 'EnergyCurve', {});
        
        for k = 1:length(peakIndicesRaw)
            P = peakIndicesRaw(k);
            idx_range = max(1, P-3) : min(N, P+3);
            
            best_score = -1;
            best_frame_data = [];
            
            for i = 1:length(idx_range)
                idx = idx_range(i);
                
                if isnan(c.C(idx)) || c.IsMulti(idx)
                    continue;
                end
                
                I = c.I(idx);
                C = c.C(idx);
                E = c.E(idx);
                
                if E > max(4.0, 40 / C), continue; end
                
                S = (I^2) / ( (C^3) * (E^0.1) );
                
                if S > best_score
                    best_score = S;
                    best_frame_data = struct('FrameIdx', idx, 'Z', Z_cache(idx), ...
                        'X', c.X(idx), 'Y', c.Y(idx), ...
                        'Intensity', I, 'C', C, 'E', E, 'IsManual', false, 'Z_disp', [], 'EnergyCurve', []);
                end
            end
            
            if ~isempty(best_frame_data)
                if isempty(tempAutoFoci) || ~any([tempAutoFoci.FrameIdx] == best_frame_data.FrameIdx)
                    tempAutoFoci(end+1) = best_frame_data;
                end
            end
        end
        
        keptAutoFoci = struct('FrameIdx', {}, 'Z', {}, 'X', {}, 'Y', {}, 'Intensity', {}, 'C', {}, 'E', {}, 'IsManual', {}, 'Z_disp', {}, 'EnergyCurve', {});
        if ~isempty(tempAutoFoci)
            [~, sortIdx] = sort([tempAutoFoci.Intensity], 'descend');
            tempAutoFoci = tempAutoFoci(sortIdx);
            
            for i = 1:length(tempAutoFoci)
                cand = tempAutoFoci(i);
                if ~isempty(manualFoci) && any(abs([manualFoci.Z] - cand.Z) <= 1.5)
                    continue;
                end
                if ~isempty(keptAutoFoci) && any(abs([keptAutoFoci.Z] - cand.Z) <= 1.5)
                    continue;
                end
                keptAutoFoci(end+1) = cand;
            end
        end
        
        for i = 1:length(keptAutoFoci)
            [zd, ec] = calculateEnergyCurve(keptAutoFoci(i).Z, keptAutoFoci(i).FrameIdx, isSq, c);
            keptAutoFoci(i).Z_disp = zd;
            keptAutoFoci(i).EnergyCurve = ec;
        end
        
        updatedFoci = [manualFoci, keptAutoFoci];
        if ~isempty(updatedFoci)
            % Enforce slider-based left-to-right indexing order
            [~, sortIdx] = sort([updatedFoci.FrameIdx]);
            updatedFoci = updatedFoci(sortIdx);
        end
    end

    function findFocalPoints(~, ~)
        if isempty(bData), return; end
        buildAnalyticsCache(true);
        
        d = uiprogressdlg(anaFig, 'Title', 'Analyzing Foci', ...
            'Message', 'Scoring frames for peak intensity, compactness, and ellipticity...', 'Indeterminate', 'on');
        drawnow;
        
        try
            % Dynamic thresholds securely anchored to global peak values within respective partitioned pipelines
            threshRawLin = max(200, 0.05 * max(cacheRawLin.I));
            threshRawSq  = max(40000, 0.05 * max(cacheRawSq.I));
            threshExpLin = max(0.01, 0.05 * max(cacheExpLin.I));
            threshExpSq  = max(0.0001, 0.05 * max(cacheExpSq.I));
            
            fociRawLin = performFocalDetection(fociRawLin, cacheRawLin, threshRawLin, false);
            fociRawSq  = performFocalDetection(fociRawSq,  cacheRawSq,  threshRawSq,  true);
            fociExpLin = performFocalDetection(fociExpLin, cacheExpLin, threshExpLin, false);
            fociExpSq  = performFocalDetection(fociExpSq,  cacheExpSq,  threshExpSq,  true);
            
            [fd, ~] = getActiveData();
            if ~isempty(fd)
                jumpToFocus(1);
            else
                activeFocusIdx = [];
                updateFociPlots();
                if ~isempty(bData), updateAnaPlot(round(sldAna.Value)); end
            end
            
        catch ME
            close(d); figure(anaFig);
            uialert(anaFig, sprintf('Error analyzing foci: %s', ME.message), 'Analysis Error');
            return;
        end
        close(d);
        if isvalid(anaFig), figure(anaFig); end
    end
    
    function updateThirdPlot()
        [fd, ~] = getActiveData();
        cla(axThirdPlot);
        hold(axThirdPlot, 'on');
        
        mode = bgThirdPlotMode.SelectedObject.Tag;
        
        if strcmp(mode, 'E')
            % --- ENERGY INTEGRAL ---
            chkDiffPos.Enable = 'off';
            if ~isempty(fd)
                for i = 1:length(fd)
                    if isempty(activeFocusIdx) || i ~= activeFocusIdx
                        plot(axThirdPlot, fd(i).Z_disp, fd(i).EnergyCurve, 'k-', 'LineWidth', 1, 'PickableParts', 'none');
                    end
                end
                
                if ~isempty(activeFocusIdx) && activeFocusIdx <= length(fd)
                    cLine = 'r'; if fd(activeFocusIdx).IsManual, cLine = 'y'; end
                    plot(axThirdPlot, fd(activeFocusIdx).Z_disp, fd(activeFocusIdx).EnergyCurve, '-', 'Color', cLine, 'LineWidth', 2, 'PickableParts', 'none');
                end
                
                axThirdPlot.XLim = [-4, 4];
                yMax = 1.2;
                allMax = max(arrayfun(@(x) max([x.EnergyCurve, 0]), fd));
                if allMax > 1.2, yMax = allMax * 1.1; end
                axThirdPlot.YLim = [0, yMax];
            else
                axThirdPlot.XLim = [-4, 4];
                axThirdPlot.YLim = [0, 1.2];
            end
            
            title(axThirdPlot, 'Energy Integral (50\mum Dia)');
            xlabel(axThirdPlot, '\Delta Z from Focus (mm)');
            ylabel(axThirdPlot, 'Normalized Energy');
            grid(axThirdPlot, 'on');
            
        else
            % --- SPATIAL TRENDS (X, Y, Z) ---
            chkDiffPos.Enable = 'on';
            if isempty(fd)
                title(axThirdPlot, 'No Focal Data');
                return;
            end
            
            if strcmp(mode, 'X')
                rawY = [fd.X]; yLbl = 'X (\mum)'; tStr = 'X Position';
            elseif strcmp(mode, 'Y')
                rawY = [fd.Y]; yLbl = 'Y (\mum)'; tStr = 'Y Position';
            else
                rawY = [fd.Z]; yLbl = 'Z (mm)'; tStr = 'Z Position';
            end
            
            if chkDiffPos.Value
                if length(rawY) < 2
                    title(axThirdPlot, 'Need \geq 2 foci for \Delta Diff');
                    return;
                end
                yData = diff(rawY);
                xData = 1:length(yData);
                yLbl = ['\Delta ', yLbl];
                tStr = [tStr, ' Difference'];
                
                scatter(axThirdPlot, xData, yData, 60, 'c', 'filled', 'MarkerEdgeColor', 'b', 'PickableParts', 'none');
            else
                yData = rawY;
                xData = 1:length(yData);
                tStr = [tStr, ' Trend'];
                
                isMan = [fd.IsManual];
                if any(~isMan)
                    scatter(axThirdPlot, xData(~isMan), yData(~isMan), 60, 'r', 'filled', 'MarkerEdgeColor', 'w', 'PickableParts', 'none');
                end
                if any(isMan)
                    scatter(axThirdPlot, xData(isMan), yData(isMan), 60, 'y', 'filled', 'MarkerEdgeColor', 'k', 'PickableParts', 'none');
                end
                
                if ~isempty(activeFocusIdx) && activeFocusIdx <= length(fd)
                    color = 'g'; if fd(activeFocusIdx).IsManual, color = 'y'; end
                    scatter(axThirdPlot, activeFocusIdx, yData(activeFocusIdx), 120, color, 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 2, 'PickableParts', 'none');
                end
            end
            
            n = length(xData);
            if n > 1
                deg = min(2, n-1);
                p = polyfit(xData, yData, deg);
                xF = linspace(min(xData), max(xData), 50);
                yF = polyval(p, xF);
                
                plot(axThirdPlot, xF, yF, 'b-', 'LineWidth', 1.5, 'PickableParts', 'none');
                
                if deg == 2
                    eqStr = sprintf('Fit: y = %.3g x^2 %+.3g x %+.3g', p(1), p(2), p(3));
                else
                    eqStr = sprintf('Fit: y = %.3g x %+.3g', p(1), p(2));
                end
                
                text(axThirdPlot, 0.05, 0.9, eqStr, 'Units', 'normalized', ...
                    'FontSize', 9, 'Color', 'b', 'BackgroundColor', [1 1 1 0.8], 'Margin', 2);
            end
            
            axThirdPlot.XLim = [0.5, n + 0.5];
            ySpan = max(yData) - min(yData);
            if ySpan == 0, ySpan = 1; end
            axThirdPlot.YLim = [min(yData) - ySpan*0.2, max(yData) + ySpan*0.2];
            
            title(axThirdPlot, tStr);
            if chkDiffPos.Value
                xlabel(axThirdPlot, 'Focus Interval Index');
            else
                xlabel(axThirdPlot, 'Focus Index');
            end
            ylabel(axThirdPlot, yLbl);
            grid(axThirdPlot, 'on');
        end
        
        hold(axThirdPlot, 'off');
    end

    function updateFociPlots()
        [fd, c] = getActiveData();
        if isempty(c.I) || isempty(xVec_cache), return; end
        
        % 1. Update Listbox (sorted by FrameIdx strictly)
        listStrs = {};
        for i = 1:length(fd)
            baseStr = sprintf('F%d: Z=%.1f, X=%.0f, Y=%.0f', fd(i).FrameIdx, fd(i).Z, fd(i).X, fd(i).Y);
            if fd(i).IsManual
                listStrs{i} = sprintf('[M] %s', baseStr);
            else
                listStrs{i} = baseStr;
            end
        end
        
        if ~isempty(listStrs)
            lstFoci.ItemsData = 1:length(fd);
            lstFoci.Items = listStrs;
            if isempty(activeFocusIdx) || activeFocusIdx > length(fd)
                activeFocusIdx = 1;
            end
            lstFoci.Value = activeFocusIdx;
            btnMoveFocus.Enable = 'on';
            btnRemoveFocus.Enable = 'on';
        else
            lstFoci.ItemsData = [];
            lstFoci.Items = {'No valid foci detected'};
            lstFoci.Value = lstFoci.Items{1};
            activeFocusIdx = [];
            btnMoveFocus.Enable = 'off';
            btnRemoveFocus.Enable = 'off';
        end
        
        % 2. Render Z-Plot
        cla(axIntensityZ);
        plotMode = bgPlotMode.SelectedObject.Tag;
        
        if strcmp(plotMode, '3D')
            view(axIntensityZ, 3);
            scatter3(axIntensityZ, c.C, c.E, c.I, 5, [0.7 0.7 0.7], '.', 'PickableParts', 'none');
            hold(axIntensityZ, 'on');
            
            if ~isempty(fd)
                isMan = [fd.IsManual];
                if any(~isMan)
                    scatter3(axIntensityZ, [fd(~isMan).C], [fd(~isMan).E], [fd(~isMan).Intensity], 60, 'r', 'filled', 'MarkerEdgeColor', 'w', 'PickableParts', 'none');
                end
                if any(isMan)
                    scatter3(axIntensityZ, [fd(isMan).C], [fd(isMan).E], [fd(isMan).Intensity], 60, 'y', 'filled', 'MarkerEdgeColor', 'k', 'PickableParts', 'none');
                end
                if ~isempty(activeFocusIdx) && activeFocusIdx <= length(fd)
                    color = 'g'; if fd(activeFocusIdx).IsManual, color = 'y'; end
                    scatter3(axIntensityZ, fd(activeFocusIdx).C, fd(activeFocusIdx).E, fd(activeFocusIdx).Intensity, 120, color, 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 2, 'PickableParts', 'none');
                end
            end
            hold(axIntensityZ, 'off');
            title(axIntensityZ, sprintf('Foci Parameter Space (3D) - %s', activeFociSource));
            xlabel(axIntensityZ, 'Compactness');
            ylabel(axIntensityZ, 'Ellipticity');
            zlabel(axIntensityZ, 'Peak Intensity');
            
            axIntensityZ.XLimMode = 'auto';
            axIntensityZ.YLimMode = 'auto';
            axIntensityZ.ZLimMode = 'auto';
            delete(findobj(axIntensityZ, 'Tag', 'CurrentZLine'));
            
        else
            view(axIntensityZ, 2);
            
            yData = c.I; yTitle = 'Peak Intensity';
            if strcmp(plotMode, 'Comp'), yData = c.C; yTitle = 'Compactness';
            elseif strcmp(plotMode, 'Ellip'), yData = c.E; yTitle = 'Ellipticity'; end
            
            plot(axIntensityZ, Z_cache, yData, 'k-', 'LineWidth', 1.5, 'PickableParts', 'none');
            hold(axIntensityZ, 'on');
            
            % Enforce visual X-Axis syncing with the slider
            if Z_cache(1) > Z_cache(end)
                axIntensityZ.XDir = 'reverse';
            else
                axIntensityZ.XDir = 'normal';
            end
            
            if ~isempty(fd)
                fY = [fd.Intensity];
                if strcmp(plotMode, 'Comp'), fY = [fd.C];
                elseif strcmp(plotMode, 'Ellip'), fY = [fd.E]; end
                
                isMan = [fd.IsManual];
                if any(~isMan), scatter(axIntensityZ, [fd(~isMan).Z], fY(~isMan), 60, 'r', 'filled', 'PickableParts', 'none'); end
                if any(isMan), scatter(axIntensityZ, [fd(isMan).Z], fY(isMan), 60, 'y', 'filled', 'MarkerEdgeColor', 'k', 'PickableParts', 'none'); end
                
                if ~isempty(activeFocusIdx) && activeFocusIdx <= length(fd)
                    color = 'g'; if fd(activeFocusIdx).IsManual, color = 'y'; end
                    scatter(axIntensityZ, fd(activeFocusIdx).Z, fY(activeFocusIdx), 120, color, 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 2, 'PickableParts', 'none');
                end
            end
            hold(axIntensityZ, 'off');
            
            title(axIntensityZ, sprintf('Detected %d Focal Planes (%s)', length(fd), activeFociSource));
            xlabel(axIntensityZ, 'Stage Position Z (mm)');
            ylabel(axIntensityZ, yTitle);
            
            axIntensityZ.XLimMode = 'manual';
            axIntensityZ.YLimMode = 'manual';
            axIntensityZ.XLim = [min(Z_cache), max(Z_cache)];
            validY = yData(~isnan(yData) & ~isinf(yData));
            if ~isempty(validY)
                maxY = max(validY);
                if maxY <= 0, maxY = 1; end 
                axIntensityZ.YLim = [min(0, min(validY)), maxY * 1.1];
            end
            
            if ~isempty(bData)
                drawCurrentZLine(round(sldAna.Value));
            end
        end
        
        axIntensityZ.ButtonDownFcn = @(src, evt) handlePlotClick(evt, 'Z');
        
        % 3. Render XY-Plot Base Background
        if isempty(bData)
            if ~isempty(loaded_mipImage_Lin)
                baseImg = loaded_mipImage_Lin;
                if chkViewSquared.Value, baseImg = baseImg.^2; end
                im = imagesc(axFociXY, 'XData', xVec_cache, 'YData', yVec_cache, 'CData', baseImg);
                im.PickableParts = 'none'; 
            end
        else
            if isempty(mipImage)
                mipImgRaw = fetchBaseFrame(1, chkExpCorr.Value);
                if chkFilter3D.Value, mipImgRaw = imgaussfilt(mipImgRaw, 0.5); end
                if chkViewSquared.Value, mipImgRaw = mipImgRaw.^2; end
                
                mipImage = mipImgRaw;
                for k = 2:length(bData)
                    tmpRaw = fetchBaseFrame(k, chkExpCorr.Value);
                    if chkFilter3D.Value, tmpRaw = imgaussfilt(tmpRaw, 0.5); end
                    if chkViewSquared.Value, tmpRaw = tmpRaw.^2; end
                    mipImage = max(mipImage, tmpRaw);
                end
            end
            im = imagesc(axFociXY, 'XData', xVec_cache, 'YData', yVec_cache, 'CData', mipImage);
            im.PickableParts = 'none';
        end
        
        axis(axFociXY, 'image'); 
        hold(axFociXY, 'on');
        
        if ~isempty(fd)
            isMan = [fd.IsManual];
            if any(~isMan)
                scatter(axFociXY, [fd(~isMan).X], [fd(~isMan).Y], 60, 'r', 'filled', 'MarkerEdgeColor', 'w', 'PickableParts', 'none');
            end
            if any(isMan)
                scatter(axFociXY, [fd(isMan).X], [fd(isMan).Y], 60, 'y', 'filled', 'MarkerEdgeColor', 'k', 'PickableParts', 'none');
            end
            
            if ~isempty(activeFocusIdx) && activeFocusIdx <= length(fd)
                color = 'g'; if fd(activeFocusIdx).IsManual, color = 'y'; end
                scatter(axFociXY, fd(activeFocusIdx).X, fd(activeFocusIdx).Y, 120, color, 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 2, 'PickableParts', 'none');
            end
            
            xSpan = max([fd.X]) - min([fd.X]);
            ySpan = max([fd.Y]) - min([fd.Y]);
            padX = max(xSpan * 0.2, 100); 
            padY = max(ySpan * 0.2, 100);
            
            axFociXY.XLim = [min([fd.X]) - padX, max([fd.X]) + padX];
            axFociXY.YLim = [min([fd.Y]) - padY, max([fd.Y]) + padY];
            title(axFociXY, 'XY Focal Mapping (Cropped)');
        else
            axFociXY.XLim = [min(xVec_cache), max(xVec_cache)];
            axFociXY.YLim = [min(yVec_cache), max(yVec_cache)];
            title(axFociXY, 'No valid focal points');
        end
        hold(axFociXY, 'off');
        axFociXY.ButtonDownFcn = @(src, evt) handlePlotClick(evt, 'XY');

        % 4. Render the Right-most Dynamic Plot
        updateThirdPlot();
    end

    function drawCurrentZLine(idx)
        if isempty(Z_cache) || idx < 1 || idx > length(Z_cache), return; end
        if strcmp(bgPlotMode.SelectedObject.Tag, '3D'), return; end
        
        pos = Z_cache(idx);
        delete(findobj(axIntensityZ, 'Tag', 'CurrentZLine'));
        
        xl = axIntensityZ.XLim;
        yl = axIntensityZ.YLim;
        hold(axIntensityZ, 'on');
        xline(axIntensityZ, pos, 'k:', 'LineWidth', 0.5, 'Tag', 'CurrentZLine', 'PickableParts', 'none');
        hold(axIntensityZ, 'off');
        axIntensityZ.XLim = xl;
        axIntensityZ.YLim = yl;
    end

    function handlePlotClick(evt, mode)
        [fd, ~] = getActiveData();
        if isempty(fd), return; end
        pt = evt.IntersectionPoint(1:2);
        
        if strcmp(mode, 'Z')
            if strcmp(bgPlotMode.SelectedObject.Tag, '3D'), return; end 
            distances = abs([fd.Z] - pt(1));
        else
            dx = [fd.X] - pt(1);
            dy = [fd.Y] - pt(2);
            distances = sqrt(dx.^2 + dy.^2);
        end
        
        [~, minIdx] = min(distances);
        if ~isempty(minIdx)
            jumpToFocus(minIdx);
        end
    end
    
    function jumpToFocus(idx)
        [fd, ~] = getActiveData();
        if isempty(idx) || idx < 1 || idx > length(fd)
            activeFocusIdx = [];
            updateFociPlots();
            if ~isempty(bData), updateAnaPlot(round(sldAna.Value)); end
        else
            activeFocusIdx = idx;
            updateFociPlots();
            
            if ~isempty(bData)
                sldAna.Value = fd(idx).FrameIdx;
                updateAnaPlot(fd(idx).FrameIdx);
                
                if ~chkLockAxes.Value
                    cX = fd(idx).X;
                    cY = fd(idx).Y;
                    if ~chkLockZoom.Value
                        axAna.XLim = [cX - 150, cX + 150];
                        axAna.YLim = [cY - 150, cY + 150];
                    else
                        spanX = diff(axAna.XLim);
                        spanY = diff(axAna.YLim);
                        axAna.XLim = [cX - spanX/2, cX + spanX/2];
                        axAna.YLim = [cY - spanY/2, cY + spanY/2];
                    end
                end
            end
        end
    end
    
    function removeFocus(~, ~)
        [fd, ~] = getActiveData();
        idx = lstFoci.Value;
        if isempty(idx) || ~isnumeric(idx) || isempty(fd)
            return;
        end
        fd(idx) = [];
        saveActiveData(fd);
        
        if isempty(fd)
            jumpToFocus([]);
        else
            nextIdx = min(idx, length(fd));
            jumpToFocus(nextIdx);
        end
    end
    
    function apply3DFilter()
        if isempty(bData) || length(bData) < 2, return; end
        d = uiprogressdlg(anaFig, 'Title', 'Filtering Data', ...
            'Message', 'Applying 3D Gaussian filter to volume. Please wait...', 'Indeterminate', 'on');
        drawnow;
        try
            h = size(bData(1).Frame, 1); w = size(bData(1).Frame, 2); N = length(bData);
            vol = zeros(h, w, N, 'single');
            
            for k = 1:N
                vol(:,:,k) = fetchBaseFrame(k, chkExpCorr.Value);
            end
            
            sigXY = edtSigmaXY.Value;
            sigZ = edtSigmaZ.Value;
            filteredVol = imgaussfilt3(vol, [sigXY, sigXY, sigZ]);
            mipImage = []; 
        catch ME
            close(d); figure(anaFig);
            uialert(anaFig, sprintf('Filtering failed: %s', ME.message), 'Filter Error');
            chkFilter3D.Value = false; filteredVol = [];
            if ~isempty(bData), updateAnaPlot(round(sldAna.Value)); end
            return;
        end
        close(d);
        if isvalid(anaFig), figure(anaFig); drawnow; end
        updateAnaPlot(round(sldAna.Value));
    end
    
    function toggleFilter(~, ~)
        if chkFilter3D.Value
            apply3DFilter();
        else
            filteredVol = []; 
            mipImage = []; 
            if ~isempty(bData), updateAnaPlot(round(sldAna.Value)); end
        end
    end
    
    function changeSigma(~, ~)
        if chkFilter3D.Value, apply3DFilter(); end
    end
    
    function toggleMIP(~, ~)
        if isempty(bData), return; end
        if chkMIP.Value
            sldAna.Enable = 'off'; btnPrev10.Enable = 'off'; btnPrev.Enable = 'off';
            btnNext.Enable = 'off'; btnNext10.Enable = 'off'; edtFrame.Enable = 'off'; edtPos.Enable = 'off';
        else
            sldAna.Enable = 'on'; btnPrev10.Enable = 'on'; btnPrev.Enable = 'on';
            btnNext.Enable = 'on'; btnNext10.Enable = 'on'; edtFrame.Enable = 'on'; edtPos.Enable = 'on';
        end
        updateAnaPlot(round(sldAna.Value));
    end

    function toggleViewSquared(~, ~)
        if chkViewSquared.Value
            if chkExpCorr.Value
                edtAnaCLimMax.Value = max(1, (edtAnaCLimMax.Value)^2);
                edtAnaCLimMin.Value = (edtAnaCLimMin.Value)^2;
            else
                edtAnaCLimMax.Value = max(1, (edtAnaCLimMax.Value)^2);
                edtAnaCLimMin.Value = (edtAnaCLimMin.Value)^2;
            end
        else
            if chkExpCorr.Value
                edtAnaCLimMax.Value = max(1, sqrt(edtAnaCLimMax.Value));
                edtAnaCLimMin.Value = sqrt(edtAnaCLimMin.Value);
            else
                edtAnaCLimMax.Value = max(1, sqrt(edtAnaCLimMax.Value));
                edtAnaCLimMin.Value = sqrt(edtAnaCLimMin.Value);
            end
        end
        applyAnaCLim();
        mipImage = []; 
        updateFociPlots(); 
        if ~isempty(bData), updateAnaPlot(round(sldAna.Value)); end
    end

    function applyAnaCLim(~, ~)
        minV = edtAnaCLimMin.Value; maxV = edtAnaCLimMax.Value;
        if maxV > minV, axAna.CLim = [minV, maxV]; axFociXY.CLim = [minV, maxV]; end
    end

    function snapAnaSlider(val)
        if isempty(bData), return; end
        val = round(val); sldAna.Value = val; 
        updateFociPlots(); 
        updateAnaPlot(val);
    end
    
    function jumpToFrame(~, event)
        if isempty(bData) || chkMIP.Value, return; end
        newVal = max(1, min(length(bData), round(event.Value)));
        snapAnaSlider(newVal);
    end
    
    function jumpToPos(~, event)
        if isempty(bData) || chkMIP.Value, return; end
        positions = [bData.Position];
        [~, minIdx] = min(abs(positions - event.Value));
        snapAnaSlider(minIdx);
    end
    
    function moveFrame(direction)
        if isempty(bData) || chkMIP.Value, return; end
        newVal = max(1, min(length(bData), round(sldAna.Value) + direction));
        snapAnaSlider(newVal);
    end
    
    function handleKeyPress(~, event)
        if isempty(bData) || strcmp(sldAna.Enable, 'off') || chkMIP.Value, return; end
        step = 1; if ismember('control', event.Modifier), step = 10; end
        curVal = round(sldAna.Value);
        if strcmp(event.Key, 'leftarrow'), snapAnaSlider(max(1, curVal - step));
        elseif strcmp(event.Key, 'rightarrow'), snapAnaSlider(min(length(bData), curVal + step));
        end
    end
    
    function updateAnaPlot(idx)
        if isempty(bData) || idx < 1 || idx > length(bData), return; end
        
        axX = axAna.XLim; axY = axAna.YLim;
        setts = bData(idx).Settings;
        pos = bData(idx).Position;
        edtFrame.Value = idx;
        edtPos.Value = pos;
        
        if chkMIP.Value
            if isempty(mipImage)
                d = uiprogressdlg(anaFig, 'Title', 'Computing MIP', ...
                    'Message', 'Calculating Maximum Intensity Projection...', 'Indeterminate', 'on');
                drawnow;
                
                if chkFilter3D.Value && ~isempty(filteredVol)
                    if chkViewSquared.Value
                        mipImage = max(filteredVol.^2, [], 3);
                    else
                        mipImage = max(filteredVol, [], 3);
                    end
                else
                    mipImgRaw = fetchBaseFrame(1, chkExpCorr.Value);
                    if chkViewSquared.Value, mipImgRaw = mipImgRaw.^2; end
                    mipImage = mipImgRaw;
                    
                    for k = 2:length(bData)
                        tmpRaw = fetchBaseFrame(k, chkExpCorr.Value);
                        if chkViewSquared.Value, tmpRaw = tmpRaw.^2; end
                        mipImage = max(mipImage, tmpRaw);
                    end
                end
                close(d);
                if isvalid(anaFig), figure(anaFig); drawnow; end
            end
            img = mipImage;
        else
            if chkFilter3D.Value && ~isempty(filteredVol)
                img = filteredVol(:,:,idx);
            else
                img = fetchBaseFrame(idx, chkExpCorr.Value);
            end
            if chkViewSquared.Value
                img = img.^2;
            end
        end
        
        pxSize = setts.d_x_pixel_size_um; bin = double(setts.i_binning);
        w = double(setts.i_width); h = double(setts.i_height);
        effPx = pxSize * bin;
        xIns = linspace(-w/2, w/2, w) * effPx; yIns = linspace(-h/2, h/2, h) * effPx;
        
        hImg = findobj(axAna, 'Type', 'image');
        if isempty(hImg)
            imagesc(axAna, 'XData', xIns, 'YData', yIns, 'CData', img);
            axis(axAna, 'image');
        else
            hImg.XData = xIns; hImg.YData = yIns; hImg.CData = img;
            axAna.XLim = axX; axAna.YLim = axY;
        end
        
        delete(findobj(axAna, 'Tag', 'FocusTargetMarker'));
        [fd, ~] = getActiveData();
        
        if ~isempty(fd)
            hold(axAna, 'on');
            theta_circ = linspace(0, 2*pi, 60);
            
            for fIdx = 1:length(fd)
                circX = fd(fIdx).X + 25 * cos(theta_circ);
                circY = fd(fIdx).Y + 25 * sin(theta_circ);
                
                if isempty(activeFocusIdx) || fIdx ~= activeFocusIdx
                    plot(axAna, circX, circY, '-k', 'LineWidth', 1, 'Tag', 'FocusTargetMarker', 'PickableParts', 'none');
                end
            end
            
            if ~isempty(activeFocusIdx) && activeFocusIdx <= length(fd)
                circX = fd(activeFocusIdx).X + 25 * cos(theta_circ);
                circY = fd(activeFocusIdx).Y + 25 * sin(theta_circ);
                
                color = 'g'; if fd(activeFocusIdx).IsManual, color = 'y'; end
                plot(axAna, circX, circY, ['-', color], 'LineWidth', 2, 'Tag', 'FocusTargetMarker', 'PickableParts', 'none');
            end
            hold(axAna, 'off');
        end
        
        if chkMIP.Value
            if chkFilter3D.Value, title(axAna, sprintf('Filtered Maximum Intensity Projection (%d Frames)', length(bData)));
            else, title(axAna, sprintf('Raw Maximum Intensity Projection (%d Frames)', length(bData))); end
        else
            title(axAna, sprintf('Frame %d | Position: %.2f mm', idx, pos));
        end
        
        xlabel(axAna, 'X (\mum)'); ylabel(axAna, 'Y (\mum)');
        drawCurrentZLine(idx);
    end

    function setupAnalysisUI(clearResults)
        if nargin < 1, clearResults = true; end
        
        if clearResults
            fociRawLin = struct('FrameIdx', {}, 'Z', {}, 'X', {}, 'Y', {}, 'Intensity', {}, 'C', {}, 'E', {}, 'IsManual', {}, 'Z_disp', {}, 'EnergyCurve', {});
            fociRawSq  = struct('FrameIdx', {}, 'Z', {}, 'X', {}, 'Y', {}, 'Intensity', {}, 'C', {}, 'E', {}, 'IsManual', {}, 'Z_disp', {}, 'EnergyCurve', {});
            fociExpLin = struct('FrameIdx', {}, 'Z', {}, 'X', {}, 'Y', {}, 'Intensity', {}, 'C', {}, 'E', {}, 'IsManual', {}, 'Z_disp', {}, 'EnergyCurve', {});
            fociExpSq  = struct('FrameIdx', {}, 'Z', {}, 'X', {}, 'Y', {}, 'Intensity', {}, 'C', {}, 'E', {}, 'IsManual', {}, 'Z_disp', {}, 'EnergyCurve', {});
            
            cacheRawLin = struct('I', [], 'C', [], 'E', [], 'X', [], 'Y', [], 'IsMulti', []);
            cacheRawSq  = struct('I', [], 'C', [], 'E', [], 'X', [], 'Y', [], 'IsMulti', []);
            cacheExpLin = struct('I', [], 'C', [], 'E', [], 'X', [], 'Y', [], 'IsMulti', []);
            cacheExpSq  = struct('I', [], 'C', [], 'E', [], 'X', [], 'Y', [], 'IsMulti', []);
            
            Z_cache = []; xVec_cache = []; yVec_cache = [];
            activeFocusIdx = [];
            
            lstFoci.ItemsData = [];
            lstFoci.Items = {'No valid foci detected'};
            lstFoci.Value = lstFoci.Items{1};
            
            edtAnaCLimMax.Value = 65535;
            applyAnaCLim();
        end
        
        mipImage = []; filteredVol = []; chkMIP.Value = false;
        
        initExposureFactors(); % Precompute global base metrics
        
        N = length(bData);
        if N > 1
            sldAna.Limits = [1, N];
            numTicks = min(5, N); tIdx = round(linspace(1, N, numTicks));
            sldAna.MajorTicks = tIdx;
            
            tLbls = cell(1, numTicks);
            for k = 1:numTicks, tLbls{k} = sprintf('%.2f mm', bData(tIdx(k)).Position); end
            sldAna.MajorTickLabels = tLbls; sldAna.Value = 1;
            
            sldAna.Enable = 'on'; btnPrev10.Enable = 'on'; btnPrev.Enable = 'on';
            btnNext.Enable = 'on'; btnNext10.Enable = 'on'; edtFrame.Enable = 'on';
            edtPos.Enable = 'on'; chkMIP.Enable = 'on'; chkFilter3D.Enable = 'on'; chkExpCorr.Enable = 'on';
            edtSigmaXY.Enable = 'on'; edtSigmaZ.Enable = 'on'; btnAnalyzeFoci.Enable = 'on';
            btnAddFocus.Enable = 'on'; chkViewSquared.Enable = 'on';
            edtFrame.Limits = [1, N];
        else
            sldAna.Limits = [1, 2]; sldAna.Value = 1; sldAna.Enable = 'off';
            btnPrev10.Enable = 'off'; btnPrev.Enable = 'off'; btnNext.Enable = 'off';
            btnNext10.Enable = 'off'; edtFrame.Enable = 'off'; edtPos.Enable = 'off';
            chkMIP.Enable = 'off'; chkFilter3D.Enable = 'off'; chkExpCorr.Enable = 'off'; edtSigmaXY.Enable = 'off';
            edtSigmaZ.Enable = 'off'; btnAnalyzeFoci.Enable = 'off';
            btnAddFocus.Enable = 'off'; chkViewSquared.Enable = 'off';
            btnRemoveFocus.Enable = 'off'; btnMoveFocus.Enable = 'off';
        end
        
        if N > 0
            updateAnaPlot(1);
        end
    end

    function loadDiskData(~, ~)
        hasResults = ~isempty(cacheRawLin.I) || ~isempty(fociRawLin) || ~isempty(fociRawSq);
        keepResults = false;
        if hasResults
            sel = uiconfirm(anaFig, 'Analysis results are currently present in memory. Do you want to keep them or discard them?', ...
                'Keep Results?', 'Options', {'Keep Results', 'Discard Results'}, 'DefaultOption', 1);
            keepResults = strcmp(sel, 'Keep Results');
        end

        [f, p] = uigetfile('*.mat', 'Select Sweep Data');
        if ischar(f)
            d = uiprogressdlg(anaFig, 'Title', 'Loading Data', ...
                'Message', 'Reading sweep dataset from disk. Please wait...', 'Indeterminate', 'on');
            drawnow;
            
            errStr = '';
            try
                loadedData = load(fullfile(p, f));
                if isfield(loadedData, 'sweepData')
                    bData = loadedData.sweepData;
                    if isfield(loadedData, 'hardwareInfo'), hwInfo = loadedData.hardwareInfo; end
                    if isfield(loadedData, 'settingsDescriptions'), desc = loadedData.settingsDescriptions; end
                else
                    errStr = 'Invalid file format. sweepData variable missing.';
                end
            catch ME
                errStr = sprintf('Error loading file: %s', ME.message);
            end
            
            close(d);
            
            if isvalid(anaFig)
                figure(anaFig); drawnow;
                if ~isempty(errStr), uialert(anaFig, errStr, 'Load Error');
                else
                    lblFilename.Text = sprintf('Loaded File: %s', f);
                    setupAnalysisUI(~keepResults);
                    
                    if ~keepResults
                        cla(axIntensityZ); title(axIntensityZ, 'Z-Profile & Focal Planes');
                        cla(axFociXY); title(axFociXY, 'XY Focal Mapping (Cropped)');
                        cla(axThirdPlot); title(axThirdPlot, 'Energy Integral (50\mum Dia)');
                    else
                        updateFociPlots();
                    end
                    
                    delete(findobj(axAna, 'Tag', 'FocusTargetMarker'));
                end
            end
        end
    end
end