function [configParam, PlutoRx] = getConfigParam()
%% 获取配置好的结构体
% 这个函数将完成配置的全部工作, 直接返回配置好的结构体, 是配置部分程序的顶层封装
% 
    % 先检查Pluto在不在，如果没连上，直接报错
    preConfigParam.PlutoAddress = FindPluto();
    if isempty(preConfigParam.PlutoAddress)
        error(message('PlutoRadioNotFound'))
    end
    preConfigParam.preConfig = 1;
    preConfigParam.Duration = 10;
    preConfigParam.Duration = getInputParam(preConfigParam);
    % 每个码元的持续时间(其实就是采样间隔嘛)
    symbolDuration = 1e-6;
    % 单个码元的片数
    chipsPerSymbol = 2;
    % 如果是长包的持续时间
    longPacketDuration = 112e-6;
    % 如果是短包的持续时间
    shortPacketDuration = 56e-6;
    % 前同步码持续时间
    preambleDuration = 8e-6;
    % 前端基带采样率
    frontEndSampleRate = 12e6;
    % 实例化一个pluto接收对象
    PlutoRx = sdrrx('Pluto', ...
    'CenterFrequency',1090e6, ...
    'GainSource', 'Manual', ...
    'Gain', 60, ...
    'BasebandSampleRate', frontEndSampleRate,...
    'OutputDataType','single');

    %% 每个数据帧的采样数量的确定
    % 根据Nyquest采样定理, 采样率应该大于2倍的信号最高频率,这个最高频率就是chipRate
    chipRate = chipsPerSymbol / symbolDuration;
    % 检验是否满足采样定理
    [n, d]=rat(frontEndSampleRate/chipRate);
    if d > 2
        %内插率
        interpRate = d;
    else
        if n <= 1
            interpRate = 2*d;
        else
            interpRate = d;
        end
    end
    preConfigParam.InterpolationFactor = interpRate;
    sampleRate = frontEndSampleRate * interpRate;
    samplesPerSymbol = int32(sampleRate * symbolDuration);
    samplePerChip = samplesPerSymbol / chipsPerSymbol;
    maxPacketLength = ...
        int32((preambleDuration + longPacketDuration) ...
        * sampleRate);
    maxNumLongPacketsInFrame = 180;
    samplesPerFrame = maxNumLongPacketsInFrame * maxPacketLength;
    preConfigParam.MaxPacketLength = maxPacketLength;
    preConfigParam.SampleRate = sampleRate;
    preConfigParam.SamplesPerSymbol = samplesPerSymbol;
    preConfigParam.SamplesPerChip = samplePerChip;
    preConfigParam.SamplesPerFrame = samplesPerFrame;
    % 顺便把Pluto的参数也设定一下
    PlutoRx.SamplesPerFrame = samplesPerFrame;
       
    %% 数据包数量的估计
    % 根据ADS-B协议,极限情况下,也就是数据包之间没有任何空间,所有的数据包都紧密连接的话,
    % 数据包的最大数量就是每帧的采样数/单个数据包的最大长度
    % 所以系统设计成可以容纳这个数量的4倍,这样可以确保在极限情况下我们也能良好地采样,不会造成失真
    preConfigParam.MaxNumPacketsInFrame = floor(samplesPerFrame / maxPacketLength / 4);
    % 至此,我们可以得到每一帧应该有的长度
    preConfigParam.FrameDuration = samplesPerFrame / frontEndSampleRate;
    
    % 把这个时间长度转换成采样数, 说白了就是采样间隔和采样频率的转换
    preConfigParam.LongPacketLength = int32(longPacketDuration * sampleRate);
    preConfigParam.PreambleLength = int32(preambleDuration * sampleRate);
    
    % 同样地,把时间长度转换成比特数
    preConfigParam.LongPacketNumBits = int32(longPacketDuration / symbolDuration);
    preConfigParam.ShortPacketNumBits = int32(shortPacketDuration / symbolDuration);
    
    %% 内插滤波系数
    % 设置一个升余弦FIR脉冲整形滤波器, 获取在进行抽样内插的时候使用的内插滤波系数
    
    b_filter = rcosdesign(0.5, 3, double(samplePerChip));
    
    preConfigParam.InterpolationFilterCoefficients = single(b_filter);
    
    %% 同步相关的设置
    
    % 同步序列
    syncSequence = [1 0 1 0 0 0 0 1 0 1 0 0 0 0 0 0];
    syncSequenceHighIndices = find(syncSequence);
    syncSequenceLowIndices = find(~syncSequence);
    preConfigParam.SyncSequence = syncSequence;
    preConfigParam.SyncSequenceLength = length(syncSequence);
    preConfigParam.SyncSequenceHighIndices = syncSequenceHighIndices;
    preConfigParam.SyncSequenceNumHighValues = length(syncSequenceHighIndices);
    preConfigParam.SyncSequenceLowIndices  = syncSequenceLowIndices;
    preConfigParam.SyncSequenceNumLowValues = length(syncSequenceLowIndices);
    syncSignal = reshape(ones(samplesPerSymbol / 2, 1) * syncSequence, 16 * samplesPerSymbol / 2, 1);
    preConfigParam.SyncDownSampleFactor = 2;
    preConfigParam.SyncFilter = single(flipud(2 * syncSignal(1 : 2 : end) - 1));
    
    configParam = preConfigParam;
end
    
    
    
    
    
    
    