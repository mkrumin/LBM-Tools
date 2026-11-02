function dataOut = readWCF(filePath, camWidth, camHeight)
    % READWCF Reads a DataRay .wcf beam profile image.
    % Ensure camWidth and camHeight match your sensor (e.g., 2048x2048 for WinCamD-LCM)
    % We lose the metadata from the files (as we do not know the format),
    % but the images are loaded ok
    
    fileInfo = dir(filePath);
    fileSize = fileInfo.bytes;
    singleFrameBytes = camWidth * camHeight * 2; % for uint16
    headerOffset = 6528; % Manually tuned
    interFrameOffset = 944; % manually tuned
    nFrames = floor((fileSize-headerOffset)/(singleFrameBytes+interFrameOffset)); % initial guess
    
    dataOut = zeros(camHeight, camWidth, nFrames, 'uint16');

    fid = fopen(filePath, 'r');
    if fid == -1
        error('Failed to open file: %s', filePath);
    end
    
    % Skip the proprietary header
    fseek(fid, headerOffset, 'bof');
    
    % Read the pixel data (WinCamD stores 12-bit ADC data as uint16)
    iFrame = 0;

    while ~feof(fid)
    iFrame = iFrame + 1;
    rawData = fread(fid, camWidth * camHeight, 'uint16');
    
    % Reshape array and transpose to match sensor orientation
    try
    img = reshape(rawData, [camWidth, camHeight])';
    dataOut(:,:,iFrame) = img;
    catch
        fprintf('Looks like we reached end of file\n')
        feof(fid)
        break
    end
    
    fseek(fid, interFrameOffset, 'cof');

end
fclose(fid);

end