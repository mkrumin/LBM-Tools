classdef DataRayCamera < handle
    % DATARAYCAMERA Handles HTTP communication and image retrieval for DataRay sensors
    
    properties (SetAccess = private)
        BaseURL
        DeviceID
        DeviceName
    end
    
    properties (Access = private)
        TextOpts
        JsonParseOpts
        JsonPostOpts
        BinaryOpts
        TargetExposure = 2000; % Default manual exposure value
        TargetAutoExposure = false; % Default auto-exposure state
    end
    
    methods
        function obj = DataRayCamera(hostIP, port)
            % 1. Setup Base Configuration
            obj.BaseURL = sprintf('http://%s:%s', hostIP, port);
            obj.TextOpts = weboptions('ContentType', 'text', 'Timeout', 5);
            obj.BinaryOpts = weboptions('ContentType', 'binary', 'Timeout', 5);
            obj.JsonParseOpts = weboptions('ContentType', 'json', 'Timeout', 5);
            obj.JsonPostOpts = weboptions('MediaType', 'application/json', ...
                                          'ContentType', 'text', ...
                                          'RequestMethod', 'post', 'Timeout', 5);
            
            % 2. Retrieve & Parse Device List
            deviceList = webread([obj.BaseURL '/RefreshDeviceList'], obj.TextOpts);
            bracketMatch = regexp(deviceList, '(?<=\[).*?(?=\])', 'match');
            if isempty(bracketMatch)
                error('Could not parse any brackets out of the server string.');
            end
            
            y = split(char(bracketMatch{1}), ',');
            obj.DeviceName = strtrim(regexprep(y{3}, '[\"'']', ''));
            obj.DeviceID = strtrim(regexprep(y{2}, '[\"'']', ''));
            
            % 3. Connect, Apply Defaults, & Initialize Stream
            webread([obj.BaseURL '/ConnectCamera/' obj.DeviceID], obj.TextOpts);
            obj.applyDefaultSettings(); 
            webread([obj.BaseURL '/StartCamera/' obj.DeviceID], obj.TextOpts);
        end
        
        function actual_us = setExposureWithRestart(obj, target_us)
            % Executes a clean disconnect/reconnect cycle to inject a manual exposure
            try
                webread([obj.BaseURL '/StopCamera/' obj.DeviceID], obj.TextOpts);
                webread([obj.BaseURL '/DisconnectCamera/' obj.DeviceID], obj.TextOpts);
            catch
            end
            
            obj.TargetAutoExposure = false;
            obj.TargetExposure = round(target_us);
            
            webread([obj.BaseURL '/ConnectCamera/' obj.DeviceID], obj.TextOpts);
            obj.applyDefaultSettings();
            webread([obj.BaseURL '/StartCamera/' obj.DeviceID], obj.TextOpts);
            
            actual_us = obj.getSetting('i_exposure_time_us');
        end
        
        function actual_us = setAutoExposureWithRestart(obj, enableAuto)
            % Executes a clean disconnect/reconnect cycle to toggle Auto-Exposure
            try
                webread([obj.BaseURL '/StopCamera/' obj.DeviceID], obj.TextOpts);
                webread([obj.BaseURL '/DisconnectCamera/' obj.DeviceID], obj.TextOpts);
            catch
            end
            
            obj.TargetAutoExposure = logical(enableAuto);
            
            webread([obj.BaseURL '/ConnectCamera/' obj.DeviceID], obj.TextOpts);
            obj.applyDefaultSettings();
            webread([obj.BaseURL '/StartCamera/' obj.DeviceID], obj.TextOpts);
            
            actual_us = obj.getSetting('i_exposure_time_us');
        end
        
        function settings = getAllSettings(obj)
            settings = webread([obj.BaseURL '/GetSettings/' obj.DeviceID], obj.JsonParseOpts);
        end
        
        function val = getSetting(obj, settingName)
            settings = obj.getAllSettings();
            if isfield(settings, settingName)
                val = settings.(settingName);
            else
                error('Setting "%s" not found on this device.', settingName);
            end
        end
        
        function actualValue = setSetting(obj, settingName, requestedValue)
            currentSettings = obj.getAllSettings();
            if ~isfield(currentSettings, settingName)
                error('Setting "%s" is not a valid camera parameter.', settingName);
            end
            currentSettings.(settingName) = requestedValue;
            safeSettings = obj.sanitizeStruct(currentSettings);
            webwrite([obj.BaseURL '/ChangeSettings/' obj.DeviceID], safeSettings, obj.JsonPostOpts);
            pause(0.2); 
            actualValue = obj.getSetting(settingName);
        end
        
        function actualValues = setMultipleSettings(obj, updateStruct)
            currentSettings = obj.getAllSettings();
            fields = fieldnames(updateStruct);
            for i = 1:length(fields)
                currentSettings.(fields{i}) = updateStruct.(fields{i});
            end
            safeSettings = obj.sanitizeStruct(currentSettings);
            webwrite([obj.BaseURL '/ChangeSettings/' obj.DeviceID], safeSettings, obj.JsonPostOpts);
            pause(0.2);
            actualValues = struct();
            for i = 1:length(fields)
                actualValues.(fields{i}) = obj.getSetting(fields{i});
            end
        end
        
        function descriptions = getSettingsDescriptions(~)
            % Returns a struct containing plain English descriptions of camera settings
            descriptions = struct(...
                'b_auto_exposure_enabled', 'Turns automatic calculation of exposure time on (1) or off (0).', ...
                'b_hypercal_enabled', 'Toggles proprietary background subtraction and baseline noise correction.', ...
                'd_autotrigger_max_percentage', 'Upper intensity threshold for detecting a pulsed laser beam.', ...
                'd_autotrigger_min_percentage', 'Lower intensity threshold for detecting a pulsed laser beam.', ...
                'd_gain', 'The sensor signal amplification level.', ...
                'd_gamma', 'The gamma correction curve applied to the image (1 = linear unadjusted response).', ...
                'd_x_pixel_multiplication_factor', 'Scaling multiplier applied to X-axis pixel size (used with external optics).', ...
                'd_x_pixel_size_um', 'Physical X-axis dimension of a single pixel on the sensor in micrometers.', ...
                'd_y_pixel_multiplication_factor', 'Scaling multiplier applied to Y-axis pixel size (used with external optics).', ...
                'd_y_pixel_size_um', 'Physical Y-axis dimension of a single pixel on the sensor in micrometers.', ...
                'd_z_position_mm', 'Physical Z-axis position of the camera in millimeters (if mounted to a motorized stage).', ...
                'i_auto_exposure_max_us', 'Upper boundary in microseconds for auto-exposure.', ...
                'i_auto_exposure_min_us', 'Lower boundary in microseconds for auto-exposure.', ...
                'i_binning', 'Combines adjacent pixels (e.g., 2 means 2x2 hardware pixels act as 1 software pixel).', ...
                'i_camera_horizontal_pixels', 'Maximum physical hardware horizontal resolution.', ...
                'i_camera_type', 'Numerical code representing the specific hardware model.', ...
                'i_camera_vertical_pixels', 'Maximum physical hardware vertical resolution.', ...
                'i_connection_type', 'Code identifying the data connection method (e.g., USB 2.0 vs 3.0).', ...
                'i_exposure_time_us', 'Exact duration the sensor is exposed to light per frame in microseconds.', ...
                'i_height', 'Actual output height resolution currently being transmitted.', ...
                'i_num_frames_to_average', 'Number of consecutive frames mathematically combined to smooth out temporal noise.', ...
                'i_trigger_mode', 'Dictates how the camera captures frames (0 = continuous free run).', ...
                'i_unique_id', 'Specific identifier for this exact hardware unit.', ...
                'i_width', 'Actual output width resolution currently being transmitted.', ...
                'i_x_offset', 'Starting X coordinate for a cropped Region of Interest (0 = left edge).', ...
                'i_y_offset', 'Starting Y coordinate for a cropped Region of Interest (0 = top edge).' ...
            );
        end
        
        function imgMatrix = getFrame(obj)
            imgMatrix = []; 
            settings = obj.getAllSettings();
            
            try
                % Grab raw stream buffer
                imageResponse = webread([obj.BaseURL '/GetImage/' obj.DeviceID], obj.BinaryOpts);
            catch
                % Failsafe for dropped requests during restarts
                return; 
            end
            
            % Standard DataRay empty buffer check
            if length(imageResponse) == 18 && strcmp(char(imageResponse'), 'No Image Available')
                return;
            end
            
            % Decode Base64 and typecast to 16-bit unsigned integers
            decodedBytes = org.apache.commons.codec.binary.Base64.decodeBase64(imageResponse);
            raw16bit = typecast(decodedBytes, 'uint16');
            
            % Strict Element Count Validation
            expectedElements = settings.i_width * settings.i_height;
            if numel(raw16bit) ~= expectedElements
                % Abort this frame if a partial buffer is received
                return; 
            end
            
            % Reshape into 2D dimension grid
            imgMatrix = reshape(raw16bit, [settings.i_width, settings.i_height])';
        end
        
        function delete(obj)
            if ~isempty(obj.DeviceID)
                try
                    webread([obj.BaseURL '/StopCamera/' obj.DeviceID], obj.TextOpts);
                    webread([obj.BaseURL '/DisconnectCamera/' obj.DeviceID], obj.TextOpts);
                catch
                end
            end
        end
    end
    
    methods (Access = private)
        function applyDefaultSettings(obj)
            % Define baseline properties and push them to the camera
            jsonData = struct(...
                'i_width', 1024, ...
                'i_height', 1024, ...
                'i_x_offset', 0, ...
                'i_y_offset', 0, ...
                'i_binning', 2, ...
                'i_num_frames_to_average', 5, ...
                'b_hypercal_enabled', false, ...
                'i_auto_exposure_max_us', 100000, ...
                'i_auto_exposure_min_us', 85, ...
                'b_auto_exposure_enabled', obj.TargetAutoExposure, ...
                'i_exposure_time_us', obj.TargetExposure, ... 
                'd_gamma', 1.0);
            
            safeData = obj.sanitizeStruct(jsonData);
            webwrite([obj.BaseURL '/ChangeSettings/' obj.DeviceID], safeData, obj.JsonPostOpts);
        end
        
        function cleanSettings = sanitizeStruct(~, rawSettings)
            % Enforces strict JSON types to prevent MATLAB from sending floats
            cleanSettings = rawSettings;
            fields = fieldnames(cleanSettings);
            for k = 1:length(fields)
                f = fields{k};
                val = cleanSettings.(f);
                if startsWith(f, 'b_')
                    cleanSettings.(f) = logical(val);
                elseif startsWith(f, 'i_')
                    cleanSettings.(f) = int32(val);
                elseif startsWith(f, 'd_')
                    cleanSettings.(f) = double(val);
                end
            end
        end
    end
end