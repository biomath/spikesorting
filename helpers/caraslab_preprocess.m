function caraslab_preprocess(datadir,sel, start_time_optional, end_time_optional)
%caraslab_preprocess(datadir,sel)
%
% This function loads in one data file at a time, removes large
% amplitude artifacts, bandpass filters the data between 300-7000 Hz, 
% using a 3rd order butterworth acausal filter, and applies common average
% referencing as described in Ludwig et al.(2009)J Neurophys 101(3):1679-89
% 
% Input variables:
%
%       datadir:    path to folder containing data directories. Each directory
%                   should contain a kilosort configuration (config.mat) 
%                   file generated by caraslab_createconfig.m
%
%       sel:         if 0 or omitted, program will cycle through all folders
%                    in the data directory.    
%
%                    if 1, program will prompt user to select folder
%
%Written by ML Caras Mar 27 2019

%Validate inputs
% narginchk(1,2)
if ~exist(datadir,'dir')
    fprintf('\nCannot find data directory!\n')
    return
end

%Set defaults
if nargin == 1
    sel = 0; %cycle through all folders
end




% if ~sel
%     %Get a list of all folders in the data directory
%     folders = caraslab_lsdir(datadir);
% % %     foldernames = extractfield(folders,'name');
%     foldernames = {folders.name};
% 
% elseif sel  
%     %Prompt user to select folder
%     pname = uigetdir(datadir,'Select data folder');
%     [~,name] = fileparts(pname);
%     foldernames = {name};  
% end

if ~sel
    foldernames = {datadir};

elseif sel  
    %Prompt user to select BLOCK
    FULLPATH = uigetdir(datadir,'Select BLOCK to process');
    PathFolders = regexp(FULLPATH,filesep,'split');
%     BLOCKNAMES = caraslab_lsdir(FULLPATH);
    BLOCKNAMES = {PathFolders(end)};
end

%Loop through files
for i = 1:numel(foldernames)
    clear ops rawsig cleansig
    
    %Define the path to the current data
%     currpath = fullfile(datadir,foldernames{i});
    currpath = datadir;
    %Load in configuration file ops struct
    load(fullfile(currpath, 'config.mat'),'ops');

    %Get sampling rate 
    fs = ops.fs;
    
    %Get number of channels and identity of bad channels
    nchans = ops.NchanTOT;
%     badchans = ops.badchannels;
    if nargin > 2
        start_point = round(start_time_optional*fs);
        if start_point == 0
            start_point = 1;
        end
        if nargin > 3
            end_point = round(end_time_optional*fs);
        end
    else
        start_point = 0;
    end

    %Load in raw voltage streams (M x N matrix),
    %where M = channel, N = samples
    fprintf('Loading raw data... ')
    load(ops.rawdata,'rawsig');
%     raw_copy_debug = rawsig;
    if start_point > 0 && end_point ==0
        cleansig = rawsig(:,start_point:end);
    elseif end_point > 0
        cleansig = rawsig(:,start_point:end_point);
    else
        cleansig = rawsig;
    end
    fprintf('Done in %3.0fs!\n', toc);
    
    % Delining
    fprintf('Delining filtered data... ')
    tic
    for ch_n = 1:size(cleansig, 2)
        cleansig(:, ch_n) = chunkwiseDeline(cleansig(:, ch_n), fs, [60, 180, 300], 10);
    end
    % flip back
    cleansig = cleansig';
    fprintf('Done in %3.0fs!\n', toc);

    %Apply common average referencing

    [cleansig, goodchans] = caraslab_CAR(cleansig, ops);
    ops.igood = goodchans;
    fprintf('Done in %3.0fs!\n', toc);

%     %Filter the raw data
%     fprintf('Bandpass filtering raw data...\n');
%     rawsig = filter(b1, a1, rawsig);
%     rawsig = flipud(rawsig);
%     rawsig = filter(b1, a1, rawsig);
%     rawsig = flipud(rawsig);   
%     fprintf('done.\n')
%     
    
    %Save -mat file with cleaned data
%     [path,name,~] = fileparts(ops.rawdata);
%     cleanfilename = [path filesep name '_CLEAN.mat'];
%     fprintf('\nSaving cleaned data: %s.....',[name,'_CLEAN.mat']);
%     save(cleanfilename, 'cleansig','-v7.3');
%     fprintf('done.\n');
    
%     %Save -mat file with filtered raw data
%     fltfilename = [path filesep name '_RAWFLT.mat'];
%     fprintf('\nSaving raw filtered data: %s.....',[name,'_RAWFLT.csv']);
%     save(fltfilename,rawsig,'-v7.3');
%     fprintf('done.\n');
    
    
    %Update ops structure
    ops.cleandata = cleanfilename;   
%     ops.rawfltdata = fltfilename;
%     ops.badchannels = badchans;
    ops.readyforsorting = cleanfilename;
    save(fullfile(currpath, 'config.mat'),'ops')
    fprintf('Updated ops struct in config file: %s\n', currpath)

%--------------------------------------------------------------------------    
% NOT CURRENTLY IN USE, BUT COULD BE IMPLEMENTED AT A LATER DATE
%--------------------------------------------------------------------------   
%Option to create a tall array from csv data
%
%     %Create datastore from -csv data
%     fprintf('================\nProcessing %s \n', foldernames{i});
%     fprintf('Creating datastore.......');
%     ds = datastore(ops.csvdata);
%     fprintf(' done.\n')
%     
%     %Create tall table from datastore
%     fprintf('Creating tall array.......');
%     talltable = tall(ds);
%     fprintf(' done.\n');
%     
%     %Convert tall table to a tall matrix- contains raw signal data
%     rawsig = table2array(talltable);
%
%     %Save csv file with cleaned data
%     [path,name,~] = fileparts(ops.csvdata);
%     csvfilename = [path filesep name '_CLEAN.csv'];
%     fprintf('\nSaving cleaned data: %s.....',[name,'_CLEAN.csv']);
%     dlmwrite(csvfilename,cleansig,'precision',7);
%     fprintf('done.\n');
%      
%     %Update ops structure with path to clean csv file
%     ops.csvdata = csvfilename;    
%     save(fullfile(currpath, 'Config.mat'),'ops')
%     fprintf('Updated ops struct in config file: %s\n', configfilename)
%--------------------------------------------------------------------------   

end



