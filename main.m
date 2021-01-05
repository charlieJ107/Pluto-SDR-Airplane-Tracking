%% 基于ADS-B 信号的接收与解调进行航班追踪的MATLAB实现
% Author: Charlie J
% Date: 2020-12
% Reference: 
%   * [Airplane Tracking Using ADS-B Signals](https://ww2.mathworks.cn/help/supportpkg/plutoradio/ug/airplane-tracking-using-ads-b-signals.html)
%   * [Communications Toolbox](https://ww2.mathworks.cn/help/comm/index.html)
%   * [Communications Toolbox Support Package for Analog Devices ADALM-Pluto Radio](https://ww2.mathworks.cn/help/supportpkg/plutoradio/index.html)
% File: Main.m
% Usage: 程序主函数

%% 用户输入和设置参数
[ConfigParam, PlutoRx] = getConfigParam();

%% GUI相关的东西,如果有能耐就做
% 没能耐就...看别人做
viewer = helperAdsbViewer();
startDataLog(viewer);
startMapUpdate(viewer);

%% 创建一个解码器
% 因为这个全是ADS-B协议的内容, 时间紧迫, 所以我就先用
% 毕竟这已经不属于数字信号处理和通信原理的内容了, 反而属于计算机网络(协议)的内容
msgParser = helperAdsbRxMsgParser(ConfigParam);

%% 启动GUI
start(viewer)

%% 主程序循环

% 初始化运行时间计时器
radioTime = 0;
while radioTime < ConfigParam.Duration
    
    [rcv, ~, lostFlag] = PlutoRx();
    
    [packet, packetCount] = AdsbRx(rcv, radioTime, ConfigParam);
    
    [msg, msgCnt] = msgParser(packet, packetCount);
    
    update(viewer, msg, msgCnt, lostFlag);
    
    radioTime = radioTime + ConfigParam.FrameDuration;
end
stop(viewer)
release(PlutoRx)
    
