function caraslab_traceviewer(datadir)
%caraslab_traceviewer(datadir)
%
% This function loads raw (filtered) and cleaned (filtered, artifacts
% removed, common average referenced) data, and allows the user to compare
% the data. Each trace should be examined for abnormalities (unexplained
% dropouts, cells that die suddenly during a recording session, etc...).
% Abnormalities should be noted to aid in data interpretation during and 
% after spike sorting.
%
% Input variables:
%
%       datadir:    path to folder containing data directories. Each directory
%                   should contain a kilosort configuration (config.mat)
%                   file generated by caraslab_createconfig.m
%
%Written by ML Caras Mar 27 2019

%Initialize figure (full screen)
figure('units','normalized','outerposition',[0 0 1 1]);


%Get a list of all folders in the data directory
folders = caraslab_lsdir(datadir);
% foldernames = extractfield(folders,'name');
foldernames = {folders.name};

for i = 1:numel(foldernames)
    clear ops rawsig cleansig
    
    %Define the path to the current data
    currpath = fullfile(datadir,foldernames{i});
    
    %Load in configuration file ops struct
    load(fullfile(currpath, 'config.mat'),'ops');
    
    %Get sampling rate
    fs = ops.fs;
    
    %Get number of channels and identity of bad channels
    nchans = ops.NchanTOT;
    badchans = ops.badchannels;
    
%     %Load in raw filtered signal
%     [~,name,ext] = fileparts(ops.rawfltdata);
%     fprintf('Loading raw filtered signal %...', [name,ext])
%     load(ops.rawfltdata,'rawsig');
%     fprintf('done.\n')
    
    %Load in clean signal
    [~,name,ext] = fileparts(ops.cleandata);
    fprintf('Loading clean signal %...', [name,ext])
    load(ops.cleandata,'cleansig');   
    fprintf('done.\n')

numsamples = size(cleansig,1);



iend = 0;

while 1
    ibegin = iend+1;
    iend = ibegin+floor(30*fs)-1; %30 second snippet

    chanend = 0;
    if iend < numsamples
        
        chanbegin = chanend+1;
        chanend = chanbegin+floor(nchans/5)-1;
        
        %Examine multiple channels simultaneously
        for ch = chanbegin:chanend
            subplot(floor(nchans/5),1,ch)
            h = LinePlotReducer(cleansig(ibegin:iend,ch));
            set(gca,'xtick',[]);
            set(gca,'ytick',[]);
            pause
        end
    else
        if ch >numchans
            break
        end
    end
    
end


end