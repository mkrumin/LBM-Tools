classdef ZaberStage < handle
    % ZABERSTAGE Controls a Zaber X-LSM200A Linear Stage via ASCII protocol

    properties (Access = private)
        SerialConn          % The serialport object
        MicrostepsPerMM = 20997.375; % Hardware specific resolution
    end

    methods
        function obj = ZaberStage(portName)
            % Constructor: Opens serial port and configures terminator
            obj.SerialConn = serialport(portName, 115200);
            configureTerminator(obj.SerialConn, "CR/LF");
        end

        function delete(obj)
            % Destructor: Automatically closes the serial port when object is cleared
            clear obj.SerialConn;
        end

        function home(obj)
            % Sends stage to home position and waits for completion
            writeline(obj.SerialConn, "/1 1 home");
            readline(obj.SerialConn); % Clear immediate ack
            obj.waitForIdle();
        end

        function moveAbsolute(obj, target_mm)
            % Converts mm to microsteps, moves, and waits for completion
            target_steps = round(target_mm * obj.MicrostepsPerMM);
            command = sprintf('/1 1 move abs %d', target_steps);

            writeline(obj.SerialConn, command);
            readline(obj.SerialConn); % Clear immediate ack

            obj.waitForIdle();
        end

        function actual_mm = getPosition(obj)
            % Queries current position and converts back to mm
            writeline(obj.SerialConn, "/1 1 get pos");
            pos_response = readline(obj.SerialConn);

            % Parse the response
            parts = split(strtrim(pos_response), ' ');
            actual_steps = str2double(parts(end));
            actual_mm = actual_steps / obj.MicrostepsPerMM;
        end

        function actual_speed_mm_s = setSpeed(obj, speed_mm_s)
            % SETSPEED Changes the maximum travel speed of the stage and
            % returns the actual speed that was set.

            % 1. Convert mm/s to microsteps/second
            speed_microsteps_s = speed_mm_s * obj.MicrostepsPerMM;

            % 2. Convert to Zaber Velocity Data units
            target_speed_data = round(speed_microsteps_s * 1.6384);

            % 3. Send the SET command
            command = sprintf('/1 1 set maxspeed %d', target_speed_data);
            writeline(obj.SerialConn, command);

            % 4. Read and check the SET acknowledgement
            set_response = readline(obj.SerialConn);
            if contains(set_response, "RJ")
                warning('Zaber rejected the maxspeed command. Response: %s', set_response);
            end

            % 5. Explicitly GET the new maxspeed to confirm
            writeline(obj.SerialConn, "/1 1 get maxspeed");
            get_response = readline(obj.SerialConn);

            % 6. Parse the GET response
            parts = split(strtrim(get_response), ' ');

            % The actual value should be the very last word in the string
            last_word = parts(end);
            actual_speed_data = str2double(last_word);

            if isnan(actual_speed_data)
                warning('Failed to parse speed data. Raw GET response: %s', get_response);
                actual_speed_mm_s = NaN;
                return;
            end

            % 7. Convert the raw data back to mm/s
            actual_microsteps_s = actual_speed_data / 1.6384;
            actual_speed_mm_s = actual_microsteps_s / obj.MicrostepsPerMM;
        end

    end

    methods (Access = private)
        function waitForIdle(obj)
            % Internal function that continuously polls until stage stops moving
            isBusy = true;
            while isBusy
                writeline(obj.SerialConn, "/1 1");
                response = readline(obj.SerialConn);

                if contains(response, "IDLE")
                    isBusy = false;
                else
                    pause(0.05); % Prevent buffer overload
                end
            end
        end
    end
end