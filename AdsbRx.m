%% 正儿八经用来接收ADS-B信号的函数
function [packet,packetCount] = AdsbRx(y,radioTime,adsbParam)
% 解调接收信号中的窄带ADS-B分组, 返回两个东西
% packet是接收的数据包, 然后packetCount是数据包有多少个
% 接收的参数包括一个接收到的信号Y, radioTime是运行的当前时间(用来同步和校准)
% 外加一套参数(就是主函数里用到的ConfigParam)

    persistent packetSync

    if isempty(packetSync)
        packetSync = RxSync(adsbParam);
    end

    % 构造函数, 插值来获得信号分片的整数个采样

    z = AdsbRxInterpolator(y, adsbParam);
    
    % 转换成能量值
    zAbs = abs(z).^2;

    % 返回搜索到的packet的采样
    [packetSamples, packetCount, syncTime] = packetSync(zAbs);

    [packet,packetCount] = AdsbRxBitParser(packetSamples, packetCount, syncTime, ...
      radioTime, adsbParam);
    
  
end
