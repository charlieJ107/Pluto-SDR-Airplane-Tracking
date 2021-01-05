%% AdsbRxBitParser 解调ADSB信号的顶层封装函数
function [pkt,packetCnt] = AdsbRxBitParser(packetSamples,...
  packetCnt, syncTimeVec,radioTime,adsbParam)



% 创建一个空的包
    pkt = repmat(AdsbPacket(adsbParam),adsbParam.MaxNumPacketsInFrame,1);

    for p=1:packetCnt
      % 将样本解调成数据比特
      xLong = adsbDemod(packetSamples(:,p), adsbParam);

      % 开始解析数据包
      pkt(p,1) = parseHeader(xLong, adsbParam);

      % CRC校验
      err = adsbCRC(xLong, pkt(p,1).DF, adsbParam);

      % 添加时间戳和CRC校验值(0：数据包正确，1：失败) 将数据包添加到数据包缓冲区并增加数据包数。
      pkt(p,1).Time = radioTime + double(syncTimeVec(p,1))/adsbParam.SampleRate;
      pkt(p,1).CRCError = err;
    end
end

%% %%%%%%%%%%%%%%% 重点来了！！！ %%%%%%%%%%%%%%%%


%% 解调ADSB信号的函数
function z = adsbDemod(y, adsbParam)

    %解调脉冲位置调制(PPM)调制信号Y，并以二进制值列向量形式返回结果Z。Y必须是数值列向量。adsbParam包含ADS-B接收器的配置信息
    samplePerSymbol = adsbParam.SamplesPerSymbol;
    samplePerChip = adsbParam.SamplesPerChip;

    bit1 = [ones(samplePerChip,1); -ones(samplePerChip,1)]; % 双极性

    numBits = size(y,1) / samplePerSymbol; % 

    yTemp = reshape(y, samplePerSymbol, numBits)';

    ySoft = yTemp*bit1; 
    z = uint8(ySoft > 0);
end


%% 解析包部首的函数
function packet = parseHeader(d, adsbParam)


    packet = AdsbPacket(adsbParam);

    packet.RawBits(:,1) = d;
    % 这里通过索引进行了隐式类型转换
    packet.DF(1) = sum(uint8([16;8;4;2;1]).*d(1:5,1),'native');  % 下行链路格式
    packet.CA(1) = sum(uint8([4;2;1]).*d(6:8,1),'native');       % 容量
end


%% CRC检验的函数
function err = adsbCRC(xLong, DF, adsbParam)

    persistent crcDet
    if isempty(crcDet)
      crcDet = comm.CRCDetector(...
        [1 1 1 1 1 1 1 1 1 1 1 1 1 0 1 0 0 0 0 0 0 1 0 0 1]);
    end

    %首先检查这是否是下行链路格式(DF)类型17，即ADS-B分组或类型11捕获压缩器。否则，丢弃该数据包。
    if DF == 11
      xShort = logical(xLong(1:adsbParam.ShortPacketNumBits));
      reset(crcDet);
      [~,err] = crcDet(xShort);
    elseif DF == 17
      reset(crcDet);
      [~,err] = crcDet(logical(xLong));
    else
      err = true;
    end
end