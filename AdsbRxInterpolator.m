function z = AdsbRxInterpolator(y, adsbParam)
%% helperAdsbRxPhyInterpolator ADS-B 接收机插值函数
%   Z = helperAdsbRxPhyInterpolator(Y,ADSB) 对接收到的信号进行插值达到 SamplesPerChip. A

coder.inline('never')

persistent interpFil

if isempty(interpFil)
  % 滤波器的构造
  interpFil = dsp.FIRInterpolator(adsbParam.InterpolationFactor, ...
    adsbParam.InterpolationFilterCoefficients);
end

%% 根据内插因子对信号进行内插.
% 举个例子, 当Y的采样频率为2.4MHz, 而ADS-B信号的频率是2MHz的脉冲,我们就需要上采样到2MHz的整数倍
% 当这个内插系数(也就是InterpolationFactor)为5时, 我们就可以得到一个12MHz的信号,这样就额可以轻松解调了

if adsbParam.InterpolationFactor > 1

  z = interpFil(y);
else
  z = y;
end

