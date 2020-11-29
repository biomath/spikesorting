function caraslab_batch_gpufilter(cur_savedir, optional_ops)
    %caraslab_kilosort(datadir,sel)
    %
    %This function applies a chunkwise gpufilter (Kilosort implementation)
    % It's done before kilosort so we can correctly output a filtered file
    % to be visualized in phy
    %
    %Input variables:
    %
    %       datadir: path to folder containing data directories. Each directory
    %                should contain a binary (-dat) data file and
    %                a kilosort configuration (config.mat) file. Both of
    %                these files are generated by caraslab_createconfig.m
    %
    %       sel:    if 0 or omitted, program will cycle through all folders
    %               in the data directory.    
    %
    %               if 1, program will prompt user to select folder
    %
    %Written by MML 08/24/20

    %Load in configuration file (contains ops struct)
    % Catch error if -mat file is not found
    try
        if nargin < 2
            load(fullfile(cur_savedir, 'config.mat'));
            fprintf('Filtering raw file: %s.......\n', ops.fbinary)
        else
            ops = optional_ops;
        end
    catch ME
        if strcmp(ME.identifier, 'MATLAB:load:couldNotReadFile')
            fprintf('\n-mat file not found\n')
            return
        else
            fprintf(ME.identifier)
            fprintf(ME.message)
            return
        end
    end

    % Load config paramaters
    [chanMap, xc, yc, kcoords, NchanTOTdefault] = loadChanMap(ops.chanMap); % function to load channel map file
    ops.NchanTOT = getOr(ops, 'NchanTOT', NchanTOTdefault); % if NchanTOT was left empty, then overwrite with the default
    
    NchanTOT = ops.NchanTOT; % total number of channels in the raw binary file, including dead, auxiliary etc
    
    if isfield(ops, 'igood')
        igood = ops.igood;  % Good channels
    else
        igood = true(1:NchanTOT);
    end
    
    if isfield(ops, 'badchannels')
        igood(ops.badchannels) = false;
    end
    
    NT       = ops.NT ; % number of timepoints per batch

    bytes       = get_file_size(ops.fbinary); % size in bytes of raw binary
    nTimepoints = floor(bytes/NchanTOT/2); % number of total timepoints
    ops.tstart  = 0; % starting timepoint for processing data segment
    ops.tend    = min(nTimepoints, ceil(ops.trange(2) * ops.fs)); % ending timepoint
    ops.sampsToRead = ops.tend-ops.tstart; % total number of samples to read
    ops.twind = ops.tstart * NchanTOT*2; % skip this many bytes at the start

    Nbatch      = ceil(ops.sampsToRead /(NT-ops.ntbuff)); % number of data batches
    ops.Nbatch = Nbatch;
    NTbuff      = NT + 4*ops.ntbuff; % we need buffers on both sides for filtering

    % set up the parameters of the filter
    if isfield(ops,'fslow')&&ops.fslow<ops.fs/2
        [b1, a1] = butter(3, [ops.fshigh/ops.fs,ops.fslow/ops.fs]*2, 'bandpass'); % butterworth filter with only 3 nodes (otherwise it's unstable for float32)
    else
        [b1, a1] = butter(3, ops.fshigh/ops.fs*2, 'high'); % the default is to only do high-pass filtering at 150Hz
    end

    if getOr(ops, 'comb', 0)  % MML edit; comb filter
        N  = 407;    % Order
        BW = 2;    % Bandwidth
        Fs = ops.fs;  % Sampling Frequency
        h = fdesign.comb('Notch', 'N,BW', N, BW, Fs);
        comb_filter = design(h, 'butter');
        comb_b1= comb_filter.Numerator;
        comb_a1= comb_filter.Denominator;
    end

    %Start timer
    tic;
    fprintf('Reading raw file and applying filters... ')
    fidC        = fopen(ops.fclean,  'w'); % MML edit; write processed data for phy
    fid         = fopen(ops.fbinary, 'r'); % open for reading raw data
    for ibatch = 1:Nbatch
        % we'll create a binary file of batches of NT samples, which overlap consecutively on ops.ntbuff samples
        % in addition to that, we'll read another ops.ntbuff samples from before and after, to have as buffers for filtering
        offset = max(0, ops.twind + 2*NchanTOT*(NT*(ibatch-1) - 2*ops.ntbuff)); % number of samples to start reading at.
        if offset==0
            ioffset = 0; % The very first batch has no pre-buffer, and has to be treated separately
        else
            ioffset = 2*ops.ntbuff;
        end
        fseek(fid, offset, 'bof'); % fseek to batch start in raw file

        buff = fread(fid, [NchanTOT NTbuff], 'int16'); % read and reshape. Assumes int16 data (which should perhaps change to an option)

        if isempty(buff)
            break; % this shouldn't really happen, unless we counted data batches wrong
        end

        nsampcurr = size(buff,2); % how many time samples the current batch has

        if nsampcurr<NTbuff
            buff(:, nsampcurr+1:NTbuff) = repmat(buff(:,nsampcurr), 1, NTbuff-nsampcurr); % pad with zeros, if this is the last batch
        end

        % Finally start filtering...
        % Can't use GPU acceleration for comb filter yet...
        if getOr(ops, 'comb', 0)  % MML edit; comb filter
            buff = buff';  % MML edit: transpose sooner
            buff = filter(comb_b1, comb_a1, buff);
            dataRAW = gpuArray(buff); % move int16 data to GPU
        else
            dataRAW = gpuArray(buff); % move int16 data to GPU
            dataRAW = dataRAW';
        end

        dataRAW = single(dataRAW); % convert to float32 so GPU operations are fast
        % subtract the mean from each channel
        dataRAW = dataRAW - mean(dataRAW, 1); % subtract mean of each channel

        % CAR, common average referencing by median
        if getOr(ops, 'CAR', 1)
            % MML edit:take median of good channels only
            dataRAW = dataRAW - median(dataRAW(:, chanMap(igood)), 2); % subtract median across channels
        end

        datr = filter(b1, a1, dataRAW); % causal forward filter

        datr = flipud(datr); % reverse time
        datr = filter(b1, a1, datr); % causal forward filter again
        datr = flipud(datr); % reverse time back

    %     datr    = gpufilter(buff, ops, ops.chanMap(ops.igood), 1); % apply filters and median subtraction
        % FOR DEBUG
    %     datr = dataRAW;

        datr    = datr(ioffset + (1:NT),:); % remove timepoints used as buffers

        % DEBUG
    %     a = datr(end-100:end, 1);    
    % %     b = datr(1:101, 1);
    %     figure
    %     hold on
    %     plot([a_pre b_pre])
    %     plot([a; b])
    %     
        datr = datr';

        datr  = gather(int16(datr)); % convert to int16, and gather on the CPU side
        fwrite(fidC, datr, 'int16'); % write this batch to clean file
    end
    fclose(fid); % close the files
    fclose(fidC);

    tEnd = toc;
    fprintf('Done in: %d minutes and %f seconds\n', floor(tEnd/60), rem(tEnd,60));
end
