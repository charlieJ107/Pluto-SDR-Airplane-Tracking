function pkt = AdsbPacket(adsbParam)
%% AdsbPacket ADS-B physical layer packet structure
%   P = AdsbPacket returns ADS-B physical layer packet structure
%   with the following fields:
%
%   RawBits           : Raw message in bits
%   CRCError          : CRC checksum (1: error, 0: no error)
%   Time              : Packet reception time
%   DF                : Downlink format
%   CA                : Capability

pkt.RawBits = coder.nullcopy(zeros(112,1,'uint8'));   
% 如果你有其他的想要设置的长包的位数，就用下面这一行，默认就是112
%pkt.RawBits = coder.nullcopy(zeros(adsbParam.LongPacketNumBits,1,'uint8'));   
                                    % Raw message
pkt.CRCError = true;                % CRC 校验和 (1: 错误, 0: 正常)
pkt.Time = 0;                       % 包接收时间
pkt.DF = uint8(0);                  % 下行链路格式
pkt.CA = uint8(0);                  % 容量性能
end
